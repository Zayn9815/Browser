import AdBlockEngine
import Foundation
import MediaInterceptor
import Observation
import ParallelDownloader
import SwiftData
import UIKit
import VaultManager
import WebKit

public struct ExtractedReaderArticle: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let title: String
    public let byline: String
    public let siteName: String
    public let excerpt: String
    public let contentHTML: String
    public let textLength: Int

    public init(
        id: UUID = UUID(),
        title: String,
        byline: String,
        siteName: String,
        excerpt: String,
        contentHTML: String,
        textLength: Int
    ) {
        self.id = id
        self.title = title
        self.byline = byline
        self.siteName = siteName
        self.excerpt = excerpt
        self.contentHTML = contentHTML
        self.textLength = textLength
    }
}

@Observable
@MainActor
public final class BrowserStore: WebViewNavigationEventDelegate {
    public var tabs: [BrowserTabState] = []
    public var activeTabID: UUID
    public var selectedSearchEngine: SearchEngineOption = BrowserEngineDefaults.defaultSearchEngine
    public var globalDarkModeEnabled: Bool = false
    public var globalAdBlockEnabled: Bool = true
    public var allowlistedHosts: Set<String> = []
    public var settings: BrowserSettingsSnapshot

    public var isOmniboxExpanded: Bool = false
    public var omniboxText: String = ""
    public var isChromeMinimized: Bool = false
    public var isTabGridPresented: Bool = false
    public var isQRScannerPresented: Bool = false
    public var isSiteMenuPresented: Bool = false
    public var isBookmarksHistoryPresented: Bool = false
    public var isGoogleSignInPresented: Bool = false
    public var openGoogleAccountManagement: Bool = false

    public var activeReaderArticle: ExtractedReaderArticle?
    public var activeDialog: BrowserDialogRequest?
    public var activePopupSession: BrowserPopupSession?
    public var statusToastMessage: String?
    public var blockedPopupsCount: Int = 0

    public let adBlockCompiler: AdBlockRuleCompiler
    public let trackerMonitor: TrackerShieldMonitor
    public let mediaInterceptor: MediaInterceptorCoordinator
    public let webViewPool: WebViewLRUPool
    public var findInPageService: FindInPageService
    public let authService: BiometricAuthService
    public let googleAccount: GoogleAccountManager

    public weak var downloadCoordinator: (any ParallelDownloadCoordinating)?
    public var onDownloadEnqueuedToast: ((String) -> Void)?

    private var modelContext: ModelContext?
    private let archiveExporter: WebArchiveExporter
    private var toastClearTask: Task<Void, Never>?

    private let tabsPersistenceKey = "prismdm.v1.normalTabs"
    private let searchEngineKey = "prismdm.v1.searchEngine"
    private let globalDarkModeKey = "prismdm.v1.globalDarkMode"
    private let globalAdBlockKey = "prismdm.v1.globalAdBlock"

