import AVFoundation
import AVKit
import Foundation
import Observation
import SwiftUI
import UIKit
import VaultManager

public final class AVPlayerSurfaceUIView: UIView {
    public override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

public struct AVPlayerSurfaceRepresentable: UIViewRepresentable {
    public let engine: NativeAVPlayerEngine

    public init(engine: NativeAVPlayerEngine) {
        self.engine = engine
    }

    public func makeUIView(context: Context) -> AVPlayerSurfaceUIView {
        let view = AVPlayerSurfaceUIView()
        view.backgroundColor = .black
        engine.attach(to: view.playerLayer)
        return view
    }

    public func updateUIView(_ uiView: AVPlayerSurfaceUIView, context: Context) {
        engine.attach(to: uiView.playerLayer)
    }
}

@Observable
@MainActor
public final class NativeAVPlayerEngine: NSObject, PlaybackEngineDriver, AVPictureInPictureControllerDelegate {
    public let coreKind: PlaybackCoreKind = .nativeAVPlayer

    public private(set) var isPlaying: Bool = false
    public private(set) var currentTimeSeconds: Double = 0
    public private(set) var durationSeconds: Double = 0
    public private(set) var bufferedSeconds: Double = 0
    public private(set) var isPiPSupported: Bool = false
    public private(set) var isPiPActive: Bool = false
    public private(set) var audioTracks: [PlayerMediaTrack] = []
    public private(set) var subtitleTracks: [PlayerMediaTrack] = []
    public private(set) var selectedAudioTrackID: Int?
    public private(set) var selectedSubtitleTrackID: Int?
    public private(set) var errorMessage: String?

    public var playbackRate: Float = 1.0 {
        didSet {
            if isPlaying {
                player.rate = playbackRate
            }
            publishNowPlaying()
        }
    }

    public var aspectMode: PlayerAspectMode = .fit {
        didSet {
            applyVideoGravity()
        }
    }

    private let player = AVPlayer()
    private weak var boundLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?
    private var timeObserverToken: Any?
    private var rateObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var audibleGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?
    private var currentTitle: String = ""

    public override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        installPlayerObservers()
    }

