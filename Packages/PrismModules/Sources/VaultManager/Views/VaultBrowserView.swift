import Photos
import PhotosUI
import PrismCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

public enum VaultSortOrder: String, CaseIterable, Identifiable, Sendable {
    case dateDescending = "Newest"
    case nameAscending = "Name"
    case sizeDescending = "Size"
    case kindAscending = "Kind"

    public var id: String { rawValue }
}

/// Streams picked photos and large 4K videos straight to disk via `FileRepresentation` (zero RAM spike).
private struct VaultTransferableMedia: Transferable {
    let tempFileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PrismVaultImport", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let originalName = received.file.lastPathComponent
            let dest = tempDir.appendingPathComponent("\(UUID().uuidString)_\(originalName)")
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VaultTransferableMedia(tempFileURL: dest)
        }
    }
}

public struct VaultBrowserView: View {
    private let fileService: VaultFileService
    @Bindable private var authService: BiometricAuthService
    @Bindable private var audioCenter: BackgroundAudioCenter
    @State private var themeEngine = PrismThemeEngine.shared
    private let onPlayMediaFile: ((URL, String) -> Void)?
    private let onDismiss: (() -> Void)?

    @State private var isPrivateMode = false
    @State private var currentRelativePath = ""
    @State private var entries: [VaultEntryItem] = []
    @State private var searchText = ""
    @State private var sortOrder: VaultSortOrder = .dateDescending
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var freeStorageLabel = ""

    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var renamingItem: VaultEntryItem?
    @State private var renameText = ""
    @State private var movingItem: VaultEntryItem?
    @State private var availableFolders: [VaultEntryItem] = []
    @State private var showSortSheet = false
    @State private var showPINSetupAlert = false
    @State private var pinSetupInput = ""

    // Import & Cross-Vault Move state
    @State private var showPhotosPicker = false
    @State private var pickedPhotoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showOppositeVaultPicker = false
    @State private var oppositeVaultEntries: [VaultEntryItem] = []
    @State private var pendingPhotoAssetIDsToDelete: [String] = []
    @State private var showDeleteOriginalsPrompt = false

    @State private var archiveProgress: Double?
    @State private var archiveStatusMessage: String?
    @State private var statusBanner: String?
    @State private var errorBanner: String?

