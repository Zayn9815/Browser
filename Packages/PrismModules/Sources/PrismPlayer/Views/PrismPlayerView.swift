import ParallelDownloader
import SwiftUI
import UIKit

/// UIHostingController subclass guaranteeing auto-hidden Status Bar & Home Indicator during playback.
public final class PlayerContainerViewController<Content: View>: UIHostingController<Content> {
    public var statusBarHidden: Bool = true {
        didSet {
            if oldValue != statusBarHidden {
                setNeedsStatusBarAppearanceUpdate()
            }
        }
    }

    public var homeIndicatorAutoHidden: Bool = true {
        didSet {
            if oldValue != homeIndicatorAutoHidden {
                setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
        }
    }

    public override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }

    public override var prefersHomeIndicatorAutoHidden: Bool {
        homeIndicatorAutoHidden
    }

    public override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }
}

/// Public entry point wrapping the Liquid Glass video player in `PlayerContainerViewController`.
public struct PrismPlayerView: UIViewControllerRepresentable {
    public let source: PlayableSource
    public let initialStartSeconds: Double
    public let initialPlaybackRate: Float
    public let autoLockLandscape: Bool
    public let onDismiss: @MainActor () -> Void
    public let onRequestDownload: (@MainActor (PlayableSource) -> Void)?

    public init(
        source: PlayableSource,
        initialStartSeconds: Double = 0,
        initialPlaybackRate: Float = 1.0,
        autoLockLandscape: Bool = false,
        onDismiss: @escaping @MainActor () -> Void,
        onRequestDownload: (@MainActor (PlayableSource) -> Void)? = nil
    ) {
        self.source = source
        self.initialStartSeconds = initialStartSeconds
        self.initialPlaybackRate = initialPlaybackRate
        self.autoLockLandscape = autoLockLandscape
        self.onDismiss = onDismiss
        self.onRequestDownload = onRequestDownload
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIViewController(context: Context) -> PlayerContainerViewController<PrismPlayerCanvasView> {
        let controller = PlayerContainerViewController(
            rootView: PrismPlayerCanvasView(
                source: source,
                initialStartSeconds: initialStartSeconds,
                initialPlaybackRate: initialPlaybackRate,
                autoLockLandscape: autoLockLandscape,
                onHUDChromeStateChanged: { [weak coordinator = context.coordinator] hudVisible, playing in
                    coordinator?.controller?.statusBarHidden = !hudVisible
                    coordinator?.controller?.homeIndicatorAutoHidden = playing || !hudVisible
                },
                onDismiss: onDismiss,
                onRequestDownload: onRequestDownload
            )
        )
        controller.view.backgroundColor = .black
        controller.statusBarHidden = false
        controller.homeIndicatorAutoHidden = true
        context.coordinator.controller = controller
        return controller
    }

    public func updateUIViewController(
        _ uiViewController: PlayerContainerViewController<PrismPlayerCanvasView>,
        context: Context
    ) {}

    @MainActor
    public final class Coordinator {
        weak var controller: PlayerContainerViewController<PrismPlayerCanvasView>?
    }
}

public struct PrismPlayerCanvasView: View {
    private let source: PlayableSource
    private let initialStartSeconds: Double
    private let initialPlaybackRate: Float
    private let autoLockLandscape: Bool
    private let onHUDChromeStateChanged: (Bool, Bool) -> Void
    private let onDismiss: () -> Void
    private let onRequestDownload: ((PlayableSource) -> Void)?

    @State private var avEngine = NativeAVPlayerEngine()
    @State private var mpvEngine = MPVUniversalEngine()
    @State private var orientationController = OrientationLockController.shared
    @State private var brightnessVolumeController = BrightnessAndVolumeController()

    @State private var isHUDVisible = true
    @State private var isHUDLocked = false
    @State private var activeIndicator: ActivePlayerGestureIndicator?
    @State private var loadErrorMessage: String?
    @State private var hudAutoHideTask: Task<Void, Never>?
    @State private var hasCleanedUp = false

    private var activeCoreKind: PlaybackCoreKind {
        source.preferredEngineType
    }

    private var activeIsPlaying: Bool {
        activeCoreKind == .nativeAVPlayer ? avEngine.isPlaying : mpvEngine.isPlaying
    }

    private var activeCurrentTime: Double {
        activeCoreKind == .nativeAVPlayer ? avEngine.currentTimeSeconds : mpvEngine.currentTimeSeconds
    }

    private var activeDuration: Double {
        activeCoreKind == .nativeAVPlayer ? avEngine.durationSeconds : mpvEngine.durationSeconds
    }

