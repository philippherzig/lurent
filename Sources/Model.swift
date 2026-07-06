import SwiftUI
import AppKit
import CoreImage
import UniformTypeIdentifiers
import Photos

// MARK: - Image source (sidebar selection)

enum ImageSource: Hashable {
    case unsplash
    case files
    case album(id: String, title: String)
}

/// Top-level source choice for the consolidated inspector picker. The Photos
/// case fans out into a per-album sub-picker (see `selectedAlbumID`).
enum SourceKind: String, CaseIterable, Identifiable {
    case unsplash, files, photos
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unsplash: return "Unsplash"
        case .files:    return "Dateien"
        case .photos:   return "Fotos"
        }
    }
    var systemImage: String {
        switch self {
        case .unsplash: return "magnifyingglass"
        case .files:    return "folder"
        case .photos:   return "photo.on.rectangle"
        }
    }
}

// MARK: - Color <-> CIColor

extension Color {
    /// sRGB CIColor for feeding into Core Image kernels.
    var asCIColor: CIColor {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        return CIColor(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: 1)
    }

    /// Builds a saturation-boosted SwiftUI Color from an averaged CIColor.
    static func vivid(from ci: CIColor) -> Color {
        let base = NSColor(srgbRed: min(1, max(0, ci.red)),
                           green: min(1, max(0, ci.green)),
                           blue: min(1, max(0, ci.blue)), alpha: 1)
        guard let rgb = base.usingColorSpace(.sRGB) else { return Color(nsColor: base) }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        s = min(1, s * 1.35 + 0.06)
        b = min(1, max(0.28, b))
        return Color(nsColor: NSColor(hue: h, saturation: s, brightness: b, alpha: 1))
    }
}

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

// MARK: - Appearance

enum Appearance: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var label: String { self == .light ? "Hell" : "Dunkel" }
    var other: Appearance { self == .light ? .dark : .light }
}

enum WallpaperStyle: String, CaseIterable, Identifiable {
    case blur, flow, mirror
    var id: String { rawValue }
    var label: String {
        switch self {
        case .blur: return "Blur"
        case .flow: return "Flow"
        case .mirror: return "Spiegel"
        }
    }
}

// MARK: - A single wallpaper "look"

struct Look {
    var source: CGImage?
    var photoID: String?
    var baseName: String?
    var attribution: String?
    var attributionURL: String?

    var style: WallpaperStyle = .blur

    // Blur style
    var blur: Double = 55
    var brightness: Double = 0
    var saturation: Double = 1.15
    var contrast: Double = 1.0
    var dither: Double = 0.1

    // Flow style
    var flowColor0: Color = Color(red: 0.98, green: 0.55, blue: 0.10)
    var flowColor1: Color = Color(red: 1.00, green: 0.13, blue: 0.55)
    var flowColor2: Color = Color(red: 0.55, green: 0.12, blue: 0.92)
    var flowBands: Int = 3
    var flowAmplitude: Double = 0.11
    var flowFrequency: Double = 1.0
    var flowSharpness: Double = 0.8
    var flowEdgeSoftness: Double = 0.7
    var flowPhase: Double = 1.0

    // Mirror style (builds on the blur controls)
    var mirrorLine: Double = 0.52
    var mirrorAmplitude: Double = 0.05
    var mirrorFrequency: Double = 1.0
    var mirrorPhase: Double = 1.0
    var mirrorHardness: Double = 1.0
    var mirrorDepth: Double = 0.35
    var mirrorSideFade: Double = 0.5

    var settings: BlurProcessor.Settings {
        .init(blur: blur, brightness: brightness, saturation: saturation,
              contrast: contrast, dither: dither)
    }

    var flowSettings: FlowProcessor.Settings {
        .init(colors: [flowColor0.asCIColor, flowColor1.asCIColor, flowColor2.asCIColor],
              bands: flowBands, amplitude: flowAmplitude, frequency: flowFrequency,
              sharpness: flowSharpness, edgeSoftness: flowEdgeSoftness,
              phase: flowPhase, dither: dither)
    }

