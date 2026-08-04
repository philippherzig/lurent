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

/// The wallpaper is rendered as one oversized **square** master and applied to every
/// display with aspect-fill center-cropping (see `setAsDesktop`). macOS scales that
/// single file down per screen, so it yields native resolution in *any* orientation —
/// landscape and portrait alike — on every display whose longest edge is ≤ this value.
/// 6016 is Apple's largest current panel dimension (Pro Display XDR), so this covers
/// the whole lineup. Going bigger only wastes pixels macOS discards; smaller would
/// upscale on the largest displays. This is why there is no resolution picker: one
/// universal size is correct for all screens.
let wallpaperMasterSide = 6016

// MARK: - Appearance

enum Appearance: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var label: String { self == .light ? L("Hell") : L("Dunkel") }
    var other: Appearance { self == .light ? .dark : .light }
}

enum WallpaperStyle: String, CaseIterable, Identifiable {
    case blur, liquid, mirror, slices
    var id: String { rawValue }
    var label: String {
        switch self {
        case .blur:   return L("Blur")
        case .liquid: return L("Liquid")
        case .mirror: return L("Spiegel")
        case .slices: return L("Lamellen")
        }
    }

    /// Styles that synthesize the image from parameters alone (no source photo).
    var isSynthetic: Bool { self == .liquid }
}

/// One draggable palette stop shown on the source photo: where it samples from,
/// the colour it currently holds, and a short label. Built on demand from the
/// current look; `id` is the absolute colour-slot index within the style.
struct PaletteStop: Identifiable {
    let id: Int
    var point: CGPoint      // normalised 0…1, y from top
    var color: Color
    var label: String
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
    var blurOffset: Double = 0    // −1…1: which square slice of the source to use (0 = centre)
    var brightness: Double = 0
    var saturation: Double = 1.0
    var contrast: Double = 1.0
    var hue: Double = 0           // global hue rotation (radians); 0 = neutral
    var dither: Double = 0        // shared grain; off by default (16-bit export avoids banding)

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

    // Mirror style (builds on the blur controls)
    var mirrorLine: Double = 0.52
    var mirrorAmplitude: Double = 0.05
    var mirrorFrequency: Double = 0.75      // lower default → longer waves
    var mirrorPhase: Double = 1.0
    var mirrorIrregularity: Double = 0.6    // 0 = pure sine, 1 = organic curve
    var mirrorHardness: Double = 1.0
    var mirrorDepth: Double = 0.35
    var mirrorSideFade: Double = 0.5

    // Slices style ("Lamellen") — cuts the blur into bands and slides each by a
    // different amount, so a smooth gradient becomes a rhythmic sliced composition.
    // `fan` bends the bands into wedges (bouquet), `curve` bows them into arcs.
    // Defaults sit in the calibrated sweet spot: a gentle diagonal with slightly
    // softened seams reads like brushed satin; angle 0 + edge 0 gives hard slats.
    var sliceCount: Double = 14
    var sliceAngle: Double = 0.35     // 0 = vertical bands
    var sliceShift: Double = 0.4
    var sliceFan: Double = 0          // 0 = parallel, 1 = fanned out like a bouquet
    var sliceCurve: Double = 0        // −1…1 bend of the bands; 0 = straight
    var sliceSeed: Double = 1

    // Palette sample points — normalised (0…1, y from top) positions on `source`
    // that each colour stop is sampled from. One point per stop, aligned 1:1 with the
    // colour slots above; dragged directly on the photo in the inspector. Photo-less
    // styles keep the stored colours instead.
    var liquidPoints: [CGPoint] = [CGPoint(x: 0.12, y: 0.74), CGPoint(x: 0.32, y: 0.52), CGPoint(x: 0.50, y: 0.34), CGPoint(x: 0.70, y: 0.52), CGPoint(x: 0.88, y: 0.70)]

