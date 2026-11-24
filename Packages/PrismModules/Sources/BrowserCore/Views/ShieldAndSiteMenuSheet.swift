import PrismCore
import SwiftData
import SwiftUI
import VaultManager

public struct ShieldAndSiteMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var store: BrowserStore
    @State private var themeEngine = PrismThemeEngine.shared

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        NavigationStack {
            List {
                Section("Connection & Privacy Shield") {
                    HStack(spacing: 12) {
                        Image(systemName: store.activeTab.hasOnlySecureContent ? "lock.shield.fill" : "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(store.activeTab.hasOnlySecureContent ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.activeTab.displayHost)
                                .font(.headline)
                            Text(store.activeTab.hasOnlySecureContent
                                ? "TLS Encrypted Connection (HTTPS)"
                                : "Unencrypted or Mixed Content")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack {
                        Label("Trackers & Ads Blocked", systemImage: "shield.lefthalf.filled")
                        Spacer()
                        Text("\(store.activeTab.blockedTrackerCount)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(tokens.accent)
                    }

                    Toggle(
                        "Block Ads & Trackers on This Site",
                        isOn: Binding(
                            get: { store.isActiveSiteAdBlockEnabled },
                            set: { _ in store.toggleActiveSiteAdBlock() }
                        )
                    )
                }

                Section("Page Appearance & Reading") {
                    Button {
                        dismiss()
                        store.translateActivePage()
                    } label: {
                        Label("Translate Page", systemImage: "translate")
                    }

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
                                .foregroundStyle(.secondary)
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

                Section("Library & Offline Export") {
                    Button {
                        store.bookmarkActivePage()
                        dismiss()
                    } label: {
                        Label("Add Bookmark", systemImage: "bookmark.fill")
                    }

                    Button {
                        dismiss()
                        store.isBookmarksHistoryPresented = true
                    } label: {
                        Label("Bookmarks & History", systemImage: "books.vertical.fill")
                    }

                    Button {
                        dismiss()
                        Task { await store.exportCurrentPageAsWebArchive() }
                    } label: {
                        Label("Save Offline (.webarchive) to Vault", systemImage: "square.and.arrow.down.on.square")
                    }

                    if let url = store.activeTab.currentURL {
                        ShareLink(item: url) {
                            Label("Share Page URL", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Page Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

public struct BookmarksAndHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BookmarkRecord.createdAt, order: .reverse) private var bookmarks: [BookmarkRecord]
    @Query(sort: \HistoryRecord.visitedAt, order: .reverse) private var history: [HistoryRecord]

    @State private var selectedSection = 0
    @State private var searchText = ""

    private let onSelectURL: @MainActor (URL) -> Void

    public init(onSelectURL: @escaping @MainActor (URL) -> Void) {
        self.onSelectURL = onSelectURL
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Library", selection: $selectedSection) {
                    Text("Bookmarks").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    if selectedSection == 0 {
                        let filtered = searchText.isEmpty
                            ? bookmarks
                            : bookmarks.filter {
                                $0.title.localizedCaseInsensitiveContains(searchText) ||
                                $0.urlString.localizedCaseInsensitiveContains(searchText)
                            }
                        if filtered.isEmpty {
                            ContentUnavailableView("No Bookmarks", systemImage: "bookmark")
                        } else {
                            ForEach(filtered) { item in
                                Button {
                                    if let url = URL(string: item.urlString) {
                                        onSelectURL(url)
                                        dismiss()
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(item.urlString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .onDelete { offsets in
                                for idx in offsets {
                                    modelContext.delete(filtered[idx])
                                }
                                try? modelContext.save()
                            }
                        }
                    } else {
                        let filtered = searchText.isEmpty
                            ? history
                            : history.filter {
                                $0.title.localizedCaseInsensitiveContains(searchText) ||
                                $0.urlString.localizedCaseInsensitiveContains(searchText)
                            }
                        if filtered.isEmpty {
                            ContentUnavailableView("No Browsing History", systemImage: "clock")
                        } else {
                            ForEach(filtered) { item in
                                Button {
                                    if let url = URL(string: item.urlString) {
                                        onSelectURL(url)
                                        dismiss()
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        HStack {
                                            Text(item.host)
                                            Spacer()
                                            Text(item.visitedAt, style: .relative)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .onDelete { offsets in
                                for idx in offsets {
                                    modelContext.delete(filtered[idx])
                                }
                                try? modelContext.save()
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter bookmarks or history")
            .navigationTitle(selectedSection == 0 ? "Bookmarks" : "History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedSection == 1 && !history.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear", role: .destructive) {
                            for entry in history {
                                modelContext.delete(entry)
                            }
                            try? modelContext.save()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
