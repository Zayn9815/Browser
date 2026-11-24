import Foundation
import Observation
import WebKit

@MainActor
public protocol TrackerTelemetryReceiver: AnyObject {
    func trackerShieldDidRecordBlockedResources(tabID: UUID, host: String, delta: Int)
}

public final class WeakTrackerMessageHandler: NSObject, WKScriptMessageHandler {
    private let tabID: UUID
    private weak var receiver: (any TrackerTelemetryReceiver)?

    public init(tabID: UUID, receiver: any TrackerTelemetryReceiver) {
        self.tabID = tabID
        self.receiver = receiver
        super.init()
    }

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let delta = body["delta"] as? Int,
              delta > 0 else {
            return
        }
        let host = (body["host"] as? String) ?? ""
        receiver?.trackerShieldDidRecordBlockedResources(tabID: tabID, host: host, delta: delta)
    }
}

@Observable
@MainActor
public final class TrackerShieldMonitor: TrackerTelemetryReceiver {
    public static let messageHandlerName = "prismTrackerTelemetry"

    public private(set) var blockedCountByTab: [UUID: Int] = [:]
    public private(set) var sessionTotalBlocked: Int = 0

    public init() {}

    public static func makeTelemetryUserScript() -> WKUserScript? {
        guard let url = Bundle.module.url(forResource: "TrackerTelemetry.user", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        )
    }

    public func attach(to userContentController: WKUserContentController, tabID: UUID) {
        if let script = Self.makeTelemetryUserScript() {
            userContentController.addUserScript(script)
        }
        let handler = WeakTrackerMessageHandler(tabID: tabID, receiver: self)
        userContentController.add(handler, contentWorld: .defaultClient, name: Self.messageHandlerName)
    }

    public func resetCount(for tabID: UUID) {
        blockedCountByTab[tabID] = 0
    }

    public func removeTab(_ tabID: UUID) {
        blockedCountByTab.removeValue(forKey: tabID)
    }

    public func count(for tabID: UUID) -> Int {
        blockedCountByTab[tabID] ?? 0
    }

    public func trackerShieldDidRecordBlockedResources(tabID: UUID, host: String, delta: Int) {
        blockedCountByTab[tabID, default: 0] += delta
        sessionTotalBlocked += delta
    }
}
