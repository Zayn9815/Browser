import AdBlockEngine
import MediaInterceptor
import ParallelDownloader
import PrismCore
import PrismPlayer
import SDMCore
import SwiftData
import SwiftUI
import VaultManager
import WebKit

public struct BrowserSettingsView: View {
    @Bindable public var store: BrowserStore
    @Bindable public var downloadStore: ParallelDownloadStore
    private let onDismiss: (() -> Void)?

    @State private var themeEngine = PrismThemeEngine.shared
    @State private var crashManager = PrismCrashManager.shared
    @State private var warningErrorCount = 0
    @State private var showSignOutConfirm = false

    public init(
        store: BrowserStore,
        downloadStore: ParallelDownloadStore,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.downloadStore = downloadStore
        self.onDismiss = onDismiss
    }

    private var diagnosticsBadgeSummary: String {
        let crashes = crashManager.crashCount
        if crashes > 0 && warningErrorCount > 0 {
            return "\(crashes) crash • \(warningErrorCount) err"
        } else if crashes > 0 {
            return "\(crashes) crash"
        } else if warningErrorCount > 0 {
            return "\(warningErrorCount) err"
        }
        return "Healthy"
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        NavigationStack {
            List {
                googleAccountSection

                Section("Browser") {
                    NavigationLink {
                        ThemesAndAppearanceSettingsView(store: store)
                    } label: {
                        SettingsCategoryRow(
                            title: "Themes & Appearance",
                            systemImage: "paintpalette.fill",
                            badgeColor: tokens.accent,
                            trailingDetail: themeEngine.selectedTheme.displayName
                        )
                    }

                    NavigationLink {
                        GeneralSettingsView(store: store)
                    } label: {
                        SettingsCategoryRow(
                            title: "General & Browsing",
                            systemImage: "safari.fill",
                            badgeColor: .blue,
                            trailingDetail: store.selectedSearchEngine.displayName
                        )
                    }

                    NavigationLink {
                        ShieldSettingsView(store: store)
                    } label: {
                        SettingsCategoryRow(
                            title: "Shield & Protection",
                            systemImage: "shield.lefthalf.filled",
                            badgeColor: tokens.accent,
                            trailingDetail: store.globalAdBlockEnabled ? "On" : "Off"
                        )
                    }

                    NavigationLink {
                        MediaSettingsView(store: store)
                    } label: {
                        SettingsCategoryRow(
                            title: "Media & PrismPlayer",
                            systemImage: "play.rectangle.fill",
                            badgeColor: .purple,
                            trailingDetail: store.settings.mediaInterceptionEnabled ? "On" : "Off"
                        )
                    }

                    NavigationLink {
                        TabsPerformanceSettingsView(store: store)
                    } label: {
                        SettingsCategoryRow(
                            title: "Tabs & Performance",
                            systemImage: "square.on.square.fill",
                            badgeColor: .teal,
                            trailingDetail: "\(store.settings.maxLiveWebViews) max"
                        )
                    }
                }

                Section("Engine & Security") {
                    NavigationLink {
                        DownloadsSettingsView(downloadStore: downloadStore)
                    } label: {
                        SettingsCategoryRow(
                            title: "Downloads & Engine",
                            systemImage: "arrow.down.circle.fill",
                            badgeColor: .indigo,
                            trailingDetail: "\(downloadStore.defaultConnectionsPerDownload)x"
                        )
                    }

                    NavigationLink {
                        PrivacySecuritySettingsView(store: store)
                    } label: {
                        SettingsCategoryRow(
                            title: "Privacy, Security & Data",
                            systemImage: "lock.shield.fill",
                            badgeColor: .green,
                            trailingDetail: store.authService.hasConfiguredPIN ? "PIN Set" : nil
                        )
                    }

                    NavigationLink {
                        DiagnosticsLogsView(downloadStore: downloadStore)
                    } label: {
                        SettingsCategoryRow(
                            title: "Diagnostics & Logs",
                            systemImage: "waveform.path.ecg.rectangle.fill",
                            badgeColor: crashManager.crashCount > 0 ? .red : .orange,
                            trailingDetail: diagnosticsBadgeSummary
                        )
                    }
                }

                Section {
                    NavigationLink {
                        AboutAndLicensesSettingsView()
                    } label: {
                        SettingsCategoryRow(
                            title: "About & Licenses",
                            systemImage: "info.circle.fill",
                            badgeColor: .gray,
                            trailingDetail: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                        )
                    }
                }
            }
            .contentMargins(.bottom, 100, for: .scrollContent)
            .navigationTitle("Settings")
            .toolbar {
                if let onDismiss {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { onDismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                crashManager.refreshSummaries()
                Task {
                    await store.googleAccount.refreshSessionStatus()
                    warningErrorCount = await PrismLogCenter.shared.warningAndErrorCount()
                }
            }
            .confirmationDialog(
                "Sign out of Google?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await store.googleAccount.signOut()
                        store.showToast("Signed out of Google.")
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This signs you out of Google Search, YouTube, Gmail, and Google services across PrismDM.")
            }
        }
    }

    // MARK: - Google Account Section

    private var googleAccountSection: some View {
        Section {
            if store.googleAccount.isSignedIn, let profile = store.googleAccount.profile {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(PrismBrandPalette.crimsonAccent.gradient)
                            .frame(width: 44, height: 44)
                        Text(profile.initials)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(.headline)
                        Text(profile.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label("Signed in across Google services", systemImage: "checkmark.seal.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                Button {
                    store.presentGoogleSignIn(manageAccount: true)
                } label: {
                    Label("Manage Google Account", systemImage: "person.crop.circle")
                }

                Button("Sign Out of Google", role: .destructive) {
                    showSignOutConfirm = true
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(PrismBrandPalette.crimsonAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in with Google")
                                .font(.headline)
                            Text("Log in once to stay signed into Google Search, YouTube, Gmail, and websites using Google Sign-In.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        store.presentGoogleSignIn(manageAccount: false)
                    } label: {
                        HStack {
                            Spacer()
                            Label("Continue with Google", systemImage: "globe")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PrismBrandPalette.crimsonAccent)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Account")
        }
    }
}

// MARK: - Reusable Native iOS Settings Row

private struct SettingsCategoryRow: View {
    let title: String
    let systemImage: String
    let badgeColor: Color
    var trailingDetail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(badgeColor.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            if let trailingDetail {
                Text(trailingDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 1. General & Appearance Sub-Page

private struct GeneralSettingsView: View {
    @Bindable var store: BrowserStore
    @State private var homepageDraft: String = ""

    var body: some View {
        List {
            Section("Search & Navigation") {
                Picker("Default Search Engine", selection: Binding(
                    get: { store.selectedSearchEngine },
                    set: { store.selectSearchEngine($0) }
                )) {
                    ForEach(SearchEngineOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }

                HStack {
                    Text("Homepage")
                    Spacer()
                    TextField("Start Page", text: $homepageDraft)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .foregroundStyle(.secondary)
                        .onSubmit {
                            store.setHomepageURLString(homepageDraft)
                            store.showToast(homepageDraft.isEmpty ? "Homepage reset to Start Page" : "Homepage saved")
                        }
                }
            }

            Section("Display & Browsing") {
                Stepper(
                    value: Binding(
                        get: { store.settings.defaultPageZoom },
                        set: { store.setDefaultPageZoom($0) }
                    ),
                    in: 0.75...1.50,
                    step: 0.05
                ) {
                    HStack {
                        Text("Default Page Zoom")
                        Spacer()
                        Text("\(Int((store.settings.defaultPageZoom * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Toggle(
                    "Request Desktop Site by Default",
                    isOn: Binding(
                        get: { store.settings.defaultRequestDesktopSite },
                        set: { store.setDefaultRequestDesktopSite($0) }
                    )
                )

                Toggle(
                    "Smart Dark Mode for Websites",
                    isOn: Binding(
                        get: { store.globalDarkModeEnabled },
                        set: { _ in store.toggleGlobalDarkMode() }
                    )
                )

                Toggle(
                    "Auto-Hide Address Bar on Scroll",
                    isOn: Binding(
                        get: { store.settings.autoHideToolbarOnScroll },
                        set: { store.setAutoHideToolbarOnScroll($0) }
                    )
                )

                Toggle(
                    "Open External App Links (tel / mailto)",
                    isOn: Binding(
                        get: { store.settings.openExternalAppLinks },
                        set: { store.setOpenExternalAppLinks($0) }
                    )
                )
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("General & Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            homepageDraft = store.settings.homepageURLString
        }
    }
}

// MARK: - 2. Shield & Protection Sub-Page

private struct ShieldSettingsView: View {
    @Bindable var store: BrowserStore

    var body: some View {
        List {
            Section {
                Toggle(
                    "Ad & Tracker Blocker",
                    isOn: Binding(
                        get: { store.globalAdBlockEnabled },
                        set: { store.setGlobalAdBlockEnabled($0) }
                    )
                )

                if store.globalAdBlockEnabled {
                    Toggle(
                        "Block Ads (EasyList)",
                        isOn: Binding(
                            get: { store.settings.blockAdsEasyList },
                            set: { store.setEasyListEnabled($0) }
                        )
                    )

                    Toggle(
                        "Block Trackers (EasyPrivacy)",
                        isOn: Binding(
                            get: { store.settings.blockTrackersEasyPrivacy },
                            set: { store.setEasyPrivacyEnabled($0) }
                        )
                    )
                }

                Toggle(
                    "Block Pop-ups & Redirects",
                    isOn: Binding(
                        get: { store.settings.blockPopups },
                        set: { store.setBlockPopups($0) }
                    )
                )

                Toggle(
                    "HTTPS-Only Mode",
                    isOn: Binding(
                        get: { store.settings.httpsOnlyEnabled },
                        set: { store.setHTTPSOnlyEnabled($0) }
                    )
                )

                Toggle(
                    "Strip Tracking Parameters (UTM / fbclid)",
                    isOn: Binding(
                        get: { store.settings.stripTrackingParameters },
                        set: { store.setStripTrackingParameters($0) }
                    )
                )

                Toggle(
                    "Block JavaScript (Strict)",
                    isOn: Binding(
                        get: { store.settings.blockJavaScript },
                        set: { store.setBlockJavaScript($0) }
                    )
                )

                NavigationLink {
                    AllowlistedSitesView(store: store)
                } label: {
                    HStack {
                        Text("Allowlisted Sites")
                        Spacer()
                        Text("\(store.allowlistedHosts.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } footer: {
                Text("Offline WebKit Content Blocker lists run natively with zero remote filter requests. HTTPS-Only automatically falls back to HTTP if a site does not support TLS.")
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("Shield & Protection")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 3. Media & PrismPlayer Sub-Page

private struct MediaSettingsView: View {
    @Bindable var store: BrowserStore

    var body: some View {
        List {
            Section {
                Toggle(
                    "Video Detector & PrismPlayer Takeover",
                    isOn: Binding(
                        get: { store.settings.mediaInterceptionEnabled },
                        set: { store.setMediaInterceptionEnabled($0) }
                    )
                )

                Toggle(
                    "Auto-Play Web Videos",
                    isOn: Binding(
                        get: { store.settings.autoPlayVideos },
                        set: { store.setAutoPlayVideos($0) }
                    )
                )

                Toggle(
                    "Auto-Lock Landscape in Fullscreen",
                    isOn: Binding(
                        get: { store.settings.autoLockLandscapeInPlayer },
                        set: { store.setAutoLockLandscapeInPlayer($0) }
                    )
                )
            } footer: {
                Text("When Auto-Lock Landscape in Fullscreen is off, PrismPlayer follows your phone's orientation and respects iOS Portrait Orientation Lock. When enabled, PrismDM detects playable HLS/MP4 streams across frames and upgrades fullscreen playback to the Liquid Glass PrismPlayer.")
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("Media & PrismPlayer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 4. Tabs & Performance Sub-Page

private struct TabsPerformanceSettingsView: View {
    @Bindable var store: BrowserStore

    var body: some View {
        List {
            Section {
                Stepper(
                    "Active WebView Pool Limit: \(store.settings.maxLiveWebViews)",
                    value: Binding(
                        get: { store.settings.maxLiveWebViews },
                        set: { store.setMaxLiveWebViews($0) }
                    ),
                    in: 2...8
                )

                Toggle(
                    "Restore Tabs on Launch",
                    isOn: Binding(
                        get: { store.settings.restoreTabsOnStartup },
                        set: { store.setRestoreTabsOnStartup($0) }
                    )
                )

                Toggle(
                    "Close Incognito Tabs When Backgrounded",
                    isOn: Binding(
                        get: { store.settings.autoCloseIncognitoOnBackground },
                        set: { store.setAutoCloseIncognitoOnBackground($0) }
                    )
                )
            } footer: {
                Text("Inactive tabs beyond the pool limit are hibernated to disk snapshots to keep iPhone RAM usage low.")
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("Tabs & Performance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 5. Downloads & Engine Sub-Page

private struct DownloadsSettingsView: View {
    @Bindable var downloadStore: ParallelDownloadStore
    @State private var themeEngine = PrismThemeEngine.shared

    var body: some View {
        let tokens = themeEngine.tokens
        List {
            Section {
                Picker("Default Downloader", selection: $downloadStore.defaultDownloaderMode) {
                    ForEach(PrismDefaultDownloaderMode.allCases) { mode in
                        Text(mode.displayTitle).tag(mode)
                    }
                }

                Picker("HTTP Engine Backend", selection: $downloadStore.preferredHTTPBackend) {
                    Text("libcurl Multi-Range").tag(DownloadEngineKind.libcurl)
                    Text("iOS Background URLSession").tag(DownloadEngineKind.urlSession)
                }

                Stepper(
                    "Connections per Download: \(downloadStore.defaultConnectionsPerDownload)",
                    value: $downloadStore.defaultConnectionsPerDownload,
                    in: 1...16
                )

                Stepper(
                    "Max Concurrent Downloads: \(downloadStore.maxConcurrentDownloads)",
                    value: $downloadStore.maxConcurrentDownloads,
                    in: 1...6
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
                    .tint(tokens.accent)
                }
            } header: {
                Text("Parallel Download Engine (SDMCore & HLS)")
            } footer: {
                Text("PrismDM Multi-Thread uses parallel byte-range chunks for direct files (with Range:0-0 probing) and concurrent N-worker segment downloading for HLS (.m3u8) streams.")
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("Downloads & Engine")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 6. Privacy, Security & Data Sub-Page

private struct PrivacySecuritySettingsView: View {
    @Bindable var store: BrowserStore

    var body: some View {
        List {
            Section("Vault & App Privacy") {
                Toggle(
                    "Privacy Screen in App Switcher",
                    isOn: Binding(
                        get: { store.settings.privacyCurtainEnabled },
                        set: { store.setPrivacyCurtainEnabled($0) }
                    )
                )

                NavigationLink {
                    VaultPINSetupView(authService: store.authService)
                } label: {
                    HStack {
                        Label("Private Vault PIN", systemImage: "key.fill")
                        Spacer()
                        Text(store.authService.hasConfiguredPIN ? "Configured" : "Not Set")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Lock Private Vault & Incognito Now", role: .destructive) {
                    store.authService.lock()
                    store.showToast("Private Vault & Incognito locked.")
                }
            }

            Section("Browsing Data") {
                NavigationLink {
                    ClearBrowsingDataView(store: store)
                } label: {
                    Label("Clear Browsing Data…", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }

            Section("Session Diagnostics") {
                LabeledContent("Active WebView Pool", value: "\(store.webViewPool.liveTabCount) / \(store.webViewPool.maxLiveWebViews)")
                LabeledContent("Trackers Blocked This Session", value: "\(store.trackerMonitor.sessionTotalBlocked)")
                LabeledContent("Pop-ups Blocked This Session", value: "\(store.blockedPopupsCount)")
                LabeledContent("Offline Filter Shards", value: AdBlockManifestLoader.summary())
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("Privacy, Security & Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 7. About & Licenses Sub-Page

private struct AboutAndLicensesSettingsView: View {
    var body: some View {
        List {
            Section("Application") {
                LabeledContent(
                    "Version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                )
                LabeledContent(
                    "Build",
                    value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                )
            }

            Section("Native Engines & Legal") {
                LabeledContent("Download Core", value: ParallelDownloaderEngineDiagnostics.sdmCoreVersionSummary)
                LabeledContent("HLS Remux Core", value: ParallelDownloaderEngineDiagnostics.ffmpegVersionSummary)
                LabeledContent("Universal Player", value: PrismPlayerEngineDiagnostics.mpvAPIVersionSummary)
                LabeledContent("Vault Archive", value: VaultEngineDiagnostics.archiveEngineSummary)
                LabeledContent("Crash Diagnostics", value: PrismCrashManager.diagnosticsVersionSummary)
                LabeledContent("Media Bridge", value: "Schema v\(MediaInterceptorBridgeInfo.loadSchemaVersion())")

                NavigationLink("Engine & Open Source Licenses") {
                    OpenSourceLicensesView()
                }
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("About & Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Allowlisted Sites Manager

private struct AllowlistedSitesView: View {
    @Bindable var store: BrowserStore
    @State private var newHostInput = ""

    private var sortedHosts: [String] {
        store.allowlistedHosts.sorted()
    }

    var body: some View {
        List {
            Section("Add Trusted Domain") {
                HStack {
                    TextField("example.com", text: $newHostInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .onSubmit(addHost)
                    Button("Add", action: addHost)
                        .disabled(newHostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Sites With AdBlock Paused") {
                if sortedHosts.isEmpty {
                    ContentUnavailableView(
                        "No Allowlisted Sites",
                        systemImage: "shield.checkered",
                        description: Text("Ads and trackers are blocked on all websites.")
                    )
                } else {
                    ForEach(sortedHosts, id: \.self) { host in
                        Text(host)
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            store.removeAllowlistedHost(sortedHosts[idx])
                        }
                    }
                }
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("Allowlisted Sites")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addHost() {
        let trimmed = newHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addAllowlistedHost(trimmed)
        newHostInput = ""
    }
}

// MARK: - Granular Clear Browsing Data Screen

private struct ClearBrowsingDataView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var store: BrowserStore

    @State private var clearHistory = true
    @State private var clearCookies = true
    @State private var clearCaches = true
    @State private var clearTabSnapshots = true
    @State private var clearSitePreferences = false
    @State private var showConfirm = false
    @State private var isClearing = false

    private var hasAnySelection: Bool {
        clearHistory || clearCookies || clearCaches || clearTabSnapshots || clearSitePreferences
    }

    var body: some View {
        List {
            Section {
                Toggle("Browsing History", isOn: $clearHistory)
                Toggle("Cookies & Signed-In Sessions", isOn: $clearCookies)
                Toggle("Cached Files, Images & Web Storage", isOn: $clearCaches)
                Toggle("Saved Tab Previews & Snapshots", isOn: $clearTabSnapshots)
                Toggle("Site Preferences & AdBlock Allowlist", isOn: $clearSitePreferences)
            } footer: {
                if clearCookies && store.googleAccount.isSignedIn {
                    Text("Clearing cookies will also sign you out of Google and other websites. Bookmarks and Vault downloads are always preserved.")
                } else {
                    Text("Bookmarks and downloaded Vault files are never deleted.")
                }
            }

            Section {
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        if isClearing {
                            ProgressView()
                        } else {
                            Text("Clear Selected Data")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!hasAnySelection || isClearing)
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("Clear Browsing Data")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clear selected browsing data?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Now", role: .destructive) {
                Task { await performClear() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func performClear() async {
        isClearing = true
        defer { isClearing = false }

        var webTypes: Set<String> = []
        if clearCookies {
            webTypes.insert(WKWebsiteDataTypeCookies)
            webTypes.insert(WKWebsiteDataTypeSessionStorage)
        }
        if clearCaches {
            webTypes.insert(WKWebsiteDataTypeDiskCache)
            webTypes.insert(WKWebsiteDataTypeMemoryCache)
            webTypes.insert(WKWebsiteDataTypeFetchCache)
            webTypes.insert(WKWebsiteDataTypeOfflineWebApplicationCache)
            webTypes.insert(WKWebsiteDataTypeLocalStorage)
            webTypes.insert(WKWebsiteDataTypeIndexedDBDatabases)
            webTypes.insert(WKWebsiteDataTypeServiceWorkerRegistrations)
        }
        if !webTypes.isEmpty {
            await WKWebsiteDataStore.default().removeData(ofTypes: webTypes, modifiedSince: .distantPast)
        }

        if clearCookies {
            await store.googleAccount.refreshSessionStatus()
        }

        if clearHistory, let entries = try? modelContext.fetch(FetchDescriptor<HistoryRecord>()) {
            for entry in entries {
                modelContext.delete(entry)
            }
            try? modelContext.save()
        }

        if clearTabSnapshots {
            store.webViewPool.clearDiskSnapshotsAndStates()
        }

        if clearSitePreferences {
            store.clearAllSitePreferences()
        }

        store.showToast("Selected browsing data cleared.")
        dismiss()
    }
}

// MARK: - Vault PIN Setup View

private struct VaultPINSetupView: View {
    @Bindable var authService: BiometricAuthService
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var feedbackMessage: String?

    var body: some View {
        Form {
            Section {
                SecureField("New PIN (4+ digits)", text: $newPIN)
                    .keyboardType(.numberPad)
                SecureField("Confirm PIN", text: $confirmPIN)
                    .keyboardType(.numberPad)

                Button(authService.hasConfiguredPIN ? "Update Custom PIN" : "Save Custom PIN") {
                    guard newPIN == confirmPIN else {
                        feedbackMessage = "PIN entries do not match."
                        return
                    }
                    if authService.configurePIN(newPIN) {
                        newPIN = ""
                        confirmPIN = ""
                        feedbackMessage = "Custom Private Vault PIN saved securely in Keychain."
                    } else {
                        feedbackMessage = authService.lastErrorMessage ?? "Failed to save PIN."
                    }
                }
                .disabled(newPIN.count < 4 || confirmPIN.count < 4)
            } header: {
                Text("Custom Backup PIN")
            } footer: {
                Text("Stored as a salted SHA-256 hash in iOS Keychain. Works as a fallback alongside \(authService.biometryLabel).")
            }

            if let feedbackMessage {
                Section {
                    Text(feedbackMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if authService.hasConfiguredPIN {
                Section {
                    Button("Remove Custom PIN", role: .destructive) {
                        authService.removeConfiguredPIN()
                        feedbackMessage = "Custom PIN removed."
                    }
                }
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("Private Vault PIN")
        .navigationBarTitleDisplayMode(.inline)
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
            "KSCrash (2.6.1)",
            "MIT License • Copyright Karl Stenerud",
            "Provides 100% local offline Mach exception, POSIX signal, C++/NSException, and watchdog crash report capture formatted in Apple symbolicated style for on-device diagnostics."
        ),
        (
            "EasyList & EasyPrivacy Filter Packs",
            "GPL-3.0 / CC-BY-SA-3.0",
            "Compiled and sharded at build time into WebKit Content Blocker JSON lists (<= 125,000 rules per shard) for offline ad and tracker blocking."
        ),
    ]

    @State private var themeEngine = PrismThemeEngine.shared

    var body: some View {
        let tokens = themeEngine.tokens
        List {
            ForEach(notices, id: \.title) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.license)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tokens.accent)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle("Open Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
