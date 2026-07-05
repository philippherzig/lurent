import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Resolution presets

struct ResolutionPreset: Identifiable, Hashable {
    let name: String
    let width: Int
    let height: Int
    var id: String { name }
    var isCustom: Bool { width == 0 && height == 0 }

    static let all: [ResolutionPreset] = [
        .init(name: "Pro Display XDR — 6016 × 3384", width: 6016, height: 3384),
        .init(name: "Studio Display 5K — 5120 × 2880", width: 5120, height: 2880),
        .init(name: "iMac 24\" 4.5K — 4480 × 2520", width: 4480, height: 2520),
        .init(name: "MacBook Pro 16\" — 3456 × 2234", width: 3456, height: 2234),
        .init(name: "MacBook Pro 14\" — 3024 × 1964", width: 3024, height: 1964),
        .init(name: "MacBook Air 13\" — 2560 × 1664", width: 2560, height: 1664),
        .init(name: "4K UHD — 3840 × 2160", width: 3840, height: 2160),
        .init(name: "Full HD — 1920 × 1080", width: 1920, height: 1080),
        .init(name: "Eigene Größe…", width: 0, height: 0),
    ]

    static var proDisplayXDR: ResolutionPreset { all[0] }
}

// MARK: - Mode & appearance

enum WallpaperMode: String, CaseIterable, Identifiable {
    case single, dynamic
    var id: String { rawValue }
    var label: String { self == .single ? "Statisch" : "Hell + Dunkel" }
}

enum Appearance: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var label: String { self == .light ? "Hell" : "Dunkel" }
    var other: Appearance { self == .light ? .dark : .light }
}

// MARK: - A single wallpaper "look"

struct Look {
    var source: CGImage?
    var photoID: String?
    var baseName: String?
    var attribution: String?
    var attributionURL: String?

    var blur: Double = 55
    var brightness: Double = 0
    var saturation: Double = 1.15
    var contrast: Double = 1.0
    var dither: Double = 1.2

    var settings: BlurProcessor.Settings {
        .init(blur: blur, brightness: brightness, saturation: saturation,
              contrast: contrast, dither: dither)
    }
}

enum ExportError: LocalizedError {
    case noSource, renderFailed, encodeFailed
    var errorDescription: String? {
        switch self {
        case .noSource:     return "Kein Quellbild ausgewählt."
        case .renderFailed: return "Das Wallpaper konnte nicht gerendert werden."
        case .encodeFailed: return "Das Bild konnte nicht kodiert werden."
        }
    }
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    private static let keyDefaultsKey = "unsplashAccessKey"
    /// Bundled key (injected at build time from .env via Secrets.generated.swift)
    /// so search works out of the box; empty if no .env was present.
    static let bundledKey = Secrets.unsplashKey

    // Credentials
    @Published var accessKey: String {
        didSet { UserDefaults.standard.set(accessKey, forKey: Self.keyDefaultsKey) }
    }

    // Search
    @Published var query: String = ""
    @Published var results: [UnsplashPhoto] = []
    @Published var isSearching = false
    @Published var isLoadingSource = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    // Mode
    @Published var mode: WallpaperMode = .single {
        didSet {
            if mode == .dynamic { seedDarkIfNeeded() }
            renderPreview()
        }
    }
    @Published var editing: Appearance = .light { didSet { renderPreview() } }

    // Looks
    @Published var lightLook = Look()
    @Published var darkLook = Look(brightness: -0.15, saturation: 1.05, contrast: 1.05)

    // Output size
    @Published var preset: ResolutionPreset = .proDisplayXDR { didSet { renderPreview() } }
    @Published var customWidth: Int = 6016 { didSet { renderPreview() } }
    @Published var customHeight: Int = 3384 { didSet { renderPreview() } }

    // Output preview
    @Published private(set) var preview: NSImage?

    private var renderTask: Task<Void, Never>?

    init() {
        accessKey = UserDefaults.standard.string(forKey: Self.keyDefaultsKey) ?? ""
    }

    // MARK: Key

