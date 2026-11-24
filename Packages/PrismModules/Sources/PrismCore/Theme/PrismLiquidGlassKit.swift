import SwiftUI

// MARK: - Static 6-Layer Atmospheric Backdrop (wqfiles WQPrismBackgroundView parity, zero GPU loops)

/// Battery-friendly multi-stop atmospheric backdrop matching `wqfiles` material richness.
/// Completely static at rest so iPhone ProMotion drops cleanly to 1–10 Hz with zero continuous GPU wake-ups.
public struct PrismThemeBackdropView: View {
    @State private var themeEngine = PrismThemeEngine.shared
    private let overrideTokens: PrismThemeTokens?

    public init(overrideTokens: PrismThemeTokens? = nil) {
        self.overrideTokens = overrideTokens
    }

    public var body: some View {
        let tokens = overrideTokens ?? themeEngine.tokens
        let glowScale: Double = tokens.isClassicStock ? 0.12 : (tokens.isLight ? 0.45 : 1.0)

        GeometryReader { geo in
            let w = max(geo.size.width, 320)
            let h = max(geo.size.height, 640)

            ZStack {
                // Layer 1: 4-stop diagonal base gradient
                LinearGradient(
                    stops: [
                        .init(color: tokens.canvasTop, location: 0.0),
                        .init(color: tokens.canvasMid, location: 0.32),
                        .init(color: tokens.canvasGlow, location: 0.64),
                        .init(color: tokens.canvasEdge, location: 1.0),
                    ],
                    startPoint: UnitPoint(x: 0.35, y: 0.0),
                    endPoint: UnitPoint(x: 0.65, y: 1.0)
                )

                // Layer 2: Subtle diagonal polar-glow ribbon
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: tokens.accent.opacity(0.10 * glowScale), location: 0.35),
                        .init(color: tokens.secondaryAccent.opacity(0.08 * glowScale), location: 0.65),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: UnitPoint(x: 0.0, y: 0.25),
                    endPoint: UnitPoint(x: 1.0, y: 0.75)
                )

                // Layers 3–6: 4 static radial ambient glow blooms
                RadialGradient(
                    colors: [tokens.accent.opacity(0.20 * glowScale), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: w * 0.47
                )
                .frame(width: w * 0.94, height: w * 0.94)
                .position(x: w * 0.13, y: h * 0.18)

                RadialGradient(
                    colors: [tokens.secondaryAccent.opacity(0.12 * glowScale), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: w * 0.43
                )
                .frame(width: w * 0.86, height: w * 0.86)
                .position(x: w * 0.83, y: h * 0.14)

                RadialGradient(
                    colors: [tokens.canvasGlow.opacity(0.46 * glowScale), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: w * 0.48
                )
                .frame(width: w * 0.96, height: w * 0.96)
                .position(x: w * 0.72, y: h * 0.78)

                RadialGradient(
                    colors: [tokens.canvasEdge.opacity(tokens.isLight ? 0.22 : 0.60), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: w * 0.39
                )
                .frame(width: w * 0.78, height: w * 0.78)
                .position(x: w * 0.09, y: h * 0.86)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Alpine Glacier Layered Mountain Wallpaper (Safari iOS 26 reference preset)

public struct PrismAlpineWallpaperView: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                LinearGradient(
                    colors: [.prismHex(0xDCE5F2), .prismHex(0xB8CBE8), .prismHex(0x8BB2E3)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Distant sunlit ridge
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.46))
                    p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.38))
                    p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.44))
                    p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.34))
                    p.addLine(to: CGPoint(x: w, y: h * 0.40))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [.prismHex(0x7DA7E0), .prismHex(0x4E80CE)],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                // Mid alpine ridge
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.56))
                    p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.49))
                    p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.55))
                    p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.47))
                    p.addLine(to: CGPoint(x: w, y: h * 0.54))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [.prismHex(0x3D78C4), .prismHex(0x286796)],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                // Foreground glacier valley
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.72))
                    p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.66))
                    p.addLine(to: CGPoint(x: w * 0.65, y: h * 0.75))
                    p.addLine(to: CGPoint(x: w, y: h * 0.69))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [.prismHex(0x1E6584), .prismHex(0x134B67)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Liquid Glass Surface Modifiers

private struct PrismGlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var themeEngine = PrismThemeEngine.shared

    let cornerRadius: CGFloat
    let prominent: Bool

    func body(content: Content) -> some View {
        let tokens = themeEngine.tokens
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency || lowPower {
            content
                .background(tokens.elevatedSurface, in: shape)
                .overlay(
                    shape.strokeBorder(
                        prominent ? tokens.accent.opacity(0.60) : tokens.glassStroke,
                        lineWidth: prominent ? 1.15 : 0.85
                    )
                )
        } else {
            content
                .background {
                    shape
                        .fill(tokens.cardSurface)
                        .overlay(
                            LinearGradient(
                                colors: [
                                    tokens.sheen.opacity(tokens.sheenAlpha * (prominent ? 1.6 : 1.0)),
                                    .clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .clipShape(shape)
                        )
                }
                .glassEffect(.regular.tint(tokens.glassTint.opacity(tokens.isLight ? 0.45 : 0.65)), in: shape)
                .overlay(
                    shape.strokeBorder(
                        prominent ? tokens.accent.opacity(0.65) : tokens.glassStroke,
                        lineWidth: prominent ? 1.15 : 0.85
                    )
                )
                .overlay(
                    shape
                        .inset(by: 0.9)
                        .strokeBorder(tokens.glassSecondaryStroke.opacity(0.55), lineWidth: 0.5)
                )
        }
    }
}

private struct PrismGlassPillModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var themeEngine = PrismThemeEngine.shared

    let prominent: Bool
    let interactive: Bool

    func body(content: Content) -> some View {
        let tokens = themeEngine.tokens
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let tintColor = prominent ? tokens.accent : tokens.glassTint.opacity(tokens.isLight ? 0.50 : 0.72)

        if reduceTransparency || lowPower {
            content
                .background(prominent ? tokens.accent : tokens.elevatedSurface, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        prominent ? tokens.secondaryAccent.opacity(0.65) : tokens.glassStroke,
                        lineWidth: 0.9
                    )
                )
        } else {
            content
                .glassEffect(
                    interactive ? .regular.tint(tintColor).interactive() : .regular.tint(tintColor),
                    in: .capsule
                )
                .overlay(
                    Capsule().strokeBorder(
                        prominent ? tokens.secondaryAccent.opacity(0.65) : tokens.glassStroke,
                        lineWidth: 0.9
                    )
                )
        }
    }
}

