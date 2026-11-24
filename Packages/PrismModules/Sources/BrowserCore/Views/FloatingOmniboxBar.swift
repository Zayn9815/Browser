import SwiftUI
import UIKit

public struct FloatingOmniboxBar: View {
    @Bindable private var store: BrowserStore
    @FocusState private var isAddressFieldFocused: Bool
    @Namespace private var omniboxNamespace
    @State private var hapticCounter = 0

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 8) {
            if store.isOmniboxExpanded {
                searchEngineRibbon
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Strictly NO SwiftUI Menu inside morphing GlassEffectContainer
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    if !store.isOmniboxExpanded {
                        navigationUnionPill
                    }

                    addressCapsule

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
                        .buttonStyle(.glass)
                        .glassEffectID("rightChromeButton", in: omniboxNamespace)
                    } else {
                        tabCounterButton
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: hapticCounter)
        .onChange(of: store.isOmniboxExpanded) { _, expanded in
            isAddressFieldFocused = expanded
        }
    }

    private var navigationUnionPill: some View {
        HStack(spacing: 0) {
            Button {
                hapticCounter += 1
                store.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 38, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!store.activeTab.canGoBack)
            .opacity(store.activeTab.canGoBack ? 1.0 : 0.38)
            .accessibilityLabel("Back")

            Button {
                hapticCounter += 1
                store.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 38, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!store.activeTab.canGoForward)
            .opacity(store.activeTab.canGoForward ? 1.0 : 0.38)
            .accessibilityLabel("Forward")
        }
        .padding(.horizontal, 4)
        .foregroundStyle(.white)
        .glassEffect(.regular, in: .capsule)
        .glassEffectUnion(id: "navCluster", namespace: omniboxNamespace)
    }

    private var addressCapsule: some View {
        HStack(spacing: 2) {
            if store.isOmniboxExpanded {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PrismBrandPalette.crimsonAccent)
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
                .foregroundStyle(.white)
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
                            .foregroundStyle(.white.opacity(0.75))
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
                        .foregroundStyle(.white)
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
                            .foregroundStyle(store.activeTab.isIncognito ? .purple : PrismBrandPalette.crimsonAccent)

                        if store.activeTab.blockedTrackerCount > 0 {
                            Text("\(store.activeTab.blockedTrackerCount)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
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
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if store.activeTab.isLoading {
                            ProgressView(value: max(0.08, store.activeTab.estimatedProgress))
                                .tint(PrismBrandPalette.crimsonAccent)
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
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 4)
                .accessibilityLabel(store.activeTab.isLoading ? "Stop Loading" : "Reload")
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .capsule)
        .glassEffectID("addressCapsule", in: omniboxNamespace)
    }

    private var tabCounterButton: some View {
        Button {
            hapticCounter += 1
            store.isTabGridPresented = true
        } label: {
            Text("\(store.tabs.count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .glassEffectID("rightChromeButton", in: omniboxNamespace)
        .accessibilityLabel("Open Tab Grid (\(store.tabs.count) tabs)")
    }

    private var searchEngineRibbon: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if let pasteString = UIPasteboard.general.string, !pasteString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            hapticCounter += 1
                            store.navigate(toInput: pasteString)
                        } label: {
                            Label("Paste & Go", systemImage: "doc.on.clipboard")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(PrismBrandPalette.crimsonAccent)
                    }

                    ForEach(SearchEngineOption.allCases) { engine in
                        let isSelected = store.selectedSearchEngine == engine
                        Button {
                            hapticCounter += 1
                            store.selectSearchEngine(engine)
                        } label: {
                            Text(engine.displayName)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .tint(isSelected ? PrismBrandPalette.crimsonAccent : .clear)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}
