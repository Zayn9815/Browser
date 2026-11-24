import ParallelDownloader
import PrismCore
import SwiftUI

public struct BrowserMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var store: BrowserStore
    @Bindable private var downloadStore: ParallelDownloadStore
    @State private var themeEngine = PrismThemeEngine.shared

    private let onOpenDownloads: () -> Void
    private let onOpenVault: () -> Void
    private let onOpenSettings: () -> Void

    private let navGridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    public init(
        store: BrowserStore,
        downloadStore: ParallelDownloadStore,
        onOpenDownloads: @escaping () -> Void,
        onOpenVault: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.downloadStore = downloadStore
        self.onOpenDownloads = onOpenDownloads
        self.onOpenVault = onOpenVault
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        NavigationStack {
            List {
                // 1. Top Quick Navigation Grid (Downloads, Vault, Library, Settings, New Tab, Private, Scan QR, Tabs)
                Section {
                    LazyVGrid(columns: navGridColumns, spacing: 12) {
                        navTile(
                            title: "Downloads",
                            icon: "arrow.down.circle.fill",
                            badgeCount: downloadStore.activeCount,
                            tokens: tokens
                        ) {
                            dismiss()
                            onOpenDownloads()
                        }

                        navTile(
                            title: "Vault",
                            icon: "lock.doc.fill",
                            tokens: tokens
                        ) {
                            dismiss()
                            onOpenVault()
                        }

                        navTile(
                            title: "Library",
                            icon: "books.vertical.fill",
                            tokens: tokens
                        ) {
                            dismiss()
                            store.isBookmarksHistoryPresented = true
                        }

                        navTile(
                            title: "Settings",
                            icon: "gearshape.fill",
                            tokens: tokens
                        ) {
                            dismiss()
                            onOpenSettings()
                        }

                        navTile(
                            title: "New Tab",
                            icon: "plus.square.fill",
                            tokens: tokens
                        ) {
                            dismiss()
                            store.createTab(url: nil, isIncognito: false, activate: true)
                        }

                        navTile(
                            title: "Private",
                            icon: "eye.slash.fill",
                            tintOverride: .purple,
                            tokens: tokens
                        ) {
                            dismiss()
                            store.createTab(url: nil, isIncognito: true, activate: true)
                        }

                        navTile(
                            title: "Scan QR",
                            icon: "qrcode.viewfinder",
                            tokens: tokens
                        ) {
                            dismiss()
                            store.isQRScannerPresented = true
                        }

                        navTile(
                            title: "Tabs",
                            icon: "square.on.square.fill",
                            badgeCount: store.tabs.count,
                            tokens: tokens
                        ) {
                            dismiss()
                            store.isTabGridPresented = true
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)

                // 2. Navigation, Shield & yt-dlp Media Extraction
                Section("Quick Tools") {
                    if store.activeTab.canGoForward {
                        Button {
                            dismiss()
                            store.goForward()
                        } label: {
                            Label("Go Forward", systemImage: "chevron.right")
                        }
                    }

                    Button {
                        dismiss()
                        store.isSiteMenuPresented = true
                    } label: {
                        HStack {
                            Label("Shield & Site Controls", systemImage: "shield.lefthalf.filled")
                            Spacer()
                            if store.activeTab.blockedTrackerCount > 0 {
                                Text("\(store.activeTab.blockedTrackerCount) blocked")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(tokens.accent)
                            }
                        }
                    }

                    if let pageURL = store.activeTab.currentURL {
                        Button {
                            dismiss()
                            let ua = store.webViewPool.existingWebView(for: store.activeTabID)?.customUserAgent
                            let ctx = BrowserSessionContext(
                                userAgent: ua,
                                pageReferer: pageURL,
                                isIncognito: store.activeTab.isIncognito
                            )
                            store.onOpenYTDLPPicker?(pageURL, ctx)
                        } label: {
                            Label("Download with yt-dlp", systemImage: "arrow.down.to.line.circle.fill")
                                .foregroundStyle(tokens.accent)
                        }
                    }

                    Button {
                        dismiss()
                        store.translateActivePage()
                    } label: {
                        Label("Translate Page", systemImage: "translate")
                    }
                }
                .prismGlassListRow()

                // 3. Page Controls & Reading
                Section("Page Controls & Reading") {
                    Stepper(
                        value: Binding(
                            get: { store.settings.defaultPageZoom },
                            set: { store.setDefaultPageZoom($0) }
                        ),
                        in: 0.75...1.50,
                        step: 0.05
                    ) {
                        HStack {
                            Label("Page Zoom", systemImage: "textformat.size")
                            Spacer()
                            Text("\(Int((store.settings.defaultPageZoom * 100).rounded()))%")
                                .foregroundStyle(tokens.secondaryText)
                                .monospacedDigit()
                        }
                    }

                    Toggle(
                        "Dark Mode on This Site",
                        isOn: Binding(
                            get: { store.isActiveTabDarkModeEnabled },
                            set: { _ in store.toggleActiveSiteDarkMode() }
                        )
                    )

                    Toggle(
                        "Request Desktop Site",
                        isOn: Binding(
                            get: { store.activeTab.preferDesktopUserAgent },
                            set: { _ in store.toggleActiveTabDesktopUserAgent() }
                        )
                    )

                    Button {
                        dismiss()
                        store.navigateToHomepage()
                    } label: {
                        Label("Go to Start Page / Home", systemImage: "house")
                    }

                    Button {
                        dismiss()
                        Task { await store.extractReaderArticle() }
                    } label: {
                        Label("Open Reader Mode", systemImage: "doc.plaintext")
                    }

                    Button {
                        dismiss()
                        store.findInPageService.isPresented = true
                        store.findInPageService.presentNativeFindNavigator(
                            in: store.webViewPool.existingWebView(for: store.activeTabID)
                        )
                    } label: {
                        Label("Find in Page", systemImage: "magnifyingglass")
                    }
                }
                .prismGlassListRow()

                // 4. Bookmarks, Offline Export & Share
                Section("Bookmarks & Export") {
                    Button {
                        store.bookmarkActivePage()
                        dismiss()
                    } label: {
                        Label("Add Bookmark", systemImage: "bookmark.fill")
                    }

                    Button {
                        dismiss()
                        Task { await store.exportCurrentPageAsWebArchive() }
                    } label: {
                        Label("Save Offline (.webarchive) to Vault", systemImage: "square.and.arrow.down.on.square")
                    }

                    if let url = store.activeTab.currentURL {
                        ShareLink(item: url) {
                            Label("Share Page", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .prismGlassListRow()
            }
            .listStyle(.insetGrouped)
            .prismThemedScrollChrome()
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .prismThemedSheetChrome()
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }

    private func navTile(
        title: String,
        icon: String,
        badgeCount: Int = 0,
        tintOverride: Color? = nil,
        tokens: PrismThemeTokens,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tintOverride ?? tokens.accent)
                        .frame(width: 50, height: 50)
                        .prismGlassCard(cornerRadius: 15)

                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(tokens.accentText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tokens.accent, in: Capsule())
                            .offset(x: 6, y: -5)
                    }
                }

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
