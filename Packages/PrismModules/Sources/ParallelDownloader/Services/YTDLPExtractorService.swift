import Foundation
import PrismCore
import YTDLP

public enum YTDLPExtractorError: LocalizedError, Sendable {
    case extractionFailed(String)
    case invalidJSONResponse
    case noPlayableFormats

    public var errorDescription: String? {
        switch self {
        case .extractionFailed(let detail):
            return detail.isEmpty ? "yt-dlp could not extract media from this link." : detail
        case .invalidJSONResponse:
            return "yt-dlp returned an unreadable metadata payload."
        case .noPlayableFormats:
            return "No downloadable video or audio formats were found for this link."
        }
    }
}

/// Strictly lazy on-device `yt-dlp` metadata extractor running off the main thread.
/// Never starts Python at app launch; only initializes `YTDLP.shared` on the first user-initiated request.
public final class YTDLPExtractorService: Sendable {
    public static let shared = YTDLPExtractorService()

    private let workerQueue = DispatchQueue(
        label: "com.prismdm.ytdlp.extractor",
        qos: .userInitiated,
        attributes: .concurrent
    )

    public init() {}

    /// Reads the bundled `yt-dlp` version from `ytdlp-apple_YTDLP.bundle/python-packages/VERSIONS`
    /// without starting the embedded Python interpreter.
    public static func bundledVersionSummary() -> String {
        let bundleName = "ytdlp-apple_YTDLP.bundle"
        var candidates: [URL] = []
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let base {
                candidates.append(base.appendingPathComponent(bundleName))
            }
        }
        candidates.append(contentsOf: Bundle.allBundles.map(\.bundleURL).filter { $0.lastPathComponent == bundleName })

