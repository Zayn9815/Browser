import Foundation
import libmpv
import Observation
import QuartzCore
import SwiftUI
import UIKit
import VaultManager

public final class MPVMetalSurfaceUIView: UIView {
    public override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    public var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        metalLayer.framebufferOnly = true
        metalLayer.pixelFormat = .bgra8Unorm
        if let scale = window?.screen.scale {
            metalLayer.contentsScale = scale
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let scale = metalLayer.contentsScale > 0 ? metalLayer.contentsScale : 3.0
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

public struct MPVMetalSurfaceRepresentable: UIViewRepresentable {
    public let engine: MPVUniversalEngine

    public init(engine: MPVUniversalEngine) {
        self.engine = engine
    }

    public func makeUIView(context: Context) -> MPVMetalSurfaceUIView {
        let view = MPVMetalSurfaceUIView()
        view.backgroundColor = .black
        engine.attach(to: view.metalLayer)
        return view
    }

    public func updateUIView(_ uiView: MPVMetalSurfaceUIView, context: Context) {
        engine.attach(to: uiView.metalLayer)
    }
}

private struct MPVTrackJSON: Decodable, Sendable {
    let id: Int
    let type: String
    let title: String?
    let lang: String?
    let isDefault: Bool?
    let selected: Bool?

    enum CodingKeys: String, CodingKey {
        case id, type, title, lang, selected
        case isDefault = "default"
    }
}

/// Thread-safe C pointer box isolating `mpv_handle` access for Swift 6 concurrency.
private final class MPVHandleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: OpaquePointer?
    private var shuttingDown = false

    func store(_ newHandle: OpaquePointer) {
        lock.lock()
        handle = newHandle
        shuttingDown = false
        lock.unlock()
    }

    func withHandle<R>(_ body: (OpaquePointer) -> R) -> R? {
        lock.lock()
        defer { lock.unlock() }
        guard !shuttingDown, let handle else { return nil }
        return body(handle)
    }

    func waitEvent(timeout: Double) -> mpv_event? {
        // Retrieve pointer without holding lock across blocking mpv_wait_event
        lock.lock()
        let current = shuttingDown ? nil : handle
        lock.unlock()
        guard let current, let eventPtr = mpv_wait_event(current, timeout) else { return nil }
        return eventPtr.pointee
    }

    func markShuttingDownAndWakeup() {
        lock.lock()
        shuttingDown = true
        let current = handle
        lock.unlock()
        if let current {
            mpv_wakeup(current)
        }
    }

    func destroyNow() {
        lock.lock()
        shuttingDown = true
        let current = handle
        handle = nil
        lock.unlock()
        if let current {
            mpv_terminate_destroy(current)
        }
    }
}

@Observable
@MainActor
public final class MPVUniversalEngine: PlaybackEngineDriver {
    public let coreKind: PlaybackCoreKind = .mpvFFmpeg

    public private(set) var isPlaying: Bool = false
    public private(set) var currentTimeSeconds: Double = 0
    public private(set) var durationSeconds: Double = 0
    public private(set) var bufferedSeconds: Double = 0
    public let isPiPSupported: Bool = false
    public let isPiPActive: Bool = false
    public private(set) var audioTracks: [PlayerMediaTrack] = []
    public private(set) var subtitleTracks: [PlayerMediaTrack] = []
    public private(set) var selectedAudioTrackID: Int?
    public private(set) var selectedSubtitleTrackID: Int?
    public private(set) var errorMessage: String?

    public var playbackRate: Float = 1.0 {
        didSet {
            let rate = Double(playbackRate)
            handleBox.withHandle { ctx in
                var val = rate
                _ = mpv_set_property(ctx, "speed", MPV_FORMAT_DOUBLE, &val)
            }
            publishNowPlaying()
        }
    }

    public var aspectMode: PlayerAspectMode = .fit {
        didSet {
            applyAspectMode()
        }
    }

