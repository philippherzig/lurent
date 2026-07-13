import CoreImage
import CoreGraphics

/// Folds the LOWER band of a (blurred) image onto itself across an adjustable
/// curved (sine) line. The line can be 100% hard; the fold dissolves toward the
/// sides. The upper part is never duplicated — the lower zone is mirrored in
/// place (`y' = curveY - y`), so a genuine colour contrast appears at the seam.
enum MirrorProcessor {

    struct Settings {
        var line: Double = 0.52        // 0…1 position of the fold line (height)
        var amplitude: Double = 0.05   // wave height as fraction of image height
        var frequency: Double = 0.75   // base waves across the width (lower = longer)
        var phase: Double = 1.0        // seed: shifts the wave / reshapes the irregular curve
        var irregular: Double = 0.6    // 0 = pure sine, 1 = organic (overlaid octaves)
        var hardness: Double = 1.0     // 0…1, 1 = razor-sharp seam in the centre
        var depth: Double = 0.35       // 0…1, how much darker the folded part is
        var sideFade: Double = 0.5     // 0…1, how much the SEAM softens toward the sides
    }

    // The lower area is ALWAYS fully folded; only the seam width varies across x
    // (hard in the centre, softer at the sides). No original leaks through.
    //
    // The fold line is an "organic" wave: a base sine plus two octaves at
    // NON-integer frequency ratios (1.73×, 2.61×) with offset phases, so the curve
    // is long yet never obviously repeats. `irregular` blends from the pure sine
    // (0) to the full organic sum (1); `phase` seeds distinct curve shapes.
    private static let kernel = CIKernel(source: """
    kernel vec4 mirror(sampler img, float baseLine, float amp, float freq, float phase,
                       float irregular, float hwMin, float hwMax, float dark, float w, float h) {
        vec2 dc = destCoord();
        float nx = dc.x / w;
        float kk = freq * 6.2831853;
        float base = sin(kk * nx + phase);
        float o1 = sin(kk * 1.73 * nx + phase * 1.7 + 1.3);
        float o2 = sin(kk * 2.61 * nx + phase * 0.9 + 4.1);
        float organic = (base + 0.5 * o1 + 0.28 * o2) / 1.78;
        float wave = mix(base, organic, irregular);
        float curveY = baseLine + amp*h*wave;
        vec4 orig = sample(img, samplerCoord(img));
        vec4 fold = sample(img, samplerTransform(img, vec2(dc.x, curveY - dc.y)));
        fold.rgb *= dark;
        float sharp = sin(3.14159265 * clamp(nx, 0.0, 1.0));  // 1 centre -> 0 sides
        float hw = mix(hwMax, hwMin, sharp);                  // seam half-width in px
        float below = smoothstep(-hw, hw, curveY - dc.y);     // 1 below line -> 0 above
        return mix(orig, fold, below);
    }
    """)!

    static func apply(to image: CIImage, size: CGSize, settings s: Settings) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let h = size.height
        let baseLine = s.line * h
        let hwMin = max(0.5, (1 - s.hardness) * 0.02 * h)     // razor at hardness 1
        let hwMax = max(hwMin, s.sideFade * 0.18 * h)         // softer seam toward the sides
        let dark = 1 - s.depth * 0.6
        let clamped = image.clampedToExtent()
        return kernel.apply(extent: rect, roiCallback: { _, _ in rect },
                            arguments: [clamped, baseLine, s.amplitude, s.frequency, s.phase,
                                        s.irregular, hwMin, hwMax, dark, size.width, h]) ?? image
    }
}
