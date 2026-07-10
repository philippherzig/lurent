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
        case .unsplash: return L("Unsplash")
        case .files:    return L("Dateien")
        case .photos:   return L("Fotos")
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
}

// MARK: - Resolution presets

struct ResolutionPreset: Identifiable, Hashable {
    let name: String
    let width: Int
    let height: Int
    var id: String { name }
    var isCustom: Bool { width == 0 && height == 0 }
    /// Localized name for display; product-size presets stay verbatim, only the
    /// "custom size" entry is translated. (`name` remains the stable identity.)
    var displayName: String { isCustom ? L("Eigene Größe…") : name }

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
    var label: String { self == .light ? L("Hell") : L("Dunkel") }
    var other: Appearance { self == .light ? .dark : .light }
}

enum WallpaperStyle: String, CaseIterable, Identifiable {
    case blur, flow, liquid, dune, mirror
    var id: String { rawValue }
    var label: String {
        switch self {
        case .blur:   return L("Blur")
        case .flow:   return L("Flow")
        case .liquid: return L("Liquid")
        case .dune:   return L("Dune")
        case .mirror: return L("Spiegel")
        }
    }

    /// Styles that synthesize the image from parameters alone (no source photo).
    var isSynthetic: Bool { self == .flow || self == .liquid || self == .dune }
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

    // Liquid style (domain-warped turbulence gradient — heart.zuerich look)
    var liquidColor0: Color = Color(red: 0.00, green: 0.04, blue: 0.08) // deep navy  #000a14
    var liquidColor1: Color = Color(red: 0.78, green: 0.25, blue: 1.00) // purple     #c841ff
    var liquidColor2: Color = Color(red: 0.81, green: 0.00, blue: 0.43) // magenta    #cf006e
    var liquidColor3: Color = Color(red: 1.00, green: 0.00, blue: 0.30) // pink-red   #ff004d
    var liquidColor4: Color = Color(red: 1.00, green: 0.24, blue: 0.00) // orange     #ff3c00
    var liquidCount: Int = 5
    var liquidTime: Double = 6.0
    var liquidSeed: Double = 3.0
    var liquidScale: Double = 0.0   // zoom above a calm base (see liquidSettings)
    var liquidTurb: Double = 0.0    // 0 = smooth satin bands, higher = liquid churn
    var liquidWave: Double = 1.0
    var liquidBias: Double = 0.0

