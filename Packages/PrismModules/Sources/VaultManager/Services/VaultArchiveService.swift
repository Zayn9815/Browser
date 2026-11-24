import Foundation
import ZIPFoundation

public enum VaultArchiveError: LocalizedError, Sendable {
    case invalidArchive(String)
    case unsafeArchiveEntry(String)
    case emptySelection
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let detail):
            return "Invalid archive: \(detail)"
        case .unsafeArchiveEntry(let path):
            return "Blocked unsafe archive path traversal entry: \(path)"
        case .emptySelection:
            return "Select at least one file or folder to compress."
        case .cancelled:
            return "Archive operation was cancelled."
        }
    }
}

public actor VaultArchiveService {
    public init() {}

    /// Extracts a ZIP archive into `destinationFolder` with strict canonical path-traversal validation
    /// and yields progress values in `0.0...1.0`.
    public func extractArchive(
        at sourceURL: URL,
        destinationFolder: URL
    ) throws -> AsyncStream<Double> {
        let fm = FileManager.default
        try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let archive: Archive
        do {
            archive = try Archive(url: sourceURL, accessMode: .read)
        } catch {
            throw VaultArchiveError.invalidArchive(error.localizedDescription)
        }

        // Pre-validate every entry against zip-slip path traversal and escaping symlinks
        let canonicalDestination = destinationFolder.standardizedFileURL.resolvingSymlinksInPath()
        let destPrefix = canonicalDestination.path.hasSuffix("/")
            ? canonicalDestination.path
            : canonicalDestination.path + "/"

        var entries: [Entry] = []
        for entry in archive {
            let entryPath = entry.path
            if entryPath.hasPrefix("/") || entryPath.contains("\0") {
                throw VaultArchiveError.unsafeArchiveEntry(entryPath)
            }
            if entry.type == .symlink {
                throw VaultArchiveError.unsafeArchiveEntry(entryPath)
            }
            let candidate = canonicalDestination.appendingPathComponent(entryPath).standardizedFileURL
            guard candidate.path == canonicalDestination.path || candidate.path.hasPrefix(destPrefix) else {
                throw VaultArchiveError.unsafeArchiveEntry(entryPath)
            }
            entries.append(entry)
        }

        let totalBytes = max(1, entries.reduce(UInt64(0)) { $0 &+ $1.uncompressedSize })
        let totalCount = max(1, entries.count)

        return AsyncStream { continuation in
            let work = Task.detached(priority: .userInitiated) {
                var extractedBytes: UInt64 = 0
                var extractedCount = 0
                let localFM = FileManager.default

                do {
                    let reader = try Archive(url: sourceURL, accessMode: .read)
                    for entry in reader {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        if entry.type == .symlink { continue }

                        let targetURL = canonicalDestination
                            .appendingPathComponent(entry.path)
                            .standardizedFileURL
                        guard targetURL.path == canonicalDestination.path || targetURL.path.hasPrefix(destPrefix) else {
                            continue
                        }

                        if entry.type == .directory {
                            try localFM.createDirectory(at: targetURL, withIntermediateDirectories: true)
                        } else {
                            try localFM.createDirectory(
                                at: targetURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true
                            )
                            if localFM.fileExists(atPath: targetURL.path) {
                                try localFM.removeItem(at: targetURL)
                            }
                            _ = try reader.extract(entry, to: targetURL)
                        }

                        extractedBytes &+= entry.uncompressedSize
                        extractedCount += 1
                        let byteProgress = Double(extractedBytes) / Double(totalBytes)
                        let countProgress = Double(extractedCount) / Double(totalCount)
                        continuation.yield(min(1.0, max(byteProgress, countProgress)))
                    }
                    continuation.yield(1.0)
                } catch {
                    // Caller checks destination or catches pre-validation errors synchronously
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                work.cancel()
            }
        }
    }

    /// Compresses one or more files/folders into a `.zip` archive inside `directory`.
    public func compressItems(
        _ urls: [URL],
        archiveName: String,
        in directory: URL
    ) async throws -> URL {
        guard !urls.isEmpty else {
            throw VaultArchiveError.emptySelection
        }

        let cleanBase = archiveName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let finalName = cleanBase.lowercased().hasSuffix(".zip")
            ? cleanBase
            : "\(cleanBase.isEmpty ? "Archive" : cleanBase).zip"

        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        var destinationURL = directory.appendingPathComponent(finalName)
        var counter = 2
        let stem = destinationURL.deletingPathExtension().lastPathComponent
        while fm.fileExists(atPath: destinationURL.path) {
            destinationURL = directory.appendingPathComponent("\(stem) (\(counter)).zip")
            counter += 1
        }

        let targetArchiveURL = destinationURL
        let sourceURLs = urls

        return try await Task.detached(priority: .userInitiated) {
            let localFM = FileManager.default
            let archive = try Archive(url: targetArchiveURL, accessMode: .create)

            for itemURL in sourceURLs {
                try Task.checkCancellation()
                var isDir: ObjCBool = false
                guard localFM.fileExists(atPath: itemURL.path, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    let baseName = itemURL.lastPathComponent
                    try archive.addEntry(
                        with: baseName + "/",
                        type: .directory,
                        uncompressedSize: Int64(0),
                        compressionMethod: .none,
                        provider: { _, _ in Data() }
                    )
                    if let enumerator = localFM.enumerator(
                        at: itemURL,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        let allObjects = enumerator.allObjects.compactMap { $0 as? URL }
                        let basePrefix = itemURL.standardizedFileURL.path + "/"
                        for child in allObjects {
                            try Task.checkCancellation()
                            let rel = child.standardizedFileURL.path.replacingOccurrences(of: basePrefix, with: "")
                            guard !rel.isEmpty else { continue }
                            let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                            if childIsDir {
                                try archive.addEntry(
                                    with: "\(baseName)/\(rel)/",
                                    type: .directory,
                                    uncompressedSize: Int64(0),
                                    compressionMethod: .none,
                                    provider: { _, _ in Data() }
                                )
                            } else {
                                try archive.addEntry(
                                    with: "\(baseName)/\(rel)",
                                    fileURL: child,
                                    compressionMethod: .deflate
                                )
                            }
                        }
                    }
                } else {
                    try archive.addEntry(
                        with: itemURL.lastPathComponent,
                        fileURL: itemURL,
                        compressionMethod: .deflate
                    )
                }
            }
            return targetArchiveURL
        }.value
    }
}
