import CoreImage
import CoreGraphics

/// Cuts the (blurred) image into parallel bands — "Lamellen" — and slides each band
/// along its own axis by a different amount. Because a heavy blur is mostly a smooth
/// gradient, sliding neighbouring bands against each other lands *different* colours
/// side by side, so a plain soft gradient turns into a rhythmic, sliced composition.
///
/// Like `MirrorProcessor` this only ever *resamples* the blur base at transformed
/// coordinates — it never differentiates or sharpens it, so it cannot amplify source
/// noise and stays clean on soft, low-resolution photos.
enum SliceProcessor {

    struct Settings {
        var count: Double = 14       // bands across the frame (at angle 0)
        var angle: Double = 0.35     // radians; 0 = vertical bands
        var shift: Double = 0.4      // 0…1 max displacement along the band axis
        var fan: Double = 0          // 0 = parallel bands, 1 = wedges fanning out
        var curve: Double = 0        // −1…1 bend of the bands; 0 = straight
        var seed: Double = 1         // reshuffles which band gets which offset
    }

    /// Distance of the fan pivot from the frame centre, along the band axis.
    ///
    /// Parallel bands are just the limit case of a fan whose pivot sits infinitely far
    /// away, so one radius covers the whole range: `fan` 0 pushes the pivot ~45 frames
    /// away (indistinguishable from parallel), `fan` 1 brings it to just outside the
    /// bottom edge, where the wedges converge into a bouquet.
    static func pivotRadius(fan: Double, minSide: Double) -> Double {
        minSide * 0.55 / max(fan, 0.012)
    }

    // Coordinates are rotated into "band space" (r.x runs across the bands, r.y along
    // them), so one angle parameter covers vertical → diagonal → horizontal lamellae.
    // Each band index gets a deterministic pseudo-random offset from a hash, which is
    // what makes the bands differ instead of marching uniformly.
    //
    // The seam is deliberately a hard cut: softening it by cross-fading a band with its
    // neighbour blends two *differently displaced* copies of the image, which reads as
    // ghosting rather than a soft edge. The crisp slice is the look.
    private static let kernel = CIKernel(source: """
    float hash1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

    kernel vec4 slices(sampler img, float cx, float cy, float ca, float sa,
                       float bandW, float shift, float seed, float pivotR, float curveK) {
        vec2 dc = destCoord();
        vec2 ctr = vec2(cx, cy);
        vec2 c = dc - ctr;
        vec2 r = vec2(ca * c.x + sa * c.y, -sa * c.x + ca * c.y);

        // Bands are wedges radiating from a pivot `pivotR` below the centre. The
        // ARC LENGTH at that radius is the across-bands coordinate, so band widths stay
        // comparable and a large pivotR straightens the wedges back into parallel
        // stripes — the parallel case needs no separate code path.
        vec2 v = vec2(r.x, r.y + pivotR);
        float len = max(length(v), 0.0001);

        // Curve: bend the band boundaries by displacing the across-coordinate
        // QUADRATICALLY with distance travelled along the wedge, so straight rays
        // become arcs (linear displacement would only shear them, i.e. change the
        // angle). Signed, so the blades can sweep either way. Works in the parallel
        // case too, where it bows the stripes into arcs.
        float along = len - pivotR;
        float i = floor((pivotR * atan(v.x, v.y) + curveK * along * along) / bandW);

        float h = hash1(i + seed * 7.0);
        float off = (h * 2.0 - 1.0) * shift;

        // Slide each wedge along its OWN direction (radially away from the pivot);
        // in the parallel limit that direction is the band axis, as before.
        vec2 vs = v + (v / len) * off;
        vec2 rs = vs - vec2(0.0, pivotR);
        vec2 p = vec2(ca * rs.x - sa * rs.y, sa * rs.x + ca * rs.y) + ctr;
        return sample(img, samplerTransform(img, p));
    }
    """)!

    static func apply(to image: CIImage, size: CGSize, settings s: Settings) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let minSide = min(size.width, size.height)
        let bandW = minSide / max(2, s.count)
        let shift = s.shift * 0.35 * minSide
        let ca = cos(s.angle), sa = sin(s.angle)
        let pivotR = pivotRadius(fan: s.fan, minSide: minSide)
        // Normalised so curve = ±1 bows the boundary by ~a quarter frame at the edge.
        let curveK = s.curve / minSide
        let clamped = image.clampedToExtent()
        return kernel.apply(extent: rect,
                            roiCallback: { _, r in r.insetBy(dx: -shift - 1, dy: -shift - 1) },
                            arguments: [clamped, size.width / 2, size.height / 2, ca, sa,
                                        bandW, shift, s.seed, pivotR, curveK]) ?? image
    }
}
