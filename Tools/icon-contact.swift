import AppKit
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Contact sheet for the app icon, rendered with the app's own pipeline.
//
// Each candidate is two layers, the way Icon Composer wants them: a soft Liquid
// gradient as the background, and an inset panel of the *same* gradient run through
// one of the photo effects as the foreground. That literally shows what Lurent does —
// a field, and a transformed piece of it — and gives macOS 26 two surfaces to light
// instead of one flat image.
//
// Top-level code needs the filename `main.swift` when compiled with other sources:
//   cp Tools/icon-contact.swift /tmp/main.swift
//   swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macos26.0 \
//     /tmp/main.swift Sources/BlurProcessor.swift Sources/LiquidProcessor.swift \
//     Sources/SliceProcessor.swift Sources/MirrorProcessor.swift -o /tmp/icon-contact
//   /tmp/icon-contact <out.png>

let args = CommandLine.arguments
guard args.count >= 2 else { fputs("usage: icon-contact <out.png> [sizes]\n", stderr); exit(2) }
let outPath = args[1]
// "sizes" renders the shortlist at the sizes that actually decide an icon: a Dock
// tile is 128 at most and the menu bar / Finder list is 32. A mark that only works
// at 1024 is not an app icon.
let sizeMode = args.count > 2 && args[2] == "sizes"

// MARK: - Palettes
//
// Soft, light and low-chroma on purpose: the icon should promise what the app
// actually produces. The current icon is full-saturation violet/magenta/orange,
// which looks like a different app's output.

struct Palette {
    let name: String
    let colors: [CIColor]
}

func rgb(_ r: Double, _ g: Double, _ b: Double) -> CIColor { CIColor(red: r, green: g, blue: b) }

// Light half and dark half of the same family. Enough chroma to hold presence at
// 32 pt in the Dock — the first pass was pastel to the point of vanishing.
let palettes: [Palette] = [
    Palette(name: "Dusk", colors: [
        rgb(0.99, 0.83, 0.72), rgb(0.96, 0.66, 0.71), rgb(0.72, 0.61, 0.90),
    ]),
    Palette(name: "Tide", colors: [
        rgb(0.80, 0.90, 0.96), rgb(0.55, 0.70, 0.93), rgb(0.42, 0.45, 0.85),
    ]),
    Palette(name: "Ember", colors: [
        rgb(1.00, 0.86, 0.70), rgb(0.98, 0.62, 0.50), rgb(0.80, 0.36, 0.55),
    ]),
    Palette(name: "Moss", colors: [
        rgb(0.88, 0.93, 0.83), rgb(0.62, 0.80, 0.74), rgb(0.35, 0.55, 0.62),
    ]),
    // Two-tone on purpose: a third hue puts a stray streak in the dark half that
    // survives every calming attempt and reads as a smudge at 32 pt.
    Palette(name: "Warm", colors: [
        rgb(1.00, 0.88, 0.79), rgb(0.91, 0.47, 0.55),
    ]),
    Palette(name: "Violet", colors: [
        rgb(0.92, 0.88, 0.98), rgb(0.51, 0.42, 0.82),
    ]),
]

/// How high the fold sits and how much it waves. The motif is always the same idea:
/// one field, split into a light face and a dark face by a soft curve — the two
/// appearances a single Lurent wallpaper carries.
enum Motif: String, CaseIterable {
    case low   = "Low fold"
    case mid   = "Mid fold"
    case steep = "Steep fold"

    var line: Double { self == .low ? 0.62 : (self == .mid ? 0.52 : 0.44) }
    var amplitude: Double { self == .steep ? 0.16 : 0.11 }
    var tilt: Double { self == .steep ? 0.30 : 0.16 }
}

// MARK: - Rendering

let cell = 320                       // per-candidate preview size
let inset = 0.17                     // how far the foreground panel sits inside

func gradient(_ p: Palette, size: CGSize, seed: Double) -> CGImage? {
    var s = LiquidProcessor.Settings(colors: p.colors)
    s.count = p.colors.count
    s.time = 6.0
    s.seed = seed
    s.scale = 0.72                   // wide, calm field rather than churn
    s.turbAmp = 0.28
    s.waveFreq = 0.8
    s.saturation = 1.02
    s.contrast = 1.0
    s.dither = 0.04
    return LiquidProcessor.render(size: size, settings: s)
}

/// The dark face: the same gradient, deepened, so both halves are visibly one family.
func darkFace(_ p: Palette, size: CGSize, seed: Double) -> CGImage? {
    var s = LiquidProcessor.Settings(colors: p.colors)
    s.count = p.colors.count
    s.time = 6.0
    s.seed = seed
    s.scale = 0.62
    s.turbAmp = 0.10                // calm: at 32 pt churn reads as noise, not texture
    s.waveFreq = 0.6
    s.brightness = -0.34            // the "Dunkel" look the app gives a dark appearance
    s.saturation = 1.05
    s.contrast = 1.06
    s.dither = 0.04
    return LiquidProcessor.render(size: size, settings: s)
}

