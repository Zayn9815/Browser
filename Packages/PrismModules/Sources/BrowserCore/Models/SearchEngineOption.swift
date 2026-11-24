import Foundation

public enum SearchEngineOption: String, CaseIterable, Codable, Sendable, Identifiable {
    case duckDuckGo
    case google
    case brave
    case bing
    case wikipedia

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .google: return "Google"
        case .brave: return "Brave"
        case .bing: return "Bing"
        case .wikipedia: return "Wikipedia"
        }
    }

    public var shortBadge: String {
        switch self {
        case .duckDuckGo: return "DDG"
        case .google: return "G"
        case .brave: return "Brave"
        case .bing: return "Bing"
        case .wikipedia: return "Wiki"
        }
    }

    public func searchURL(for rawQuery: String) -> URL? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components: URLComponents
        switch self {
        case .duckDuckGo:
            components = URLComponents(string: "https://duckduckgo.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        case .google:
            components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        case .brave:
            components = URLComponents(string: "https://search.brave.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        case .bing:
            components = URLComponents(string: "https://www.bing.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        case .wikipedia:
            components = URLComponents(string: "https://en.wikipedia.org/w/index.php")!
            components.queryItems = [URLQueryItem(name: "search", value: trimmed)]
        }
        return components.url
    }

    /// Resolves either a direct URL (with optional implicit https:// scheme) or a search query.
    public func resolveNavigationURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let explicit = URL(string: trimmed),
           let scheme = explicit.scheme?.lowercased(),
           ["http", "https", "about", "file"].contains(scheme),
           (scheme == "about" || scheme == "file" || explicit.host != nil) {
            return explicit
        }

        let containsWhitespace = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        if !containsWhitespace && trimmed.contains(".") {
            if let prefixed = URL(string: "https://\(trimmed)"), prefixed.host != nil {
                return prefixed
            }
        }

        return searchURL(for: trimmed)
    }
}
