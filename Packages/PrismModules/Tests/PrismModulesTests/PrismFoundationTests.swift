import Foundation
import Testing
@testable import AdBlockEngine
@testable import BrowserCore
@testable import MediaInterceptor
@testable import ParallelDownloader
@testable import PrismPlayer
@testable import VaultManager

@Suite("PrismDM Phase 1 Foundation Contracts")
struct PrismFoundationTests {
    @Test("Default search engine is DuckDuckGo and resolves queries vs direct URLs")
    func searchEngineResolution() {
        #expect(BrowserEngineDefaults.defaultSearchEngine == .duckDuckGo)
        #expect(BrowserEngineDefaults.maxLiveWebViews == 4)

        let direct = SearchEngineOption.duckDuckGo.resolveNavigationURL(from: "apple.com")
        #expect(direct?.absoluteString == "https://apple.com")

        let search = SearchEngineOption.duckDuckGo.resolveNavigationURL(from: "swift 6 liquid glass")
        #expect(search?.host == "duckduckgo.com")
        #expect(search?.absoluteString.contains("q=swift") == true)
    }

    @Test("PlayableSource routes MP4/HLS to AVPlayer and MKV/WebM/AVI/FLV to libmpv")
    func dualPlaybackEngineRouting() {
        let session = BrowserSessionContext()
        let mp4 = PlayableSource.remoteStream(
            id: UUID(),
            url: URL(string: "https://cdn.example.com/movie.mp4")!,
            title: "MP4",
            mimeType: "video/mp4",
            sessionContext: session,
            variants: []
        )
        let hls = PlayableSource.remoteStream(
            id: UUID(),
            url: URL(string: "https://cdn.example.com/master.m3u8")!,
            title: "HLS",
            mimeType: "application/vnd.apple.mpegurl",
            sessionContext: session,
            variants: []
        )
        let mkv = PlayableSource.vaultFile(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/sample.mkv"),
            title: "MKV",
            resumeSeconds: 0
        )
        let webm = PlayableSource.remoteStream(
            id: UUID(),
            url: URL(string: "https://cdn.example.com/video.webm")!,
            title: "WebM",
            mimeType: "video/webm",
            sessionContext: session,
            variants: []
        )

        #expect(mp4.preferredEngineType == .nativeAVPlayer)
        #expect(hls.preferredEngineType == .nativeAVPlayer)
        #expect(mkv.preferredEngineType == .mpvFFmpeg)
        #expect(webm.preferredEngineType == .mpvFFmpeg)
    }

    @Test("BrowserCookieSnapshot enforces RFC 6265 domain, path, and Secure scheme scoping")
    func cookieScoping() {
        let secureCookie = BrowserCookieSnapshot(
            name: "sid",
            value: "token123",
            domain: ".example.com",
            path: "/media",
            isSecure: true,
            isHostOnly: false,
            expiresAtUnix: Date.now.timeIntervalSince1970 + 3600
        )

        #expect(secureCookie.matches(url: URL(string: "https://cdn.example.com/media/video.mp4")!))
        #expect(!secureCookie.matches(url: URL(string: "http://cdn.example.com/media/video.mp4")!))
        #expect(!secureCookie.matches(url: URL(string: "https://other.org/media/video.mp4")!))
        #expect(!secureCookie.matches(url: URL(string: "https://cdn.example.com/public/video.mp4")!))
    }

    @Test("SwiftData in-memory Vault container initializes all 4 schemas cleanly")
    func swiftDataVaultContainer() throws {
        let container = try VaultSchemaRegistry.makeModelContainer(inMemory: true)
        #expect(!container.schema.entities.isEmpty)
        #expect(container.schema.entities.count == 4)
    }

    @Test("MediaBridgeEnvelope decodes schemaVersion 1 JS bridge payload")
    func mediaBridgeDecoding() throws {
        let json = """
        {
          "schemaVersion": 1,
          "event": "MEDIA_CANDIDATE_DETECTED",
          "frameOrigin": "https://embed.example.com",
          "pageReferer": "https://example.com/watch/1",
          "pageTitle": "Demo",
          "timestampMs": 1795481500000,
          "payload": {
            "candidateId": "cand-1",
            "streamUrl": "https://cdn.example.com/master.m3u8",
            "containerHint": "m3u8",
            "isDRMProtected": false
          }
        }
        """
        let envelope = try JSONDecoder().decode(MediaBridgeEnvelope.self, from: Data(json.utf8))
        #expect(envelope.schemaVersion == 1)
        #expect(envelope.event == .mediaCandidateDetected)
        #expect(envelope.payload.containerHint == "m3u8")
        #expect(envelope.payload.isDRMProtected == false)
    }
}
