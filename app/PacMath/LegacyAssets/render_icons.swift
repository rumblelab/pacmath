import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rad(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

struct FoodDot {
    let extraDistance: CGFloat
    let radiusScale: CGFloat
}

func renderIcon(
    outPath: String,
    bgMode: String = "gradient",
    chompyCx: CGFloat = 0.44,
    chompyCy: CGFloat = 0.50,
    chompyRadiusScale: CGFloat = 0.30,
    mouthAngleDeg: CGFloat = 58,
    mouthFacingDeg: CGFloat = 0,
    foodDots: [FoodDot] = [FoodDot(extraDistance: 0.085, radiusScale: 0.058)],
    foodColor: String = "green",
    mathWatermark: Bool = false
) {
    let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!

    let bgDeep = CGColor(srgbRed: 23/255,  green: 0/255,   blue: 66/255,  alpha: 1)
    let bgBase = CGColor(srgbRed: 33/255,  green: 0/255,   blue: 93/255,  alpha: 1)
    let bgLift = CGColor(srgbRed: 56/255,  green: 16/255,  blue: 128/255, alpha: 1)

    // --- Background ---
    switch bgMode {
    case "gradient":
        let g = CGGradient(
            colorsSpace: cs,
            colors: [bgLift, bgBase, bgDeep] as CFArray,
            locations: [0, 0.55, 1]
        )!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
    case "solid":
        ctx.setFillColor(bgBase)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    case "radial":
        ctx.setFillColor(bgDeep)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let radial = CGGradient(
            colorsSpace: cs,
            colors: [bgLift, bgDeep] as CFArray,
            locations: [0, 1]
        )!
        let center = CGPoint(x: size * chompyCx, y: size * chompyCy)
        ctx.drawRadialGradient(radial, startCenter: center, startRadius: 0, endCenter: center, endRadius: size * 0.72, options: [])
    default: break
    }

    // Subtle glow behind Chompy
    let glowCenter = CGPoint(x: size * chompyCx, y: size * chompyCy)
    let glowColors = [
        CGColor(srgbRed: 96/255, green: 40/255, blue: 180/255, alpha: 0.55),
        CGColor(srgbRed: 33/255, green: 0/255,  blue: 93/255,  alpha: 0.0)
    ]
    let glow = CGGradient(colorsSpace: cs, colors: glowColors as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: size * 0.55, options: [])

    // --- Math watermark (faint + − × ÷ shapes) ---
    if mathWatermark {
        ctx.saveGState()
        ctx.setAlpha(0.09)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let positions: [(CGFloat, CGFloat, String)] = [
            (0.14, 0.84, "+"),
            (0.86, 0.86, "×"),
            (0.88, 0.16, "÷"),
            (0.12, 0.16, "−"),
            (0.88, 0.50, "+"),
            (0.14, 0.50, "×")
        ]
        let symSize: CGFloat = 110
        let thickness: CGFloat = 22
        for (nx, ny, sym) in positions {
            let cx = size * nx
            let cy = size * ny
            switch sym {
            case "+":
                ctx.fill(CGRect(x: cx - symSize/2, y: cy - thickness/2, width: symSize, height: thickness))
                ctx.fill(CGRect(x: cx - thickness/2, y: cy - symSize/2, width: thickness, height: symSize))
            case "−":
                ctx.fill(CGRect(x: cx - symSize/2, y: cy - thickness/2, width: symSize, height: thickness))
            case "×":
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: .pi / 4)
                ctx.fill(CGRect(x: -symSize/2, y: -thickness/2, width: symSize, height: thickness))
                ctx.fill(CGRect(x: -thickness/2, y: -symSize/2, width: thickness, height: symSize))
                ctx.restoreGState()
            case "÷":
                ctx.fill(CGRect(x: cx - symSize/2, y: cy - thickness/2, width: symSize, height: thickness))
                let dotR: CGFloat = thickness * 0.9
                ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy + symSize/4, width: dotR*2, height: dotR*2))
                ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - symSize/4 - dotR*2, width: dotR*2, height: dotR*2))
            default: break
            }
        }
        ctx.restoreGState()
    }

    // --- Chompy ---
    let chompyYellow = CGColor(srgbRed: 255/255, green: 215/255, blue: 0/255, alpha: 1)
    let chompyRadius = size * chompyRadiusScale
    let chompyCenter = CGPoint(x: size * chompyCx, y: size * chompyCy)
    let halfMouth = mouthAngleDeg / 2
    let mouthStart = mouthFacingDeg + halfMouth
    let mouthEnd = mouthFacingDeg + 360 - halfMouth

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -22),
        blur: 44,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
    )
    ctx.setFillColor(chompyYellow)
    ctx.beginPath()
    ctx.move(to: chompyCenter)
    ctx.addArc(
        center: chompyCenter,
        radius: chompyRadius,
        startAngle: rad(mouthStart),
        endAngle: rad(mouthEnd),
        clockwise: false
    )
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()

    // --- Food dots ---
    let foodColorCG: CGColor
    switch foodColor {
    case "salmon": foodColorCG = CGColor(srgbRed: 250/255, green: 128/255, blue: 114/255, alpha: 1)
    case "yellow": foodColorCG = CGColor(srgbRed: 255/255, green: 215/255, blue: 0/255, alpha: 1)
    default:       foodColorCG = CGColor(srgbRed: 123/255, green: 224/255, blue: 146/255, alpha: 1)
    }
    ctx.setFillColor(foodColorCG)

    for dot in foodDots {
        let dotDist = chompyRadius + dot.extraDistance * size
        let dotCenter = CGPoint(
            x: chompyCenter.x + cos(rad(mouthFacingDeg)) * dotDist,
            y: chompyCenter.y + sin(rad(mouthFacingDeg)) * dotDist
        )
        let r = dot.radiusScale * size
        ctx.fillEllipse(in: CGRect(x: dotCenter.x - r, y: dotCenter.y - r, width: r*2, height: r*2))
    }

    // --- Export ---
    let cgImage = ctx.makeImage()!
    let url = URL(fileURLWithPath: outPath)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cgImage, nil)
    _ = CGImageDestinationFinalize(dest)
}

