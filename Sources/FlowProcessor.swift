import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Generates a flowing "wave" gradient: colour bands separated by sine-shaped
/// boundaries whose transition is HARD in the centre and eases out toward the
/// sides (variable half-width via a sin(pi*x) falloff). Inspired by the
/// Icon Composer background look.
enum FlowProcessor {

    struct Settings {
        var colors: [CIColor]          // 2 or 3, ordered bottom → top
        var bands: Int = 3             // 2 or 3
        var amplitude: Double = 0.11   // wave height as fraction of image height
        var frequency: Double = 1.0    // waves across the width
        var sharpness: Double = 0.8    // 0…1, higher = harder centre edge
        var edgeSoftness: Double = 0.7 // 0…1, higher = more dissolve at the sides
        var phase: Double = 1.0        // wave variation
        var brightness: Double = 0
        var saturation: Double = 1.15
        var contrast: Double = 1.0
        var dither: Double = 0.1
    }

    private static let ctx = BlurProcessor.context
    private static let cs = BlurProcessor.outputColorSpace

    private static let kernel2 = CIColorKernel(source: """
    kernel vec4 edge2(__color top, __color bot, float amp, float freq, float phase,
                      float hwMin, float hwMax, float w, float h) {
        vec2 p = destCoord();
        float nx = p.x / w;
        float ny = p.y / h;
        float wave = sin(freq*6.2831853*nx + phase) + 0.25*sin(2.0*freq*6.2831853*nx + phase*1.6);
        float curve = 0.5 + amp * wave;
        float sharp = sin(3.14159265 * clamp(nx, 0.0, 1.0));
        float hw = mix(hwMax, hwMin, sharp);
        return mix(bot, top, smoothstep(-hw, hw, ny - curve));
    }
    """)!

    private static let kernel3 = CIColorKernel(source: """
    kernel vec4 edge3(__color c0, __color c1, __color c2, float amp, float freq, float phase,
                      float hwMin, float hwMax, float w, float h) {
        vec2 p = destCoord();
        float nx = p.x / w;
        float ny = p.y / h;
        float sharp = sin(3.14159265 * clamp(nx, 0.0, 1.0));
        float hw = mix(hwMax, hwMin, sharp);
        float k1 = 0.36 + amp*(sin(freq*6.2831853*nx + phase + 0.3) + 0.2*sin(2.0*freq*6.2831853*nx));
        float k2 = 0.68 + amp*(sin(freq*6.2831853*nx + phase + 2.4) + 0.2*sin(2.0*freq*6.2831853*nx + 1.1));
        vec4 col = mix(c0, c1, smoothstep(-hw, hw, ny - k1));
        col = mix(col, c2, smoothstep(-hw, hw, ny - k2));
        return col;
    }
    """)!

    static func render(size: CGSize, settings: Settings, deepColor: Bool = false) -> CGImage? {
        guard size.width >= 1, size.height >= 1, !settings.colors.isEmpty else { return nil }
        let w = size.width, h = size.height
        let rect = CGRect(origin: .zero, size: size)

        // Map 0…1 sliders to normalised transition half-widths.
        let hwMin = 0.0015 + (1 - settings.sharpness) * (0.03 - 0.0015)
        let hwMax = 0.08 + settings.edgeSoftness * (0.55 - 0.08)
        let cols = settings.colors

        var image: CIImage?
        if settings.bands >= 3 && cols.count >= 3 {
            image = kernel3.apply(extent: rect, arguments: [
                cols[0], cols[1], cols[2],
                settings.amplitude, settings.frequency, settings.phase,
                hwMin, hwMax, w, h])
        } else {
            let bot = cols[0]
            let top = cols.count > 1 ? cols[1] : cols[0]
            image = kernel2.apply(extent: rect, arguments: [
                top, bot,
                settings.amplitude, settings.frequency, settings.phase,
                hwMin, hwMax, w, h])
        }
        guard var img = image else { return nil }

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
