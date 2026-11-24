import SwiftUI

public enum ActivePlayerGestureIndicator: Equatable, Sendable {
    case brightness(Double)
    case volume(Double)
    case scrub(targetSeconds: Double, deltaSeconds: Double, durationSeconds: Double)
    case skip(deltaSeconds: Int)
}

public struct PlayerGestureCanvas: View {
    public let isHUDLocked: Bool
    public let currentTimeSeconds: Double
    public let durationSeconds: Double
    @Bindable public var brightnessVolumeController: BrightnessAndVolumeController
    public let onSingleTap: () -> Void
    public let onTogglePlayPause: () -> Void
    public let onSkip: (Double) -> Void
    public let onScrubCommit: (Double) -> Void
    @Binding public var activeIndicator: ActivePlayerGestureIndicator?

    private enum DragMode {
        case undecided
        case brightness
        case volume
        case scrub
    }

    @State private var dragMode: DragMode = .undecided
    @State private var lastDragTranslation: CGSize = .zero
    @State private var scrubStartSeconds: Double = 0
    @State private var scrubPreviewSeconds: Double = 0
    @State private var lastScrubTickBucket: Int = 0
    @State private var scrubTickCounter: Int = 0
    @State private var skipHapticCounter: Int = 0
    @State private var skipBadgeClearTask: Task<Void, Never>?

    public init(
        isHUDLocked: Bool,
        currentTimeSeconds: Double,
        durationSeconds: Double,
        brightnessVolumeController: BrightnessAndVolumeController,
        activeIndicator: Binding<ActivePlayerGestureIndicator?>,
        onSingleTap: @escaping () -> Void,
        onTogglePlayPause: @escaping () -> Void,
        onSkip: @escaping (Double) -> Void,
        onScrubCommit: @escaping (Double) -> Void
    ) {
        self.isHUDLocked = isHUDLocked
        self.currentTimeSeconds = currentTimeSeconds
        self.durationSeconds = durationSeconds
        self.brightnessVolumeController = brightnessVolumeController
        self._activeIndicator = activeIndicator
        self.onSingleTap = onSingleTap
        self.onTogglePlayPause = onTogglePlayPause
        self.onSkip = onSkip
        self.onScrubCommit = onScrubCommit
    }

    public var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { value in
                            guard !isHUDLocked else {
                                onSingleTap()
                                return
                            }
                            handleDoubleTap(at: value.location, in: geo.size)
                        }
                        .exclusively(
                            before: TapGesture(count: 1)
                                .onEnded {
                                    onSingleTap()
                                }
                        )
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard !isHUDLocked else { return }
                            handleDragChanged(value, in: geo.size)
                        }
                        .onEnded { _ in
                            guard !isHUDLocked else { return }
                            handleDragEnded()
                        }
                )
        }
        .sensoryFeedback(.selection, trigger: scrubTickCounter)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: skipHapticCounter)
    }

    private func handleDoubleTap(at location: CGPoint, in size: CGSize) {
        let ratio = size.width > 0 ? (location.x / size.width) : 0.5
        if ratio < 0.35 {
            skipHapticCounter += 1
            onSkip(-10)
            flashSkipBadge(-10)
        } else if ratio > 0.65 {
            skipHapticCounter += 1
            onSkip(10)
            flashSkipBadge(10)
        } else {
            skipHapticCounter += 1
            onTogglePlayPause()
        }
    }

    private func flashSkipBadge(_ delta: Int) {
        activeIndicator = .skip(deltaSeconds: delta)
        skipBadgeClearTask?.cancel()
        skipBadgeClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            if case .skip = activeIndicator {
                activeIndicator = nil
            }
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
        if dragMode == .undecided {
            let dx = abs(value.translation.width)
            let dy = abs(value.translation.height)
            if dx > dy && dx > 12 {
                dragMode = .scrub
                scrubStartSeconds = currentTimeSeconds
                scrubPreviewSeconds = currentTimeSeconds
                lastScrubTickBucket = Int(currentTimeSeconds / 5.0)
            } else if dy >= dx && dy > 12 {
                let startRatio = size.width > 0 ? (value.startLocation.x / size.width) : 0.5
                dragMode = startRatio < 0.5 ? .brightness : .volume
            }
            lastDragTranslation = value.translation
            return
        }

        let stepDY = value.translation.height - lastDragTranslation.height
        lastDragTranslation = value.translation

        switch dragMode {
        case .brightness:
            let sensitivity = max(size.height * 0.65, 180)
            brightnessVolumeController.adjustBrightness(by: -stepDY / sensitivity)
            activeIndicator = .brightness(Double(brightnessVolumeController.currentBrightness))

        case .volume:
            let sensitivity = max(size.height * 0.65, 180)
            brightnessVolumeController.adjustVolume(by: Float(-stepDY / sensitivity))
            activeIndicator = .volume(Double(brightnessVolumeController.currentVolume))

        case .scrub:
            let spanSeconds = min(max(durationSeconds * 0.45, 60), 240)
            let width = max(size.width, 300)
            let delta = Double(value.translation.width / width) * spanSeconds
            let maxDur = durationSeconds > 0 ? durationSeconds : max(scrubStartSeconds + 300, 300)
            let target = min(max(0, scrubStartSeconds + delta), maxDur)
            scrubPreviewSeconds = target
            let bucket = Int(target / 5.0)
            if bucket != lastScrubTickBucket {
                lastScrubTickBucket = bucket
                scrubTickCounter += 1
            }
            activeIndicator = .scrub(
                targetSeconds: target,
                deltaSeconds: target - scrubStartSeconds,
                durationSeconds: durationSeconds
            )

        case .undecided:
            break
        }
    }

    private func handleDragEnded() {
        if dragMode == .scrub {
            onScrubCommit(scrubPreviewSeconds)
        }
        dragMode = .undecided
        lastDragTranslation = .zero
        activeIndicator = nil
    }
}
