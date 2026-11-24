import AVFoundation
import MediaPlayer
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
public final class BrightnessAndVolumeController {
    public private(set) var currentBrightness: CGFloat = 0.5
    public private(set) var currentVolume: Float = 0.5

    private var savedInitialBrightness: CGFloat?
    fileprivate weak var volumeSlider: UISlider?

    public init() {}

    public func beginSession() {
        if let screen = activeWindowSceneScreen() {
            savedInitialBrightness = screen.brightness
            currentBrightness = screen.brightness
        }
        currentVolume = AVAudioSession.sharedInstance().outputVolume
    }

    public func endSession() {
        if let savedInitialBrightness, let screen = activeWindowSceneScreen() {
            screen.brightness = savedInitialBrightness
        }
        savedInitialBrightness = nil
    }

    public func adjustBrightness(by delta: CGFloat) {
        let next = min(max(currentBrightness + delta, 0.02), 1.0)
        currentBrightness = next
        activeWindowSceneScreen()?.brightness = next
    }

    public func adjustVolume(by delta: Float) {
        let next = min(max(currentVolume + delta, 0.0), 1.0)
        currentVolume = next
        if let slider = volumeSlider {
            slider.setValue(next, animated: false)
            slider.sendActions(for: .touchUpInside)
        }
    }

    private func activeWindowSceneScreen() -> UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return active.screen
        }
        return scenes.first?.screen
    }
}

/// Mounts an offscreen 1x1 MPVolumeView (alpha 0.001) so right-edge volume drags adjust real
/// hardware volume via its internal UISlider while suppressing the iOS system volume HUD.
public struct HiddenSystemVolumeBridge: UIViewRepresentable {
    public let controller: BrightnessAndVolumeController

    public init(controller: BrightnessAndVolumeController) {
        self.controller = controller
    }

    public func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        volumeView.alpha = 0.001
        volumeView.clipsToBounds = true
        volumeView.isUserInteractionEnabled = false
        bindSlider(in: volumeView)
        return volumeView
    }

    public func updateUIView(_ uiView: MPVolumeView, context: Context) {
        if controller.volumeSlider == nil {
            bindSlider(in: uiView)
        }
    }

    private func bindSlider(in volumeView: MPVolumeView) {
        if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
            controller.volumeSlider = slider
        }
    }
}
