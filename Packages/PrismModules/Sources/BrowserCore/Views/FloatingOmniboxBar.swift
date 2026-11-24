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

    private let isTopMode: Bool

    public init(store: BrowserStore, isTopMode: Bool = false) {
        self.store = store
        self.isTopMode = isTopMode
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        VStack(spacing: 8) {
            if !isTopMode && store.isOmniboxExpanded {
                searchEngineRibbon(tokens: tokens)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Strictly NO SwiftUI Menu inside morphing GlassEffectContainer
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 8) {
                    if !store.isOmniboxExpanded {
                        navigationUnionPill(tokens: tokens)
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
                        .buttonStyle(.glass)
                        .glassEffectID("rightChromeButton", in: omniboxNamespace)
                    } else {
                        rightControlsUnionPill(tokens: tokens)
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
        .onChange(of: store.isOmniboxExpanded) { _, expanded in
            isAddressFieldFocused = expanded
            if expanded {
                horizontalSwipeOffset = 0
            }
        }
    }

    private func navigationUnionPill(tokens: PrismThemeTokens) -> some View {
        HStack(spacing: 0) {
            Button {
                hapticCounter += 1
                store.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!store.activeTab.canGoBack)
            .opacity(store.activeTab.canGoBack ? 1.0 : 0.36)
            .accessibilityLabel("Back")

            Button {
                hapticCounter += 1
                store.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!store.activeTab.canGoForward)
            .opacity(store.activeTab.canGoForward ? 1.0 : 0.36)
            .accessibilityLabel("Forward")
        }
        .padding(.horizontal, 2)
        .foregroundStyle(tokens.primaryText)
        .glassEffect(.regular, in: .capsule)
        .glassEffectUnion(id: "navCluster", namespace: omniboxNamespace)
    }

    private func addressCapsule(tokens: PrismThemeTokens) -> some View {
        HStack(spacing: 2) {
            if store.isOmniboxExpanded {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tokens.accent)
                    .padding(.leading, 12)
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
                            .frame(width: 38, height: 44)
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
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 4)
                .accessibilityLabel("Scan QR Code URL")
            } else {
                Button {
                    hapticCounter += 1
                    store.isSiteMenuPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.activeTab.isIncognito
                            ? "eye.slash.fill"
                            : (store.activeTab.hasOnlySecureContent ? "shield.lefthalf.filled" : "exclamationmark.triangle.fill"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(store.activeTab.isIncognito ? .purple : tokens.accent)

                        if store.activeTab.blockedTrackerCount > 0 {
                            Text("\(store.activeTab.blockedTrackerCount)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(tokens.secondaryText)
                        }
                    }
                    .padding(.leading, 11)
                    .padding(.trailing, 5)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Site Security and Controls")

                Button {
                    hapticCounter += 1
                    store.omniboxText = store.activeTab.urlString
                    withAnimation(.bouncy(duration: 0.30)) {
                        store.isOmniboxExpanded = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.activeTab.displayHost)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(tokens.primaryText)
                            .lineLimit(1)
                        if store.activeTab.isLoading {
                            ProgressView(value: max(0.08, store.activeTab.estimatedProgress))
                                .tint(tokens.accent)
                                .scaleEffect(y: 0.65)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                Button {
                    hapticCounter += 1
                    store.reloadOrStop()
                } label: {
                    Image(systemName: store.activeTab.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tokens.primaryText)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 3)
                .accessibilityLabel(store.activeTab.isLoading ? "Stop Loading" : "Reload")
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .capsule)
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

    private func rightControlsUnionPill(tokens: PrismThemeTokens) -> some View {
        HStack(spacing: 0) {
            Button {
                hapticCounter += 1
                store.isTabGridPresented = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(tokens.primaryText.opacity(0.85), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    Text("\(store.tabs.count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(tokens.primaryText)
                }
                .frame(width: 38, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open Tab Grid (\(store.tabs.count) tabs)")

            Button {
                hapticCounter += 1
                store.isBrowserMenuPresented = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tokens.primaryText)
                    .frame(width: 38, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Browser Menu")
        }
        .padding(.horizontal, 2)
        .glassEffect(.regular, in: .capsule)
        .glassEffectID("rightChromeButton", in: omniboxNamespace)
    }

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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(tokens.accent)
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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .tint(isSelected ? tokens.accent : .clear)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}
