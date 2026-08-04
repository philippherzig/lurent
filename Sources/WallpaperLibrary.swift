import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Errors

enum LibraryError: LocalizedError {
    case noDirectory, storeFailed, missingFile, notEditable

    var errorDescription: String? {
        switch self {
        case .noDirectory:  return L("Der Wallpaper-Ordner konnte nicht angelegt werden.")
        case .storeFailed:  return L("Das Projekt konnte nicht gesichert werden.")
        case .missingFile:  return L("Die Wallpaper-Datei ist nicht mehr verfügbar (noch nicht aus iCloud geladen?).")
        case .notEditable:  return L("Dieses Wallpaper stammt aus einer früheren Version und lässt sich nicht mehr bearbeiten.")
        }
    }
}

// MARK: - One project

/// A saved creation: its recipe, its source image, and the renders derived from them.
/// `recipe == nil` marks a wallpaper migrated from before projects existed — it can
/// still be applied, exported and deleted, but there is nothing to reopen.
struct Project: Identifiable, Hashable {
    let id: String              // = folder name
    let url: URL                // the folder itself
    var createdAt: Date
    var updatedAt: Date
    var name: String?
    var attribution: String?
    var attributionURL: String?
    var recipe: ProjectRecipe?

    var isEditable: Bool { recipe != nil }

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

    // Identity is the folder; `updatedAt` is included so SwiftUI notices a save.
    // Hand-written because `LookRecipe` deliberately stops at `Equatable`.
    static func == (a: Project, b: Project) -> Bool {
        a.id == b.id && a.updatedAt == b.updatedAt
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
    var attribution: String?
    var attributionURL: String?
    var recipe: ProjectRecipe?
    var appVersion: String?
}

// MARK: - The library on disk

enum WallpaperLibrary {

    /// Longest edge kept for the stored copy of a source photo. Unsplash's `regular`
    /// size is ~1080 px wide, so this only ever bites on large local files — where
    /// the square 6016 master can't use the extra detail anyway.
    static let sourceMaxPixels = 4096

    /// Rail thumbnails are 76 pt; 512 covers Retina with room to spare.
    static let previewMaxPixels = 512

    // MARK: Locations

    /// Where projects live. Preferred: the user's plain iCloud Drive folder, so the
    /// collection syncs across Macs and survives reinstalling the app.
    ///
    /// This is an ordinary filesystem path, *not* a ubiquity container: real iCloud
    /// entitlements need a provisioning profile, which Developer-ID distribution
    /// outside the App Store can't have. Lurent isn't sandboxed, so the path works
    /// as-is. With iCloud Drive turned off the folder doesn't exist — then the
    /// collection stays local under Application Support.
    static func directory() throws -> URL {
        let dir = iCloudRoot.map { $0.appendingPathComponent("Lurent", isDirectory: true) }
            ?? localFallbackDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.noDirectory
        }
        return dir
    }

