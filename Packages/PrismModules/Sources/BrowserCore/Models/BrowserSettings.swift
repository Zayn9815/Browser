import Foundation

public struct BrowserSettingsSnapshot: Codable, Sendable, Equatable {
    // Shield & Protection
    public var blockAdsEasyList: Bool = true
    public var blockTrackersEasyPrivacy: Bool = true
    public var blockPopups: Bool = true
    public var httpsOnlyEnabled: Bool = false
    public var stripTrackingParameters: Bool = true
    public var blockJavaScript: Bool = false

    // Appearance & Browsing
    public var defaultPageZoom: Double = 1.0
    public var defaultRequestDesktopSite: Bool = false
    public var autoHideToolbarOnScroll: Bool = true
    public var openExternalAppLinks: Bool = true
    public var homepageURLString: String = ""

    // Media & Player
    public var mediaInterceptionEnabled: Bool = true
    public var autoPlayVideos: Bool = true
    public var autoLockLandscapeInPlayer: Bool = true

    // Tabs & Privacy
    public var maxLiveWebViews: Int = BrowserEngineDefaults.maxLiveWebViews
    public var restoreTabsOnStartup: Bool = true
    public var autoCloseIncognitoOnBackground: Bool = false
    public var privacyCurtainEnabled: Bool = true

    public init() {}

    public var enabledAdBlockSourceLists: Set<String> {
        var lists: Set<String> = []
        if blockAdsEasyList { lists.insert("easylist") }
        if blockTrackersEasyPrivacy { lists.insert("easyprivacy") }
        return lists
    }

    public static func load(from defaults: UserDefaults = .standard) -> BrowserSettingsSnapshot {
        guard let data = defaults.data(forKey: "prismdm.v2.browserSettings"),
              let decoded = try? JSONDecoder().decode(BrowserSettingsSnapshot.self, from: data) else {
            return BrowserSettingsSnapshot()
        }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: "prismdm.v2.browserSettings")
        }
    }
}

public enum URLTrackingSanitizer: Sendable {
    private static let trackingParamNames: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_source_platform", "utm_creative_format", "utm_marketing_tactic",
        "fbclid", "gclid", "gbraid", "wbraid", "dclid", "msclkid", "yclid",
        "mc_cid", "mc_eid", "igshid", "mkt_tok", "_hsenc", "_hsmi",
        "oly_anon_id", "oly_enc_id", "vero_id", "ref_src", "ref_url"
    ]

    public static func sanitize(_ url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              !items.isEmpty else {
            return url
        }

        // Never strip query parameters on OAuth / authentication endpoints
        let host = (url.host ?? "").lowercased()
        if host.contains("accounts.google.") || host.contains("login.") || host.contains("oauth") {
            return url
        }

        let filtered = items.filter { !trackingParamNames.contains($0.name.lowercased()) }
        guard filtered.count != items.count else {
            return url
        }

        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url ?? url
    }

    public static func upgradeToHTTPSIfNeeded(_ url: URL, enabled: Bool) -> URL {
        guard enabled,
              url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased(),
              host != "localhost",
              !host.hasPrefix("127."),
              !host.hasPrefix("192.168."),
              !host.hasPrefix("10.") else {
            return url
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? url
    }
}
