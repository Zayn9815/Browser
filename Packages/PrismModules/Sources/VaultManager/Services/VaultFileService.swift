import Foundation

public enum VaultFileError: LocalizedError, Sendable {
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case invalidFilename(String)
    case pathOutsideVault
    case coordinationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace(let required, let available):
            let formatter = ByteCountFormatter()
            return "Not enough iPhone storage (\(formatter.string(fromByteCount: available)) free, \(formatter.string(fromByteCount: required)) required)."
        case .invalidFilename(let name):
            return "Invalid file or folder name: \(name)"
        case .pathOutsideVault:
            return "Operation blocked: target path escapes the PrismDM Vault."
        case .coordinationFailed(let detail):
            return "Coordinated file operation failed: \(detail)"
        }
    }
}

public struct VaultEntryItem: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let url: URL
    public let relativePath: String
    public let isDirectory: Bool
    public let byteSize: Int64
    public let modifiedAt: Date
    public let kind: VaultMediaKind
    public let isPrivate: Bool

    public init(
        name: String,
        url: URL,
        relativePath: String,
        isDirectory: Bool,
        byteSize: Int64,
        modifiedAt: Date,
        kind: VaultMediaKind,
        isPrivate: Bool
    ) {
        self.id = "\(isPrivate ? "priv" : "pub"):\(relativePath)"
        self.name = name
        self.url = url
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.kind = kind
        self.isPrivate = isPrivate
    }
}

