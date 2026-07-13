import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Turns a source image into a smooth, gradient-like wallpaper by heavily
/// blurring it and then aspect-filling it into the requested pixel size.
enum BlurProcessor {

    struct Settings {
        /// 0…100 slider value; mapped to a gaussian sigma relative to the source.
        var blur: Double = 55
        /// Core Image brightness (-1…1), 0 = neutral.
        var brightness: Double = 0
        /// Core Image saturation (0…2), 1 = neutral.
        var saturation: Double = 1.15
        /// Core Image contrast (0…2), 1 = neutral.
        var contrast: Double = 1.0
        /// Dither intensity applied at output resolution. 16-bit output already
        /// removes banding; this adds a subtle grain on top (kept low by default).
        var dither: Double = 0.1
        /// Global hue rotation in radians (0 = neutral); rotates every colour.
        var hue: Double = 0
    }

    static let context: CIContext = {
        CIContext(options: [.cacheIntermediates: false])
    }()

    static let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Renders `source` into an image of exactly `targetSize` pixels.
    /// - Parameter deepColor: render a 16-bit-per-channel image (for export) so
    ///   the final gradient has no 8-bit quantisation banding.
    static func render(source: CGImage, targetSize: CGSize, settings: Settings,
                       deepColor: Bool = false) -> CGImage? {
        guard let image = processedImage(source: source, targetSize: targetSize, settings: settings)
        else { return nil }
        return finalize(image, size: targetSize, dither: settings.dither, deepColor: deepColor)
    }

    /// The blurred, colour-graded, aspect-filled image at `targetSize`, origin
    /// (0,0), before dithering/output — reusable as input for other styles.
    static func processedImage(source: CGImage, targetSize: CGSize, settings: Settings) -> CIImage? {
        guard targetSize.width >= 1, targetSize.height >= 1 else { return nil }

        var image = CIImage(cgImage: source)
        let content = image.extent
        let minSide = min(content.width, content.height)

        // Map the 0…100 slider to a gaussian sigma as a fraction of the shorter
        // side. A big sigma collapses the photo into soft colour fields.
        let fraction = (settings.blur / 100.0) * 0.22
        let sigma = fraction * minSide
        if sigma > 0.5 {
            image = image
                .clampedToExtent()
                .applyingGaussianBlur(sigma: sigma)
                .cropped(to: content)
        }

        // Colour grading (shared with the synthetic styles).
        image = colorGrade(image, brightness: settings.brightness,
                           saturation: settings.saturation, contrast: settings.contrast,
                           hue: settings.hue)

        // Aspect-fill into the target canvas, centred.
        let ext = image.extent
        guard ext.width > 0, ext.height > 0 else { return nil }
        let scale = max(targetSize.width / ext.width, targetSize.height / ext.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let scaled = image.extent
        let cropRect = CGRect(
            x: scaled.midX - targetSize.width / 2,
            y: scaled.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        return image
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x,
                                               y: -cropRect.origin.y))
    }

    /// Brightness / saturation / contrast / hue grade — shared by every style so the
    /// controls behave identically across Blur, Flow, Liquid, Dune, Glow and Spiegel.
    static func colorGrade(_ image: CIImage, brightness: Double,
                           saturation: Double, contrast: Double, hue: Double = 0) -> CIImage {
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.brightness = Float(brightness)
        color.saturation = Float(saturation)
        color.contrast = Float(contrast)
        var out = color.outputImage ?? image
        if hue != 0 {
            let h = CIFilter.hueAdjust()
            h.inputImage = out
            h.angle = Float(hue)
            out = h.outputImage ?? out
        }
        return out
    }

    /// Applies dithering and renders to a CGImage of exactly `size` pixels.
    static func finalize(_ input: CIImage, size: CGSize, dither: Double, deepColor: Bool) -> CGImage? {
        var image = input
        if dither > 0 {
            let d = CIFilter.dither()
            d.inputImage = image
            d.intensity = Float(dither)
            image = d.outputImage ?? image
        }
        let outRect = CGRect(origin: .zero, size: size)
        if deepColor {
            return context.createCGImage(image, from: outRect,
                                         format: .RGBA16, colorSpace: outputColorSpace)
        }
        return context.createCGImage(image, from: outRect)
    }
}
