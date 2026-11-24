import SwiftUI
import UIKit
import WebKit

public struct PrismWebViewRepresentable: UIViewRepresentable {
    public let webView: WKWebView
    public let onStateChanged: @MainActor (WebViewObservableUpdate) -> Void
    public let onScrollDirectionChanged: @MainActor (_ isScrollingDown: Bool) -> Void

    public init(
        webView: WKWebView,
        onStateChanged: @escaping @MainActor (WebViewObservableUpdate) -> Void,
        onScrollDirectionChanged: @escaping @MainActor (_ isScrollingDown: Bool) -> Void
    ) {
        self.webView = webView
        self.onStateChanged = onStateChanged
        self.onScrollDirectionChanged = onScrollDirectionChanged
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            onStateChanged: onStateChanged,
            onScrollDirectionChanged: onScrollDirectionChanged
        )
    }

    public func makeUIView(context: Context) -> WebViewContainerUIView {
        let container = WebViewContainerUIView()
        container.backgroundColor = UIColor(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 15.0 / 255.0, alpha: 1.0)
        context.coordinator.bind(webView: webView, into: container)
        return container
    }

    public func updateUIView(_ uiView: WebViewContainerUIView, context: Context) {
        context.coordinator.onStateChanged = onStateChanged
        context.coordinator.onScrollDirectionChanged = onScrollDirectionChanged
        if context.coordinator.boundWebView !== webView {
            context.coordinator.bind(webView: webView, into: uiView)
        }
    }

    public static func dismantleUIView(_ uiView: WebViewContainerUIView, coordinator: Coordinator) {
        coordinator.unbind()
    }

    public final class WebViewContainerUIView: UIView {
        public weak var hostedWebView: WKWebView?

        public override func layoutSubviews() {
            super.layoutSubviews()
            hostedWebView?.frame = bounds
        }
    }

    @MainActor
    public final class Coordinator: NSObject, UIScrollViewDelegate {
        public var onStateChanged: @MainActor (WebViewObservableUpdate) -> Void
        public var onScrollDirectionChanged: @MainActor (_ isScrollingDown: Bool) -> Void
        public private(set) weak var boundWebView: WKWebView?

        private var observations: [NSKeyValueObservation] = []
        private var lastScrollOffsetY: CGFloat = 0
        private var lastEmittedSnapshot: WebViewObservableUpdate?

        public init(
            onStateChanged: @escaping @MainActor (WebViewObservableUpdate) -> Void,
            onScrollDirectionChanged: @escaping @MainActor (_ isScrollingDown: Bool) -> Void
        ) {
            self.onStateChanged = onStateChanged
            self.onScrollDirectionChanged = onScrollDirectionChanged
        }

        public func bind(webView: WKWebView, into container: WebViewContainerUIView) {
            unbind()

            if let previous = container.hostedWebView, previous !== webView {
                previous.removeFromSuperview()
            }
            if webView.superview !== container {
                webView.removeFromSuperview()
                webView.frame = container.bounds
                webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(webView)
            }
            container.hostedWebView = webView
            boundWebView = webView
            lastScrollOffsetY = webView.scrollView.contentOffset.y
            webView.scrollView.delegate = self

            observations = [
                webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emitSnapshot(from: view)
                    }
                },
                webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emitSnapshot(from: view)
                    }
                },
                webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emitSnapshot(from: view)
                    }
                },
                webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emitSnapshot(from: view)
                    }
                },
                webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emitSnapshot(from: view)
                    }
                },
                webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emitSnapshot(from: view)
                    }
                },
                webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view else { return }
                        self.emitSnapshot(from: view)
                    }
                },
            ]

            emitSnapshot(from: webView)
        }

        public func unbind() {
            observations.forEach { $0.invalidate() }
            observations.removeAll()
            lastEmittedSnapshot = nil
            if boundWebView?.scrollView.delegate === self {
                boundWebView?.scrollView.delegate = nil
            }
            boundWebView = nil
        }

        private func emitSnapshot(from webView: WKWebView) {
            let next = WebViewObservableUpdate(
                title: webView.title ?? "",
                urlString: webView.url?.absoluteString ?? "",
                isLoading: webView.isLoading,
                estimatedProgress: webView.estimatedProgress,
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward,
                hasOnlySecureContent: webView.hasOnlySecureContent
            )
            if let prev = lastEmittedSnapshot {
                let onlyProgressChanged = prev.title == next.title
                    && prev.urlString == next.urlString
                    && prev.isLoading == next.isLoading
                    && prev.canGoBack == next.canGoBack
                    && prev.canGoForward == next.canGoForward
                    && prev.hasOnlySecureContent == next.hasOnlySecureContent
                if onlyProgressChanged
                    && abs(next.estimatedProgress - prev.estimatedProgress) < 0.04
                    && next.estimatedProgress < 0.99
                    && next.estimatedProgress > 0.01 {
                    return
                }
                if prev == next {
                    return
                }
            }
            lastEmittedSnapshot = next
            onStateChanged(next)
        }

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let offsetY = scrollView.contentOffset.y
            let delta = offsetY - lastScrollOffsetY
            if offsetY <= 8 {
                onScrollDirectionChanged(false)
                lastScrollOffsetY = offsetY
                return
            }
            if delta > 18 {
                onScrollDirectionChanged(true)
                lastScrollOffsetY = offsetY
            } else if delta < -14 {
                onScrollDirectionChanged(false)
                lastScrollOffsetY = offsetY
            }
        }
    }
}

public struct WebViewObservableUpdate: Sendable, Equatable {
    public let title: String
    public let urlString: String
    public let isLoading: Bool
    public let estimatedProgress: Double
    public let canGoBack: Bool
    public let canGoForward: Bool
    public let hasOnlySecureContent: Bool

    public init(
        title: String,
        urlString: String,
        isLoading: Bool,
        estimatedProgress: Double,
        canGoBack: Bool,
        canGoForward: Bool,
        hasOnlySecureContent: Bool
    ) {
        self.title = title
        self.urlString = urlString
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.hasOnlySecureContent = hasOnlySecureContent
    }
}
