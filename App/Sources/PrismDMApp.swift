import BrowserCore
import SwiftData
import SwiftUI
import VaultManager

@main
public struct PrismDMApp: App {
    @UIApplicationDelegateAdaptor(PrismAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var browserStore = BrowserStore()
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
        WindowGroup {
            ZStack {
                RootShellCoordinatorView(
                    browserStore: browserStore,
                    audioCenter: audioCenter
                )
                .modelContainer(modelContainer)

                if scenePhase != .active {
                    ZStack {
                        PrismBrandPalette.obsidianBackground
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(PrismBrandPalette.crimsonAccent)
                            Text("PrismDM")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .padding(28)
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    }
                    .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    browserStore.handleSceneBackgrounded(isBackgroundAudioActive: audioCenter.isPlaying)
                    browserStore.authService.lock()
                }
            }
        }
    }
}
