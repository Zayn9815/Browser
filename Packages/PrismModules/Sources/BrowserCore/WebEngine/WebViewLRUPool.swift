import AdBlockEngine
import Foundation
import UIKit
import WebKit

@MainActor
public final class WebViewLRUPool {
    public let maxLiveWebViews: Int
    public var configureAdditionalScripts: ((WKUserContentController, UUID) -> Void)?

    private var liveWebViews: [UUID: WKWebView] = [:]
    private var coordinators: [UUID: WebViewNavigationCoordinator] = [:]
    private var accessOrder: [UUID] = []

    /// Ephemeral RAM-only caches for Incognito tabs (purged immediately on Private Vault lock)
    private var incognitoInteractionStates: [UUID: Data] = [:]
    private var incognitoSnapshots: [UUID: Data] = [:]

    private let statesDirectory: URL
    private let snapshotsDirectory: URL
    private let adBlockCompiler: AdBlockRuleCompiler
    private let trackerMonitor: TrackerShieldMonitor
    private var memoryWarningObserver: NSObjectProtocol?

    public init(
        maxLiveWebViews: Int = BrowserEngineDefaults.maxLiveWebViews,
        adBlockCompiler: AdBlockRuleCompiler = .shared,
        trackerMonitor: TrackerShieldMonitor
    ) {
        self.maxLiveWebViews = max(1, maxLiveWebViews)
        self.adBlockCompiler = adBlockCompiler
        self.trackerMonitor = trackerMonitor

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.statesDirectory = caches.appendingPathComponent("TabStates", isDirectory: true)
        self.snapshotsDirectory = caches.appendingPathComponent("TabSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: statesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)

        self.memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evictAllInactiveOnMemoryWarning()
            }
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    public var liveTabCount: Int {
        liveWebViews.count
    }

    public func existingWebView(for tabID: UUID) -> WKWebView? {
        liveWebViews[tabID]
    }

    /// Lazily instantiates a `WKWebView` only when the tab becomes active; never preloads inactive tabs.
    public func webView(
        for tab: BrowserTabState,
        globalDarkMode: Bool,
        allowlistedHosts: Set<String>,
        delegate: any WebViewNavigationEventDelegate
    ) -> WKWebView {
        if let existing = liveWebViews[tab.id] {
            touchLRU(tab.id)
            return existing
        }

        // Enforce strict 4-tab live WebView cap before creating a new instance
        while liveWebViews.count >= maxLiveWebViews, let victimID = accessOrder.first(where: { $0 != tab.id }) {
            evict(tabID: victimID, isIncognito: isTabIncognito(victimID))
        }

        let config = makeConfiguration(
            tabID: tab.id,
            isIncognito: tab.isIncognito,
            initialDarkMode: tab.darkModeOverride ?? globalDarkMode
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isFindInteractionEnabled = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 15.0 / 255.0, alpha: 1.0)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.customUserAgent = tab.preferDesktopUserAgent
            ? BrowserEngineDefaults.desktopUserAgent
            : BrowserEngineDefaults.mobileUserAgent

        let coordinator = WebViewNavigationCoordinator(
            tabID: tab.id,
            isIncognito: tab.isIncognito,
            eventDelegate: delegate
        )
        coordinator.attach(to: webView)

        liveWebViews[tab.id] = webView
        coordinators[tab.id] = coordinator
        touchLRU(tab.id)

        // Apply offline sharded AdBlock rules asynchronously
        let siteHost = tab.currentURL?.host?.lowercased()
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            await self.adBlockCompiler.apply(
                to: webView.configuration.userContentController,
                siteHost: siteHost,
                allowlistedHosts: allowlistedHosts
            )
        }

        // Restore serialized interactionState if hibernated previously, else load current URL
        if let stateData = loadInteractionState(for: tab.id, isIncognito: tab.isIncognito) {
            webView.interactionState = stateData
        } else if let url = tab.currentURL {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    public func captureSnapshotAndState(for tabID: UUID, isIncognito: Bool) async -> UIImage? {
        guard let webView = liveWebViews[tabID] else {
            return loadSnapshotImage(for: tabID, isIncognito: isIncognito)
        }

        if let data = webView.interactionState as? Data {
            saveInteractionState(data, for: tabID, isIncognito: isIncognito)
        }

        let snapConfig = WKSnapshotConfiguration()
        snapConfig.snapshotWidth = NSNumber(value: 360)
        do {
            let image = try await webView.takeSnapshot(with: snapConfig)
            let resized = downscaleSnapshot(image, targetSize: CGSize(width: 360, height: 640))
            if let jpeg = resized.jpegData(compressionQuality: 0.72) {
                saveSnapshotData(jpeg, for: tabID, isIncognito: isIncognito)
            }
            return resized
        } catch {
            return loadSnapshotImage(for: tabID, isIncognito: isIncognito)
        }
    }

    public func loadSnapshotImage(for tabID: UUID, isIncognito: Bool) -> UIImage? {
        if isIncognito {
            guard let data = incognitoSnapshots[tabID] else { return nil }
            return UIImage(data: data)
        }
        let url = snapshotURL(for: tabID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Hibernates a tab synchronously (persisting `interactionState`) and tears down its `WKWebView` cleanly.
    public func evict(tabID: UUID, isIncognito: Bool) {
        guard let webView = liveWebViews.removeValue(forKey: tabID) else { return }
        coordinators.removeValue(forKey: tabID)
        accessOrder.removeAll { $0 == tabID }

        if let stateData = webView.interactionState as? Data {
            saveInteractionState(stateData, for: tabID, isIncognito: isIncognito)
        }

        // Capture best-effort off-thread snapshot if view has bounds before tearing down
        if webView.bounds.width > 10, webView.bounds.height > 10 {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 640))
            let img = renderer.image { _ in
                webView.drawHierarchy(in: CGRect(x: 0, y: 0, width: 360, height: 640), afterScreenUpdates: false)
            }
            if let jpeg = img.jpegData(compressionQuality: 0.68) {
                saveSnapshotData(jpeg, for: tabID, isIncognito: isIncognito)
            }
        }

        teardownWebView(webView)
    }

    public func closeTab(tabID: UUID, isIncognito: Bool) {
        if let webView = liveWebViews.removeValue(forKey: tabID) {
            teardownWebView(webView)
        }
        coordinators.removeValue(forKey: tabID)
        accessOrder.removeAll { $0 == tabID }
        trackerMonitor.removeTab(tabID)

        if isIncognito {
            incognitoInteractionStates.removeValue(forKey: tabID)
            incognitoSnapshots.removeValue(forKey: tabID)
        } else {
            try? FileManager.default.removeItem(at: stateURL(for: tabID))
            try? FileManager.default.removeItem(at: snapshotURL(for: tabID))
        }
    }

    public func purgeIncognitoCaches(incognitoTabIDs: [UUID]) {
        for id in incognitoTabIDs {
            if let webView = liveWebViews.removeValue(forKey: id) {
                teardownWebView(webView)
            }
            coordinators.removeValue(forKey: id)
            accessOrder.removeAll { $0 == id }
        }
        incognitoInteractionStates.removeAll()
        incognitoSnapshots.removeAll()
    }

    public func suspendBackgroundMedia(except activeTabID: UUID?) {
        let pauseScript = "document.querySelectorAll('video, audio').forEach(m => { try { m.pause(); } catch(_) {} });"
        for (id, webView) in liveWebViews where id != activeTabID {
            webView.evaluateJavaScript(pauseScript, in: nil, in: .page) { _ in }
        }
    }

    public func suspendAllMedia() {
        suspendBackgroundMedia(except: nil)
    }

    public func applyDarkMode(_ enabled: Bool, to tabID: UUID) {
        guard let webView = liveWebViews[tabID] else { return }
        let js = "window.__prismInitialDarkMode = \(enabled ? "true" : "false"); if (window.__prismSetDarkMode) { window.__prismSetDarkMode(\(enabled ? "true" : "false")); }"
        webView.evaluateJavaScript(js, in: nil, in: .page) { _ in }
    }

    public func applyAdBlockRules(to tabID: UUID, siteHost: String?, allowlistedHosts: Set<String>) {
        guard let webView = liveWebViews[tabID] else { return }
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            await self.adBlockCompiler.apply(
                to: webView.configuration.userContentController,
                siteHost: siteHost,
                allowlistedHosts: allowlistedHosts
            )
        }
    }

    // MARK: - Private Setup & Teardown

    private func makeConfiguration(
        tabID: UUID,
        isIncognito: Bool,
        initialDarkMode: Bool
    ) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isIncognito ? .nonPersistent() : .default()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = config.userContentController

        // 1. Dark Mode flag + FOUC-free atDocumentStart CSS injector in .page world
        let darkFlagScript = WKUserScript(
            source: "window.__prismInitialDarkMode = \(initialDarkMode ? "true" : "false");",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        controller.addUserScript(darkFlagScript)

        if let darkURL = Bundle.module.url(forResource: "DarkModeInjector.user", withExtension: "js"),
           let darkSource = try? String(contentsOf: darkURL, encoding: .utf8) {
            controller.addUserScript(
                WKUserScript(
                    source: darkSource,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false,
                    in: .page
                )
            )
        }

        // 2. Mozilla Readability.js + ReaderExtractor.user.js isolated strictly in .defaultClient world
        if let readabilityURL = Bundle.module.url(forResource: "Readability", withExtension: "js"),
           let readabilitySource = try? String(contentsOf: readabilityURL, encoding: .utf8) {
            controller.addUserScript(
                WKUserScript(
                    source: readabilitySource,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true,
                    in: .defaultClient
                )
            )
        }
        if let readerURL = Bundle.module.url(forResource: "ReaderExtractor.user", withExtension: "js"),
           let readerSource = try? String(contentsOf: readerURL, encoding: .utf8) {
            controller.addUserScript(
                WKUserScript(
                    source: readerSource,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true,
                    in: .defaultClient
                )
            )
        }

        // 3. Tracker telemetry isolated in .defaultClient world
        trackerMonitor.attach(to: controller, tabID: tabID)

        // 4. Extension point for Phase 3 MediaInterceptor (.page world cross-frame video sniffer)
        configureAdditionalScripts?(controller, tabID)

        return config
    }

    private func teardownWebView(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        let controller = webView.configuration.userContentController
        controller.removeAllScriptMessageHandlers(from: .page)
        controller.removeAllScriptMessageHandlers(from: .defaultClient)
        controller.removeAllUserScripts()
        controller.removeAllContentRuleLists()
        webView.removeFromSuperview()
    }

    private func evictAllInactiveOnMemoryWarning() {
        let activeID = accessOrder.last
        let victims = accessOrder.filter { $0 != activeID }
        for id in victims {
            evict(tabID: id, isIncognito: isTabIncognito(id))
        }
    }

    private func touchLRU(_ tabID: UUID) {
        accessOrder.removeAll { $0 == tabID }
        accessOrder.append(tabID)
    }

    private func isTabIncognito(_ tabID: UUID) -> Bool {
        guard let webView = liveWebViews[tabID] else {
            return incognitoInteractionStates[tabID] != nil || incognitoSnapshots[tabID] != nil
        }
        return !webView.configuration.websiteDataStore.isPersistent
    }

    private func stateURL(for tabID: UUID) -> URL {
        statesDirectory.appendingPathComponent("\(tabID.uuidString).bin")
    }

    private func snapshotURL(for tabID: UUID) -> URL {
        snapshotsDirectory.appendingPathComponent("\(tabID.uuidString).jpg")
    }

    private func saveInteractionState(_ data: Data, for tabID: UUID, isIncognito: Bool) {
        if isIncognito {
            incognitoInteractionStates[tabID] = data
        } else {
            try? data.write(to: stateURL(for: tabID), options: .atomic)
        }
    }

    private func loadInteractionState(for tabID: UUID, isIncognito: Bool) -> Data? {
        if isIncognito {
            return incognitoInteractionStates[tabID]
        }
        return try? Data(contentsOf: stateURL(for: tabID))
    }

    private func saveSnapshotData(_ data: Data, for tabID: UUID, isIncognito: Bool) {
        if isIncognito {
            incognitoSnapshots[tabID] = data
        } else {
            try? data.write(to: snapshotURL(for: tabID), options: .atomic)
        }
    }

    private func downscaleSnapshot(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
