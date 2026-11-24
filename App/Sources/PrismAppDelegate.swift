import ParallelDownloader
import PrismPlayer
import UIKit

private final class BackgroundCompletionBox: @unchecked Sendable {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @MainActor
    func invoke() {
        handler()
    }
}

@MainActor
public final class PrismAppDelegate: NSObject, UIApplicationDelegate {
    public static var orientationMask: UIInterfaceOrientationMask {
        get { OrientationLockController.shared.supportedMask }
        set {
            if newValue == .portrait {
                OrientationLockController.shared.lockPortrait()
            } else if newValue == .landscapeRight || newValue == .landscapeLeft || newValue == .landscape {
                OrientationLockController.shared.lockLandscape()
            } else {
                OrientationLockController.shared.restoreDefaultOrientations()
            }
        }
    }

    public func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }

    public func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let box = BackgroundCompletionBox(completionHandler)
        ParallelDownloadBackgroundRelay.handleEvents(identifier: identifier) {
            Task { @MainActor in
                box.invoke()
            }
        }
    }
}
