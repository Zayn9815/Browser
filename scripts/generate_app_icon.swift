#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Configuration

private let canvasSize = 1024
private let previewSize = 180
private let rootDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let assetsDirectory = rootDirectory.appendingPathComponent("App/Resources/Assets.xcassets", isDirectory: true)

private struct RGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
}

private struct IconThemeSpec {
    let iconSetName: String
    let bgCenter: RGB
    let bgMid: RGB
    let bgEdge: RGB
    let glowPrimary: RGB
    let glowSecondary: RGB
    let dispersionTop: RGB
    let dispersionMid: RGB
    let dispersionBot: RGB
    let rightFacetTop: RGB
    let rightFacetMid: RGB
    let rightFacetBot: RGB
    let baseTop: RGB
    let baseBot: RGB
    let rimAccent: RGB
    let isLight: Bool
}

private let allIconSpecs: [IconThemeSpec] = [
    // 1. Default: Crimson Liquid Glass
    IconThemeSpec(
        iconSetName: "AppIcon",
        bgCenter: RGB(r: 56, g: 11, b: 22),
        bgMid: RGB(r: 26, g: 5, b: 10),
        bgEdge: RGB(r: 13, g: 3, b: 5),
        glowPrimary: RGB(r: 255, g: 45, b: 85),
        glowSecondary: RGB(r: 180, g: 16, b: 52),
        dispersionTop: RGB(r: 255, g: 100, b: 130),
        dispersionMid: RGB(r: 255, g: 45, b: 85),
        dispersionBot: RGB(r: 168, g: 24, b: 56),
        rightFacetTop: RGB(r: 255, g: 94, b: 126),
        rightFacetMid: RGB(r: 220, g: 20, b: 60),
        rightFacetBot: RGB(r: 34, g: 10, b: 18),
        baseTop: RGB(r: 58, g: 18, b: 30),
        baseBot: RGB(r: 20, g: 8, b: 14),
        rimAccent: RGB(r: 255, g: 72, b: 108),
        isLight: false
    ),
    // 2. iPhone Duo (Space Black & Apple Sapphire)
    IconThemeSpec(
        iconSetName: "AppIcon-Duo",
        bgCenter: RGB(r: 26, g: 30, b: 38),
        bgMid: RGB(r: 18, g: 21, b: 27),
        bgEdge: RGB(r: 9, g: 10, b: 13),
        glowPrimary: RGB(r: 10, g: 132, b: 255),
        glowSecondary: RGB(r: 90, g: 200, b: 250),
        dispersionTop: RGB(r: 120, g: 212, b: 255),
        dispersionMid: RGB(r: 10, g: 132, b: 255),
        dispersionBot: RGB(r: 8, g: 86, b: 196),
        rightFacetTop: RGB(r: 90, g: 200, b: 250),
        rightFacetMid: RGB(r: 10, g: 132, b: 255),
        rightFacetBot: RGB(r: 16, g: 22, b: 34),
        baseTop: RGB(r: 26, g: 36, b: 54),
        baseBot: RGB(r: 12, g: 15, b: 22),
        rimAccent: RGB(r: 90, g: 200, b: 250),
        isLight: false
    ),
    // 3. Glacier Liquid Glass (Night-Blue Ice & Glacial Aqua)
    IconThemeSpec(
        iconSetName: "AppIcon-Glacier",
        bgCenter: RGB(r: 31, g: 77, b: 98),
        bgMid: RGB(r: 18, g: 43, b: 67),
        bgEdge: RGB(r: 9, g: 21, b: 36),
        glowPrimary: RGB(r: 0, g: 245, b: 255),
        glowSecondary: RGB(r: 79, g: 255, b: 176),
        dispersionTop: RGB(r: 128, g: 255, b: 220),
        dispersionMid: RGB(r: 0, g: 245, b: 255),
        dispersionBot: RGB(r: 14, g: 140, b: 180),
        rightFacetTop: RGB(r: 128, g: 245, b: 255),
        rightFacetMid: RGB(r: 0, g: 210, b: 235),
        rightFacetBot: RGB(r: 12, g: 32, b: 48),
        baseTop: RGB(r: 22, g: 58, b: 78),
        baseBot: RGB(r: 10, g: 24, b: 38),
        rimAccent: RGB(r: 0, g: 245, b: 255),
        isLight: false
    ),
    // 4. Anodized Obsidian (Matte Obsidian & Electric Mint)
    IconThemeSpec(
        iconSetName: "AppIcon-ObsidianMint",
        bgCenter: RGB(r: 23, g: 28, b: 38),
        bgMid: RGB(r: 18, g: 22, b: 29),
        bgEdge: RGB(r: 9, g: 11, b: 14),
        glowPrimary: RGB(r: 50, g: 215, b: 75),
        glowSecondary: RGB(r: 99, g: 230, b: 134),
        dispersionTop: RGB(r: 130, g: 242, b: 162),
        dispersionMid: RGB(r: 50, g: 215, b: 75),
        dispersionBot: RGB(r: 26, g: 136, b: 52),
        rightFacetTop: RGB(r: 99, g: 230, b: 134),
        rightFacetMid: RGB(r: 50, g: 215, b: 75),
        rightFacetBot: RGB(r: 14, g: 26, b: 20),
        baseTop: RGB(r: 24, g: 46, b: 34),
        baseBot: RGB(r: 12, g: 16, b: 20),
        rimAccent: RGB(r: 50, g: 215, b: 75),
        isLight: false
    ),
    // 5. Sahara Sand (Desert Dusk & Terracotta Gold)
    IconThemeSpec(
        iconSetName: "AppIcon-Sahara",
        bgCenter: RGB(r: 51, g: 34, b: 21),
        bgMid: RGB(r: 38, g: 26, b: 16),
        bgEdge: RGB(r: 26, g: 18, b: 11),
        glowPrimary: RGB(r: 229, g: 169, b: 82),
        glowSecondary: RGB(r: 217, g: 119, b: 66),
        dispersionTop: RGB(r: 245, g: 214, b: 167),
        dispersionMid: RGB(r: 229, g: 169, b: 82),
        dispersionBot: RGB(r: 196, g: 102, b: 52),
        rightFacetTop: RGB(r: 245, g: 206, b: 142),
        rightFacetMid: RGB(r: 229, g: 169, b: 82),
        rightFacetBot: RGB(r: 38, g: 24, b: 14),
        baseTop: RGB(r: 68, g: 44, b: 24),
        baseBot: RGB(r: 28, g: 18, b: 11),
        rimAccent: RGB(r: 240, g: 186, b: 104),
        isLight: false
    ),
    // 6. Classic Stock (Native iOS Dark & System Blue)
    IconThemeSpec(
        iconSetName: "AppIcon-Classic",
        bgCenter: RGB(r: 34, g: 34, b: 38),
        bgMid: RGB(r: 18, g: 18, b: 20),
        bgEdge: RGB(r: 0, g: 0, b: 0),
        glowPrimary: RGB(r: 10, g: 132, b: 255),
        glowSecondary: RGB(r: 100, g: 210, b: 255),
        dispersionTop: RGB(r: 110, g: 212, b: 255),
        dispersionMid: RGB(r: 10, g: 132, b: 255),
        dispersionBot: RGB(r: 0, g: 92, b: 204),
        rightFacetTop: RGB(r: 100, g: 210, b: 255),
        rightFacetMid: RGB(r: 10, g: 132, b: 255),
        rightFacetBot: RGB(r: 18, g: 20, b: 26),
        baseTop: RGB(r: 30, g: 36, b: 48),
        baseBot: RGB(r: 14, g: 14, b: 18),
        rimAccent: RGB(r: 64, g: 168, b: 255),
        isLight: false
    ),
    // 7. Frost Light (Crisp Light Frost & Crimson Prism)
    IconThemeSpec(
        iconSetName: "AppIcon-Frost",
        bgCenter: RGB(r: 255, g: 255, b: 255),
        bgMid: RGB(r: 240, g: 243, b: 250),
        bgEdge: RGB(r: 224, g: 229, b: 240),
        glowPrimary: RGB(r: 220, g: 20, b: 60),
        glowSecondary: RGB(r: 255, g: 82, b: 112),
        dispersionTop: RGB(r: 255, g: 94, b: 124),
        dispersionMid: RGB(r: 220, g: 20, b: 60),
        dispersionBot: RGB(r: 168, g: 16, b: 48),
        rightFacetTop: RGB(r: 255, g: 76, b: 108),
        rightFacetMid: RGB(r: 220, g: 20, b: 60),
        rightFacetBot: RGB(r: 146, g: 18, b: 46),
        baseTop: RGB(r: 218, g: 224, b: 236),
        baseBot: RGB(r: 188, g: 196, b: 212),
        rimAccent: RGB(r: 220, g: 20, b: 60),
        isLight: true
    ),
]

