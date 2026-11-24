import BrowserCore
import ParallelDownloader
import PrismCore
import SwiftData
import SwiftUI
import VaultManager

@main
public struct PrismDMApp: App {
    @UIApplicationDelegateAdaptor(PrismAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var browserStore = BrowserStore()
    @State private var downloadStore = ParallelDownloadStore()
    @State private var themeEngine = PrismThemeEngine.shared
    private let audioCenter = BackgroundAudioCenter.shared
    private let modelContainer: ModelContainer

    public init() {
        do {
            self.modelContainer = try VaultSchemaRegistry.makeModelContainer()
        } catch {
            fatalError("Failed to initialize PrismDM Vault ModelContainer: \(error)")
        }
    }

    public var body: some Scene {
        let tokens = themeEngine.tokens
        WindowGroup {
            ZStack {
                RootShellCoordinatorView(
                    browserStore: browserStore,
                    downloadStore: downloadStore,
                    audioCenter: audioCenter
                )
                .modelContainer(modelContainer)

                if scenePhase != .active && browserStore.settings.privacyCurtainEnabled {
                    ZStack {
                        PrismThemeBackdropView()
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(tokens.accent)
                            Text("PrismDM")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(tokens.primaryText)
                        }
                        .padding(28)
                        .prismGlassCard(cornerRadius: 24, prominent: true)
                    }
                    .transition(.opacity)
                }
            }
            .tint(tokens.accent)
            .preferredColorScheme(tokens.preferredColorScheme)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    browserStore.handleSceneBackgrounded(isBackgroundAudioActive: audioCenter.isPlaying)
                    browserStore.authService.lock()
                }
            }
        }
    }
}
