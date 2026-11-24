import AdBlockEngine
import PrismCore
import SwiftData
import SwiftUI
import VaultManager

public struct StartPageView: View {
    @Bindable private var store: BrowserStore
    @State private var themeEngine = PrismThemeEngine.shared
    private let bookmarks: [BookmarkRecord]
    private let onOpenDownloads: () -> Void
    private let onOpenVault: () -> Void
    private let onOpenSettings: (() -> Void)?

    @State private var isEditingShortcuts = false
    @State private var showAddShortcutSheet = false
    @State private var editingShortcut: StartPageShortcut?
    @State private var draftTitle = ""
    @State private var draftURL = ""

    private let shortcutColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    public init(
        store: BrowserStore,
        bookmarks: [BookmarkRecord],
        onOpenDownloads: @escaping () -> Void,
        onOpenVault: @escaping () -> Void,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.store = store
        self.bookmarks = bookmarks
        self.onOpenDownloads = onOpenDownloads
        self.onOpenVault = onOpenVault
        self.onOpenSettings = onOpenSettings
    }

    private var isTopBarMode: Bool {
        store.settings.searchBarPosition == .top
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        ZStack {
            PrismAtmosphericWallpaperView(themeEngine: themeEngine)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection(tokens: tokens)
                    shortcutsSection(tokens: tokens)
                    privacyReportCard(tokens: tokens)
                    quickActionsSection(tokens: tokens)
                    if !bookmarks.isEmpty {
                        bookmarksSection(tokens: tokens)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, isTopBarMode ? 84 : 22)
                .padding(.bottom, isTopBarMode ? 64 : 132)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showAddShortcutSheet) {
            shortcutEditorSheet(isEditingExisting: false)
                .prismThemedSheetChrome()
        }
        .sheet(item: $editingShortcut) { item in
            shortcutEditorSheet(isEditingExisting: true, existingID: item.id)
                .prismThemedSheetChrome()
        }
    }

    // MARK: - Top Brand & Google Account Pill