    // Colour-slot setters (write a stop by index into the flat stored properties).
    mutating func setLiquidColor(_ i: Int, _ c: Color) {
        switch i { case 0: liquidColor0 = c; case 1: liquidColor1 = c; case 2: liquidColor2 = c
                   case 3: liquidColor3 = c; default: liquidColor4 = c }
    }

    var settings: BlurProcessor.Settings {
        .init(blur: blur, brightness: brightness, saturation: saturation,
              contrast: contrast, dither: dither, hue: hue, offset: blurOffset)
    }

    var liquidSettings: LiquidProcessor.Settings {
        // Colours are stored dark → bright; when fewer than 5 are active, keep the
        // BRIGHTEST `count` (drop the darker stops), matching the light aesthetic.
        let all = [liquidColor0, liquidColor1, liquidColor2, liquidColor3, liquidColor4]
        return .init(colors: all.suffix(liquidCount).map(\.asCIColor),
              count: liquidCount, time: liquidTime, seed: liquidSeed,
              // Slider sits at 0 for a calm base zoom; higher values zoom in.
              scale: 0.5 + liquidScale, turbAmp: liquidTurb, waveFreq: liquidWave,
              bias: liquidBias, brightness: brightness, saturation: saturation,
              contrast: contrast, dither: dither, hue: hue)
    }

    var mirrorSettings: MirrorProcessor.Settings {
        .init(line: mirrorLine, amplitude: mirrorAmplitude, frequency: mirrorFrequency,
              phase: mirrorPhase, irregular: mirrorIrregularity, hardness: mirrorHardness,
              depth: mirrorDepth, sideFade: mirrorSideFade)
    }

