import SwiftUI
import UIKit

public enum PrismThemeID: String, CaseIterable, Codable, Sendable, Identifiable {
    case crimsonLiquidGlass
    case iPhoneDuo
    case glacierLiquidGlass
    case anodizedObsidian
    case saharaSand
    case classicStock
    case frostLight

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .crimsonLiquidGlass: return "Crimson Liquid Glass"
        case .iPhoneDuo: return "iPhone Duo"
        case .glacierLiquidGlass: return "Glacier Liquid Glass"
        case .anodizedObsidian: return "Anodized Obsidian"
        case .saharaSand: return "Sahara Sand"
        case .classicStock: return "Classic Stock"
        case .frostLight: return "Frost Light"
        }
    }

    public var subtitle: String {
        switch self {
        case .crimsonLiquidGlass: return "Deep burgundy & obsidian ruby · Glowing Crimson"
        case .iPhoneDuo: return "Space Black & Graphite glass · Apple Sapphire"
        case .glacierLiquidGlass: return "Sub-zero night-blue ice · Glacial Aqua & Aurora"
        case .anodizedObsidian: return "Matte obsidian crystal · Surgical Electric Mint"
        case .saharaSand: return "Desert dusk dunes · Terracotta Gold frosted glass"
        case .classicStock: return "Clean native iOS dark surfaces & system blue"
        case .frostLight: return "Crisp light Liquid Glass · High-contrast Crimson"
        }
    }

    public var tokens: PrismThemeTokens {
        switch self {
        case .crimsonLiquidGlass:
            return PrismThemeTokens(
                id: self,
                canvasTop: .prismHex(0x1A050A),
                canvasMid: .prismHex(0x380B16),
                canvasGlow: .prismHex(0x4A1020),
                canvasEdge: .prismHex(0x0D0305),
                elevatedSurface: .prismHex(0x2C0811),
                cardSurface: .prismHex(0x3A0C18, alpha: 0.54),
                plainCellSurface: .prismHex(0x3A0C18, alpha: 0.42),
                glassTint: .prismHex(0x3A0C18, alpha: 0.54),
                glassAlpha: 0.54,
                glassStroke: .prismHex(0xFFE0E8, alpha: 0.32),
                glassSecondaryStroke: .prismHex(0xFF6482, alpha: 0.26),
                sheen: .prismHex(0xFFD6E0),
                sheenAlpha: 0.07,
                hairline: .prismHex(0xFFDCE4, alpha: 0.16),
                primaryText: .prismHex(0xFFFFFF),
                secondaryText: .prismHex(0xF4B8C4),
                tertiaryText: .prismHex(0xFFDCE4, alpha: 0.78),
                accent: .prismHex(0xFF2D55),
                secondaryAccent: .prismHex(0xFF6482),
                accentText: .prismHex(0xFFFFFF),
                activePill: .prismHex(0xA81838),
                destructive: .prismHex(0xFF453A),
                preferredColorScheme: .dark,
                swatchBackground: .prismHex(0x1A050A)
            )

        case .iPhoneDuo:
            return PrismThemeTokens(
                id: self,
                canvasTop: .prismHex(0x090A0D),
                canvasMid: .prismHex(0x12151B),
                canvasGlow: .prismHex(0x1A1E26),
                canvasEdge: .prismHex(0x050608),
                elevatedSurface: .prismHex(0x161920),
                cardSurface: .prismHex(0x161920, alpha: 0.72),
                plainCellSurface: .prismHex(0x161920, alpha: 0.56),
                glassTint: .prismHex(0x161920, alpha: 0.72),
                glassAlpha: 0.72,
                glassStroke: .prismHex(0xFFFFFF, alpha: 0.30),
                glassSecondaryStroke: .prismHex(0x5AC8FA, alpha: 0.24),
                sheen: .prismHex(0xFFFFFF),
                sheenAlpha: 0.07,
                hairline: .prismHex(0xFFFFFF, alpha: 0.10),
                primaryText: .prismHex(0xFFFFFF),
                secondaryText: .prismHex(0x9BA3B0),
                tertiaryText: .prismHex(0xC3C9D3, alpha: 0.80),
                accent: .prismHex(0x0A84FF),
                secondaryAccent: .prismHex(0x5AC8FA),
                accentText: .prismHex(0xFFFFFF),
                activePill: .prismHex(0x0A84FF),
                destructive: .prismHex(0xFF453A),
                preferredColorScheme: .dark,
                swatchBackground: .prismHex(0x12151B)
            )

        case .glacierLiquidGlass:
            return PrismThemeTokens(
                id: self,
                canvasTop: .prismHex(0x091524),
                canvasMid: .prismHex(0x122B43),
                canvasGlow: .prismHex(0x1F4D62),
                canvasEdge: .prismHex(0x04090E),
                elevatedSurface: .prismHex(0x11283F),
                cardSurface: .prismHex(0x102A45, alpha: 0.48),
                plainCellSurface: .prismHex(0x102A45, alpha: 0.36),
                glassTint: .prismHex(0x102A45, alpha: 0.48),
                glassAlpha: 0.48,
                glassStroke: .prismHex(0xE0FFFF, alpha: 0.32),
                glassSecondaryStroke: .prismHex(0x80F0FF, alpha: 0.22),
                sheen: .prismHex(0xE0FFFF),
                sheenAlpha: 0.06,
                hairline: .prismHex(0xD1E8FA, alpha: 0.16),
                primaryText: .prismHex(0xFFFFFF),
                secondaryText: .prismHex(0xB0E2FF),
                tertiaryText: .prismHex(0xD1E8FA, alpha: 0.82),
                accent: .prismHex(0x00F5FF),
                secondaryAccent: .prismHex(0x4FFFB0),
                accentText: .prismHex(0x071A2B),
                activePill: .prismHex(0x0E5A74),
                destructive: .prismHex(0xFF453A),
                preferredColorScheme: .dark,
                swatchBackground: .prismHex(0x122B43)
            )

        case .anodizedObsidian:
            return PrismThemeTokens(
                id: self,
                canvasTop: .prismHex(0x090B0E),
                canvasMid: .prismHex(0x12161D),
                canvasGlow: .prismHex(0x171C26),
                canvasEdge: .prismHex(0x050608),
                elevatedSurface: .prismHex(0x141820),
                cardSurface: .prismHex(0x12161D, alpha: 0.74),
                plainCellSurface: .prismHex(0x12161D, alpha: 0.60),
                glassTint: .prismHex(0x12161D, alpha: 0.74),
                glassAlpha: 0.74,
                glassStroke: .prismHex(0xDAE2EE, alpha: 0.26),
                glassSecondaryStroke: .prismHex(0x32D74B, alpha: 0.24),
                sheen: .prismHex(0xFFFFFF),
                sheenAlpha: 0.05,
                hairline: .prismHex(0xFFFFFF, alpha: 0.09),
                primaryText: .prismHex(0xFFFFFF),
                secondaryText: .prismHex(0x9AA3B2),
                tertiaryText: .prismHex(0xC4CCD8, alpha: 0.80),
                accent: .prismHex(0x32D74B),
                secondaryAccent: .prismHex(0x63E686),
                accentText: .prismHex(0x06140A),
                activePill: .prismHex(0x1E7D32),
                destructive: .prismHex(0xFF453A),
                preferredColorScheme: .dark,
                swatchBackground: .prismHex(0x12161D)
            )

        case .saharaSand:
            return PrismThemeTokens(
                id: self,
                canvasTop: .prismHex(0x1A120B),
                canvasMid: .prismHex(0x261A10),
                canvasGlow: .prismHex(0x332215),
                canvasEdge: .prismHex(0x120C07),
                elevatedSurface: .prismHex(0x24180F),
                cardSurface: .prismHex(0x2B1D12, alpha: 0.68),
                plainCellSurface: .prismHex(0x2B1D12, alpha: 0.50),
                glassTint: .prismHex(0x2B1D12, alpha: 0.68),
                glassAlpha: 0.68,
                glassStroke: .prismHex(0xF5D6A7, alpha: 0.34),
                glassSecondaryStroke: .prismHex(0xD97742, alpha: 0.28),
                sheen: .prismHex(0xF5D6A7),
                sheenAlpha: 0.08,
                hairline: .prismHex(0xF5D6A7, alpha: 0.16),
                primaryText: .prismHex(0xFFF7EB),
                secondaryText: .prismHex(0xD6C0A6),
                tertiaryText: .prismHex(0xEAD7BF, alpha: 0.82),
                accent: .prismHex(0xE5A952),
                secondaryAccent: .prismHex(0xD97742),
                accentText: .prismHex(0x1A120B),
                activePill: .prismHex(0xB87424),
                destructive: .prismHex(0xFF453A),
                preferredColorScheme: .dark,
                swatchBackground: .prismHex(0x261A10)
            )

        case .classicStock:
            return PrismThemeTokens(
                id: self,
                canvasTop: .prismHex(0x000000),
                canvasMid: .prismHex(0x0E0E10),
                canvasGlow: .prismHex(0x1C1C1E),
                canvasEdge: .prismHex(0x000000),
                elevatedSurface: .prismHex(0x1C1C1E),
                cardSurface: .prismHex(0x1C1C1E, alpha: 0.88),
                plainCellSurface: .prismHex(0x1C1C1E, alpha: 0.82),
                glassTint: .prismHex(0x1C1C1E, alpha: 0.88),
                glassAlpha: 0.88,
                glassStroke: .prismHex(0xFFFFFF, alpha: 0.16),
                glassSecondaryStroke: .prismHex(0x0A84FF, alpha: 0.22),
                sheen: .prismHex(0xFFFFFF),
                sheenAlpha: 0.02,
                hairline: .prismHex(0x545458, alpha: 0.45),
                primaryText: .prismHex(0xFFFFFF),
                secondaryText: .prismHex(0xA1A1AA),
                tertiaryText: .prismHex(0xD1D1D6, alpha: 0.82),
                accent: .prismHex(0x0A84FF),
                secondaryAccent: .prismHex(0x64D2FF),
                accentText: .prismHex(0xFFFFFF),
                activePill: .prismHex(0x0A84FF),
                destructive: .prismHex(0xFF453A),
                preferredColorScheme: .dark,
                swatchBackground: .prismHex(0x0E0E10)
            )

        case .frostLight:
            return PrismThemeTokens(
                id: self,
                canvasTop: .prismHex(0xF6F7FB),
                canvasMid: .prismHex(0xECEFF6),
                canvasGlow: .prismHex(0xDCE5F8),
                canvasEdge: .prismHex(0xE8ECF5),
                elevatedSurface: .prismHex(0xFFFFFF),
                cardSurface: .prismHex(0xFFFFFF, alpha: 0.78),
                plainCellSurface: .prismHex(0xFFFFFF, alpha: 0.68),
                glassTint: .prismHex(0xFFFFFF, alpha: 0.76),
                glassAlpha: 0.76,
                glassStroke: .prismHex(0x11131A, alpha: 0.14),
                glassSecondaryStroke: .prismHex(0xDC143C, alpha: 0.22),
                sheen: .prismHex(0xFFFFFF),
                sheenAlpha: 0.22,
                hairline: .prismHex(0x11131A, alpha: 0.12),
                primaryText: .prismHex(0x11131A),
                secondaryText: .prismHex(0x4A5164),
                tertiaryText: .prismHex(0x646D82),
                accent: .prismHex(0xDC143C),
                secondaryAccent: .prismHex(0xFF2D55),
                accentText: .prismHex(0xFFFFFF),
                activePill: .prismHex(0xDC143C),
                destructive: .prismHex(0xD70015),
                preferredColorScheme: .light,
                swatchBackground: .prismHex(0xF0F2F8)
            )
        }
    }
}

