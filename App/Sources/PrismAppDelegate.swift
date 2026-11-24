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
    public func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLockController.shared.supportedMask
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
