import SwiftUI
import CoreGraphics

// MARK: - Colour <-> hex (the on-disk representation of a palette stop)

extension Color {
    init?(hex: String?) {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
        self = Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    /// `rrggbb`, sRGB, no leading `#` — matches what `init(hex:)` reads back.
    var hexRGB: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let to255: (CGFloat) -> Int = { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "%02x%02x%02x",
                      to255(ns.redComponent), to255(ns.greenComponent), to255(ns.blueComponent))
    }
}

// MARK: - The serialisable half of a Look

/// Everything about a `Look` except the source bitmap, in a form that survives a
/// round trip through `project.json`.
///
/// **Every field is optional on purpose.** A file written by an older build is
/// missing the newer keys, and one written by a newer build carries keys this
/// version doesn't know — with optionals both simply load, and anything absent falls
/// back to the `Look()` default in `init(recipe:source:)`. A non-optional field here
/// would make one missing key fail the whole decode.
struct LookRecipe: Codable, Equatable {
    var photoID: String?
    var baseName: String?
    var attribution: String?
    var attributionURL: String?

    var style: String?

    var blur: Double?
    var blurOffset: Double?
    var brightness: Double?
    var saturation: Double?
    var contrast: Double?
    var hue: Double?
    var dither: Double?

    var liquidColors: [String]?      // five sRGB hex stops, dark -> bright
    var liquidCount: Int?
    var liquidTime: Double?
    var liquidSeed: Double?
    var liquidScale: Double?
    var liquidTurb: Double?
    var liquidWave: Double?
    var liquidBias: Double?
    var liquidPoints: [CGPoint]?

    var mirrorLine: Double?
    var mirrorAmplitude: Double?
    var mirrorFrequency: Double?
    var mirrorPhase: Double?
    var mirrorIrregularity: Double?
    var mirrorHardness: Double?
    var mirrorDepth: Double?
    var mirrorSideFade: Double?

    var sliceCount: Double?
    var sliceAngle: Double?
    var sliceShift: Double?
    var sliceFan: Double?
    var sliceCurve: Double?
    var sliceSeed: Double?
}

extension Look {
    var recipe: LookRecipe {
        LookRecipe(
            photoID: photoID, baseName: baseName,
            attribution: attribution, attributionURL: attributionURL,
            style: style.rawValue,
            blur: blur, blurOffset: blurOffset, brightness: brightness,
            saturation: saturation, contrast: contrast, hue: hue, dither: dither,
            liquidColors: [liquidColor0, liquidColor1, liquidColor2, liquidColor3, liquidColor4].map(\.hexRGB),
            liquidCount: liquidCount, liquidTime: liquidTime, liquidSeed: liquidSeed,
            liquidScale: liquidScale, liquidTurb: liquidTurb, liquidWave: liquidWave,
            liquidBias: liquidBias, liquidPoints: liquidPoints,
            mirrorLine: mirrorLine, mirrorAmplitude: mirrorAmplitude,
            mirrorFrequency: mirrorFrequency, mirrorPhase: mirrorPhase,
            mirrorIrregularity: mirrorIrregularity, mirrorHardness: mirrorHardness,
            mirrorDepth: mirrorDepth, mirrorSideFade: mirrorSideFade,
            sliceCount: sliceCount, sliceAngle: sliceAngle, sliceShift: sliceShift,
            sliceFan: sliceFan, sliceCurve: sliceCurve, sliceSeed: sliceSeed
        )
    }

    /// Rebuilds a look from a stored recipe. Missing keys keep the `Look()` default,
    /// so a partial or older file still yields a usable look.
    init(recipe r: LookRecipe, source: CGImage?) {
        self.init()
        self.source = source
        photoID = r.photoID
        baseName = r.baseName
        attribution = r.attribution
        attributionURL = r.attributionURL

        if let s = r.style, let parsed = WallpaperStyle(rawValue: s) { style = parsed }

        blur = r.blur ?? blur
        blurOffset = r.blurOffset ?? blurOffset
        brightness = r.brightness ?? brightness
        saturation = r.saturation ?? saturation
        contrast = r.contrast ?? contrast
        hue = r.hue ?? hue
        dither = r.dither ?? dither

        if let hexes = r.liquidColors {
            for (i, hex) in hexes.prefix(5).enumerated() {
                if let c = Color(hex: hex) { setLiquidColor(i, c) }
            }
        }
        liquidCount = r.liquidCount ?? liquidCount
        liquidTime = r.liquidTime ?? liquidTime
        liquidSeed = r.liquidSeed ?? liquidSeed
        liquidScale = r.liquidScale ?? liquidScale
        liquidTurb = r.liquidTurb ?? liquidTurb
        liquidWave = r.liquidWave ?? liquidWave
        liquidBias = r.liquidBias ?? liquidBias
        // Only accept a full set of stops; a truncated array would desync the
        // points from the colour slots they sample.
        if let pts = r.liquidPoints, pts.count == liquidPoints.count { liquidPoints = pts }

        mirrorLine = r.mirrorLine ?? mirrorLine
        mirrorAmplitude = r.mirrorAmplitude ?? mirrorAmplitude
        mirrorFrequency = r.mirrorFrequency ?? mirrorFrequency
        mirrorPhase = r.mirrorPhase ?? mirrorPhase
        mirrorIrregularity = r.mirrorIrregularity ?? mirrorIrregularity
        mirrorHardness = r.mirrorHardness ?? mirrorHardness
        mirrorDepth = r.mirrorDepth ?? mirrorDepth
        mirrorSideFade = r.mirrorSideFade ?? mirrorSideFade

        sliceCount = r.sliceCount ?? sliceCount
        sliceAngle = r.sliceAngle ?? sliceAngle
        sliceShift = r.sliceShift ?? sliceShift
        sliceFan = r.sliceFan ?? sliceFan
        sliceCurve = r.sliceCurve ?? sliceCurve
        sliceSeed = r.sliceSeed ?? sliceSeed
    }
}
