import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Usage:
//   swift caption.swift <input.png> <output.png> bare
//   swift caption.swift <input.png> <output.png> top     "<headline>" ["<subtitle>"]
//   swift caption.swift <input.png> <output.png> overlay <yFrac> "<headline>" ["<subtitle>"]
//
// Modes:
//   bare    — screenshot centered on a 1320×2868 canvas; no text.
//   top     — 440px caption band at top, screenshot fitted below. Legacy mode.
//   overlay — screenshot centered on canvas; caption drawn on top of it at
//             yFrac (0 = visual top of canvas, 1 = visual bottom). Use for
//             screens that have open negative space.
guard CommandLine.arguments.count >= 4 else {
    print("usage:")
    print("  swift caption.swift <input.png> <output.png> bare")
    print("  swift caption.swift <input.png> <output.png> top \"<headline>\" [\"<subtitle>\"]")
    print("  swift caption.swift <input.png> <output.png> overlay <yFrac> \"<headline>\" [\"<subtitle>\"]")
    exit(1)
}
let inputPath  = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let mode       = CommandLine.arguments[3]

// Canvas: exact 6.5" iPhone App Store size (matches native 1284x2778
// source screenshots and is the slot App Store Connect currently exposes
// for PacMath). Regenerate at 1320x2868 if a 6.9" slot appears later.
let canvasW: CGFloat = 1284
let canvasH: CGFloat = 2778

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil,
    width: Int(canvasW), height: Int(canvasH),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
) else {
    print("failed to create context")
    exit(1)
}

// --- Brand purple gradient background ---
let bgDeep = CGColor(srgbRed: 23/255,  green: 0/255,   blue: 66/255,  alpha: 1)
let bgBase = CGColor(srgbRed: 33/255,  green: 0/255,   blue: 93/255,  alpha: 1)
let bgLift = CGColor(srgbRed: 56/255,  green: 16/255,  blue: 128/255, alpha: 1)
let bg = CGGradient(colorsSpace: cs, colors: [bgLift, bgBase, bgDeep] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg,
    start: CGPoint(x: 0, y: canvasH),
    end:   CGPoint(x: 0, y: 0),
    options: []
)

// --- Load input screenshot ---
let inputURL = URL(fileURLWithPath: inputPath)
guard let src = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let shot = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("failed to load input: \(inputPath)")
    exit(1)
}
let imgW = CGFloat(shot.width)
let imgH = CGFloat(shot.height)

// --- Text helpers ---
// Monospaced Menlo matches Theme.mono in the app (SF Mono system monospaced).
func makeLine(_ text: String, fontSize: CGFloat, bold: Bool, color: CGColor) -> CTLine {
    let fontName = bold ? "Menlo-Bold" : "Menlo-Regular"
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTKernAttributeName as String): -0.5
    ]
    let attr = NSAttributedString(string: text, attributes: attrs)
    return CTLineCreateWithAttributedString(attr)
}

func drawCentered(_ line: CTLine, baselineY: CGFloat) {
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let w = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let xStart = (canvasW - w) / 2
    ctx.textMatrix = .identity
    ctx.textPosition = CGPoint(x: xStart, y: baselineY)
    CTLineDraw(line, ctx)
}

let white      = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let whiteMuted = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.72)

// --- Mode dispatch ---
switch mode {
case "bare":
    // Center screenshot on canvas, no text.
    let scale  = min(canvasW / imgW, canvasH / imgH)
    let scaledW = imgW * scale
    let scaledH = imgH * scale
    let dstX = (canvasW - scaledW) / 2
    let dstY = (canvasH - scaledH) / 2
    ctx.draw(shot, in: CGRect(x: dstX, y: dstY, width: scaledW, height: scaledH))

case "top":
    guard CommandLine.arguments.count >= 5 else {
        print("top mode requires: <input> <output> top \"<headline>\" [\"<subtitle>\"]")
        exit(1)
    }
    let headline = CommandLine.arguments[4]
    let subtitle = CommandLine.arguments.count >= 6 ? CommandLine.arguments[5] : ""

    let captionAreaH: CGFloat = 440
    let availH = canvasH - captionAreaH
    let scale  = min(canvasW / imgW, availH / imgH)
    let scaledW = imgW * scale
    let scaledH = imgH * scale
    let dstX = (canvasW - scaledW) / 2
    let dstY: CGFloat = 0
    ctx.draw(shot, in: CGRect(x: dstX, y: dstY, width: scaledW, height: scaledH))

    // Headline and subtitle in the top band. CG y grows upward, so canvasH-N
    // moves N pixels down from visual top.
    let headlineLine = makeLine(headline, fontSize: 90, bold: true, color: white)
    drawCentered(headlineLine, baselineY: canvasH - 230)

    if !subtitle.isEmpty {
        let subLine = makeLine(subtitle, fontSize: 40, bold: false, color: whiteMuted)
        drawCentered(subLine, baselineY: canvasH - 320)
    }

case "overlay":
    guard CommandLine.arguments.count >= 6,
          let yFrac = Double(CommandLine.arguments[4]) else {
        print("overlay mode requires: <input> <output> overlay <yFrac> \"<headline>\" [\"<subtitle>\"]")
        exit(1)
    }
    let headline = CommandLine.arguments[5]
    let subtitle = CommandLine.arguments.count >= 7 ? CommandLine.arguments[6] : ""

    // Center screenshot on canvas (gradient fills the margin).
    let scale  = min(canvasW / imgW, canvasH / imgH)
    let scaledW = imgW * scale
    let scaledH = imgH * scale
    let dstX = (canvasW - scaledW) / 2
    let dstY = (canvasH - scaledH) / 2
    ctx.draw(shot, in: CGRect(x: dstX, y: dstY, width: scaledW, height: scaledH))

    // yFrac is the visual position of the headline baseline from the top.
    // In CG coords, baseline = canvasH * (1 - yFrac).
    let headlineFontSize: CGFloat = 84
    let subtitleFontSize: CGFloat = 38
    let headlineBaseline = canvasH * (1 - CGFloat(yFrac))

    let headlineLine = makeLine(headline, fontSize: headlineFontSize, bold: true, color: white)
    drawCentered(headlineLine, baselineY: headlineBaseline)

    if !subtitle.isEmpty {
        // Subtitle sits one line below the headline (CG y-down = smaller value).
        let subLine = makeLine(subtitle, fontSize: subtitleFontSize, bold: false, color: whiteMuted)
        drawCentered(subLine, baselineY: headlineBaseline - headlineFontSize * 0.95)
    }

default:
    print("unknown mode: \(mode) — use bare | top | overlay")
    exit(1)
}

// --- Export PNG ---
guard let cgImage = ctx.makeImage() else {
    print("failed to make image")
    exit(1)
}
let outURL = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    print("failed to create destination")
    exit(1)
}
CGImageDestinationAddImage(dest, cgImage, nil)
if !CGImageDestinationFinalize(dest) {
    print("failed to write png")
    exit(1)
}
print("wrote \(outputPath)")
