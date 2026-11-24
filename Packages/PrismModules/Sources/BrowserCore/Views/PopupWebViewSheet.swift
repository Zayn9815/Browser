import SwiftUI
import UIKit
import WebKit

public struct BrowserPopupSession: Identifiable {
    public let id: UUID
    public let webView: WKWebView

    public init(id: UUID = UUID(), webView: WKWebView) {
        self.id = id
        self.webView = webView
    }
}

public struct PopupWebViewSheet: View {
    public let session: BrowserPopupSession
    public let onDismiss: @MainActor () -> Void

    @State private var hostTitle: String = "Sign In"

    public init(
        session: BrowserPopupSession,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.session = session
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            PopupWKWebViewHost(webView: session.webView) { host in
                if !host.isEmpty {
                    hostTitle = host
                }
            }
            .navigationTitle(hostTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.webView.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

private struct PopupWKWebViewHost: UIViewRepresentable {
    let webView: WKWebView
    let onHostChanged: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHostChanged: onHostChanged)
    }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.observe(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator {
        let onHostChanged: @MainActor (String) -> Void
        private var urlObservation: NSKeyValueObservation?

        init(onHostChanged: @escaping @MainActor (String) -> Void) {
            self.onHostChanged = onHostChanged
        }

        func observe(_ webView: WKWebView) {
            if let host = webView.url?.host {
                onHostChanged(host)
            }
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self, weak view] in
                    guard let self, let host = view?.url?.host else { return }
                    self.onHostChanged(host)
                }
            }
        }
    }
}
