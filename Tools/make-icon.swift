import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the Fence app icon at each size needed by the asset catalog.
// The mark is the same scope glyph the menu bar uses, so the app reads as one thing.

let outputDirectory = CommandLine.arguments[1]

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Apple-ish rounded square. 0.2235 of the side is close to the macOS squircle.
func squirclePath(in rect: CGRect) -> CGPath {
    let radius = rect.width * 0.2235
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: CGFloat) -> CGImage? {
    let scale = size / 1024.0
    guard let context = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)

    // The art sits inside a margin, the way macOS app icons do.
    let margin: CGFloat = 100 * scale
    let plate = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let path = squirclePath(in: plate)

    // Indigo gradient, keyed to the app's accent colour.
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            color(0.42, 0.50, 0.99),
            color(0.29, 0.34, 0.86),
            color(0.17, 0.19, 0.62),
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.midX, y: plate.maxY),
        end: CGPoint(x: plate.midX, y: plate.minY),
        options: []
    )

    // Soft highlight across the top edge, so the plate reads as a surface.
    let highlight = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [color(1, 1, 1, 0.26), color(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        highlight,
        start: CGPoint(x: plate.midX, y: plate.maxY),
        end: CGPoint(x: plate.midX, y: plate.midY + plate.height * 0.08),
        options: []
    )
    context.restoreGState()

    // Hairline edge for definition on light and dark backgrounds.
    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(color(0, 0, 0, 0.16))
    context.setLineWidth(max(1, 3 * scale))
    context.strokePath()
    context.restoreGState()

    // The scope mark: outer ring, inner ring, centre dot.
    let centre = CGPoint(x: plate.midX, y: plate.midY)
    context.setStrokeColor(color(1, 1, 1, 0.92))
    context.setLineCap(.round)

    let outerRadius = plate.width * 0.300
    context.setLineWidth(plate.width * 0.072)
    context.addArc(center: centre, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()

    let innerRadius = plate.width * 0.168
    context.setStrokeColor(color(1, 1, 1, 0.55))
    context.setLineWidth(plate.width * 0.044)
    context.addArc(center: centre, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()

    context.setFillColor(color(1, 1, 1, 1))
    let dotRadius = plate.width * 0.064
    context.addArc(center: centre, radius: dotRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.fillPath()

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        print("failed to create destination for \(url.lastPathComponent)")
        return
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

// (base point size, scale)
let variants: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

var manifest: [[String: String]] = []
for (base, scale) in variants {
    let pixels = base * scale
    guard let image = drawIcon(size: CGFloat(pixels)) else {
        print("render failed at \(pixels)")
        continue
    }
    let suffix = scale == 1 ? "" : "@\(scale)x"
    let name = "icon_\(base)x\(base)\(suffix).png"
    write(image, to: URL(fileURLWithPath: outputDirectory).appendingPathComponent(name))
    manifest.append([
        "filename": name,
        "idiom": "mac",
        "scale": "\(scale)x",
        "size": "\(base)x\(base)",
    ])
    print("wrote \(name) (\(pixels)px)")
}

// Rewrite Contents.json so the catalog points at the files we just made.
let contents: [String: Any] = [
    "images": manifest,
    "info": ["author": "xcode", "version": 1],
]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("Contents.json"))
print("wrote Contents.json")