    public func attach(to playerLayer: AVPlayerLayer) {
        if boundLayer === playerLayer && playerLayer.player === player {
            applyVideoGravity()
            return
        }
        boundLayer = playerLayer
        playerLayer.player = player
        applyVideoGravity()

        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: playerLayer)
            pip?.delegate = self
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
            pipController = pip
            isPiPSupported = pip != nil
        } else {
            pipController = nil
            isPiPSupported = false
        }
    }

    public func load(_ source: PlayableSource) async throws {
        errorMessage = nil
        currentTitle = source.title
        BackgroundAudioCenter.shared.configureAudioSession()

        let asset: AVURLAsset
        switch source {
        case .remoteStream(_, let url, _, _, let sessionContext, _):
            let headers = sessionContext.httpHeaderDictionary(for: url)
            if headers.isEmpty {
                asset = AVURLAsset(url: url)
            } else {
                asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            }
        case .vaultFile(_, let fileURL, _, _):
            asset = AVURLAsset(url: fileURL)
        }

        let item = AVPlayerItem(asset: asset)
        observeItemStatus(item)
        player.replaceCurrentItem(with: item)

        // Load duration and audio/subtitle track groups asynchronously
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 {
            durationSeconds = duration.seconds
        }
        await loadMediaSelectionTracks(from: asset, item: item)

        if case .vaultFile(_, _, _, let resumeSeconds) = source, resumeSeconds > 1 {
            await seek(to: resumeSeconds, accurate: true)
        }

        play()
    }

    public func play() {
        BackgroundAudioCenter.shared.configureAudioSession()
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
        publishNowPlaying()
    }

    public func pause() {
        player.pause()
        isPlaying = false
        publishNowPlaying()
    }

    public func seek(to seconds: Double, accurate: Bool) async {
        let maxDuration = durationSeconds > 0 ? durationSeconds : .greatestFiniteMagnitude
        let target = min(max(0, seconds), maxDuration)
        let cmTarget = CMTime(seconds: target, preferredTimescale: 600)
        let tolerance: CMTime = accurate ? .zero : CMTime(seconds: 0.35, preferredTimescale: 600)
        _ = await player.seek(to: cmTarget, toleranceBefore: tolerance, toleranceAfter: tolerance)
        currentTimeSeconds = target
        publishNowPlaying()
    }

    public func skip(by deltaSeconds: Double) async {
        await seek(to: currentTimeSeconds + deltaSeconds, accurate: false)
    }

    public func selectAudioTrack(_ id: Int) {
        guard let item = player.currentItem,
              let group = audibleGroup,
              id >= 0, id < group.options.count else {
            return
        }
        item.select(group.options[id], in: group)
        selectedAudioTrackID = id
    }

    public func selectSubtitleTrack(_ id: Int?) {
        guard let item = player.currentItem, let group = legibleGroup else { return }
        if let id, id >= 0, id < group.options.count {
            item.select(group.options[id], in: group)
            selectedSubtitleTrackID = id
        } else {
            item.select(nil, in: group)
            selectedSubtitleTrackID = nil
        }
    }

    public func togglePictureInPicture() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else if pipController.isPictureInPicturePossible {
            pipController.startPictureInPicture()
        }
    }

    public func teardown() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        rateObservation?.invalidate()
        rateObservation = nil
        statusObservation?.invalidate()
        statusObservation = nil
        pipController?.delegate = nil
        pipController = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        boundLayer?.player = nil
        boundLayer = nil
        isPlaying = false
    }

    // MARK: - AVPictureInPictureControllerDelegate

    nonisolated public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            self?.isPiPActive = true
        }
    }

    nonisolated public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            self?.isPiPActive = false
        }
    }

    // MARK: - Private Observers & Helpers

    private func installPlayerObservers() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let sec = time.seconds
                if sec.isFinite {
                    self.currentTimeSeconds = max(0, sec)
                }
                if let item = self.player.currentItem {
                    if item.duration.seconds.isFinite && item.duration.seconds > 0 {
                        self.durationSeconds = item.duration.seconds
                    }
                    if let range = item.loadedTimeRanges.last?.timeRangeValue {
                        let end = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
                        if end.isFinite {
                            self.bufferedSeconds = max(0, end)
                        }
                    }
                }
                self.publishNowPlaying()
            }
        }

        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] avPlayer, _ in
            Task { @MainActor [weak self, weak avPlayer] in
                guard let self, let avPlayer else { return }
                self.isPlaying = (avPlayer.timeControlStatus == .playing)
            }
        }
    }

    private func observeItemStatus(_ item: AVPlayerItem) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            Task { @MainActor [weak self, weak playerItem] in
                guard let self, let playerItem else { return }
                if playerItem.status == .failed {
                    self.errorMessage = playerItem.error?.localizedDescription ?? "AVPlayer failed to load media."
                }
            }
        }
    }

    private func loadMediaSelectionTracks(from asset: AVURLAsset, item: AVPlayerItem) async {
        if let audible = try? await asset.loadMediaSelectionGroup(for: .audible) {
            audibleGroup = audible
            audioTracks = audible.options.enumerated().map { idx, opt in
                PlayerMediaTrack(
                    id: idx,
                    title: opt.displayName,
                    languageCode: opt.locale?.language.languageCode?.identifier,
                    isDefault: opt == audible.defaultOption
                )
            }
            if let def = audible.defaultOption, let idx = audible.options.firstIndex(of: def) {
                selectedAudioTrackID = idx
            }
        }

        if let legible = try? await asset.loadMediaSelectionGroup(for: .legible) {
            legibleGroup = legible
            subtitleTracks = legible.options.enumerated().map { idx, opt in
                PlayerMediaTrack(
                    id: idx,
                    title: opt.displayName,
                    languageCode: opt.locale?.language.languageCode?.identifier,
                    isDefault: opt == legible.defaultOption
                )
            }
        }
    }

    private func applyVideoGravity() {
        guard let boundLayer else { return }
        switch aspectMode {
        case .fit:
            boundLayer.videoGravity = .resizeAspect
        case .fill:
            boundLayer.videoGravity = .resizeAspectFill
        case .stretch:
            boundLayer.videoGravity = .resize
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
