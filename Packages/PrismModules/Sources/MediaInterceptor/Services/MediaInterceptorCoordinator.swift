import Foundation
import Observation
import ParallelDownloader
import PrismPlayer
import WebKit

public struct FullscreenPlaybackHandoff: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let source: PlayableSource
    public let startTimeSeconds: Double
    public let playbackRate: Float

    public init(
        id: UUID = UUID(),
        source: PlayableSource,
        startTimeSeconds: Double,
        playbackRate: Float
    ) {
        self.id = id
        self.source = source
        self.startTimeSeconds = startTimeSeconds
        self.playbackRate = playbackRate
    }
}

@Observable
@MainActor
public final class MediaInterceptorCoordinator: PrismScriptMessageHandling {
    public private(set) var candidatesByTab: [UUID: [InterceptedMediaItem]] = [:]
    public private(set) var drmBlockedTabs: Set<UUID> = []
    public var isEnabled: Bool = true

    public var pendingQualityPickerItem: InterceptedMediaItem?
    public var onFullscreenHandoff: ((FullscreenPlaybackHandoff) -> Void)?
    public var onRequestDownload: ((InterceptedMediaItem, HLSStreamVariant?) -> Void)?

    private var correlatorsByTab: [UUID: BlobStreamCorrelator] = [:]

    public init() {}

