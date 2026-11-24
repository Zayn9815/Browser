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
                audioCenter.playFile(at: fileURL, title: title)
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
                                description: Text("Downloads triggered in the browser will appear here once ParallelDownloader UI activates in Phase 4.")
                            )
                        }
                    }
                    .navigationTitle("Downloads")
                }
            },
            browserOverlayContent: {
                EmptyView()
            }
        )
        .onOpenURL { incomingURL in
            handleIncomingURL(incomingURL)
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
