import SwiftUI

public struct PlayerLiquidGlassHUD: View {
    public let source: PlayableSource
    public let coreKind: PlaybackCoreKind
    public let isPlaying: Bool
    public let currentTimeSeconds: Double
    public let durationSeconds: Double
    public let bufferedSeconds: Double
    public let playbackRate: Float
    public let aspectMode: PlayerAspectMode
    public let isPiPSupported: Bool
    public let isLandscapeLocked: Bool
    public let isHUDVisible: Bool
    public let isHUDLocked: Bool
    public let activeIndicator: ActivePlayerGestureIndicator?
    public let audioTracks: [PlayerMediaTrack]
    public let subtitleTracks: [PlayerMediaTrack]
    public let selectedAudioTrackID: Int?
    public let selectedSubtitleTrackID: Int?
    public let canDownload: Bool

    public let onClose: () -> Void
    public let onTogglePlayPause: () -> Void
    public let onSkip: (Double) -> Void
    public let onSeek: (Double) -> Void
    public let onSelectSpeed: (Float) -> Void
    public let onCycleAspectMode: () -> Void
    public let onTogglePiP: () -> Void
    public let onToggleOrientation: () -> Void
    public let onToggleLock: () -> Void
    public let onSelectAudioTrack: (Int) -> Void
    public let onSelectSubtitleTrack: (Int?) -> Void
    public let onTapDownload: () -> Void

    @State private var isDraggingSlider = false
    @State private var sliderTimeSeconds: Double = 0
    @State private var showSpeedSheet = false
    @State private var showTracksSheet = false
    @State private var hapticCounter = 0

    public init(
        source: PlayableSource,
        coreKind: PlaybackCoreKind,
        isPlaying: Bool,
        currentTimeSeconds: Double,
        durationSeconds: Double,
        bufferedSeconds: Double,
        playbackRate: Float,
        aspectMode: PlayerAspectMode,
        isPiPSupported: Bool,
        isLandscapeLocked: Bool,
        isHUDVisible: Bool,
        isHUDLocked: Bool,
        activeIndicator: ActivePlayerGestureIndicator?,
        audioTracks: [PlayerMediaTrack],
        subtitleTracks: [PlayerMediaTrack],
        selectedAudioTrackID: Int?,
        selectedSubtitleTrackID: Int?,
        canDownload: Bool,
        onClose: @escaping () -> Void,
        onTogglePlayPause: @escaping () -> Void,
        onSkip: @escaping (Double) -> Void,
        onSeek: @escaping (Double) -> Void,
        onSelectSpeed: @escaping (Float) -> Void,
        onCycleAspectMode: @escaping () -> Void,
        onTogglePiP: @escaping () -> Void,
        onToggleOrientation: @escaping () -> Void,
        onToggleLock: @escaping () -> Void,
        onSelectAudioTrack: @escaping (Int) -> Void,
        onSelectSubtitleTrack: @escaping (Int?) -> Void,
        onTapDownload: @escaping () -> Void
    ) {
        self.source = source
        self.coreKind = coreKind
        self.isPlaying = isPlaying
        self.currentTimeSeconds = currentTimeSeconds
        self.durationSeconds = durationSeconds
        self.bufferedSeconds = bufferedSeconds
        self.playbackRate = playbackRate
        self.aspectMode = aspectMode
        self.isPiPSupported = isPiPSupported
        self.isLandscapeLocked = isLandscapeLocked
        self.isHUDVisible = isHUDVisible
        self.isHUDLocked = isHUDLocked
        self.activeIndicator = activeIndicator
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.selectedAudioTrackID = selectedAudioTrackID
        self.selectedSubtitleTrackID = selectedSubtitleTrackID
        self.canDownload = canDownload
        self.onClose = onClose
        self.onTogglePlayPause = onTogglePlayPause
        self.onSkip = onSkip
        self.onSeek = onSeek
        self.onSelectSpeed = onSelectSpeed
        self.onCycleAspectMode = onCycleAspectMode
        self.onTogglePiP = onTogglePiP
        self.onToggleOrientation = onToggleOrientation
        self.onToggleLock = onToggleLock
        self.onSelectAudioTrack = onSelectAudioTrack
        self.onSelectSubtitleTrack = onSelectSubtitleTrack
        self.onTapDownload = onTapDownload
    }

