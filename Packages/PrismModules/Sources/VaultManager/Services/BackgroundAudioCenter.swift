import AVFoundation
import Foundation
import MediaPlayer
import Observation

@Observable
@MainActor
public final class BackgroundAudioCenter {
    public static let shared = BackgroundAudioCenter()

    public private(set) var currentTrackURL: URL?
    public private(set) var currentTitle: String = ""
    public private(set) var isPlaying: Bool = false
    public private(set) var currentTimeSeconds: Double = 0
    public private(set) var durationSeconds: Double = 0

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var remoteCommandsConfigured = false

    public var hasActiveTrack: Bool {
        currentTrackURL != nil
    }

    public init() {}

    public func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Audio session may fail transiently if interrupted; playback retry handles it
        }
    }

    public func playFile(at url: URL, title: String? = nil) {
        stop()
        configureAudioSession()
        configureRemoteCommandsIfNeeded()

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.allowsExternalPlayback = true
        self.player = newPlayer
        self.currentTrackURL = url
        self.currentTitle = title ?? url.deletingPathExtension().lastPathComponent
        self.currentTimeSeconds = 0
        self.durationSeconds = 0

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTimeSeconds = max(0, seconds)
                }
                if let dur = self.player?.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
                    self.durationSeconds = dur
                }
                self.publishNowPlayingInfo()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.currentTimeSeconds = 0
                self.player?.seek(to: .zero)
                self.publishNowPlayingInfo()
            }
        }

        newPlayer.play()
        isPlaying = true
        publishNowPlayingInfo()
    }

    public func play() {
        guard let player else { return }
        configureAudioSession()
        player.play()
        isPlaying = true
        publishNowPlayingInfo()
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        publishNowPlayingInfo()
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func skip(by deltaSeconds: Double) {
        guard let player else { return }
        let target = max(0, min(durationSeconds > 0 ? durationSeconds : .greatestFiniteMagnitude, currentTimeSeconds + deltaSeconds))
        seek(to: target)
    }

    public func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, seconds)
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTimeSeconds = clamped
        publishNowPlayingInfo()
    }

    public func stop() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        currentTrackURL = nil
        currentTitle = ""
        isPlaying = false
        currentTimeSeconds = 0
        durationSeconds = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Allows external players (such as PrismPlayer) to synchronize Lock Screen / Control Center Now Playing state.
    public func updateExternalNowPlaying(
        title: String,
        elapsedSeconds: Double,
        durationSeconds: Double,
        playbackRate: Float
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "PrismDM",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
        ]
        if durationSeconds.isFinite && durationSeconds > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = durationSeconds
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func publishNowPlayingInfo() {
        guard !currentTitle.isEmpty else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        updateExternalNowPlaying(
            title: currentTitle,
            elapsedSeconds: currentTimeSeconds,
            durationSeconds: durationSeconds,
            playbackRate: isPlaying ? 1.0 : 0.0
        )
    }

    private func configureRemoteCommandsIfNeeded() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.play() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.skip(by: 15) }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.skip(by: -15) }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let target = posEvent.positionTime
            Task { @MainActor [weak self] in self?.seek(to: target) }
            return .success
        }
    }
}
