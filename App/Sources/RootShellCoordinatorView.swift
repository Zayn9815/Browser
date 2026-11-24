import AdBlockEngine
import BrowserCore
import MediaInterceptor
import ParallelDownloader
import PrismPlayer
import SwiftUI
import VaultManager

public enum PrismRootTab: Hashable, Sendable {
    case browser
    case downloads
    case vault
    case settings
}

public struct RootShellCoordinatorView: View {
    @State private var selectedTab: PrismRootTab = .browser
    @State private var omniboxExpanded = false
    @State private var omniboxInput = ""
    @State private var activeSearchEngine: SearchEngineOption = BrowserEngineDefaults.defaultSearchEngine
    @State private var showStatusAccessory = true
    @State private var hapticCounter = 0

    @Namespace private var chromeNamespace

    private let sdmSummary = ParallelDownloaderEngineDiagnostics.sdmCoreVersionSummary
    private let ffmpegSummary = ParallelDownloaderEngineDiagnostics.ffmpegVersionSummary
    private let mpvSummary = PrismPlayerEngineDiagnostics.mpvAPIVersionSummary
    private let zipSummary = VaultEngineDiagnostics.archiveEngineSummary
    private let adBlockSummary = AdBlockManifestLoader.summary()
    private let bridgeSchemaVersion = MediaInterceptorBridgeInfo.loadSchemaVersion()

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Browser", systemImage: "safari.fill", value: PrismRootTab.browser) {
                browserFoundationView
            }

            Tab("Downloads", systemImage: "arrow.down.circle.fill", value: PrismRootTab.downloads) {
                moduleStatusListView(
                    title: "Parallel Downloader",
                    subtitle: "SDMCore (libcurl + URLSession) & FFmpeg HLS Muxer",
                    rows: [
                        ("HTTP Engine", sdmSummary, "bolt.horizontal.fill"),
                        ("HLS Muxer", ffmpegSummary, "film.stack.fill"),
                        ("Default Threads", "8 adaptive HTTP Range connections", "square.split.2x2.fill"),
                    ]
                )
            }

            Tab("Vault", systemImage: "lock.doc.fill", value: PrismRootTab.vault) {
                moduleStatusListView(
                    title: "Prism Vault",
                    subtitle: "SwiftData Metadata, Files App Exposure & Archive Engine",
                    rows: [
                        ("Archive Engine", zipSummary, "archivebox.fill"),
                        ("Playback Core", mpvSummary, "play.rectangle.fill"),
                        ("SwiftData Models", "Bookmark, History, VaultItem, SitePreference", "cylinder.split.1x2.fill"),
                    ]
                )
            }

            Tab("Settings", systemImage: "gearshape.fill", value: PrismRootTab.settings) {
                moduleStatusListView(
                    title: "PrismDM System",
                    subtitle: "iPhone-Only iOS 26.0+ • Swift 6 • Liquid Glass",
                    rows: [
                        ("Bundle ID", Bundle.main.bundleIdentifier ?? "com.prismdm.ios", "iphone"),
                        ("Search Engine", activeSearchEngine.displayName, "magnifyingglass"),
                        ("Live WebView Pool", "\(BrowserEngineDefaults.maxLiveWebViews) active LRU cap", "memorychip"),
                        ("AdBlock Engine", adBlockSummary, "shield.lefthalf.filled"),
                        ("Media Bridge", "Schema v\(bridgeSchemaVersion) (\(MediaInterceptorBridgeInfo.messageHandlerName))", "waveform.path"),
                    ]
                )
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .prismBottomAccessory(isVisible: showStatusAccessory) {
            compactEngineAccessoryBar
        }
        .tint(PrismBrandPalette.crimsonAccent)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: hapticCounter)
    }

    private var browserFoundationView: some View {
        ZStack(alignment: .bottom) {
            PrismBrandPalette.obsidianBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PrismDM")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                        Text("iPhone-Only iOS 26 Native Browser & Parallel Download Manager")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .padding(.top, 12)

                    VStack(spacing: 12) {
                        engineCardRow(title: "Download Core", detail: sdmSummary, icon: "arrow.down.circle.fill")
                        engineCardRow(title: "HLS Remux Core", detail: ffmpegSummary, icon: "film.fill")
                        engineCardRow(title: "Universal Player", detail: mpvSummary, icon: "play.circle.fill")
                        engineCardRow(title: "Vault Archive", detail: zipSummary, icon: "archivebox.fill")
                        engineCardRow(title: "Offline AdBlock", detail: adBlockSummary, icon: "shield.checkered")
                    }
                    .padding(16)
                    .background(
                        ConcentricRectangle(corners: .concentric(minimum: 16), isUniform: true)
                            .fill(PrismBrandPalette.obsidianElevated)
                    )
                    .containerShape(.rect(cornerRadius: 22))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 130)
            }

            floatingOmniboxChrome
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }

    private var floatingOmniboxChrome: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                if !omniboxExpanded {
                    HStack(spacing: 2) {
                        Button {
                            hapticCounter += 1
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel("Back")

                        Button {
                            hapticCounter += 1
                        } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel("Forward")
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectUnion(id: "navCluster", namespace: chromeNamespace)
                }

                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(PrismBrandPalette.crimsonAccent)

                    if omniboxExpanded {
                        TextField("Search \(activeSearchEngine.displayName) or enter URL", text: $omniboxInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.webSearch)
                            .submitLabel(.go)
                            .onSubmit {
                                hapticCounter += 1
                                withAnimation(.bouncy(duration: 0.30)) {
                                    omniboxExpanded = false
                                }
                            }
                    } else {
                        Button {
                            hapticCounter += 1
                            withAnimation(.bouncy(duration: 0.30)) {
                                omniboxExpanded = true
                            }
                        } label: {
                            Text(omniboxInput.isEmpty ? "Search \(activeSearchEngine.displayName) or URL" : omniboxInput)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("addressCapsule", in: chromeNamespace)

                if omniboxExpanded {
                    Button("Done") {
                        hapticCounter += 1
                        withAnimation(.bouncy(duration: 0.30)) {
                            omniboxExpanded = false
                        }
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("tabActionButton", in: chromeNamespace)
                } else {
                    Button {
                        hapticCounter += 1
                        activeSearchEngine = nextSearchEngine(after: activeSearchEngine)
                    } label: {
                        Text(activeSearchEngine.shortBadge)
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 36, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("tabActionButton", in: chromeNamespace)
                }
            }
        }
    }

    private var compactEngineAccessoryBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.shield.fill")
                .foregroundStyle(PrismBrandPalette.crimsonAccent)
            Text("Engines Ready • iOS 26 arm64")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                hapticCounter += 1
                selectedTab = .downloads
            } label: {
                Image(systemName: "arrow.down.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    private func engineCardRow(title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(PrismBrandPalette.crimsonAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
            }
            Spacer(minLength: 0)
        }
    }

    private func moduleStatusListView(
        title: String,
        subtitle: String,
        rows: [(String, String, String)]
    ) -> some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows, id: \.0) { row in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.0)
                                    .font(.headline)
                                Text(row.1)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: row.2)
                                .foregroundStyle(PrismBrandPalette.crimsonAccent)
                        }
                    }
                } header: {
                    Text(subtitle)
                }
            }
            .navigationTitle(title)
        }
    }

    private func nextSearchEngine(after current: SearchEngineOption) -> SearchEngineOption {
        let all = SearchEngineOption.allCases
        guard let index = all.firstIndex(of: current) else { return .duckDuckGo }
        return all[(index + 1) % all.count]
    }
}
