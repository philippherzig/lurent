import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Generates a "liquid gradient": a domain-warped turbulence field mapped onto a
/// multi-stop colour palette. Each frame (see `time`) is a finished still image;
/// scrubbing `time`/`seed` in the preview picks the moment to export.
///
/// The warp is an iterated `sin` folding of the coordinate field — the same idea
/// behind the flowing WebGL background on heart.zuerich — evaluated once per
/// pixel in a Core Image colour kernel. Colours are mixed in the linear working
/// space (like `FlowProcessor`), which keeps the mid-tones vivid instead of
/// muddy.
enum LiquidProcessor {

    struct Settings {
        var colors: [CIColor]        // up to 5 stops, ordered low → high value
        var count: Int = 5           // how many stops are active (2…5)
        var time: Double = 6.0       // frame to freeze (animation phase)
        var seed: Double = 3.0       // reshuffles the flow pattern
        var scale: Double = 1.25     // zoom into the field
        var turbAmp: Double = 0.9    // warp strength (0 = smooth, high = liquid)
        var waveFreq: Double = 1.0   // ripple frequency of the final banding
        var bias: Double = 0.0       // tone bias: <0 lifts, >0 deepens the palette
        var brightness: Double = 0
        var saturation: Double = 1.15
        var contrast: Double = 1.0
        var dither: Double = 0.1
        var hue: Double = 0
    }

    private static let ctx = BlurProcessor.context
    private static let cs = BlurProcessor.outputColorSpace

    // Ported from the heart.zuerich "liquid gradient" fragment shader:
    // iterated domain warp -> normalised value -> multi-stop palette.
    private static let kernel = CIColorKernel(source: """
    vec4 pick(float i, vec4 c0, vec4 c1, vec4 c2, vec4 c3, vec4 c4) {
        if (i < 0.5) return c0;
        if (i < 1.5) return c1;
        if (i < 2.5) return c2;
        if (i < 3.5) return c3;
        return c4;
    }

    kernel vec4 liquid(__color c0, __color c1, __color c2, __color c3, __color c4,
                       float count, float w, float h, float time, float seed,
                       float scale, float turbAmp, float waveFreq, float bias) {
        vec2 fc = destCoord();
        vec2 r = vec2(w, h);
        vec2 p = (fc * 2.0 - r) / r.y;

        float t = time * 0.3;

        // Seed-based rotation (golden angle) so each seed gives a distinct flow.
        float ang = seed * 2.3999632;
        float cs = cos(ang);
        float sn = sin(ang);
        p = vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y);

        vec2 so = vec2(sin(seed * 1.7), cos(seed * 2.3));

        // Turbulence: a few layers, each iteratively folded through sin() so the
        // coordinate field curdles into liquid veins.
        float totalVal = 0.0;
        float totalW = 0.0;
        for (float i = 0.0; i < 4.0; i += 1.0) {
            float eph = i / 4.0;
            vec2 q = p * scale;
            float a = so.x;
            float d = so.y;
            for (int j = 2; j < 13; j += 1) {
                float fj = float(j);
                q += turbAmp * sin(q.yx * fj + t + vec2(a, d) + so * fj) / fj;
                a += cos(fj + d * 1.2 + q.x * 2.0 - t);
                d += sin(fj * q.y + a + t);
            }
            float v = 0.5 + 0.5 * sin(length(q.yx + vec2(a, d) * 0.2) * waveFreq + i * i + so.x);
            float wgt = smoothstep(0.0, 0.5, eph) * smoothstep(1.0, 0.5, eph);
            totalVal += v * wgt;
            totalW += wgt;
        }
        float val = totalVal / max(totalW, 0.001);
        val = clamp((val - 0.3) / 0.4, 0.0, 1.0);
        val = pow(val, exp(-bias));

        // Multi-stop palette (linear-light mix, smoothstep-eased segments).
        float cnt = max(count, 2.0);
        float seg = 1.0 / (cnt - 1.0);
        float fidx = clamp(floor(val / seg), 0.0, cnt - 2.0);
        float lt = clamp((val - fidx * seg) / seg, 0.0, 1.0);
        lt = lt * lt * (3.0 - 2.0 * lt);
        vec4 A = pick(fidx, c0, c1, c2, c3, c4);
        vec4 B = pick(fidx + 1.0, c0, c1, c2, c3, c4);
        return mix(A, B, lt);
    }
    """)!

    static func render(size: CGSize, settings: Settings, deepColor: Bool = false) -> CGImage? {
        guard size.width >= 1, size.height >= 1, !settings.colors.isEmpty else { return nil }
        let w = size.width, h = size.height
        let rect = CGRect(origin: .zero, size: size)

        // Pad the palette to 5 stops (repeat the last) so the kernel signature is
        // fixed; `count` gates how many are actually sampled.
        var cols = settings.colors
        let last = cols.last ?? CIColor(red: 0.5, green: 0.5, blue: 0.5)
        while cols.count < 5 { cols.append(last) }
        let count = Double(min(max(settings.count, 2), 5))

        guard var img = kernel.apply(extent: rect, arguments: [
            cols[0], cols[1], cols[2], cols[3], cols[4],
            count, w, h, settings.time, settings.seed,
            settings.scale, settings.turbAmp, settings.waveFreq, settings.bias,
        ]) else { return nil }

        img = BlurProcessor.colorGrade(img, brightness: settings.brightness,
                                       saturation: settings.saturation, contrast: settings.contrast,
                                       hue: settings.hue)

        if settings.dither > 0 {
            let d = CIFilter.dither()
            d.inputImage = img
            d.intensity = Float(settings.dither)
            img = d.outputImage ?? img
        }

        if deepColor {
            return ctx.createCGImage(img, from: rect, format: .RGBA16, colorSpace: cs)
        }
        return ctx.createCGImage(img, from: rect, format: .RGBA8, colorSpace: cs)
    }
}