private struct PrismGlassCircleButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var themeEngine = PrismThemeEngine.shared

    let size: CGFloat
    let prominent: Bool
    let active: Bool

    func body(content: Content) -> some View {
        let tokens = themeEngine.tokens
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let tintColor = prominent
            ? tokens.accent
            : (active ? tokens.activePill.opacity(0.78) : tokens.glassTint.opacity(tokens.isLight ? 0.50 : 0.72))

        if reduceTransparency || lowPower {
            content
                .frame(width: size, height: size)
                .background(prominent ? tokens.accent : tokens.elevatedSurface, in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        (prominent || active) ? tokens.accent.opacity(0.75) : tokens.glassStroke,
                        lineWidth: 0.95
                    )
                )
                .contentShape(Circle())
        } else {
            content
                .frame(width: size, height: size)
                .glassEffect(.regular.tint(tintColor), in: .circle)
                .overlay(
                    Circle().strokeBorder(
                        (prominent || active) ? tokens.accent.opacity(0.75) : tokens.glassStroke,
                        lineWidth: 0.95
                    )
                )
                .shadow(
                    color: (prominent || active) ? tokens.accent.opacity(0.30) : .clear,
                    radius: 8,
                    y: 2
                )
                .contentShape(Circle())
        }
    }
}

private struct PrismThemedScrollChromeModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var themeEngine = PrismThemeEngine.shared

    func body(content: Content) -> some View {
        let tokens = themeEngine.tokens
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        content
            .scrollContentBackground(.hidden)
            .listRowBackground(
                (reduceTransparency || lowPower) ? tokens.elevatedSurface : tokens.cardSurface
            )
            .listRowSeparatorTint(tokens.hairline)
            .background(PrismThemeBackdropView())
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(tokens.preferredColorScheme)
            .tint(tokens.accent)
    }
}

private struct PrismGlassListRowModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var themeEngine = PrismThemeEngine.shared

    func body(content: Content) -> some View {
        let tokens = themeEngine.tokens
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        content
            .listRowBackground(
                (reduceTransparency || lowPower) ? tokens.elevatedSurface : tokens.cardSurface
            )
            .listRowSeparatorTint(tokens.hairline)
    }
}

private struct PrismThemedSheetChromeModifier: ViewModifier {
    @State private var themeEngine = PrismThemeEngine.shared

    func body(content: Content) -> some View {
        let tokens = themeEngine.tokens
        content
            .presentationBackground {
                PrismThemeBackdropView()
            }
            .preferredColorScheme(tokens.preferredColorScheme)
            .tint(tokens.accent)
    }
}

public extension View {
    func prismGlassCard(cornerRadius: CGFloat = 20, prominent: Bool = false) -> some View {
        modifier(PrismGlassCardModifier(cornerRadius: cornerRadius, prominent: prominent))
    }

    func prismGlassPill(prominent: Bool = false, interactive: Bool = false) -> some View {
        modifier(PrismGlassPillModifier(prominent: prominent, interactive: interactive))
    }

    func prismGlassCircleButton(size: CGFloat = 46, prominent: Bool = false, active: Bool = false) -> some View {
        modifier(PrismGlassCircleButtonModifier(size: size, prominent: prominent, active: active))
    }

    func prismThemedScrollChrome() -> some View {
        modifier(PrismThemedScrollChromeModifier())
    }

    func prismGlassListRow() -> some View {
        modifier(PrismGlassListRowModifier())
    }

    func prismThemedSheetChrome() -> some View {
        modifier(PrismThemedSheetChromeModifier())
    }
}