    var mirrorSettings: MirrorProcessor.Settings {
        .init(line: mirrorLine, amplitude: mirrorAmplitude, frequency: mirrorFrequency,
              phase: mirrorPhase, hardness: mirrorHardness, depth: mirrorDepth,
              sideFade: mirrorSideFade)
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
    @Published var statusMessage: String? {
        didSet { scheduleStatusDismiss() }
    }

    // Source picking (three-column layout)
    @Published var selectedSource: ImageSource? = .unsplash

    // Local files ("Dateien" source)
    @Published private(set) var recentFiles: [URL] = []

    // Photos library ("Fotos" source)
    @Published var photoAlbums: [PhotoAlbum] = []
    @Published var photosAuthStatus: PHAuthorizationStatus = .notDetermined
    @Published var albumAssets: [PHAsset] = []

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
    private var statusDismissTask: Task<Void, Never>?

    init() {
        accessKey = UserDefaults.standard.string(forKey: Self.keyDefaultsKey) ?? ""
        recentFiles = Self.loadRecentFiles()
        refreshPhotosAuthStatus()
    }

    private func scheduleStatusDismiss() {
        statusDismissTask?.cancel()
        guard statusMessage != nil else { return }
        statusDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if Task.isCancelled { return }
            statusMessage = nil
        }
    }

    // MARK: Key

    var effectiveKey: String {
        let user = accessKey.trimmingCharacters(in: .whitespaces)
        return user.isEmpty ? Self.bundledKey : user
    }
    private var service: UnsplashService { UnsplashService(accessKey: effectiveKey) }

    // MARK: Current look editing

    var effectiveAppearance: Appearance { editing }

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

    // MARK: Source kind (consolidated inspector picker)

    /// The top-level source, derived from / written back to `selectedSource`.
    /// Choosing `.photos` lands on the first available album (or a placeholder
    /// until the library is authorized and albums load).
    var sourceKind: SourceKind {
        get {
            switch selectedSource {
            case .files:            return .files
            case .album:            return .photos
            case .unsplash, .none:  return .unsplash
            }
        }
        set {
            switch newValue {
            case .unsplash: selectedSource = .unsplash
            case .files:    selectedSource = .files
            case .photos:
                if case .album = selectedSource { return }   // already on an album
                if let first = photoAlbums.first {
                    selectedSource = .album(id: first.id, title: first.title)
                } else {
                    selectedSource = .album(id: "", title: "")
                }
            }
        }
    }

    /// Currently selected album id ("" when none), for the album sub-picker.
    var selectedAlbumID: String {
        get { if case let .album(id, _) = selectedSource { return id }; return "" }
        set {
            guard let album = photoAlbums.first(where: { $0.id == newValue }) else { return }
            selectedSource = .album(id: album.id, title: album.title)
        }
    }

    var sourceKindBinding: Binding<SourceKind> {
        Binding(get: { self.sourceKind }, set: { self.sourceKind = $0 })
    }

    var albumBinding: Binding<String> {
        Binding(get: { self.selectedAlbumID }, set: { self.selectedAlbumID = $0 })
    }

    func resetCurrentLook() {
        mutateCurrentLook {
            let d = Look()
            switch $0.style {
            case .flow:
                $0.flowBands = d.flowBands; $0.flowAmplitude = d.flowAmplitude
                $0.flowFrequency = d.flowFrequency; $0.flowSharpness = d.flowSharpness
                $0.flowEdgeSoftness = d.flowEdgeSoftness; $0.flowPhase = d.flowPhase
            case .mirror:
                $0.blur = d.blur; $0.brightness = d.brightness
                $0.saturation = d.saturation; $0.contrast = d.contrast
                $0.mirrorLine = d.mirrorLine; $0.mirrorAmplitude = d.mirrorAmplitude
                $0.mirrorFrequency = d.mirrorFrequency; $0.mirrorPhase = d.mirrorPhase
                $0.mirrorHardness = d.mirrorHardness; $0.mirrorDepth = d.mirrorDepth
                $0.mirrorSideFade = d.mirrorSideFade
            case .blur:
                $0.blur = d.blur; $0.brightness = d.brightness
                $0.saturation = d.saturation; $0.contrast = d.contrast
            }
            $0.dither = d.dither
        }
    }