    private let handleBox = MPVHandleBox()
    private let eventQueue = DispatchQueue(label: "com.prismdm.mpv.events", qos: .userInitiated)
    private weak var metalLayer: CAMetalLayer?
    private var pendingSource: PlayableSource?
    private var currentTitle: String = ""
    private var isInitialized = false

    public init() {}

    public func attach(to layer: CAMetalLayer) {
        if metalLayer === layer && isInitialized {
            return
        }
        metalLayer = layer
        if let source = pendingSource {
            pendingSource = nil
            Task { @MainActor [weak self] in
                try? await self?.load(source)
            }
        }
    }

    public func load(_ source: PlayableSource) async throws {
        errorMessage = nil
        currentTitle = source.title
        BackgroundAudioCenter.shared.configureAudioSession()

        guard let metalLayer else {
            pendingSource = source
            return
        }

        if !isInitialized {
            try initializeMPV(metalLayer: metalLayer, source: source)
        }

        applyHTTPHeadersIfNeeded(for: source)

        let targetPath: String
        var resumeSeconds: Double = 0
        switch source {
        case .remoteStream(_, let url, _, _, _, _):
            targetPath = url.absoluteString
        case .vaultFile(_, let fileURL, _, let resume):
            targetPath = fileURL.path(percentEncoded: false)
            resumeSeconds = resume
        }

        executeCommand(["loadfile", targetPath, "replace"])
        setFlagProperty("pause", false)
        isPlaying = true

        if resumeSeconds > 1 {
            try? await Task.sleep(for: .milliseconds(350))
            await seek(to: resumeSeconds, accurate: true)
        }
    }

    public func play() {
        BackgroundAudioCenter.shared.configureAudioSession()
        setFlagProperty("pause", false)
        isPlaying = true
        publishNowPlaying()
    }

    public func pause() {
        setFlagProperty("pause", true)
        isPlaying = false
        publishNowPlaying()
    }

    public func seek(to seconds: Double, accurate: Bool) async {
        let target = max(0, seconds)
        let mode = accurate ? "absolute+exact" : "absolute+keyframes"
        executeCommand(["seek", String(format: "%.3f", target), mode])
        currentTimeSeconds = target
        publishNowPlaying()
    }

    public func skip(by deltaSeconds: Double) async {
        executeCommand(["seek", String(format: "%.3f", deltaSeconds), "relative"])
    }

    public func selectAudioTrack(_ id: Int) {
        handleBox.withHandle { ctx in
            _ = mpv_set_property_string(ctx, "aid", "\(id)")
        }
        selectedAudioTrackID = id
    }

    public func selectSubtitleTrack(_ id: Int?) {
        handleBox.withHandle { ctx in
            if let id {
                _ = mpv_set_property_string(ctx, "sid", "\(id)")
            } else {
                _ = mpv_set_property_string(ctx, "sid", "no")
            }
        }
        selectedSubtitleTrackID = id
    }

    public func togglePictureInPicture() {
        // libmpv Metal renderer runs full-screen universal decode; PiP is supported by NativeAVPlayerEngine
    }

    public func teardown() {
        isInitialized = false
        isPlaying = false
        pendingSource = nil
        handleBox.markShuttingDownAndWakeup()
        let box = handleBox
        eventQueue.async {
            box.destroyNow()
        }
    }

    // MARK: - Private libmpv Lifecycle

