import PrismCore
import SwiftUI
import UIKit

public struct FloatingOmniboxBar: View {
    @Bindable private var store: BrowserStore
    @State private var themeEngine = PrismThemeEngine.shared
    @FocusState private var isAddressFieldFocused: Bool
    @Namespace private var omniboxNamespace

    @State private var hapticCounter = 0
    @State private var tabSwipeHapticCounter = 0
    @State private var horizontalSwipeOffset: CGFloat = 0
    @State private var showTabQuickActions = false

    private let isTopMode: Bool
    private let activeDownloadCount: Int

    public init(store: BrowserStore, isTopMode: Bool = false, activeDownloadCount: Int = 0) {
        self.store = store
        self.isTopMode = isTopMode
        self.activeDownloadCount = activeDownloadCount
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        VStack(spacing: 8) {
            if !isTopMode && store.isOmniboxExpanded {
                searchEngineRibbon(tokens: tokens)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Safari iOS 26 3-piece detached Liquid Glass bar (strictly NO SwiftUI Menu inside GlassEffectContainer)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 9) {
                    if !store.isOmniboxExpanded {
                        backCircleButton(tokens: tokens)
                    }

                    addressCapsule(tokens: tokens)

                    if store.isOmniboxExpanded {
                        Button("Cancel") {
                            hapticCounter += 1
                            isAddressFieldFocused = false
                            withAnimation(.bouncy(duration: 0.30)) {
                                store.isOmniboxExpanded = false
                                store.omniboxText = store.activeTab.urlString
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tokens.primaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .prismGlassPill(interactive: true)
                        .buttonStyle(.borderless)
                        .glassEffectID("rightChromeButton", in: omniboxNamespace)
                    } else {
                        tabsCircleButton(tokens: tokens)
                    }
                }
            }

            if isTopMode && store.isOmniboxExpanded {
                searchEngineRibbon(tokens: tokens)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, isTopMode ? 6 : 0)
        .padding(.bottom, isTopMode ? 0 : 12)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: hapticCounter)
        .sensoryFeedback(.selection, trigger: tabSwipeHapticCounter)
        .confirmationDialog("Tab Actions", isPresented: $showTabQuickActions, titleVisibility: .hidden) {
            Button("New Tab") {
                hapticCounter += 1
                store.createTab(url: nil, isIncognito: false, activate: true)
            }
            Button("New Private Tab") {
                hapticCounter += 1
                store.createTab(url: nil, isIncognito: true, activate: true)
            }
            Button("Close Current Tab", role: .destructive) {
                hapticCounter += 1
                store.closeTab(store.activeTabID)
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: store.isOmniboxExpanded) { _, expanded in
            isAddressFieldFocused = expanded
            if expanded {
                horizontalSwipeOffset = 0
            }
        }
    }

    // MARK: - 1. Left Detached Circular Back Button (<)

    private func backCircleButton(tokens: PrismThemeTokens) -> some View {
        Button {
            hapticCounter += 1
            store.goBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(tokens.primaryText)
                .opacity(store.activeTab.canGoBack ? 1.0 : 0.36)
                .prismGlassCircleButton(size: 46)
        }
        .buttonStyle(.borderless)
        .disabled(!store.activeTab.canGoBack && !store.activeTab.canGoForward)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.42).onEnded { _ in
                if store.activeTab.canGoBack || store.activeTab.canGoForward {
                    hapticCounter += 1
                    store.isTabHistoryPresented = true
                }
            }
        )
        .glassEffectID("leftBackButton", in: omniboxNamespace)
        .accessibilityLabel("Back")
        .accessibilityHint("Long press for tab history")
    }

    // MARK: - 2. Center Detached Liquid Glass Omnibox Capsule (≡ | Domain | ↻)

