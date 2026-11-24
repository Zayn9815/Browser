import Foundation
import SDMCore
import VaultManager

public enum DownloadAdapterError: LocalizedError, Sendable {
    case invalidDownloadURL(String)
    case insufficientDiskSpace(availableBytes: Int64, requiredBytes: Int64)

    public var errorDescription: String? {
        switch self {
        case .invalidDownloadURL(let raw):
            return "Unsupported download URL: \(raw)"
        case .insufficientDiskSpace(let available, let required):
            let fmt = ByteCountFormatter()
            return "Not enough storage on iPhone (\(fmt.string(fromByteCount: available)) free; need at least \(fmt.string(fromByteCount: required)))."
        }
    }
}

/// Bridges browser session state (`BrowserSessionContext`) into both:
/// 1. Patched `SDMCore.DownloadRequestContext` (RFC 6265-validated cookies, User-Agent, full Referer, Origin)
/// 2. CRLF-formatted `AVDictionary` `"headers"` string for `FFmpegHLSMuxerWorker`.
public struct BrowserSessionHeaderAdapter: Sendable {
    private static let maxCookieCount = 512
    private static let maxCookieValueUTF8Bytes = 16_384
    private static let maxUserAgentUTF8Bytes = 2_048
    private static let maxOriginUTF8Bytes = 1_024
    public static let defaultMinimumFreeDiskBytes: Int64 = 100 * 1024 * 1024

    public init() {}

    /// Filters and sanitizes cookies according to RFC 6265 and SDMCore's strict validator invariants.
    public func filterValidCookies(
        _ cookies: [BrowserCookieSnapshot],
        for targetURL: URL,
        now: Date = .now
    ) -> [DownloadCookie] {
        var filtered: [DownloadCookie] = []
        filtered.reserveCapacity(min(cookies.count, Self.maxCookieCount))

        for cookie in cookies {
            guard filtered.count < Self.maxCookieCount else { break }
            guard cookie.matches(url: targetURL, now: now) else { continue }
            guard isSafeHeaderScalarString(cookie.name),
                  !cookie.name.isEmpty,
                  !cookie.name.contains(where: { "()<>@,;:\\\"/[]?={} ".contains($0) }),
                  isSafeHeaderScalarString(cookie.value),
                  !cookie.value.contains(";"),
                  cookie.value.utf8.count <= Self.maxCookieValueUTF8Bytes,
                  isSafeHeaderScalarString(cookie.domain),
                  !cookie.domain.isEmpty,
                  !cookie.domain.contains(where: { "/: ".contains($0) }),
                  isSafeHeaderScalarString(cookie.path),
                  cookie.path.hasPrefix("/") else {
                continue
            }

            let sanitizedExpiry: Double?
            if let exp = cookie.expiresAtUnix {
                guard exp.isFinite, exp > now.timeIntervalSince1970, exp < Double(Int64.max) else {
                    continue
                }
                sanitizedExpiry = exp
            } else {
                sanitizedExpiry = nil
            }

            filtered.append(
                DownloadCookie(
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path,
                    secure: cookie.isSecure,
                    hostOnly: cookie.isHostOnly,
                    expirationDate: sanitizedExpiry
                )
            )
        }

        return filtered
    }

    /// Builds an `SDMCore.DownloadRequestContext` guaranteed to pass `SDMCore` validation while forwarding
    /// full-path `Referer` and `Origin` headers for authenticated CDNs.
    public func makeSDMRequestContext(
        from session: BrowserSessionContext?,
        for targetURL: URL,
        now: Date = .now
    ) -> DownloadRequestContext? {
        guard let session else { return nil }

        let validCookies = filterValidCookies(session.cookies, for: targetURL, now: now)

        let sanitizedUA: String? = {
            guard let ua = session.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ua.isEmpty,
                  isSafeHeaderScalarString(ua),
                  ua.utf8.count <= Self.maxUserAgentUTF8Bytes else {
                return nil
            }
            return ua
        }()

        let sanitizedReferer: URL? = {
            guard let ref = session.pageReferer,
                  let refScheme = ref.scheme?.lowercased(),
                  ["http", "https"].contains(refScheme),
                  ref.user == nil,
                  ref.password == nil,
                  isSafeHeaderScalarString(ref.absoluteString) else {
                return nil
            }
            // Enforce HTTPS -> HTTP downgrade safety
            if refScheme == "https" && targetURL.scheme?.lowercased() != "https" {
                return nil
            }
            return ref
        }()

        let sanitizedOrigin: String? = {
            guard let raw = session.origin?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  raw.utf8.count <= Self.maxOriginUTF8Bytes,
                  isSafeHeaderScalarString(raw) else {
                return nil
            }
            let lower = raw.lowercased()
            guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
                return nil
            }
            if lower.hasPrefix("https://") && targetURL.scheme?.lowercased() != "https" {
                return nil
            }
            return raw
        }()

        if validCookies.isEmpty && sanitizedUA == nil && sanitizedReferer == nil && sanitizedOrigin == nil {
            return nil
        }

        return DownloadRequestContext(
            cookies: validCookies,
            userAgent: sanitizedUA,
            referrer: sanitizedReferer,
            referrerPolicy: .fullURL,
            origin: sanitizedOrigin
        )
    }

    /// Produces a CRLF-terminated HTTP header block suitable for FFmpeg's `av_dict_set(&opts, "headers", ...)`.
    public func makeFFmpegCRLFHeaders(
        from session: BrowserSessionContext?,
        for targetURL: URL,
        now: Date = .now
    ) -> String {
        guard let session else { return "" }
        var lines: [String] = []

        if let ua = session.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ua.isEmpty,
           isSafeHeaderScalarString(ua) {
            lines.append("User-Agent: \(ua)")
        }

        if let ref = session.pageReferer,
           let refScheme = ref.scheme?.lowercased(),
           ["http", "https"].contains(refScheme),
           !(refScheme == "https" && targetURL.scheme?.lowercased() != "https"),
           isSafeHeaderScalarString(ref.absoluteString) {
            var comps = URLComponents(url: ref, resolvingAgainstBaseURL: false)
            comps?.fragment = nil
            if let cleanRef = comps?.url?.absoluteString {
                lines.append("Referer: \(cleanRef)")
            }
        }

        if let origin = session.origin?.trimmingCharacters(in: .whitespacesAndNewlines),
           !origin.isEmpty,
           isSafeHeaderScalarString(origin),
           (origin.lowercased().hasPrefix("http://") || origin.lowercased().hasPrefix("https://")),
           !(origin.lowercased().hasPrefix("https://") && targetURL.scheme?.lowercased() != "https") {
            lines.append("Origin: \(origin)")
        }

        let validCookies = filterValidCookies(session.cookies, for: targetURL, now: now)
        if !validCookies.isEmpty {
            let cookieHeader = validCookies
                .sorted { $0.path.count > $1.path.count }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            if !cookieHeader.isEmpty {
                lines.append("Cookie: \(cookieHeader)")
            }
        }

        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Pre-flight disk-space verification against the Vault volume before starting a transfer.
    public func verifyDiskSpace(
        using vault: any VaultManaging,
        expectedBytes: Int64 = 0,
        minimumHeadroomBytes: Int64 = defaultMinimumFreeDiskBytes
    ) throws {
        let available = try vault.availableDiskBytes()
        let required = max(0, expectedBytes) + minimumHeadroomBytes
        if available < required {
            throw DownloadAdapterError.insufficientDiskSpace(availableBytes: available, requiredBytes: required)
        }
    }

    private func isSafeHeaderScalarString(_ value: String) -> Bool {
        !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}