    private func initializeMPV(metalLayer: CAMetalLayer, source: PlayableSource) throws {
        guard let ctx = mpv_create() else {
            throw NSError(domain: "PrismMPV", code: 1, userInfo: [NSLocalizedDescriptionKey: "mpv_create() returned nil"])
        }

        // Bind CAMetalLayer pointer as native MoltenVK/Metal window handle
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
        _ = mpv_set_option(ctx, "wid", MPV_FORMAT_INT64, &wid)
        _ = mpv_set_option_string(ctx, "vo", "gpu-next")
        _ = mpv_set_option_string(ctx, "gpu-context", "moltenvk")
        _ = mpv_set_option_string(ctx, "hwdec", "videotoolbox")
        _ = mpv_set_option_string(ctx, "hwdec-codecs", "all")
        _ = mpv_set_option_string(ctx, "keep-open", "yes")
        _ = mpv_set_option_string(ctx, "sub-auto", "fuzzy")
        _ = mpv_set_option_string(ctx, "demuxer-max-bytes", "64MiB")
        _ = mpv_set_option_string(ctx, "demuxer-max-back-bytes", "16MiB")
        _ = mpv_set_option_string(ctx, "cache", "yes")
        _ = mpv_set_option_string(ctx, "tls-verify", "no")

        if case .remoteStream(_, let url, _, _, let session, _) = source {
            let headers = session.httpHeaderDictionary(for: url)
            if let ua = headers["User-Agent"] {
                _ = mpv_set_option_string(ctx, "user-agent", ua)
            }
            if let referer = headers["Referer"] {
                _ = mpv_set_option_string(ctx, "referrer", referer)
            }
            let extraFields = headers
                .filter { $0.key != "User-Agent" && $0.key != "Referer" }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ",")
            if !extraFields.isEmpty {
                _ = mpv_set_option_string(ctx, "http-header-fields", extraFields)
            }
        }

        let status = mpv_initialize(ctx)
        guard status >= 0 else {
            mpv_terminate_destroy(ctx)
            throw NSError(domain: "PrismMPV", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "mpv_initialize failed (\(status))"])
        }

        _ = mpv_observe_property(ctx, 1, "time-pos", MPV_FORMAT_DOUBLE)
        _ = mpv_observe_property(ctx, 2, "duration", MPV_FORMAT_DOUBLE)
        _ = mpv_observe_property(ctx, 3, "pause", MPV_FORMAT_FLAG)
        _ = mpv_observe_property(ctx, 4, "demuxer-cache-duration", MPV_FORMAT_DOUBLE)
        _ = mpv_observe_property(ctx, 5, "track-list", MPV_FORMAT_STRING)

