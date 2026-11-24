import Foundation

public struct BrowserCookieSnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let isSecure: Bool
    public let isHostOnly: Bool
    public let expiresAtUnix: Double?

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        isSecure: Bool = true,
        isHostOnly: Bool = true,
        expiresAtUnix: Double? = nil
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.isSecure = isSecure
        self.isHostOnly = isHostOnly
        self.expiresAtUnix = expiresAtUnix
    }

    public init(httpCookie: HTTPCookie) {
        let rawDomain = httpCookie.domain
        let isHostOnly = !rawDomain.hasPrefix(".")
        self.init(
            name: httpCookie.name,
            value: httpCookie.value,
            domain: rawDomain,
            path: httpCookie.path.isEmpty ? "/" : httpCookie.path,
            isSecure: httpCookie.isSecure,
            isHostOnly: isHostOnly,
            expiresAtUnix: httpCookie.expiresDate?.timeIntervalSince1970
        )
    }

    public func matches(url: URL, now: Date = .now) -> Bool {
        guard let host = url.host?.lowercased(),
              expiresAtUnix.map({ $0 > now.timeIntervalSince1970 }) ?? true,
              !isSecure || url.scheme?.lowercased() == "https" else {
            return false
        }
        let normalizedDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalizedDomain.isEmpty else { return false }
        guard host == normalizedDomain || (!isHostOnly && host.hasSuffix("." + normalizedDomain)) else {
            return false
        }
        let requestPath = url.path.isEmpty ? "/" : url.path
        return requestPath == path || (requestPath.hasPrefix(path) && (path.hasSuffix("/") || requestPath.dropFirst(path.count).hasPrefix("/")))
    }
}

public struct BrowserSessionContext: Codable, Sendable, Equatable {
    public let cookies: [BrowserCookieSnapshot]
    public let userAgent: String?
    public let pageReferer: URL?
    public let origin: String?
    public let mimeType: String?
    public let suggestedFilename: String?
    public let isIncognito: Bool

    public init(
        cookies: [BrowserCookieSnapshot] = [],
        userAgent: String? = nil,
        pageReferer: URL? = nil,
        origin: String? = nil,
        mimeType: String? = nil,
        suggestedFilename: String? = nil,
        isIncognito: Bool = false
    ) {
        self.cookies = cookies
        self.userAgent = userAgent
        self.pageReferer = pageReferer
        self.origin = origin
        self.mimeType = mimeType
        self.suggestedFilename = suggestedFilename
        self.isIncognito = isIncognito
    }

    public func httpHeaderDictionary(for targetURL: URL) -> [String: String] {
        var headers: [String: String] = [:]
        if let userAgent, !userAgent.isEmpty {
            headers["User-Agent"] = userAgent
        }
        if let pageReferer, !(pageReferer.scheme?.lowercased() == "https" && targetURL.scheme?.lowercased() != "https") {
            headers["Referer"] = pageReferer.absoluteString
        }
        if let origin, !origin.isEmpty, !(origin.lowercased().hasPrefix("https://") && targetURL.scheme?.lowercased() != "https") {
            headers["Origin"] = origin
        }
        let cookieHeader = cookies
            .filter { $0.matches(url: targetURL) }
            .sorted { $0.path.count > $1.path.count }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        return headers
    }
}
