import Foundation
import Testing
@testable import BrowserCore
@testable import ParallelDownloader
@testable import PrismCore

@Suite("PrismDM Flagship Upgrade Verification")
struct FlagshipUpgradeTests {
    @Test("SpeedETASmoother formats seconds, minutes, hours, and handles unknown totals")
    func speedETASmootherFormatting() {
        #expect(SpeedETASmoother.formatETA(38) == "~38s left")
        #expect(SpeedETASmoother.formatETA(134) == "~2m 14s left")
        #expect(SpeedETASmoother.formatETA(3900) == "~1h 05m left")

        var smoother = SpeedETASmoother(alpha: 0.28)
        let id = UUID()

        let unknown = smoother.update(
            taskID: id,
            instantaneousBytesPerSecond: 1_000_000,
            downloadedBytes: 500_000,
            totalBytes: nil,
            isActive: true
        )
        #expect(unknown.formattedETA == "Calculating...")

        let active = smoother.update(
            taskID: id,
            instantaneousBytesPerSecond: 2_000_000,
            downloadedBytes: 2_000_000,
            totalBytes: 22_000_000,
            isActive: true
        )
        #expect(active.smoothedBytesPerSecond > 1_000_000)
        #expect(active.etaSeconds != nil)
        #expect(active.formattedETA.hasSuffix("left"))

        let done = smoother.update(
            taskID: id,
            instantaneousBytesPerSecond: 2_000_000,
            downloadedBytes: 22_000_000,
            totalBytes: 22_000_000,
            isActive: true
        )
        #expect(done.formattedETA == "Finalizing...")
    }

    @Test("HLSPlaylistParser resolves master highest-bandwidth variant and media segments with EXT-X-MAP")
    func hlsPlaylistParsing() {
        let masterURL = URL(string: "https://cdn.example.com/hls/master.m3u8")!
        let masterText = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
        360p/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080
        1080p/index.m3u8
        """
        let best = HLSPlaylistParser.parseMasterBestVariant(from: masterText, baseURL: masterURL)
        #expect(best?.bandwidthBps == 4_500_000)
        #expect(best?.url.absoluteString == "https://cdn.example.com/hls/1080p/index.m3u8")

        let mediaBase = URL(string: "https://cdn.example.com/hls/1080p/index.m3u8")!
        let mediaText = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:6.000,
        seg001.m4s
        #EXTINF:6.000,
        seg002.m4s
        #EXT-X-ENDLIST
        """
        let parsed = HLSPlaylistParser.parseMediaPlaylist(from: mediaText, baseURL: mediaBase, bandwidthHintBps: 4_500_000)
        #expect(parsed.initMapURL?.absoluteString == "https://cdn.example.com/hls/1080p/init.mp4")
        #expect(parsed.segments.count == 2)
        #expect(parsed.segments[0].url.absoluteString == "https://cdn.example.com/hls/1080p/seg001.m4s")
        #expect(parsed.totalDurationSeconds == 12.0)
        #expect(!parsed.hasUnsupportedDRM)
    }

    @Test("PrismLogCenter redacts cookies, bearer tokens, PINs, PrivateVault paths, and private URLs")
    func logCenterPrivacyRedaction() {
        let raw = "Cookie: session=abc123\nAuthorization: Bearer secretTokenXYZ\nPIN: 4829\nPrivateVault/secret_movie.mp4"
        let redacted = PrismLogCenter.redact(raw, isPrivateContext: false)
        #expect(!redacted.contains("abc123"))
        #expect(!redacted.contains("secretTokenXYZ"))
        #expect(!redacted.contains("4829"))
        #expect(!redacted.contains("secret_movie.mp4"))
        #expect(redacted.contains("<redacted>"))

        let privateRaw = "Navigated to https://private.example.com/secret?token=99"
        let privateRedacted = PrismLogCenter.redact(privateRaw, isPrivateContext: true)
        #expect(!privateRedacted.contains("private.example.com"))
        #expect(privateRedacted.contains("<redacted-private-url>"))
    }

    @Test("PrismCore provides all 7 themes and 7 alternate PrismDM app icons")
    func themeAndIconCatalogIntegrity() {
        #expect(PrismThemeID.allCases.count == 7)
        #expect(PrismAlternateAppIcon.allCases.count == 7)
        #expect(PrismThemeID.crimsonLiquidGlass.displayName == "Crimson Liquid Glass")
        #expect(PrismThemeID.frostLight.tokens.preferredColorScheme == .light)
        #expect(PrismThemeID.crimsonLiquidGlass.tokens.preferredColorScheme == .dark)
        #expect(PrismAlternateAppIcon.crimsonDefault.alternateIconName == nil)
        #expect(PrismAlternateAppIcon.glacier.alternateIconName == "AppIcon-Glacier")
    }

