import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Generates a Big Sur–style "dune" gradient by compositing several wavy colour
/// layers on top of one another — like stacked sheets of silk. Each boundary
/// carries its OWN wave (distinct phase + amplitude, so the sheets aren't
/// parallel) and its OWN hardness *field that varies along the contour*: crisp
/// in some stretches, dissolving in others. That per-edge, along-the-line
/// variation — the `MirrorProcessor` seam idea (hard in places, soft in others)
/// generalised to every boundary — is what gives the classic macOS wallpaper its
/// layered depth instead of one uniformly blurred rainbow.
///
/// A thin light/shadow lip along the crisp stretches embosses the fold edges,
/// and an optional gaussian soft-focus adds overall haze. Colours are mixed in
/// the linear working space (like the other synthetic styles) so mid-tones stay
/// vivid; a yellow→blue top boundary passes through a natural white seam.
enum DuneProcessor {

    struct Settings {
        var colors: [CIColor]          // up to 5 stops, ordered low → high value
        var count: Int = 5             // how many stops are active (2…5)
        var tilt: Double = 0.42        // diagonal skew of the layered axis
        var amplitude: Double = 0.12   // fold height as fraction of the ramp
        var frequency: Double = 1.05   // number of folds across the width
        var sharpness: Double = 1.0    // 0 = all edges soft, 1 = crisp where the
                                       //     per-edge field is hard (layered look)
        var shading: Double = 1.0      // emboss lip along the crisp edges
        var softness: Double = 0       // gaussian soft-focus, fraction of short side
        var phase: Double = 0.5        // fold variation
        var brightness: Double = 0
        var saturation: Double = 1.15
        var contrast: Double = 1.0
        var dither: Double = 0.1
    }

    private static let ctx = BlurProcessor.context
    private static let cs = BlurProcessor.outputColorSpace

    // NB: `active` is a reserved word in the CI Kernel Language — the layer gate
    // is named `gate`.
    private static let kernel = CIColorKernel(source: """
    vec4 pick(float i, vec4 c0, vec4 c1, vec4 c2, vec4 c3, vec4 c4) {
        if (i < 0.5) return c0;
        if (i < 1.5) return c1;
        if (i < 2.5) return c2;
        if (i < 3.5) return c3;
        return c4;
    }

    kernel vec4 dune(__color c0, __color c1, __color c2, __color c3, __color c4,
                     float count, float w, float h,
                     float tilt, float amp, float freq, float phase,
                     float sharp, float shade) {
        vec2 fc = destCoord();
        float nx = fc.x / w;
        float ny = fc.y / h;
        float TWO_PI = 6.2831853;

        // Compare boundaries against a tilted vertical coordinate → diagonal flow.
        float y = ny + tilt * (nx - 0.5);
        float cnt = max(count, 2.0);

        vec4 col = c0;
        for (int k = 1; k < 5; k += 1) {
            float fk = float(k);
            float gate = step(fk, cnt - 1.0 + 0.001);
            float level = fk / (cnt - 1.0);
            float ph = phase + fk * 1.7;

            // Boundary wave — each layer its own phase / amplitude (non-parallel).
            float ak = amp * (0.75 + 0.45 * sin(fk * 2.3 + 1.1));
            float wave = sin(freq * TWO_PI * nx + ph)
                       + 0.35 * sin(2.0 * freq * TWO_PI * nx + ph * 1.6 + fk)
                       + 0.18 * sin(3.0 * freq * TWO_PI * nx + ph * 0.7);
            float b = level + ak * wave;

            // Hardness varies ALONG the boundary (per-layer pseudo-random field):
            // crisp where the field is high, dissolving where it is low.
            float hf = 0.5 + 0.32 * sin(0.9 * TWO_PI * nx + fk * 2.1)
                           + 0.18 * sin(1.7 * TWO_PI * nx + fk * 3.7 + 0.6);
            hf = clamp(hf, 0.0, 1.0);
            float hard = clamp(sharp * hf, 0.0, 1.0);
            float hw = mix(0.16, 0.004, hard);

            float e = smoothstep(-hw, hw, y - b) * gate;
            vec4 ck = pick(fk, c0, c1, c2, c3, c4);
            col = mix(col, ck, e);

            // Emboss lip: highlight above / shadow below, only where the edge is crisp.
            float d = y - b;
            float lip = gate * hard * exp(-abs(d) / (hw + 0.03));
            col.rgb *= 1.0 + shade * 0.18 * lip * sign(d);
        }
        col.a = 1.0;
        return col;
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
            count, w, h,
            settings.tilt, settings.amplitude, settings.frequency, settings.phase,
            settings.sharpness, settings.shading,
        ]) else { return nil }

        // Optional overall haze on top of the per-edge softness.
        let sigma = settings.softness * min(w, h)
        if sigma > 0.5 {
            img = img.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: rect)
        }

        img = BlurProcessor.colorGrade(img, brightness: settings.brightness,
                                       saturation: settings.saturation, contrast: settings.contrast)

        if settings.dither > 0 {
            let d = CIFilter.dither()
            d.inputImage = img
            d.intensity = Float(settings.dither)
            img = d.outputImage ?? img
        }

        if deepColor {
            return ctx.createCGImage(img, from: rect, format: .RGBA16, colorSpace: cs)
        }
        return ctx.createCGImage(img, from: rect)
    }
}