        for bundleURL in candidates {
            let versionsURL = bundleURL.appendingPathComponent("python-packages/VERSIONS")
            if let text = try? String(contentsOf: versionsURL, encoding: .utf8) {
                for line in text.split(whereSeparator: \.isNewline) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.lowercased().hasPrefix("yt-dlp") || trimmed.lowercased().hasPrefix("yt_dlp") {
                        return trimmed
                    }
                }
            }
        }
        return "yt-dlp (bundled via ytdlp-apple)"
    }

    public func extractMediaInfo(
        url: URL,
        sessionContext: BrowserSessionContext? = nil
    ) async throws -> YTDLPMediaInfo {
        let isPrivate = sessionContext?.isIncognito ?? false
        PrismLogCenter.record(
            .info,
            category: .downloader,
            "yt-dlp extracting formats for \(url.host ?? "media")",
            isPrivateContext: isPrivate
        )

        return try await withCheckedThrowingContinuation { continuation in
            workerQueue.async {
                let tempCookieURL = Self.writeEphemeralNetscapeCookies(from: sessionContext)
                defer {
                    if let tempCookieURL {
                        try? FileManager.default.removeItem(at: tempCookieURL)
                    }
                }

                var args: [String] = [
                    "-J",
                    "--no-playlist",
                    "--no-warnings",
                    "--no-check-certificates",
                ]
                if let ua = sessionContext?.userAgent, !ua.isEmpty {
                    args.append(contentsOf: ["--user-agent", ua])
                }
                if let referer = sessionContext?.pageReferer?.absoluteString, !referer.isEmpty {
                    args.append(contentsOf: ["--referer", referer])
                }
                if let tempCookieURL {
                    args.append(contentsOf: ["--cookies", tempCookieURL.path])
                }
                args.append(url.absoluteString)

                do {
                    let output = try YTDLP.shared.run(args)
                    guard output.code == 0, !output.stdout.isEmpty else {
                        let errMsg = output.errorMessage ?? "yt-dlp exited with code \(output.code)"
                        PrismLogCenter.record(.error, category: .downloader, "yt-dlp extract failed: \(errMsg)", isPrivateContext: isPrivate)
                        continuation.resume(throwing: YTDLPExtractorError.extractionFailed(errMsg))
                        return
                    }
                    let info = try Self.parseMediaInfo(fromJSONData: Data(output.stdout.utf8), sourceURL: url)
                    continuation.resume(returning: info)
                } catch {
                    PrismLogCenter.record(.error, category: .downloader, "yt-dlp error: \(error.localizedDescription)", isPrivateContext: isPrivate)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Pure JSON parser (unit-testable without invoking Python).
    public static func parseMediaInfo(fromJSONData data: Data, sourceURL: URL) throws -> YTDLPMediaInfo {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTDLPExtractorError.invalidJSONResponse
        }

        let title = (root["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? (sourceURL.host ?? "Video")
        let uploader = (root["uploader"] as? String)
            ?? (root["channel"] as? String)
            ?? (sourceURL.host ?? "")
        let duration = (root["duration"] as? Double) ?? (root["duration"] as? Int).map(Double.init)
        let thumbURL = (root["thumbnail"] as? String).flatMap(URL.init(string:))
        let extractor = (root["extractor_key"] as? String) ?? (root["extractor"] as? String) ?? "yt-dlp"

        let rawFormats = (root["formats"] as? [[String: Any]]) ?? []
        let parsedFormats = buildFormatOptions(from: rawFormats, rootFallback: root, durationSeconds: duration)

        guard !parsedFormats.isEmpty else {
            throw YTDLPExtractorError.noPlayableFormats
        }

        return YTDLPMediaInfo(
            sourceURL: sourceURL,
            title: title,
            uploader: uploader,
            durationSeconds: duration,
            thumbnailURL: thumbURL,
            extractorName: extractor,
            formats: parsedFormats
        )
    }

    // MARK: - Format Deduplication & Adaptive Pairing

    private struct RawFormat {
        let formatID: String
        let url: URL
        let ext: String
        let vcodec: String
        let acodec: String
        let height: Int?
        let fps: Double?
        let tbrKbps: Double?
        let abrKbps: Double?
        let filesize: UInt64?
        let httpHeaders: [String: String]
        let isHLS: Bool

        var hasVideo: Bool { vcodec != "none" && !vcodec.isEmpty }
        var hasAudio: Bool { acodec != "none" && !acodec.isEmpty }
        var isMuxed: Bool { hasVideo && hasAudio }
        var isMP4CompatibleVideo: Bool {
            ext == "mp4" || vcodec.hasPrefix("avc1") || vcodec.hasPrefix("hvc1") || vcodec.hasPrefix("hev1")
        }
        var isM4AAudio: Bool {
            ext == "m4a" || acodec.hasPrefix("mp4a")
        }

        func estimatedBytes(durationSeconds: Double?) -> UInt64? {
            if let filesize, filesize > 0 { return filesize }
            if let durationSeconds, durationSeconds > 0, let kbps = (tbrKbps ?? abrKbps), kbps > 0 {
                return UInt64(((kbps * 1000.0) / 8.0) * durationSeconds)
            }
            return nil
        }
    }

    private static func buildFormatOptions(
        from dicts: [[String: Any]],
        rootFallback: [String: Any],
        durationSeconds: Double?
    ) -> [YTDLPFormatOption] {
        var raws: [RawFormat] = []

        for d in dicts {
            guard let id = d["format_id"] as? String,
                  let urlStr = d["url"] as? String,
                  let url = URL(string: urlStr) else {
                continue
            }
            let proto = (d["protocol"] as? String ?? "").lowercased()
            if proto.contains("mhtml") || proto.contains("storyboard") { continue }
            let ext = (d["ext"] as? String ?? "mp4").lowercased()
            if ext == "mhtml" { continue }

            let vcodec = (d["vcodec"] as? String ?? "none").lowercased()
            let acodec = (d["acodec"] as? String ?? "none").lowercased()
            let height = (d["height"] as? Int) ?? (d["height"] as? Double).map(Int.init)
            let fps = (d["fps"] as? Double) ?? (d["fps"] as? Int).map(Double.init)
            let tbr = (d["tbr"] as? Double) ?? (d["vbr"] as? Double)
            let abr = d["abr"] as? Double
            let size = (d["filesize"] as? UInt64)
                ?? (d["filesize"] as? Int).flatMap { $0 > 0 ? UInt64($0) : nil }
                ?? (d["filesize_approx"] as? UInt64)
                ?? (d["filesize_approx"] as? Int).flatMap { $0 > 0 ? UInt64($0) : nil }
            let headers = (d["http_headers"] as? [String: String]) ?? [:]
            let isHLS = proto.contains("m3u8") || urlStr.lowercased().contains(".m3u8")

            raws.append(RawFormat(
                formatID: id,
                url: url,
                ext: ext,
                vcodec: vcodec,
                acodec: acodec,
                height: height,
                fps: fps,
                tbrKbps: tbr,
                abrKbps: abr,
                filesize: size,
                httpHeaders: headers,
                isHLS: isHLS
            ))
        }

        // Handle single-URL extractors where root itself contains url/ext
        if raws.isEmpty,
           let directStr = rootFallback["url"] as? String,
           let directURL = URL(string: directStr) {
            let ext = (rootFallback["ext"] as? String ?? "mp4").lowercased()
            let headers = (rootFallback["http_headers"] as? [String: String]) ?? [:]
            let size = (rootFallback["filesize"] as? Int).flatMap { $0 > 0 ? UInt64($0) : nil }
            return [
                YTDLPFormatOption(
                    id: "direct-best",
                    label: "Best Available (\(ext.uppercased()))",
                    detail: "Direct stream",
                    containerExt: ext,
                    resolutionHeight: rootFallback["height"] as? Int,
                    isAudioOnly: false,
                    estimatedBytes: size,
                    formatSelector: "best",
                    videoURL: directURL,
                    audioURL: nil,
                    httpHeaders: headers,
                    isHLS: directStr.lowercased().contains(".m3u8")
                ),
            ]
        }

        // Best audio-only stream (prefer M4A/AAC for instant -c copy MP4 muxing)
        let audioCandidates = raws.filter { !$0.hasVideo && $0.hasAudio && !$0.isHLS }
        let bestM4AAudio = audioCandidates
            .filter(\.isM4AAudio)
            .max(by: { ($0.abrKbps ?? $0.tbrKbps ?? 0) < ($1.abrKbps ?? $1.tbrKbps ?? 0) })
            ?? audioCandidates.max(by: { ($0.abrKbps ?? $0.tbrKbps ?? 0) < ($1.abrKbps ?? $1.tbrKbps ?? 0) })

        let bestAudioBytes = bestM4AAudio?.estimatedBytes(durationSeconds: durationSeconds) ?? 0

        // Group video formats by standard height tiers
        let videoCandidates = raws.filter { $0.hasVideo && ($0.height ?? 0) > 0 }
        let distinctHeights = Array(Set(videoCandidates.compactMap(\.height))).sorted(by: >)
        var options: [YTDLPFormatOption] = []

        for height in distinctHeights {
            let atHeight = videoCandidates.filter { $0.height == height }
            // Prefer non-HLS MP4-compatible video (muxed first, or video-only paired with bestM4AAudio)
            let bestVideo = atHeight.sorted { lhs, rhs in
                let lScore = (lhs.isHLS ? 0 : 100) + (lhs.isMP4CompatibleVideo ? 40 : 0) + (lhs.isMuxed ? 20 : 0)
                let rScore = (rhs.isHLS ? 0 : 100) + (rhs.isMP4CompatibleVideo ? 40 : 0) + (rhs.isMuxed ? 20 : 0)
                if lScore != rScore { return lScore > rScore }
                return (lhs.tbrKbps ?? 0) > (rhs.tbrKbps ?? 0)
            }.first

            guard let v = bestVideo else { continue }
            let vBytes = v.estimatedBytes(durationSeconds: durationSeconds)
            let pairAudio = v.isMuxed ? nil : bestM4AAudio
            let totalBytes: UInt64? = {
                if let vBytes {
                    return vBytes + (pairAudio != nil ? bestAudioBytes : 0)
                }
                return nil
            }()

            let fpsTag = (v.fps ?? 0) >= 50 ? " \(Int((v.fps ?? 60).rounded()))fps" : ""
            let tierName: String
            switch height {
            case 2160...: tierName = "2160p 4K\(fpsTag)"
            case 1440..<2160: tierName = "1440p QHD\(fpsTag)"
            case 1080..<1440: tierName = "1080p Full HD\(fpsTag)"
            case 720..<1080: tierName = "720p HD\(fpsTag)"
            default: tierName = "\(height)p\(fpsTag)"
            }

            let selector: String
            if let pairAudio {
                selector = "\(v.formatID)+\(pairAudio.formatID)/best[height<=\(height)][ext=mp4]/best"
            } else {
                selector = "\(v.formatID)/best[height<=\(height)]/best"
            }

            let detail = pairAudio != nil
                ? "MP4 • Parallel + Local FFmpeg Mux"
                : (v.isHLS ? "HLS Stream • \(v.ext.uppercased())" : "MP4 • Direct Stream")

            options.append(YTDLPFormatOption(
                id: "video-\(height)-\(v.formatID)",
                label: tierName,
                detail: detail,
                containerExt: "mp4",
                resolutionHeight: height,
                isAudioOnly: false,
                estimatedBytes: totalBytes,
                formatSelector: selector,
                videoURL: v.url,
                audioURL: pairAudio?.url,
                httpHeaders: v.httpHeaders,
                isHLS: v.isHLS
            ))
        }

        // Add Audio Only (M4A) option
        if let audio = bestM4AAudio {
            let kbps = Int((audio.abrKbps ?? audio.tbrKbps ?? 128).rounded())
            options.append(YTDLPFormatOption(
                id: "audio-m4a-\(audio.formatID)",
                label: "Audio Only (M4A)",
                detail: "AAC ~\(kbps) kbps • Direct Audio",
                containerExt: audio.isM4AAudio ? "m4a" : audio.ext,
                resolutionHeight: nil,
                isAudioOnly: true,
                estimatedBytes: audio.estimatedBytes(durationSeconds: durationSeconds),
                formatSelector: "\(audio.formatID)/bestaudio[ext=m4a]/bestaudio",
                videoURL: nil,
                audioURL: audio.url,
                httpHeaders: audio.httpHeaders,
                isHLS: audio.isHLS
            ))
        }

        // Always keep a fallback "Best Available MP4" if nothing matched height tiers
        if options.isEmpty {
            options.append(YTDLPFormatOption(
                id: "fallback-best",
                label: "Best Available MP4",
                detail: "yt-dlp Direct Selection",
                containerExt: "mp4",
                resolutionHeight: nil,
                isAudioOnly: false,
                estimatedBytes: nil,
                formatSelector: "best[ext=mp4]/best",
                videoURL: nil,
                audioURL: nil,
                httpHeaders: [:],
                isHLS: false
            ))
        }

        return options
    }

    // MARK: - Ephemeral Netscape Cookie Export (Zero Disk Retention / Zero Logging)

    public static func writeEphemeralNetscapeCookies(from sessionContext: BrowserSessionContext?) -> URL? {
        guard let cookies = sessionContext?.cookies, !cookies.isEmpty else {
            return nil
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrismYTDLPCookies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(UUID().uuidString).txt")

        var lines: [String] = ["# Netscape HTTP Cookie File"]
        for cookie in cookies where !cookie.name.isEmpty && !cookie.domain.isEmpty {
            let includeSubdomains = cookie.isHostOnly ? "FALSE" : "TRUE"
            let domain = (!cookie.isHostOnly && !cookie.domain.hasPrefix(".")) ? ".\(cookie.domain)" : cookie.domain
            let path = cookie.path.isEmpty ? "/" : cookie.path
            let secure = cookie.isSecure ? "TRUE" : "FALSE"
            let expiry = Int(cookie.expiresAtUnix ?? 0)
            lines.append("\(domain)\t\(includeSubdomains)\t\(path)\t\(secure)\t\(expiry)\t\(cookie.name)\t\(cookie.value)")
        }
        guard lines.count > 1 else { return nil }
        let payload = lines.joined(separator: "\n") + "\n"
        do {
            try payload.write(to: fileURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return fileURL
        } catch {
            return nil
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
