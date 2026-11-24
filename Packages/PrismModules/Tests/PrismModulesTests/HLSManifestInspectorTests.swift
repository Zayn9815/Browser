import Foundation
import Testing
@testable import MediaInterceptor

@Suite("HLSManifestInspector Master Playlist Parsing")
struct HLSManifestInspectorTests {
    @Test("Parses #EXT-X-STREAM-INF variants, resolves relative URLs, and sorts highest resolution first")
    func parsesMasterPlaylist() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=640x360,FRAME-RATE=30.000,CODECS="avc1.4d401e,mp4a.40.2"
        low/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=6200000,RESOLUTION=1920x1080,FRAME-RATE=60.000,CODECS="avc1.64002a,mp4a.40.2"
        high/1080p60.m3u8?sig=xyz
        #EXT-X-STREAM-INF:BANDWIDTH=3100000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
        https://edge.example.com/streams/720p.m3u8
        """
        let baseURL = URL(string: "https://cdn.example.com/hls/master.m3u8")!
        let variants = HLSManifestInspector.parseMasterPlaylist(playlist, baseURL: baseURL)

        #expect(variants.count == 3)
        #expect(variants[0].height == 1080)
        #expect(variants[0].width == 1920)
        #expect(variants[0].bandwidthBitsPerSec == 6_200_000)
        #expect(variants[0].frameRate == 60.0)
        #expect(variants[0].codecs == "avc1.64002a,mp4a.40.2")
        #expect(variants[0].url.absoluteString == "https://cdn.example.com/hls/high/1080p60.m3u8?sig=xyz")

        #expect(variants[1].height == 720)
        #expect(variants[1].url.absoluteString == "https://edge.example.com/streams/720p.m3u8")

        #expect(variants[2].height == 360)
        #expect(variants[2].url.absoluteString == "https://cdn.example.com/hls/low/index.m3u8")
    }
}
