import Foundation
import SwiftData
import ZIPFoundation

public struct VaultItemRecordSnapshot: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let relativePath: String
    public let displayName: String
    public let fileExtension: String
    public let mimeType: String?
    public let byteSize: Int64
    public let kind: VaultMediaKind
    public let sourceURLString: String?
    public let durationSeconds: Double?
    public let lastPlaybackPositionSeconds: Double
    public let isPrivateVault: Bool
    public let createdAt: Date

    public init(
        id: UUID,
        relativePath: String,
        displayName: String,
        fileExtension: String,
        mimeType: String?,
        byteSize: Int64,
        kind: VaultMediaKind,
        sourceURLString: String?,
        durationSeconds: Double?,
        lastPlaybackPositionSeconds: Double,
        isPrivateVault: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.relativePath = relativePath
        self.displayName = displayName
        self.fileExtension = fileExtension
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.kind = kind
        self.sourceURLString = sourceURLString
        self.durationSeconds = durationSeconds
        self.lastPlaybackPositionSeconds = lastPlaybackPositionSeconds
        self.isPrivateVault = isPrivateVault
        self.createdAt = createdAt
    }
}

public protocol VaultManaging: Sendable {
    func vaultRootURL(isPrivate: Bool) throws -> URL
    func availableDiskBytes() throws -> Int64
    func registerCompletedFile(
        at tempOrFinalURL: URL,
        preferredFilename: String,
        mimeType: String?,
        sourceURL: URL?,
        isPrivate: Bool
    ) async throws -> VaultItemRecordSnapshot
    func deleteVaultFile(relativePath: String, isPrivate: Bool) async throws
    func extractArchive(at sourceURL: URL, destinationFolder: URL) async throws -> AsyncStream<Double>
    func compressItems(_ urls: [URL], archiveName: String, in directory: URL) async throws -> URL
}

public enum VaultSchemaRegistry: Sendable {
    public static func makeSchema() -> Schema {
        Schema([
            BookmarkRecord.self,
            HistoryRecord.self,
            VaultItemRecord.self,
            SitePreferenceRecord.self,
        ])
    }

    public static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(
            "PrismDMVault",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

public enum VaultEngineDiagnostics: Sendable {
    /// Exercises real ZIPFoundation linkage so Release builds keep ZIP support verified.
    public static var archiveEngineSummary: String {
        let method = CompressionMethod.deflate
        return "ZIPFoundation (compression=\(method.rawValue))"
    }
}
