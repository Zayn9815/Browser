import Foundation
import SwiftData

@Model
public final class SitePreferenceRecord {
    @Attribute(.unique) public var host: String
    public var adBlockEnabled: Bool
    public var darkModeEnabled: Bool
    public var preferDesktopUserAgent: Bool
    public var autoReaderMode: Bool
    public var updatedAt: Date

    public init(
        host: String,
        adBlockEnabled: Bool = true,
        darkModeEnabled: Bool = false,
        preferDesktopUserAgent: Bool = false,
        autoReaderMode: Bool = false,
        updatedAt: Date = .now
    ) {
        self.host = host.lowercased()
        self.adBlockEnabled = adBlockEnabled
        self.darkModeEnabled = darkModeEnabled
        self.preferDesktopUserAgent = preferDesktopUserAgent
        self.autoReaderMode = autoReaderMode
        self.updatedAt = updatedAt
    }
}