    var effectiveKey: String {
        let user = accessKey.trimmingCharacters(in: .whitespaces)
        return user.isEmpty ? Self.bundledKey : user
    }
    private var service: UnsplashService { UnsplashService(accessKey: effectiveKey) }

    // MARK: Current look editing

    var effectiveAppearance: Appearance { mode == .single ? .light : editing }

    var currentLook: Look {
        effectiveAppearance == .light ? lightLook : darkLook
    }

    private func mutateCurrentLook(_ change: (inout Look) -> Void) {
        if effectiveAppearance == .light { change(&lightLook) } else { change(&darkLook) }
        scheduleRender()
    }

    /// Two-way binding to a field of the currently edited look.
    func bind<T>(_ keyPath: WritableKeyPath<Look, T>) -> Binding<T> {
        Binding(
            get: { self.currentLook[keyPath: keyPath] },
            set: { newValue in self.mutateCurrentLook { $0[keyPath: keyPath] = newValue } }
        )
    }

    func resetCurrentLook() {
        mutateCurrentLook {
            let d = Look()
            $0.blur = d.blur; $0.brightness = d.brightness
            $0.saturation = d.saturation; $0.contrast = d.contrast
            $0.dither = d.dither
        }
    }

    private func seedDarkIfNeeded() {
        guard darkLook.source == nil, lightLook.source != nil else { return }
        var d = lightLook
        d.brightness = -0.15; d.saturation = 1.05; d.contrast = 1.05
        darkLook = d
    }

    func copyCurrentSourceToOther() {
        let src = currentLook
        let apply: (inout Look) -> Void = {
            $0.source = src.source; $0.photoID = src.photoID; $0.baseName = src.baseName
            $0.attribution = src.attribution; $0.attributionURL = src.attributionURL
        }
        if effectiveAppearance == .light { apply(&darkLook) } else { apply(&lightLook) }
        renderPreview()
    }

    // MARK: Output size

    var pixelSize: (width: Int, height: Int) {
        preset.isCustom ? (max(1, customWidth), max(1, customHeight)) : (preset.width, preset.height)
    }

    var pixelSizeLabel: String {
        let s = pixelSize
        let mp = Double(s.width * s.height) / 1_000_000
        return "\(s.width) × \(s.height) px · \(String(format: "%.1f", mp)) MP"
    }

    // MARK: Search

