import Foundation

public enum MediaBridgeEventKind: String, Codable, Sendable {
    case mediaCandidateDetected = "MEDIA_CANDIDATE_DETECTED"
    case fullscreenIntercepted = "FULLSCREEN_INTERCEPTED"
    case blobSourceAttached = "BLOB_SOURCE_ATTACHED"
    case videoPlaybackState = "VIDEO_PLAYBACK_STATE"
    case drmStreamDetected = "DRM_STREAM_DETECTED"
}

public struct ViewportRectPayload: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct MediaBridgePayload: Codable, Sendable, Equatable {
    public let candidateId: String?
    public let streamUrl: String?
    public let containerHint: String?
    public let mimeType: String?
    public let isBlob: Bool?
    public let isDRMProtected: Bool?
    public let videoWidth: Int?
    public let videoHeight: Int?
    public let durationSeconds: Double?
    public let elementRectViewport: ViewportRectPayload?
    public let blobUrl: String?
    public let videoElementId: String?
    public let recentNetworkManifests: [String]?
    public let hasMediaKeys: Bool?
    public let resolvedStreamUrl: String?
    public let currentTimeSeconds: Double?
    public let playbackRate: Double?
    public let wasPlaying: Bool?

    public init(
        candidateId: String? = nil,
        streamUrl: String? = nil,
        containerHint: String? = nil,
        mimeType: String? = nil,
        isBlob: Bool? = nil,
        isDRMProtected: Bool? = nil,
        videoWidth: Int? = nil,
        videoHeight: Int? = nil,
        durationSeconds: Double? = nil,
        elementRectViewport: ViewportRectPayload? = nil,
        blobUrl: String? = nil,
        videoElementId: String? = nil,
        recentNetworkManifests: [String]? = nil,
        hasMediaKeys: Bool? = nil,
        resolvedStreamUrl: String? = nil,
        currentTimeSeconds: Double? = nil,
        playbackRate: Double? = nil,
        wasPlaying: Bool? = nil
    ) {
        self.candidateId = candidateId
        self.streamUrl = streamUrl
        self.containerHint = containerHint
        self.mimeType = mimeType
        self.isBlob = isBlob
        self.isDRMProtected = isDRMProtected
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.durationSeconds = durationSeconds
        self.elementRectViewport = elementRectViewport
        self.blobUrl = blobUrl
        self.videoElementId = videoElementId
        self.recentNetworkManifests = recentNetworkManifests
        self.hasMediaKeys = hasMediaKeys
        self.resolvedStreamUrl = resolvedStreamUrl
        self.currentTimeSeconds = currentTimeSeconds
        self.playbackRate = playbackRate
        self.wasPlaying = wasPlaying
    }
}

public struct MediaBridgeEnvelope: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let maxPayloadBytes = 65_536

    public let schemaVersion: Int
    public let event: MediaBridgeEventKind
    public let frameOrigin: String?
    public let pageReferer: String?
    public let pageTitle: String?
    public let timestampMs: Int64
    public let payload: MediaBridgePayload

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        event: MediaBridgeEventKind,
        frameOrigin: String? = nil,
        pageReferer: String? = nil,
        pageTitle: String? = nil,
        timestampMs: Int64,
        payload: MediaBridgePayload
    ) {
        self.schemaVersion = schemaVersion
        self.event = event
        self.frameOrigin = frameOrigin
        self.pageReferer = pageReferer
        self.pageTitle = pageTitle
        self.timestampMs = timestampMs
        self.payload = payload
    }
}

public enum MediaInterceptorBridgeInfo: Sendable {
    public static let messageHandlerName = "prismMediaBridge"

    public static func loadSchemaVersion() -> Int {
        guard let url = Bundle.module.url(forResource: "MediaBridgeSchema", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["schemaVersion"] as? Int else {
            return MediaBridgeEnvelope.currentSchemaVersion
        }
        return version
    }
}