public struct PrismThemeTokens: Sendable {
    public let id: PrismThemeID
    public let canvasTop: Color
    public let canvasMid: Color
    public let canvasGlow: Color
    public let canvasEdge: Color
    public let elevatedSurface: Color
    public let cardSurface: Color
    public let plainCellSurface: Color
    public let glassTint: Color
    public let glassAlpha: Double
    public let glassStroke: Color
    public let glassSecondaryStroke: Color
    public let sheen: Color
    public let sheenAlpha: Double
    public let hairline: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let tertiaryText: Color
    public let accent: Color
    public let secondaryAccent: Color
    public let accentText: Color
    public let activePill: Color
    public let destructive: Color
    public let preferredColorScheme: ColorScheme
    public let swatchBackground: Color

    public var canvasBackground: Color { canvasTop }
    public var isLight: Bool { preferredColorScheme == .light }
    public var isClassicStock: Bool { id == .classicStock }
}

public enum PrismWallpaperOption: String, CaseIterable, Codable, Sendable, Identifiable {
    case matchActiveTheme
    case alpineGlacier
    case crimsonRubyGlow
    case glacierAuroraIce
    case anodizedMintMesh
    case saharaDuskDunes
    case spaceBlackSapphire
    case pureObsidianMatte
    case customPhoto

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .matchActiveTheme: return "Match Active Theme"
        case .alpineGlacier: return "Alpine Glacier"
        case .crimsonRubyGlow: return "Crimson Ruby Glow"
        case .glacierAuroraIce: return "Glacier Aurora Ice"
        case .anodizedMintMesh: return "Anodized Mint Mesh"
        case .saharaDuskDunes: return "Sahara Dusk Dunes"
        case .spaceBlackSapphire: return "Space Black Sapphire"
        case .pureObsidianMatte: return "Pure Obsidian Matte"
        case .customPhoto: return "Custom Photo"
        }
    }

    public var previewColors: [Color] {
        switch self {
        case .matchActiveTheme:
            return [.prismHex(0x380B16), .prismHex(0xFF2D55)]
        case .alpineGlacier:
            return [.prismHex(0xB8CBE8), .prismHex(0x4F83D1), .prismHex(0x1E6A8A)]
        case .crimsonRubyGlow:
            return [.prismHex(0x1A050A), .prismHex(0x4A1020), .prismHex(0xFF2D55)]
        case .glacierAuroraIce:
            return [.prismHex(0x091524), .prismHex(0x1F4D62), .prismHex(0x00F5FF)]
        case .anodizedMintMesh:
            return [.prismHex(0x090B0E), .prismHex(0x14261E), .prismHex(0x32D74B)]
        case .saharaDuskDunes:
            return [.prismHex(0x1A120B), .prismHex(0x3A2414), .prismHex(0xE5A952)]
        case .spaceBlackSapphire:
            return [.prismHex(0x090A0D), .prismHex(0x152238), .prismHex(0x0A84FF)]
        case .pureObsidianMatte:
            return [.prismHex(0x0A0A0F), .prismHex(0x161620), .prismHex(0x262634)]
        case .customPhoto:
            return [.prismHex(0x2A2D36), .prismHex(0x52586A)]
        }
    }
}

