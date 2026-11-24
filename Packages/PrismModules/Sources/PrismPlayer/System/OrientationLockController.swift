import Observation
import UIKit

@Observable
@MainActor
public final class OrientationLockController {
    public static let shared = OrientationLockController()

    public private(set) var supportedMask: UIInterfaceOrientationMask = .allButUpsideDown
    public private(set) var isLandscapeLocked: Bool = false
    public private(set) var hasActiveOrientationOverride: Bool = false

    private var restoreMaskTask: Task<Void, Never>?

    public init() {}

    /// Reflects the real current interface orientation of the active window scene.
    public var isCurrentlyLandscape: Bool {
        if hasActiveOrientationOverride {
            return isLandscapeLocked
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.effectiveGeometry.interfaceOrientation.isLandscape ?? false
    }

    public func beginPlayerSession(autoLockLandscape: Bool) {
        restoreMaskTask?.cancel()
        restoreMaskTask = nil

        if autoLockLandscape {
            lockLandscape()
        } else {
            hasActiveOrientationOverride = false
            isLandscapeLocked = false
            supportedMask = .allButUpsideDown
            notifySupportedOrientationsChanged()
        }
    }

    public func endPlayerSession() {
        restoreMaskTask?.cancel()
        restoreMaskTask = nil

        let needsPortraitRecovery = hasActiveOrientationOverride || isLandscapeLocked || isCurrentlyLandscape
        hasActiveOrientationOverride = false
        isLandscapeLocked = false

        if needsPortraitRecovery {
            supportedMask = .portrait
            notifySupportedOrientationsChanged()
            requestGeometryUpdate(for: .portrait)

            // After fullScreenCover dismissal settles, widen supportedMask back to .allButUpsideDown
            // WITHOUT calling requestGeometryUpdate so the app shell stays upright.
            restoreMaskTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(320))
                guard let self, !Task.isCancelled else { return }
                self.supportedMask = .allButUpsideDown
                self.notifySupportedOrientationsChanged()
            }
        } else {
            supportedMask = .allButUpsideDown
            notifySupportedOrientationsChanged()
        }
    }

    public func lockLandscape() {
        restoreMaskTask?.cancel()
        restoreMaskTask = nil
        hasActiveOrientationOverride = true
        isLandscapeLocked = true
        supportedMask = .landscapeRight
        notifySupportedOrientationsChanged()
        requestGeometryUpdate(for: .landscapeRight)
    }

    public func lockPortrait() {
        restoreMaskTask?.cancel()
        restoreMaskTask = nil
        hasActiveOrientationOverride = true
        isLandscapeLocked = false
        supportedMask = .portrait
        notifySupportedOrientationsChanged()
        requestGeometryUpdate(for: .portrait)
    }

    public func toggleOrientation() {
        if isCurrentlyLandscape {
            lockPortrait()
        } else {
            lockLandscape()
        }
    }

    public func restoreDefaultOrientations() {
        endPlayerSession()
    }

    private func notifySupportedOrientationsChanged() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                var currentVC = window.rootViewController
                while let vc = currentVC {
                    vc.setNeedsUpdateOfSupportedInterfaceOrientations()
                    currentVC = vc.presentedViewController
                }
            }
        }
    }

    private func requestGeometryUpdate(for mask: UIInterfaceOrientationMask) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            scene.requestGeometryUpdate(preferences) { _ in }
        }
    }
}