    /// After a source lands in one appearance, auto-seed the other look if it
    /// has no source yet, so the app is exportable after a single image pick.
    private func seedOtherIfNeeded(from seeded: Appearance) {
        if seeded == .light {
            guard darkLook.source == nil, lightLook.source != nil else { return }
            var d = lightLook
            d.brightness = -0.15; d.saturation = 1.05; d.contrast = 1.05
            darkLook = d
        } else {
            guard lightLook.source == nil, darkLook.source != nil else { return }
            var l = darkLook
            l.brightness = 0; l.saturation = 1.15; l.contrast = 1.0
            lightLook = l
        }
    }

    /// Copies the entire current look (source, style, all parameters) to the
    /// other appearance — the way to make a "static" wallpaper.
    func copyCurrentLookToOther() {
        let src = currentLook
        if effectiveAppearance == .light { darkLook = src } else { lightLook = src }
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
        applySource(cg, photoID: url.path,
                    baseName: url.deletingPathExtension().lastPathComponent,
                    attribution: url.lastPathComponent, attributionURL: nil,
                    to: effectiveAppearance)
        recordRecent(url)
    }

    // MARK: Recent local files ("Dateien" source)

    private static let recentFilesKey = "recentLocalFiles"
    private static let maxRecentFiles = 24

    private static func loadRecentFiles() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        return paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    private func saveRecentFiles() {
        UserDefaults.standard.set(recentFiles.map(\.path), forKey: Self.recentFilesKey)
    }

    private func recordRecent(_ url: URL) {
        var updated = recentFiles.filter { $0.path != url.path }
        updated.insert(url, at: 0)
        if updated.count > Self.maxRecentFiles { updated.removeLast(updated.count - Self.maxRecentFiles) }
        recentFiles = updated
        saveRecentFiles()
    }

    func applySource(_ cg: CGImage, photoID: String?, baseName: String?,
                             attribution: String?, attributionURL: String?, to appearance: Appearance) {
        let palette = Self.extractPalette(from: cg)
        let apply: (inout Look) -> Void = {
            $0.source = cg; $0.photoID = photoID; $0.baseName = baseName
            $0.attribution = attribution; $0.attributionURL = attributionURL
            $0.flowColor0 = palette[0]; $0.flowColor1 = palette[1]; $0.flowColor2 = palette[2]
        }
        if appearance == .light { apply(&lightLook) } else { apply(&darkLook) }
        seedOtherIfNeeded(from: appearance)
        renderPreview()
    }

    /// Re-derive the Flow palette from the current look's photo.
    func reloadPaletteFromPhoto() {
        guard let src = currentLook.source else { return }
        let palette = Self.extractPalette(from: src)
        mutateCurrentLook {
            $0.flowColor0 = palette[0]; $0.flowColor1 = palette[1]; $0.flowColor2 = palette[2]
        }
    }

