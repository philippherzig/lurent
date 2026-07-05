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
        /// Dither intensity applied at output resolution to break up the colour
        /// banding that smooth blurred gradients show on wide-gamut displays.
        var dither: Double = 1.2
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

        // Colour grading.
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.brightness = Float(settings.brightness)
        color.saturation = Float(settings.saturation)
        color.contrast = Float(settings.contrast)
        image = color.outputImage ?? image

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
        image = image
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x,
                                               y: -cropRect.origin.y))

        // Dither at output resolution to defeat banding on smooth gradients.
        if settings.dither > 0 {
            let dither = CIFilter.dither()
            dither.inputImage = image
            dither.intensity = Float(settings.dither)
            image = dither.outputImage ?? image
        }

        let outRect = CGRect(origin: .zero, size: targetSize)
        if deepColor {
            return context.createCGImage(image, from: outRect,
                                         format: .RGBA16, colorSpace: outputColorSpace)
        }
        return context.createCGImage(image, from: outRect)
    }
}
