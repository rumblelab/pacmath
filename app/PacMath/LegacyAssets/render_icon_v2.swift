import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreText

// PacMath app icon — v2 (post-Apple-rejection redesign).
//
// History: v1 was a yellow circle with a wedge mouth (Pac-Man silhouette) and
// got rejected under App Store guideline 4.1(a) Copycats. v2 keeps Chompy
// recognizable but breaks the trademark read by:
//   1. Honey-gold body (#F7B733) instead of Pac-Man yellow (#FFD700)
//   2. Two eyes — Pac-Man has none
//   3. No wedge mouth visible (only top half of head shows)
//   4. Composed behind a flashcard with "6+7" so the icon reads as Education
//
// Usage:
//   swift app/PacMath/LegacyAssets/render_icon_v2.swift <output-dir>
// then copy the result over app/PacMath/Assets.xcassets/AppIcon.appiconset/pacmath-icon.png

let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rad(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

let bgDeep   = CGColor(srgbRed: 23/255,  green: 0/255,   blue: 66/255,  alpha: 1)
let bgBase   = CGColor(srgbRed: 33/255,  green: 0/255,   blue: 93/255,  alpha: 1)
let bgLift   = CGColor(srgbRed: 56/255,  green: 16/255,  blue: 128/255, alpha: 1)
let honey    = CGColor(srgbRed: 247/255, green: 183/255, blue: 51/255,  alpha: 1)
let white    = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let cardInk  = CGColor(srgbRed: 33/255,  green: 0/255,   blue: 93/255,  alpha: 1)

func makeContext() -> CGContext {
    CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
}

func drawBackground(_ ctx: CGContext) {
    let g = CGGradient(
        colorsSpace: cs,
        colors: [bgLift, bgBase, bgDeep] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
}

func drawText(_ ctx: CGContext, text: String, fontName: String, pt: CGFloat, color: CGColor, at point: CGPoint, kern: CGFloat = 0) {
    let font = CTFontCreateWithName(fontName as CFString, pt, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTKernAttributeName as String): kern
    ]
    let attr = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attr)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(
        x: point.x - bounds.width/2 - bounds.minX,
        y: point.y - bounds.height/2 - bounds.minY
    )
    CTLineDraw(line, ctx)
}

// Chompy peeking up from behind the flashcard. Everything below `clipY` is
// hidden so only the top of the head shows above the card.
func drawPeekingChompy(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                      clipY: CGFloat, bodyColor: CGColor, lookDeg: CGFloat) {
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: clipY, width: size, height: size - clipY))

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
    ctx.setFillColor(bodyColor)
    ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius*2, height: radius*2))
    ctx.restoreGState()

    let eyeR = radius * 0.22
    let eyeSpacing = radius * 0.42
    let eyeY = center.y + radius * 0.28  // Y-up: upper part of head
    let eyeL = CGPoint(x: center.x - eyeSpacing, y: eyeY)
    let eyeR_p = CGPoint(x: center.x + eyeSpacing, y: eyeY)

    ctx.setFillColor(white)
    ctx.fillEllipse(in: CGRect(x: eyeL.x - eyeR, y: eyeL.y - eyeR, width: eyeR*2, height: eyeR*2))
    ctx.fillEllipse(in: CGRect(x: eyeR_p.x - eyeR, y: eyeR_p.y - eyeR, width: eyeR*2, height: eyeR*2))

    let pupilR = eyeR * 0.55
    let shift = eyeR * 0.35
    let dx = cos(rad(lookDeg)) * shift
    let dy = sin(rad(lookDeg)) * shift
    ctx.setFillColor(bgDeep)
    ctx.fillEllipse(in: CGRect(x: eyeL.x + dx - pupilR, y: eyeL.y + dy - pupilR, width: pupilR*2, height: pupilR*2))
    ctx.fillEllipse(in: CGRect(x: eyeR_p.x + dx - pupilR, y: eyeR_p.y + dy - pupilR, width: pupilR*2, height: pupilR*2))

    let hiR = pupilR * 0.35
    ctx.setFillColor(white)
    ctx.fillEllipse(in: CGRect(x: eyeL.x + dx - hiR*0.2, y: eyeL.y + dy + hiR*0.4, width: hiR*2, height: hiR*2))
    ctx.fillEllipse(in: CGRect(x: eyeR_p.x + dx - hiR*0.2, y: eyeR_p.y + dy + hiR*0.4, width: hiR*2, height: hiR*2))

    ctx.restoreGState()
}

func drawFlashcard(_ ctx: CGContext, rect: CGRect, equation: String, equationPt: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 50,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.setFillColor(white)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 72, cornerHeight: 72, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    drawText(ctx, text: equation, fontName: "Menlo-Bold", pt: equationPt,
             color: cardInk, at: CGPoint(x: rect.midX, y: rect.midY), kern: -6)
}

func render(outPath: String) {
    let ctx = makeContext()
    drawBackground(ctx)

    let cardW = size * 0.72
    let cardH = size * 0.44
    let cardX = (size - cardW) / 2
    let cardY = size * 0.14
    let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
    let cardTop = cardY + cardH

    let chompyR = size * 0.18
    let chompyCenter = CGPoint(x: size/2, y: cardTop - chompyR * 0.15)

    drawPeekingChompy(ctx, center: chompyCenter, radius: chompyR,
                      clipY: cardTop, bodyColor: honey, lookDeg: 100)
    drawFlashcard(ctx, rect: cardRect, equation: "6+7", equationPt: 340)

    let cgImage = ctx.makeImage()!
    let url = URL(fileURLWithPath: outPath)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cgImage, nil)
    _ = CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
render(outPath: "\(outDir)/pacmath-icon.png")
print("rendered v2 icon to \(outDir)/pacmath-icon.png")