    func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            defer { isSearching = false }
            do {
                results = try await service.search(query: q)
                if results.isEmpty { errorMessage = "Keine Treffer für „\(q)“." }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Source selection

    private func baseName(for photo: UnsplashPhoto) -> String {
        if let slug = photo.slug, !slug.isEmpty { return slug }
        if let alt = photo.alt_description, !alt.isEmpty {
            return Self.slugify(alt) + "-" + photo.id
        }
        return "unsplash-" + photo.id
    }

    func select(_ photo: UnsplashPhoto) {
        let target = effectiveAppearance
        isLoadingSource = true
        errorMessage = nil
        Task {
            defer { isLoadingSource = false }
            do {
                let cg = try await service.loadImage(from: photo.urls.regular)
                applySource(cg, photoID: photo.id, baseName: baseName(for: photo),
                            attribution: "Foto: \(photo.user.name) · Unsplash",
                            attributionURL: photo.user.links?.html, to: target)
                if let dl = photo.links?.download_location {
                    Task { await service.trackDownload(dl) }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openLocalImage(url: URL) {
        errorMessage = nil
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            errorMessage = "Bild konnte nicht geladen werden: \(url.lastPathComponent)"
            return
        }
        applySource(cg, photoID: nil,
                    baseName: url.deletingPathExtension().lastPathComponent,
                    attribution: url.lastPathComponent, attributionURL: nil,
                    to: effectiveAppearance)
    }

    private func applySource(_ cg: CGImage, photoID: String?, baseName: String?,
                             attribution: String?, attributionURL: String?, to appearance: Appearance) {
        let apply: (inout Look) -> Void = {
            $0.source = cg; $0.photoID = photoID; $0.baseName = baseName
            $0.attribution = attribution; $0.attributionURL = attributionURL
        }
        if appearance == .light { apply(&lightLook) } else { apply(&darkLook) }
        renderPreview()
    }

    // MARK: Rendering

    private func previewTargetSize() -> CGSize {
        let s = pixelSize
        let longest = Double(max(s.width, s.height))
        let cap = 1800.0
        guard longest > cap else { return CGSize(width: s.width, height: s.height) }
        let f = cap / longest
        return CGSize(width: Double(s.width) * f, height: Double(s.height) * f)
    }

    func renderPreview() {
        guard let src = currentLook.source else { preview = nil; return }
        let size = previewTargetSize()
        if let cg = BlurProcessor.render(source: src, targetSize: size, settings: currentLook.settings) {
            preview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            if Task.isCancelled { return }
            renderPreview()
        }
    }

    private func renderFull(_ look: Look) throws -> CGImage {
        guard let src = look.source else { throw ExportError.noSource }
        let s = pixelSize
        guard let cg = BlurProcessor.render(
            source: src, targetSize: CGSize(width: s.width, height: s.height),
            settings: look.settings, deepColor: true
        ) else { throw ExportError.renderFailed }
        return cg
    }

    private func pngData(_ cg: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: cg.width, height: cg.height)
        guard let d = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.encodeFailed
        }
        return d
    }

    // MARK: File names

    var canExport: Bool {
        mode == .single ? lightLook.source != nil
                        : (lightLook.source != nil && darkLook.source != nil)
    }

    func exportFileName(ext: String) -> String {
        let s = pixelSize
        if mode == .dynamic {
            let base = lightLook.baseName ?? "blur-wallpaper"
            return "\(base)-dynamic-\(s.width)x\(s.height).\(ext)"
        }
        let base = lightLook.baseName ?? "blur-wallpaper"
        return "\(base)-\(s.width)x\(s.height).\(ext)"
    }

    private func writeOutput(to url: URL) throws {
        if mode == .dynamic {
            let l = try renderFull(lightLook)
            let d = try renderFull(darkLook)
            try DynamicWallpaper.writeHEIC(light: l, dark: d, to: url)
        } else {
            try pngData(try renderFull(lightLook)).write(to: url)
        }
    }

    // MARK: Export (save panel)

    func exportWithPanel() {
        let panel = NSSavePanel()
        let ext = mode == .dynamic ? "heic" : "png"
        panel.allowedContentTypes = [mode == .dynamic ? .heic : .png]
        panel.nameFieldStringValue = exportFileName(ext: ext)
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try self.writeOutput(to: url)
                    self.statusMessage = "Exportiert: \(url.lastPathComponent)"
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: Set as desktop

    func setAsDesktop() {
        do {
            let dir = try Self.appSupportDir()
            // Clean old exports so the wallpaper agent reloads a fresh file.
            if let existing = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for f in existing { try? FileManager.default.removeItem(at: f) }
            }
            let ext = mode == .dynamic ? "heic" : "png"
            let url = dir.appendingPathComponent("current-\(UUID().uuidString.prefix(8)).\(ext)")
            try writeOutput(to: url)
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
            statusMessage = mode == .dynamic
                ? "Als dynamisches Wallpaper gesetzt."
                : "Als Schreibtischhintergrund gesetzt."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Drag & drop (reliable file-backed provider)

    func makeDragProvider() -> NSItemProvider {
        do {
            // Render synchronously now so the file exists before the drop resolves.
            let ext = mode == .dynamic ? "heic" : "png"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(exportFileName(ext: ext))
            try writeOutput(to: url)
            let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
            provider.suggestedName = url.lastPathComponent
            return provider
        } catch {
            errorMessage = error.localizedDescription
            return NSItemProvider()
        }
    }

    // MARK: Helpers

    static func slugify(_ s: String) -> String {
        let mapped = s.lowercased().map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "-"
        }
        var out = String(mapped)
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(out.prefix(60))
    }

    static func appSupportDir() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Blur Wallpaper Maker", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
