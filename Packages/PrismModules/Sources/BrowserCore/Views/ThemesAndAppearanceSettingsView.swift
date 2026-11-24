import PhotosUI
import PrismCore
import SwiftUI

public struct ThemesAndAppearanceSettingsView: View {
    @Bindable private var store: BrowserStore
    @State private var themeEngine = PrismThemeEngine.shared

    @State private var selectedWallpaperPhoto: PhotosPickerItem?
    @State private var iconStatusMessage: String?

    private let iconColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        List {
            // 1. Themes (all 7 palettes with dual-dot swatches)
            Section {
                ForEach(PrismThemeID.allCases) { themeID in
                    let previewTokens = themeID.tokens
                    let isSelected = themeEngine.selectedTheme == themeID
                    Button {
                        withAnimation(.snappy(duration: 0.24)) {
                            themeEngine.selectedTheme = themeID
                        }
                    } label: {
                        HStack(spacing: 12) {
                            dualSwatchDots(
                                primary: previewTokens.swatchBackground,
                                secondary: previewTokens.accent,
                                stroke: previewTokens.hairline
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(themeID.displayName)
                                    .font(.body.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                Text(themeID.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(tokens.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Theme Palette")
            } footer: {
                Text("Themes apply immediately across the Start Page, Liquid Glass chrome, Downloads, Vault, and Settings with WCAG AA+ text contrast.")
            }

            // 2. Search Bar Position
            Section {
                Picker(
                    "Search Bar Position",
                    selection: Binding(
                        get: { store.settings.searchBarPosition },
                        set: { store.setSearchBarPosition($0) }
                    )
                ) {
                    ForEach(SearchBarPosition.allCases) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Browser Layout")
            } footer: {
                Text("Bottom keeps the search bar within one-hand thumb reach above the Home Indicator. Swipe left or right on the address bar to switch tabs.")
            }

            // 3. Start Page Wallpaper
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(PrismWallpaperOption.allCases.filter { $0 != .customPhoto }) { option in
                            wallpaperCard(option: option, tokens: tokens)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))

                PhotosPicker(
                    selection: $selectedWallpaperPhoto,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack {
                        Label("Choose Custom Photo…", systemImage: "photo.on.rectangle.angled")
                        Spacer()
                        if themeEngine.selectedWallpaper == .customPhoto {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(tokens.accent)
                        }
                    }
                }
                .onChange(of: selectedWallpaperPhoto) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                _ = themeEngine.saveCustomWallpaperData(data)
                                selectedWallpaperPhoto = nil
                            }
                        }
                    }
                }

                if themeEngine.customWallpaperImage != nil {
                    Button("Remove Custom Wallpaper", role: .destructive) {
                        themeEngine.clearCustomWallpaper()
                    }
                }
            } header: {
                Text("Start Page Wallpaper")
            } footer: {
                Text("Custom wallpapers are downscaled once and stored on disk with zero idle GPU cost.")
            }

            // 4. Alternate App Icons (exact PrismDM prism geometry)
            Section {
                LazyVGrid(columns: iconColumns, spacing: 14) {
                    ForEach(PrismAlternateAppIcon.allCases) { icon in
                        let isSelected = themeEngine.activeAppIcon == icon
                        Button {
                            Task {
                                await themeEngine.applyAlternateAppIcon(icon)
                                if let err = themeEngine.iconChangeError {
                                    iconStatusMessage = err
                                } else {
                                    iconStatusMessage = "App icon updated to \(icon.displayName)."
                                }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    if let uiImage = UIImage(named: icon.previewAssetName) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    } else {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(icon.previewBackground)
                                            .frame(width: 60, height: 60)
                                            .overlay(
                                                Image(systemName: "pyramid.fill")
                                                    .font(.title2)
                                                    .foregroundStyle(icon.previewAccent)
                                            )
                                    }

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(.white, tokens.accent)
                                            .offset(x: 4, y: -4)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(isSelected ? tokens.accent : Color.clear, lineWidth: 2.5)
                                )

                                Text(icon.displayName)
                                    .font(.caption2.weight(isSelected ? .bold : .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 6)

                if let iconStatusMessage {
                    Text(iconStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("App Icon")
            } footer: {
                Text("All 7 alternate icons preserve the PrismDM geometric prism logo in matching theme palettes.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Themes & Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .tint(tokens.accent)
    }

    private func dualSwatchDots(primary: Color, secondary: Color, stroke: Color) -> some View {
        ZStack {
            Circle()
                .fill(primary)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(stroke, lineWidth: 1))
                .offset(x: -5)
            Circle()
                .fill(secondary)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .offset(x: 7, y: 2)
        }
        .frame(width: 38, height: 28)
    }

    private func wallpaperCard(option: PrismWallpaperOption, tokens: PrismThemeTokens) -> some View {
        let isSelected = themeEngine.selectedWallpaper == option
        let gradientColors = option == .matchActiveTheme
            ? [tokens.canvasTop, tokens.canvasMid, tokens.accent.opacity(0.65)]
            : option.previewColors
        return Button {
            themeEngine.selectedWallpaper = option
        } label: {
            VStack(spacing: 6) {
                LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 78, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? tokens.accent : Color.primary.opacity(0.15), lineWidth: isSelected ? 2.5 : 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white, tokens.accent)
                                .padding(5)
                        }
                    }

                Text(option.displayName)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 82)
        }
        .buttonStyle(.borderless)
    }
}
