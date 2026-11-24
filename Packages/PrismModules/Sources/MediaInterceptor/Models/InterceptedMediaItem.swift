import CoreGraphics
import Foundation
import ParallelDownloader
import PrismPlayer

public enum InterceptedContainerHint: String, Codable, Sendable, CaseIterable {
    case m3u8
    case mp4
    case mpd
    case webm
    case unknown

    public var requiresHLSMuxer: Bool {
        self == .m3u8 || self == .mpd
    }
}

public struct InterceptedMediaItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let candidateId: String
    public let streamURL: URL
    public let containerHint: InterceptedContainerHint
    public let mimeType: String?
    public let title: String
    public let pageReferer: URL?
    public let frameOrigin: String?
    public let isDRMProtected: Bool
    public let videoWidth: Int?
    public let videoHeight: Int?
    public let durationSeconds: Double?
    public let sessionContext: BrowserSessionContext
    public let variants: [HLSStreamVariant]
    public let detectedAt: Date

    public init(
        id: UUID = UUID(),
        candidateId: String,
        streamURL: URL,
        containerHint: InterceptedContainerHint,
        mimeType: String? = nil,
        title: String,
        pageReferer: URL? = nil,
        frameOrigin: String? = nil,
        isDRMProtected: Bool = false,
        videoWidth: Int? = nil,
        videoHeight: Int? = nil,
        durationSeconds: Double? = nil,
        sessionContext: BrowserSessionContext,
        variants: [HLSStreamVariant] = [],
        detectedAt: Date = .now
    ) {
        self.id = id
        self.candidateId = candidateId
        self.streamURL = streamURL
        self.containerHint = containerHint
        self.mimeType = mimeType
        self.title = title
        self.pageReferer = pageReferer
        self.frameOrigin = frameOrigin
        self.isDRMProtected = isDRMProtected
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.durationSeconds = durationSeconds
        self.sessionContext = sessionContext
        self.variants = variants
        self.detectedAt = detectedAt
    }

    public func asPlayableSource() -> PlayableSource {
        .remoteStream(
            id: id,
            url: streamURL,
            title: title,
            mimeType: mimeType,
            sessionContext: sessionContext,
            variants: variants
        )
    }
}
