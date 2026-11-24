import Foundation
import ParallelDownloader
import UIKit
import WebKit

public enum BrowserDialogRequest: Identifiable {
    case jsAlert(id: UUID, host: String, message: String, onDismiss: @MainActor () -> Void)
    case jsConfirm(id: UUID, host: String, message: String, onDecision: @MainActor (Bool) -> Void)
    case jsPrompt(id: UUID, host: String, prompt: String, defaultText: String, onSubmit: @MainActor (String?) -> Void)
    case httpAuth(id: UUID, host: String, realm: String, onSubmit: @MainActor (String?, String?) -> Void)

    public var id: UUID {
        switch self {
        case .jsAlert(let id, _, _, _): return id
        case .jsConfirm(let id, _, _, _): return id
        case .jsPrompt(let id, _, _, _, _): return id
        case .httpAuth(let id, _, _, _): return id
        }
    }
}

@MainActor
public protocol WebViewNavigationEventDelegate: AnyObject {
    var currentSettingsSnapshot: BrowserSettingsSnapshot { get }
    func navigationDidStartLoad(tabID: UUID, url: URL?)
    func navigationDidCommit(tabID: UUID, url: URL?, title: String?)
    func navigationDidFinish(tabID: UUID, url: URL?, title: String?)
    func navigationDidFail(tabID: UUID, error: Error)
    func navigationDidRequestNewTab(url: URL, isIncognito: Bool)
    func navigationDidRequestPopup(_ session: BrowserPopupSession)
    func navigationDidClosePopup(webView: WKWebView)
    func navigationDidBlockPopup(tabID: UUID)
    func navigationDidRequestDialog(_ dialog: BrowserDialogRequest)
    func navigationDidInterceptDownload(
        tabID: UUID,
        url: URL,
        suggestedFilename: String?,
        mimeType: String?,
        sessionContext: BrowserSessionContext
    )
    func navigationDidRecoverFromContentProcessTermination(tabID: UUID)
}

