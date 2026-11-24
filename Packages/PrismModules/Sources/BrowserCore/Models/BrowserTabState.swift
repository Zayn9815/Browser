import Foundation

public struct BrowserTabState: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public var title: String
    public var urlString: String
    public var isIncognito: Bool
    public var isPinned: Bool
    public var isLoading: Bool
    public var estimatedProgress: Double
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var hasOnlySecureContent: Bool
    public var blockedTrackerCount: Int
    public var preferDesktopUserAgent: Bool
    public var darkModeOverride: Bool?
    public var lastAccessedAt: Date
    public var snapshotFilename: String?
    public var interactionStateFilename: String?

    public init(
        id: UUID = UUID(),
        title: String = "New Tab",
        urlString: String = "",
        isIncognito: Bool = false,
        isPinned: Bool = false,
        isLoading: Bool = false,
        estimatedProgress: Double = 0,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        hasOnlySecureContent: Bool = true,
        blockedTrackerCount: Int = 0,
        preferDesktopUserAgent: Bool = false,
        darkModeOverride: Bool? = nil,
        lastAccessedAt: Date = .now,
        snapshotFilename: String? = nil,
        interactionStateFilename: String? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.isIncognito = isIncognito
        self.isPinned = isPinned
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.hasOnlySecureContent = hasOnlySecureContent
        self.blockedTrackerCount = blockedTrackerCount
        self.preferDesktopUserAgent = preferDesktopUserAgent
        self.darkModeOverride = darkModeOverride
        self.lastAccessedAt = lastAccessedAt
        self.snapshotFilename = snapshotFilename
        self.interactionStateFilename = interactionStateFilename
    }

    public var currentURL: URL? {
        URL(string: urlString)
    }

    public var displayHost: String {
        guard let host = currentURL?.host, !host.isEmpty else {
            return isIncognito ? "Private Tab" : "Search or enter URL"
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

public enum BrowserEngineDefaults: Sendable {
    public static let maxLiveWebViews = 4
    public static let defaultSearchEngine: SearchEngineOption = .duckDuckGo
    public static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
    public static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
}
