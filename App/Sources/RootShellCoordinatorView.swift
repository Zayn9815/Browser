import AdBlockEngine
import BrowserCore
import MediaInterceptor
import ParallelDownloader
import PrismPlayer
import SwiftUI
import VaultManager

public struct RootShellCoordinatorView: View {
    @Bindable private var browserStore: BrowserStore
    @Bindable private var downloadStore: ParallelDownloadStore
    @Bindable private var audioCenter: BackgroundAudioCenter
    @State private var selectedTab: PrismShellTab = .browser

    @State private var activePlayerHandoff: FullscreenPlaybackHandoff?
    @State private var qualityPickerItem: InterceptedMediaItem?

    public init(
        browserStore: BrowserStore,
        downloadStore: ParallelDownloadStore,
        audioCenter: BackgroundAudioCenter = .shared
    ) {
        self.browserStore = browserStore
        self.downloadStore = downloadStore
        self.audioCenter = audioCenter
    }

    public var body: some View {
        BrowserShellView(
            store: browserStore,
            downloadStore: downloadStore,
            audioCenter: audioCenter,
            selectedTab: $selectedTab,
            onPlayVaultMedia: { fileURL, title in
                presentLocalMediaInPlayer(fileURL: fileURL, title: title)
            },
            downloadsTabContent: {
                DownloadsTabView(store: downloadStore) { fileURL, title in
                    presentLocalMediaInPlayer(fileURL: fileURL, title: title)
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
            browserStore.downloadCoordinator = downloadStore
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

    private func presentLocalMediaInPlayer(fileURL: URL, title: String) {
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

        Task { @MainActor in
            do {
                if item.containerHint.requiresHLSMuxer {
                    _ = try await downloadStore.enqueueHLSStreamMux(
                        manifestURL: targetURL,
                        variantTitle: variantTitle,
                        sessionContext: item.sessionContext
                    )
                } else {
                    _ = try await downloadStore.enqueueHTTPDownload(
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
        if url.isFileURL {
            handleIncomingDocumentURL(url)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            selectedTab = .browser
            browserStore.createTab(url: url, isIncognito: false, activate: true)
            return
        }

        if scheme == "prismdm",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let rawTarget = components.queryItems?.first(where: { $0.name == "url" })?.value,
           let parsed = URL(string: rawTarget) {
            let action = (url.host ?? "").lowercased()
            if action == "download" {
                selectedTab = .downloads
                Task { @MainActor in
                    let lower = parsed.absoluteString.lowercased()
                    if lower.contains(".m3u8") || lower.contains(".mpd") {
                        _ = try? await downloadStore.enqueueHLSStreamMux(
                            manifestURL: parsed,
                            variantTitle: nil,
                            sessionContext: nil
                        )
                    } else {
                        _ = try? await downloadStore.enqueueHTTPDownload(
                            url: parsed,
                            sessionContext: nil,
                            preferredEngine: nil,
                            connectionLimit: nil,
                            bandwidthLimitBytesPerSec: nil
                        )
                    }
                }
            } else {
                selectedTab = .browser
                browserStore.createTab(url: parsed, isIncognito: false, activate: true)
            }
        }
    }

    private func handleIncomingDocumentURL(_ fileURL: URL) {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        let kind = VaultMediaKind.infer(fromFileExtension: fileURL.pathExtension)

        Task { @MainActor in
            defer {
                if accessed { fileURL.stopAccessingSecurityScopedResource() }
            }
            if let imported = try? await VaultFileService.shared.registerCompletedFile(
                at: fileURL,
                preferredFilename: fileURL.lastPathComponent,
                mimeType: nil,
                sourceURL: nil,
                isPrivate: false
            ), let root = try? VaultFileService.shared.vaultRootURL(isPrivate: false) {
                let finalURL = root.appendingPathComponent(imported.relativePath)
                if kind == .video || kind == .audio {
                    presentLocalMediaInPlayer(fileURL: finalURL, title: imported.displayName)
                } else {
                    selectedTab = .vault
                    browserStore.showToast("Imported \(imported.displayName) to Vault")
                }
            }
        }
    }
}