    public init(
        fileService: VaultFileService = .shared,
        authService: BiometricAuthService = .shared,
        audioCenter: BackgroundAudioCenter = .shared,
        onPlayMediaFile: ((URL, String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.fileService = fileService
        self.authService = authService
        self.audioCenter = audioCenter
        self.onPlayMediaFile = onPlayMediaFile
        self.onDismiss = onDismiss
    }

    private var filteredEntries: [VaultEntryItem] {
        let base: [VaultEntryItem]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = entries
        } else {
            let query = searchText.lowercased()
            base = entries.filter { $0.name.lowercased().contains(query) }
        }
        return base.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            switch sortOrder {
            case .dateDescending:
                return lhs.modifiedAt > rhs.modifiedAt
            case .nameAscending:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .sizeDescending:
                return lhs.byteSize > rhs.byteSize
            case .kindAscending:
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
        }
    }

    private var breadcrumbSegments: [String] {
        currentRelativePath.split(separator: "/").map(String.init)
    }

    private var isUnlockedForCurrentMode: Bool {
        !isPrivateMode || authService.isPrivateUnlocked
    }

    private var reloadTaskKey: String {
        "\(isPrivateMode)-\(currentRelativePath)-\(authService.isPrivateUnlocked)"
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        NavigationStack {
            Group {
                if isPrivateMode && !authService.isPrivateUnlocked {
                    VaultLockOverlayView(
                        authService: authService,
                        title: "Private Vault Locked",
                        subtitle: "Authenticate with Face ID, Touch ID, or Passcode to access Private Vault."
                    )
                } else {
                    vaultContentList(tokens: tokens)
                }
            }
            .background(PrismThemeBackdropView())
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle(isPrivateMode ? "Private Vault" : "Vault")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search files & folders")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !currentRelativePath.isEmpty {
                        Button {
                            navigateUp()
                        } label: {
                            Label("Up", systemImage: "chevron.left")
                        }
                    } else if isPrivateMode && authService.isPrivateUnlocked {
                        Button {
                            authService.lock()
                        } label: {
                            Label("Lock", systemImage: "lock.fill")
                        }
                    } else if let onDismiss {
                        Button("Done") {
                            onDismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isUnlockedForCurrentMode {
                        importMenuButton
                    }

                    Button {
                        showSortSheet = true
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }

                    if isUnlockedForCurrentMode {
                        Button(isSelecting ? "Done" : "Select") {
                            withAnimation(.snappy) {
                                isSelecting.toggle()
                                if !isSelecting {
                                    selectedIDs.removeAll()
                                }
                            }
                        }
                    }
                }
            }
            .task(id: reloadTaskKey) {
                await reloadDirectory()
            }
            .photosPicker(
                isPresented: $showPhotosPicker,
                selection: $pickedPhotoItems,
                maxSelectionCount: 25,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            )
            .onChange(of: pickedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await importPickedPhotos(newItems) }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await importExternalFiles(urls) }
                case .failure(let error):
                    errorBanner = error.localizedDescription
                }
            }
            .alert("Delete Originals from iOS Photos?", isPresented: $showDeleteOriginalsPrompt) {
                Button("Delete Originals", role: .destructive) {
                    let ids = pendingPhotoAssetIDsToDelete
                    pendingPhotoAssetIDsToDelete = []
                    Task { await deleteOriginalPhotoAssets(identifiers: ids) }
                }
                Button("Keep in Photos", role: .cancel) {
                    pendingPhotoAssetIDsToDelete = []
                }
            } message: {
                Text("Your \(pendingPhotoAssetIDsToDelete.count) item(s) have been safely copied into Private Vault. Remove the original copies from iOS Photos?")
            }
            .alert("New Folder", isPresented: $showNewFolderAlert) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") {
                    Task { await createFolder() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Item", isPresented: Binding(
                get: { renamingItem != nil },
                set: { if !$0 { renamingItem = nil } }
            )) {
                TextField("New name", text: $renameText)
                Button("Rename") {
                    Task { await commitRename() }
                }
                Button("Cancel", role: .cancel) { renamingItem = nil }
            }
            .alert("Configure Vault PIN", isPresented: $showPINSetupAlert) {
                SecureField("4+ digits", text: $pinSetupInput)
                    .keyboardType(.numberPad)
                Button("Save PIN") {
                    _ = authService.configurePIN(pinSetupInput)
                    pinSetupInput = ""
                }
                if authService.hasConfiguredPIN {
                    Button("Remove PIN", role: .destructive) {
                        authService.removeConfiguredPIN()
                    }
                }
                Button("Cancel", role: .cancel) { pinSetupInput = "" }
            }
            .sheet(isPresented: $showSortSheet) {
                NavigationStack {
                    List {
                        Section("Sort Files By") {
                            ForEach(VaultSortOrder.allCases) { option in
                                Button {
                                    sortOrder = option
                                    showSortSheet = false
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        Spacer()
                                        if sortOrder == option {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(tokens.accent)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }

                        Section("Private Vault Security") {
                            Button(authService.hasConfiguredPIN ? "Change or Remove Custom PIN" : "Set Fallback Vault PIN") {
                                showSortSheet = false
                                showPINSetupAlert = true
                            }
                        }
                    }
                    .navigationTitle("Vault Options")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $movingItem) { item in
                NavigationStack {
                    List {
                        Section("Move Within \(isPrivateMode ? "Private Vault" : "Files Vault")") {
                            Button {
                                Task { await commitMove(item: item, targetFolder: "") }
                            } label: {
                                Label("Vault Root", systemImage: "internaldrive")
                            }
                            ForEach(availableFolders.filter { $0.relativePath != item.relativePath && !$0.relativePath.hasPrefix(item.relativePath + "/") }) { folder in
                                Button {
                                    Task { await commitMove(item: item, targetFolder: folder.relativePath) }
                                } label: {
                                    Label(folder.relativePath, systemImage: "folder.fill")
                                }
                            }
                        }

                        Section("Move Across Vaults") {
                            Button {
                                movingItem = nil
                                Task { await moveAcrossVaults(items: [item], toPrivate: !item.isPrivate) }
                            } label: {
                                Label(
                                    item.isPrivate ? "Move to Files Vault" : "Move to Private Vault",
                                    systemImage: item.isPrivate ? "folder.badge.person.crop" : "lock.shield.fill"
                                )
                            }
                        }
                    }
                    .navigationTitle("Move “\(item.name)”")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { movingItem = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showOppositeVaultPicker) {
                NavigationStack {
                    List {
                        if oppositeVaultEntries.isEmpty {
                            ContentUnavailableView(
                                isPrivateMode ? "Files Vault is Empty" : "Private Vault is Empty",
                                systemImage: "folder"
                            )
                        } else {
                            ForEach(oppositeVaultEntries) { item in
                                Button {
                                    showOppositeVaultPicker = false
                                    Task { await moveAcrossVaults(items: [item], toPrivate: isPrivateMode) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: iconName(for: item))
                                            .foregroundStyle(tokens.accent)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(item.isDirectory
                                                ? "Folder"
                                                : ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle(isPrivateMode ? "Move from Files Vault" : "Move from Private Vault")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showOppositeVaultPicker = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .tint(tokens.accent)
    }

    private var importMenuButton: some View {
        Menu {
            Button {
                showPhotosPicker = true
            } label: {
                Label("Import from Photos & Videos", systemImage: "photo.on.rectangle.angled")
            }

            Button {
                showFileImporter = true
            } label: {
                Label("Import from iOS Files", systemImage: "doc.badge.plus")
            }

            Button {
                Task { await openOppositeVaultPicker() }
            } label: {
                Label(
                    isPrivateMode ? "Move from Files Vault" : "Move from Private Vault",
                    systemImage: isPrivateMode ? "lock.doc.fill" : "folder.fill"
                )
            }

            Divider()

            Button {
                newFolderName = ""
                showNewFolderAlert = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
        }
        .accessibilityLabel("Import or Create")
    }

    private func vaultContentList(tokens: PrismThemeTokens) -> some View {
        VStack(spacing: 0) {
            Picker("Vault Space", selection: $isPrivateMode) {
                Text("Files Vault").tag(false)
                Text("Private Vault").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .onChange(of: isPrivateMode) { _, _ in
                currentRelativePath = ""
                selectedIDs.removeAll()
                isSelecting = false
            }

            if !breadcrumbSegments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button("Vault") { currentRelativePath = "" }
                            .font(.caption.weight(.semibold))
                        ForEach(Array(breadcrumbSegments.enumerated()), id: \.offset) { idx, part in
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button(part) {
                                currentRelativePath = breadcrumbSegments.prefix(idx + 1).joined(separator: "/")
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }

            if let progress = archiveProgress {
                VStack(alignment: .leading, spacing: 4) {
                    Text(archiveStatusMessage ?? "Processing…")
                        .font(.caption.weight(.medium))
                    ProgressView(value: progress)
                        .tint(tokens.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if let statusBanner {
                Text(statusBanner)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tokens.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            if let errorBanner {
                Text(errorBanner)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            List {
                Section {
                    if filteredEntries.isEmpty {
                        VStack(spacing: 14) {
                            ContentUnavailableView(
                                isPrivateMode ? "Private Vault is Empty" : "No Files Yet",
                                systemImage: isPrivateMode ? "lock.doc" : "folder",
                                description: Text(isPrivateMode
                                    ? "Import photos, videos, or files here to hide them from iOS Files and backups."
                                    : "Downloads, imported media, and saved .webarchive pages appear here and in the iOS Files app.")
                            )
                            HStack(spacing: 10) {
                                Button {
                                    showPhotosPicker = true
                                } label: {
                                    Label("Import Photos", systemImage: "photo.on.rectangle")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(tokens.accent)

                                Button {
                                    showFileImporter = true
                                } label: {
                                    Label("Import Files", systemImage: "doc.badge.plus")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.bottom, 8)
                        }
                    } else {
                        ForEach(filteredEntries) { item in
                            vaultRow(for: item, tokens: tokens)
                                .prismGlassListRow()
                        }
                    }
                } footer: {
                    if !freeStorageLabel.isEmpty {
                        Text("\(filteredEntries.count) item(s) • \(freeStorageLabel) available on iPhone")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .refreshable {
                await reloadDirectory()
            }

            if isSelecting && !selectedIDs.isEmpty {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            let targets = entries.filter { selectedIDs.contains($0.id) }
                            Task { await moveAcrossVaults(items: targets, toPrivate: !isPrivateMode) }
                        } label: {
                            Label(
                                isPrivateMode ? "To Files" : "To Private",
                                systemImage: isPrivateMode ? "folder.fill" : "lock.shield.fill"
                            )
                            .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.glass)

                        Button {
                            Task { await compressSelected() }
                        } label: {
                            Label("Zip (\(selectedIDs.count))", systemImage: "archivebox.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.glass)

                        Button(role: .destructive) {
                            Task { await deleteSelected() }
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder
    private func vaultRow(for item: VaultEntryItem, tokens: PrismThemeTokens) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIDs.contains(item.id) ? tokens.accent : .secondary)
            }

            Image(systemName: iconName(for: item))
                .font(.title3)
                .foregroundStyle(item.isDirectory ? .blue : tokens.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !item.isDirectory {
                        Text(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))
                    } else {
                        Text("Folder")
                    }
                    Text("•")
                    Text(item.modifiedAt, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if !isSelecting && !item.isDirectory {
                ShareLink(item: item.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                if selectedIDs.contains(item.id) {
                    selectedIDs.remove(item.id)
                } else {
                    selectedIDs.insert(item.id)
                }
            } else if item.isDirectory {
                currentRelativePath = item.relativePath
            } else {
                openItem(item)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                Task { await moveAcrossVaults(items: [item], toPrivate: !item.isPrivate) }
            } label: {
                Label(
                    item.isPrivate ? "Files Vault" : "Private Vault",
                    systemImage: item.isPrivate ? "folder.fill" : "lock.shield.fill"
                )
            }
            .tint(item.isPrivate ? .blue : .purple)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await deleteItem(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            if item.kind == .audio || item.kind == .video {
                Button {
                    audioCenter.playFile(at: item.url, title: item.name)
                } label: {
                    Label("Play Background Audio", systemImage: "headphones")
                }
            }

            if !item.isDirectory && item.url.pathExtension.lowercased() == "zip" {
                Button {
                    Task { await extractItem(item) }
                } label: {
                    Label("Extract Here", systemImage: "archivebox.fill")
                }
            }

            Button {
                Task { await moveAcrossVaults(items: [item], toPrivate: !item.isPrivate) }
            } label: {
                Label(
                    item.isPrivate ? "Move to Files Vault" : "Move to Private Vault",
                    systemImage: item.isPrivate ? "folder.fill" : "lock.shield.fill"
                )
            }

            if !item.isDirectory && (item.kind == .image || item.kind == .video) {
                Button {
                    Task { await saveToPhotoLibrary(item) }
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
            }

            Button {
                renameText = item.name
                renamingItem = item
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                Task {
                    availableFolders = (try? await fileService.listAllFolders(isPrivate: isPrivateMode)) ?? []
                    movingItem = item
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }

            if !item.isDirectory {
                ShareLink(item: item.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            Button(role: .destructive) {
                Task { await deleteItem(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Import, Cross-Vault Move & Photos Export

    private func importPickedPhotos(_ items: [PhotosPickerItem]) async {
        pickedPhotoItems = []
        errorBanner = nil
        statusBanner = nil
        archiveStatusMessage = "Importing \(items.count) media item(s)…"
        archiveProgress = 0.05

        var importedCount = 0
        var assetIDs: [String] = []
        let total = Double(max(1, items.count))

        for (index, pickerItem) in items.enumerated() {
            do {
                if let transferable = try await pickerItem.loadTransferable(type: VaultTransferableMedia.self) {
                    let rawName = transferable.tempFileURL.lastPathComponent
                    let cleanName: String
                    if let underscoreIdx = rawName.firstIndex(of: "_"), rawName.distance(from: rawName.startIndex, to: underscoreIdx) == 36 {
                        cleanName = String(rawName[rawName.index(after: underscoreIdx)...])
                    } else {
                        cleanName = rawName
                    }
                    _ = try await fileService.importExternalFile(
                        from: transferable.tempFileURL,
                        preferredFilename: cleanName,
                        intoFolderRelativePath: currentRelativePath,
                        isPrivate: isPrivateMode,
                        deleteSourceIfTemporary: true
                    )
                    importedCount += 1
                    if let assetID = pickerItem.itemIdentifier {
                        assetIDs.append(assetID)
                    }
                }
            } catch {
                errorBanner = error.localizedDescription
                PrismLogCenter.record(.error, category: .vault, "Photo import failed: \(error.localizedDescription)")
            }
            archiveProgress = Double(index + 1) / total
        }

        archiveProgress = nil
        archiveStatusMessage = nil
        await reloadDirectory()

        if importedCount > 0 {
            showTemporaryStatus("Imported \(importedCount) item(s) to \(isPrivateMode ? "Private Vault" : "Files Vault")")
            if isPrivateMode && !assetIDs.isEmpty {
                pendingPhotoAssetIDsToDelete = assetIDs
                showDeleteOriginalsPrompt = true
            }
        }
    }

    private func importExternalFiles(_ urls: [URL]) async {
        errorBanner = nil
        statusBanner = nil
        archiveStatusMessage = "Importing \(urls.count) file(s)…"
        archiveProgress = 0.05

        var importedCount = 0
        let total = Double(max(1, urls.count))

        for (index, url) in urls.enumerated() {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                _ = try await fileService.importExternalFile(
                    from: url,
                    preferredFilename: url.lastPathComponent,
                    intoFolderRelativePath: currentRelativePath,
                    isPrivate: isPrivateMode,
                    deleteSourceIfTemporary: false
                )
                importedCount += 1
            } catch {
                errorBanner = error.localizedDescription
                PrismLogCenter.record(.error, category: .vault, "File import failed: \(error.localizedDescription)")
            }
            archiveProgress = Double(index + 1) / total
        }

        archiveProgress = nil
        archiveStatusMessage = nil
        await reloadDirectory()

        if importedCount > 0 {
            showTemporaryStatus("Imported \(importedCount) file(s) to \(isPrivateMode ? "Private Vault" : "Files Vault")")
        }
    }

    private func openOppositeVaultPicker() async {
        let sourceIsPrivate = !isPrivateMode
        if sourceIsPrivate && !authService.isPrivateUnlocked {
            let ok = await authService.authenticate()
            guard ok else { return }
        }
        oppositeVaultEntries = (try? await fileService.listDirectory(relativePath: "", isPrivate: sourceIsPrivate)) ?? []
        showOppositeVaultPicker = true
    }

    private func moveAcrossVaults(items: [VaultEntryItem], toPrivate: Bool) async {
        guard !items.isEmpty else { return }
        if toPrivate && !authService.isPrivateUnlocked {
            let ok = await authService.authenticate()
            guard ok else { return }
        }
        errorBanner = nil
        var movedCount = 0
        for item in items {
            do {
                _ = try await fileService.moveAcrossVaults(
                    relativePath: item.relativePath,
                    fromPrivate: item.isPrivate,
                    toPrivate: toPrivate,
                    destinationFolderRelativePath: toPrivate == isPrivateMode ? currentRelativePath : ""
                )
                movedCount += 1
            } catch {
                errorBanner = error.localizedDescription
                PrismLogCenter.record(.error, category: .vault, "Cross-vault move failed: \(error.localizedDescription)")
            }
        }
        selectedIDs.removeAll()
        isSelecting = false
        await reloadDirectory()
        if movedCount > 0 {
            showTemporaryStatus("Moved \(movedCount) item(s) to \(toPrivate ? "Private Vault" : "Files Vault")")
        }
    }

    private func deleteOriginalPhotoAssets(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            errorBanner = "Photos permission required to delete original items."
            return
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count > 0 else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            showTemporaryStatus("Removed original item(s) from iOS Photos")
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func saveToPhotoLibrary(_ item: VaultEntryItem) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            errorBanner = "Allow Photos access in iOS Settings to save media."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if item.kind == .video {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: item.url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: item.url)
                }
            }
            showTemporaryStatus("Saved \(item.name) to iOS Photos")
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func showTemporaryStatus(_ message: String) {
        statusBanner = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.0))
            if statusBanner == message {
                statusBanner = nil
            }
        }
    }

    // MARK: - Existing Helpers

    private func iconName(for item: VaultEntryItem) -> String {
        if item.isDirectory { return "folder.fill" }
        switch item.kind {
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .archive: return "doc.zipper"
        case .document: return "doc.text.fill"
        case .image: return "photo.fill"
        case .webArchive: return "globe"
        case .binary: return "doc.fill"
        }
    }

    private func openItem(_ item: VaultEntryItem) {
        switch item.kind {
        case .video:
            if let onPlayMediaFile {
                onPlayMediaFile(item.url, item.name)
            } else {
                audioCenter.playFile(at: item.url, title: item.name)
            }
        case .audio:
            audioCenter.playFile(at: item.url, title: item.name)
        case .archive where item.url.pathExtension.lowercased() == "zip":
            Task { await extractItem(item) }
        default:
            if let onPlayMediaFile {
                onPlayMediaFile(item.url, item.name)
            }
        }
    }

    private func navigateUp() {
        var parts = breadcrumbSegments
        guard !parts.isEmpty else { return }
        parts.removeLast()
        currentRelativePath = parts.joined(separator: "/")
    }

    private func reloadDirectory() async {
        if isPrivateMode && !authService.isPrivateUnlocked {
            entries = []
            return
        }
        errorBanner = nil
        do {
            entries = try await fileService.listDirectory(relativePath: currentRelativePath, isPrivate: isPrivateMode)
            let freeBytes = try fileService.availableDiskBytes()
            freeStorageLabel = ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func createFolder() async {
        do {
            _ = try await fileService.createFolder(
                named: newFolderName,
                inRelativePath: currentRelativePath,
                isPrivate: isPrivateMode
            )
            await reloadDirectory()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func commitRename() async {
        guard let item = renamingItem else { return }
        renamingItem = nil
        do {
            _ = try await fileService.renameItem(
                relativePath: item.relativePath,
                to: renameText,
                isPrivate: isPrivateMode
            )
            await reloadDirectory()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func commitMove(item: VaultEntryItem, targetFolder: String) async {
        movingItem = nil
        do {
            _ = try await fileService.moveItem(
                relativePath: item.relativePath,
                toFolderRelativePath: targetFolder,
                isPrivate: isPrivateMode
            )
            await reloadDirectory()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func deleteItem(_ item: VaultEntryItem) async {
        do {
            try await fileService.deleteVaultFile(relativePath: item.relativePath, isPrivate: isPrivateMode)
            await reloadDirectory()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func deleteSelected() async {
        let targets = entries.filter { selectedIDs.contains($0.id) }
        for item in targets {
            try? await fileService.deleteVaultFile(relativePath: item.relativePath, isPrivate: isPrivateMode)
        }
        selectedIDs.removeAll()
        isSelecting = false
        await reloadDirectory()
    }

    private func compressSelected() async {
        let targets = entries.filter { selectedIDs.contains($0.id) }.map(\.url)
        guard !targets.isEmpty else { return }
        archiveStatusMessage = "Compressing \(targets.count) item(s)…"
        archiveProgress = 0.25
        do {
            let root = try fileService.vaultRootURL(isPrivate: isPrivateMode)
            let currentDir = currentRelativePath.isEmpty
                ? root
                : root.appendingPathComponent(currentRelativePath, isDirectory: true)
            _ = try await fileService.compressItems(targets, archiveName: "PrismArchive", in: currentDir)
            archiveProgress = 1.0
            selectedIDs.removeAll()
            isSelecting = false
            await reloadDirectory()
        } catch {
            errorBanner = error.localizedDescription
        }
        archiveProgress = nil
        archiveStatusMessage = nil
    }

    private func extractItem(_ item: VaultEntryItem) async {
        archiveStatusMessage = "Extracting \(item.name)…"
        archiveProgress = 0.0
        do {
            let destFolder = item.url.deletingLastPathComponent()
                .appendingPathComponent(item.url.deletingPathExtension().lastPathComponent, isDirectory: true)
            let stream = try await fileService.extractArchive(at: item.url, destinationFolder: destFolder)
            for await fraction in stream {
                archiveProgress = fraction
            }
            await reloadDirectory()
        } catch {
            errorBanner = error.localizedDescription
        }
        archiveProgress = nil
        archiveStatusMessage = nil
    }
}