    var sliceSettings: SliceProcessor.Settings {
        .init(count: sliceCount, angle: sliceAngle, shift: sliceShift,
              fan: sliceFan, curve: sliceCurve, seed: sliceSeed)
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

    // Looks. Any write here is a change to the open project, so it schedules a save.
    @Published var lightLook = Look() { didSet { scheduleAutosave() } }
    @Published var darkLook = Look(brightness: -0.15, saturation: 1.0, contrast: 1.05) {
        didSet { scheduleAutosave() }
    }

    // Output preview. `previewGeneration` ticks on every render so views that want to
    // follow the live editor (the selected rail tile) have something to key off.
    @Published private(set) var preview: NSImage?
    @Published private(set) var previewGeneration = 0

    // The collection (left rail) and the project currently open in the editor.
    @Published private(set) var projects: [Project] = []
    @Published private(set) var selectedProjectID: String?

    /// Which project's render is on the desktop right now. Only meaningful within a
    /// session — the desktop can be changed from anywhere.
    @Published private(set) var activeProjectID: String?

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    private var renderTask: Task<Void, Never>?
    private var statusDismissTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?

    /// Set while a project is being read into the looks. Without it the assignments
    /// below would trip `didSet` and immediately write the project back over itself.
    private var isLoadingProject = false

    private static let lastOpenProjectKey = "lastOpenProjectID"

    init() {
        recentFiles = Self.loadRecentFiles()
        refreshPhotosAuthStatus()
        WallpaperLibrary.migrate()
        projects = WallpaperLibrary.load()

        // Reopen where the user left off; fall back to the newest project, or start
        // the collection off with one if this is a first run.
        let remembered = UserDefaults.standard.string(forKey: Self.lastOpenProjectKey)
        if let project = projects.first(where: { $0.id == remembered }) ?? projects.first {
            open(project)
        } else {
            try? createFirstProject()
        }
    }

    /// The collection is empty (first run, or the user deleted everything) — there is
    /// always exactly one project open, so make one.
    private func createFirstProject() throws {
        let project = try WallpaperLibrary.create(slug: nil)
        refreshProjects()
        selectedProjectID = project.id
        UserDefaults.standard.set(project.id, forKey: Self.lastOpenProjectKey)
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

    /// Binding for an `Int` field exposed through a `Double` slider (rounds on set).
    func bindInt(_ keyPath: WritableKeyPath<Look, Int>) -> Binding<Double> {
        Binding(
            get: { Double(self.currentLook[keyPath: keyPath]) },
            set: { newValue in self.mutateCurrentLook { $0[keyPath: keyPath] = Int(newValue.rounded()) } }
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
            case .liquid:
                $0.liquidCount = d.liquidCount; $0.liquidTime = d.liquidTime
                $0.liquidSeed = d.liquidSeed; $0.liquidScale = d.liquidScale
                $0.liquidTurb = d.liquidTurb; $0.liquidWave = d.liquidWave
                $0.liquidBias = d.liquidBias
            case .mirror:
                $0.blur = d.blur
                $0.mirrorLine = d.mirrorLine; $0.mirrorAmplitude = d.mirrorAmplitude
                $0.mirrorFrequency = d.mirrorFrequency; $0.mirrorPhase = d.mirrorPhase
                $0.mirrorIrregularity = d.mirrorIrregularity
                $0.mirrorHardness = d.mirrorHardness; $0.mirrorDepth = d.mirrorDepth
                $0.mirrorSideFade = d.mirrorSideFade
            case .slices:
                $0.blur = d.blur
                $0.sliceCount = d.sliceCount; $0.sliceAngle = d.sliceAngle
                $0.sliceShift = d.sliceShift; $0.sliceFan = d.sliceFan
                $0.sliceCurve = d.sliceCurve; $0.sliceSeed = d.sliceSeed
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
            d.brightness = -0.15; d.saturation = 1.0; d.contrast = 1.05
            darkLook = d
        } else {
            guard lightLook.source == nil, darkLook.source != nil else { return }
            var l = darkLook
            l.brightness = 0; l.saturation = 1.0; l.contrast = 1.0
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
        (wallpaperMasterSide, wallpaperMasterSide)
    }

    // MARK: Initial load

    private var didLoadInitial = false

    /// Fills the Unsplash picker with a few popular wallpaper photos so the app opens
    /// on something to click rather than an empty grid. No-ops if the user already
    /// searched, switched away from Unsplash, or if there's no bundled key / network.
    ///
    /// Deliberately does **not** select a photo: with autosave, writing a random photo
    /// into the reopened project on every launch would quietly rewrite the user's
    /// work. Auto-selection now only happens for a freshly created empty project,
    /// via `loadRandomStarterPhoto`.
    func loadInitialPhotosIfNeeded() {
        guard !didLoadInitial else { return }
        didLoadInitial = true
        guard selectedSource == .unsplash, results.isEmpty else { return }
        loadStarterPhotos(select: lightLook.source == nil && selectedProject?.recipe != nil)
    }

    /// Gives a brand-new project a picture to start from.
    func loadRandomStarterPhoto() {
        loadStarterPhotos(select: true)
    }

    private func loadStarterPhotos(select shouldSelect: Bool) {
        isSearching = true
        let projectID = selectedProjectID
        Task {
            defer { isSearching = false }
            do {
                // Pull a RANDOM shallow page of the curated "wallpapers" topic so the
                // picker isn't the identical top-12 on every launch. Staying within the
                // first few popular pages keeps quality high while rotating the set.
                let photos = try await service.topicPhotos(page: Int.random(in: 1...10))
                if results.isEmpty, selectedSource == .unsplash { results = photos }
                // Bail if the user started interacting, or switched project, while the
                // request was in flight — otherwise this lands in the wrong project.
                guard shouldSelect, selectedProjectID == projectID,
                      lightLook.source == nil, let pick = photos.randomElement() else { return }
                select(pick)
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
            return WallpaperLibrary.slugify(alt) + "-" + photo.id
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
        // Every palette colour is sampled straight from the photo at the look's
        // sample points (the "Farbtupfer" the user then drags in the inspector).
        let apply: (inout Look) -> Void = {
            $0.source = cg; $0.photoID = photoID; $0.baseName = baseName
            $0.attribution = attribution; $0.attributionURL = attributionURL
            Self.resampleColors(&$0, from: cg)
        }
        if appearance == .light { apply(&lightLook) } else { apply(&darkLook) }
        seedOtherIfNeeded(from: appearance)
        renderPreview()
    }

    /// The palette stops the current style/appearance exposes for photo-pointer
    /// editing, in display order (active stops only).
    var activePaletteStops: [PaletteStop] {
        let l = currentLook
        switch l.style {
        case .liquid:
            let cols = [l.liquidColor0, l.liquidColor1, l.liquidColor2, l.liquidColor3, l.liquidColor4]
            let start = 5 - min(max(l.liquidCount, 0), 5)
            return Array(start..<5).enumerated().map { (k, idx) in
                PaletteStop(id: idx, point: l.liquidPoints[idx], color: cols[idx], label: "\(k + 1)")
            }
        case .blur, .mirror, .slices:
            return []
        }
    }

    /// Re-positions palette stop `slot` of the current style to a normalised photo
    /// point, samples the colour there and writes it into that stop.
    func movePalettePoint(slot: Int, to raw: CGPoint) {
        guard let src = currentLook.source else { return }
        let p = CGPoint(x: min(1, max(0, raw.x)), y: min(1, max(0, raw.y)))
        let color = Self.sampleColor(from: src, at: p)
        mutateCurrentLook { look in
            switch look.style {
            case .liquid:
                guard look.liquidPoints.indices.contains(slot) else { return }
                look.liquidPoints[slot] = p; look.setLiquidColor(slot, color)
            case .blur, .mirror, .slices:
                break
            }
        }
    }

    /// Fills every palette colour from the look's sample points against `cg` — the
    /// "straight from the photo" derivation used when a new source loads.
    private static func resampleColors(_ look: inout Look, from cg: CGImage) {
        for i in 0..<5 { look.setLiquidColor(i, sampleColor(from: cg, at: look.liquidPoints[i])) }
    }

    /// Average sRGB colour of a small patch of `cg` around a normalised point
    /// (0…1, y from top) — a soft eyedropper that ignores single-pixel noise.
    static func sampleColor(from cg: CGImage, at p: CGPoint, radius: Double = 0.03) -> Color {
        let W = cg.width, H = cg.height
        guard W > 0, H > 0 else { return Color(white: 0.5) }
        let cx = Double(W) * min(1, max(0, p.x)), cy = Double(H) * min(1, max(0, p.y))
        let r = max(1.0, Double(max(W, H)) * radius)
        let x0 = max(0, Int((cx - r).rounded(.down))), y0 = max(0, Int((cy - r).rounded(.down)))
        let x1 = min(W, Int((cx + r).rounded(.up))),   y1 = min(H, Int((cy + r).rounded(.up)))
        let w = max(1, x1 - x0), h = max(1, y1 - y0)
        guard let crop = cg.cropping(to: CGRect(x: x0, y: y0, width: w, height: h)) else {
            return Color(white: 0.5)
        }
        // Downscale the patch into a tiny buffer; its mean is the sampled colour.
        let sw = min(8, w), sh = min(8, h)
        var buf = [UInt8](repeating: 0, count: sw * sh * 4)
        guard let c = CGContext(data: &buf, width: sw, height: sh, bitsPerComponent: 8,
                                bytesPerRow: sw * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Color(white: 0.5)
        }
        c.interpolationQuality = .medium
        c.draw(crop, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        var rs = 0.0, gs = 0.0, bs = 0.0, n = 0.0
        var i = 0
        while i < buf.count {
            if buf[i + 3] > 127 {
                rs += Double(buf[i]) / 255; gs += Double(buf[i + 1]) / 255; bs += Double(buf[i + 2]) / 255; n += 1
            }
            i += 4
        }
        guard n > 0 else { return Color(white: 0.5) }
        return Color(red: rs / n, green: gs / n, blue: bs / n)
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
        defer { previewGeneration &+= 1 }
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
        case .liquid:
            return LiquidProcessor.render(size: size, settings: look.liquidSettings, deepColor: deep)
        case .mirror:
            guard let src = look.source,
                  let base = BlurProcessor.processedImage(source: src, targetSize: size, settings: look.settings)
            else { return nil }
            let folded = MirrorProcessor.apply(to: base, size: size, settings: look.mirrorSettings)
            return BlurProcessor.finalize(folded, size: size, dither: look.dither, deepColor: deep)
        case .slices:
            guard let src = look.source,
                  let base = BlurProcessor.processedImage(source: src, targetSize: size, settings: look.settings)
            else { return nil }
            let sliced = SliceProcessor.apply(to: base, size: size, settings: look.sliceSettings)
            return BlurProcessor.finalize(sliced, size: size, dither: look.dither, deepColor: deep)
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

    /// Puts the open project on the desktop. Nothing is filed away here — the project
    /// is already saved; applying only changes what the desktop points at.
    func applySelected() {
        guard let project = selectedProject else { return }
        applyProject(project)
    }

    /// Applies any project from the rail. Editable projects are opened first so the
    /// full-size render comes from the recipe currently on screen.
    func applyProject(_ project: Project) {
        errorMessage = nil
        if project.isEditable, project.id != selectedProjectID { open(project) }
        Task { @MainActor in
            guard let ready = await ensureRendered(project) else { return }
            apply(ready, status: L("Als dynamisches Wallpaper gesetzt."))
        }
    }

    /// Makes sure `wallpaper.heic` exists and is newer than the recipe, rendering the
    /// 6016² master only when it actually has to. That render costs seconds, which is
    /// why it never runs on a slider change — only when a file is genuinely needed.
    @discardableResult
    func ensureRendered(_ project: Project) async -> Project? {
        let url = project.wallpaperURL
        if FileManager.default.fileExists(atPath: url.path),
           WallpaperLibrary.modificationDate(of: url) >= project.updatedAt,
           await WallpaperLibrary.ensureDownloaded(url) {
            return project
        }
        guard project.isEditable else {
            // Legacy project: the render is all there is. If it isn't there, it's gone.
            guard await WallpaperLibrary.ensureDownloaded(url) else {
                errorMessage = LibraryError.missingFile.localizedDescription
                return nil
            }
            return project
        }
        guard project.id == selectedProjectID else {
            errorMessage = LibraryError.missingFile.localizedDescription
            return nil
        }
        do {
            try writeOutput(to: url)
            return project
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// The one place that talks to `NSWorkspace` about the desktop.
    ///
    /// macOS 26 keeps an *absolute path per Space and per Display* in the
    /// WallpaperAgent index and the agent caches by path, so re-setting the same URL
    /// won't repaint. An older build forced a repaint by killing the agent, but
    /// `setDesktopImageURL` persists to the agent's store *asynchronously* — killing
    /// it right after races that write and the agent respawns onto the previous
    /// wallpaper. Copying to a fresh path on every apply sidesteps both: the path is
    /// always new (repaint, no kill) and every previously referenced file still
    /// exists, so other Spaces and displays keep resolving theirs.
    ///
    /// The copy is deliberately local (Application Support) even when the library
    /// lives in iCloud Drive: Drive may evict a synced file and leave a `.icloud`
    /// placeholder, and a desktop image pointing at a placeholder breaks.
    private func apply(_ project: Project, status: String) {
        Task { @MainActor in
            let source = project.wallpaperURL
            guard await WallpaperLibrary.ensureDownloaded(source) else {
                errorMessage = LibraryError.missingFile.localizedDescription
                return
            }
            do {
                let live = try WallpaperLibrary.appliedDirectory()
                    .appendingPathComponent("\(UUID().uuidString).heic")
                try FileManager.default.copyItem(at: source, to: live)
                // `copyItem` carries the library file's date over, and re-applying an
                // old wallpaper would then look stale to the pruner below. What matters
                // here is when it was *applied*.
                try? FileManager.default.setAttributes([.modificationDate: Date()],
                                                       ofItemAtPath: live.path)

                // The master is square and matches no display exactly, so force
                // aspect-fill with clipping: macOS center-crops it to each screen's own
                // aspect (the wide middle strip on landscape, the tall middle strip on
                // portrait) at native resolution, instead of letterboxing.
                let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true,
                ]
                for screen in NSScreen.screens {
                    try NSWorkspace.shared.setDesktopImageURL(live, for: screen, options: options)
                }
                statusMessage = status
                activeProjectID = project.id
                Self.pruneAppliedCopies(keeping: live)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Every file currently shown as a desktop image, across all screens of the
    /// active Space. Used to keep pruning from yanking a wallpaper out from under
    /// the user.
    private static func currentDesktopURLs() -> Set<URL> {
        Set(NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) })
    }

    /// Drops stale live copies.
    ///
    /// `desktopImageURL` only reports the *active* Space, so inactive Spaces hold
    /// references this code can't see. Deleting one of those blanks that Space, so
    /// the newest `appliedCopyCushion` copies are kept regardless — matching the
    /// library's own limit, which is the most creations that can be in play anyway.
    /// At roughly 650 KB per file that ceiling costs a few dozen megabytes.
    private static func pruneAppliedCopies(keeping live: URL) {
        guard let dir = try? appliedDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles])
        else { return }

        var keep = currentDesktopURLs().map(\.standardizedFileURL.path)
        keep.append(live.standardizedFileURL.path)
        keep.append(contentsOf: files
            .sorted { modified($0) > modified($1) }
            .prefix(appliedCopyCushion)
            .map(\.standardizedFileURL.path))

        let keepSet = Set(keep)
        for file in files where !keepSet.contains(file.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static let appliedCopyCushion = 50

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? Date(timeIntervalSince1970: 0)
    }

    private static func appliedDirectory() throws -> URL {
        try WallpaperLibrary.appliedDirectory()
    }

    // MARK: Projects

    func refreshProjects() {
        projects = WallpaperLibrary.load()
    }

    /// Reads a project into the editor. Everything the user sees afterwards belongs
    /// to this project, and every further edit autosaves back into it.
    func open(_ project: Project) {
        guard project.id != selectedProjectID || selectedProjectID == nil else { return }
        selectedProjectID = project.id
        UserDefaults.standard.set(project.id, forKey: Self.lastOpenProjectKey)

        guard let recipe = project.recipe else {
            // Legacy project — there is no recipe to load, so the editor keeps
            // whatever it had; the inspector shows the read-only pane instead.
            renderPreview()
            return
        }

        let lightSource = WallpaperLibrary.readImage(at: project.lightSourceURL)
        let darkSource = WallpaperLibrary.readImage(at: project.darkSourceURL) ?? lightSource

        withAutosaveSuspended {
            lightLook = Look(recipe: recipe.light, source: lightSource)
            darkLook = Look(recipe: recipe.dark, source: darkSource)
            editing = .light
        }
        renderPreview()
    }

    /// Full copy of the open project, opened straight away — the "+" button.
    ///
    /// A legacy project has no recipe, so a copy of it would be just as uneditable.
    /// Branching off one starts a blank project instead.
    func duplicateSelected() {
        guard let project = selectedProject, project.isEditable else { newProject(); return }
        flushAutosave()
        do {
            let copy = try WallpaperLibrary.duplicate(project)
            refreshProjects()
            selectedProjectID = nil          // force `open` to re-read
            open(copy)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A blank project. Only reachable from the ⋯ menu and on an empty collection.
    func newProject() {
        flushAutosave()
        do {
            let project = try WallpaperLibrary.create(slug: nil)
            refreshProjects()
            selectedProjectID = project.id
            UserDefaults.standard.set(project.id, forKey: Self.lastOpenProjectKey)
            withAutosaveSuspended {
                lightLook = Look()
                darkLook = Look(brightness: -0.15, saturation: 1.0, contrast: 1.05)
                editing = .light
            }
            renderPreview()
            // A fresh, empty project is the only place the launch photo still applies.
            loadRandomStarterPhoto()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ project: Project) {
        WallpaperLibrary.delete(project)
        refreshProjects()
        if activeProjectID == project.id { activeProjectID = nil }
        if selectedProjectID == project.id {
            selectedProjectID = nil
            if let next = projects.first { open(next) } else { newProject() }
        }
    }

    func revealInFinder(_ project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting([project.url])
    }

    /// Copies a project's finished wallpaper out to a location the user picks,
    /// rendering it first if it isn't current.
    func exportProject(_ project: Project) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.heic]
        panel.nameFieldStringValue = "\(project.id).heic"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let ready = await self.ensureRendered(project) else { return }
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.copyItem(at: ready.wallpaperURL, to: url)
                    self.statusMessage = L("Exportiert: %@", url.lastPathComponent)
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: Autosave

    /// Saving is not a user action: every edit lands on disk on its own. The delay
    /// coalesces a slider drag into one write; `flushAutosave` forces it out when
    /// something is about to depend on the file (duplicating, quitting).
    private func scheduleAutosave() {
        guard !isLoadingProject else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            saveOpenProject()
        }
    }

    func flushAutosave() {
        autosaveTask?.cancel()
        autosaveTask = nil
        saveOpenProject()
    }

    private func withAutosaveSuspended(_ body: () -> Void) {
        isLoadingProject = true
        body()
        isLoadingProject = false
        autosaveTask?.cancel()
        autosaveTask = nil
    }

    private func saveOpenProject() {
        guard var project = selectedProject, project.isEditable else { return }
        let recipe = ProjectRecipe(light: lightLook.recipe, dark: darkLook.recipe)
        let name = lightLook.baseName ?? darkLook.baseName

        // Nothing changed but the timestamp — skip the write so an idle app stays
        // idle and iCloud isn't handed pointless revisions.
        if project.recipe == recipe, project.name == name { return }

        let previous = project.recipe
        do {
            try WallpaperLibrary.save(&project, recipe: recipe, name: name,
                                      attribution: lightLook.attribution,
                                      attributionURL: lightLook.attributionURL)
            writeSourceImages(for: project, previous: previous)
            writeThumbnail(for: project)
            refreshProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stores a copy of each look's source photo so the project survives the original
    /// file being moved, the Photos asset being deleted, or opening on another Mac.
    /// One file when both appearances share a photo, which is the common case.
    ///
    /// Only re-encoded when the photo actually changed: a slider drag saves several
    /// times a second, and rewriting a megabyte of HEIC into iCloud each time would be
    /// pure churn.
    private func writeSourceImages(for project: Project, previous: ProjectRecipe?) {
        let fm = FileManager.default
        if let light = lightLook.source,
           previous?.light.photoID != lightLook.photoID || !fm.fileExists(atPath: project.lightSourceURL.path) {
            try? WallpaperLibrary.writeSource(light, to: project.lightSourceURL)
        }

        // A separate dark source is the exception; when both share a photo the extra
        // file must go, or a stale one would win on the next open.
        let needsDarkCopy = darkLook.source != nil && darkLook.photoID != lightLook.photoID
        if needsDarkCopy {
            if previous?.dark.photoID != darkLook.photoID || !fm.fileExists(atPath: project.darkSourceURL.path),
               let dark = darkLook.source {
                try? WallpaperLibrary.writeSource(dark, to: project.darkSourceURL)
            }
        } else if fm.fileExists(atPath: project.darkSourceURL.path) {
            try? fm.removeItem(at: project.darkSourceURL)
        }
    }

    /// The rail tile. Always the Light appearance so the collection reads
    /// consistently, and small enough that writing it on every edit is free.
    private func writeThumbnail(for project: Project) {
        let side = Double(WallpaperLibrary.previewMaxPixels)
        guard let cg = renderCG(lightLook, size: CGSize(width: side, height: side), deep: false) else { return }
        try? WallpaperLibrary.writePreview(cg, to: project.previewURL)
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

}
