import Foundation
import Observation
import WebKit

@Observable
@MainActor
public final class FindInPageService {
    public var isPresented = false
    public var query = ""
    public var lastMatchFound: Bool?

    public init() {}

    public func presentNativeFindNavigator(in webView: WKWebView?) {
        guard let webView else { return }
        webView.isFindInteractionEnabled = true
        webView.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    public func findNext(in webView: WKWebView?, backwards: Bool = false) async {
        guard let webView else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastMatchFound = nil
            return
        }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.caseSensitive = false
        config.wraps = true

        do {
            let result = try await webView.find(trimmed, configuration: config)
            lastMatchFound = result.matchFound
        } catch {
            lastMatchFound = false
        }
    }

    public func dismiss() {
        isPresented = false
        query = ""
        lastMatchFound = nil
    }
}