public enum PrismAlternateAppIcon: String, CaseIterable, Codable, Sendable, Identifiable {
    case crimsonDefault = "AppIcon"
    case iPhoneDuo = "AppIcon-Duo"
    case glacier = "AppIcon-Glacier"
    case obsidianMint = "AppIcon-ObsidianMint"
    case sahara = "AppIcon-Sahara"
    case classic = "AppIcon-Classic"
    case frost = "AppIcon-Frost"

    public var id: String { rawValue }

    /// Value passed to `UIApplication.shared.setAlternateIconName(_:)`. `nil` restores the primary icon.
    public var alternateIconName: String? {
        self == .crimsonDefault ? nil : rawValue
    }

    public var previewAssetName: String {
        "IconPreview-\(rawValue)"
    }

    public var displayName: String {
        switch self {
        case .crimsonDefault: return "Crimson"
        case .iPhoneDuo: return "Duo"
        case .glacier: return "Glacier"
        case .obsidianMint: return "Obsidian Mint"
        case .sahara: return "Sahara"
        case .classic: return "Classic"
        case .frost: return "Frost"
        }
    }

    public var previewAccent: Color {
        switch self {
        case .crimsonDefault: return .prismHex(0xFF2D55)
        case .iPhoneDuo: return .prismHex(0x0A84FF)
        case .glacier: return .prismHex(0x00F5FF)
        case .obsidianMint: return .prismHex(0x32D74B)
        case .sahara: return .prismHex(0xE5A952)
        case .classic: return .prismHex(0x0A84FF)
        case .frost: return .prismHex(0xDC143C)
        }
    }

    public var previewBackground: Color {
        switch self {
        case .crimsonDefault: return .prismHex(0x1A050A)
        case .iPhoneDuo: return .prismHex(0x090A0D)
        case .glacier: return .prismHex(0x091524)
        case .obsidianMint: return .prismHex(0x090B0E)
        case .sahara: return .prismHex(0x1A120B)
        case .classic: return .prismHex(0x000000)
        case .frost: return .prismHex(0xF2F4F8)
        }
    }
}

public extension Color {
    static func prismHex(_ rgb: UInt32, alpha: Double = 1.0) -> Color {
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
