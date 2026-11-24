import Foundation
import SwiftData

@Model
public final class BookmarkRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var urlString: String
    public var folderName: String?
    public var faviconData: Data?
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        folderName: String? = nil,
        faviconData: Data? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.folderName = folderName
        self.faviconData = faviconData
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