    @Test("StartPageShortcut ships 8 defaults with valid URLs and monograms")
    func startPageShortcutDefaults() {
        let defaults = StartPageShortcut.defaultShortcuts
        #expect(defaults.count == 8)
        for item in defaults {
            #expect(item.url != nil)
            #expect(!item.monogram.isEmpty)
            #expect(!item.host.isEmpty)
        }
    }

    @Test("Liquid Glass surface tokens and Alpine Glacier wallpaper preset are configured")
    func liquidGlassTokensAndAlpineWallpaper() {
        let crimson = PrismThemeID.crimsonLiquidGlass.tokens
        #expect(crimson.glassAlpha > 0.4 && crimson.glassAlpha < 0.7)
        #expect(crimson.sheenAlpha > 0.0)
        #expect(!crimson.isClassicStock)

        let classic = PrismThemeID.classicStock.tokens
        #expect(classic.isClassicStock)

        #expect(PrismWallpaperOption.allCases.contains(.alpineGlacier))
        #expect(PrismWallpaperOption.alpineGlacier.displayName == "Alpine Glacier")
    }

    @Test("YTDLPURLMatcher routes social/video pages to yt-dlp and direct files to libcurl")
    func ytdlpURLRouting() {
        #expect(YTDLPURLMatcher.shouldPreferYTDLP(for: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!))
        #expect(YTDLPURLMatcher.shouldPreferYTDLP(for: URL(string: "https://youtu.be/dQw4w9WgXcQ")!))
        #expect(YTDLPURLMatcher.shouldPreferYTDLP(for: URL(string: "https://www.tiktok.com/@user/video/123456")!))
        #expect(YTDLPURLMatcher.shouldPreferYTDLP(for: URL(string: "https://x.com/user/status/123456")!))
        #expect(!YTDLPURLMatcher.shouldPreferYTDLP(for: URL(string: "https://cdn.example.com/archive.zip")!))
        #expect(!YTDLPURLMatcher.shouldPreferYTDLP(for: URL(string: "https://cdn.example.com/movie.mp4")!))
        #expect(!YTDLPURLMatcher.shouldPreferYTDLP(for: URL(string: "https://cdn.example.com/stream.m3u8")!))
    }

    @Test("YTDLPExtractorService parses adaptive video + M4A audio formats and deduplicates tiers")
    func ytdlpJSONParsing() throws {
        let json = """
        {
          "title": "Sample 4K Clip",
          "uploader": "PrismChannel",
          "duration": 120,
          "extractor_key": "Youtube",
          "formats": [
            {"format_id": "140", "url": "https://cdn.example.com/a.m4a", "ext": "m4a", "vcodec": "none", "acodec": "mp4a.40.2", "abr": 128, "filesize": 2000000},
            {"format_id": "137", "url": "https://cdn.example.com/1080.mp4", "ext": "mp4", "vcodec": "avc1.640028", "acodec": "none", "height": 1080, "fps": 60, "filesize": 50000000},
            {"format_id": "22", "url": "https://cdn.example.com/720.mp4", "ext": "mp4", "vcodec": "avc1.64001F", "acodec": "mp4a.40.2", "height": 720, "filesize": 22000000}
          ]
        }
        """
        let info = try YTDLPExtractorService.parseMediaInfo(
            fromJSONData: Data(json.utf8),
            sourceURL: URL(string: "https://www.youtube.com/watch?v=test")!
        )
        #expect(info.title == "Sample 4K Clip")
        #expect(info.formats.count == 3)
        let hd1080 = info.formats.first(where: { $0.resolutionHeight == 1080 })
        #expect(hd1080?.requiresDualMux == true)
        #expect(hd1080?.estimatedBytes == 52_000_000)
        #expect(info.formats.contains(where: { $0.isAudioOnly }))
    }

    @Test("YTDLPDownloadWorker parses live stdout progress lines accurately")
    func ytdlpProgressLineParsing() {
        let parsed = YTDLPDownloadWorker.parseProgressLine("[download]  42.5% of   50.00MiB at    4.00MiB/s ETA 00:07")
        #expect(parsed != nil)
        #expect(abs((parsed?.fraction ?? 0) - 0.425) < 0.001)
        #expect(parsed?.totalBytes == 52_428_800)
        #expect(parsed?.speedBytesPerSecond == 4_194_304)
    }
}