        handleBox.store(ctx)
        isInitialized = true
        applyAspectMode()
        startEventLoop()
    }

    private func applyHTTPHeadersIfNeeded(for source: PlayableSource) {
        guard case .remoteStream(_, let url, _, _, let session, _) = source else { return }
        let headers = session.httpHeaderDictionary(for: url)
        handleBox.withHandle { ctx in
            if let ua = headers["User-Agent"] {
                _ = mpv_set_property_string(ctx, "user-agent", ua)
            }
            if let referer = headers["Referer"] {
                _ = mpv_set_property_string(ctx, "referrer", referer)
            }
            let extraFields = headers
                .filter { $0.key != "User-Agent" && $0.key != "Referer" }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ",")
            if !extraFields.isEmpty {
                _ = mpv_set_property_string(ctx, "http-header-fields", extraFields)
            }
        }
    }

    private func startEventLoop() {
        let box = handleBox
        eventQueue.async { [weak self] in
            while let event = box.waitEvent(timeout: 0.25) {
                switch event.event_id {
                case MPV_EVENT_SHUTDOWN:
                    return
                case MPV_EVENT_FILE_LOADED:
                    Task { @MainActor [weak self] in
                        self?.refreshTracksFromMPV()
                    }
                case MPV_EVENT_PROPERTY_CHANGE:
                    guard let propPtr = event.data?.assumingMemoryBound(to: mpv_event_property.self) else { continue }
                    let prop = propPtr.pointee
                    guard let namePtr = prop.name else { continue }
                    let name = String(cString: namePtr)
                    switch (name, prop.format) {
                    case ("time-pos", MPV_FORMAT_DOUBLE):
                        if let val = prop.data?.assumingMemoryBound(to: Double.self).pointee, val.isFinite {
                            Task { @MainActor [weak self] in
                                self?.currentTimeSeconds = max(0, val)
                                self?.publishNowPlaying()
                            }
                        }
                    case ("duration", MPV_FORMAT_DOUBLE):
                        if let val = prop.data?.assumingMemoryBound(to: Double.self).pointee, val.isFinite, val > 0 {
                            Task { @MainActor [weak self] in
                                self?.durationSeconds = val
                            }
                        }
                    case ("pause", MPV_FORMAT_FLAG):
                        if let flag = prop.data?.assumingMemoryBound(to: Int32.self).pointee {
                            let paused = (flag != 0)
                            Task { @MainActor [weak self] in
                                self?.isPlaying = !paused
                                self?.publishNowPlaying()
                            }
                        }
                    case ("demuxer-cache-duration", MPV_FORMAT_DOUBLE):
                        if let val = prop.data?.assumingMemoryBound(to: Double.self).pointee, val.isFinite {
                            Task { @MainActor [weak self] in
                                guard let self else { return }
                                self.bufferedSeconds = self.currentTimeSeconds + max(0, val)
                            }
                        }
                    case ("track-list", _):
                        Task { @MainActor [weak self] in
                            self?.refreshTracksFromMPV()
                        }
                    default:
                        break
                    }
                default:
                    break
                }
            }
        }
    }

    private func refreshTracksFromMPV() {
        let jsonString: String? = handleBox.withHandle { ctx in
            guard let cStr = mpv_get_property_string(ctx, "track-list") else { return nil }
            defer { mpv_free(cStr) }
            return String(cString: cStr)
        } ?? nil

        guard let jsonString,
              let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MPVTrackJSON].self, from: data) else {
            return
        }

        var audios: [PlayerMediaTrack] = []
        var subs: [PlayerMediaTrack] = []
        for item in decoded {
            let label = item.title ?? item.lang?.uppercased() ?? "Track \(item.id)"
            let track = PlayerMediaTrack(
                id: item.id,
                title: label,
                languageCode: item.lang,
                isDefault: item.isDefault ?? false
            )
            if item.type == "audio" {
                audios.append(track)
                if item.selected == true { selectedAudioTrackID = item.id }
            } else if item.type == "sub" {
                subs.append(track)
                if item.selected == true { selectedSubtitleTrackID = item.id }
            }
        }
        audioTracks = audios
        subtitleTracks = subs
    }

    private func applyAspectMode() {
        handleBox.withHandle { ctx in
            switch aspectMode {
            case .fit:
                _ = mpv_set_property_string(ctx, "keepaspect", "yes")
                _ = mpv_set_property_string(ctx, "panscan", "0.0")
            case .fill:
                _ = mpv_set_property_string(ctx, "keepaspect", "yes")
                _ = mpv_set_property_string(ctx, "panscan", "1.0")
            case .stretch:
                _ = mpv_set_property_string(ctx, "keepaspect", "no")
                _ = mpv_set_property_string(ctx, "panscan", "0.0")
            }
        }
    }

    private func setFlagProperty(_ name: String, _ flag: Bool) {
        handleBox.withHandle { ctx in
            var value: Int32 = flag ? 1 : 0
            _ = mpv_set_property(ctx, name, MPV_FORMAT_FLAG, &value)
        }
    }

    private func executeCommand(_ args: [String]) {
        handleBox.withHandle { ctx in
            var cStrings = args.map { strdup($0) }
            cStrings.append(nil)
            defer {
                for ptr in cStrings where ptr != nil {
                    free(ptr)
                }
            }
            cStrings.withUnsafeMutableBufferPointer { buffer in
                buffer.baseAddress?.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { rebound in
                    _ = mpv_command(ctx, rebound)
                }
            }
        }
    }

    private func publishNowPlaying() {
        BackgroundAudioCenter.shared.updateExternalNowPlaying(
            title: currentTitle,
            elapsedSeconds: currentTimeSeconds,
            durationSeconds: durationSeconds,
            playbackRate: isPlaying ? playbackRate : 0.0
        )
    }
}
