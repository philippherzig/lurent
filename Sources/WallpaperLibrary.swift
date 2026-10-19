import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Errors

enum LibraryError: LocalizedError {
    case noDirectory, storeFailed, missingFile, notEditable, notAProject

    var errorDescription: String? {
        switch self {
        case .noDirectory:  return L("Der Wallpaper-Ordner konnte nicht angelegt werden.")
        case .storeFailed:  return L("Das Projekt konnte nicht gesichert werden.")
        case .missingFile:  return L("Die Wallpaper-Datei ist nicht mehr verfügbar (noch nicht aus iCloud geladen?).")
        case .notEditable:  return L("Dieses Wallpaper stammt aus einer früheren Version und lässt sich nicht mehr bearbeiten.")
        case .notAProject:  return L("Das ist kein Lurent-Projekt.")
        }
    }
}

// MARK: - One project

/// A saved creation: its recipe, its source image, and the renders derived from them.
/// `recipe == nil` marks a wallpaper migrated from before projects existed — it can
/// still be applied, exported and deleted, but there is nothing to reopen.
struct Project: Identifiable, Hashable {
    /// A UUID from the manifest, **not** the file name. A project is a document the
    /// user may rename in the Finder at any time; identity has to survive that.
    let id: String
    let url: URL                // the .lurent package
    var createdAt: Date
    var updatedAt: Date
    var name: String?
    var nameIsCustom: Bool
    var attribution: String?
    var attributionURL: String?
    var recipe: ProjectRecipe?

    var isEditable: Bool { recipe != nil }