    private var activeBuffered: Double {
        activeCoreKind == .nativeAVPlayer ? avEngine.bufferedSeconds : mpvEngine.bufferedSeconds
    }

    private var activeRate: Float {
        activeCoreKind == .nativeAVPlayer ? avEngine.playbackRate : mpvEngine.playbackRate
    }

    private var activeAspectMode: PlayerAspectMode {
        activeCoreKind == .nativeAVPlayer ? avEngine.aspectMode : mpvEngine.aspectMode
    }

    private var activeAudioTracks: [PlayerMediaTrack] {
        activeCoreKind == .nativeAVPlayer ? avEngine.audioTracks : mpvEngine.audioTracks
    }

    private var activeSubtitleTracks: [PlayerMediaTrack] {
        activeCoreKind == .nativeAVPlayer ? avEngine.subtitleTracks : mpvEngine.subtitleTracks
    }

    private var activeSelectedAudioID: Int? {
        activeCoreKind == .nativeAVPlayer ? avEngine.selectedAudioTrackID : mpvEngine.selectedAudioTrackID
    }

    private var activeSelectedSubtitleID: Int? {
        activeCoreKind == .nativeAVPlayer ? avEngine.selectedSubtitleTrackID : mpvEngine.selectedSubtitleTrackID
    }

    private var canDownloadSource: Bool {
        if case .remoteStream = source { return onRequestDownload != nil }
        return false
    }

    public init(
        source: PlayableSource,
        initialStartSeconds: Double = 0,
        initialPlaybackRate: Float = 1.0,
        autoLockLandscape: Bool = false,
        onHUDChromeStateChanged: @escaping (Bool, Bool) -> Void,
        onDismiss: @escaping () -> Void,
        onRequestDownload: ((PlayableSource) -> Void)? = nil
    ) {
        self.source = source
        self.initialStartSeconds = initialStartSeconds
        self.initialPlaybackRate = initialPlaybackRate
        self.autoLockLandscape = autoLockLandscape
        self.onHUDChromeStateChanged = onHUDChromeStateChanged
        self.onDismiss = onDismiss
        self.onRequestDownload = onRequestDownload
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Offscreen 1x1 MPVolumeView to suppress system volume HUD during right-edge drags
            HiddenSystemVolumeBridge(controller: brightnessVolumeController)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)

            Group {
                if activeCoreKind == .nativeAVPlayer {
                    AVPlayerSurfaceRepresentable(engine: avEngine)
                } else {
                    MPVMetalSurfaceRepresentable(engine: mpvEngine)
                }
            }
            .ignoresSafeArea()

            PlayerGestureCanvas(
                isHUDLocked: isHUDLocked,
                currentTimeSeconds: activeCurrentTime,
                durationSeconds: activeDuration,
                brightnessVolumeController: brightnessVolumeController,
                activeIndicator: $activeIndicator,
                onSingleTap: {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        isHUDVisible.toggle()
                    }
                    onHUDChromeStateChanged(isHUDVisible, activeIsPlaying)
                    if isHUDVisible {
                        scheduleHUDAutoHide()
                    }
                },
                onTogglePlayPause: {
                    togglePlayPause()
                },
                onSkip: { delta in
                    Task { await skip(by: delta) }
                },
                onScrubCommit: { target in
                    Task { await seek(to: target, accurate: true) }
                }
            )
            .ignoresSafeArea()

