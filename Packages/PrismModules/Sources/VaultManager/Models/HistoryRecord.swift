import Foundation
import SwiftData

@Model
public final class HistoryRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var urlString: String
    public var host: String
    public var visitedAt: Date
    public var visitCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        host: String,
        visitedAt: Date = .now,
        visitCount: Int = 1
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.host = host
        self.visitedAt = visitedAt
        self.visitCount = visitCount
    }
}