// ─────────────────────────────────────────────────────────────
// Variants
// ─────────────────────────────────────────────────────────────

let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// 01 — v2 baseline: Chompy + single food dot
renderIcon(outPath: "\(outDir)/01-baseline.png")

// 02 — solo centered, no food dot, bigger Chompy
renderIcon(
    outPath: "\(outDir)/02-solo-centered.png",
    chompyCx: 0.50,
    chompyRadiusScale: 0.33,
    foodDots: []
)

// 03 — food-dot trail (3 dots in front)
renderIcon(
    outPath: "\(outDir)/03-trail.png",
    chompyCx: 0.33,
    chompyRadiusScale: 0.28,
    foodDots: [
        FoodDot(extraDistance: 0.07, radiusScale: 0.048),
        FoodDot(extraDistance: 0.18, radiusScale: 0.048),
        FoodDot(extraDistance: 0.29, radiusScale: 0.048)
    ]
)

// 04 — mouth pointing up (vertical stance, visually bottom half)
renderIcon(
    outPath: "\(outDir)/04-mouth-up.png",
    chompyCx: 0.50,
    chompyCy: 0.40,
    chompyRadiusScale: 0.30,
    mouthFacingDeg: 90,
    foodDots: [FoodDot(extraDistance: 0.09, radiusScale: 0.060)]
)

// 05 — math symbol watermark background
renderIcon(
    outPath: "\(outDir)/05-math-watermark.png",
    mathWatermark: true
)

// 06 — radial burst background (glow radiates from Chompy)
renderIcon(
    outPath: "\(outDir)/06-radial-burst.png",
    bgMode: "radial"
)

// 07 — diagonal gaze (mouth 25° up-right, Chompy bottom-left)
renderIcon(
    outPath: "\(outDir)/07-diagonal-gaze.png",
    chompyCx: 0.38,
    chompyCy: 0.42,
    mouthFacingDeg: 25,
    foodDots: [FoodDot(extraDistance: 0.10, radiusScale: 0.060)]
)

// 08 — big centered, pure hero shot
renderIcon(
    outPath: "\(outDir)/08-big-centered.png",
    chompyCx: 0.50,
    chompyCy: 0.50,
    chompyRadiusScale: 0.38,
    foodDots: []
)

// 09 — salmon food dot accent
renderIcon(
    outPath: "\(outDir)/09-salmon-dot.png",
    foodColor: "salmon"
)

// 10 — trail + math watermark combo
renderIcon(
    outPath: "\(outDir)/10-trail-math.png",
    chompyCx: 0.35,
    chompyRadiusScale: 0.28,
    foodDots: [
        FoodDot(extraDistance: 0.08, radiusScale: 0.048),
        FoodDot(extraDistance: 0.20, radiusScale: 0.048)
    ],
    mathWatermark: true
)

print("rendered 10 variants to \(outDir)")
