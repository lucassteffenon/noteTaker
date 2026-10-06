// Draws the app icon: sound-wave bars turning into lines of text, with an AI sparkle.
// Usage: swift scripts/generate_icon.swift <output.png>
import AppKit
import CoreGraphics

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

// Opaque RGB (no alpha channel), as App Store icons require.
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Background: indigo to violet diagonal gradient. CoreGraphics' origin is bottom-left.
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [color(0x4F46E5), color(0x7C3AED)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: []
)

func capsule(x: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat, fill: CGColor) {
    let rect = CGRect(x: x, y: centerY - height / 2, width: width, height: height)
    let radius = min(width, height) / 2
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(fill)
    context.fillPath()
}

let center: CGFloat = 420 // below the canvas middle, so bars + sparkles are optically centered
let thickness: CGFloat = 46

// Left: sound-wave bars.
let barHeights: [CGFloat] = [170, 340, 250, 130]
for (index, height) in barHeights.enumerated() {
    capsule(x: 196 + CGFloat(index) * 74, centerY: center, width: thickness, height: height, fill: color(0xFFFFFF))
}

// Right: lines of notes, top to bottom.
let lineWidths: [CGFloat] = [300, 240, 300, 170]
let lineSpacing: CGFloat = 82
let firstLineY = center + lineSpacing * 1.5
for (index, width) in lineWidths.enumerated() {
    capsule(
        x: 528, centerY: firstLineY - CGFloat(index) * lineSpacing,
        width: width, height: thickness, fill: color(0xFFFFFF, 0.88)
    )
}

// Four-point sparkle (the AI summary) above the notes.
func sparkle(cx: CGFloat, cy: CGFloat, radius: CGFloat) {
    let mid = CGPoint(x: cx, y: cy)
    context.move(to: CGPoint(x: cx, y: cy + radius))
    context.addQuadCurve(to: CGPoint(x: cx + radius, y: cy), control: mid)
    context.addQuadCurve(to: CGPoint(x: cx, y: cy - radius), control: mid)
    context.addQuadCurve(to: CGPoint(x: cx - radius, y: cy), control: mid)
    context.addQuadCurve(to: CGPoint(x: cx, y: cy + radius), control: mid)
    context.setFillColor(color(0xFDE68A))
    context.fillPath()
}
sparkle(cx: 800, cy: 698, radius: 78)
sparkle(cx: 878, cy: 598, radius: 34)

let image = context.makeImage()!
let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
