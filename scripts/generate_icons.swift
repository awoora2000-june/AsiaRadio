import AppKit
import CoreText
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

let sizes: [(String, Int)] = [
    ("icon-20@2x.png", 40),
    ("icon-20@3x.png", 60),
    ("icon-29@2x.png", 58),
    ("icon-29@3x.png", 87),
    ("icon-40@2x.png", 80),
    ("icon-40@3x.png", 120),
    ("icon-60@2x.png", 120),
    ("icon-60@3x.png", 180),
    ("icon-1024.png", 1024)
]

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)

    // Background gradient (dark, premium).
    let gradient = NSGradient(colors: [
        NSColor(red: 0.07, green: 0.06, blue: 0.18, alpha: 1),
        NSColor(red: 0.15, green: 0.07, blue: 0.34, alpha: 1),
        NSColor(red: 0.06, green: 0.34, blue: 0.50, alpha: 1)
    ])
    gradient?.draw(in: rect, angle: 90)

    let center = CGPoint(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2)

    // Soft aura ring behind monogram.
    let ringRadius = CGFloat(pixels) * 0.36
    let ringRect = NSRect(
        x: center.x - ringRadius,
        y: center.y - ringRadius * 0.98,
        width: ringRadius * 2,
        height: ringRadius * 2
    )
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = max(6, CGFloat(pixels) / 18)
    NSColor(red: 0.62, green: 0.85, blue: 1.0, alpha: 0.22).setStroke()
    ring.stroke()

    // Inner glow for depth.
    let glowRadius = CGFloat(pixels) * 0.30
    let glowRect = NSRect(
        x: center.x - glowRadius,
        y: center.y - glowRadius,
        width: glowRadius * 2,
        height: glowRadius * 2
    )
    let glowGradient = NSGradient(colors: [
        NSColor(red: 0.85, green: 0.96, blue: 1.0, alpha: 0.18),
        NSColor(red: 0.85, green: 0.96, blue: 1.0, alpha: 0.0)
    ])
    glowGradient?.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

    // Monogram: A is italic; R is upright with stem sheared to match A's left stroke.
    let monoSize = CGFloat(pixels) * 0.58
    let monoY = center.y - CGFloat(pixels) * 0.03
    let heavyFont = NSFont.systemFont(ofSize: monoSize, weight: .heavy)
    let italicFont = NSFontManager.shared.convert(heavyFont, toHaveTrait: .italicFontMask)
    let stemSlant = measureLeftStemSlant(for: italicFont)
    let shadow = NSShadow()
    shadow.shadowBlurRadius = CGFloat(pixels) * 0.035
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 0.01)

    func glyphPath(for letter: Character, font: NSFont) -> CGPath? {
        let ctFont = CTFontCreateWithFontDescriptor(font.fontDescriptor, font.pointSize, nil)
        var glyph: CGGlyph = 0
        var character = Array(String(letter).utf16)
        guard CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1) else { return nil }
        return CTFontCreatePathForGlyph(ctFont, glyph, nil)
    }

    func drawMonogramGlyph(
        _ letter: Character,
        font: NSFont,
        xOffset: CGFloat,
        color: NSColor,
        shear: CGFloat = 0
    ) {
        guard let path = glyphPath(for: letter, font: font) else { return }
        let bounds = path.boundingBox
        let targetCenter = CGPoint(x: center.x + xOffset, y: monoY)
        let offset = CGPoint(
            x: targetCenter.x - bounds.midX,
            y: targetCenter.y - bounds.midY
        )

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        if let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: offset.x, y: offset.y)
            if shear != 0 {
                let pivot = CGPoint(x: bounds.minX, y: bounds.midY)
                context.translateBy(x: pivot.x, y: pivot.y)
                context.concatenate(CGAffineTransform(a: 1, b: 0, c: shear, d: 1, tx: 0, ty: 0))
                context.translateBy(x: -pivot.x, y: -pivot.y)
            }
            context.addPath(path)
            context.setFillColor(color.cgColor)
            context.fillPath()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    drawMonogramGlyph(
        "A",
        font: italicFont,
        xOffset: -CGFloat(pixels) * 0.06,
        color: NSColor(white: 1.0, alpha: 0.92)
    )
    drawMonogramGlyph(
        "R",
        font: heavyFont,
        xOffset: CGFloat(pixels) * 0.07,
        color: NSColor(red: 0.40, green: 0.95, blue: 0.86, alpha: 0.92),
        shear: stemSlant
    )

    // Bottom label text (only for larger sizes for crispness).
    if pixels >= 120 {
        let label = "Auradio"
        let labelFont = NSFont.systemFont(ofSize: CGFloat(pixels) * 0.17, weight: .semibold)
        let labelShadow = NSShadow()
        labelShadow.shadowBlurRadius = CGFloat(pixels) * 0.02
        labelShadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        labelShadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 0.006)

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor(white: 1.0, alpha: 0.92),
            .shadow: labelShadow,
            .kern: CGFloat(pixels) * 0.01
        ]
        let text = NSAttributedString(string: label, attributes: labelAttributes)
        let tSize = text.size()
        let y = CGFloat(pixels) * 0.10 - tSize.height / 2
        text.draw(at: CGPoint(x: center.x - tSize.width / 2, y: y))
    }

    // Subtle highlight card to give depth.
    let inset = CGFloat(pixels) * 0.11
    let card = NSBezierPath(
        roundedRect: rect.insetBy(dx: inset, dy: inset),
        xRadius: CGFloat(pixels) * 0.18,
        yRadius: CGFloat(pixels) * 0.18
    )
    NSColor(white: 1, alpha: 0.05).setFill()
    card.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func measureLeftStemSlant(for font: NSFont) -> CGFloat {
    let ctFont = CTFontCreateWithFontDescriptor(font.fontDescriptor, font.pointSize, nil)
    let angle = CTFontGetSlantAngle(ctFont)
    let slant = tan(angle)
    guard slant.isFinite, slant > 0.05, slant < 0.6 else { return 0.21 }
    return slant
}

for (name, size) in sizes {
    let rep = drawIcon(pixels: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to create \(name)\n", stderr)
        exit(1)
    }
    try data.write(to: outDir.appendingPathComponent(name))
}

print("Icons generated in \(outDir.path)")
