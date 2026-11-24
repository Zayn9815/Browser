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
                BrowserSettingsView(store: store, downloadStore: downloadStore)
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
        .sheet(isPresented: $store.isGoogleSignInPresented) {
            GoogleSignInSheet(
                accountManager: store.googleAccount,
                openAccountManagement: store.openGoogleAccountManagement,
                onComplete: { message in
                    store.showToast(message)
                }
            )
        }
        .sheet(item: $store.activePopupSession) { session in
            PopupWebViewSheet(session: session) {
                store.activePopupSession = nil
                Task {
                    await store.googleAccount.refreshSessionStatus()
                }
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
                        guard store.settings.autoHideToolbarOnScroll else {
                            if store.isChromeMinimized { store.isChromeMinimized = false }
                            return
                        }
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        HStack(spacing: 8) {
                            Image(systemName: store.activeTab.isIncognito ? "eye.slash.fill" : "pyramid.fill")
                                .font(.title2)
                                .foregroundStyle(store.activeTab.isIncognito ? .purple : PrismBrandPalette.crimsonAccent)
                            Text(store.activeTab.isIncognito ? "Private Incognito" : "PrismDM")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Spacer()

                        if !store.activeTab.isIncognito {
                            Button {
                                store.presentGoogleSignIn(manageAccount: store.googleAccount.isSignedIn)
                            } label: {
                                if store.googleAccount.isSignedIn, let profile = store.googleAccount.profile {
                                    HStack(spacing: 6) {
                                        Text(profile.initials)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 26, height: 26)
                                            .background(PrismBrandPalette.crimsonAccent, in: .circle)
                                        Text("Google")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(.leading, 4)
                                    .padding(.trailing, 10)
                                    .padding(.vertical, 4)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                } else {
                                    Label("Sign In", systemImage: "person.crop.circle")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(store.activeTab.isIncognito
                        ? "Non-persistent cookies, zero history saved, biometric-protected."
                        : (store.globalAdBlockEnabled
                            ? "Shield active • \(store.adBlockCompiler.totalActiveRules > 0 ? "\(store.adBlockCompiler.totalActiveRules) offline rules" : AdBlockManifestLoader.summary())"
                            : "AdBlock paused • Configure protection in Settings"))
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
