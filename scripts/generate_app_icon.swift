#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Configuration

private let canvasSize = 1024
private let rootDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let iconsetDirectory = rootDirectory
    .appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

private enum IconVariant {
    case standard
    case tinted

    var filename: String {
        switch self {
        case .standard: return "AppIcon-1024.png"
        case .tinted: return "AppIcon-1024-Tinted.png"
        }
    }
}

private func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0, in space: CGColorSpace) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255.0, g / 255.0, b / 255.0, a])!
}

private func renderIcon(variant: IconVariant) throws -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw NSError(domain: "PrismIconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create sRGB color space"])
    }

    // Strict opaque 8-bit sRGB bitmap (NO alpha channel so actool never rejects transparency)
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    guard let ctx = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: canvasSize * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        throw NSError(domain: "PrismIconGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate 1024x1024 CGContext"])
    }

    let size = CGFloat(canvasSize)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let center = CGPoint(x: size * 0.5, y: size * 0.5)

    // 1. Opaque Obsidian Background Gradient (#0A0A0F -> #141422)
    ctx.setFillColor(rgba(10, 10, 15, 1.0, in: colorSpace))
    ctx.fill(rect)

    let bgColors: [CGColor] = variant == .standard
        ? [rgba(26, 22, 38, 1.0, in: colorSpace), rgba(13, 13, 21, 1.0, in: colorSpace), rgba(10, 10, 15, 1.0, in: colorSpace)]
        : [rgba(38, 38, 44, 1.0, in: colorSpace), rgba(18, 18, 22, 1.0, in: colorSpace), rgba(10, 10, 12, 1.0, in: colorSpace)]
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0.0, 0.55, 1.0]) {
        ctx.drawRadialGradient(
            bgGradient,
            startCenter: CGPoint(x: size * 0.5, y: size * 0.56),
            startRadius: 20,
            endCenter: center,
            endRadius: size * 0.72,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // 2. Subtle Crimson Ambient Backlight Glow Behind Prism (Standard Variant)
    if variant == .standard {
        let glowColors = [
            rgba(220, 20, 60, 0.34, in: colorSpace),
            rgba(180, 16, 52, 0.14, in: colorSpace),
            rgba(10, 10, 15, 0.0, in: colorSpace)
        ] as CFArray
        if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.45, 1.0]) {
            ctx.drawRadialGradient(
                glow,
                startCenter: CGPoint(x: size * 0.62, y: size * 0.46),
                startRadius: 10,
                endCenter: CGPoint(x: size * 0.60, y: size * 0.46),
                endRadius: size * 0.46,
                options: []
            )
        }
    }

    // 3. Concentric Precision Optical Rings
    ctx.saveGState()
    for (radius, alpha) in [(size * 0.39, 0.09), (size * 0.44, 0.05)] {
        ctx.setStrokeColor(rgba(255, 255, 255, alpha, in: colorSpace))
        ctx.setLineWidth(2.0)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Prism Vertex Geometry (CoreGraphics origin is bottom-left)
    let apex = CGPoint(x: size * 0.50, y: size * 0.81)
    let bottomLeft = CGPoint(x: size * 0.19, y: size * 0.24)
    let bottomRight = CGPoint(x: size * 0.81, y: size * 0.24)
    let innerCore = CGPoint(x: size * 0.50, y: size * 0.45)

    // 4. Incoming White Optical Beam (Left -> Left Prism Facet)
    ctx.saveGState()
    let incomingPath = CGMutablePath()
    incomingPath.move(to: CGPoint(x: -20, y: size * 0.39))
    incomingPath.addLine(to: CGPoint(x: size * 0.365, y: size * 0.53))
    incomingPath.addLine(to: CGPoint(x: size * 0.382, y: size * 0.48))
    incomingPath.addLine(to: CGPoint(x: -20, y: size * 0.33))
    incomingPath.closeSubpath()
    ctx.addPath(incomingPath)
    ctx.clip()
    let beamColors = [
        rgba(255, 255, 255, 0.05, in: colorSpace),
        rgba(240, 244, 255, 0.65, in: colorSpace),
        rgba(255, 255, 255, 0.92, in: colorSpace)
    ] as CFArray
    if let beamGradient = CGGradient(colorsSpace: colorSpace, colors: beamColors, locations: [0.0, 0.65, 1.0]) {
        ctx.drawLinearGradient(
            beamGradient,
            start: CGPoint(x: 0, y: size * 0.36),
            end: CGPoint(x: size * 0.38, y: size * 0.51),
            options: []
        )
    }
    ctx.restoreGState()

    // 5. Refracted Crimson Dispersion Fan (Right Prism Facet -> Right Edge)
    let dispersionBands: [(topY: CGFloat, botY: CGFloat, color: CGColor)] = variant == .standard
        ? [
            (0.56, 0.48, rgba(255, 92, 122, 0.85, in: colorSpace)),
            (0.49, 0.39, rgba(220, 20, 60, 0.92, in: colorSpace)),
            (0.40, 0.30, rgba(168, 12, 48, 0.78, in: colorSpace))
        ]
        : [
            (0.56, 0.48, rgba(245, 245, 250, 0.80, in: colorSpace)),
            (0.49, 0.39, rgba(210, 210, 220, 0.85, in: colorSpace)),
            (0.40, 0.30, rgba(165, 165, 175, 0.65, in: colorSpace))
        ]

    for band in dispersionBands {
        ctx.saveGState()
        let bandPath = CGMutablePath()
        bandPath.move(to: CGPoint(x: size * 0.615, y: size * 0.525))
        bandPath.addLine(to: CGPoint(x: size + 24, y: size * band.topY))
        bandPath.addLine(to: CGPoint(x: size + 24, y: size * band.botY))
        bandPath.addLine(to: CGPoint(x: size * 0.645, y: size * 0.465))
        bandPath.closeSubpath()
        ctx.addPath(bandPath)
        ctx.clip()

        let gradColors = [band.color, rgba(220, 20, 60, 0.0, in: colorSpace)] as CFArray
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
    // Left Glass Facet (Cool Specular Silver-Obsidian)
    ctx.saveGState()
    let leftFacet = CGMutablePath()
    leftFacet.move(to: apex)
    leftFacet.addLine(to: bottomLeft)
    leftFacet.addLine(to: innerCore)
    leftFacet.closeSubpath()
    ctx.addPath(leftFacet)
    ctx.clip()
    let leftColors = [
        rgba(248, 250, 255, 0.36, in: colorSpace),
        rgba(120, 130, 158, 0.22, in: colorSpace),
        rgba(28, 30, 44, 0.90, in: colorSpace)
    ] as CFArray
    if let g = CGGradient(colorsSpace: colorSpace, colors: leftColors, locations: [0.0, 0.45, 1.0]) {
        ctx.drawLinearGradient(g, start: apex, end: bottomLeft, options: [])
    }
    ctx.restoreGState()

    // Right Glass Facet (Crimson Specular Reflection)
    ctx.saveGState()
    let rightFacet = CGMutablePath()
    rightFacet.move(to: apex)
    rightFacet.addLine(to: innerCore)
    rightFacet.addLine(to: bottomRight)
    rightFacet.closeSubpath()
    ctx.addPath(rightFacet)
    ctx.clip()
    let rightColors: [CGColor] = variant == .standard
        ? [rgba(255, 84, 114, 0.46, in: colorSpace), rgba(220, 20, 60, 0.32, in: colorSpace), rgba(24, 14, 24, 0.92, in: colorSpace)]
        : [rgba(230, 230, 236, 0.42, in: colorSpace), rgba(160, 160, 170, 0.28, in: colorSpace), rgba(26, 26, 30, 0.92, in: colorSpace)]
    if let g = CGGradient(colorsSpace: colorSpace, colors: rightColors as CFArray, locations: [0.0, 0.50, 1.0]) {
        ctx.drawLinearGradient(g, start: apex, end: bottomRight, options: [])
    }
    ctx.restoreGState()

    // Bottom Glass Facet (Deep Obsidian Base with Crimson Rim Bounce)
    ctx.saveGState()
    let baseFacet = CGMutablePath()
    baseFacet.move(to: bottomLeft)
    baseFacet.addLine(to: innerCore)
    baseFacet.addLine(to: bottomRight)
    baseFacet.closeSubpath()
    ctx.addPath(baseFacet)
    ctx.clip()
    let baseColors: [CGColor] = variant == .standard
        ? [rgba(48, 24, 38, 0.88, in: colorSpace), rgba(18, 18, 28, 0.96, in: colorSpace)]
        : [rgba(52, 52, 60, 0.88, in: colorSpace), rgba(20, 20, 24, 0.96, in: colorSpace)]
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
    let internalColors: [CGColor] = variant == .standard
        ? [rgba(255, 255, 255, 0.78, in: colorSpace), rgba(255, 120, 146, 0.65, in: colorSpace), rgba(220, 20, 60, 0.88, in: colorSpace)]
        : [rgba(255, 255, 255, 0.80, in: colorSpace), rgba(215, 215, 222, 0.65, in: colorSpace)]
    if let g = CGGradient(colorsSpace: colorSpace, colors: internalColors as CFArray, locations: variant == .standard ? [0.0, 0.52, 1.0] : [0.0, 1.0]) {
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

    // Outer Prism Rim
    let outerRim = CGMutablePath()
    outerRim.move(to: apex)
    outerRim.addLine(to: bottomRight)
    outerRim.addLine(to: bottomLeft)
    outerRim.closeSubpath()
    ctx.addPath(outerRim)
    ctx.setStrokeColor(rgba(255, 255, 255, 0.72, in: colorSpace))
    ctx.setLineWidth(7.5)
    ctx.strokePath()

    // Inner Ridge Lines
    ctx.setStrokeColor(rgba(255, 255, 255, 0.36, in: colorSpace))
    ctx.setLineWidth(4.0)
    ctx.move(to: apex)
    ctx.addLine(to: innerCore)
    ctx.move(to: bottomLeft)
    ctx.addLine(to: innerCore)
    ctx.move(to: bottomRight)
    ctx.addLine(to: innerCore)
    ctx.strokePath()

    // Crimson Rim Highlight on Right Edge (Standard Variant)
    if variant == .standard {
        ctx.setStrokeColor(rgba(255, 64, 96, 0.90, in: colorSpace))
        ctx.setLineWidth(4.5)
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

do {
    for variant in [IconVariant.standard, IconVariant.tinted] {
        let image = try renderIcon(variant: variant)
        let outputURL = iconsetDirectory.appendingPathComponent(variant.filename)
        try writeOpaquePNG(image, to: outputURL)
        print("[icon-gen] Generated opaque \(image.width)x\(image.height) sRGB PNG (alphaInfo=\(image.alphaInfo.rawValue)): \(outputURL.path)")
    }
} catch {
    fputs("[icon-gen] error: \(error)\n", stderr)
    exit(1)
}
