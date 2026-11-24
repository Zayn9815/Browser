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

    @State private var isEditingShortcuts = false
    @State private var showAddShortcutSheet = false
    @State private var editingShortcut: StartPageShortcut?
    @State private var draftTitle = ""
    @State private var draftURL = ""

    private let shortcutColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    public init(
        store: BrowserStore,
        bookmarks: [BookmarkRecord],
        onOpenDownloads: @escaping () -> Void,
        onOpenVault: @escaping () -> Void
    ) {
        self.store = store
        self.bookmarks = bookmarks
        self.onOpenDownloads = onOpenDownloads
        self.onOpenVault = onOpenVault
    }

    private var isTopBarMode: Bool {
        store.settings.searchBarPosition == .top
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        ZStack {
            PrismAtmosphericWallpaperView(themeEngine: themeEngine)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerSection(tokens: tokens)
                    shortcutsSection(tokens: tokens)
                    quickActionsSection(tokens: tokens)
                    if !bookmarks.isEmpty {
                        bookmarksSection(tokens: tokens)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, isTopBarMode ? 84 : 24)
                .padding(.bottom, isTopBarMode ? 60 : 128)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showAddShortcutSheet) {
            shortcutEditorSheet(isEditingExisting: false)
        }
        .sheet(item: $editingShortcut) { item in
            shortcutEditorSheet(isEditingExisting: true, existingID: item.id)
        }
    }

    private func headerSection(tokens: PrismThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: store.activeTab.isIncognito ? "eye.slash.fill" : "pyramid.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(store.activeTab.isIncognito ? Color.purple : tokens.accent)
                    Text(store.activeTab.isIncognito ? "Private Incognito" : "PrismDM")
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
                            .padding(.trailing, 10)
                            .padding(.vertical, 4)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        } else {
                            Label("Sign In", systemImage: "person.crop.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tokens.primaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: store.activeTab.isIncognito
                    ? "lock.shield.fill"
                    : (store.globalAdBlockEnabled ? "shield.lefthalf.filled" : "shield.slash"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(store.activeTab.isIncognito ? .purple : tokens.accent)

                Text(store.activeTab.isIncognito
                    ? "Ephemeral session • Zero history • Biometric-locked"
                    : (store.globalAdBlockEnabled
                        ? "Shield active • \(store.adBlockCompiler.totalActiveRules > 0 ? "\(store.adBlockCompiler.totalActiveRules) offline rules" : AdBlockManifestLoader.summary())"
                        : "AdBlock paused • Configure in Settings"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tokens.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tokens.cardSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(tokens.hairline, lineWidth: 1))
        }
    }

    private func shortcutsSection(tokens: PrismThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shortcuts")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tokens.primaryText)

                Spacer()

                if isEditingShortcuts {
                    Button {
                        draftTitle = ""
                        draftURL = ""
                        showAddShortcutSheet = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption.weight(.semibold))
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(tokens.accent)
                .buttonStyle(.borderless)
            }

            LazyVGrid(columns: shortcutColumns, spacing: 14) {
                ForEach(Array(store.shortcutStore.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    shortcutTile(shortcut: shortcut, index: index, tokens: tokens)
                        .onAppear {
                            store.shortcutStore.fetchFaviconIfNeeded(for: shortcut)
                        }
                }

                // Always-visible Add tile in edit mode (or when grid is sparse)
                if isEditingShortcuts || store.shortcutStore.shortcuts.count < 8 {
                    Button {
                        draftTitle = ""
                        draftURL = ""
                        showAddShortcutSheet = true
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(tokens.cardSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(tokens.hairline, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                                    )
                                    .frame(width: 56, height: 56)

                                Image(systemName: "plus")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(tokens.accent)
                            }
                            Text("Add")
                                .font(.caption2.weight(.medium))
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
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(tokens.cardSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(tokens.glassStroke.opacity(0.65), lineWidth: 0.9)
                            )
                            .frame(width: 56, height: 56)

                        if let cachedImage {
                            Image(uiImage: cachedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Color.prismHex(shortcut.brandHex).gradient)
                                    .frame(width: 34, height: 34)
                                Text(shortcut.monogram)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    Text(shortcut.title)
                        .font(.caption2.weight(.medium))
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

    private func quickActionsSection(tokens: PrismThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.headline.weight(.bold))
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
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tokens.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tokens.primaryText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tokens.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tokens.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func bookmarksSection(tokens: PrismThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bookmarks")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tokens.primaryText)
                Spacer()
                Button("All") {
                    store.isBookmarksHistoryPresented = true
                }
                .font(.caption.weight(.semibold))
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
                        .background(
                            ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true)
                                .fill(tokens.cardSurface)
                        )
                        .overlay(
                            ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true)
                                .strokeBorder(tokens.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
            .containerShape(.rect(cornerRadius: 18))
        }
    }

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

                if isEditingExisting {
                    Section {
                        Button("Reset All Shortcuts to Defaults", role: .destructive) {
                            store.shortcutStore.resetToDefaults()
                            editingShortcut = nil
                        }
                    }
                }
            }
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