public actor VaultFileService: VaultManaging {
    public static let shared = VaultFileService()

    private let archiveService = VaultArchiveService()

    public init() {}

    nonisolated public func vaultRootURL(isPrivate: Bool) throws -> URL {
        let fm = FileManager.default
        if isPrivate {
            let support = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            var privateRoot = support.appendingPathComponent("PrivateVault", isDirectory: true)
            if !fm.fileExists(atPath: privateRoot.path) {
                try fm.createDirectory(at: privateRoot, withIntermediateDirectories: true)
            }
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? privateRoot.setResourceValues(resourceValues)
            return privateRoot
        } else {
            // Documents/Vault is automatically visible in iOS Files app via UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace
            let docs = try fm.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let publicRoot = docs.appendingPathComponent("Vault", isDirectory: true)
            if !fm.fileExists(atPath: publicRoot.path) {
                try fm.createDirectory(at: publicRoot, withIntermediateDirectories: true)
            }
            return publicRoot
        }
    }

    nonisolated public func availableDiskBytes() throws -> Int64 {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let values = try docs.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values.volumeAvailableCapacityForImportantUsage {
            return important
        }
        if let standard = values.volumeAvailableCapacity {
            return Int64(standard)
        }
        return 0
    }

    public func assertSufficientDiskSpace(requiredBytes: Int64, safetyMarginBytes: Int64 = 100 * 1024 * 1024) throws {
        let available = try availableDiskBytes()
        let needed = max(0, requiredBytes) + safetyMarginBytes
        if available < needed {
            throw VaultFileError.insufficientDiskSpace(requiredBytes: needed, availableBytes: available)
        }
    }

    public func sanitizeFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/:\\\0*?\"<>|")
        let cleaned = trimmed.components(separatedBy: forbidden).joined(separator: "_")
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "Download_\(Int(Date.now.timeIntervalSince1970))"
        }
        return cleaned
    }

    public func uniqueDestinationURL(in directory: URL, preferredFilename: String) -> URL {
        let fm = FileManager.default
        let safeName = sanitizeFilename(preferredFilename)
        var candidate = directory.appendingPathComponent(safeName)
        guard fm.fileExists(atPath: candidate.path) else {
            return candidate
        }
        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(nextName)
            index += 1
        }
        return candidate
    }

    public func listDirectory(relativePath: String = "", isPrivate: Bool) throws -> [VaultEntryItem] {
        let root = try vaultRootURL(isPrivate: isPrivate)
        let targetDir = try resolveSubpath(relativePath, inside: root)
        let fm = FileManager.default

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
        ]
        let urls = try fm.contentsOfDirectory(
            at: targetDir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            let byteSize = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate ?? values?.creationDate ?? .now
            let canonicalItem = url.standardizedFileURL.resolvingSymlinksInPath().path
            let rel = canonicalItem
                .replacingOccurrences(of: canonicalRoot, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let kind: VaultMediaKind = isDirectory
                ? .binary
                : VaultMediaKind.infer(fromFileExtension: url.pathExtension)
            return VaultEntryItem(
                name: url.lastPathComponent,
                url: url,
                relativePath: rel,
                isDirectory: isDirectory,
                byteSize: byteSize,
                modifiedAt: modified,
                kind: kind,
                isPrivate: isPrivate
            )
        }
    }

    public func listAllFolders(isPrivate: Bool) throws -> [VaultEntryItem] {
        let root = try vaultRootURL(isPrivate: isPrivate)
        let fm = FileManager.default
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        var folders: [VaultEntryItem] = []

        if let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                guard values?.isDirectory == true else { continue }
                let rel = url.standardizedFileURL.resolvingSymlinksInPath().path
                    .replacingOccurrences(of: canonicalRoot, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                folders.append(
                    VaultEntryItem(
                        name: url.lastPathComponent,
                        url: url,
                        relativePath: rel,
                        isDirectory: true,
                        byteSize: 0,
                        modifiedAt: values?.contentModificationDate ?? .now,
                        kind: .binary,
                        isPrivate: isPrivate
                    )
                )
            }
        }
        return folders.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
    }

    @discardableResult
    public func createFolder(named name: String, inRelativePath parentPath: String, isPrivate: Bool) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
            throw VaultFileError.invalidFilename(name)
        }
        let root = try vaultRootURL(isPrivate: isPrivate)
        let parent = try resolveSubpath(parentPath, inside: root)
        let folderURL = uniqueDestinationURL(in: parent, preferredFilename: trimmed)
        try coordinateWrite(at: folderURL) { target in
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        }
        return folderURL
    }

    @discardableResult
    public func renameItem(relativePath: String, to newName: String, isPrivate: Bool) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
            throw VaultFileError.invalidFilename(newName)
        }
        let root = try vaultRootURL(isPrivate: isPrivate)
        let sourceURL = try resolveSubpath(relativePath, inside: root)
        let destinationURL = uniqueDestinationURL(in: sourceURL.deletingLastPathComponent(), preferredFilename: trimmed)
        try coordinateMove(from: sourceURL, to: destinationURL)
        return destinationURL
    }

    @discardableResult
    public func moveItem(relativePath: String, toFolderRelativePath folderPath: String, isPrivate: Bool) throws -> URL {
        let root = try vaultRootURL(isPrivate: isPrivate)
        let sourceURL = try resolveSubpath(relativePath, inside: root)
        let destinationFolder = try resolveSubpath(folderPath, inside: root)
        let destinationURL = uniqueDestinationURL(in: destinationFolder, preferredFilename: sourceURL.lastPathComponent)
        try coordinateMove(from: sourceURL, to: destinationURL)
        return destinationURL
    }

    /// Streams/copies an externally picked file (from iOS Files or PhotosPicker FileRepresentation)
    /// into the target vault folder with disk-space preflight and Private Vault backup exclusion.
    @discardableResult
    public func importExternalFile(
        from sourceURL: URL,
        preferredFilename: String? = nil,
        intoFolderRelativePath folderPath: String = "",
        isPrivate: Bool,
        deleteSourceIfTemporary: Bool = false
    ) throws -> URL {
        let root = try vaultRootURL(isPrivate: isPrivate)
        let destinationFolder = try resolveSubpath(folderPath, inside: root)
        let fileSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        try assertSufficientDiskSpace(requiredBytes: fileSize, safetyMarginBytes: 32 * 1024 * 1024)

        let name = (preferredFilename?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? sourceURL.lastPathComponent
        var destinationURL = uniqueDestinationURL(in: destinationFolder, preferredFilename: name)

        if deleteSourceIfTemporary {
            try coordinateCopyOrMove(from: sourceURL, to: destinationURL)
        } else {
            let coordinator = NSFileCoordinator()
            var coordError: NSError?
            var copyError: Error?
            coordinator.coordinate(
                readingItemAt: sourceURL,
                options: [],
                writingItemAt: destinationURL,
                options: .forReplacing,
                error: &coordError
            ) { actualSrc, actualDst in
                do {
                    try FileManager.default.copyItem(at: actualSrc, to: actualDst)
                } catch {
                    copyError = error
                }
            }
            if let coordError { throw VaultFileError.coordinationFailed(coordError.localizedDescription) }
            if let copyError { throw copyError }
        }

        var rv = URLResourceValues()
        rv.isExcludedFromBackup = isPrivate
        try? destinationURL.setResourceValues(rv)
        return destinationURL
    }

    /// Atomically moves a file or folder between Files Vault (`Documents/Vault`) and Private Vault (`ApplicationSupport/PrivateVault`).
    @discardableResult
    public func moveAcrossVaults(
        relativePath: String,
        fromPrivate: Bool,
        toPrivate: Bool,
        destinationFolderRelativePath: String = ""
    ) throws -> URL {
        guard fromPrivate != toPrivate else {
            return try moveItem(relativePath: relativePath, toFolderRelativePath: destinationFolderRelativePath, isPrivate: fromPrivate)
        }
        let sourceRoot = try vaultRootURL(isPrivate: fromPrivate)
        let destinationRoot = try vaultRootURL(isPrivate: toPrivate)
        let sourceURL = try resolveSubpath(relativePath, inside: sourceRoot)
        let destinationFolder = try resolveSubpath(destinationFolderRelativePath, inside: destinationRoot)
        var destinationURL = uniqueDestinationURL(in: destinationFolder, preferredFilename: sourceURL.lastPathComponent)

        try coordinateMove(from: sourceURL, to: destinationURL)

        var rv = URLResourceValues()
        rv.isExcludedFromBackup = toPrivate
        try? destinationURL.setResourceValues(rv)
        return destinationURL
    }

    public func registerCompletedFile(
        at tempOrFinalURL: URL,
        preferredFilename: String,
        mimeType: String?,
        sourceURL: URL?,
        isPrivate: Bool
    ) async throws -> VaultItemRecordSnapshot {
        let root = try vaultRootURL(isPrivate: isPrivate)
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalSource = tempOrFinalURL.standardizedFileURL.resolvingSymlinksInPath()

        let finalURL: URL
        if canonicalSource.path.hasPrefix(canonicalRoot + "/") {
            finalURL = canonicalSource
        } else {
            let fileSize = (try? canonicalSource.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            try assertSufficientDiskSpace(requiredBytes: fileSize, safetyMarginBytes: 32 * 1024 * 1024)
            let dest = uniqueDestinationURL(in: root, preferredFilename: preferredFilename)
            try coordinateCopyOrMove(from: canonicalSource, to: dest)
            finalURL = dest
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        let byteSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let ext = finalURL.pathExtension.lowercased()
        let rel = finalURL.standardizedFileURL.resolvingSymlinksInPath().path
            .replacingOccurrences(of: canonicalRoot, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return VaultItemRecordSnapshot(
            id: UUID(),
            relativePath: rel,
            displayName: finalURL.lastPathComponent,
            fileExtension: ext,
            mimeType: mimeType,
            byteSize: byteSize,
            kind: VaultMediaKind.infer(fromFileExtension: ext),
            sourceURLString: sourceURL?.absoluteString,
            durationSeconds: nil,
            lastPlaybackPositionSeconds: 0,
            isPrivateVault: isPrivate,
            createdAt: .now
        )
    }

    public func deleteVaultFile(relativePath: String, isPrivate: Bool) async throws {
        let root = try vaultRootURL(isPrivate: isPrivate)
        let targetURL = try resolveSubpath(relativePath, inside: root)
        guard targetURL.standardizedFileURL.path != root.standardizedFileURL.path else {
            throw VaultFileError.pathOutsideVault
        }
        try coordinateDelete(at: targetURL)
    }

    public func extractArchive(at sourceURL: URL, destinationFolder: URL) async throws -> AsyncStream<Double> {
        try await archiveService.extractArchive(at: sourceURL, destinationFolder: destinationFolder)
    }

    public func compressItems(_ urls: [URL], archiveName: String, in directory: URL) async throws -> URL {
        try await archiveService.compressItems(urls, archiveName: archiveName, in: directory)
    }

    // MARK: - Coordinated File Helpers

    private func resolveSubpath(_ relativePath: String, inside root: URL) throws -> URL {
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidate = trimmed.isEmpty
            ? canonicalRoot
            : canonicalRoot.appendingPathComponent(trimmed).standardizedFileURL
        let rootPrefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard candidate.path == canonicalRoot.path || candidate.path.hasPrefix(rootPrefix) else {
            throw VaultFileError.pathOutsideVault
        }
        return candidate
    }

    private func coordinateWrite(at url: URL, body: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var bodyError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { actualURL in
            do {
                try body(actualURL)
            } catch {
                bodyError = error
            }
        }
        if let coordError { throw VaultFileError.coordinationFailed(coordError.localizedDescription) }
        if let bodyError { throw bodyError }
    }

    private func coordinateDelete(at url: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var bodyError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { actualURL in
            do {
                if FileManager.default.fileExists(atPath: actualURL.path) {
                    try FileManager.default.removeItem(at: actualURL)
                }
            } catch {
                bodyError = error
            }
        }
        if let coordError { throw VaultFileError.coordinationFailed(coordError.localizedDescription) }
        if let bodyError { throw bodyError }
    }

    private func coordinateMove(from source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var bodyError: Error?
        coordinator.coordinate(
            writingItemAt: source,
            options: .forMoving,
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordError
        ) { actualSrc, actualDst in
            do {
                try FileManager.default.moveItem(at: actualSrc, to: actualDst)
            } catch {
                bodyError = error
            }
        }
        if let coordError { throw VaultFileError.coordinationFailed(coordError.localizedDescription) }
        if let bodyError { throw bodyError }
    }

    private func coordinateCopyOrMove(from source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var bodyError: Error?
        coordinator.coordinate(
            readingItemAt: source,
            options: [],
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordError
        ) { actualSrc, actualDst in
            do {
                let fm = FileManager.default
                do {
                    try fm.moveItem(at: actualSrc, to: actualDst)
                } catch {
                    try fm.copyItem(at: actualSrc, to: actualDst)
                    try? fm.removeItem(at: actualSrc)
                }
            } catch {
                bodyError = error
            }
        }
        if let coordError { throw VaultFileError.coordinationFailed(coordError.localizedDescription) }
        if let bodyError { throw bodyError }
    }
}
