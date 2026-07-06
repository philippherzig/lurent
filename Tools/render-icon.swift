import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Standalone CLI: renders the app's signature Flow gradient at 1024x1024
// and writes it as a full-bleed PNG for use as the App Icon background.
// Build/run with:
//   swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
//     -o /tmp/render-icon Tools/render-icon.swift Sources/FlowProcessor.swift Sources/BlurProcessor.swift
//   /tmp/render-icon

let size = CGSize(width: 1024, height: 1024)

let settings = FlowProcessor.Settings(
    colors: [
        CIColor(red: 0.98, green: 0.55, blue: 0.10),
        CIColor(red: 1.00, green: 0.13, blue: 0.55),
        CIColor(red: 0.55, green: 0.12, blue: 0.92)
    ],
    bands: 3,
    amplitude: 0.11,
    frequency: 1.0,
    sharpness: 0.8,
    edgeSoftness: 0.7,
    phase: 1.0,
    dither: 0.05
)

guard let cgImage = FlowProcessor.render(size: size, settings: settings) else {
    FileHandle.standardError.write("Failed to render Flow gradient\n".data(using: .utf8)!)
    exit(1)
}

// Resolve relative to the current working directory (run this from the repo root).
let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outURL = rootURL
    .appendingPathComponent("AppIcon.icon")
    .appendingPathComponent("Assets")
    .appendingPathComponent("flow-gradient.png")

guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write("Failed to create image destination at \(outURL.path)\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, cgImage, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("Failed to finalize PNG\n".data(using: .utf8)!)
    exit(1)
}

print("Wrote \(outURL.path) (\(cgImage.width)x\(cgImage.height))")
