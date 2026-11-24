import Foundation

public enum YTDLPQualityPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case askEveryTime
    case bestMP4
    case p1080
    case p720
    case audioM4A

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .askEveryTime: return "Ask Every Time"
        case .bestMP4: return "Best Available MP4"
        case .p1080: return "1080p Full HD"
        case .p720: return "720p HD"
        case .audioM4A: return "Audio Only (M4A)"
        }
    }
}

public struct YTDLPFormatOption: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let label: String
    public let detail: String
    public let containerExt: String
    public let resolutionHeight: Int?
    public let isAudioOnly: Bool
    public let estimatedBytes: UInt64?
    public let formatSelector: String
    public let videoURL: URL?
    public let audioURL: URL?
    public let httpHeaders: [String: String]
    public let isHLS: Bool

    public var requiresDualMux: Bool {
        videoURL != nil && audioURL != nil
    }

    public var supportsParallelFastPath: Bool {
        if isHLS { return false }
        if isAudioOnly { return audioURL != nil || videoURL != nil }
        return videoURL != nil
    }

    public var formattedSizeLabel: String {
        guard let estimatedBytes, estimatedBytes > 0 else { return "Size varies" }
        return ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file)
    }

    public init(
        id: String,
        label: String,
        detail: String,
        containerExt: String,
        resolutionHeight: Int?,
        isAudioOnly: Bool,
        estimatedBytes: UInt64?,
        formatSelector: String,
        videoURL: URL?,
        audioURL: URL?,
        httpHeaders: [String: String] = [:],
        isHLS: Bool = false
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.containerExt = containerExt
        self.resolutionHeight = resolutionHeight
        self.isAudioOnly = isAudioOnly
        self.estimatedBytes = estimatedBytes
        self.formatSelector = formatSelector
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.httpHeaders = httpHeaders
        self.isHLS = isHLS
    }
}

public struct YTDLPMediaInfo: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let sourceURL: URL
    public let title: String
    public let uploader: String
    public let durationSeconds: Double?
    public let thumbnailURL: URL?
    public let extractorName: String
    public let formats: [YTDLPFormatOption]

    public var formattedDuration: String? {
        guard let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 else { return nil }
        let total = Int(durationSeconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        title: String,
        uploader: String,
        durationSeconds: Double?,
        thumbnailURL: URL?,
        extractorName: String,
        formats: [YTDLPFormatOption]
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.title = title
        self.uploader = uploader
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.extractorName = extractorName
        self.formats = formats
    }

    public func preferredFormat(for preset: YTDLPQualityPreset) -> YTDLPFormatOption? {
        switch preset {
        case .askEveryTime, .bestMP4:
            return formats.first(where: { !$0.isAudioOnly }) ?? formats.first
        case .p1080:
            return formats.first(where: { ($0.resolutionHeight ?? 0) <= 1080 && !$0.isAudioOnly })
                ?? formats.first(where: { !$0.isAudioOnly })
                ?? formats.first
        case .p720:
            return formats.first(where: { ($0.resolutionHeight ?? 0) <= 720 && !$0.isAudioOnly })
                ?? formats.first(where: { !$0.isAudioOnly })
                ?? formats.first
        case .audioM4A:
            return formats.first(where: { $0.isAudioOnly }) ?? formats.first
        }
    }
}

/// Lightweight host/URL matcher used by `Auto / Smart Hybrid` mode to route supported social/video pages
/// to `yt-dlp` without ever initializing the embedded Python runtime for direct file downloads.
public enum YTDLPURLMatcher {
    private static let supportedDomains: [String] = [
        "youtube.com", "youtu.be", "music.youtube.com",
        "tiktok.com", "vm.tiktok.com",
        "instagram.com", "instagr.am",
        "twitter.com", "x.com",
        "reddit.com", "redd.it", "v.redd.it",
        "facebook.com", "fb.watch",
        "vimeo.com",
        "twitch.tv", "clips.twitch.tv",
        "dailymotion.com", "dai.ly",
        "soundcloud.com",
        "bilibili.com", "b23.tv",
        "rumble.com",
        "kick.com",
        "pinterest.com", "pin.it",
        "threads.net",
        "bsky.app",
    ]

    private static let directFileExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "webm", "avi", "flv", "ts",
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus",
        "zip", "rar", "7z", "tar", "gz", "dmg", "ipa", "apk", "pdf", "iso", "bin",
        "m3u8", "mpd",
    ]

    public static func shouldPreferYTDLP(for url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty && directFileExtensions.contains(ext) {
            return false
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return supportedDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }
}