    private static var iCloudRoot: URL? {
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
              let folders = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles])
        else { return [] }

        let projects = folders.compactMap { folder -> Project? in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir),
                  isDir.boolValue else { return nil }
            return project(at: folder)
        }
        return projects.sorted { $0.createdAt > $1.createdAt }
    }

    static func project(at folder: URL) -> Project? {
        let manifestURL = folder.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? decoder.decode(Manifest.self, from: data) else { return nil }
        return Project(id: m.id, url: folder, createdAt: m.createdAt,
                       updatedAt: m.updatedAt ?? m.createdAt, name: m.name,
                       attribution: m.attribution, attributionURL: m.attributionURL,
                       recipe: m.recipe)
    }

    // MARK: Writing

    /// Creates an empty project folder and its manifest.
    static func create(slug: String?, now: Date = Date()) throws -> Project {
        let dir = try directory()
        let id = uniqueID(in: dir, slug: slug, now: now)
        let folder = dir.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.storeFailed
        }
        var project = Project(id: id, url: folder, createdAt: now, updatedAt: now,
                              name: nil, attribution: nil, attributionURL: nil,
                              recipe: ProjectRecipe(light: LookRecipe(), dark: LookRecipe()))
        try writeManifest(&project)
        return project
    }

    /// Persists the recipe and metadata. The heavy `wallpaper.heic` is not touched
    /// here — see `AppModel.ensureRendered`.
    static func save(_ project: inout Project, recipe: ProjectRecipe,
                     name: String?, attribution: String?, attributionURL: String?,
                     now: Date = Date()) throws {
        project.recipe = recipe
        project.name = name
        project.attribution = attribution
        project.attributionURL = attributionURL
        project.updatedAt = now
        try writeManifest(&project)
    }

    private static func writeManifest(_ project: inout Project) throws {
        let m = Manifest(id: project.id, createdAt: project.createdAt,
                         updatedAt: project.updatedAt, name: project.name,
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

    /// Copies a whole project folder under a fresh id. Everything comes along —
    /// recipe, source images, renders — so the copy is immediately usable offline.
    static func duplicate(_ project: Project, now: Date = Date()) throws -> Project {
        let dir = try directory()
        let slug = project.name.map(slugify)
        let id = uniqueID(in: dir, slug: slug, now: now)
        let folder = dir.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.copyItem(at: project.url, to: folder)
        } catch {
            throw LibraryError.storeFailed
        }
        var copy = project
        copy = Project(id: id, url: folder, createdAt: now, updatedAt: now,
                       name: project.name, attribution: project.attribution,
                       attributionURL: project.attributionURL, recipe: project.recipe)
        try writeManifest(&copy)
        return copy
    }

    /// Moves the folder to the Trash rather than deleting it — a mis-click on a
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
        let scaled = downscale(image, maxPixels: maxPixels) ?? image
        let type = UTType.heic.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw LibraryError.storeFailed
        }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw LibraryError.storeFailed }
    }

    private static func downscale(_ image: CGImage, maxPixels: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxPixels else { return image }
        let f = Double(maxPixels) / Double(longest)
        let w = max(1, Int((Double(image.width) * f).rounded()))
        let h = max(1, Int((Double(image.height) * f).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
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

    /// Brings everything older than the project format forward, once.
    static func migrate() {
        migrateLegacySlots()
        migrateFlatEntries()
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
            // Keep the old basename as the folder name — it already carries the
            // timestamp and photo slug, and reusing it keeps ids stable.
            let id = heic.deletingPathExtension().lastPathComponent
            if adoptRenderedWallpaper(at: heic, copying: false, date: date, preferredID: id) {
                try? FileManager.default.removeItem(at: sidecar)
            }
        }
    }

    private static func flatCreatedAt(_ sidecar: URL) -> Date? {
        struct Flat: Codable { var createdAt: Date? }
        guard let data = try? Data(contentsOf: sidecar) else { return nil }
        return (try? decoder.decode(Flat.self, from: data))?.createdAt
    }

    /// Wraps a bare rendered wallpaper into a recipe-less project folder.
    @discardableResult
    private static func adoptRenderedWallpaper(at file: URL, copying: Bool, date: Date,
                                               preferredID: String? = nil) -> Bool {
        guard let dir = try? directory() else { return false }
        let id: String
        if let preferredID,
           !FileManager.default.fileExists(atPath: dir.appendingPathComponent(preferredID).path) {
            id = preferredID
        } else {
            id = uniqueID(in: dir, slug: nil, now: date)
        }
        let folder = dir.appendingPathComponent(id, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        else { return false }

        let target = folder.appendingPathComponent("wallpaper.heic")
        let moved: Bool
        if copying {
            moved = (try? FileManager.default.copyItem(at: file, to: target)) != nil
        } else {
            moved = (try? FileManager.default.moveItem(at: file, to: target)) != nil
        }
        guard moved else {
            try? FileManager.default.removeItem(at: folder)
            return false
        }

        var project = Project(id: id, url: folder, createdAt: date, updatedAt: date,
                              name: nil, attribution: nil, attributionURL: nil, recipe: nil)
        try? writeManifest(&project)
        return true
    }

    // MARK: Naming

    /// `20260804-101533-mountain-lake`, suffixed if that name is somehow taken.
    private static func uniqueID(in dir: URL, slug: String?, now: Date) -> String {
        let stamp = stampFormatter.string(from: now)
        let base = [stamp, slug].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "-")
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
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
