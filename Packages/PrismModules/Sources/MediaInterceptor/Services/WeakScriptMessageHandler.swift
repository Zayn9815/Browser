import Foundation
import WebKit

@MainActor
public protocol PrismScriptMessageHandling: AnyObject {
    func handleScriptMessage(_ message: WKScriptMessage, for tabID: UUID)
}

/// Leak-safe WKScriptMessageHandler preventing WKUserContentController -> Coordinator retain cycles.
public final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private let tabID: UUID
    private weak var delegate: (any PrismScriptMessageHandling)?

    public init(tabID: UUID, delegate: any PrismScriptMessageHandling) {
        self.tabID = tabID
        self.delegate = delegate
        super.init()
    }

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.handleScriptMessage(message, for: tabID)
    }
}
