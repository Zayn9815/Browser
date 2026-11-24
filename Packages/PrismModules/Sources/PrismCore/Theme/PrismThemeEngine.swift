import Foundation
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
public final class PrismThemeEngine {
    public static let shared = PrismThemeEngine()

    public var selectedTheme: PrismThemeID {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: Self.themeKey)
        }
    }

    public var selectedWallpaper: PrismWallpaperOption {
        didSet {
            UserDefaults.standard.set(selectedWallpaper.rawValue, forKey: Self.wallpaperKey)
        }
    }

    public private(set) var activeAppIcon: PrismAlternateAppIcon
    public private(set) var customWallpaperImage: UIImage?
    public private(set) var iconChangeError: String?

    private static let themeKey = "prismdm.v2.selectedTheme"
    private static let wallpaperKey = "prismdm.v2.selectedWallpaper"
    private static let iconKey = "prismdm.v2.selectedAppIcon"

    public var tokens: PrismThemeTokens {
        selectedTheme.tokens
    }

    public init() {
        if let rawTheme = UserDefaults.standard.string(forKey: Self.themeKey),
           let parsed = PrismThemeID(rawValue: rawTheme) {
            self.selectedTheme = parsed
        } else {
            self.selectedTheme = .crimsonLiquidGlass
        }

        if let rawWall = UserDefaults.standard.string(forKey: Self.wallpaperKey),
           let parsedWall = PrismWallpaperOption(rawValue: rawWall) {
            self.selectedWallpaper = parsedWall
        } else {
            self.selectedWallpaper = .matchActiveTheme
        }

        if let systemIconName = UIApplication.shared.alternateIconName,
           let matched = PrismAlternateAppIcon(rawValue: systemIconName) {
            self.activeAppIcon = matched
        } else if let savedIcon = UserDefaults.standard.string(forKey: Self.iconKey),
                  let parsedIcon = PrismAlternateAppIcon(rawValue: savedIcon) {
            self.activeAppIcon = parsedIcon
        } else {
            self.activeAppIcon = .crimsonDefault
        }

        self.customWallpaperImage = Self.loadCustomWallpaperFromDisk()
    }

    public func applyAlternateAppIcon(_ icon: PrismAlternateAppIcon) async {
        iconChangeError = nil
        guard UIApplication.shared.supportsAlternateIcons else {
            iconChangeError = "Alternate app icons are not supported on this device."
            return
        }
        do {
            try await UIApplication.shared.setAlternateIconName(icon.alternateIconName)
            activeAppIcon = icon
            UserDefaults.standard.set(icon.rawValue, forKey: Self.iconKey)
        } catch {
            iconChangeError = error.localizedDescription
        }
    }

    public func saveCustomWallpaperData(_ rawData: Data) -> Bool {
        guard let image = UIImage(data: rawData) else { return false }
        let downscaled = Self.downscaleForScreen(image, maxDimension: 1800)
        guard let jpeg = downscaled.jpegData(compressionQuality: 0.84) else { return false }
        do {
            let url = try Self.customWallpaperFileURL()
            try jpeg.write(to: url, options: .atomic)
            customWallpaperImage = downscaled
            selectedWallpaper = .customPhoto
            return true
        } catch {
            return false
        }
    }

    public func clearCustomWallpaper() {
        if let url = try? Self.customWallpaperFileURL() {
            try? FileManager.default.removeItem(at: url)
        }
        customWallpaperImage = nil
        if selectedWallpaper == .customPhoto {
            selectedWallpaper = .matchActiveTheme
        }
    }

    private static func customWallpaperFileURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PrismDM", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("start_wallpaper.jpg")
    }

    private static func loadCustomWallpaperFromDisk() -> UIImage? {
        guard let url = try? customWallpaperFileURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }

    private static func downscaleForScreen(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// Static, battery-friendly atmospheric background view (zero continuous GPU animations).
public struct PrismAtmosphericWallpaperView: View {
    @Bindable private var themeEngine: PrismThemeEngine
    private let overrideWallpaper: PrismWallpaperOption?

    public init(
        themeEngine: PrismThemeEngine = .shared,
        overrideWallpaper: PrismWallpaperOption? = nil
    ) {
        self.themeEngine = themeEngine
        self.overrideWallpaper = overrideWallpaper
    }

    private var effectiveWallpaper: PrismWallpaperOption {
        overrideWallpaper ?? themeEngine.selectedWallpaper
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        ZStack {
            if effectiveWallpaper == .customPhoto, let image = themeEngine.customWallpaperImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                // Adaptive contrast scrim ensuring Start Page text & tiles remain legible
                LinearGradient(
                    colors: tokens.isLight
                        ? [Color.white.opacity(0.62), Color.white.opacity(0.42), Color.white.opacity(0.72)]
                        : [Color.black.opacity(0.58), Color.black.opacity(0.38), Color.black.opacity(0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                curatedGradient(for: effectiveWallpaper, tokens: tokens)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func curatedGradient(for option: PrismWallpaperOption, tokens: PrismThemeTokens) -> some View {
        switch option {
        case .matchActiveTheme:
            meshBackdrop(
                top: tokens.canvasTop,
                mid: tokens.canvasMid,
                edge: tokens.canvasEdge,
                glowA: tokens.canvasGlow,
                glowB: tokens.accent.opacity(tokens.isLight ? 0.14 : 0.22)
            )
        case .crimsonRubyGlow:
            meshBackdrop(
                top: .prismHex(0x1A050A),
                mid: .prismHex(0x380B16),
                edge: .prismHex(0x0D0305),
                glowA: .prismHex(0x5A1226),
                glowB: .prismHex(0xFF2D55, alpha: 0.26)
            )
        case .glacierAuroraIce:
            meshBackdrop(
                top: .prismHex(0x091524),
                mid: .prismHex(0x122B43),
                edge: .prismHex(0x04090E),
                glowA: .prismHex(0x1F4D62),
                glowB: .prismHex(0x00F5FF, alpha: 0.20)
            )
        case .anodizedMintMesh:
            meshBackdrop(
                top: .prismHex(0x090B0E),
                mid: .prismHex(0x12161D),
                edge: .prismHex(0x050608),
                glowA: .prismHex(0x132B1F),
                glowB: .prismHex(0x32D74B, alpha: 0.18)
            )
        case .saharaDuskDunes:
            meshBackdrop(
                top: .prismHex(0x1A120B),
                mid: .prismHex(0x2B1D12),
                edge: .prismHex(0x120C07),
                glowA: .prismHex(0x452A16),
                glowB: .prismHex(0xE5A952, alpha: 0.20)
            )
        case .spaceBlackSapphire:
            meshBackdrop(
                top: .prismHex(0x090A0D),
                mid: .prismHex(0x12151B),
                edge: .prismHex(0x050608),
                glowA: .prismHex(0x15253F),
                glowB: .prismHex(0x0A84FF, alpha: 0.22)
            )
        case .pureObsidianMatte:
            LinearGradient(
                colors: [.prismHex(0x0A0A0F), .prismHex(0x111118), .prismHex(0x07070B)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .customPhoto:
            LinearGradient(
                colors: [tokens.canvasTop, tokens.canvasMid, tokens.canvasEdge],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func meshBackdrop(top: Color, mid: Color, edge: Color, glowA: Color, glowB: Color) -> some View {
        ZStack {
            LinearGradient(
                colors: [top, mid, edge],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [glowA.opacity(0.85), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 380
            )
            RadialGradient(
                colors: [glowB, .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 340
            )
        }
    }
}
