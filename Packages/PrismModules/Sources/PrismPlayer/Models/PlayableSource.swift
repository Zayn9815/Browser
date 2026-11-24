import CoreGraphics
import Foundation
import ParallelDownloader

public struct HLSStreamVariant: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let url: URL
    public let width: Int?
    public let height: Int?
    public let bandwidthBitsPerSec: Int
    public let frameRate: Double?
    public let codecs: String?

    public init(
        id: String? = nil,
        url: URL,
        width: Int? = nil,
        height: Int? = nil,
        bandwidthBitsPerSec: Int,
        frameRate: Double? = nil,
        codecs: String? = nil
    ) {
        self.id = id ?? url.absoluteString
        self.url = url
        self.width = width
        self.height = height
        self.bandwidthBitsPerSec = bandwidthBitsPerSec
        self.frameRate = frameRate
        self.codecs = codecs
    }

    public var resolution: CGSize? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    public var displayLabel: String {
        var components: [String] = []
        if let height {
            if let frameRate, frameRate >= 50 {
                components.append("\(height)p\(Int(frameRate.rounded()))")
            } else {
                components.append("\(height)p")
            }
        }
        if bandwidthBitsPerSec > 0 {
            let mbps = Double(bandwidthBitsPerSec) / 1_000_000.0
            components.append(String(format: "%.1f Mbps", mbps))
        }
        if let codecs, !codecs.isEmpty {
            components.append(codecs)
        }
        return components.isEmpty ? url.lastPathComponent : components.joined(separator: " • ")
    }
}

public enum PlaybackCoreKind: String, Sendable, Codable, Equatable {
    case nativeAVPlayer
    case mpvFFmpeg
}

public enum PlayableSource: Identifiable, Sendable, Equatable {
    case remoteStream(
        id: UUID,
        url: URL,
        title: String,
        mimeType: String?,
        sessionContext: BrowserSessionContext,
        variants: [HLSStreamVariant]
    )
    case vaultFile(
        id: UUID,
        fileURL: URL,
        title: String,
        resumeSeconds: Double
    )

    public var id: UUID {
        switch self {
        case .remoteStream(let id, _, _, _, _, _):
            return id
        case .vaultFile(let id, _, _, _):
            return id
        }
    }

    public var title: String {
        switch self {
        case .remoteStream(_, _, let title, _, _, _):
            return title
        case .vaultFile(_, _, let title, _):
            return title
        }
    }

    public var sourceURL: URL {
        switch self {
        case .remoteStream(_, let url, _, _, _, _):
            return url
        case .vaultFile(_, let fileURL, _, _):
            return fileURL
        }
    }

    /// Routes natively hardware-decoded Apple formats (MP4/MOV/M4V/HLS/M4A/MP3/AAC/WAV) to AVPlayer,
    /// and universal container formats (MKV/AVI/WebM/FLV/TS/OGG/OPUS/WMA/MPD) to libmpv/FFmpeg.
    public var preferredEngineType: PlaybackCoreKind {
        let ext = sourceURL.pathExtension.lowercased()
        switch ext {
        case "mkv", "avi", "webm", "flv", "wmv", "ogv", "ogg", "opus", "mpd", "ts", "m2ts", "divx", "rmvb":
            return .mpvFFmpeg
        case "mp4", "mov", "m4v", "m3u8", "m3u", "mp3", "m4a", "aac", "wav", "aiff":
            return .nativeAVPlayer
        default:
            if case .remoteStream(_, _, _, let mimeType, _, _) = self,
               let lowered = mimeType?.lowercased() {
                if lowered.contains("webm") || lowered.contains("matroska") || lowered.contains("x-flv") || lowered.contains("dash+xml") || lowered.contains("x-msvideo") {
                    return .mpvFFmpeg
                }
            }
            return .nativeAVPlayer
        }
    }
}
