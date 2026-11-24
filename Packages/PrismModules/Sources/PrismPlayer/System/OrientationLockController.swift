import Observation
import UIKit

@Observable
@MainActor
public final class OrientationLockController {
    public static let shared = OrientationLockController()

    public private(set) var supportedMask: UIInterfaceOrientationMask = [
        .portrait,
        .landscapeLeft,
        .landscapeRight,
    ]
    public private(set) var isLandscapeLocked: Bool = false

    public init() {}

    public func lockLandscape() {
        isLandscapeLocked = true
        apply(mask: .landscapeRight)
    }

    public func lockPortrait() {
        isLandscapeLocked = false
        apply(mask: .portrait)
    }

    public func toggleOrientation() {
        if isLandscapeLocked {
            lockPortrait()
        } else {
            lockLandscape()
        }
    }

    public func restoreDefaultOrientations() {
        isLandscapeLocked = false
        supportedMask = [.portrait, .landscapeLeft, .landscapeRight]
        requestGeometryUpdate(for: .portrait)
    }

    private func apply(mask: UIInterfaceOrientationMask) {
        supportedMask = mask
        requestGeometryUpdate(for: mask)
    }

    private func requestGeometryUpdate(for mask: UIInterfaceOrientationMask) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            scene.requestGeometryUpdate(preferences) { _ in }
        }
    }
}
