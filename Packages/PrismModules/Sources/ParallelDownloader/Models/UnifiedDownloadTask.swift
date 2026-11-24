import Foundation
import SDMCore

public enum PrismDefaultDownloaderMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case smartHybrid
    case ytdlpUniversal
    case libcurlParallel
    case urlSessionBackground

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .smartHybrid:
            return "Auto / Smart Hybrid"
        case .ytdlpUniversal:
            return "yt-dlp (Universal Media Extractor)"
        case .libcurlParallel:
            return "libcurl Multi-Range Parallel"
        case .urlSessionBackground:
            return "iOS Background URLSession"
        }
    }

    public var shortLabel: String {
        switch self {
        case .smartHybrid: return "Smart Hybrid"
        case .ytdlpUniversal: return "yt-dlp"
        case .libcurlParallel: return "libcurl"
        case .urlSessionBackground: return "URLSession"
        }
    }

    public var underlyingSDMEngine: DownloadEngineKind {
        switch self {
        case .smartHybrid, .ytdlpUniversal, .libcurlParallel:
            return .libcurl
        case .urlSessionBackground:
            return .urlSession
        }
    }
}

public enum PrismTransferBackendKind: String, Codable, Sendable, CaseIterable {
    case sdmLibcurlRange
    case sdmBackgroundSession
    case ffmpegHLSMuxer
    case ytdlpParallel
    case ytdlpDirect

    public var displayTitle: String {
        switch self {
        case .sdmLibcurlRange:
            return "libcurl Multi-Range"
        case .sdmBackgroundSession:
            return "iOS Background URLSession"
        case .ffmpegHLSMuxer:
            return "FFmpeg HLS Parallel"
        case .ytdlpParallel:
            return "yt-dlp + Parallel"
        case .ytdlpDirect:
            return "yt-dlp Direct"
        }
    }
}

public struct UnifiedDownloadItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let backend: PrismTransferBackendKind
    public let sourceURL: URL
    public let resolvedFilename: String
    public let destinationURL: URL?
    public let state: DownloadState
    public let totalBytes: UInt64?
    public let isTotalBytesEstimated: Bool
    public let downloadedBytes: UInt64
    public let speedBytesPerSecond: UInt64
    public let etaSeconds: Double?
    public let formattedETALabel: String
    public let mediaProgressFraction: Double?
    public let segments: [DownloadSegmentSnapshot]
    public let errorMessage: String?
    public let createdAt: Date

    public init(
        id: UUID,
        backend: PrismTransferBackendKind,
        sourceURL: URL,
        resolvedFilename: String,
        destinationURL: URL? = nil,
        state: DownloadState,
        totalBytes: UInt64? = nil,
        isTotalBytesEstimated: Bool = false,
        downloadedBytes: UInt64 = 0,
        speedBytesPerSecond: UInt64 = 0,
        etaSeconds: Double? = nil,
        formattedETALabel: String = "",
        mediaProgressFraction: Double? = nil,
        segments: [DownloadSegmentSnapshot] = [],
        errorMessage: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.backend = backend
        self.sourceURL = sourceURL
        self.resolvedFilename = resolvedFilename
        self.destinationURL = destinationURL
        self.state = state
        self.totalBytes = totalBytes
        self.isTotalBytesEstimated = isTotalBytesEstimated
        self.downloadedBytes = downloadedBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.etaSeconds = etaSeconds
        self.formattedETALabel = formattedETALabel
        self.mediaProgressFraction = mediaProgressFraction
        self.segments = segments
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }

    public var progressFraction: Double? {
        if let mediaProgressFraction {
            return min(max(mediaProgressFraction, 0), 1)
        }
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(downloadedBytes) / Double(totalBytes), 0), 1)
    }

    public var isActive: Bool {
        switch state {
        case .created, .probing, .queued, .downloading, .pausing, .retrying, .finalizing:
            return true
        case .paused, .completed, .failed, .cancelled:
            return false
        }
    }

    public var formattedSizeRatio: String {
        let doneStr = ByteCountFormatter.string(fromByteCount: Int64(downloadedBytes), countStyle: .file)
        guard let totalBytes, totalBytes > 0 else {
            return doneStr
        }
        let totalStr = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        if isTotalBytesEstimated && state != .completed {
            return "\(doneStr) / ~\(totalStr)"
        }
        return "\(doneStr) / \(totalStr)"
    }
}
