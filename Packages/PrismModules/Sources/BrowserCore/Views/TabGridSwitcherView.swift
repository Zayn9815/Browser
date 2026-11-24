import SwiftUI
import UIKit
import VaultManager

public struct TabGridSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var store: BrowserStore
    @State private var showPrivateSection = false
    @State private var hapticCounter = 0

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    public init(store: BrowserStore) {
        self.store = store
        self._showPrivateSection = State(initialValue: store.activeTab.isIncognito)
    }

    private var displayedTabs: [BrowserTabState] {
        showPrivateSection ? store.incognitoTabs : store.normalTabs
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            PrismBrandPalette.obsidianBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                if showPrivateSection && !store.authService.isPrivateUnlocked {
                    VaultLockOverlayView(
                        authService: store.authService,
                        title: "Private Incognito Locked",
                        subtitle: "Use Face ID, Touch ID, or your Vault PIN to view Private Tabs."
                    )
                } else {
                    ScrollView {
                        if displayedTabs.isEmpty {
                            ContentUnavailableView(
                                showPrivateSection ? "No Private Tabs" : "No Open Tabs",
                                systemImage: showPrivateSection ? "eye.slash.fill" : "square.on.square",
                                description: Text(showPrivateSection
                                    ? "Tap + below to start an ephemeral Private session with non-persistent storage."
                                    : "Tap + below to open a new browser tab.")
                            )
                            .padding(.top, 72)
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(displayedTabs) { tab in
                                    tabCard(for: tab)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 100)
                        }
                    }
                }
            }

            bottomGlassToolbar
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: hapticCounter)
        .task {
            _ = await store.webViewPool.captureSnapshotAndState(
                for: store.activeTabID,
                isIncognito: store.activeTab.isIncognito
            )
        }
    }

    private var headerBar: some View {
        HStack {
            Text(showPrivateSection ? "Private Tabs (\(store.incognitoTabs.count))" : "Tabs (\(store.normalTabs.count))")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Text("LRU Live: \(store.webViewPool.liveTabCount)/\(store.webViewPool.maxLiveWebViews)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func tabCard(for tab: BrowserTabState) -> some View {
        let isSelected = tab.id == store.activeTabID
        let thumbnail = store.webViewPool.loadSnapshotImage(for: tab.id, isIncognito: tab.isIncognito)

        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: tab.isIncognito ? "eye.slash.fill" : "globe")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tab.isIncognito ? .purple : PrismBrandPalette.crimsonAccent)

                Text(tab.title.isEmpty ? tab.displayHost : tab.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Button {
                    hapticCounter += 1
                    withAnimation(.snappy) {
                        store.closeTab(tab.id)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close \(tab.title)")
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.06))

            ZStack {
                PrismBrandPalette.obsidianElevated
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: tab.isIncognito ? "eye.slash" : "safari")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.4))
                        Text(tab.displayHost)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(height: 175)
            .clipped()
            .clipShape(ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true))
            .padding(6)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticCounter += 1
                store.selectTab(tab.id)
                dismiss()
            }
        }
        .background(PrismBrandPalette.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isSelected ? PrismBrandPalette.crimsonAccent : Color.white.opacity(0.14),
                    lineWidth: isSelected ? 2.2 : 1
                )
        )
        .containerShape(.rect(cornerRadius: 20))
    }

    private var bottomGlassToolbar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    hapticCounter += 1
                    withAnimation(.snappy) {
                        showPrivateSection.toggle()
                    }
                } label: {
                    Label(
                        showPrivateSection ? "Private" : "Normal",
                        systemImage: showPrivateSection ? "eye.slash.fill" : "square.on.square"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)

                Spacer()

                if showPrivateSection && store.authService.isPrivateUnlocked && !store.incognitoTabs.isEmpty {
                    Button(role: .destructive) {
                        hapticCounter += 1
                        store.closeAllIncognitoTabs()
                    } label: {
                        Image(systemName: "trash.fill")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Close All Private Tabs")
                }

                Button {
                    hapticCounter += 1
                    if showPrivateSection && !store.authService.isPrivateUnlocked {
                        Task {
                            if await store.authService.authenticate() {
                                store.createTab(url: nil, isIncognito: true, activate: true)
                                dismiss()
                            }
                        }
                    } else {
                        store.createTab(url: nil, isIncognito: showPrivateSection, activate: true)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.glassProminent)
                .tint(PrismBrandPalette.crimsonAccent)
                .accessibilityLabel("New Tab")

                Button("Done") {
                    hapticCounter += 1
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
            }
        }
    }
}
