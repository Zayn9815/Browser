import Foundation
import SDMCore
import Testing
@testable import ParallelDownloader

@Suite("BrowserSessionHeaderAdapter RFC 6265 & Header Formatting")
struct BrowserSessionHeaderAdapterTests {
    @Test("Filters cookies strictly by domain, path, Secure scheme, and expiration before SDMCore validation")
    func filtersCookiesForSDMCore() {
        let adapter = BrowserSessionHeaderAdapter()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let targetURL = URL(string: "https://cdn.example.com/media/stream.mp4")!

        let session = BrowserSessionContext(
            cookies: [
                // Valid matching subdomain + path cookie
                BrowserCookieSnapshot(
                    name: "session_id",
                    value: "abc123",
                    domain: ".example.com",
                    path: "/media",
                    isSecure: true,
                    isHostOnly: false,
                    expiresAtUnix: now.timeIntervalSince1970 + 3600
                ),
                // Must be excluded: unrelated domain
                BrowserCookieSnapshot(
                    name: "other",
                    value: "nope",
                    domain: "unrelated.org",
                    path: "/",
                    isSecure: true,
                    isHostOnly: true,
                    expiresAtUnix: now.timeIntervalSince1970 + 3600
                ),
                // Must be excluded: mismatched path
                BrowserCookieSnapshot(
                    name: "admin",
                    value: "secret",
                    domain: "cdn.example.com",
                    path: "/admin",
                    isSecure: true,
                    isHostOnly: true,
                    expiresAtUnix: now.timeIntervalSince1970 + 3600
                ),
                // Must be excluded: expired cookie
                BrowserCookieSnapshot(
                    name: "stale",
                    value: "old",
                    domain: "cdn.example.com",
                    path: "/",
                    isSecure: true,
                    isHostOnly: true,
                    expiresAtUnix: now.timeIntervalSince1970 - 60
                ),
                // Must be excluded: invalid control character in value
                BrowserCookieSnapshot(
                    name: "inject",
                    value: "bad\r\nheader",
                    domain: "cdn.example.com",
                    path: "/",
                    isSecure: true,
                    isHostOnly: true,
                    expiresAtUnix: nil
                ),
            ],
            userAgent: "PrismDM/1.0 Safari/604.1",
            pageReferer: URL(string: "https://watch.example.com/videos/42?ref=home")!,
            origin: "https://watch.example.com",
            mimeType: "video/mp4",
            suggestedFilename: "stream.mp4",
            isIncognito: false
        )

        let sdmContext = adapter.makeSDMRequestContext(from: session, for: targetURL, now: now)
        #expect(sdmContext != nil)
        #expect(sdmContext?.cookies.count == 1)
        #expect(sdmContext?.cookies.first?.name == "session_id")
        #expect(sdmContext?.referrerPolicy == .fullURL)
        #expect(sdmContext?.referrer?.absoluteString == "https://watch.example.com/videos/42?ref=home")
        #expect(sdmContext?.origin == "https://watch.example.com")
        #expect(sdmContext?.userAgent == "PrismDM/1.0 Safari/604.1")
    }

    @Test("Enforces HTTPS-to-HTTP downgrade protection on Secure cookies, Referer, and Origin")
    func enforcesDowngradeProtection() {
        let adapter = BrowserSessionHeaderAdapter()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let insecureURL = URL(string: "http://cdn.example.com/file.bin")!

        let session = BrowserSessionContext(
            cookies: [
                BrowserCookieSnapshot(
                    name: "sec",
                    value: "token",
                    domain: "cdn.example.com",
                    path: "/",
                    isSecure: true,
                    isHostOnly: true,
                    expiresAtUnix: now.timeIntervalSince1970 + 3600
                ),
            ],
            userAgent: "PrismDM/1.0",
            pageReferer: URL(string: "https://secure.example.com/private")!,
            origin: "https://secure.example.com"
        )

        let sdmContext = adapter.makeSDMRequestContext(from: session, for: insecureURL, now: now)
        #expect(sdmContext?.cookies.isEmpty == true)
        #expect(sdmContext?.referrer == nil)
        #expect(sdmContext?.origin == nil)
        #expect(sdmContext?.userAgent == "PrismDM/1.0")
    }

    @Test("Serializes CRLF-delimited FFmpeg AVDictionary headers accurately")
    func formatsFFmpegCRLFHeaders() {
        let adapter = BrowserSessionHeaderAdapter()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hlsURL = URL(string: "https://cdn.example.com/hls/master.m3u8")!

        let session = BrowserSessionContext(
            cookies: [
                BrowserCookieSnapshot(
                    name: "auth",
                    value: "xyz789",
                    domain: ".example.com",
                    path: "/",
                    isSecure: true,
                    isHostOnly: false,
                    expiresAtUnix: now.timeIntervalSince1970 + 3600
                ),
            ],
            userAgent: "PrismDM-iOS/1.0",
            pageReferer: URL(string: "https://example.com/watch/99#frag")!,
            origin: "https://example.com"
        )

        let headers = adapter.makeFFmpegCRLFHeaders(from: session, for: hlsURL, now: now)
        #expect(headers.hasSuffix("\r\n"))
        #expect(headers.contains("User-Agent: PrismDM-iOS/1.0\r\n"))
        #expect(headers.contains("Referer: https://example.com/watch/99\r\n"))
        #expect(!headers.contains("#frag"))
        #expect(headers.contains("Origin: https://example.com\r\n"))
        #expect(headers.contains("Cookie: auth=xyz789\r\n"))
    }
}
