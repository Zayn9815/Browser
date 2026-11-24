import Foundation
import SwiftData

public enum VaultMediaKind: String, Codable, Sendable, CaseIterable {
    case video
    case audio
    case archive
    case document
    case image
    case webArchive
    case binary

    public static func infer(fromFileExtension ext: String) -> VaultMediaKind {
        switch ext.lowercased() {
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "ts", "m2ts", "3gp":
            return .video
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aiff":
            return .audio
        case "zip", "cbz", "jar", "ipa", "epub":
            return .archive
        case "pdf", "txt", "md", "rtf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "json", "xml":
            return .document
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif", "svg":
            return .image
        case "webarchive":
            return .webArchive
        default:
            return .binary
        }
    }
}

@Model
public final class VaultItemRecord {
    @Attribute(.unique) public var id: UUID
    /// Relative path inside Documents/Vault (or ApplicationSupport/PrivateVault when isPrivateVault == true)
    public var relativePath: String
    public var displayName: String
    public var fileExtension: String
    public var mimeType: String?
    public var byteSize: Int64
    public var kindRawValue: String
    public var sourceURLString: String?
    public var durationSeconds: Double?
    public var lastPlaybackPositionSeconds: Double
    public var isPrivateVault: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        relativePath: String,
        displayName: String,
        fileExtension: String,
        mimeType: String? = nil,
        byteSize: Int64 = 0,
        kind: VaultMediaKind? = nil,
        sourceURLString: String? = nil,
        durationSeconds: Double? = nil,
        lastPlaybackPositionSeconds: Double = 0,
        isPrivateVault: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.relativePath = relativePath
        self.displayName = displayName
        self.fileExtension = fileExtension.lowercased()
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.kindRawValue = (kind ?? VaultMediaKind.infer(fromFileExtension: fileExtension)).rawValue
        self.sourceURLString = sourceURLString
        self.durationSeconds = durationSeconds
        self.lastPlaybackPositionSeconds = lastPlaybackPositionSeconds
        self.isPrivateVault = isPrivateVault
        self.createdAt = createdAt
    }

    public var kind: VaultMediaKind {
        VaultMediaKind(rawValue: kindRawValue) ?? .binary
    }
}