private func rgba(_ c: RGB, _ a: CGFloat = 1.0, in space: CGColorSpace) -> CGColor {
    CGColor(colorSpace: space, components: [c.r / 255.0, c.g / 255.0, c.b / 255.0, a])!
}

private func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0, in space: CGColorSpace) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255.0, g / 255.0, b / 255.0, a])!
}

private func renderIcon(spec: IconThemeSpec, tinted: Bool, pixelSize: Int) throws -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw NSError(domain: "PrismIconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create sRGB color space"])
    }

    // Strict opaque 8-bit sRGB bitmap (NO alpha channel so actool never rejects transparency)
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        throw NSError(domain: "PrismIconGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate CGContext"])
    }

    let size = CGFloat(pixelSize)
    let scale = size / 1024.0
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let center = CGPoint(x: size * 0.5, y: size * 0.5)

    // 1. Opaque Background Gradient
    ctx.setFillColor(tinted ? rgba(10, 10, 12, 1.0, in: colorSpace) : rgba(spec.bgEdge, 1.0, in: colorSpace))
    ctx.fill(rect)

    let bgColors: [CGColor] = tinted
        ? [rgba(38, 38, 44, 1.0, in: colorSpace), rgba(18, 18, 22, 1.0, in: colorSpace), rgba(10, 10, 12, 1.0, in: colorSpace)]
        : [rgba(spec.bgCenter, 1.0, in: colorSpace), rgba(spec.bgMid, 1.0, in: colorSpace), rgba(spec.bgEdge, 1.0, in: colorSpace)]

    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0.0, 0.55, 1.0]) {
        ctx.drawRadialGradient(
            bgGradient,
            startCenter: CGPoint(x: size * 0.5, y: size * 0.56),
            startRadius: 20 * scale,
            endCenter: center,
            endRadius: size * 0.72,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // 2. Subtle Theme Ambient Backlight Glow Behind Prism
    if !tinted {
        let glowAlphaA: CGFloat = spec.isLight ? 0.22 : 0.34
        let glowAlphaB: CGFloat = spec.isLight ? 0.10 : 0.14
        let glowColors = [
            rgba(spec.glowPrimary, glowAlphaA, in: colorSpace),
            rgba(spec.glowSecondary, glowAlphaB, in: colorSpace),
            rgba(spec.bgEdge, 0.0, in: colorSpace)
        ] as CFArray
        if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.45, 1.0]) {
            ctx.drawRadialGradient(
                glow,
                startCenter: CGPoint(x: size * 0.62, y: size * 0.46),
                startRadius: 10 * scale,
                endCenter: CGPoint(x: size * 0.60, y: size * 0.46),
                endRadius: size * 0.46,
                options: []
            )
        }
    }

    // 3. Concentric Precision Optical Rings
    ctx.saveGState()
    let ringColor = (!tinted && spec.isLight) ? RGB(r: 20, g: 24, b: 36) : RGB(r: 255, g: 255, b: 255)
    for (radius, alpha) in [(size * 0.39, 0.09), (size * 0.44, 0.05)] {
        ctx.setStrokeColor(rgba(ringColor, alpha, in: colorSpace))
        ctx.setLineWidth(2.0 * scale)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Exact PrismDM Vertex Geometry (CoreGraphics origin is bottom-left)
    let apex = CGPoint(x: size * 0.50, y: size * 0.81)
    let bottomLeft = CGPoint(x: size * 0.19, y: size * 0.24)
    let bottomRight = CGPoint(x: size * 0.81, y: size * 0.24)
    let innerCore = CGPoint(x: size * 0.50, y: size * 0.45)

    // 4. Incoming Optical Beam (Left -> Left Prism Facet)
    ctx.saveGState()
    let incomingPath = CGMutablePath()
    incomingPath.move(to: CGPoint(x: -20 * scale, y: size * 0.39))
    incomingPath.addLine(to: CGPoint(x: size * 0.365, y: size * 0.53))
    incomingPath.addLine(to: CGPoint(x: size * 0.382, y: size * 0.48))
    incomingPath.addLine(to: CGPoint(x: -20 * scale, y: size * 0.33))
    incomingPath.closeSubpath()
    ctx.addPath(incomingPath)
    ctx.clip()
    let beamColors: [CGColor] = (!tinted && spec.isLight)
        ? [rgba(30, 36, 52, 0.05, in: colorSpace), rgba(30, 36, 52, 0.35, in: colorSpace), rgba(20, 24, 36, 0.65, in: colorSpace)]
        : [rgba(255, 255, 255, 0.05, in: colorSpace), rgba(240, 244, 255, 0.65, in: colorSpace), rgba(255, 255, 255, 0.92, in: colorSpace)]
    if let beamGradient = CGGradient(colorsSpace: colorSpace, colors: beamColors as CFArray, locations: [0.0, 0.65, 1.0]) {
        ctx.drawLinearGradient(
            beamGradient,
            start: CGPoint(x: 0, y: size * 0.36),
            end: CGPoint(x: size * 0.38, y: size * 0.51),
            options: []
        )
    }
    ctx.restoreGState()

    // 5. Refracted Dispersion Fan (Right Prism Facet -> Right Edge)
    let dispersionBands: [(topY: CGFloat, botY: CGFloat, color: CGColor)] = tinted
        ? [
            (0.56, 0.48, rgba(245, 245, 250, 0.80, in: colorSpace)),
            (0.49, 0.39, rgba(210, 210, 220, 0.85, in: colorSpace)),
            (0.40, 0.30, rgba(165, 165, 175, 0.65, in: colorSpace))
        ]
        : [
            (0.56, 0.48, rgba(spec.dispersionTop, 0.85, in: colorSpace)),
            (0.49, 0.39, rgba(spec.dispersionMid, 0.92, in: colorSpace)),
            (0.40, 0.30, rgba(spec.dispersionBot, 0.78, in: colorSpace))
        ]

    for band in dispersionBands {
        ctx.saveGState()
        let bandPath = CGMutablePath()
        bandPath.move(to: CGPoint(x: size * 0.615, y: size * 0.525))
        bandPath.addLine(to: CGPoint(x: size + 24 * scale, y: size * band.topY))
        bandPath.addLine(to: CGPoint(x: size + 24 * scale, y: size * band.botY))
        bandPath.addLine(to: CGPoint(x: size * 0.645, y: size * 0.465))
        bandPath.closeSubpath()
        ctx.addPath(bandPath)
        ctx.clip()

        let gradColors = [band.color, rgba(spec.dispersionMid, 0.0, in: colorSpace)] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: size * 0.62, y: size * 0.50),
                end: CGPoint(x: size * 1.02, y: size * ((band.topY + band.botY) * 0.5)),
                options: []
            )
        }
        ctx.restoreGState()
    }

    // 6. Faceted Glass Prism Body (Three Geometric Planes)
    // Left Glass Facet
    ctx.saveGState()
    let leftFacet = CGMutablePath()
    leftFacet.move(to: apex)
    leftFacet.addLine(to: bottomLeft)
    leftFacet.addLine(to: innerCore)
    leftFacet.closeSubpath()
    ctx.addPath(leftFacet)
    ctx.clip()
    let leftColors: [CGColor] = (!tinted && spec.isLight)
        ? [rgba(255, 255, 255, 0.94, in: colorSpace), rgba(214, 220, 234, 0.85, in: colorSpace), rgba(164, 174, 196, 0.92, in: colorSpace)]
        : [rgba(248, 250, 255, 0.36, in: colorSpace), rgba(120, 130, 158, 0.22, in: colorSpace), rgba(28, 30, 44, 0.90, in: colorSpace)]
    if let g = CGGradient(colorsSpace: colorSpace, colors: leftColors as CFArray, locations: [0.0, 0.45, 1.0]) {
        ctx.drawLinearGradient(g, start: apex, end: bottomLeft, options: [])
    }
    ctx.restoreGState()

    // Right Glass Facet
    ctx.saveGState()
    let rightFacet = CGMutablePath()
    rightFacet.move(to: apex)
    rightFacet.addLine(to: innerCore)
    rightFacet.addLine(to: bottomRight)
    rightFacet.closeSubpath()
    ctx.addPath(rightFacet)
    ctx.clip()
    let rightColors: [CGColor] = tinted
        ? [rgba(230, 230, 236, 0.42, in: colorSpace), rgba(160, 160, 170, 0.28, in: colorSpace), rgba(26, 26, 30, 0.92, in: colorSpace)]
        : [rgba(spec.rightFacetTop, spec.isLight ? 0.72 : 0.46, in: colorSpace),
           rgba(spec.rightFacetMid, spec.isLight ? 0.56 : 0.32, in: colorSpace),
           rgba(spec.rightFacetBot, 0.92, in: colorSpace)]
    if let g = CGGradient(colorsSpace: colorSpace, colors: rightColors as CFArray, locations: [0.0, 0.50, 1.0]) {
        ctx.drawLinearGradient(g, start: apex, end: bottomRight, options: [])
    }
    ctx.restoreGState()

    // Bottom Glass Facet
    ctx.saveGState()
    let baseFacet = CGMutablePath()
    baseFacet.move(to: bottomLeft)
    baseFacet.addLine(to: innerCore)
    baseFacet.addLine(to: bottomRight)
    baseFacet.closeSubpath()
    ctx.addPath(baseFacet)
    ctx.clip()
    let baseColors: [CGColor] = tinted
        ? [rgba(52, 52, 60, 0.88, in: colorSpace), rgba(20, 20, 24, 0.96, in: colorSpace)]
        : [rgba(spec.baseTop, 0.88, in: colorSpace), rgba(spec.baseBot, 0.96, in: colorSpace)]
    if let g = CGGradient(colorsSpace: colorSpace, colors: baseColors as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(g, start: innerCore, end: CGPoint(x: size * 0.5, y: size * 0.24), options: [])
    }
    ctx.restoreGState()

    // 7. Internal Refraction Beam Crossing Prism Core
    ctx.saveGState()
    let internalBeam = CGMutablePath()
    internalBeam.move(to: CGPoint(x: size * 0.365, y: size * 0.53))
    internalBeam.addLine(to: CGPoint(x: size * 0.625, y: size * 0.52))
    internalBeam.addLine(to: CGPoint(x: size * 0.648, y: size * 0.462))
    internalBeam.addLine(to: CGPoint(x: size * 0.382, y: size * 0.48))
    internalBeam.closeSubpath()
    ctx.addPath(internalBeam)
    ctx.clip()
    let internalColors: [CGColor] = tinted
        ? [rgba(255, 255, 255, 0.80, in: colorSpace), rgba(215, 215, 222, 0.65, in: colorSpace)]
        : [rgba(255, 255, 255, 0.82, in: colorSpace), rgba(spec.dispersionTop, 0.72, in: colorSpace), rgba(spec.dispersionMid, 0.90, in: colorSpace)]
    if let g = CGGradient(colorsSpace: colorSpace, colors: internalColors as CFArray, locations: tinted ? [0.0, 1.0] : [0.0, 0.52, 1.0]) {
        ctx.drawLinearGradient(
            g,
            start: CGPoint(x: size * 0.365, y: size * 0.50),
            end: CGPoint(x: size * 0.645, y: size * 0.49),
            options: []
        )
    }
    ctx.restoreGState()

    // 8. Specular Liquid Glass Bevel Strokes
    ctx.saveGState()
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)

    let outerRim = CGMutablePath()
    outerRim.move(to: apex)
    outerRim.addLine(to: bottomRight)
    outerRim.addLine(to: bottomLeft)
    outerRim.closeSubpath()
    ctx.addPath(outerRim)
    ctx.setStrokeColor((!tinted && spec.isLight) ? rgba(24, 28, 42, 0.55, in: colorSpace) : rgba(255, 255, 255, 0.72, in: colorSpace))
    ctx.setLineWidth(7.5 * scale)
    ctx.strokePath()

    ctx.setStrokeColor((!tinted && spec.isLight) ? rgba(24, 28, 42, 0.25, in: colorSpace) : rgba(255, 255, 255, 0.36, in: colorSpace))
    ctx.setLineWidth(4.0 * scale)
    ctx.move(to: apex)
    ctx.addLine(to: innerCore)
    ctx.move(to: bottomLeft)
    ctx.addLine(to: innerCore)
    ctx.move(to: bottomRight)
    ctx.addLine(to: innerCore)
    ctx.strokePath()

    if !tinted {
        ctx.setStrokeColor(rgba(spec.rimAccent, 0.92, in: colorSpace))
        ctx.setLineWidth(4.5 * scale)
        ctx.move(to: apex)
        ctx.addLine(to: bottomRight)
        ctx.strokePath()
    }
    ctx.restoreGState()

    guard let image = ctx.makeImage() else {
        throw NSError(domain: "PrismIconGen", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
    }
    return image
}