    // Dune style (Big Sur–style flowing gradient: warped multi-stop ramp)
    var duneColor0: Color = Color(red: 0.45, green: 0.16, blue: 0.62) // purple
    var duneColor1: Color = Color(red: 1.00, green: 0.15, blue: 0.45) // magenta/pink
    var duneColor2: Color = Color(red: 1.00, green: 0.42, blue: 0.20) // orange-red
    var duneColor3: Color = Color(red: 1.00, green: 0.80, blue: 0.30) // golden yellow
    var duneColor4: Color = Color(red: 0.20, green: 0.62, blue: 0.95) // sky blue
    var duneCount: Int = 5
    var duneTilt: Double = 0.42
    var duneAmplitude: Double = 0.12
    var duneFrequency: Double = 1.05
    var duneSharpness: Double = 0.9
    var duneShading: Double = 0.65
    var duneSoftness: Double = 0.005
    var dunePhase: Double = 0.5

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
              phase: flowPhase, brightness: brightness, saturation: saturation,
              contrast: contrast, dither: dither)
    }

    var liquidSettings: LiquidProcessor.Settings {
        .init(colors: [liquidColor0.asCIColor, liquidColor1.asCIColor, liquidColor2.asCIColor,
                       liquidColor3.asCIColor, liquidColor4.asCIColor],
              count: liquidCount, time: liquidTime, seed: liquidSeed,
              // Slider sits at 0 for a calm base zoom; higher values zoom in.
              scale: 0.5 + liquidScale, turbAmp: liquidTurb, waveFreq: liquidWave,
              bias: liquidBias, brightness: brightness, saturation: saturation,
              contrast: contrast, dither: dither)
    }

    var duneSettings: DuneProcessor.Settings {
        .init(colors: [duneColor0.asCIColor, duneColor1.asCIColor, duneColor2.asCIColor,
                       duneColor3.asCIColor, duneColor4.asCIColor],
              count: duneCount, tilt: duneTilt, amplitude: duneAmplitude,
              frequency: duneFrequency, sharpness: duneSharpness, shading: duneShading,
              softness: duneSoftness, phase: dunePhase,
              brightness: brightness, saturation: saturation,
              contrast: contrast, dither: dither)
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
        case .noSource:     return L("Kein Quellbild ausgewählt.")
        case .renderFailed: return L("Das Wallpaper konnte nicht gerendert werden.")
        case .encodeFailed: return L("Das Bild konnte nicht kodiert werden.")
        }
    }
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    /// Bundled Unsplash key (injected at build time from .env via
    /// Secrets.generated.swift) so search works out of the box; empty if no .env
    /// was present. This is the only key the app uses — there is no user override.
    static let bundledKey = Secrets.unsplashKey

    // Search
    @Published var query: String = ""
    @Published var results: [UnsplashPhoto] = []
    @Published var isSearching = false
    @Published var isLoadingSource = false
    @Published var errorMessage: String?
    @Published var statusMessage: String? {
        didSet { scheduleStatusDismiss() }
    }

    // Source picking. `lastAlbumID` remembers the chosen album so switching the
    // source away from Photos and back restores it instead of jumping to the first.
    @Published var selectedSource: ImageSource? = .unsplash {
        didSet {
            if case let .album(id, _) = selectedSource, !id.isEmpty { lastAlbumID = id }
        }
    }
    private var lastAlbumID: String?

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

    private var service: UnsplashService { UnsplashService(accessKey: Self.bundledKey) }

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
                let remembered = lastAlbumID.flatMap { id in photoAlbums.first(where: { $0.id == id }) }
                if let album = remembered ?? photoAlbums.first {
                    selectedSource = .album(id: album.id, title: album.title)
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
        Binding(
            get: {
                // Fall back to the first album while `selectedAlbumID` is still the
                // empty placeholder (albums just loaded) so the Picker always has a
                // matching tag — avoids SwiftUI's "selection does not match any tag".
                let current = self.selectedAlbumID
                if self.photoAlbums.contains(where: { $0.id == current }) { return current }
                return self.photoAlbums.first?.id ?? current
            },
            set: { self.selectedAlbumID = $0 }
        )
    }

    func resetCurrentLook() {
        mutateCurrentLook {
            let d = Look()
            switch $0.style {
            case .blur:
                $0.blur = d.blur
            case .flow:
                $0.flowBands = d.flowBands; $0.flowAmplitude = d.flowAmplitude
                $0.flowFrequency = d.flowFrequency; $0.flowSharpness = d.flowSharpness
                $0.flowEdgeSoftness = d.flowEdgeSoftness; $0.flowPhase = d.flowPhase
            case .liquid:
                $0.liquidCount = d.liquidCount; $0.liquidTime = d.liquidTime
                $0.liquidSeed = d.liquidSeed; $0.liquidScale = d.liquidScale
                $0.liquidTurb = d.liquidTurb; $0.liquidWave = d.liquidWave
                $0.liquidBias = d.liquidBias
            case .dune:
                $0.duneCount = d.duneCount; $0.duneTilt = d.duneTilt
                $0.duneAmplitude = d.duneAmplitude; $0.duneFrequency = d.duneFrequency
                $0.duneSharpness = d.duneSharpness; $0.duneShading = d.duneShading
                $0.duneSoftness = d.duneSoftness; $0.dunePhase = d.dunePhase
            case .mirror:
                $0.blur = d.blur
                $0.mirrorLine = d.mirrorLine; $0.mirrorAmplitude = d.mirrorAmplitude
                $0.mirrorFrequency = d.mirrorFrequency; $0.mirrorPhase = d.mirrorPhase
                $0.mirrorHardness = d.mirrorHardness; $0.mirrorDepth = d.mirrorDepth
                $0.mirrorSideFade = d.mirrorSideFade
            }
            // Colour grade + grain: shared across every style.
            $0.brightness = d.brightness; $0.saturation = d.saturation
            $0.contrast = d.contrast; $0.dither = d.dither
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

    // MARK: Initial load

    private var didLoadInitial = false

    /// On first launch, fill the Unsplash picker with a few popular wallpaper
    /// photos and auto-select the first one (Blur style) so the app opens on a
    /// real preview instead of the empty state. No-ops if the user already picked
    /// an image, switched away from Unsplash, or if there's no bundled key / network.
    func loadInitialPhotosIfNeeded() {
        guard !didLoadInitial else { return }
        didLoadInitial = true
        guard selectedSource == .unsplash, results.isEmpty, lightLook.source == nil else { return }

        isSearching = true
        Task {
            defer { isSearching = false }
            do {
                let photos = try await service.topicPhotos()
                // Bail if the user started interacting while the request was in flight.
                guard selectedSource == .unsplash, results.isEmpty, lightLook.source == nil,
                      let first = photos.first else { return }
                results = photos
                select(first)
            } catch {
                // Startup convenience — stay silent so a missing key or offline
                // launch just falls back to the empty state, no error alert.
            }
        }
    }

    // MARK: Search

    func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Clearing the field (e.g. the search field's native clear button) runs
        // this with an empty query — drop stale results instead of leaving them.
        guard !q.isEmpty else { results = []; errorMessage = nil; return }
        isSearching = true
        errorMessage = nil
        Task {
            defer { isSearching = false }
            do {
                results = try await service.search(query: q)
                if results.isEmpty { errorMessage = L("Keine Treffer für „%@“.", q) }
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
            errorMessage = L("Bild konnte nicht geladen werden: %@", url.lastPathComponent)
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
        let flow = Self.extractPalette(from: cg, count: 3)
        let liquid = Self.extractPalette(from: cg, count: 5, sortedByLuminance: true)
        let apply: (inout Look) -> Void = {
            $0.source = cg; $0.photoID = photoID; $0.baseName = baseName
            $0.attribution = attribution; $0.attributionURL = attributionURL
            if flow.count == 3 {
                $0.flowColor0 = flow[0]; $0.flowColor1 = flow[1]; $0.flowColor2 = flow[2]
            }
            if liquid.count == 5 {
                $0.liquidColor0 = liquid[0]; $0.liquidColor1 = liquid[1]; $0.liquidColor2 = liquid[2]
                $0.liquidColor3 = liquid[3]; $0.liquidColor4 = liquid[4]
                // Dune shares the dark→bright directional ramp.
                $0.duneColor0 = liquid[0]; $0.duneColor1 = liquid[1]; $0.duneColor2 = liquid[2]
                $0.duneColor3 = liquid[3]; $0.duneColor4 = liquid[4]
            }
        }
        if appearance == .light { apply(&lightLook) } else { apply(&darkLook) }
        seedOtherIfNeeded(from: appearance)
        renderPreview()
    }

    /// Re-derive the Flow palette from the current look's photo.
    func reloadPaletteFromPhoto() {
        guard let src = currentLook.source else { return }
        let palette = Self.extractPalette(from: src, count: 3)
        guard palette.count == 3 else { return }
        mutateCurrentLook {
            $0.flowColor0 = palette[0]; $0.flowColor1 = palette[1]; $0.flowColor2 = palette[2]
        }
    }

    /// Re-derive the Liquid palette (5 stops, dark → bright) from the current photo.
    func reloadLiquidPaletteFromPhoto() {
        guard let src = currentLook.source else { return }
        let p = Self.extractPalette(from: src, count: 5, sortedByLuminance: true)
        guard p.count == 5 else { return }
        mutateCurrentLook {
            $0.liquidColor0 = p[0]; $0.liquidColor1 = p[1]; $0.liquidColor2 = p[2]
            $0.liquidColor3 = p[3]; $0.liquidColor4 = p[4]
        }
    }

    /// Re-derive the Dune palette (5 stops, dark → bright) from the current photo.
    func reloadDunePaletteFromPhoto() {
        guard let src = currentLook.source else { return }
        let p = Self.extractPalette(from: src, count: 5, sortedByLuminance: true)
        guard p.count == 5 else { return }
        mutateCurrentLook {
            $0.duneColor0 = p[0]; $0.duneColor1 = p[1]; $0.duneColor2 = p[2]
            $0.duneColor3 = p[3]; $0.duneColor4 = p[4]
        }
    }

    /// A *curated* palette from a photo, tuned to read **bright, clean and
    /// friendly** rather than dark and earthy — a faithful strip-average of an
    /// earthy landscape only ever yields muddy browns.
    ///
    /// It reads the image's dominant **hues** (an earthy brown is just a
    /// desaturated orange; a hazy mountain is really only blue + a warm accent),
    /// then renders each as a clean, vivid, light stop. If the photo has too few
    /// distinct hues, the remaining stops are filled with **harmonious** hues
    /// derived from the dominant one — a full, cohesive palette instead of the same
    /// muted colour twice. A strong bright-neutral presence (clouds, haze, snow)
    /// adds one airy near-white accent. `sortedByLuminance` orders the stops
    /// dark → bright (Liquid/Dune ramp); otherwise by hue (Flow).
    private static func extractPalette(from cg: CGImage, count: Int,
                                       sortedByLuminance: Bool = false) -> [Color] {
        guard count > 0 else { return [] }
        let pixels = downsampledPixels(from: cg, maxDim: 64)
        var hues = dominantHues(pixels)
        if hues.isEmpty { hues = [(h: 0.58, s: 0.6, w: 1)] }        // fallback: friendly blue

        // Reserve one slot for an airy near-white when the image is cloudy / hazy.
        let airy = brightNeutralShare(pixels) > 0.06
        let hueSlots = max(airy ? count - 1 : count, 1)

        // Fill harmonically from the dominant hue when the photo has too few.
        let base = hues[0].h
        let offsets = [0.083, -0.083, 0.5, 0.166, -0.166, 0.25, -0.25, 0.33, -0.33, 0.417]
        var oi = 0
        while hues.count < hueSlots && oi < offsets.count {
            var h = (base + offsets[oi]).truncatingRemainder(dividingBy: 1); if h < 0 { h += 1 }
            if hues.allSatisfy({ hueDistance($0.h, h) > 0.075 }) { hues.append((h: h, s: 0.62, w: 0.3)) }
            oi += 1
        }
        hues = Array(hues.prefix(hueSlots))

        // Render each hue clean, vivid and bright (keeping a little of its own sat).
        var stops: [(Double, Double, Double)] = []
        let n = max(hues.count, 1)
        for (i, hs) in hues.enumerated() {
            let t = n > 1 ? Double(i) / Double(n - 1) : 0.5
            let s = min(0.9, max(0.5, hs.s + (0.74 - hs.s) * 0.6))
            let v = 0.80 + 0.17 * t                                // all bright; gentle range
            stops.append(rgb(fromHue: hs.h, sat: s, bri: v))
        }
        if airy { stops.append(rgb(fromHue: hues.first?.h ?? 0.6, sat: 0.06, bri: 0.98)) }
        while stops.count < count, let last = stops.last { stops.append(last) }
        stops = Array(stops.prefix(count))

        if sortedByLuminance {
            stops.sort { luminance($0) < luminance($1) }
        } else {
            stops.sort { hsb(fromR: $0.0, g: $0.1, b: $0.2).0 < hsb(fromR: $1.0, g: $1.1, b: $1.2).0 }
        }
        return stops.map { Color(red: $0.0, green: $0.1, blue: $0.2) }
    }

    /// Draws the source into a small RGB bitmap and returns its opaque pixels as
    /// (r, g, b) in 0…1 — a fast, representative sample of the whole image.
    private static func downsampledPixels(from cg: CGImage, maxDim: Int) -> [(Double, Double, Double)] {
        let w0 = cg.width, h0 = cg.height
        guard w0 > 0, h0 > 0 else { return [] }
        let scale = Double(maxDim) / Double(max(w0, h0))
        let w = max(1, Int(Double(w0) * scale)), h = max(1, Int(Double(h0) * scale))
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        c.interpolationQuality = .medium
        c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var out: [(Double, Double, Double)] = []
        out.reserveCapacity(w * h)
        var i = 0
        while i < buf.count {
            if buf[i + 3] > 127 {
                out.append((Double(buf[i]) / 255, Double(buf[i + 1]) / 255, Double(buf[i + 2]) / 255))
            }
            i += 4
        }
        return out
    }

    /// The image's distinct dominant **hues**, most prominent first. Builds a
    /// vibrance-weighted (s·v) hue histogram over the chromatic pixels, then greedily
    /// takes the heaviest bin and suppresses its neighbours within ~36°, so one hue
    /// family can't claim several slots. Returns (hue, representative saturation, weight).
    private static func dominantHues(_ pixels: [(Double, Double, Double)]) -> [(h: Double, s: Double, w: Double)] {
        let bins = 36
        var wsum = [Double](repeating: 0, count: bins), ssum = wsum
        for (r, g, b) in pixels {
            let (h, s, v) = hsb(fromR: r, g: g, b: b)
            if s < 0.12 || v < 0.12 { continue }          // only chromatic pixels vote on hue
            let bi = min(bins - 1, Int(h * Double(bins)))
            let wt = s * v
            wsum[bi] += wt; ssum[bi] += s * wt
        }
        var idx = (0..<bins).filter { wsum[$0] > 0 }.sorted { wsum[$0] > wsum[$1] }
        var out: [(h: Double, s: Double, w: Double)] = []
        while let bi = idx.first {
            let h = (Double(bi) + 0.5) / Double(bins)
            out.append((h: h, s: ssum[bi] / max(wsum[bi], 1e-9), w: wsum[bi]))
            idx.removeAll { hueDistance((Double($0) + 0.5) / Double(bins), h) < 0.10 }
        }
        return out
    }

    /// Fraction of pixels that are bright and near-neutral (clouds / haze / snow) —
    /// decides whether the palette gets an airy near-white accent.
    private static func brightNeutralShare(_ pixels: [(Double, Double, Double)]) -> Double {
        guard !pixels.isEmpty else { return 0 }
        var n = 0
        for (r, g, b) in pixels {
            let (_, s, v) = hsb(fromR: r, g: g, b: b)
            if s < 0.14 && v > 0.72 { n += 1 }
        }
        return Double(n) / Double(pixels.count)
    }

    /// Circular distance between two hues on the 0…1 wheel (0…0.5).
    private nonisolated static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b); return d > 0.5 ? 1 - d : d
    }

    /// Rec. 709 luminance of an (r, g, b) tuple.
    private nonisolated static func luminance(_ c: (Double, Double, Double)) -> Double {
        0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
    }

    /// RGB (0…1) → HSB (0…1).
    private nonisolated static func hsb(fromR r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 1e-6 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6; if h < 0 { h += 1 }
        }
        return (h, mx <= 1e-6 ? 0 : d / mx, mx)
    }

    /// HSB (0…1) → RGB (0…1), for luminance ordering.
    private nonisolated static func rgb(fromHue h: Double, sat s: Double, bri b: Double) -> (Double, Double, Double) {
        if s <= 1e-6 { return (b, b, b) }
        let i = floor(h * 6), f = h * 6 - i
        let p = b * (1 - s), q = b * (1 - s * f), t = b * (1 - s * (1 - f))
        switch Int(i) % 6 {
        case 0: return (b, t, p); case 1: return (q, b, p); case 2: return (p, b, t)
        case 3: return (p, q, b); case 4: return (t, p, b); default: return (b, p, q)
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
        case .liquid:
            return LiquidProcessor.render(size: size, settings: look.liquidSettings, deepColor: deep)
        case .dune:
            return DuneProcessor.render(size: size, settings: look.duneSettings, deepColor: deep)
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
        if !look.style.isSynthetic, look.source == nil { throw ExportError.noSource }
        let s = pixelSize
        guard let cg = renderCG(look, size: CGSize(width: s.width, height: s.height), deep: true) else {
            throw ExportError.renderFailed
        }
        return cg
    }

    // MARK: File names

    func lookHasContent(_ l: Look) -> Bool { l.style.isSynthetic || l.source != nil }

    var canExport: Bool {
        lookHasContent(lightLook) && lookHasContent(darkLook)
    }

    func exportFileName(ext: String) -> String {
        let s = pixelSize
        let base = lightLook.baseName ?? "lurent-wallpaper"
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
                    self.statusMessage = L("Exportiert: %@", url.lastPathComponent)
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
            // macOS 26 keeps an *absolute path per Space and per Display* in the
            // WallpaperAgent index, and the agent caches by path — setting the same
            // URL again won't repaint. The previous approach forced a repaint by
            // killing the WallpaperAgent, but `setDesktopImageURL` persists to the
            // agent's store *asynchronously*: killing it right after races that write,
            // so the agent respawns onto the previous wallpaper (flicker → snaps back,
            // to the "all Spaces" system wallpaper when one is active).
            //
            // Instead alternate between two stable files. Each set presents a NEW path
            // (so it repaints without a kill), while BOTH files always exist — so any
            // other Space/Display keeps resolving its reference after a switch.
            let slotA = dir.appendingPathComponent("wallpaper-a.heic")
            let slotB = dir.appendingPathComponent("wallpaper-b.heic")
            let shown = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
            let target = (shown?.lastPathComponent == slotA.lastPathComponent) ? slotB : slotA

            let tmp = target.appendingPathExtension("tmp")
            try? FileManager.default.removeItem(at: tmp)
            try writeOutput(to: tmp)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: target)
            }

            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(target, for: screen, options: [:])
            }
            statusMessage = L("Als dynamisches Wallpaper gesetzt.")
        } catch {
            errorMessage = error.localizedDescription
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
        let dir = base.appendingPathComponent("Lurent", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
