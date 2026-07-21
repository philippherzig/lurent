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
        var seed: Double = 1         // reshuffles which band gets which offset
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
                       float bandW, float shift, float seed) {
        vec2 dc = destCoord();
        vec2 ctr = vec2(cx, cy);
        vec2 c = dc - ctr;
        vec2 r = vec2(ca * c.x + sa * c.y, -sa * c.x + ca * c.y);

        float i = floor(r.x / bandW);
        float h = hash1(i + seed * 7.0);
        vec2 rs = vec2(r.x, r.y + (h * 2.0 - 1.0) * shift);
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
        let clamped = image.clampedToExtent()
        return kernel.apply(extent: rect,
                            roiCallback: { _, r in r.insetBy(dx: -shift - 1, dy: -shift - 1) },
                            arguments: [clamped, size.width / 2, size.height / 2, ca, sa,
                                        bandW, shift, s.seed]) ?? image
    }
}