    public static func makeMediaSnifferUserScript() -> WKUserScript? {
        guard let url = Bundle.module.url(forResource: "MediaSniffer.user", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
    }

    public func attach(to userContentController: WKUserContentController, tabID: UUID) {
        if let script = Self.makeMediaSnifferUserScript() {
            userContentController.addUserScript(script)
        }
        let weakHandler = WeakScriptMessageHandler(tabID: tabID, delegate: self)
        userContentController.add(
            weakHandler,
            contentWorld: .page,
            name: MediaInterceptorBridgeInfo.messageHandlerName
        )
    }

    public func clearTab(_ tabID: UUID) {
        candidatesByTab.removeValue(forKey: tabID)
        drmBlockedTabs.remove(tabID)
        correlatorsByTab.removeValue(forKey: tabID)
    }

    public func activeCandidate(for tabID: UUID) -> InterceptedMediaItem? {
        guard isEnabled, !drmBlockedTabs.contains(tabID) else { return nil }
        return candidatesByTab[tabID]?.last(where: { !$0.isDRMProtected })
    }

    public func allCandidates(for tabID: UUID) -> [InterceptedMediaItem] {
        guard isEnabled, !drmBlockedTabs.contains(tabID) else { return [] }
        return (candidatesByTab[tabID] ?? []).filter { !$0.isDRMProtected }
    }

    // MARK: - PrismScriptMessageHandling

    public func handleScriptMessage(_ message: WKScriptMessage, for tabID: UUID) {
        guard isEnabled,
              message.name == MediaInterceptorBridgeInfo.messageHandlerName,
              let envelope = decodeValidatedEnvelope(from: message.body) else {
            return
        }

        let webView = message.webView
        let frameInfo = message.frameInfo
        let frameOrigin = envelope.frameOrigin ?? originString(from: frameInfo.request.url) ?? ""
        let pageReferer = envelope.pageReferer.flatMap(URL.init(string:)) ?? webView?.url ?? frameInfo.request.url
        let pageTitle = nonEmpty(envelope.pageTitle) ?? nonEmpty(webView?.title) ?? pageReferer?.host ?? "Stream"

        switch envelope.event {
        case .drmStreamDetected:
            var correlator = correlatorsByTab[tabID] ?? BlobStreamCorrelator()
            correlator.markFrameOriginDRMProtected(frameOrigin)
            correlatorsByTab[tabID] = correlator
            drmBlockedTabs.insert(tabID)
            candidatesByTab[tabID]?.removeAll { $0.frameOrigin?.lowercased() == frameOrigin.lowercased() }

        case .mediaCandidateDetected:
            if envelope.payload.isDRMProtected == true || drmBlockedTabs.contains(tabID) {
                return
            }
            guard let rawURL = envelope.payload.streamUrl,
                  let streamURL = validatedHTTPURL(rawURL) else {
                return
            }
            let hint = parseHint(envelope.payload.containerHint, url: streamURL)
            if hint == .m3u8 || hint == .mpd {
                var correlator = correlatorsByTab[tabID] ?? BlobStreamCorrelator()
                correlator.recordManifest(url: streamURL, containerHint: hint, frameOrigin: frameOrigin)
                correlatorsByTab[tabID] = correlator
            }

            Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                let session = await self.snapshotSessionContext(
                    webView: webView,
                    targetURL: streamURL,
                    pageReferer: pageReferer,
                    frameOrigin: frameOrigin,
                    mimeType: envelope.payload.mimeType,
                    suggestedTitle: pageTitle
                )
                let item = InterceptedMediaItem(
                    candidateId: envelope.payload.candidateId ?? streamURL.absoluteString,
                    streamURL: streamURL,
                    containerHint: hint,
                    mimeType: envelope.payload.mimeType,
                    title: pageTitle,
                    pageReferer: pageReferer,
                    frameOrigin: frameOrigin,
                    isDRMProtected: false,
                    videoWidth: envelope.payload.videoWidth,
                    videoHeight: envelope.payload.videoHeight,
                    durationSeconds: envelope.payload.durationSeconds,
                    sessionContext: session
                )
                self.upsertCandidate(item, for: tabID)
            }

        case .blobSourceAttached:
            var correlator = correlatorsByTab[tabID] ?? BlobStreamCorrelator()
            let hasDRM = (envelope.payload.hasMediaKeys == true) || (envelope.payload.isDRMProtected == true)
            guard let correlated = correlator.correlateBlob(
                frameOrigin: frameOrigin,
                recentNetworkManifests: envelope.payload.recentNetworkManifests ?? [],
                hasMediaKeys: hasDRM
            ) else {
                correlatorsByTab[tabID] = correlator
                if hasDRM {
                    drmBlockedTabs.insert(tabID)
                }
                return
            }
            correlatorsByTab[tabID] = correlator

            Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                let session = await self.snapshotSessionContext(
                    webView: webView,
                    targetURL: correlated.url,
                    pageReferer: pageReferer,
                    frameOrigin: frameOrigin,
                    mimeType: correlated.containerHint == .m3u8 ? "application/vnd.apple.mpegurl" : "application/dash+xml",
                    suggestedTitle: pageTitle
                )
                let item = InterceptedMediaItem(
                    candidateId: envelope.payload.videoElementId ?? correlated.url.absoluteString,
                    streamURL: correlated.url,
                    containerHint: correlated.containerHint,
                    mimeType: correlated.containerHint == .m3u8 ? "application/vnd.apple.mpegurl" : "application/dash+xml",
                    title: pageTitle,
                    pageReferer: pageReferer,
                    frameOrigin: frameOrigin,
                    isDRMProtected: false,
                    videoWidth: envelope.payload.videoWidth,
                    videoHeight: envelope.payload.videoHeight,
                    durationSeconds: envelope.payload.durationSeconds,
                    sessionContext: session
                )
                self.upsertCandidate(item, for: tabID)
            }

        case .fullscreenIntercepted:
            guard envelope.payload.isDRMProtected != true, !drmBlockedTabs.contains(tabID) else {
                return
            }
            let rawStream = envelope.payload.resolvedStreamUrl ?? activeCandidate(for: tabID)?.streamURL.absoluteString
            guard let rawStream, let streamURL = validatedHTTPURL(rawStream) else { return }

            let videoElementId = envelope.payload.videoElementId ?? ""
            let startTime = max(0, envelope.payload.currentTimeSeconds ?? 0)
            let rate = Float(envelope.payload.playbackRate ?? 1.0)
            let hint = parseHint(envelope.payload.containerHint, url: streamURL)

            // Pause underlying webpage video inside its exact frame in .page world so zero double audio plays
            if let webView {
                let escapedId = videoElementId.replacingOccurrences(of: "'", with: "")
                webView.evaluateJavaScript(
                    "if (window.__prismPauseInterceptedVideo) { window.__prismPauseInterceptedVideo('\(escapedId)'); }",
                    in: frameInfo,
                    in: .page
                ) { _ in }
            }

            Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                let session = await self.snapshotSessionContext(
                    webView: webView,
                    targetURL: streamURL,
                    pageReferer: pageReferer,
                    frameOrigin: frameOrigin,
                    mimeType: envelope.payload.mimeType,
                    suggestedTitle: pageTitle
                )
                let item = InterceptedMediaItem(
                    candidateId: videoElementId.isEmpty ? streamURL.absoluteString : videoElementId,
                    streamURL: streamURL,
                    containerHint: hint,
                    mimeType: envelope.payload.mimeType,
                    title: pageTitle,
                    pageReferer: pageReferer,
                    frameOrigin: frameOrigin,
                    isDRMProtected: false,
                    videoWidth: envelope.payload.videoWidth,
                    videoHeight: envelope.payload.videoHeight,
                    durationSeconds: envelope.payload.durationSeconds,
                    sessionContext: session
                )
                self.upsertCandidate(item, for: tabID)
                self.onFullscreenHandoff?(
                    FullscreenPlaybackHandoff(
                        source: item.asPlayableSource(),
                        startTimeSeconds: startTime,
                        playbackRate: rate > 0 ? rate : 1.0
                    )
                )
            }

