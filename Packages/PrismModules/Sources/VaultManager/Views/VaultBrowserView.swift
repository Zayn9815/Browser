import SwiftData
import SwiftUI

public enum VaultSortOrder: String, CaseIterable, Identifiable, Sendable {
    case dateDescending = "Newest"
    case nameAscending = "Name"
    case sizeDescending = "Size"
    case kindAscending = "Kind"

    public var id: String { rawValue }
}

public struct VaultBrowserView: View {
    private let fileService: VaultFileService
    @Bindable private var authService: BiometricAuthService
    @Bindable private var audioCenter: BackgroundAudioCenter
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

    @State private var archiveProgress: Double?
    @State private var archiveStatusMessage: String?
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
                return lhs.isDirectory
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

    public var body: some View {
        NavigationStack {
            ZStack {
                if isPrivateMode && !authService.isPrivateUnlocked {
                    VaultLockOverlayView(authService: authService) {
                        Task { await reloadDirectory() }
                    }
                } else {
                    vaultContentList
                }
            }
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
                    Button {
                        showSortSheet = true
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }

                    Button {
                        newFolderName = ""
                        showNewFolderAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }

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
            .task(id: "\(isPrivateMode)-\(currentRelativePath)-\(authService.isPrivateUnlocked)") {
                await reloadDirectory()
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
                                                .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
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
        }
    }

    private var vaultContentList: some View {
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
                    Text(archiveStatusMessage ?? "Processing archive…")
                        .font(.caption.weight(.medium))
                    ProgressView(value: progress)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
                        ContentUnavailableView(
                            isPrivateMode ? "Private Vault is Empty" : "No Files Yet",
                            systemImage: isPrivateMode ? "lock.doc" : "folder",
                            description: Text(isPrivateMode
                                ? "Private downloads and saved pages stay hidden from iOS Files and backups."
                                : "Downloads and saved .webarchive pages appear here and in the iOS Files app.")
                        )
                    } else {
                        ForEach(filteredEntries) { item in
                            vaultRow(for: item)
                        }
                    }
                } footer: {
                    if !freeStorageLabel.isEmpty {
                        Text("\(filteredEntries.count) item(s) • \(freeStorageLabel) available on iPhone")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await reloadDirectory()
            }

            if isSelecting && !selectedIDs.isEmpty {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            Task { await compressSelected() }
                        } label: {
                            Label("Zip (\(selectedIDs.count))", systemImage: "archivebox.fill")
                        }
                        .buttonStyle(.glass)

                        Button(role: .destructive) {
                            Task { await deleteSelected() }
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
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
    private func vaultRow(for item: VaultEntryItem) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIDs.contains(item.id)
                        ? Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0)
                        : .secondary)
            }

            Image(systemName: iconName(for: item))
                .font(.title3)
                .foregroundStyle(item.isDirectory
                    ? .blue
                    : Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
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
