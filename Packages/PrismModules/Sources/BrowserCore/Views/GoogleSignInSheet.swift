import SwiftUI
import UIKit
import WebKit

public struct GoogleSignInSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let accountManager: GoogleAccountManager
    private let openAccountManagement: Bool
    private let onComplete: @MainActor (String) -> Void

    @State private var currentHost: String = "accounts.google.com"
    @State private var isLoading: Bool = true
    @State private var estimatedProgress: Double = 0.1
    @State private var canGoBack: Bool = false
    @State private var webViewRef: WKWebView?
    @State private var hasHandledCompletion = false

    public init(
        accountManager: GoogleAccountManager = .shared,
        openAccountManagement: Bool = false,
        onComplete: @escaping @MainActor (String) -> Void
    ) {
        self.accountManager = accountManager
        self.openAccountManagement = openAccountManagement
        self.onComplete = onComplete
    }

    private var initialURL: URL {
        if openAccountManagement {
            return URL(string: "https://myaccount.google.com/")!
        }
        return URL(string: "https://accounts.google.com/ServiceLogin?hl=en&continue=https%3A%2F%2Fmyaccount.google.com%2F")!
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView(value: max(0.08, estimatedProgress))
                        .tint(PrismBrandPalette.crimsonAccent)
                }

                GoogleAuthWebView(
                    initialURL: initialURL,
                    onWebViewReady: { webView in
                        webViewRef = webView
                    },
                    onStateUpdate: { host, loading, progress, back in
                        if !host.isEmpty { currentHost = host }
                        isLoading = loading
                        estimatedProgress = progress
                        canGoBack = back
                    },
                    onSignedInDetected: { name, email in
                        guard !openAccountManagement, !hasHandledCompletion else { return }
                        hasHandledCompletion = true
                        accountManager.recordSignedIn(displayName: name, email: email)
                        let label = email?.isEmpty == false ? email! : (name ?? "Google Account")
                        onComplete("Signed in as \(label)")
                        dismiss()
                    }
                )
            }
            .navigationTitle(openAccountManagement ? "Google Account" : "Sign in with Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button("Done") {
                            Task {
                                await accountManager.refreshSessionStatus()
                            }
                            dismiss()
                        }
                        if canGoBack {
                            Button {
                                webViewRef?.goBack()
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(openAccountManagement ? "Google Account" : "Sign in with Google")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text(currentHost)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        webViewRef?.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

private struct GoogleAuthWebView: UIViewRepresentable {
    let initialURL: URL
    let onWebViewReady: @MainActor @Sendable (WKWebView) -> Void
    let onStateUpdate: @MainActor @Sendable (_ host: String, _ isLoading: Bool, _ progress: Double, _ canGoBack: Bool) -> Void
    let onSignedInDetected: @MainActor @Sendable (_ displayName: String?, _ email: String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onStateUpdate: onStateUpdate,
            onSignedInDetected: onSignedInDetected
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Share the browser's persistent data store so signing in logs into all Google services across tabs
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = BrowserEngineDefaults.mobileUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        context.coordinator.observe(webView)
        let readyCallback = onWebViewReady
        Task { @MainActor in
            readyCallback(webView)
        }
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onStateUpdate: @MainActor (String, Bool, Double, Bool) -> Void
        let onSignedInDetected: @MainActor (String?, String?) -> Void
        private var observations: [NSKeyValueObservation] = []

        init(
            onStateUpdate: @escaping @MainActor (String, Bool, Double, Bool) -> Void,
            onSignedInDetected: @escaping @MainActor (String?, String?) -> Void
        ) {
            self.onStateUpdate = onStateUpdate
            self.onSignedInDetected = onSignedInDetected
        }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emit(view)
                    }
                },
                webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emit(view)
                    }
                },
                webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emit(view)
                    }
                },
                webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emit(view)
                    }
                },
            ]
        }

        private func emit(_ webView: WKWebView) {
            onStateUpdate(
                webView.url?.host ?? "",
                webView.isLoading,
                webView.estimatedProgress,
                webView.canGoBack
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            emit(webView)
            guard let host = webView.url?.host?.lowercased() else { return }
            let reachedGoogleAccount = host == "myaccount.google.com"
                || (host == "www.google.com" && (webView.url?.path ?? "").isEmpty)
            guard reachedGoogleAccount else { return }

            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                let hasAuthCookie = cookies.contains { cookie in
                    let dom = cookie.domain.lowercased()
                    return (dom == "google.com" || dom.hasSuffix(".google.com"))
                        && (cookie.name == "SID" || cookie.name == "__Secure-1PSID" || cookie.name == "SAPISID")
                        && !cookie.value.isEmpty
                }
                guard hasAuthCookie else { return }

                // Best-effort extraction of signed-in account name and email from myaccount.google.com
                let extractJS = """
                (() => {
                    try {
                        const text = document.body ? document.body.innerText : '';
                        const emailMatch = text.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}/);
                        const email = emailMatch ? emailMatch[0] : '';
                        let name = '';
                        const h1 = document.querySelector('h1');
                        if (h1 && h1.textContent) {
                            name = h1.textContent.replace(/^Welcome,\\s*/i, '').trim();
                        }
                        return JSON.stringify({ name, email });
                    } catch (_) {
                        return JSON.stringify({ name: '', email: '' });
                    }
                })();
                """

                var extractedName: String?
                var extractedEmail: String?
                if let raw = try? await webView.evaluateJavaScript(extractJS) as? String,
                   let data = raw.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    let n = obj["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let e = obj["email"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    extractedName = n.isEmpty ? nil : n
                    extractedEmail = e.isEmpty ? nil : e
                }

                self.onSignedInDetected(extractedName, extractedEmail)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
