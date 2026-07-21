import AppKit
import CoreImage
import CoreGraphics

// Contact sheet for calibrating SliceProcessor ("Lamellen"): renders a grid of the
// effect over a blurred sample photo across a parameter sweep, so the subjective knobs
// can be judged at a glance.
//
// Top-level code needs the filename `main.swift` when compiled with other sources, so
// build a copy under that name:
//   cp Tools/slice-contact.swift /tmp/main.swift
//   swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macos26.0 \
//     /tmp/main.swift Sources/BlurProcessor.swift Sources/SliceProcessor.swift -o /tmp/slice-contact
//   /tmp/slice-contact <sample.jpg> <out.png> [mode]
//
//   mode = "cs" → rows: count, cols: shift   (default)
//   mode = "ca" → rows: angle, cols: count
//   mode = "fc" → rows: fan,   cols: count
//   mode = "kf" → rows: curve, cols: fan

let args = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: slice-contact <in> <out> [cs|ca]\n", stderr); exit(2) }
let srcPath = args[1], outPath = args[2]
let mode = args.count > 3 ? args[3] : "cs"

guard let nsimg = NSImage(contentsOfFile: srcPath),
      let src = nsimg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("cannot load \(srcPath)\n", stderr); exit(1)
}

let ctx = CIContext(options: [.cacheIntermediates: false, .workingFormat: CIFormat.RGBAh])
let tileW = 330, tileH = 330   // square, like the app canvas
let padX = 66, padTop = 34, gap = 10

func tile(_ s: SliceProcessor.Settings) -> CGImage? {
    var bs = BlurProcessor.Settings(); bs.blur = 55; bs.saturation = 1.1; bs.contrast = 1.0
    let size = CGSize(width: tileW, height: tileH)
    guard let base = BlurProcessor.processedImage(source: src, targetSize: size, settings: bs) else { return nil }
    let out = SliceProcessor.apply(to: base, size: size, settings: s)
    return ctx.createCGImage(out, from: CGRect(origin: .zero, size: size))
}

let rows: [Double], cols: [Double], rowLabel: String, colLabel: String
if mode == "kf" {
    rows = [-1.0, -0.35, 0.35, 1.0]; cols = [0, 0.3, 0.65, 1.0]
    rowLabel = "curve"; colLabel = "fan"
} else if mode == "fc" {
    rows = [0, 0.25, 0.6, 1.0]; cols = [6, 12, 20, 32]
    rowLabel = "fan"; colLabel = "count"
} else if mode == "ca" {
    rows = [0, 0.35, 0.9, 1.571]; cols = [6, 12, 20, 32]
    rowLabel = "angle"; colLabel = "count"
} else {
    rows = [4, 8, 16, 28]; cols = [0.1, 0.3, 0.6, 1.0]
    rowLabel = "count"; colLabel = "shift"
}

let W = padX + cols.count * (tileW + gap)
let H = padTop + 22 + rows.count * (tileH + gap + 18)
let sheet = NSImage(size: NSSize(width: W, height: H))
sheet.lockFocusFlipped(true)
NSColor(white: 0.11, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

let head: [NSAttributedString.Key: Any] = [
    .foregroundColor: NSColor.white, .font: NSFont.boldSystemFont(ofSize: 13)]
let small: [NSAttributedString.Key: Any] = [
    .foregroundColor: NSColor(white: 0.75, alpha: 1), .font: NSFont.systemFont(ofSize: 11)]

("\(rowLabel) (↓)  ×  \(colLabel) (→)" as NSString).draw(at: NSPoint(x: 12, y: 8), withAttributes: head)

for (ci, c) in cols.enumerated() {
    let x = padX + ci * (tileW + gap)
    (String(format: "%@=%.2f", colLabel, c) as NSString).draw(at: NSPoint(x: x + 4, y: padTop), withAttributes: small)
}

for (ri, r) in rows.enumerated() {
    let y = padTop + 22 + ri * (tileH + gap + 18)
    (String(format: "%@=%.2f", rowLabel, r) as NSString).draw(at: NSPoint(x: 6, y: y + tileH / 2), withAttributes: small)
    for (ci, c) in cols.enumerated() {
        let x = padX + ci * (tileW + gap)
        var s = SliceProcessor.Settings()
        if mode == "kf"      { s.curve = r; s.fan = c; s.count = 14; s.shift = 0.4; s.angle = 0 }
        else if mode == "fc" { s.fan = r; s.count = c; s.shift = 0.4; s.angle = 0 }
        else if mode == "ca" { s.angle = r; s.count = c; s.shift = 0.4 }
        else                 { s.count = r; s.shift = c }
        if let cg = tile(s) {
            NSImage(cgImage: cg, size: NSSize(width: tileW, height: tileH))
                .draw(in: NSRect(x: x, y: y, width: tileW, height: tileH))
        }
    }
}

sheet.unlockFocus()
guard let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("encode failed\n", stderr); exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
fputs("wrote \(outPath)\n", stderr)