    /// Three dominant colours (bottom → top thirds), saturation-boosted so the
    /// Flow gradient stays vivid.
    private static func extractPalette(from cg: CGImage) -> [Color] {
        let ci = CIImage(cgImage: cg)
        let e = ci.extent
        let third = e.height / 3
        let rects = [
            CGRect(x: e.minX, y: e.minY, width: e.width, height: third),
            CGRect(x: e.minX, y: e.minY + third, width: e.width, height: third),
            CGRect(x: e.minX, y: e.minY + 2 * third, width: e.width, height: third),
        ]
        return rects.map { rect in
            let avg = FlowProcessor.averageColor(of: ci, in: rect)
            return Color.vivid(from: avg)
        }
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
        let size = previewTargetSize()
        guard let cg = renderCG(currentLook, size: size, deep: false) else { preview = nil; return }
        preview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Renders a look with its selected style; nil if a photo-based style has no source.
    private func renderCG(_ look: Look, size: CGSize, deep: Bool) -> CGImage? {
        switch look.style {
        case .blur:
            guard let src = look.source else { return nil }
            return BlurProcessor.render(source: src, targetSize: size, settings: look.settings, deepColor: deep)
        case .flow:
            return FlowProcessor.render(size: size, settings: look.flowSettings, deepColor: deep)
        case .mirror:
            guard let src = look.source,
                  let base = BlurProcessor.processedImage(source: src, targetSize: size, settings: look.settings)
            else { return nil }
            let folded = MirrorProcessor.apply(to: base, size: size, settings: look.mirrorSettings)
            return BlurProcessor.finalize(folded, size: size, dither: look.dither, deepColor: deep)
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
        if look.style != .flow, look.source == nil { throw ExportError.noSource }
        let s = pixelSize
        guard let cg = renderCG(look, size: CGSize(width: s.width, height: s.height), deep: true) else {
            throw ExportError.renderFailed
        }
        return cg
    }

    // MARK: File names

    func lookHasContent(_ l: Look) -> Bool { l.style == .flow || l.source != nil }

    var canExport: Bool {
        lookHasContent(lightLook) && lookHasContent(darkLook)
    }

    func exportFileName(ext: String) -> String {
        let s = pixelSize
        let base = lightLook.baseName ?? "blur-wallpaper"
        return "\(base)-dynamic-\(s.width)x\(s.height).\(ext)"
    }

    func writeOutput(to url: URL) throws {
        let l = try renderFull(lightLook)
        let d = try renderFull(darkLook)
        try DynamicWallpaper.writeHEIC(light: l, dark: d, to: url)
    }

    // MARK: Export (save panel)

    func exportWithPanel() {
        let panel = NSSavePanel()
        let ext = "heic"
        panel.allowedContentTypes = [.heic]
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
            // macOS 26 stores an *absolute path per Space and per Display* in the
            // WallpaperAgent index. A fresh random filename each time (plus deleting
            // the previous export) leaves every other Space pointing at a file that
            // no longer exists — so the wallpaper vanishes on Space/Display switch and
            // System Settings shows a broken "?" thumbnail. Use one stable path that
            // every Space can keep referencing, and update it in place instead.
            let url = dir.appendingPathComponent("current.heic")
            let tmp = dir.appendingPathComponent("current.heic.tmp")
            try? FileManager.default.removeItem(at: tmp)
            try writeOutput(to: tmp)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }

            // One-time cleanup of the old buggy exports (current-<uuid>.heic).
            if let existing = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for f in existing where f.lastPathComponent.hasPrefix("current-") {
                    try? FileManager.default.removeItem(at: f)
                }
            }

            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
            // The path is unchanged across sets, so the agent caches the old pixels.
            // Restart it so it re-reads current.heic and repaints every Space.
            Self.reloadWallpaperAgent()
            statusMessage = "Als dynamisches Wallpaper gesetzt."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Force the wallpaper agent to reload from disk. `setDesktopImageURL` caches
    /// by file path, so overwriting the same `current.heic` won't repaint on its
    /// own; launchd respawns the agent immediately after it's killed.
    static func reloadWallpaperAgent() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        proc.arguments = ["WallpaperAgent"]
        // Only wait if the process actually launched; run() throwing means it never did.
        if (try? proc.run()) != nil {
            proc.waitUntilExit()
        }
    }

    // MARK: Drag & drop (reliable file-backed provider)

    func makeDragProvider() -> NSItemProvider {
        do {
            // Render synchronously now so the file exists before the drop resolves.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(exportFileName(ext: "heic"))
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