            if let error = loadErrorMessage ?? (activeCoreKind == .nativeAVPlayer ? avEngine.errorMessage : mpvEngine.errorMessage) {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Close") {
                        closePlayer()
                    }
                    .buttonStyle(.glass)
                }
                .padding(24)
                .glassEffect(.clear, in: .rect(cornerRadius: 24))
                .padding(.horizontal, 24)
            }

            PlayerLiquidGlassHUD(
                source: source,
                coreKind: activeCoreKind,
                isPlaying: activeIsPlaying,
                currentTimeSeconds: activeCurrentTime,
                durationSeconds: activeDuration,
                bufferedSeconds: activeBuffered,
                playbackRate: activeRate,
                aspectMode: activeAspectMode,
                isPiPSupported: activeCoreKind == .nativeAVPlayer && avEngine.isPiPSupported,
                isLandscapeLocked: orientationController.isCurrentlyLandscape,
                isHUDVisible: isHUDVisible,
                isHUDLocked: isHUDLocked,
                activeIndicator: activeIndicator,
                audioTracks: activeAudioTracks,
                subtitleTracks: activeSubtitleTracks,
                selectedAudioTrackID: activeSelectedAudioID,
                selectedSubtitleTrackID: activeSelectedSubtitleID,
                canDownload: canDownloadSource,
                onClose: closePlayer,
                onTogglePlayPause: togglePlayPause,
                onSkip: { delta in Task { await skip(by: delta) } },
                onSeek: { seconds in Task { await seek(to: seconds, accurate: true) } },
                onSelectSpeed: { rate in
                    if activeCoreKind == .nativeAVPlayer {
                        avEngine.playbackRate = rate
                    } else {
                        mpvEngine.playbackRate = rate
                    }
                    scheduleHUDAutoHide()
                },
                onCycleAspectMode: {
                    let all = PlayerAspectMode.allCases
                    let next = all[((all.firstIndex(of: activeAspectMode) ?? 0) + 1) % all.count]
                    if activeCoreKind == .nativeAVPlayer {
                        avEngine.aspectMode = next
                    } else {
                        mpvEngine.aspectMode = next
                    }
                    scheduleHUDAutoHide()
                },
                onTogglePiP: {
                    avEngine.togglePictureInPicture()
                },
                onToggleOrientation: {
                    orientationController.toggleOrientation()
                    scheduleHUDAutoHide()
                },
                onToggleLock: {
                    withAnimation(.snappy) {
                        isHUDLocked.toggle()
                    }
                    scheduleHUDAutoHide()
                },
                onSelectAudioTrack: { id in
                    if activeCoreKind == .nativeAVPlayer {
                        avEngine.selectAudioTrack(id)
                    } else {
                        mpvEngine.selectAudioTrack(id)
                    }
                },
                onSelectSubtitleTrack: { id in
                    if activeCoreKind == .nativeAVPlayer {
                        avEngine.selectSubtitleTrack(id)
                    } else {
                        mpvEngine.selectSubtitleTrack(id)
                    }
                },
                onTapDownload: {
                    onRequestDownload?(source)
                }
            )
        }
        .task {
            brightnessVolumeController.beginSession()
            orientationController.beginPlayerSession(autoLockLandscape: autoLockLandscape)
            onHUDChromeStateChanged(isHUDVisible, true)
            await startPlayback()
            scheduleHUDAutoHide()
        }
        .onDisappear {
            cleanupSession()
        }
        .onChange(of: activeIsPlaying) { _, playing in
            onHUDChromeStateChanged(isHUDVisible, playing)
        }
    }

    private func startPlayback() async {
        do {
            if activeCoreKind == .nativeAVPlayer {
                avEngine.playbackRate = initialPlaybackRate
                try await avEngine.load(source)
                if initialStartSeconds > 0.5 {
                    await avEngine.seek(to: initialStartSeconds, accurate: true)
                }
            } else {
                mpvEngine.playbackRate = initialPlaybackRate
                try await mpvEngine.load(source)
                if initialStartSeconds > 0.5 {
                    await mpvEngine.seek(to: initialStartSeconds, accurate: true)
                }
            }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func togglePlayPause() {
        if activeCoreKind == .nativeAVPlayer {
            activeIsPlaying ? avEngine.pause() : avEngine.play()
        } else {
            activeIsPlaying ? mpvEngine.pause() : mpvEngine.play()
        }
        scheduleHUDAutoHide()
    }

    private func skip(by delta: Double) async {
        if activeCoreKind == .nativeAVPlayer {
            await avEngine.skip(by: delta)
        } else {
            await mpvEngine.skip(by: delta)
        }
        scheduleHUDAutoHide()
    }

    private func seek(to seconds: Double, accurate: Bool) async {
        if activeCoreKind == .nativeAVPlayer {
            await avEngine.seek(to: seconds, accurate: accurate)
        } else {
            await mpvEngine.seek(to: seconds, accurate: accurate)
        }
        scheduleHUDAutoHide()
    }

    private func scheduleHUDAutoHide() {
        hudAutoHideTask?.cancel()
        hudAutoHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.0))
            guard !Task.isCancelled, activeIsPlaying else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isHUDVisible = false
            }
            onHUDChromeStateChanged(false, activeIsPlaying)
        }
    }

    private func closePlayer() {
        cleanupSession()
        onDismiss()
    }

    private func cleanupSession() {
        guard !hasCleanedUp else { return }
        hasCleanedUp = true
        hudAutoHideTask?.cancel()
        hudAutoHideTask = nil
        avEngine.teardown()
        mpvEngine.teardown()
        brightnessVolumeController.endSession()
        orientationController.endPlayerSession()
    }
}
