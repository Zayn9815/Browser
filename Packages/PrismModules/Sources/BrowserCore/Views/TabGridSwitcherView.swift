import PrismCore
import SwiftUI
import UIKit
import VaultManager

public struct TabGridSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var store: BrowserStore
    @State private var themeEngine = PrismThemeEngine.shared
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
        let tokens = themeEngine.tokens
        ZStack(alignment: .bottom) {
            PrismThemeBackdropView()

            VStack(spacing: 0) {
                headerBar(tokens: tokens)

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
                            .foregroundStyle(tokens.primaryText)
                            .padding(.top, 72)
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(displayedTabs) { tab in
                                    tabCard(for: tab, tokens: tokens)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 108)
                        }
                    }
                }
            }

            bottomGlassToolbar(tokens: tokens)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .preferredColorScheme(tokens.preferredColorScheme)
        .tint(tokens.accent)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: hapticCounter)
        .task {
            _ = await store.webViewPool.captureSnapshotAndState(
                for: store.activeTabID,
                isIncognito: store.activeTab.isIncognito
            )
        }
    }

    private func headerBar(tokens: PrismThemeTokens) -> some View {
        HStack {
            Text(showPrivateSection ? "Private Tabs (\(store.incognitoTabs.count))" : "Tabs (\(store.normalTabs.count))")
                .font(.headline.weight(.bold))
                .foregroundStyle(tokens.primaryText)
            Spacer()
            Text("Live: \(store.webViewPool.liveTabCount)/\(store.webViewPool.maxLiveWebViews)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(tokens.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .prismGlassPill()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func tabCard(for tab: BrowserTabState, tokens: PrismThemeTokens) -> some View {
        let isSelected = tab.id == store.activeTabID
        let thumbnail = store.webViewPool.loadSnapshotImage(for: tab.id, isIncognito: tab.isIncognito)

        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: tab.isIncognito ? "eye.slash.fill" : "globe")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tab.isIncognito ? .purple : tokens.accent)

                Text(tab.title.isEmpty ? tab.displayHost : tab.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tokens.primaryText)
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
                        .foregroundStyle(tokens.secondaryText)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close Tab")
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 6)

            Button {
                hapticCounter += 1
                store.selectTab(tab.id)
                dismiss()
            } label: {
                ZStack {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        tokens.canvasMid.opacity(0.65)
                        VStack(spacing: 6) {
                            Image(systemName: tab.urlString.isEmpty ? "pyramid.fill" : "safari")
                                .font(.title2)
                                .foregroundStyle(tokens.accent.opacity(0.85))
                            Text(tab.displayHost)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(tokens.secondaryText)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .frame(height: 184)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding([.horizontal, .bottom], 6)
            }
            .buttonStyle(.plain)
        }
        .prismGlassCard(cornerRadius: 18, prominent: isSelected)
        .shadow(color: isSelected ? tokens.accent.opacity(0.32) : .clear, radius: 10, y: 3)
    }

    private func bottomGlassToolbar(tokens: PrismThemeTokens) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    hapticCounter += 1
                    store.createTab(url: nil, isIncognito: showPrivateSection, activate: true)
                    dismiss()
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(tokens.accentText)
                        .prismGlassCircleButton(size: 46, prominent: true)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showPrivateSection ? "New Private Tab" : "New Tab")

                HStack(spacing: 4) {
                    Button {
                        hapticCounter += 1
                        withAnimation(.snappy) { showPrivateSection = false }
                    } label: {
                        Text("Tabs")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(!showPrivateSection ? tokens.accentText : tokens.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(!showPrivateSection ? tokens.accent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.borderless)

                    Button {
                        hapticCounter += 1
                        withAnimation(.snappy) { showPrivateSection = true }
                    } label: {
                        Label("Private", systemImage: "eye.slash.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(showPrivateSection ? .white : tokens.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(showPrivateSection ? Color.purple : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.borderless)
                }
                .padding(4)
                .prismGlassPill()

                Spacer()

                if showPrivateSection && !store.incognitoTabs.isEmpty && store.authService.isPrivateUnlocked {
                    Button {
                        hapticCounter += 1
                        store.closeAllIncognitoTabs()
                    } label: {
                        Text("Burn")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(tokens.destructive, in: Capsule())
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    hapticCounter += 1
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tokens.primaryText)
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .prismGlassPill(interactive: true)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
