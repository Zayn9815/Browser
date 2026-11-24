import AdBlockEngine
import MediaInterceptor
import ParallelDownloader
import PrismPlayer
import SDMCore
import SwiftData
import SwiftUI
import VaultManager
import WebKit

public enum PrismShellTab: Hashable, Sendable {
    case browser
    case downloads
    case vault
    case settings
}

public struct BrowserShellView<DownloadsContent: View, BrowserOverlayContent: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BookmarkRecord.createdAt, order: .reverse) private var bookmarks: [BookmarkRecord]

    @Bindable public var store: BrowserStore
    @Bindable public var downloadStore: ParallelDownloadStore
    @Bindable public var audioCenter: BackgroundAudioCenter
    @Binding public var selectedTab: PrismShellTab

    private let onPlayVaultMedia: ((URL, String) -> Void)?
    private let downloadsTabContent: () -> DownloadsContent
    private let browserOverlayContent: () -> BrowserOverlayContent

    @State private var promptInputText = ""
    @State private var authUsername = ""
    @State private var authPassword = ""
    @State private var showClearDataConfirm = false

    public init(
        store: BrowserStore,
        downloadStore: ParallelDownloadStore,
        audioCenter: BackgroundAudioCenter = .shared,
        selectedTab: Binding<PrismShellTab>,
        onPlayVaultMedia: ((URL, String) -> Void)? = nil,
        @ViewBuilder downloadsTabContent: @escaping () -> DownloadsContent,
        @ViewBuilder browserOverlayContent: @escaping () -> BrowserOverlayContent
    ) {
        self.store = store
        self.downloadStore = downloadStore
        self.audioCenter = audioCenter
        self._selectedTab = selectedTab
        self.onPlayVaultMedia = onPlayVaultMedia
        self.downloadsTabContent = downloadsTabContent
        self.browserOverlayContent = browserOverlayContent
    }

    private var shouldShowBottomAccessory: Bool {
        downloadStore.activeCount > 0 || audioCenter.hasActiveTrack
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Browser", systemImage: "safari.fill", value: PrismShellTab.browser) {
                browserViewport
            }

            Tab("Downloads", systemImage: "arrow.down.circle.fill", value: PrismShellTab.downloads) {
                downloadsTabContent()
            }
            .badge(downloadStore.activeCount)

            Tab("Vault", systemImage: "lock.doc.fill", value: PrismShellTab.vault) {
                VaultBrowserView(
                    authService: store.authService,
                    audioCenter: audioCenter,
                    onPlayMediaFile: onPlayVaultMedia
                )
            }

            Tab("Settings", systemImage: "gearshape.fill", value: PrismShellTab.settings) {
                settingsView
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .prismBottomAccessory(isVisible: shouldShowBottomAccessory) {
            TransferMiniBarView(
                downloadStore: downloadStore,
                audioCenter: audioCenter,
                onOpenDownloads: { selectedTab = .downloads }
            )
        }
        .tint(PrismBrandPalette.crimsonAccent)
        .onAppear {
            store.attachModelContext(modelContext)
            downloadStore.attachModelContext(modelContext)
        }
        .fullScreenCover(isPresented: $store.isTabGridPresented) {
            TabGridSwitcherView(store: store)
        }
        .sheet(isPresented: $store.isQRScannerPresented) {
            QRCodeScannerSheet { scannedPayload in
                store.navigate(toInput: scannedPayload)
            }
        }
        .sheet(isPresented: $store.isSiteMenuPresented) {
            ShieldAndSiteMenuSheet(store: store)
        }
        .sheet(isPresented: $store.isBookmarksHistoryPresented) {
            BookmarksAndHistorySheet { url in
                store.navigate(to: url)
            }
        }
        .sheet(item: $store.activeReaderArticle) { article in
            ReaderModeSheet(article: article)
        }
        .modifier(BrowserDialogAlertModifier(
            store: store,
            promptInputText: $promptInputText,
            authUsername: $authUsername,
            authPassword: $authPassword
        ))
    }

    private var browserViewport: some View {
        ZStack(alignment: .bottom) {
            PrismBrandPalette.obsidianBackground
                .ignoresSafeArea()

            if store.activeTab.isIncognito && !store.authService.isPrivateUnlocked {
                VaultLockOverlayView(
                    authService: store.authService,
                    title: "Private Tab Locked",
                    subtitle: "Authenticate to resume your Private Incognito session."
                )
            } else if store.activeTab.urlString.isEmpty {
                startPageView
            } else {
                PrismWebViewRepresentable(
                    webView: store.activeWebView(),
                    onStateChanged: { update in
                        store.handleWebViewUpdate(update, for: store.activeTabID)
                    },
                    onScrollDirectionChanged: { scrollingDown in
                        if !store.isOmniboxExpanded {
                            withAnimation(.snappy(duration: 0.22)) {
                                store.isChromeMinimized = scrollingDown
                            }
                        }
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            }

            VStack(spacing: 8) {
                if let toast = store.statusToastMessage {
                    Text(toast)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                browserOverlayContent()

                if store.findInPageService.isPresented {
                    findInPageGlassBar
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !store.isChromeMinimized || store.isOmniboxExpanded || store.activeTab.urlString.isEmpty {
                    FloatingOmniboxBar(store: store)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    collapsedRevealPill
                        .transition(.opacity)
                }
            }
        }
    }

    private var startPageView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: store.activeTab.isIncognito ? "eye.slash.fill" : "pyramid.fill")
                            .font(.title2)
                            .foregroundStyle(store.activeTab.isIncognito ? .purple : PrismBrandPalette.crimsonAccent)
                        Text(store.activeTab.isIncognito ? "Private Incognito" : "PrismDM")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Text(store.activeTab.isIncognito
                        ? "Non-persistent cookies, zero history saved, biometric-protected."
                        : "AdBlock active • \(store.adBlockCompiler.totalActiveRules > 0 ? "\(store.adBlockCompiler.totalActiveRules) offline rules" : AdBlockManifestLoader.summary())")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                }
                .padding(.top, 24)

                if !bookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Bookmarks")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Button("All") {
                                store.isBookmarksHistoryPresented = true
                            }
                            .font(.caption.weight(.semibold))
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(bookmarks.prefix(6)) { bookmark in
                                Button {
                                    if let url = URL(string: bookmark.urlString) {
                                        store.navigate(to: url)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bookmark.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(URL(string: bookmark.urlString)?.host ?? bookmark.urlString)
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.62))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true)
                                            .fill(PrismBrandPalette.obsidianElevated)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .containerShape(.rect(cornerRadius: 18))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick Actions")
                        .font(.headline)
                        .foregroundStyle(.white)

                    HStack(spacing: 10) {
                        Button {
                            store.isQRScannerPresented = true
                        } label: {
                            Label("Scan QR", systemImage: "qrcode.viewfinder")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)

                        Button {
                            store.isBookmarksHistoryPresented = true
                        } label: {
                            Label("Library", systemImage: "books.vertical.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
    }

    private var collapsedRevealPill: some View {
        Button {
            withAnimation(.snappy) {
                store.isChromeMinimized = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: store.activeTab.hasOnlySecureContent ? "lock.fill" : "globe")
                    .font(.caption2)
                Text(store.activeTab.displayHost)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    private var findInPageGlassBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Find on page", text: $store.findInPageService.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(.white)
                    .onSubmit {
                        Task {
                            await store.findInPageService.findNext(
                                in: store.webViewPool.existingWebView(for: store.activeTabID),
                                backwards: false
                            )
                        }
                    }

                Button {
                    Task {
                        await store.findInPageService.findNext(
                            in: store.webViewPool.existingWebView(for: store.activeTabID),
                            backwards: true
                        )
                    }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await store.findInPageService.findNext(
                            in: store.webViewPool.existingWebView(for: store.activeTabID),
                            backwards: false
                        )
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)

                Button {
                    store.findInPageService.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private var settingsView: some View {
        NavigationStack {
            List {
                Section("Parallel Download Engine (SDMCore)") {
                    Picker("Default HTTP Backend", selection: $downloadStore.preferredHTTPBackend) {
                        Text("libcurl Multi-Range").tag(DownloadEngineKind.libcurl)
                        Text("iOS Background URLSession").tag(DownloadEngineKind.urlSession)
                    }

                    Stepper(
                        "Connections per Download: \(downloadStore.defaultConnectionsPerDownload)",
                        value: $downloadStore.defaultConnectionsPerDownload,
                        in: 1...16
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Global Bandwidth Cap")
                            Spacer()
                            Text(downloadStore.globalBandwidthLimitBytesPerSec == 0
                                ? "Unlimited"
                                : "\(ByteCountFormatter.string(fromByteCount: Int64(downloadStore.globalBandwidthLimitBytesPerSec), countStyle: .file))/s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(downloadStore.globalBandwidthLimitBytesPerSec) / 1_000_000.0 },
                                set: { downloadStore.globalBandwidthLimitBytesPerSec = UInt64(($0 * 1_000_000.0).rounded()) }
                            ),
                            in: 0...50,
                            step: 1
                        )
                        .tint(PrismBrandPalette.crimsonAccent)
                    }
                }

                Section("Browser Defaults") {
                    Picker("Default Search Engine", selection: Binding(
                        get: { store.selectedSearchEngine },
                        set: { store.selectSearchEngine($0) }
                    )) {
                        ForEach(SearchEngineOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }

                    Toggle("Global Dark Mode Injection", isOn: Binding(
                        get: { store.globalDarkModeEnabled },
                        set: { _ in store.toggleGlobalDarkMode() }
                    ))

                    Toggle(
                        "Offline Ad & Tracker Blocker",
                        isOn: Binding(
                            get: { store.globalAdBlockEnabled },
                            set: { store.setGlobalAdBlockEnabled($0) }
                        )
                    )
                }

                Section("Privacy & Browsing Data") {
                    LabeledContent("LRU Active WebView Pool", value: "\(store.webViewPool.liveTabCount) / \(store.webViewPool.maxLiveWebViews)")
                    LabeledContent("Session Trackers Blocked", value: "\(store.trackerMonitor.sessionTotalBlocked)")
                    LabeledContent("Offline AdBlock Shards", value: AdBlockManifestLoader.summary())

                    Button("Clear Browsing Data & Cache", role: .destructive) {
                        showClearDataConfirm = true
                    }

                    Button("Lock Private Vault & Incognito", role: .destructive) {
                        store.authService.lock()
                        store.showToast("Private Vault & Incognito locked.")
                    }
                }

                Section("Native Engines & Legal") {
                    LabeledContent("Download Core", value: ParallelDownloaderEngineDiagnostics.sdmCoreVersionSummary)
                    LabeledContent("HLS Remux Core", value: ParallelDownloaderEngineDiagnostics.ffmpegVersionSummary)
                    LabeledContent("Universal Player", value: PrismPlayerEngineDiagnostics.mpvAPIVersionSummary)
                    LabeledContent("Vault Archive", value: VaultEngineDiagnostics.archiveEngineSummary)
                    LabeledContent("Media Bridge", value: "Schema v\(MediaInterceptorBridgeInfo.loadSchemaVersion())")

                    NavigationLink("Engine & Open Source Licenses") {
                        OpenSourceLicensesView()
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Clear all browsing history, cookies, and web caches?",
                isPresented: $showClearDataConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Browsing Data", role: .destructive) {
                    Task { await clearBrowsingData() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Downloaded Vault files and Bookmarks are preserved.")
            }
        }
    }

    private func clearBrowsingData() async {
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await WKWebsiteDataStore.default().removeData(ofTypes: allTypes, modifiedSince: .distantPast)
        if let entries = try? modelContext.fetch(FetchDescriptor<HistoryRecord>()) {
            for entry in entries {
                modelContext.delete(entry)
            }
            try? modelContext.save()
        }
        store.showToast("Cleared browsing history, cookies, and web cache.")
    }
}

// MARK: - Open Source Licenses View

private struct OpenSourceLicensesView: View {
    private let notices: [(title: String, license: String, detail: String)] = [
        (
            "SwiftyDownloadManager (SDMCore & CurlBinary)",
            "FSL-1.1-MIT • Copyright 2026 Kyle Ye",
            "Integrates only the iOS arm64 SDMCore C++20 libcurl + URLSession transfer engine and bundled Mozilla CA certificate bundle (cacert.pem). No SwiftyDownloadManager brand assets, icons, or trademarks are included. Subcomponents: libcurl (curl License), OpenSSL (Apache-2.0), Mozilla NSS CA Bundle (MPL-2.0)."
        ),
        (
            "FFmpegKit & libmpv (kingslay/FFmpegKit 9.0.2)",
            "LGPL-2.1-or-later / MIT / BSD",
            "Powers in-process Libavformat/Libavcodec HTTPS HLS-to-MP4 remuxing (-c copy, aac_adtstoasc) and libmpv + VideoToolbox + MoltenVK universal container playback (MKV, AVI, WebM, FLV, ASS/SSA)."
        ),
        (
            "ZIPFoundation (0.9.21)",
            "MIT License • Copyright Thomas Zoechling",
            "Provides in-app Vault ZIP archive compression and path-traversal-validated extraction."
        ),
        (
            "Mozilla Readability.js (0.6.0)",
            "Apache-2.0 / MPL-2.0 • Mozilla Corporation",
            "Runs isolated in WebKit's .defaultClient world to extract clean Reader Mode articles."
        ),
        (
            "EasyList & EasyPrivacy Filter Packs",
            "GPL-3.0 / CC-BY-SA-3.0",
            "Compiled and sharded at build time into WebKit Content Blocker JSON lists (<= 125,000 rules per shard) for offline ad and tracker blocking."
        ),
    ]

    var body: some View {
        List {
            ForEach(notices, id: \.title) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.license)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PrismBrandPalette.crimsonAccent)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Open Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Native SwiftUI Dialogs for JS Alert / Confirm / Prompt / HTTP Auth

private struct BrowserDialogAlertModifier: ViewModifier {
    @Bindable var store: BrowserStore
    @Binding var promptInputText: String
    @Binding var authUsername: String
    @Binding var authPassword: String

    func body(content: Content) -> some View {
        content
            .alert(
                alertTitle,
                isPresented: Binding(
                    get: { store.activeDialog != nil },
                    set: { presented in
                        if !presented {
                            cancelCurrentDialogIfNeeded()
                        }
                    }
                ),
                actions: {
                    dialogActions
                },
                message: {
                    Text(alertMessage)
                }
            )
            .onChange(of: store.activeDialog?.id) { _, _ in
                if case .jsPrompt(_, _, _, let defaultText, _) = store.activeDialog {
                    promptInputText = defaultText
                } else if case .httpAuth = store.activeDialog {
                    authUsername = ""
                    authPassword = ""
                }
            }
    }

    private var alertTitle: String {
        switch store.activeDialog {
        case .jsAlert(_, let host, _, _): return host
        case .jsConfirm(_, let host, _, _): return host
        case .jsPrompt(_, let host, _, _, _): return host
        case .httpAuth(_, let host, _, _): return "Sign in to \(host)"
        case nil: return ""
        }
    }

    private var alertMessage: String {
        switch store.activeDialog {
        case .jsAlert(_, _, let message, _): return message
        case .jsConfirm(_, _, let message, _): return message
        case .jsPrompt(_, _, let prompt, _, _): return prompt
        case .httpAuth(_, _, let realm, _): return realm
        case nil: return ""
        }
    }

    @ViewBuilder
    private var dialogActions: some View {
        switch store.activeDialog {
        case .jsAlert(_, _, _, let onDismiss):
            Button("OK") {
                store.activeDialog = nil
                onDismiss()
            }
        case .jsConfirm(_, _, _, let onDecision):
            Button("OK") {
                store.activeDialog = nil
                onDecision(true)
            }
            Button("Cancel", role: .cancel) {
                store.activeDialog = nil
                onDecision(false)
            }
        case .jsPrompt(_, _, _, _, let onSubmit):
            TextField("Response", text: $promptInputText)
            Button("OK") {
                let value = promptInputText
                store.activeDialog = nil
                onSubmit(value)
            }
            Button("Cancel", role: .cancel) {
                store.activeDialog = nil
                onSubmit(nil)
            }
        case .httpAuth(_, _, _, let onSubmit):
            TextField("Username", text: $authUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $authPassword)
            Button("Sign In") {
                let u = authUsername
                let p = authPassword
                store.activeDialog = nil
                onSubmit(u, p)
            }
            Button("Cancel", role: .cancel) {
                store.activeDialog = nil
                onSubmit(nil, nil)
            }
        case nil:
            EmptyView()
        }
    }

    private func cancelCurrentDialogIfNeeded() {
        guard let current = store.activeDialog else { return }
        store.activeDialog = nil
        switch current {
        case .jsAlert(_, _, _, let onDismiss):
            onDismiss()
        case .jsConfirm(_, _, _, let onDecision):
            onDecision(false)
        case .jsPrompt(_, _, _, _, let onSubmit):
            onSubmit(nil)
        case .httpAuth(_, _, _, let onSubmit):
            onSubmit(nil, nil)
        }
    }
}
