import Foundation

public struct CapturedManifestEntry: Sendable, Equatable {
    public let url: URL
    public let containerHint: InterceptedContainerHint
    public let frameOrigin: String
    public let capturedAt: Date

    public init(
        url: URL,
        containerHint: InterceptedContainerHint,
        frameOrigin: String,
        capturedAt: Date = .now
    ) {
        self.url = url
        self.containerHint = containerHint
        self.frameOrigin = frameOrigin
        self.capturedAt = capturedAt
    }
}

/// Correlates MSE `blob:` `<video>` elements to the most recent `.m3u8` / `.mpd` manifest captured
/// from the same `frameOrigin` within a 15-second sliding window while suppressing DRM-protected frames.
public struct BlobStreamCorrelator: Sendable {
    public let slidingWindowSeconds: TimeInterval

    private var manifestsByOrigin: [String: [CapturedManifestEntry]] = [:]
    private var drmProtectedOrigins: Set<String> = []

    public init(slidingWindowSeconds: TimeInterval = 15.0) {
        self.slidingWindowSeconds = slidingWindowSeconds
    }

    public mutating func markFrameOriginDRMProtected(_ frameOrigin: String) {
        let key = normalizeOrigin(frameOrigin)
        guard !key.isEmpty else { return }
        drmProtectedOrigins.insert(key)
        manifestsByOrigin.removeValue(forKey: key)
    }

    public func isOriginDRMProtected(_ frameOrigin: String) -> Bool {
        drmProtectedOrigins.contains(normalizeOrigin(frameOrigin))
    }

    public mutating func recordManifest(
        url: URL,
        containerHint: InterceptedContainerHint,
        frameOrigin: String,
        at timestamp: Date = .now
    ) {
        guard containerHint == .m3u8 || containerHint == .mpd else { return }
        let key = normalizeOrigin(frameOrigin)
        guard !key.isEmpty, !drmProtectedOrigins.contains(key) else { return }

        pruneExpired(forOriginKey: key, now: timestamp)
        var list = manifestsByOrigin[key] ?? []
        list.removeAll { $0.url == url }
        list.append(CapturedManifestEntry(url: url, containerHint: containerHint, frameOrigin: key, capturedAt: timestamp))
        if list.count > 24 {
            list.removeFirst(list.count - 24)
        }
        manifestsByOrigin[key] = list
    }

    public mutating func correlateBlob(
        frameOrigin: String,
        recentNetworkManifests: [String],
        hasMediaKeys: Bool,
        now: Date = .now
    ) -> CapturedManifestEntry? {
        let key = normalizeOrigin(frameOrigin)
        if hasMediaKeys || drmProtectedOrigins.contains(key) {
            if !key.isEmpty {
                drmProtectedOrigins.insert(key)
                manifestsByOrigin.removeValue(forKey: key)
            }
            return nil
        }

        // First prefer any validated recent network manifest reported directly from the frame
        for raw in recentNetworkManifests.reversed() {
            guard let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }
            let lower = raw.lowercased()
            let hint: InterceptedContainerHint
            if lower.contains(".m3u8") {
                hint = .m3u8
            } else if lower.contains(".mpd") {
                hint = .mpd
            } else {
                continue
            }
            return CapturedManifestEntry(url: url, containerHint: hint, frameOrigin: key, capturedAt: now)
        }

        // Fallback to recorded manifests inside the 15-second sliding window for this frameOrigin
        pruneExpired(forOriginKey: key, now: now)
        return manifestsByOrigin[key]?.last
    }

    public mutating func reset() {
        manifestsByOrigin.removeAll()
        drmProtectedOrigins.removeAll()
    }

    private mutating func pruneExpired(forOriginKey key: String, now: Date) {
        guard var list = manifestsByOrigin[key] else { return }
        list.removeAll { now.timeIntervalSince($0.capturedAt) > slidingWindowSeconds }
        if list.isEmpty {
            manifestsByOrigin.removeValue(forKey: key)
        } else {
            manifestsByOrigin[key] = list
        }
    }

    private func normalizeOrigin(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