    public init(
        adBlockCompiler: AdBlockRuleCompiler = .shared,
        authService: BiometricAuthService = .shared,
        fileService: VaultFileService = .shared,
        googleAccount: GoogleAccountManager = .shared
    ) {
        let loadedSettings = BrowserSettingsSnapshot.load()
        self.settings = loadedSettings
        self.adBlockCompiler = adBlockCompiler
        self.googleAccount = googleAccount
        let monitor = TrackerShieldMonitor()
        self.trackerMonitor = monitor
        let interceptor = MediaInterceptorCoordinator()
        interceptor.isEnabled = loadedSettings.mediaInterceptionEnabled
        self.mediaInterceptor = interceptor
        let pool = WebViewLRUPool(
            maxLiveWebViews: loadedSettings.maxLiveWebViews,
            adBlockCompiler: adBlockCompiler,
            trackerMonitor: monitor
        )
        pool.configureAdditionalScripts = { [weak interceptor] controller, tabID in
            interceptor?.attach(to: controller, tabID: tabID)
        }
        self.webViewPool = pool
        self.findInPageService = FindInPageService()
        self.authService = authService
        self.archiveExporter = WebArchiveExporter(fileService: fileService)

        if let savedEngineRaw = UserDefaults.standard.string(forKey: searchEngineKey),
           let engine = SearchEngineOption(rawValue: savedEngineRaw) {
            self.selectedSearchEngine = engine
        }
        self.globalDarkModeEnabled = UserDefaults.standard.bool(forKey: globalDarkModeKey)
        if UserDefaults.standard.object(forKey: globalAdBlockKey) != nil {
            self.globalAdBlockEnabled = UserDefaults.standard.bool(forKey: globalAdBlockKey)
        }

        let restored = loadedSettings.restoreTabsOnStartup ? Self.loadPersistedTabs(key: tabsPersistenceKey) : []
        if !restored.isEmpty {
            self.tabs = restored
            self.activeTabID = restored[0].id
        } else {
            let homeURL = loadedSettings.homepageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            let initial = BrowserTabState(
                title: homeURL.isEmpty ? "Start Page" : (URL(string: homeURL)?.host ?? "Home"),
                urlString: homeURL,
                preferDesktopUserAgent: loadedSettings.defaultRequestDesktopSite
            )
            self.tabs = [initial]
            self.activeTabID = initial.id
        }
    }

    public var currentSettingsSnapshot: BrowserSettingsSnapshot {
        settings
    }

