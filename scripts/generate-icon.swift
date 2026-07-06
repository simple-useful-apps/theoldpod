// Generates the theoldpod app icon: a minimal iPod click wheel — one
// off-white ring and a center button — on a deep desaturated-blue gradient.
// Pure geometry, no skeuomorphism (see GOAL.md §Principles).
//
// Usage: swift scripts/generate-icon.swift   (from the repo root)
// Writes PNGs directly into both asset catalogs. Regenerate any time.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

let bgTop = CGColor(srgbRed: 0.243, green: 0.373, blue: 0.612, alpha: 1) // #3E5F9C
let bgBottom = CGColor(srgbRed: 0.067, green: 0.110, blue: 0.220, alpha: 1) // #111C38
let wheel = CGColor(srgbRed: 0.953, green: 0.953, blue: 0.937, alpha: 1) // #F3F3EF
let button = CGColor(srgbRed: 0.898, green: 0.898, blue: 0.878, alpha: 1) // #E5E5E0

// Geometry at the 1024pt reference size (content scale 1.0).
// Real iPod click-wheel proportions: the center button is ~half the wheel's
// diameter, separated from the ring by a thin seam of background.
let refSize: CGFloat = 1024
let wheelOuterR: CGFloat = 340
let wheelInnerR: CGFloat = 196
let buttonR: CGFloat = 172

/// Draws the icon into `ctx`. `rounded` inset-masks the artwork the way
/// macOS icons expect (transparent margin + rounded rect); iOS wants
/// full-bleed and masks the corners itself.
func draw(in ctx: CGContext, pixelSize: Int, rounded: Bool) {
    let size = CGFloat(pixelSize)
    let s = size / refSize

    var contentScale: CGFloat = 1
    if rounded {
        // macOS: artwork occupies the central ~82% inside a rounded rect.
        let inset = 92 * s
        let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let path = CGPath(roundedRect: rect, cornerWidth: 168 * s, cornerHeight: 168 * s, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        contentScale = 0.82
    }

    // Background: vertical deep-blue gradient.
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [bgTop, bgBottom] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: size / 2, y: size),
        end: CGPoint(x: size / 2, y: 0),
        options: []
    )

    let center = CGPoint(x: size / 2, y: size / 2)
    let k = s * contentScale

    // Wheel ring (even-odd fill of two concentric circles).
    ctx.setFillColor(wheel)
    ctx.addEllipse(in: circleRect(center: center, radius: wheelOuterR * k))
    ctx.addEllipse(in: circleRect(center: center, radius: wheelInnerR * k))
    ctx.fillPath(using: .evenOdd)

    // Center button, slightly dimmer, with a seam of background around it.
    ctx.setFillColor(button)
    ctx.fillEllipse(in: circleRect(center: center, radius: buttonR * k))
}

func circleRect(center: CGPoint, radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

func render(pixelSize: Int, rounded: Bool, to url: URL) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: pixelSize, height: pixelSize,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    draw(in: ctx, pixelSize: pixelSize, rounded: rounded)
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed to write \(url.path)") }
    print("wrote \(url.lastPathComponent) (\(pixelSize)px)")
}

// MARK: - Output

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iosSet = root.appendingPathComponent("Apps/iOS/Resources/Assets.xcassets/AppIcon.appiconset")
let macSet = root.appendingPathComponent("Apps/macOS/Resources/Assets.xcassets/AppIcon.appiconset")

// iOS: single universal 1024, full-bleed (system masks the corners).
render(pixelSize: 1024, rounded: false, to: iosSet.appendingPathComponent("AppIcon1024.png"))

// macOS: the classic size ladder, rounded-rect with margin baked in.
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points).png" : "icon_\(points)@2x.png"
    render(pixelSize: points * scale, rounded: true, to: macSet.appendingPathComponent(name))
}
