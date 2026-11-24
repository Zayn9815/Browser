import ParallelDownloader
import UIKit

@MainActor
public enum PrismOrientationLockState {
    public static var supportedMask: UIInterfaceOrientationMask = [
        .portrait,
        .landscapeLeft,
        .landscapeRight,
    ]
}

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
        PrismOrientationLockState.supportedMask
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