    private func addressCapsule(tokens: PrismThemeTokens) -> some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 2) {
                if store.isOmniboxExpanded {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tokens.accent)
                        .padding(.leading, 14)
                        .padding(.trailing, 6)

                    TextField(
                        "Search \(store.selectedSearchEngine.displayName) or enter URL",
                        text: $store.omniboxText
                    )
                    .focused($isAddressFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .foregroundStyle(tokens.primaryText)
                    .onSubmit {
                        hapticCounter += 1
                        isAddressFieldFocused = false
                        store.navigate(toInput: store.omniboxText)
                    }

                    if !store.omniboxText.isEmpty {
                        Button {
                            hapticCounter += 1
                            store.omniboxText = ""
                            isAddressFieldFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(tokens.secondaryText)
                                .frame(width: 36, height: 46)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear Address")
                    }

                    Button {
                        hapticCounter += 1
                        isAddressFieldFocused = false
                        store.isQRScannerPresented = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(tokens.primaryText)
                            .frame(width: 40, height: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .padding(.trailing, 4)
                    .accessibilityLabel("Scan QR Code URL")
                } else {
                    // Leading Safari-style Three Horizontal Lines (≡) Menu Icon
                    Button {
                        hapticCounter += 1
                        store.isBrowserMenuPresented = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tokens.primaryText)
                                .frame(width: 40, height: 46)
                                .contentShape(Rectangle())

                            if activeDownloadCount > 0 {
                                Circle()
                                    .fill(tokens.accent)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: tokens.accent.opacity(0.8), radius: 3)
                                    .offset(x: -7, y: 11)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 4)
                    .accessibilityLabel("Browser Menu")

                    // Centered Domain / Start Page Search Prompt
                    Button {
                        hapticCounter += 1
                        store.omniboxText = store.activeTab.urlString
                        withAnimation(.bouncy(duration: 0.30)) {
                            store.isOmniboxExpanded = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if store.activeTab.isIncognito {
                                Image(systemName: "eye.slash.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.purple)
                            } else if !store.activeTab.urlString.isEmpty && !store.activeTab.hasOnlySecureContent {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.orange)
                            }

                            Text(store.activeTab.urlString.isEmpty ? "Search or enter website" : store.activeTab.displayHost)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(store.activeTab.urlString.isEmpty ? tokens.secondaryText : tokens.primaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)

                    // Trailing Reload / Stop Button
                    Button {
                        hapticCounter += 1
                        store.reloadOrStop()
                    } label: {
                        Image(systemName: store.activeTab.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tokens.primaryText)
                            .opacity(store.activeTab.urlString.isEmpty ? 0.42 : 0.95)
                            .frame(width: 40, height: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.activeTab.urlString.isEmpty && !store.activeTab.isLoading)
                    .padding(.trailing, 4)
                    .accessibilityLabel(store.activeTab.isLoading ? "Stop Loading" : "Reload")
                }
            }

            // Ultra-subtle loading progress hairline along bottom edge of capsule
            if !store.isOmniboxExpanded && store.activeTab.isLoading {
                GeometryReader { geo in
                    Capsule()
                        .fill(tokens.accent)
                        .frame(width: max(18, geo.size.width * CGFloat(max(0.08, store.activeTab.estimatedProgress))), height: 2.2)
                        .shadow(color: tokens.accent.opacity(0.75), radius: 3)
                }
                .frame(height: 2.2)
                .padding(.horizontal, 18)
                .padding(.bottom, 1.5)
                .allowsHitTesting(false)
            }
        }
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .prismGlassPill()
        .glassEffectID("addressCapsule", in: omniboxNamespace)
        .offset(x: horizontalSwipeOffset)
        .simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .local)
                .onChanged { value in
                    guard !store.isOmniboxExpanded else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.35 else { return }
                    horizontalSwipeOffset = max(-52, min(52, dx * 0.55))
                }
                .onEnded { value in
                    guard !store.isOmniboxExpanded else {
                        horizontalSwipeOffset = 0
                        return
                    }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > abs(dy) * 1.35 && abs(dx) >= 48 {
                        let delta = dx < 0 ? 1 : -1
                        if store.selectAdjacentTab(delta: delta) {
                            tabSwipeHapticCounter += 1
                        }
                    }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        horizontalSwipeOffset = 0
                    }
                }
        )
    }

    // MARK: - 3. Right Detached Circular Tabs Button (square.on.square)

    private func tabsCircleButton(tokens: PrismThemeTokens) -> some View {
        Button {
            hapticCounter += 1
            store.isTabGridPresented = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "square.on.square")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tokens.primaryText)
                    .prismGlassCircleButton(size: 46)

                if store.tabs.count > 1 {
                    Text("\(min(store.tabs.count, 99))")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tokens.accentText)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .background(tokens.accent, in: Capsule())
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.borderless)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.42).onEnded { _ in
                hapticCounter += 1
                showTabQuickActions = true
            }
        )
        .glassEffectID("rightChromeButton", in: omniboxNamespace)
        .accessibilityLabel("Tabs (\(store.tabs.count))")
        .accessibilityHint("Long press for quick tab actions")
    }

    // MARK: - Search Engine Ribbon (Expanded Mode)

    private func searchEngineRibbon(tokens: PrismThemeTokens) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if let pasteString = UIPasteboard.general.string,
                       !pasteString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            hapticCounter += 1
                            store.navigate(toInput: pasteString)
                        } label: {
                            Label("Paste & Go", systemImage: "doc.on.clipboard")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tokens.accentText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .prismGlassPill(prominent: true, interactive: true)
                        }
                        .buttonStyle(.borderless)
                    }

                    ForEach(SearchEngineOption.allCases) { engine in
                        let isSelected = store.selectedSearchEngine == engine
                        Button {
                            hapticCounter += 1
                            store.selectSearchEngine(engine)
                        } label: {
                            Text(engine.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected ? tokens.accentText : tokens.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .prismGlassPill(prominent: isSelected, interactive: true)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}