@MainActor
public final class WebViewNavigationCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private let tabID: UUID
    private let isIncognito: Bool
    private weak var eventDelegate: (any WebViewNavigationEventDelegate)?
    private weak var trackedWebView: WKWebView?

    private var downloadMetadataByTask: [ObjectIdentifier: (suggestedFilename: String?, mimeType: String?)] = [:]
    private var crashTimestamps: [Date] = []
    private var upgradedHTTPRequests: [String: URL] = [:]
    private var httpsFallbackHosts: Set<String> = []

    public init(
        tabID: UUID,
        isIncognito: Bool,
        eventDelegate: any WebViewNavigationEventDelegate
    ) {
        self.tabID = tabID
        self.isIncognito = isIncognito
        self.eventDelegate = eventDelegate
        super.init()
    }

    public func attach(to webView: WKWebView) {
        trackedWebView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    // MARK: - WKNavigationDelegate

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            return .allow
        }

        let settings = eventDelegate?.currentSettingsSnapshot ?? BrowserSettingsSnapshot()
        let scheme = url.scheme?.lowercased() ?? ""
        if ["tel", "mailto", "sms", "facetime"].contains(scheme) {
            if settings.openExternalAppLinks {
                await UIApplication.shared.open(url)
            }
            return .cancel
        }

        if navigationAction.shouldPerformDownload {
            return .download
        }

        // Main-frame privacy & security URL transformations (tracking param stripping + HTTPS-Only upgrade)
        if navigationAction.targetFrame?.isMainFrame == true,
           ["http", "https"].contains(scheme),
           (navigationAction.request.httpMethod ?? "GET").uppercased() == "GET" {
            var transformed = url
            if settings.stripTrackingParameters {
                transformed = URLTrackingSanitizer.sanitize(transformed)
            }
            let host = (transformed.host ?? "").lowercased()
            if settings.httpsOnlyEnabled && transformed.scheme?.lowercased() == "http" && !httpsFallbackHosts.contains(host) {
                let upgraded = URLTrackingSanitizer.upgradeToHTTPSIfNeeded(transformed, enabled: true)
                if upgraded != transformed {
                    upgradedHTTPRequests[upgraded.absoluteString] = transformed
                    transformed = upgraded
                }
            }
            if transformed != url {
                var newRequest = navigationAction.request
                newRequest.url = transformed
                webView.load(newRequest)
                return .cancel
            }
        }

        // Handle target="_blank" links cleanly by spawning a new tab (or blocking script popups)
        if navigationAction.targetFrame == nil, ["http", "https"].contains(scheme) {
            if settings.blockPopups && navigationAction.navigationType == .other && !Self.isLikelyAuthPopup(url: url) {
                eventDelegate?.navigationDidBlockPopup(tabID: tabID)
                return .cancel
            }
            eventDelegate?.navigationDidRequestNewTab(url: url, isIncognito: isIncognito)
            return .cancel
        }

        return .allow
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            let disposition = (httpResponse.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
            if disposition.contains("attachment") {
                return .download
            }
        }

        if !navigationResponse.canShowMIMEType {
            return .download
        }

        let mime = (navigationResponse.response.mimeType ?? "").lowercased()
        let downloadableMIMEs = [
            "application/octet-stream",
            "application/zip",
            "application/x-rar-compressed",
            "application/x-7z-compressed",
            "application/gzip",
            "application/x-tar",
            "application/vnd.android.package-archive",
            "application/x-apple-diskimage",
        ]
        if downloadableMIMEs.contains(mime) {
            return .download
        }

        return .allow
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        eventDelegate?.navigationDidStartLoad(tabID: tabID, url: webView.url)
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let current = webView.url?.absoluteString {
            upgradedHTTPRequests.removeValue(forKey: current)
        }
        eventDelegate?.navigationDidCommit(tabID: tabID, url: webView.url, title: webView.title)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        eventDelegate?.navigationDidFinish(tabID: tabID, url: webView.url, title: webView.title)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        eventDelegate?.navigationDidFail(tabID: tabID, error: error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        // WebKit emits error code 102 ("Frame load interrupted") when handing off to WKDownload
        if nsError.code == NSURLErrorCancelled || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102) {
            return
        }

        // Graceful HTTP fallback if an automatic HTTPS-Only upgrade failed TLS/connection
        if let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView.url,
           let originalHTTP = upgradedHTTPRequests.removeValue(forKey: failingURL.absoluteString) {
            if let host = originalHTTP.host?.lowercased() {
                httpsFallbackHosts.insert(host)
            }
            webView.load(URLRequest(url: originalHTTP))
            return
        }

        eventDelegate?.navigationDidFail(tabID: tabID, error: error)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let now = Date.now
        crashTimestamps = crashTimestamps.filter { now.timeIntervalSince($0) < 10.0 }
        guard crashTimestamps.count < 2 else { return }
        crashTimestamps.append(now)
        webView.reload()
        eventDelegate?.navigationDidRecoverFromContentProcessTermination(tabID: tabID)
    }

    public func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest else {
            return (.performDefaultHandling, nil)
        }

        let host = challenge.protectionSpace.host
        let realm = challenge.protectionSpace.realm ?? host
        let credentials: (String?, String?) = await withCheckedContinuation { continuation in
            var resumed = false
            let dialog = BrowserDialogRequest.httpAuth(id: UUID(), host: host, realm: realm) { user, pass in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: (user, pass))
            }
            if let eventDelegate {
                eventDelegate.navigationDidRequestDialog(dialog)
            } else {
                resumed = true
                continuation.resume(returning: (nil, nil))
            }
        }

        if let user = credentials.0, let pass = credentials.1 {
            return (.useCredential, URLCredential(user: user, password: pass, persistence: .forSession))
        }
        return (.cancelAuthenticationChallenge, nil)
    }

    // MARK: - WKDownloadDelegate Handoff to ParallelDownloader

    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        handoffDownloadToParallelEngine(download, webView: webView, suggestedFilename: nil, mimeType: nil)
    }

    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        let suggested = navigationResponse.response.suggestedFilename
        let mime = navigationResponse.response.mimeType
        downloadMetadataByTask[ObjectIdentifier(download)] = (suggested, mime)
        handoffDownloadToParallelEngine(download, webView: webView, suggestedFilename: suggested, mimeType: mime)
    }

    public func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        // Already handed off to ParallelDownloader; cancel WebKit internal transfer cleanly
        let key = ObjectIdentifier(download)
        if downloadMetadataByTask[key] == nil, let webView = trackedWebView {
            handoffDownloadToParallelEngine(
                download,
                webView: webView,
                suggestedFilename: suggestedFilename,
                mimeType: response.mimeType
            )
        }
        downloadMetadataByTask.removeValue(forKey: key)
        return nil
    }

    private func handoffDownloadToParallelEngine(
        _ download: WKDownload,
        webView: WKWebView,
        suggestedFilename: String?,
        mimeType: String?
    ) {
        guard let targetURL = download.originalRequest?.url else {
            download.cancel()
            return
        }

        let pageURL = webView.url
        let userAgent = webView.customUserAgent ?? BrowserEngineDefaults.mobileUserAgent
        let origin: String? = {
            guard let pageURL, let scheme = pageURL.scheme, let host = pageURL.host else { return nil }
            if let port = pageURL.port {
                return "\(scheme)://\(host):\(port)"
            }
            return "\(scheme)://\(host)"
        }()

        // Cancel WebKit's internal single-threaded transfer and hand off to SDMCore / ParallelDownloader
        download.cancel()

        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            let rawCookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let matchingCookies = rawCookies
                .map(BrowserCookieSnapshot.init(httpCookie:))
                .filter { $0.matches(url: targetURL) }

            let context = BrowserSessionContext(
                cookies: matchingCookies,
                userAgent: userAgent,
                pageReferer: pageURL,
                origin: origin,
                mimeType: mimeType,
                suggestedFilename: suggestedFilename,
                isIncognito: self.isIncognito
            )

            self.eventDelegate?.navigationDidInterceptDownload(
                tabID: self.tabID,
                url: targetURL,
                suggestedFilename: suggestedFilename,
                mimeType: mimeType,
                sessionContext: context
            )
        }
    }

    // MARK: - WKUIDelegate

    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let settings = eventDelegate?.currentSettingsSnapshot ?? BrowserSettingsSnapshot()
        let url = navigationAction.request.url
        let isAuthFlow = Self.isLikelyAuthPopup(url: url)
        let hasExplicitPopupDimensions = (windowFeatures.width != nil || windowFeatures.height != nil)

        // Preserve window.opener for OAuth ("Sign in with Google", Apple, GitHub, Firebase) popups
        if isAuthFlow || (hasExplicitPopupDimensions && (url == nil || url?.absoluteString == "about:blank")) {
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.customUserAgent = webView.customUserAgent ?? BrowserEngineDefaults.mobileUserAgent
            popupWebView.allowsBackForwardNavigationGestures = true
            popupWebView.isOpaque = true
            popupWebView.backgroundColor = .systemBackground
            popupWebView.uiDelegate = self
            eventDelegate?.navigationDidRequestPopup(BrowserPopupSession(webView: popupWebView))
            return popupWebView
        }

        if settings.blockPopups && navigationAction.navigationType == .other {
            eventDelegate?.navigationDidBlockPopup(tabID: tabID)
            return nil
        }

        if let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            eventDelegate?.navigationDidRequestNewTab(url: url, isIncognito: isIncognito)
        }
        return nil
    }

    public func webViewDidClose(_ webView: WKWebView) {
        eventDelegate?.navigationDidClosePopup(webView: webView)
    }

    private static func isLikelyAuthPopup(url: URL?) -> Bool {
        guard let url else { return false }
        let host = (url.host ?? "").lowercased()
        let full = url.absoluteString.lowercased()
        let authHosts = [
            "accounts.google.com",
            "accounts.youtube.com",
            "appleid.apple.com",
            "login.microsoftonline.com",
            "login.live.com",
            "github.com",
            "discord.com",
            "twitter.com",
            "x.com",
            "facebook.com",
        ]
        if authHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            if host.contains("accounts.google.") || host.contains("appleid.apple.") || host.contains("login.microsoftonline.") {
                return true
            }
            if full.contains("oauth") || full.contains("login") || full.contains("signin") || full.contains("authorize") {
                return true
            }
        }
        return full.contains("/oauth") || full.contains("oauth2") || full.contains("openid")
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        let host = frame.securityOrigin.host.isEmpty ? (webView.url?.host ?? "Page") : frame.securityOrigin.host
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            let dialog = BrowserDialogRequest.jsAlert(id: UUID(), host: host, message: message) {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            if let eventDelegate {
                eventDelegate.navigationDidRequestDialog(dialog)
            } else {
                resumed = true
                continuation.resume()
            }
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        let host = frame.securityOrigin.host.isEmpty ? (webView.url?.host ?? "Page") : frame.securityOrigin.host
        return await withCheckedContinuation { continuation in
            var resumed = false
            let dialog = BrowserDialogRequest.jsConfirm(id: UUID(), host: host, message: message) { confirmed in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: confirmed)
            }
            if let eventDelegate {
                eventDelegate.navigationDidRequestDialog(dialog)
            } else {
                resumed = true
                continuation.resume(returning: false)
            }
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        let host = frame.securityOrigin.host.isEmpty ? (webView.url?.host ?? "Page") : frame.securityOrigin.host
        return await withCheckedContinuation { continuation in
            var resumed = false
            let dialog = BrowserDialogRequest.jsPrompt(
                id: UUID(),
                host: host,
                prompt: prompt,
                defaultText: defaultText ?? ""
            ) { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }
            if let eventDelegate {
                eventDelegate.navigationDidRequestDialog(dialog)
            } else {
                resumed = true
                continuation.resume(returning: nil)
            }
        }
    }
}
