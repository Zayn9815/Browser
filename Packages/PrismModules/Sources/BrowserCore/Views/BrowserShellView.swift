import AdBlockEngine
import MediaInterceptor
import ParallelDownloader
import PrismCore
import PrismPlayer
import SDMCore
import SwiftData
import SwiftUI
import Translation
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

    @State private var themeEngine = PrismThemeEngine.shared

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

    private var shouldShowTransferMiniBar: Bool {
        downloadStore.activeCount > 0 || audioCenter.hasActiveTrack
    }

    private var isTopBarMode: Bool {
        store.settings.searchBarPosition == .top
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        browserViewport(tokens: tokens)
            .tint(tokens.accent)
            .onAppear {
                store.attachModelContext(modelContext)
                downloadStore.attachModelContext(modelContext)
            }
            .translationTask(store.translationService.configuration) { session in
                await store.translationService.runTranslationSession(session)
            }
            .sheet(
                isPresented: Binding(
                    get: { selectedTab == .downloads },
                    set: { presented in
                        if !presented && selectedTab == .downloads {
                            selectedTab = .browser
                        }
                    }
                )
            ) {
                downloadsTabContent()
                    .tint(tokens.accent)
            }
            .sheet(
                isPresented: Binding(
                    get: { selectedTab == .vault },
                    set: { presented in
                        if !presented && selectedTab == .vault {
                            selectedTab = .browser
                        }
                    }
                )
            ) {
                VaultBrowserView(
                    authService: store.authService,
                    audioCenter: audioCenter,
                    onPlayMediaFile: onPlayVaultMedia,
                    onDismiss: { selectedTab = .browser }
                )
                .tint(tokens.accent)
            }
            .sheet(
                isPresented: Binding(
                    get: { selectedTab == .settings },
                    set: { presented in
                        if !presented && selectedTab == .settings {
                            selectedTab = .browser
                        }
                    }
                )
            ) {
                BrowserSettingsView(
                    store: store,
                    downloadStore: downloadStore,
                    onDismiss: { selectedTab = .browser }
                )
                .tint(tokens.accent)
            }
            .sheet(isPresented: $store.isBrowserMenuPresented) {
                BrowserMenuSheet(
                    store: store,
                    downloadStore: downloadStore,
                    onOpenDownloads: { selectedTab = .downloads },
                    onOpenVault: { selectedTab = .vault },
                    onOpenSettings: { selectedTab = .settings }
                )
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

    private func browserViewport(tokens: PrismThemeTokens) -> some View {
        ZStack {
            tokens.backgroundTop
                .ignoresSafeArea()

            // Primary content canvas: Private Lock, Start Page, or WebView
            if store.activeTab.isIncognito && !store.authService.isPrivateUnlocked {
                VaultLockOverlayView(
                    authService: store.authService,
                    title: "Private Tab Locked",
                    subtitle: "Authenticate to resume your Private Incognito session."
                )
            } else if store.activeTab.urlString.isEmpty {
                StartPageView(
                    store: store,
                    bookmarks: bookmarks,
                    onOpenDownloads: { selectedTab = .downloads },
                    onOpenVault: { selectedTab = .vault }
                )
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

            // Floating chrome overlay respecting top & bottom safe areas (Home Indicator + Dynamic Island)
            VStack(spacing: 8) {
                // Top Omnibox mode
                if isTopBarMode {
                    if !store.isChromeMinimized || store.isOmniboxExpanded || store.activeTab.urlString.isEmpty {
                        FloatingOmniboxBar(store: store, isTopMode: true)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        collapsedRevealPill(tokens: tokens)
                            .padding(.top, 4)
                            .transition(.opacity)
                    }
                }

                // Translation banner (when active)
                if store.translationService.isBannerVisible {
                    translationBanner(tokens: tokens)
                        .padding(.horizontal, 12)
                        .padding(.top, isTopBarMode ? 0 : 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Status toast
                if let toast = store.statusToastMessage {
                    Text(toast)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tokens.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, isTopBarMode ? 0 : 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                // Detected media pill (Play / Download)
                browserOverlayContent()

                // Find in page glass bar
                if store.findInPageService.isPresented {
                    findInPageGlassBar(tokens: tokens)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Floating transfer/audio mini-bar (ONLY when active)
                if shouldShowTransferMiniBar {
                    TransferMiniBarView(
                        downloadStore: downloadStore,
                        audioCenter: audioCenter,
                        onOpenDownloads: { selectedTab = .downloads }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, isTopBarMode ? 12 : 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Bottom Omnibox mode (default) with ergonomic Home-bar cushion (+12 pt above safe area)
                if !isTopBarMode {
                    if !store.isChromeMinimized || store.isOmniboxExpanded || store.activeTab.urlString.isEmpty {
                        FloatingOmniboxBar(store: store, isTopMode: false)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        collapsedRevealPill(tokens: tokens)
                            .padding(.bottom, 12)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private func translationBanner(tokens: PrismThemeTokens) -> some View {
        let svc = store.translationService
        return HStack(spacing: 8) {
            if svc.isTranslating {
                ProgressView()
                    .controlSize(.small)
                    .tint(tokens.accent)
            } else {
                Image(systemName: "translate")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tokens.accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(svc.statusMessage ?? "Translate to \(svc.selectedTarget.displayName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Menu {
                ForEach(TranslationTargetLanguage.supported) { lang in
                    Button {
                        store.translateActivePage(target: lang)
                    } label: {
                        HStack {
                            Text(lang.displayName)
                            if lang == svc.selectedTarget {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(svc.selectedTarget.code.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tokens.accentText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tokens.accent, in: Capsule())
            }

            if svc.isShowingTranslated {
                Button("Original") {
                    store.restoreOriginalActivePage()
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tokens.primaryText)
                .buttonStyle(.borderless)
            } else if svc.showGoogleFallbackOffer {
                Button("Google") {
                    store.openGoogleTranslateFallback()
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(tokens.accent)
                .buttonStyle(.borderless)
            }

            Button {
                svc.dismissBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(tokens.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss Translation Banner")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tokens.cardSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.glassStroke, lineWidth: 1))
    }

    private func collapsedRevealPill(tokens: PrismThemeTokens) -> some View {
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
            .foregroundStyle(tokens.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func findInPageGlassBar(tokens: PrismThemeTokens) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Find on page", text: $store.findInPageService.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(tokens.primaryText)
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
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                Button {
                    Task {
                        await store.findInPageService.findNext(
                            in: store.webViewPool.existingWebView(for: store.activeTabID),
                            backwards: false
                        )
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                Button {
                    store.findInPageService.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
            }
            .foregroundStyle(tokens.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
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
