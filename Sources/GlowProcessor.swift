import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Generates a "glow" wallpaper: soft light shapes on a near-flat field, where
/// the blur is not a post-pass but the analytic falloff of a signed-distance
/// field. Two forms share one kernel:
///
///   • `.ring`  — a thin luminous ring/arc, faded around its circumference by a
///                directional ramp (the look of the reference screenshot).
///   • `.blobs` — a handful of seed-placed blobs and capsules fused with a
///                polynomial smooth-min, so the shapes melt into each other and
///                dissolve into blur at their shared edge (metaballs).
///
/// Like `FlowProcessor`/`LiquidProcessor`, everything is evaluated once per pixel
/// in a Core Image colour kernel and mixed in the linear working space, so the
/// gradients stay perfectly smooth at 6016×3384 with no clamp artefacts.
enum GlowProcessor {

    enum Form: Int, CaseIterable, Identifiable {
        case ring = 0, arc = 1, orb = 2, wave = 3, blobs = 4
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .ring:  return L("Ring")
            case .arc:   return L("Bogen")
            case .orb:   return L("Kugel")
            case .wave:  return L("Welle")
            case .blobs: return L("Blobs")
            }
        }
    }

    struct Settings {
        var background: CIColor          // flat field colour
        var light: CIColor               // colour the shapes glow toward
        var form: Form = .ring
        var seed: Double = 3.0           // reshuffles blob placement
        var count: Int = 4               // active blobs (1…8), blobs form
        var scale: Double = 1.0          // overall shape size
        var merge: Double = 0.25         // how softly blobs fuse (smooth-min k)
        var thickness: Double = 0.01     // ring half-thickness
        var edge: Double = 0.004         // crisp-side edge width (small = sharper)
        var softness: Double = 0.25      // dissolve width on the fading side (the "blur")
        var halo: Double = 0.5           // extra wide bloom beyond the edge
        var tilt: Double = 1.0           // gradient strength: sharp+bright ↔ blurred+gone
        var tiltDir: Double = 5.2        // gradient direction (rad); where the crisp side sits
        var intensity: Double = 1.0      // overall glow strength
        var warp: Double = 0.0           // organic distortion of the subject
        var stretch: Double = 0.0        // anisotropic stretch (−wide … +tall)
        var rotation: Double = 0.0       // rotate the subject (rad)
        var brightness: Double = 0
        var saturation: Double = 1.0
        var contrast: Double = 1.0
        var dither: Double = 0.1
    }

    private static let ctx = BlurProcessor.context
    private static let cs = BlurProcessor.outputColorSpace

    private static let kernel = CIColorKernel(source: """
    float h11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
    vec2  h22(float n) { return fract(sin(vec2(n * 127.1, n * 311.7)) * 43758.5453); }

    // Polynomial smooth-min: fuses two distance fields over a band of width k.
    float smin(float a, float b, float k) {
        float hh = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
        return mix(b, a, hh) - k * hh * (1.0 - hh);
    }

    // Distance from p to the segment a→b (for capsule-shaped light streaks).
    float sdSeg(vec2 p, vec2 a, vec2 b) {
        vec2 pa = p - a, ba = b - a;
        float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        return length(pa - ba * t);
    }

    kernel vec4 glow(__color bg, __color light, float w, float h,
                     float form, float seed, float count, float scale,
                     float merge, float thickness, float edge, float softness,
                     float halo, float tilt, float tiltDir, float intensity,
                     float warp, float stretch, float rot) {
        vec2 r = vec2(w, h);
        vec2 p = (destCoord() * 2.0 - r) / r.y;   // centered, aspect-correct

        // Build the shape coordinate `ps`: ROTATE the subject, then anisotropic
        // STRETCH (stretch<0 = wide, >0 = tall), then an organic domain WARP (ring →
        // wobble, orb → amoeba, wave → churn). All act on `ps`; the light gradient
        // below keeps the clean `p`, so only the subject deforms, not the lighting.
        float ca = cos(rot), sa = sin(rot);
        vec2 pr = vec2(ca * p.x + sa * p.y, -sa * p.x + ca * p.y);
        float sx = 1.0 + max(-stretch, 0.0) * 1.6;
        float sy = 1.0 + max(stretch, 0.0) * 1.6;
        vec2 ps = vec2(pr.x / sx, pr.y / sy);
        if (warp > 0.001) {
            float f = 2.6;
            float ph = seed * 1.7;
            ps += warp * vec2(sin(f * ps.y + 1.7 + ph) + 0.5 * sin(2.3 * f * ps.x + 0.6 + ph),
                              sin(f * ps.x + 4.2 + ph) + 0.5 * sin(2.3 * f * ps.y + 2.3 + ph));
        }

        // dc = signed distance to the shape core (negative = on/inside it).
        float dc;
        if (form > 3.5) {
            // --- Blobs: clustered blobs + capsules fused with smooth-min ---
            float d = 1e9;
            float n = max(count, 1.0);
            for (float i = 0.0; i < 8.0; i += 1.0) {
                if (i >= n) break;
                float s = seed * 7.0 + i * 13.0;
                vec2 c = (h22(s) - 0.5) * vec2(1.5 * scale, 1.05 * scale);
                float rad = (0.16 + 0.30 * h11(s + 3.0)) * scale;
                float di;
                if (h11(s + 5.0) < 0.35) {
                    vec2 dir = (h22(s + 9.0) - 0.5);
                    vec2 a = c - dir * 0.5 * scale;
                    vec2 b = c + dir * 0.5 * scale;
                    di = sdSeg(ps, a, b) - rad * 0.7;
                } else {
                    di = length(ps - c) - rad;
                }
                d = smin(d, di, merge);
            }
            dc = d;
        } else if (form > 2.5) {
            // --- Wave: a gently undulating horizon streak ---
            float yline = 0.12 * scale * sin(2.6 * ps.x + 1.0);
            dc = abs(ps.y - yline) - thickness;
        } else if (form > 1.5) {
            // --- Orb: a single soft filled disc ---
            dc = length(ps) - 0.42 * scale;
        } else if (form > 0.5) {
            // --- Arc: a ring cut by a half-plane -> an open bow ---
            float ring = abs(length(ps) - 0.55 * scale) - thickness;
            dc = max(ring, ps.y - 0.12 * scale);
        } else {
            // --- Ring: a thin bright band of half-width `thickness` ---
            dc = abs(length(ps) - 0.55 * scale) - thickness;
        }

        // The whole point: a directional gradient that runs the shape from a
        // CRISP, bright edge on one side to a fully DISSOLVED blur on the other.
        // g = 0 on the fading side, 1 on the crisp side; `tilt` sets how far it
        // dissolves, `tiltDir` where the crisp side sits.
        float g = clamp(0.5 + 0.5 * (cos(tiltDir) * p.x + sin(tiltDir) * p.y), 0.0, 1.0);
        float t = 1.0 - tilt * (1.0 - g);

        // Spatially varying blur: the shape is a hard edge smeared by a radius
        // that is tiny (`edge`) on the crisp side and wide (`softness`) on the
        // fading side. This is what makes one edge razor-sharp and the other melt.
        float blurR = mix(softness, edge, t);
        float shape = smoothstep(blurR, -blurR, dc);

        // A little outer glow bleed, tight on the crisp side, wide as it dissolves.
        float glowSig = mix(softness, edge * 8.0 + 0.01, t);
        float e = max(dc, 0.0);
        float bloom = halo * exp(-e * e / (glowSig * glowSig));

        // Brightness fades with the same gradient -> high contrast one side, gone the other.
        float field = clamp(shape + bloom, 0.0, 1.0) * t;
        field = clamp(field * intensity, 0.0, 1.0);
        return mix(bg, light, field);
    }
    """)!

    static func render(size: CGSize, settings s: Settings, deepColor: Bool = false) -> CGImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let w = size.width, h = size.height
        let rect = CGRect(origin: .zero, size: size)

        guard var img = kernel.apply(extent: rect, arguments: [
            s.background, s.light, w, h,
            Double(s.form.rawValue), s.seed, Double(min(max(s.count, 1), 8)), max(s.scale, 0.01),
            max(s.merge, 0.001), s.thickness, max(s.edge, 0.001), max(s.softness, 0.001),
            s.halo, s.tilt, s.tiltDir, s.intensity, s.warp, s.stretch, s.rotation,
        ]) else { return nil }

        img = BlurProcessor.colorGrade(img, brightness: s.brightness,
                                       saturation: s.saturation, contrast: s.contrast)

        return BlurProcessor.finalize(img, size: size, dither: s.dither, deepColor: deepColor)
    }
}
