import Foundation
import libmpv

@MainActor
public protocol PlaybackEngineDriver: AnyObject {
    var coreKind: PlaybackCoreKind { get }
    var isPlaying: Bool { get }
    var currentTimeSeconds: Double { get }
    var durationSeconds: Double { get }
    var bufferedSeconds: Double { get }
    var playbackRate: Float { get set }
    var aspectMode: PlayerAspectMode { get set }
    var isPiPSupported: Bool { get }
    var isPiPActive: Bool { get }
    var audioTracks: [PlayerMediaTrack] { get }
    var subtitleTracks: [PlayerMediaTrack] { get }

    func load(_ source: PlayableSource) async throws
    func play()
    func pause()
    func seek(to seconds: Double, accurate: Bool) async
    func skip(by deltaSeconds: Double) async
    func selectAudioTrack(_ id: Int)
    func selectSubtitleTrack(_ id: Int?)
    func togglePictureInPicture()
    func teardown()
}

public enum PrismPlayerEngineDiagnostics: Sendable {
    /// Exercises real libmpv C API linkage so Release builds verify and embed libmpv.framework.
    public static var mpvAPIVersionSummary: String {
        let raw = mpv_client_api_version()
        let major = (raw >> 16) & 0xFFFF
        let minor = raw & 0xFFFF
        return "AVPlayer + libmpv API \(major).\(minor)"
    }
}
