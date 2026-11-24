import Foundation
import Testing
@testable import MediaInterceptor

@Suite("BlobStreamCorrelator Verification")
struct BlobStreamCorrelatorTests {
    @Test("Correlates same-origin MSE blob element to recent manifest within 15s window")
    func sameOriginCorrelation() {
        var correlator = BlobStreamCorrelator(slidingWindowSeconds: 15.0)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manifestURL = URL(string: "https://cdn.example.com/live/master.m3u8?token=abc")!

        correlator.recordManifest(
            url: manifestURL,
            containerHint: .m3u8,
            frameOrigin: "https://embed.example.com",
            at: now
        )

        let matched = correlator.correlateBlob(
            frameOrigin: "https://embed.example.com",
            recentNetworkManifests: [],
            hasMediaKeys: false,
            now: now.addingTimeInterval(10.0)
        )
        #expect(matched?.url == manifestURL)
        #expect(matched?.containerHint == .m3u8)

        // Different frameOrigin must not leak manifests across iframes
        let crossOrigin = correlator.correlateBlob(
            frameOrigin: "https://other-embed.net",
            recentNetworkManifests: [],
            hasMediaKeys: false,
            now: now.addingTimeInterval(10.0)
        )
        #expect(crossOrigin == nil)
    }

    @Test("Manifests older than 15-second sliding window expire cleanly")
    func slidingWindowExpiry() {
        var correlator = BlobStreamCorrelator(slidingWindowSeconds: 15.0)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manifestURL = URL(string: "https://cdn.example.com/vod/index.m3u8")!

        correlator.recordManifest(
            url: manifestURL,
            containerHint: .m3u8,
            frameOrigin: "https://player.example.com",
            at: now
        )

        let expired = correlator.correlateBlob(
            frameOrigin: "https://player.example.com",
            recentNetworkManifests: [],
            hasMediaKeys: false,
            now: now.addingTimeInterval(16.5)
        )
        #expect(expired == nil)
    }

    @Test("DRM/EME-protected frames are suppressed and never correlated")
    func drmPassthroughSuppression() {
        var correlator = BlobStreamCorrelator(slidingWindowSeconds: 15.0)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manifestURL = URL(string: "https://drm.example.com/fairplay/master.m3u8")!

        correlator.recordManifest(
            url: manifestURL,
            containerHint: .m3u8,
            frameOrigin: "https://drm.example.com",
            at: now
        )

        let drmResult = correlator.correlateBlob(
            frameOrigin: "https://drm.example.com",
            recentNetworkManifests: [manifestURL.absoluteString],
            hasMediaKeys: true,
            now: now.addingTimeInterval(1.0)
        )
        #expect(drmResult == nil)
        #expect(correlator.isOriginDRMProtected("https://drm.example.com"))
    }
}