/// The fold: a soft wave across the frame, tilted, with a second harmonic so it reads
/// as organic rather than as a sine. Same shape language as the Mirror style.
func foldPath(_ m: Motif, side: Double) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    var x = 0.0
    while x <= side {
        let t = x / side
        let wave = sin(t * .pi * 1.15 + 0.6) * 0.62 + sin(t * .pi * 2.3 + 1.9) * 0.38
        let y = side * (1 - m.line) + wave * side * m.amplitude + (t - 0.5) * side * m.tilt
        path.addLine(to: CGPoint(x: x, y: y))
        x += 2
    }
    path.addLine(to: CGPoint(x: side, y: 0))
    path.closeSubpath()
    return path
}

/// Light field with the dark face folded over the lower part — the two appearances a
/// single Lurent wallpaper carries, in one mark.
func candidate(_ p: Palette, motif: Motif, side: Int, seed: Double) -> CGImage? {
    let size = CGSize(width: side, height: side)
    guard let bg = gradient(p, size: size, seed: seed),
          let dark = darkFace(p, size: size, seed: seed) else { return nil }

    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let full = CGRect(x: 0, y: 0, width: side, height: side)
    ctx.draw(bg, in: full)

    let d = Double(side)
    let fold = foldPath(motif, side: d)

    ctx.saveGState()
    ctx.addPath(fold)
    ctx.clip()
    ctx.draw(dark, in: full)
    ctx.restoreGState()

    // A hairline of light along the fold — the edge the system's specular pass picks up.
    ctx.saveGState()
    ctx.addPath(fold)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.42))
    ctx.setLineWidth(d * 0.007)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

// MARK: - Size check

if sizeMode {
    let shortlist: [(Palette, Motif, Double)] = [
        (palettes[4], .mid, 3.0),   // Warm   — brand colours, two-tone
        (palettes[5], .mid, 4.0),   // Violet — brand colours, two-tone
        (palettes[1], .mid, 5.0),   // Tide   — best legibility so far
        (palettes[0], .mid, 3.0),   // Dusk   — the three-hue original
    ]
    let sizes = [128, 64, 32]
    let rowH: CGFloat = 150
    let w = 460, h = Int(rowH) * shortlist.count + 20
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)

    for (i, item) in shortlist.enumerated() {
        let y = CGFloat(h) - CGFloat(i + 1) * rowH
        (item.0.name as NSString).draw(at: NSPoint(x: 14, y: y + 60), withAttributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
        var x: CGFloat = 110
        for side in sizes {
            // Render large and downsample, exactly how the system scales the asset.
            guard let img = candidate(item.0, motif: item.1, side: 512, seed: item.2) else { continue }
            let r = CGRect(x: x, y: y + 40, width: CGFloat(side), height: CGFloat(side))
            c.saveGState()
            c.interpolationQuality = .high
            let sq = CGPath(roundedRect: r, cornerWidth: CGFloat(side) * 0.225,
                            cornerHeight: CGFloat(side) * 0.225, transform: nil)
            c.addPath(sq); c.clip()
            c.draw(img, in: r)
            c.restoreGState()
            x += CGFloat(side) + 26
        }
    }
    NSGraphicsContext.current = nil
    if let out = c.makeImage(),
       let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(outPath)  (size check)")
    }
    exit(0)
}

// MARK: - Sheet

let cols = Motif.allCases.count
let rows = palettes.count
let label: CGFloat = 34
let pad: CGFloat = 16
let sheetW = Int(CGFloat(cols) * (CGFloat(cell) + pad) + pad)
let sheetH = Int(CGFloat(rows) * (CGFloat(cell) + pad + label) + pad)

let sheet = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8,
                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

let ns = NSGraphicsContext(cgContext: sheet, flipped: false)
NSGraphicsContext.current = ns

for (r, p) in palettes.enumerated() {
    for (c, motif) in Motif.allCases.enumerated() {
        let x = pad + CGFloat(c) * (CGFloat(cell) + pad)
        let y = CGFloat(sheetH) - CGFloat(r + 1) * (CGFloat(cell) + pad + label)
        guard let img = candidate(p, motif: motif, side: cell, seed: Double(r) * 2.0 + 3.0) else { continue }

        // Rounded like macOS 26 masks it, so the judgement matches what ships.
        sheet.saveGState()
        let rect = CGRect(x: x, y: y + label, width: CGFloat(cell), height: CGFloat(cell))
        let squircle = CGPath(roundedRect: rect, cornerWidth: CGFloat(cell) * 0.225,
                              cornerHeight: CGFloat(cell) * 0.225, transform: nil)
        sheet.addPath(squircle)
        sheet.clip()
        sheet.draw(img, in: rect)
        sheet.restoreGState()

        let text = "\(p.name) · \(motif.rawValue)" as NSString
        text.draw(at: NSPoint(x: x + 4, y: y + 8), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ])
    }
}
NSGraphicsContext.current = nil

guard let out = sheet.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("cannot write \(outPath)\n", stderr); exit(1)
}
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { fputs("finalize failed\n", stderr); exit(1) }
print("wrote \(outPath)  (\(sheetW)×\(sheetH))")
