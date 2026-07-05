import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum WallpaperError: LocalizedError {
    case metadata, destination, finalize
    var errorDescription: String? {
        switch self {
        case .metadata:    return "Wallpaper-Metadaten konnten nicht erzeugt werden."
        case .destination: return "HEIC konnte nicht erstellt werden (HEVC-Encoder nicht verfügbar?)."
        case .finalize:    return "HEIC konnte nicht geschrieben werden."
        }
    }
}

/// Writes appearance-based (Light/Dark) dynamic desktop wallpapers as a single
/// HEIC file. macOS 26 (Tahoe) / Sonoma recognise the `apple_desktop:apr` tag
/// with a flat `{ l, d }` index dictionary — matching the system's own
/// `Sonoma.heic`. The legacy `apple_desktop:apple_desktop` (`{ ap: { l, d } }`)
/// tag is added too for older releases.
enum DynamicWallpaper {

    private static let namespace = "http://ns.apple.com/namespace/1.0/" as CFString
    private static let prefix = "apple_desktop" as CFString

    /// Image index 0 = Light appearance, index 1 = Dark appearance.
    static func writeHEIC(light: CGImage, dark: CGImage, to url: URL) throws {
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil)

        // Current macOS format.
        try setTag(metadata, name: "apr", path: "apple_desktop:apr",
                   plist: ["l": 0, "d": 1])
        // Legacy format (Mojave … Ventura).
        try setTag(metadata, name: "apple_desktop", path: "apple_desktop:apple_desktop",
                   plist: ["ap": ["l": 0, "d": 1]])

        let type = UTType.heic.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 2, nil) else {
            throw WallpaperError.destination
        }
        CGImageDestinationAddImageAndMetadata(dest, light, metadata, nil)
        CGImageDestinationAddImage(dest, dark, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw WallpaperError.finalize
        }
    }

    private static func setTag(_ metadata: CGMutableImageMetadata,
                               name: String, path: String, plist: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let base64 = data.base64EncodedString()
        guard let tag = CGImageMetadataTagCreate(
            namespace, prefix, name as CFString, .string, base64 as CFString
        ), CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag) else {
            throw WallpaperError.metadata
        }
    }
}