    /// What the rail and the inspector show. Falls back to the file name so a
    /// manifest without a name never renders blank.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? L("Ohne Titel") : base
    }

    var previewURL: URL { url.appendingPathComponent("preview.heic") }
    var wallpaperURL: URL { url.appendingPathComponent("wallpaper.heic") }
    var lightSourceURL: URL { url.appendingPathComponent("source.heic") }
    var darkSourceURL: URL { url.appendingPathComponent("source-dark.heic") }
    var manifestURL: URL { url.appendingPathComponent("project.json") }

    /// What the rail shows. Legacy projects have no small preview, so they fall back
    /// to the full wallpaper (ImageIO thumbnails it just as happily).
    var thumbnailURL: URL {
        FileManager.default.fileExists(atPath: previewURL.path) ? previewURL : wallpaperURL
    }

    var style: WallpaperStyle? {
        recipe?.light.style.flatMap(WallpaperStyle.init(rawValue:))
    }

    // `updatedAt` and `url` are included so SwiftUI notices a save or a rename.
    // Hand-written because `LookRecipe` deliberately stops at `Equatable`.
    static func == (a: Project, b: Project) -> Bool {
        a.id == b.id && a.updatedAt == b.updatedAt && a.url == b.url
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ProjectRecipe: Codable, Equatable {
    var light: LookRecipe
    var dark: LookRecipe
}

/// `project.json`. Optional everywhere but `id`/`createdAt` so files from other
/// versions keep loading — same reasoning as `LookRecipe`.
private struct Manifest: Codable {
    var id: String
    var createdAt: Date
    var updatedAt: Date?
    var name: String?
    /// Set once the user renamed the package in the Finder. From then on picking a
    /// different photo must not quietly rewrite the title back to the photo's
    /// description.
    var nameIsCustom: Bool?
    var attribution: String?
    var attributionURL: String?
    var recipe: ProjectRecipe?
    var appVersion: String?
}

// MARK: - The library on disk

enum WallpaperLibrary {

    /// Longest edge kept for the stored copy of a source photo — caps what a large
    /// photo (from Commons or a local file) costs in project storage. Softened by
    /// the blur styles regardless, so the square 6016 master rarely misses the
    /// extra detail above this.
    static let sourceMaxPixels = 4096

    /// Rail thumbnails are 76 pt; 512 covers Retina with room to spare.
    static let previewMaxPixels = 512

    // MARK: Locations

    /// The app's own iCloud container, e.g. `iCloud.app.lurent`. Must match the
    /// `com.apple.developer.ubiquity-container-identifiers` entitlement.
    static let ubiquityContainerID = "iCloud.app.lurent"

    /// Where projects live, in order of preference:
    ///
    /// 1. **The app's ubiquity container.** Syncs across Macs, shows up in iCloud
    ///    Drive as a "Lurent" folder with the app icon, and needs no folder picking —
    ///    it is the only option that works from inside a sandbox without asking the
    ///    user anything. Requires the iCloud entitlements, which in turn require a
    ///    provisioning profile, i.e. App Store distribution.
    /// 2. **The plain iCloud Drive folder.** What Developer-ID builds use today: an
    ///    ordinary path, no entitlement, but unreachable from a sandbox.
    /// 3. **Application Support.** Local only; also where a sandboxed build without
    ///    the iCloud entitlement lands.
    static func directory() throws -> URL {
        let dir = resolvedRoot
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.noDirectory
        }
        return dir
    }

    /// Resolved once: `url(forUbiquityContainerIdentifier:)` talks to the iCloud
    /// daemon and may block, which must not happen on every save.
    private static let resolvedRoot: URL = {
        if let container = ubiquityDocuments {
            return container
        }
        if let cloudDocs = plainCloudDocsRoot {
            return cloudDocs.appendingPathComponent("Lurent", isDirectory: true)
        }
        return localFallbackDirectory
    }()

    private static var ubiquityDocuments: URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: ubiquityContainerID)
        else { return nil }
        return container.appendingPathComponent("Documents", isDirectory: true)
    }

    private static var plainCloudDocsRoot: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url
    }


    private static var localFallbackDirectory: URL {
        appSupportRoot.appendingPathComponent("Wallpapers", isDirectory: true)
    }

    private static var appSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Lurent", isDirectory: true)
    }

    /// Local copies that macOS actually points at. Never in iCloud: Drive may evict a
    /// synced file and leave a `.icloud` placeholder, and a desktop image pointing at
    /// a placeholder breaks.
    static func appliedDirectory() throws -> URL {
        let dir = appSupportRoot.appendingPathComponent("Applied", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.noDirectory
        }
        return dir
    }

    // MARK: Reading

    /// Every project, newest first.
    static func load() -> [Project] {
        guard let dir = try? directory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles])
        else { return [] }

        let projects = entries.compactMap { url -> Project? in
            guard url.pathExtension.lowercased() == packageExtension else { return nil }
            return project(at: url)
        }
        return projects.sorted { $0.createdAt > $1.createdAt }
    }

    /// Reads a package's manifest. Returns nil for anything that isn't one — that is
    /// also how a half-copied package on its way in from iCloud is skipped.
    ///
    /// **The file name wins.** The app always writes name and file name together, so
    /// finding them out of sync means the user renamed the document in the Finder —
    /// and on a document format that rename is the authoritative one. It is also
    /// treated as deliberate, so a later photo change won't undo it. The manifest
    /// catches up on the next save.
    static func project(at package: URL) -> Project? {
        let manifestURL = package.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? decoder.decode(Manifest.self, from: data) else { return nil }

        let filename = package.deletingPathExtension().lastPathComponent
        let renamedOutside = !filename.isEmpty && filename != m.name
        return Project(id: m.id, url: package, createdAt: m.createdAt,
                       updatedAt: m.updatedAt ?? m.createdAt,
                       name: renamedOutside ? filename : m.name,
                       nameIsCustom: renamedOutside || (m.nameIsCustom ?? false),
                       attribution: m.attribution, attributionURL: m.attributionURL,
                       recipe: m.recipe)
    }

    // MARK: Writing

    /// Creates an empty project package and its manifest.
    static func create(name: String?, now: Date = Date()) throws -> Project {
        let dir = try directory()
        let title = name ?? L("Ohne Titel")
        let url = try makePackage(in: dir, name: title)
        var project = Project(id: UUID().uuidString, url: url, createdAt: now, updatedAt: now,
                              name: storedName(for: url), nameIsCustom: false,
                              attribution: nil, attributionURL: nil,
                              recipe: ProjectRecipe(light: LookRecipe(), dark: LookRecipe()))
        try writeManifest(&project)
        return project
    }

    /// The name to record in the manifest for a package the app just placed.
    ///
    /// Always taken from the file that actually ended up on disk, never from the
    /// requested title: collisions get a `" 2"` suffix, and storing the unsuffixed
    /// title would leave name and file name disagreeing — which `project(at:)` reads
    /// as a Finder rename and would then freeze the name forever.
    private static func storedName(for package: URL) -> String {
        package.deletingPathExtension().lastPathComponent
    }

    private static func makePackage(in dir: URL, name: String) throws -> URL {
        let url = dir.appendingPathComponent(uniqueFilename(in: dir, name: name), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.storeFailed
        }
        return url
    }

    /// Persists the recipe and metadata. The heavy `wallpaper.heic` is not touched
    /// here — see `AppModel.ensureRendered`.
    static func save(_ project: inout Project, recipe: ProjectRecipe,
                     name: String?, nameIsCustom: Bool,
                     attribution: String?, attributionURL: String?,
                     now: Date = Date()) throws {
        project.recipe = recipe
        project.name = name
        project.nameIsCustom = nameIsCustom
        project.attribution = attribution
        project.attributionURL = attributionURL
        project.updatedAt = now
        try writeManifest(&project)
    }

    /// Renames the document: the package on disk moves, the id stays. Returns the
    /// project pointing at its new location. `isCustom` marks a name the user chose,
    /// which then survives any later photo change; the derived-title path passes false.
    static func rename(_ project: Project, to name: String, isCustom: Bool = true) throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = trimmed.isEmpty ? L("Ohne Titel") : trimmed

        let dir = project.url.deletingLastPathComponent()
        let target = dir.appendingPathComponent(
            uniqueFilename(in: dir, name: wanted, excluding: project.url),
            isDirectory: true)
        if target != project.url {
            do {
                try FileManager.default.moveItem(at: project.url, to: target)
            } catch {
                throw LibraryError.storeFailed
            }
        }
        // The stored name is whatever the file ended up being called — including any
        // collision suffix. Storing `wanted` instead would leave name and file name
        // disagreeing, which `project(at:)` reads as a Finder rename.
        var renamed = Project(id: project.id, url: target, createdAt: project.createdAt,
                              updatedAt: project.updatedAt, name: storedName(for: target),
                              nameIsCustom: isCustom || project.nameIsCustom,
                              attribution: project.attribution,
                              attributionURL: project.attributionURL, recipe: project.recipe)
        try writeManifest(&renamed)
        return renamed
    }

    private static func writeManifest(_ project: inout Project) throws {
        let m = Manifest(id: project.id, createdAt: project.createdAt,
                         updatedAt: project.updatedAt, name: project.name,
                         nameIsCustom: project.nameIsCustom,
                         attribution: project.attribution,
                         attributionURL: project.attributionURL,
                         recipe: project.recipe, appVersion: appVersion)
        guard let data = try? encoder.encode(m) else { throw LibraryError.storeFailed }
        do {
            try data.write(to: project.manifestURL, options: .atomic)
        } catch {
            throw LibraryError.storeFailed
        }
    }

    /// Copies a whole project package under a fresh id. Everything comes along —
    /// recipe, source images, renders — so the copy is immediately usable offline.
    static func duplicate(_ project: Project, now: Date = Date()) throws -> Project {
        try adopt(project.url, createdAt: now, copying: true)
    }

    /// Brings a `.lurent` from outside the collection in. It gets a **new** id, so
    /// importing the same file twice yields two independent projects instead of two
    /// entries fighting over one identity.
    static func importPackage(at source: URL, now: Date = Date()) throws -> Project {
        guard project(at: source) != nil else { throw LibraryError.notAProject }
        return try adopt(source, createdAt: now, copying: true)
    }

    /// Takes a package into the collection under a fresh identity.
    ///
    /// The copy's title is derived from its own source photo rather than inherited,
    /// and `nameIsCustom` resets: a duplicate is a new document that nobody has named
    /// yet, so it should behave like one — `Wasserfall` duplicated is `Wasserfall 2`,
    /// and pointing it at another photo renames it along.
    private static func adopt(_ source: URL, createdAt: Date, copying: Bool) throws -> Project {
        guard let incoming = project(at: source) else { throw LibraryError.notAProject }
        let title = readableTitle(from: incoming.recipe?.light.baseName)
            ?? incoming.displayName

        let dir = try directory()
        let target = dir.appendingPathComponent(uniqueFilename(in: dir, name: title),
                                                isDirectory: true)
        do {
            if copying {
                try FileManager.default.copyItem(at: source, to: target)
            } else {
                try FileManager.default.moveItem(at: source, to: target)
            }
        } catch {
            throw LibraryError.storeFailed
        }
        guard var adopted = project(at: target) else { throw LibraryError.notAProject }
        adopted = Project(id: UUID().uuidString, url: target, createdAt: createdAt,
                          updatedAt: createdAt, name: storedName(for: target),
                          nameIsCustom: false,
                          attribution: adopted.attribution,
                          attributionURL: adopted.attributionURL, recipe: adopted.recipe)
        try writeManifest(&adopted)
        return adopted
    }

    /// Is this package already one of ours?
    static func isInCollection(_ url: URL) -> Bool {
        guard let dir = try? directory() else { return false }
        return url.standardizedFileURL.deletingLastPathComponent() == dir.standardizedFileURL
    }

    /// Moves the package to the Trash rather than deleting it — a mis-click on a
    /// project the user spent time on should be recoverable.
    static func delete(_ project: Project) {
        var trashed: NSURL?
        try? FileManager.default.trashItem(at: project.url, resultingItemURL: &trashed)
    }

    // MARK: Images

    /// Writes a source bitmap as HEIC, downscaled to `sourceMaxPixels`.
    static func writeSource(_ image: CGImage, to url: URL) throws {
        try writeHEIC(image, to: url, maxPixels: sourceMaxPixels, quality: 0.92)
    }

    /// Writes the rail thumbnail.
    static func writePreview(_ image: CGImage, to url: URL) throws {
        try writeHEIC(image, to: url, maxPixels: previewMaxPixels, quality: 0.8)
    }

    private static func writeHEIC(_ image: CGImage, to url: URL,
                                  maxPixels: Int, quality: Double) throws {
        let scaled = normalizedSource(image, maxPixels: maxPixels)
        let type = UTType.heic.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw LibraryError.storeFailed
        }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw LibraryError.storeFailed }
    }

    /// The colour space a source photo is kept in — its own, as long as 8 bits can
    /// hold it, so a Display P3 photo stays wide. Device RGB here would clip it back
    /// to sRGB before the render ever saw the wide colours, which is the whole point
    /// of the P3 output space (see `BlurProcessor.outputColorSpace`).
    ///
    /// Two kinds of source don't survive 8 bits in their own space, and both are
    /// redrawn as plain Display P3 instead — same wide gamut, usable steps:
    ///
    ///   * HDR. An iPhone photo is PQ, whose code values are spread over a
    ///     10,000-nit range; at 8 bits that leaves 131 distinct steps across the
    ///     SDR range where Display P3 leaves 141 (measured). The wallpaper is SDR
    ///     either way, so the PQ curve buys nothing downstream.
    ///   * Extended-range spaces, which 8 bits cannot represent at all.
    ///
    /// Anything that isn't RGB (grey, CMYK) lands there too; P3 holds it all.
    private static func storageSpace(for image: CGImage) -> CGColorSpace {
        guard let s = image.colorSpace, s.model == .rgb,
              !CGColorSpaceUsesITUR_2100TF(s),
              !CGColorSpaceUsesExtendedRange(s)
        else { return BlurProcessor.outputColorSpace }
        return s
    }

    /// Brings a source photo into the shape the rest of the app expects: no longer
    /// than `maxPixels` on its longest edge, in a colour space that survives 8-bit
    /// storage. Idempotent — an image that already qualifies is returned untouched.
    ///
    /// This has to run where a photo *enters* the app, not only where it is stored.
    /// The renderer works from `Look.source` during the session and from the stored
    /// copy after a reopen; if the two differ, the same project renders differently
    /// once it has been closed. Tying the conversion to the resize is what used to
    /// cause exactly that — a 12 MP iPhone photo (4032 px) is already under the cap,
    /// so it skipped the resize and kept its PQ profile, while a 48 MP one did not.
    static func normalizedSource(_ image: CGImage, maxPixels: Int = sourceMaxPixels) -> CGImage {
        let longest = max(image.width, image.height)
        let f = longest > maxPixels ? Double(maxPixels) / Double(longest) : 1
        let space = storageSpace(for: image)

        // Right size and a space we can keep: nothing to redraw.
        if f == 1, let current = image.colorSpace, current.name == space.name { return image }

        let w = max(1, Int((Double(image.width) * f).rounded()))
        let h = max(1, Int((Double(image.height) * f).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    static func readImage(at url: URL) -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: iCloud

    /// Pulls an evicted iCloud file back down and waits briefly for it. Returns false
    /// if the bytes still aren't there — callers surface `.missingFile` rather than
    /// handing macOS a placeholder. Async because the wait can run into seconds on a
    /// cold file and must not block the UI.
    @discardableResult
    static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 10) async -> Bool {
        if isReadable(url) { return true }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isReadable(url) { return true }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return isReadable(url)
    }

    /// Local bytes present? A file outside iCloud has no downloading status at all,
    /// so plain existence is the answer there.
    private static func isReadable(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
            .ubiquitousItemDownloadingStatus
        return status == nil || status == .current || status == .downloaded
    }

    // MARK: Migration

    private static let migratedSlotsKey = "legacySlotsMigrated"
    private static let migratedFlatKey = "flatEntriesMigrated"
    private static let migratedPackagesKey = "projectPackagesMigrated"

    /// Brings everything older than the current format forward, once each.
    static func migrate() {
        migrateLegacySlots()
        migrateFlatEntries()
        migrateToPackages()
    }

    /// Project folders were named `<timestamp>-<slug>` and identified by that name.
    /// They become `<Name>.lurent` packages with a UUID in the manifest, so the user
    /// can rename them in the Finder without the app losing track.
    private static func migrateToPackages() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedPackagesKey) else { return }
        defaults.set(true, forKey: migratedPackagesKey)

        guard let dir = try? directory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return }

        for folder in entries where folder.pathExtension.lowercased() != packageExtension {
            guard var project = project(at: folder) else { continue }

            // The old id was the folder name; the name was a raw photo slug or nil.
            let title = readableTitle(from: project.name)
                ?? readableTitle(from: strippedTimestamp(folder.lastPathComponent))
                ?? L("Ohne Titel")
            let target = dir.appendingPathComponent(uniqueFilename(in: dir, name: title),
                                                    isDirectory: true)
            guard (try? FileManager.default.moveItem(at: folder, to: target)) != nil else { continue }

            project = Project(id: UUID().uuidString, url: target,
                              createdAt: project.createdAt, updatedAt: project.updatedAt,
                              name: storedName(for: target), nameIsCustom: false,
                              attribution: project.attribution,
                              attributionURL: project.attributionURL, recipe: project.recipe)
            try? writeManifest(&project)
        }
    }

    /// `20260804-112027-waterfalls` → `waterfalls`.
    private static func strippedTimestamp(_ s: String) -> String {
        let parts = s.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 8, Int(parts[0]) != nil else { return s }
        return String(parts[2])
    }

    /// Builds before the library existed alternated between two fixed files
    /// (`wallpaper-a/b.heic`, and `current.heic` before that), so each new wallpaper
    /// eventually overwrote an older one. Whatever survived gets copied in.
    ///
    /// The originals stay put on purpose: other Spaces and displays may still point
    /// at those exact paths, and removing them would blank those desktops.
    private static func migrateLegacySlots() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedSlotsKey) else { return }
        defaults.set(true, forKey: migratedSlotsKey)

        for name in ["wallpaper-a.heic", "wallpaper-b.heic", "current.heic"] {
            let legacy = appSupportRoot.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: legacy.path) else { continue }
            adoptRenderedWallpaper(at: legacy, copying: true, date: modificationDate(of: legacy))
        }
    }

    /// The first library format kept `<id>.heic` + `<id>.json` loose in the folder.
    /// Each pair becomes a folder holding the same render — without a recipe, so it
    /// stays applicable but not editable.
    private static func migrateFlatEntries() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedFlatKey) else { return }
        defaults.set(true, forKey: migratedFlatKey)

        guard let dir = try? directory(),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return }

        for heic in files where heic.pathExtension.lowercased() == "heic" {
            let sidecar = heic.deletingPathExtension().appendingPathExtension("json")
            let date = flatCreatedAt(sidecar) ?? modificationDate(of: heic)
            // The old basename carries the photo slug — the only title material there is.
            let title = readableTitle(from: strippedTimestamp(heic.deletingPathExtension().lastPathComponent))
            if adoptRenderedWallpaper(at: heic, copying: false, date: date, title: title) {
                try? FileManager.default.removeItem(at: sidecar)
            }
        }
    }

    private static func flatCreatedAt(_ sidecar: URL) -> Date? {
        struct Flat: Codable { var createdAt: Date? }
        guard let data = try? Data(contentsOf: sidecar) else { return nil }
        return (try? decoder.decode(Flat.self, from: data))?.createdAt
    }

    /// Wraps a bare rendered wallpaper into a recipe-less project package.
    @discardableResult
    private static func adoptRenderedWallpaper(at file: URL, copying: Bool, date: Date,
                                               title: String? = nil) -> Bool {
        guard let dir = try? directory() else { return false }
        let name = title ?? L("Ohne Titel")
        guard let package = try? makePackage(in: dir, name: name) else { return false }

        let target = package.appendingPathComponent("wallpaper.heic")
        let moved: Bool
        if copying {
            moved = (try? FileManager.default.copyItem(at: file, to: target)) != nil
        } else {
            moved = (try? FileManager.default.moveItem(at: file, to: target)) != nil
        }
        guard moved else {
            try? FileManager.default.removeItem(at: package)
            return false
        }

        var project = Project(id: UUID().uuidString, url: package, createdAt: date,
                              updatedAt: date, name: storedName(for: package), nameIsCustom: false,
                              attribution: nil, attributionURL: nil, recipe: nil)
        try? writeManifest(&project)
        return true
    }

    // MARK: Naming

    static let packageExtension = "lurent"

    /// Must match `UTExportedTypeDeclarations` in Info.plist.
    static let typeIdentifier = "app.lurent.project"

    /// The declared type for open/save panels. Falls back to a plain package if
    /// LaunchServices hasn't picked up the declaration yet (first run of a fresh
    /// build), so the panels still work instead of accepting nothing.
    static var contentType: UTType {
        UTType(typeIdentifier) ?? .package
    }

    /// `Wasserfall.lurent`, or `Wasserfall 2.lurent` when taken.
    ///
    /// A name that already ends in a number keeps counting instead of stacking:
    /// duplicating `Wasserfall 2` gives `Wasserfall 3`, not `Wasserfall 2 2`.
    /// `excluding` lets a rename keep its current name when nothing really changed.
    private static func uniqueFilename(in dir: URL, name: String, excluding: URL? = nil) -> String {
        let (base, start) = splitTrailingNumber(filesystemSafe(name))

        func isFree(_ filename: String) -> Bool {
            let url = dir.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) { return true }
            return url.standardizedFileURL == excluding?.standardizedFileURL
        }

        let plain = "\(base).\(packageExtension)"
        if start == nil, isFree(plain) { return plain }

        var n = start ?? 2
        while true {
            let candidate = "\(base) \(n).\(packageExtension)"
            if isFree(candidate) { return candidate }
            n += 1
        }
    }

    /// The title without any collision suffix: `"Wasserfall 2"` → `"Wasserfall"`.
    /// Used to tell "same title, different copy" from a genuinely new title.
    static func baseTitle(of name: String) -> String {
        splitTrailingNumber(name).0
    }

    /// `"Wasserfall 2"` → `("Wasserfall", 2)`; `"Wasserfall"` → `("Wasserfall", nil)`.
    private static func splitTrailingNumber(_ name: String) -> (String, Int?) {
        guard let space = name.lastIndex(of: " ") else { return (name, nil) }
        let tail = name[name.index(after: space)...]
        guard let n = Int(tail), n >= 2, !tail.isEmpty else { return (name, nil) }
        let base = String(name[..<space]).trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? (name, nil) : (base, n)
    }

    /// A file name can't hold `/` (or `:`, which the Finder shows as `/`), and a
    /// leading dot would hide the package.
    private static func filesystemSafe(_ name: String) -> String {
        var out = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasPrefix(".") { out.removeFirst() }
        out = String(out.prefix(60)).trimmingCharacters(in: .whitespaces)
        return out.isEmpty ? L("Ohne Titel") : out
    }

    /// Turns a slug into something worth putting on a document:
    /// `a-plane-flying-in-the-sky-at-sunset-m6gcw9ypefi` → `A plane flying in the sky at sunset`.
    /// Returns nil when there is nothing usable left.
    ///
    /// Capped by characters, not by word count, and always cut on a word boundary —
    /// a fixed word limit lands mid-phrase and leaves titles like "A plane flying in
    /// the" hanging.
    static func readableTitle(from raw: String?, maxLength: Int = 40) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var words = raw.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map(String.init)
        // Derived base names end in the photo id — a long token carrying digits,
        // which reads as noise rather than a word.
        if let last = words.last, last.count > 8, last.rangeOfCharacter(from: .decimalDigits) != nil {
            words.removeLast()
        }
        guard !words.isEmpty else { return nil }

        var title = ""
        for word in words {
            let next = title.isEmpty ? word : title + " " + word
            if next.count > maxLength, !title.isEmpty { break }
            title = next
            if title.count >= maxLength { break }
        }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    static func slugify(_ s: String) -> String {
        let mapped = s.lowercased().map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "-"
        }
        var out = String(mapped)
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(out.prefix(60))
    }

    // MARK: Shared helpers

    static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? Date(timeIntervalSince1970: 0)
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