private func writeOpaquePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "PrismIconGen", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot create PNG destination at \(url.path)"])
    }
    let properties: [CFString: Any] = [
        kCGImagePropertyHasAlpha: false,
        kCGImagePropertyDPIWidth: 144,
        kCGImagePropertyDPIHeight: 144
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "PrismIconGen", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG at \(url.path)"])
    }
}

private func writeAppIconContentsJSON(to dir: URL, standardFile: String, tintedFile: String) throws {
    let json = """
    {
      "images" : [
        {
          "filename" : "\(standardFile)",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
        {
          "appearances" : [
            {
              "appearance" : "luminosity",
              "value" : "dark"
            }
          ],
          "filename" : "\(standardFile)",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
        {
          "appearances" : [
            {
              "appearance" : "luminosity",
              "value" : "tinted"
            }
          ],
          "filename" : "\(tintedFile)",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

private func writePreviewImageSet(image: CGImage, assetName: String) throws {
    let dir = assetsDirectory.appendingPathComponent("\(assetName).imageset", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let filename = "\(assetName).png"
    try writeOpaquePNG(image, to: dir.appendingPathComponent(filename))
    let json = """
    {
      "images" : [
        {
          "filename" : "\(filename)",
          "idiom" : "universal",
          "scale" : "3x"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

do {
    for spec in allIconSpecs {
        let iconDir = assetsDirectory.appendingPathComponent("\(spec.iconSetName).appiconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)

        let stdName = "\(spec.iconSetName)-1024.png"
        let tintName = "\(spec.iconSetName)-1024-Tinted.png"

        let stdImg = try renderIcon(spec: spec, tinted: false, pixelSize: canvasSize)
        let tintImg = try renderIcon(spec: spec, tinted: true, pixelSize: canvasSize)
        try writeOpaquePNG(stdImg, to: iconDir.appendingPathComponent(stdName))
        try writeOpaquePNG(tintImg, to: iconDir.appendingPathComponent(tintName))
        try writeAppIconContentsJSON(to: iconDir, standardFile: stdName, tintedFile: tintName)

        let previewImg = try renderIcon(spec: spec, tinted: false, pixelSize: previewSize)
        try writePreviewImageSet(image: previewImg, assetName: "IconPreview-\(spec.iconSetName)")

        print("[icon-gen] Generated opaque \(spec.iconSetName) (1024x1024 + tinted + 180x180 preview)")
    }
} catch {
    fputs("[icon-gen] error: \(error)\n", stderr)
    exit(1)
}