        case .videoPlaybackState:
            if envelope.payload.isDRMProtected == true {
                drmBlockedTabs.insert(tabID)
            }
        }
    }

    // MARK: - Private Validation & Session Capture

    private func decodeValidatedEnvelope(from body: Any) -> MediaBridgeEnvelope? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              data.count <= MediaBridgeEnvelope.maxPayloadBytes,
              let envelope = try? JSONDecoder().decode(MediaBridgeEnvelope.self, from: data),
              envelope.schemaVersion == MediaBridgeEnvelope.currentSchemaVersion else {
            return nil
        }
        return envelope
    }

    private func snapshotSessionContext(
        webView: WKWebView?,
        targetURL: URL,
        pageReferer: URL?,
        frameOrigin: String,
        mimeType: String?,
        suggestedTitle: String
    ) async -> BrowserSessionContext {
        let isIncognito = webView.map { !$0.configuration.websiteDataStore.isPersistent } ?? false
        let userAgent = webView?.customUserAgent
        let rawCookies: [HTTPCookie]
        if let store = webView?.configuration.websiteDataStore.httpCookieStore {
            rawCookies = await store.allCookies()
        } else {
            rawCookies = []
        }
        let matching = rawCookies
            .map(BrowserCookieSnapshot.init(httpCookie:))
            .filter { $0.matches(url: targetURL) }

        let safeOrigin = frameOrigin.lowercased().hasPrefix("http") ? frameOrigin : originString(from: pageReferer)
        let ext = targetURL.pathExtension.lowercased()
        let filenameExt = ["mp4", "m3u8", "mpd", "webm", "mov", "mkv"].contains(ext) ? ext : "mp4"
        let cleanStem = suggestedTitle.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestedFilename = "\(cleanStem.isEmpty ? "Video" : cleanStem).\(filenameExt == "m3u8" ? "mp4" : filenameExt)"

        return BrowserSessionContext(
            cookies: matching,
            userAgent: userAgent,
            pageReferer: pageReferer,
            origin: safeOrigin,
            mimeType: mimeType,
            suggestedFilename: suggestedFilename,
            isIncognito: isIncognito
        )
    }

    private func upsertCandidate(_ item: InterceptedMediaItem, for tabID: UUID) {
        var list = candidatesByTab[tabID] ?? []
        list.removeAll { $0.streamURL == item.streamURL }
        list.append(item)
        if list.count > 12 {
            list.removeFirst(list.count - 12)
        }
        candidatesByTab[tabID] = list
    }

    private func validatedHTTPURL(_ raw: String) -> URL? {
        guard raw.utf8.count <= 4096,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func parseHint(_ raw: String?, url: URL) -> InterceptedContainerHint {
        if let raw, let hint = InterceptedContainerHint(rawValue: raw.lowercased()) {
            return hint
        }
        let ext = url.pathExtension.lowercased()
        if ext == "m3u8" { return .m3u8 }
        if ext == "mpd" { return .mpd }
        if ext == "webm" { return .webm }
        if ext == "mp4" { return .mp4 }
        return .unknown
    }

    private func originString(from url: URL?) -> String? {
        guard let url, let scheme = url.scheme, let host = url.host else { return nil }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