    public func attachModelContext(_ context: ModelContext) {
        guard modelContext == nil else { return }
        self.modelContext = context
        loadSitePreferencesFromSwiftData()

        // Pre-warm offline AdBlock rule lists and refresh Google session asynchronously without blocking launch
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.adBlockCompiler.prepareRuleLists(
                allowlistedHosts: self.allowlistedHosts,
                enabledSourceLists: self.settings.enabledAdBlockSourceLists
            )
            await self.googleAccount.refreshSessionStatus()
        }
    }

    public var activeTab: BrowserTabState {
        tabs.first(where: { $0.id == activeTabID }) ?? tabs[0]
    }

    public var activeTabIndex: Int? {
        tabs.firstIndex(where: { $0.id == activeTabID })
    }

    public var normalTabs: [BrowserTabState] {
        tabs.filter { !$0.isIncognito }
    }

    public var incognitoTabs: [BrowserTabState] {
        tabs.filter(\.isIncognito)
    }

    public func activeWebView() -> WKWebView {
        webViewPool.webView(
            for: activeTab,
            globalDarkMode: globalDarkModeEnabled,
            allowlistedHosts: effectiveAllowlistedHosts,
            settings: settings,
            delegate: self
        )
    }

    public var effectiveAllowlistedHosts: Set<String> {
        globalAdBlockEnabled ? allowlistedHosts : ["*"]
    }

    public func presentGoogleSignIn(manageAccount: Bool = false) {
        openGoogleAccountManagement = manageAccount
        isGoogleSignInPresented = true
    }

    // MARK: - Navigation Actions

    public func navigate(toInput input: String) {
        guard let targetURL = selectedSearchEngine.resolveNavigationURL(from: input) else { return }
        navigate(to: targetURL)
    }

    public func navigateToHomepage() {
        let trimmed = settings.homepageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let url = selectedSearchEngine.resolveNavigationURL(from: trimmed) {
            navigate(to: url)
        } else if let idx = activeTabIndex {
            tabs[idx].urlString = ""
            tabs[idx].title = tabs[idx].isIncognito ? "Private Tab" : "Start Page"
            omniboxText = ""
            isChromeMinimized = false
            persistNormalTabs()
        }
    }

    public func navigate(to url: URL) {
        if let idx = activeTabIndex {
            tabs[idx].urlString = url.absoluteString
            tabs[idx].lastAccessedAt = .now
            if tabs[idx].title == "Start Page" || tabs[idx].title == "New Tab" {
                tabs[idx].title = url.host ?? url.absoluteString
            }
        }
        omniboxText = url.absoluteString
        isOmniboxExpanded = false
        trackerMonitor.resetCount(for: activeTabID)

        let webView = activeWebView()
        applySitePreferencesIfPresent(for: url.host?.lowercased(), to: activeTabID, webView: webView)
        webView.load(URLRequest(url: url))
        persistNormalTabs()
    }

    public func goBack() {
        webViewPool.existingWebView(for: activeTabID)?.goBack()
    }

    public func goForward() {
        webViewPool.existingWebView(for: activeTabID)?.goForward()
    }

    public func reloadOrStop() {
        guard let webView = webViewPool.existingWebView(for: activeTabID) else { return }
        if webView.isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    public func selectSearchEngine(_ engine: SearchEngineOption) {
        selectedSearchEngine = engine
        UserDefaults.standard.set(engine.rawValue, forKey: searchEngineKey)
    }

    // MARK: - Tab Management (Lazy Instantiation + LRU Pool)

    @discardableResult
    public func createTab(url: URL? = nil, isIncognito: Bool = false, activate: Bool = true) -> UUID {
        let outgoingID = activeTabID
        let outgoingIncognito = activeTab.isIncognito

        let newTab = BrowserTabState(
            title: url?.host ?? (isIncognito ? "Private Tab" : "Start Page"),
            urlString: url?.absoluteString ?? "",
            isIncognito: isIncognito,
            preferDesktopUserAgent: settings.defaultRequestDesktopSite
        )
        tabs.append(newTab)

        if activate {
            Task { @MainActor [weak self] in
                _ = await self?.webViewPool.captureSnapshotAndState(for: outgoingID, isIncognito: outgoingIncognito)
            }
            activeTabID = newTab.id
            webViewPool.suspendBackgroundMedia(except: newTab.id)
            omniboxText = url?.absoluteString ?? ""
            isChromeMinimized = false
            if let url {
                let webView = activeWebView()
                webView.load(URLRequest(url: url))
            }
        }

        persistNormalTabs()
        return newTab.id
    }

    public func selectTab(_ tabID: UUID) {
        guard tabID != activeTabID, tabs.contains(where: { $0.id == tabID }) else {
            isTabGridPresented = false
            return
        }

        let outgoingID = activeTabID
        let outgoingIncognito = activeTab.isIncognito
        Task { @MainActor [weak self] in
            _ = await self?.webViewPool.captureSnapshotAndState(for: outgoingID, isIncognito: outgoingIncognito)
        }

        activeTabID = tabID
        if let idx = activeTabIndex {
            tabs[idx].lastAccessedAt = .now
            omniboxText = tabs[idx].urlString
        }
        webViewPool.suspendBackgroundMedia(except: tabID)
        isChromeMinimized = false
        isTabGridPresented = false
        persistNormalTabs()
    }

    public func closeTab(_ tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let removed = tabs.remove(at: idx)
        webViewPool.closeTab(tabID: removed.id, isIncognito: removed.isIncognito)
        mediaInterceptor.clearTab(removed.id)

        if tabs.isEmpty {
            let fresh = BrowserTabState(
                title: "Start Page",
                urlString: "",
                preferDesktopUserAgent: settings.defaultRequestDesktopSite
            )
            tabs = [fresh]
            activeTabID = fresh.id
            omniboxText = ""
        } else if activeTabID == tabID {
            let nextIndex = min(idx, tabs.count - 1)
            activeTabID = tabs[nextIndex].id
            omniboxText = tabs[nextIndex].urlString
        }
        persistNormalTabs()
    }

    public func closeAllIncognitoTabs() {
        let privateIDs = incognitoTabs.map(\.id)
        webViewPool.purgeIncognitoCaches(incognitoTabIDs: privateIDs)
        for id in privateIDs {
            mediaInterceptor.clearTab(id)
        }
        tabs.removeAll { $0.isIncognito }
        if tabs.isEmpty {
            let fresh = BrowserTabState(
                title: "Start Page",
                urlString: "",
                preferDesktopUserAgent: settings.defaultRequestDesktopSite
            )
            tabs = [fresh]
            activeTabID = fresh.id
        } else if !tabs.contains(where: { $0.id == activeTabID }) {
            activeTabID = tabs[0].id
        }
        omniboxText = activeTab.urlString
        persistNormalTabs()
    }

    public func handleSceneBackgrounded(isBackgroundAudioActive: Bool) {
        if !isBackgroundAudioActive {
            webViewPool.suspendAllMedia()
        }
        if settings.autoCloseIncognitoOnBackground && !incognitoTabs.isEmpty {
            closeAllIncognitoTabs()
        }
        let currentID = activeTabID
        let currentIncognito = activeTab.isIncognito
        Task { @MainActor [weak self] in
            _ = await self?.webViewPool.captureSnapshotAndState(for: currentID, isIncognito: currentIncognito)
        }
        persistNormalTabs()
    }

    // MARK: - Site Controls & Browser Settings Mutators

    public var isActiveTabDarkModeEnabled: Bool {
        activeTab.darkModeOverride ?? globalDarkModeEnabled
    }

    public var isActiveSiteAdBlockEnabled: Bool {
        guard globalAdBlockEnabled, !settings.enabledAdBlockSourceLists.isEmpty else { return false }
        guard let host = activeTab.currentURL?.host?.lowercased() else { return true }
        return !allowlistedHosts.contains(host)
    }

    public func toggleGlobalDarkMode() {
        globalDarkModeEnabled.toggle()
        UserDefaults.standard.set(globalDarkModeEnabled, forKey: globalDarkModeKey)
        webViewPool.applyDarkMode(isActiveTabDarkModeEnabled, to: activeTabID)
    }

    public func toggleActiveSiteDarkMode() {
        guard let idx = activeTabIndex else { return }
        let next = !(tabs[idx].darkModeOverride ?? globalDarkModeEnabled)
        tabs[idx].darkModeOverride = next
        webViewPool.applyDarkMode(next, to: activeTabID)
        if let host = tabs[idx].currentURL?.host?.lowercased(), !tabs[idx].isIncognito {
            upsertSitePreference(host: host) { $0.darkModeEnabled = next }
        }
    }

    public func toggleActiveTabDesktopUserAgent() {
        guard let idx = activeTabIndex else { return }
        tabs[idx].preferDesktopUserAgent.toggle()
        let preferDesktop = tabs[idx].preferDesktopUserAgent
        if let webView = webViewPool.existingWebView(for: activeTabID) {
            webView.customUserAgent = preferDesktop
                ? BrowserEngineDefaults.desktopUserAgent
                : BrowserEngineDefaults.mobileUserAgent
            webView.reload()
        }
        if let host = tabs[idx].currentURL?.host?.lowercased(), !tabs[idx].isIncognito {
            upsertSitePreference(host: host) { $0.preferDesktopUserAgent = preferDesktop }
        }
        persistNormalTabs()
    }

    public func setGlobalAdBlockEnabled(_ enabled: Bool) {
        globalAdBlockEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: globalAdBlockKey)
        reapplyAdBlockToAllLiveTabs(reloadActive: true)
    }

    public func setEasyListEnabled(_ enabled: Bool) {
        settings.blockAdsEasyList = enabled
        settings.save()
        reapplyAdBlockToAllLiveTabs(reloadActive: true)
    }

    public func setEasyPrivacyEnabled(_ enabled: Bool) {
        settings.blockTrackersEasyPrivacy = enabled
        settings.save()
        reapplyAdBlockToAllLiveTabs(reloadActive: true)
    }

    public func setBlockPopups(_ enabled: Bool) {
        settings.blockPopups = enabled
        settings.save()
        webViewPool.applyPopupBlocking(enabled)
    }

    public func setHTTPSOnlyEnabled(_ enabled: Bool) {
        settings.httpsOnlyEnabled = enabled
        settings.save()
    }

    public func setStripTrackingParameters(_ enabled: Bool) {
        settings.stripTrackingParameters = enabled
        settings.save()
    }

    public func setBlockJavaScript(_ enabled: Bool) {
        settings.blockJavaScript = enabled
        settings.save()
        webViewPool.applyJavaScriptBlocking(enabled, reloadTabID: activeTabID)
    }

    public func setDefaultPageZoom(_ zoom: Double) {
        let clamped = (max(0.75, min(1.50, zoom)) * 20.0).rounded() / 20.0
        settings.defaultPageZoom = clamped
        settings.save()
        webViewPool.applyPageZoom(clamped)
    }

    public func setDefaultRequestDesktopSite(_ enabled: Bool) {
        settings.defaultRequestDesktopSite = enabled
        settings.save()
        if let idx = activeTabIndex {
            tabs[idx].preferDesktopUserAgent = enabled
            if let webView = webViewPool.existingWebView(for: activeTabID) {
                webView.customUserAgent = enabled
                    ? BrowserEngineDefaults.desktopUserAgent
                    : BrowserEngineDefaults.mobileUserAgent
                webView.reload()
            }
        }
        persistNormalTabs()
    }

    public func setAutoHideToolbarOnScroll(_ enabled: Bool) {
        settings.autoHideToolbarOnScroll = enabled
        settings.save()
        if !enabled {
            isChromeMinimized = false
        }
    }

    public func setOpenExternalAppLinks(_ enabled: Bool) {
        settings.openExternalAppLinks = enabled
        settings.save()
    }

    public func setHomepageURLString(_ value: String) {
        settings.homepageURLString = value.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.save()
    }

    public func setMediaInterceptionEnabled(_ enabled: Bool) {
        settings.mediaInterceptionEnabled = enabled
        settings.save()
        mediaInterceptor.isEnabled = enabled
        webViewPool.applyMediaInterceptionEnabled(enabled)
    }

    public func setAutoPlayVideos(_ enabled: Bool) {
        settings.autoPlayVideos = enabled
        settings.save()
    }

    public func setAutoLockLandscapeInPlayer(_ enabled: Bool) {
        settings.autoLockLandscapeInPlayer = enabled
        settings.save()
    }

    public func setMaxLiveWebViews(_ limit: Int) {
        let clamped = max(2, min(8, limit))
        settings.maxLiveWebViews = clamped
        settings.save()
        webViewPool.setMaxLiveWebViews(clamped, activeTabID: activeTabID)
    }

    public func setRestoreTabsOnStartup(_ enabled: Bool) {
        settings.restoreTabsOnStartup = enabled
        settings.save()
    }

    public func setAutoCloseIncognitoOnBackground(_ enabled: Bool) {
        settings.autoCloseIncognitoOnBackground = enabled
        settings.save()
    }

    public func setPrivacyCurtainEnabled(_ enabled: Bool) {
        settings.privacyCurtainEnabled = enabled
        settings.save()
    }

    public func addAllowlistedHost(_ rawHost: String) {
        let cleaned = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first
            .map(String.init) ?? ""
        guard !cleaned.isEmpty, cleaned.contains(".") else { return }
        allowlistedHosts.insert(cleaned)
        upsertSitePreference(host: cleaned) { $0.adBlockEnabled = false }
        reapplyAdBlockToAllLiveTabs(reloadActive: activeTab.currentURL?.host?.lowercased() == cleaned)
    }

    public func removeAllowlistedHost(_ host: String) {
        let normalized = host.lowercased()
        allowlistedHosts.remove(normalized)
        upsertSitePreference(host: normalized) { $0.adBlockEnabled = true }
        reapplyAdBlockToAllLiveTabs(reloadActive: activeTab.currentURL?.host?.lowercased() == normalized)
    }

    public func clearAllSitePreferences() {
        allowlistedHosts.removeAll()
        if let modelContext, let records = try? modelContext.fetch(FetchDescriptor<SitePreferenceRecord>()) {
            for record in records {
                modelContext.delete(record)
            }
            try? modelContext.save()
        }
        reapplyAdBlockToAllLiveTabs(reloadActive: false)
    }

    public func toggleActiveSiteAdBlock() {
        guard let host = activeTab.currentURL?.host?.lowercased(), !host.isEmpty else {
            setGlobalAdBlockEnabled(!globalAdBlockEnabled)
            return
        }
        if allowlistedHosts.contains(host) {
            allowlistedHosts.remove(host)
            upsertSitePreference(host: host) { $0.adBlockEnabled = true }
            showToast("AdBlock enabled for \(host)")
        } else {
            allowlistedHosts.insert(host)
            upsertSitePreference(host: host) { $0.adBlockEnabled = false }
            showToast("AdBlock paused on \(host)")
        }
        webViewPool.applyAdBlockRules(
            to: activeTabID,
            siteHost: host,
            allowlistedHosts: effectiveAllowlistedHosts,
            enabledSourceLists: settings.enabledAdBlockSourceLists
        )
        webViewPool.existingWebView(for: activeTabID)?.reload()
    }

    private func reapplyAdBlockToAllLiveTabs(reloadActive: Bool) {
        let lists = settings.enabledAdBlockSourceLists
        for tab in tabs {
            webViewPool.applyAdBlockRules(
                to: tab.id,
                siteHost: tab.currentURL?.host?.lowercased(),
                allowlistedHosts: effectiveAllowlistedHosts,
                enabledSourceLists: lists
            )
        }
        if reloadActive {
            webViewPool.existingWebView(for: activeTabID)?.reload()
        }
    }

    public func extractReaderArticle() async {
        guard let webView = webViewPool.existingWebView(for: activeTabID) else {
            showToast("Open a webpage first to use Reader Mode.")
            return
        }
        do {
            let rawResult: Any? = try await webView.evaluateJavaScript(
                "typeof window.__prismExtractReaderArticle === 'function' ? window.__prismExtractReaderArticle() : JSON.stringify({ error: 'Reader script unavailable.' })",
                in: nil,
                in: .defaultClient
            )
            guard let jsonString = rawResult as? String,
                  let data = jsonString.data(using: .utf8),
                  let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                showToast("Unable to parse article content.")
                return
            }
            if let errorMsg = dict["error"] as? String {
                showToast(errorMsg)
                return
            }
            activeReaderArticle = ExtractedReaderArticle(
                title: (dict["title"] as? String) ?? activeTab.title,
                byline: (dict["byline"] as? String) ?? "",
                siteName: (dict["siteName"] as? String) ?? activeTab.displayHost,
                excerpt: (dict["excerpt"] as? String) ?? "",
                contentHTML: (dict["contentHTML"] as? String) ?? "",
                textLength: (dict["textLength"] as? Int) ?? 0
            )
        } catch {
            showToast("Reader Mode failed: \(error.localizedDescription)")
        }
    }

    public func exportCurrentPageAsWebArchive() async {
        guard let webView = webViewPool.existingWebView(for: activeTabID), webView.url != nil else {
            showToast("No loaded page to save.")
            return
        }
        do {
            let saved = try await archiveExporter.exportCurrentPage(
                from: webView,
                pageTitle: activeTab.title,
                isPrivate: activeTab.isIncognito
            )
            if let modelContext {
                let record = VaultItemRecord(
                    id: saved.id,
                    relativePath: saved.relativePath,
                    displayName: saved.displayName,
                    fileExtension: saved.fileExtension,
                    mimeType: saved.mimeType,
                    byteSize: saved.byteSize,
                    kind: saved.kind,
                    sourceURLString: saved.sourceURLString,
                    isPrivateVault: saved.isPrivateVault,
                    createdAt: saved.createdAt
                )
                modelContext.insert(record)
                try? modelContext.save()
            }
            showToast("Saved \(saved.displayName) to \(saved.isPrivateVault ? "Private Vault" : "Vault")")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    public func bookmarkActivePage() {
        guard let url = activeTab.currentURL, let modelContext else {
            showToast("Nothing to bookmark yet.")
            return
        }
        let targetString = url.absoluteString
        let descriptor = FetchDescriptor<BookmarkRecord>(
            predicate: #Predicate { $0.urlString == targetString }
        )
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            showToast("Page is already bookmarked.")
            return
        }
        let bookmark = BookmarkRecord(
            title: activeTab.title.isEmpty ? activeTab.displayHost : activeTab.title,
            urlString: targetString
        )
        modelContext.insert(bookmark)
        try? modelContext.save()
        showToast("Bookmarked \(bookmark.title)")
    }

    public func handleWebViewUpdate(_ update: WebViewObservableUpdate, for tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if !update.title.isEmpty {
            tabs[idx].title = update.title
        }
        if !update.urlString.isEmpty {
            tabs[idx].urlString = update.urlString
            if tabID == activeTabID && !isOmniboxExpanded {
                omniboxText = update.urlString
            }
        }
        tabs[idx].isLoading = update.isLoading
        tabs[idx].estimatedProgress = update.estimatedProgress
        tabs[idx].canGoBack = update.canGoBack
        tabs[idx].canGoForward = update.canGoForward
        tabs[idx].hasOnlySecureContent = update.hasOnlySecureContent
        tabs[idx].blockedTrackerCount = trackerMonitor.count(for: tabID)
    }

    public func showToast(_ message: String) {
        statusToastMessage = message
        toastClearTask?.cancel()
        toastClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            self?.statusToastMessage = nil
        }
    }

    // MARK: - WebViewNavigationEventDelegate

    public func navigationDidStartLoad(tabID: UUID, url: URL?) {
        trackerMonitor.resetCount(for: tabID)
        mediaInterceptor.clearTab(tabID)
        if let idx = tabs.firstIndex(where: { $0.id == tabID }) {
            tabs[idx].isLoading = true
            tabs[idx].blockedTrackerCount = 0
        }
    }

    public func navigationDidCommit(tabID: UUID, url: URL?, title: String?) {
        guard let host = url?.host?.lowercased() else { return }
        if let webView = webViewPool.existingWebView(for: tabID) {
            applySitePreferencesIfPresent(for: host, to: tabID, webView: webView)
        }
    }

    public func navigationDidFinish(tabID: UUID, url: URL?, title: String?) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].isLoading = false
        tabs[idx].blockedTrackerCount = trackerMonitor.count(for: tabID)
        if let url {
            tabs[idx].urlString = url.absoluteString
            if let title, !title.isEmpty {
                tabs[idx].title = title
            }
            if !tabs[idx].isIncognito {
                recordHistoryVisit(url: url, title: tabs[idx].title)
                persistNormalTabs()
                if let host = url.host?.lowercased(), host.hasSuffix("google.com") || host.hasSuffix("youtube.com") {
                    Task { @MainActor [weak self] in
                        await self?.googleAccount.refreshSessionStatus()
                    }
                }
            }
        }
    }

    public func navigationDidFail(tabID: UUID, error: Error) {
        if let idx = tabs.firstIndex(where: { $0.id == tabID }) {
            tabs[idx].isLoading = false
        }
        showToast(error.localizedDescription)
    }

    public func navigationDidRequestNewTab(url: URL, isIncognito: Bool) {
        createTab(url: url, isIncognito: isIncognito, activate: true)
    }

    public func navigationDidRequestPopup(_ session: BrowserPopupSession) {
        activePopupSession = session
    }

    public func navigationDidClosePopup(webView: WKWebView) {
        if activePopupSession?.webView === webView {
            activePopupSession = nil
            Task { @MainActor [weak self] in
                await self?.googleAccount.refreshSessionStatus()
            }
        }
    }

    public func navigationDidBlockPopup(tabID: UUID) {
        blockedPopupsCount += 1
        showToast("Blocked pop-up window")
    }

    public func navigationDidRequestDialog(_ dialog: BrowserDialogRequest) {
        activeDialog = dialog
    }

    public func navigationDidInterceptDownload(
        tabID: UUID,
        url: URL,
        suggestedFilename: String?,
        mimeType: String?,
        sessionContext: BrowserSessionContext
    ) {
        let filename = suggestedFilename ?? url.lastPathComponent
        guard let downloadCoordinator else {
            showToast("Queued download handoff for \(filename)")
            onDownloadEnqueuedToast?(filename)
            return
        }
        Task { @MainActor [weak self] in
            do {
                _ = try await downloadCoordinator.enqueueHTTPDownload(
                    url: url,
                    sessionContext: sessionContext,
                    preferredEngine: nil,
                    connectionLimit: nil,
                    bandwidthLimitBytesPerSec: nil
                )
                self?.showToast("Downloading \(filename)…")
                self?.onDownloadEnqueuedToast?(filename)
            } catch {
                self?.showToast("Download failed: \(error.localizedDescription)")
            }
        }
    }

    public func navigationDidRecoverFromContentProcessTermination(tabID: UUID) {
        showToast("Recovered webpage after WebKit process restart.")
    }

    // MARK: - SwiftData & Persistence Helpers

    private func recordHistoryVisit(url: URL, title: String) {
        guard let modelContext, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return }
        let urlString = url.absoluteString
        let host = url.host?.lowercased() ?? ""
        let descriptor = FetchDescriptor<HistoryRecord>(
            predicate: #Predicate { $0.urlString == urlString }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.visitedAt = .now
            existing.visitCount += 1
            if !title.isEmpty { existing.title = title }
        } else {
            let entry = HistoryRecord(title: title.isEmpty ? host : title, urlString: urlString, host: host)
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }

    private func loadSitePreferencesFromSwiftData() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<SitePreferenceRecord>()
        guard let records = try? modelContext.fetch(descriptor) else { return }
        allowlistedHosts = Set(records.filter { !$0.adBlockEnabled }.map(\.host))
    }

    private func applySitePreferencesIfPresent(for host: String?, to tabID: UUID, webView: WKWebView) {
        guard let host, !host.isEmpty else { return }
        webViewPool.applyAdBlockRules(
            to: tabID,
            siteHost: host,
            allowlistedHosts: effectiveAllowlistedHosts,
            enabledSourceLists: settings.enabledAdBlockSourceLists
        )

        guard let modelContext else { return }
        let descriptor = FetchDescriptor<SitePreferenceRecord>(
            predicate: #Predicate { $0.host == host }
        )
        if let pref = try? modelContext.fetch(descriptor).first {
            webViewPool.applyDarkMode(pref.darkModeEnabled || globalDarkModeEnabled, to: tabID)
            let desiredUA = pref.preferDesktopUserAgent
                ? BrowserEngineDefaults.desktopUserAgent
                : BrowserEngineDefaults.mobileUserAgent
            if webView.customUserAgent != desiredUA {
                webView.customUserAgent = desiredUA
            }
        }
    }

    private func upsertSitePreference(host: String, mutate: (SitePreferenceRecord) -> Void) {
        guard let modelContext else { return }
        let normalized = host.lowercased()
        let descriptor = FetchDescriptor<SitePreferenceRecord>(
            predicate: #Predicate { $0.host == normalized }
        )
        let record: SitePreferenceRecord
        if let existing = try? modelContext.fetch(descriptor).first {
            record = existing
        } else {
            record = SitePreferenceRecord(host: normalized)
            modelContext.insert(record)
        }
        mutate(record)
        record.updatedAt = .now
        try? modelContext.save()
    }

    private func persistNormalTabs() {
        let toSave = normalTabs
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: tabsPersistenceKey)
        }
    }

    private static func loadPersistedTabs(key: String) -> [BrowserTabState] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BrowserTabState].self, from: data) else {
            return []
        }
        return decoded
    }
}