    public var body: some View {
        ZStack {
            if let activeIndicator {
                gestureIndicatorBadge(activeIndicator)
                    .transition(.opacity)
            }

            if isHUDVisible {
                if isHUDLocked {
                    lockedHUDOverlay
                } else {
                    fullHUDOverlay
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: hapticCounter)
        .sheet(isPresented: $showSpeedSheet) {
            speedPickerSheet
        }
        .sheet(isPresented: $showTracksSheet) {
            tracksPickerSheet
        }
    }

    private var lockedHUDOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    hapticCounter += 1
                    onToggleLock()
                } label: {
                    Label("Unlock", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(.clear.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            Spacer()
        }
    }

    private var fullHUDOverlay: some View {
        VStack(spacing: 0) {
            // Top Liquid Glass Bar (Clear Glass over Video)
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 10) {
                    Button {
                        hapticCounter += 1
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .glassEffect(.clear.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Player")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(coreKind == .nativeAVPlayer ? "AVPlayer Hardware" : "libmpv + VideoToolbox")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassEffect(.clear, in: .capsule)

                    Spacer(minLength: 4)

                    HStack(spacing: 8) {
                        if isPiPSupported {
                            Button {
                                hapticCounter += 1
                                onTogglePiP()
                            } label: {
                                Image(systemName: "pip.enter")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .glassEffect(.clear.interactive(), in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Picture in Picture")
                        }

                        Button {
                            hapticCounter += 1
                            onToggleOrientation()
                        } label: {
                            Image(systemName: isLandscapeLocked ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .glassEffect(.clear.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rotate Orientation")

                        Button {
                            hapticCounter += 1
                            onToggleLock()
                        } label: {
                            Image(systemName: "lock.open.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .glassEffect(.clear.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Lock Controls")

                        if canDownload {
                            Button {
                                hapticCounter += 1
                                onTapDownload()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.subheadline.weight(.bold))
                                    Text("Download")
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .glassEffect(
                                    .clear.tint(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0)).interactive(),
                                    in: .capsule
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Download Stream")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Spacer()

            // Center Playback Transport Cluster
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 24) {
                    Button {
                        hapticCounter += 1
                        onSkip(-10)
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .glassEffect(.clear.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rewind 10 seconds")

                    Button {
                        hapticCounter += 1
                        onTogglePlayPause()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 68, height: 68)
                            .glassEffect(.clear.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")

                    Button {
                        hapticCounter += 1
                        onSkip(10)
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .glassEffect(.clear.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Forward 10 seconds")
                }
            }

            Spacer()

            // Bottom Timeline & Utility Bar
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text(Self.formatTimestamp(isDraggingSlider ? sliderTimeSeconds : currentTimeSeconds))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 48, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: {
                                isDraggingSlider ? sliderTimeSeconds : currentTimeSeconds
                            },
                            set: { newVal in
                                sliderTimeSeconds = newVal
                            }
                        ),
                        in: 0...max(durationSeconds, 1.0),
                        onEditingChanged: { editing in
                            isDraggingSlider = editing
                            if !editing {
                                onSeek(sliderTimeSeconds)
                            }
                        }
                    )
                    .tint(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))

                    Text(Self.formatTimestamp(durationSeconds))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(minWidth: 48, alignment: .trailing)
                }

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            hapticCounter += 1
                            showSpeedSheet = true
                        } label: {
                            Text(String(format: "%.2gx", playbackRate))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .glassEffect(.clear.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)

                        Button {
                            hapticCounter += 1
                            onCycleAspectMode()
                        } label: {
                            Label(aspectMode.rawValue, systemImage: "aspectratio")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .glassEffect(.clear.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if !audioTracks.isEmpty || !subtitleTracks.isEmpty {
                            Button {
                                hapticCounter += 1
                                showTracksSheet = true
                            } label: {
                                Label("Audio & Subtitles", systemImage: "captions.bubble.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .glassEffect(.clear.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.clear, in: .rect(cornerRadius: 24))
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func gestureIndicatorBadge(_ indicator: ActivePlayerGestureIndicator) -> some View {
        switch indicator {
        case .brightness(let level):
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.yellow)
                ProgressView(value: level)
                    .frame(width: 110)
                    .tint(.yellow)
                Text("\(Int((level * 100).rounded()))%")
                    .font(.caption.weight(.bold).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.clear, in: .capsule)

        case .volume(let level):
            HStack(spacing: 10) {
                Image(systemName: level <= 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.white)
                ProgressView(value: level)
                    .frame(width: 110)
                    .tint(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                Text("\(Int((level * 100).rounded()))%")
                    .font(.caption.weight(.bold).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.clear, in: .capsule)

        case .scrub(let target, let delta, let duration):
            VStack(spacing: 4) {
                Text("\(Self.formatTimestamp(target)) / \(Self.formatTimestamp(duration))")
                    .font(.headline.monospacedDigit())
                let sign = delta >= 0 ? "+" : "-"
                Text("\(sign)\(Self.formatTimestamp(abs(delta)))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassEffect(.clear, in: .capsule)

        case .skip(let delta):
            HStack(spacing: 6) {
                Image(systemName: delta >= 0 ? "goforward.10" : "gobackward.10")
                Text("\(delta >= 0 ? "+" : "")\(delta)s")
                    .font(.headline.monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.clear, in: .capsule)
        }
    }

    private var speedPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(PlayerPlaybackSpeed.allCases) { speed in
                    Button {
                        onSelectSpeed(speed.rawValue)
                        showSpeedSheet = false
                    } label: {
                        HStack {
                            Text(speed.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if abs(playbackRate - speed.rawValue) < 0.01 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var tracksPickerSheet: some View {
        NavigationStack {
            List {
                if !audioTracks.isEmpty {
                    Section("Audio Tracks") {
                        ForEach(audioTracks) { track in
                            Button {
                                onSelectAudioTrack(track.id)
                                showTracksSheet = false
                            } label: {
                                HStack {
                                    Text(track.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedAudioTrackID == track.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Subtitles") {
                    Button {
                        onSelectSubtitleTrack(nil)
                        showTracksSheet = false
                    } label: {
                        HStack {
                            Text("Off")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedSubtitleTrackID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                            }
                        }
                    }

                    ForEach(subtitleTracks) { track in
                        Button {
                            onSelectSubtitleTrack(track.id)
                            showTracksSheet = false
                        } label: {
                            HStack {
                                Text(track.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedSubtitleTrackID == track.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Audio & Subtitles")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    public static func formatTimestamp(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