    private func headerSection(tokens: PrismThemeTokens) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image(systemName: store.activeTab.isIncognito ? "eye.slash.fill" : "pyramid.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(store.activeTab.isIncognito ? Color.purple : tokens.accent)
                    .shadow(color: (store.activeTab.isIncognito ? Color.purple : tokens.accent).opacity(0.45), radius: 8)

                Text(store.activeTab.isIncognito ? "Private" : "PrismDM")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(tokens.primaryText)
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
                                .foregroundStyle(tokens.accentText)
                                .frame(width: 26, height: 26)
                                .background(tokens.accent, in: .circle)
                            Text("Google")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tokens.primaryText)
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 11)
                        .padding(.vertical, 4)
                        .prismGlassPill(interactive: true)
                    } else {
                        Label("Sign In", systemImage: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tokens.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .prismGlassPill(interactive: true)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Safari iOS 26 Style 4-Column Favorites / Shortcuts Grid

    private func shortcutsSection(tokens: PrismThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Favorites")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tokens.primaryText)

                Spacer()

                if isEditingShortcuts {
                    Button {
                        draftTitle = ""
                        draftURL = ""
                        showAddShortcutSheet = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tokens.accent)
                    }
                    .buttonStyle(.borderless)
                    .padding(.trailing, 8)
                }

                Button(isEditingShortcuts ? "Done" : "Edit") {
                    withAnimation(.snappy(duration: 0.22)) {
                        isEditingShortcuts.toggle()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tokens.accent)
                .buttonStyle(.borderless)
            }

            LazyVGrid(columns: shortcutColumns, spacing: 16) {
                ForEach(Array(store.shortcutStore.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    shortcutTile(shortcut: shortcut, index: index, tokens: tokens)
                        .onAppear {
                            store.shortcutStore.fetchFaviconIfNeeded(for: shortcut)
                        }
                }

                if isEditingShortcuts || store.shortcutStore.shortcuts.count < 8 {
                    Button {
                        draftTitle = ""
                        draftURL = ""
                        showAddShortcutSheet = true
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(tokens.accent)
                                .frame(width: 60, height: 60)
                                .prismGlassCard(cornerRadius: 16)

                            Text("Add")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tokens.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func shortcutTile(shortcut: StartPageShortcut, index: Int, tokens: PrismThemeTokens) -> some View {
        let cachedImage = store.shortcutStore.cachedFaviconsByHost[shortcut.host]
        return ZStack(alignment: .topTrailing) {
            Button {
                if isEditingShortcuts {
                    draftTitle = shortcut.title
                    draftURL = shortcut.urlString
                    editingShortcut = shortcut
                } else if let url = shortcut.url {
                    store.navigate(to: url)
                }
            } label: {
                VStack(spacing: 7) {
                    ZStack {
                        if let cachedImage {
                            Image(uiImage: cachedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Color.prismHex(shortcut.brandHex).gradient)
                                    .frame(width: 36, height: 36)
                                Text(shortcut.monogram)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .frame(width: 60, height: 60)
                    .prismGlassCard(cornerRadius: 16)

                    Text(shortcut.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tokens.primaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .contextMenu {
                if let url = shortcut.url {
                    Button {
                        store.createTab(url: url, isIncognito: store.activeTab.isIncognito, activate: true)
                    } label: {
                        Label("Open in New Tab", systemImage: "plus.square.on.square")
                    }
                }

                Button {
                    draftTitle = shortcut.title
                    draftURL = shortcut.urlString
                    editingShortcut = shortcut
                } label: {
                    Label("Edit Shortcut", systemImage: "pencil")
                }

                if index > 0 {
                    Button {
                        withAnimation(.snappy) {
                            store.shortcutStore.moveShortcut(id: shortcut.id, by: -1)
                        }
                    } label: {
                        Label("Move Left", systemImage: "arrow.left")
                    }
                }

                if index < store.shortcutStore.shortcuts.count - 1 {
                    Button {
                        withAnimation(.snappy) {
                            store.shortcutStore.moveShortcut(id: shortcut.id, by: 1)
                        }
                    } label: {
                        Label("Move Right", systemImage: "arrow.right")
                    }
                }

                Button(role: .destructive) {
                    withAnimation(.snappy) {
                        store.shortcutStore.removeShortcut(id: shortcut.id)
                    }
                } label: {
                    Label("Remove Shortcut", systemImage: "trash")
                }
            }

            if isEditingShortcuts {
                Button {
                    withAnimation(.snappy) {
                        store.shortcutStore.removeShortcut(id: shortcut.id)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white, tokens.destructive)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .offset(x: 2, y: -4)
            }
        }
    }

    // MARK: - Safari iOS 26 Style Frosted Privacy Report Glass Card

    private func privacyReportCard(tokens: PrismThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy Report")
                .font(.title3.weight(.bold))
                .foregroundStyle(tokens.primaryText)

            Button {
                onOpenSettings?()
            } label: {
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: store.activeTab.isIncognito
                            ? "lock.shield.fill"
                            : (store.globalAdBlockEnabled ? "shield.lefthalf.filled" : "shield.slash"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(store.activeTab.isIncognito ? .purple : tokens.accent)

                        Text("\(store.trackerMonitor.sessionTotalBlocked)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(tokens.primaryText)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.activeTab.isIncognito
                            ? "Private Incognito session active. Zero cookies or history saved."
                            : (store.globalAdBlockEnabled
                                ? "PrismDM Shield active with \(store.adBlockCompiler.totalActiveRules > 0 ? "\(store.adBlockCompiler.totalActiveRules) offline rules" : AdBlockManifestLoader.summary())."
                                : "AdBlock paused. Tap to configure Shield & YouTube Ad-Free protection."))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(tokens.primaryText)
                            .multilineTextAlignment(.leading)

                        if !store.activeTab.isIncognito && store.settings.youTubeAdShieldEnabled && store.globalAdBlockEnabled {
                            Text("EasyList • EasyPrivacy • YouTube Ad-Free Shield")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tokens.secondaryText)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .prismGlassCard(cornerRadius: 22)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Quick Actions

    private func quickActionsSection(tokens: PrismThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.title3.weight(.bold))
                .foregroundStyle(tokens.primaryText)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                quickActionTile(title: "Downloads", icon: "arrow.down.circle.fill", tokens: tokens, action: onOpenDownloads)
                quickActionTile(title: "Vault", icon: "lock.doc.fill", tokens: tokens, action: onOpenVault)
                quickActionTile(title: "Library", icon: "books.vertical.fill", tokens: tokens) {
                    store.isBookmarksHistoryPresented = true
                }
                quickActionTile(title: "Scan QR", icon: "qrcode.viewfinder", tokens: tokens) {
                    store.isQRScannerPresented = true
                }
            }
        }
    }

    private func quickActionTile(
        title: String,
        icon: String,
        tokens: PrismThemeTokens,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tokens.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tokens.primaryText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .prismGlassCard(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Bookmarks

    private func bookmarksSection(tokens: PrismThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bookmarks")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tokens.primaryText)
                Spacer()
                Button("Show All") {
                    store.isBookmarksHistoryPresented = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tokens.accent)
                .buttonStyle(.borderless)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(bookmarks.prefix(6)) { bookmark in
                    Button {
                        if let url = URL(string: bookmark.urlString) {
                            store.navigate(to: url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tokens.primaryText)
                                .lineLimit(1)
                            Text(URL(string: bookmark.urlString)?.host ?? bookmark.urlString)
                                .font(.caption2)
                                .foregroundStyle(tokens.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .prismGlassCard(cornerRadius: 16)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Shortcut Editor Sheet

    private func shortcutEditorSheet(isEditingExisting: Bool, existingID: UUID? = nil) -> some View {
        NavigationStack {
            Form {
                Section("Shortcut Details") {
                    TextField("Title (e.g. YouTube)", text: $draftTitle)
                    TextField("URL (e.g. https://youtube.com)", text: $draftURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                .prismGlassListRow()

                if isEditingExisting {
                    Section {
                        Button("Reset All Shortcuts to Defaults", role: .destructive) {
                            store.shortcutStore.resetToDefaults()
                            editingShortcut = nil
                        }
                    }
                    .prismGlassListRow()
                }
            }
            .prismThemedScrollChrome()
            .navigationTitle(isEditingExisting ? "Edit Shortcut" : "Add Shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddShortcutSheet = false
                        editingShortcut = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isEditingExisting, let existingID {
                            store.shortcutStore.updateShortcut(id: existingID, title: draftTitle, rawURL: draftURL)
                            editingShortcut = nil
                        } else {
                            store.shortcutStore.addShortcut(title: draftTitle, rawURL: draftURL)
                            showAddShortcutSheet = false
                        }
                    }
                    .disabled(draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
