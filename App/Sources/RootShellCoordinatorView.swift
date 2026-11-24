import AdBlockEngine
import BrowserCore
import MediaInterceptor
import ParallelDownloader
import PrismPlayer
import SwiftUI
import VaultManager

public struct RootShellCoordinatorView: View {
    @Bindable private var browserStore: BrowserStore
    @Bindable private var audioCenter: BackgroundAudioCenter
    @State private var selectedTab: PrismShellTab = .browser

    @State private var activePlayerHandoff: FullscreenPlaybackHandoff?
    @State private var qualityPickerItem: InterceptedMediaItem?

    private let sdmSummary = ParallelDownloaderEngineDiagnostics.sdmCoreVersionSummary
    private let ffmpegSummary = ParallelDownloaderEngineDiagnostics.ffmpegVersionSummary

    public init(
        browserStore: BrowserStore,
        audioCenter: BackgroundAudioCenter = .shared
    ) {
        self.browserStore = browserStore
        self.audioCenter = audioCenter
    }

    public var body: some View {
        BrowserShellView(
            store: browserStore,
            audioCenter: audioCenter,
            selectedTab: $selectedTab,
            activeDownloadCount: 0,
            aggregateSpeedBytesPerSec: 0,
            onPlayVaultMedia: { fileURL, title in
                let source = PlayableSource.vaultFile(
                    id: UUID(),
                    fileURL: fileURL,
                    title: title,
                    resumeSeconds: 0
                )
                activePlayerHandoff = FullscreenPlaybackHandoff(
                    source: source,
                    startTimeSeconds: 0,
                    playbackRate: 1.0
                )
            },
            downloadsTabContent: {
                NavigationStack {
                    List {
                        Section("Parallel Transfer Engines Ready") {
                            Label(sdmSummary, systemImage: "bolt.horizontal.fill")
                            Label(ffmpegSummary, systemImage: "film.stack.fill")
                        }
                        Section {
                            ContentUnavailableView(
                                "No Active Downloads",
                                systemImage: "arrow.down.circle",
                                description: Text("Downloads triggered in the browser or PrismPlayer will appear here once ParallelDownloader UI activates in Phase 4.")
                            )
                        }
                    }
                    .navigationTitle("Downloads")
                }
            },
            browserOverlayContent: {
                if let detected = browserStore.mediaInterceptor.activeCandidate(for: browserStore.activeTabID) {
                    FloatingMediaPillView(
                        item: detected,
                        onPlay: {
                            activePlayerHandoff = FullscreenPlaybackHandoff(
                                source: detected.asPlayableSource(),
                                startTimeSeconds: 0,
                                playbackRate: 1.0
                            )
                        },
                        onDownload: {
                            if detected.containerHint == .m3u8 {
                                qualityPickerItem = detected
                            } else {
                                triggerMediaDownload(item: detected, selectedVariant: nil)
                            }
                        }
                    )
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        )
        .onAppear {
            browserStore.mediaInterceptor.onFullscreenHandoff = { handoff in
                activePlayerHandoff = handoff
            }
        }
        .fullScreenCover(item: $activePlayerHandoff) { handoff in
            PrismPlayerView(
                source: handoff.source,
                initialStartSeconds: handoff.startTimeSeconds,
                initialPlaybackRate: handoff.playbackRate,
                autoLockLandscape: true,
                onDismiss: {
                    activePlayerHandoff = nil
                },
                onRequestDownload: { source in
                    handleInPlayerDownloadTap(source)
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $qualityPickerItem) { item in
            StreamQualityPickerSheet(
                item: item,
                onSelectDownload: { selectedItem, variant in
                    triggerMediaDownload(item: selectedItem, selectedVariant: variant)
                },
                onSelectPlay: { selectedItem, variant in
                    let finalURL = variant?.url ?? selectedItem.streamURL
                    let playSource = PlayableSource.remoteStream(
                        id: UUID(),
                        url: finalURL,
                        title: selectedItem.title,
                        mimeType: selectedItem.mimeType,
                        sessionContext: selectedItem.sessionContext,
                        variants: selectedItem.variants
                    )
                    activePlayerHandoff = FullscreenPlaybackHandoff(
                        source: playSource,
                        startTimeSeconds: 0,
                        playbackRate: 1.0
                    )
                }
            )
        }
        .onOpenURL { incomingURL in
            handleIncomingURL(incomingURL)
        }
    }

    private func handleInPlayerDownloadTap(_ source: PlayableSource) {
        guard case .remoteStream(_, let url, let title, let mimeType, let session, let variants) = source else {
            return
        }
        let hint: InterceptedContainerHint = {
            let ext = url.pathExtension.lowercased()
            if ext == "m3u8" || (mimeType?.lowercased().contains("mpegurl") == true) { return .m3u8 }
            if ext == "mpd" || (mimeType?.lowercased().contains("dash+xml") == true) { return .mpd }
            if ext == "webm" { return .webm }
            return .mp4
        }()
        let item = InterceptedMediaItem(
            candidateId: url.absoluteString,
            streamURL: url,
            containerHint: hint,
            mimeType: mimeType,
            title: title,
            pageReferer: session.pageReferer,
            frameOrigin: session.origin,
            isDRMProtected: false,
            sessionContext: session,
            variants: variants
        )

        if hint == .m3u8 {
            activePlayerHandoff = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                qualityPickerItem = item
            }
        } else {
            triggerMediaDownload(item: item, selectedVariant: nil)
        }
    }

    private func triggerMediaDownload(item: InterceptedMediaItem, selectedVariant: HLSStreamVariant?) {
        let targetURL = selectedVariant?.url ?? item.streamURL
        let variantTitle = selectedVariant.map { "\(item.title) (\($0.displayLabel))" } ?? item.title

        guard let coordinator = browserStore.downloadCoordinator else {
            browserStore.showToast("Queued \(variantTitle) for ParallelDownloader")
            return
        }

        Task { @MainActor in
            do {
                if item.containerHint.requiresHLSMuxer {
                    _ = try await coordinator.enqueueHLSStreamMux(
                        manifestURL: targetURL,
                        variantTitle: variantTitle,
                        sessionContext: item.sessionContext
                    )
                } else {
                    _ = try await coordinator.enqueueHTTPDownload(
                        url: targetURL,
                        sessionContext: item.sessionContext,
                        preferredEngine: nil,
                        connectionLimit: nil,
                        bandwidthLimitBytesPerSec: nil
                    )
                }
                browserStore.showToast("Downloading \(variantTitle)…")
            } catch {
                browserStore.showToast("Download error: \(error.localizedDescription)")
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            selectedTab = .browser
            browserStore.createTab(url: url, isIncognito: false, activate: true)
        } else if scheme == "prismdm" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let target = components.queryItems?.first(where: { $0.name == "url" })?.value,
               let parsed = URL(string: target) {
                selectedTab = .browser
                browserStore.createTab(url: parsed, isIncognito: false, activate: true)
            }
        }
    }
}
