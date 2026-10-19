import Foundation
import AppKit

// MARK: - API models

/// One file from Wikimedia Commons, as returned by the MediaWiki `imageinfo` API.
struct CommonsPhoto: Identifiable, Decodable {
    let pageid: Int
    let title: String              // "File:Sunset over mountains.jpg"
    let imageinfo: [ImageInfo]

    var id: Int { pageid }

    struct ImageInfo: Decodable {
        let url: String            // full-resolution original
        let width: Int
        let height: Int
        let size: Int               // original file size in bytes
        let thumburl: String?      // present when `iiurlwidth` was requested
        let extmetadata: ExtMetadata?
    }

    struct ExtMetadata: Decodable {
        let Artist: MetaValue?
        let LicenseShortName: MetaValue?
        let ImageDescription: MetaValue?
    }

    struct MetaValue: Decodable { let value: String }

    private var info: ImageInfo? { imageinfo.first }

    var thumbURL: String? { info?.thumburl }
    var fullURL: String? { info?.url }
    var fileSize: Int? { info?.size }

    /// "File:Sunset over mountains.jpg" → "Sunset over mountains"
    var baseTitle: String {
        var t = title
        if t.hasPrefix("File:") { t.removeFirst("File:".count) }
        if let dot = t.lastIndex(of: ".") { t = String(t[..<dot]) }
        return t
    }

    /// Plain-text description, HTML-stripped — falls back to the file's base title
    /// since Commons has no dedicated alt-text field.
    var displayTitle: String {
        Self.stripHTML(info?.extmetadata?.ImageDescription?.value) ?? baseTitle
    }

    /// The photographer's name, HTML-stripped — `extmetadata` values are often a raw
    /// `<a href="…">Name</a>` snippet rather than plain text.
    var artist: String? {
        Self.stripHTML(info?.extmetadata?.Artist?.value)
    }

    private static func stripHTML(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let decoded = stripped.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Attribution

/// Every Commons file carries its own CC licence, which requires crediting the
/// author with a link back to the file page. Building the URL in one place keeps
/// the encoding from being forgotten on one of the call sites.
enum CommonsAttribution {
    static let host = "commons.wikimedia.org"

    /// The canonical file page, e.g. `.../wiki/File:Sunset_over_mountains.jpg` — its
    /// own description page states the exact licence, which is why crediting it
    /// (rather than just the photographer's name) satisfies the licence requirement.
    static func pageURL(title: String) -> URL? {
        var comps = URLComponents(string: "https://commons.wikimedia.org/wiki/")!
        comps.path += title.replacingOccurrences(of: " ", with: "_")
        return comps.url
    }

    static var homeURL: URL { URL(string: "https://commons.wikimedia.org")! }

    /// Does this stored attribution URL point at Commons? That is how a look knows
    /// whether it owes a credit — local files and Photos assets carry no URL.
    static func isCommons(_ raw: String?) -> Bool {
        guard let raw, let host = URL(string: raw)?.host() else { return false }
        return host == Self.host
    }
}

// MARK: - Errors

enum CommonsError: LocalizedError {
    case http(Int)
    case badResponse
    case imageDecode

    var errorDescription: String? {
        switch self {
        case .http(let c): return L("Wikimedia-Commons-Fehler (HTTP %ld).", c)
        case .badResponse: return L("Unerwartete Antwort von Wikimedia Commons.")
        case .imageDecode: return L("Das Bild konnte nicht geladen werden.")
        }
    }
}

// MARK: - Service

/// Talks to the public Wikimedia Commons API (`commons.wikimedia.org/w/api.php`).
/// No API key and no approval process — Commons' entire purpose is free reuse of
/// its media, so third-party apps just identify themselves with a descriptive
/// User-Agent. See https://foundation.wikimedia.org/wiki/Policy:User-Agent_policy
struct CommonsService {
    private static let userAgent = "Lurent/1.0 (https://lurent.app) macOS"
    private static let endpoint = URL(string: "https://commons.wikimedia.org/w/api.php")!

    /// Rotating search terms for the launch grid — Commons has no popularity
    /// ranking, so a curated category (see `curatedSearch`) stands in for it.
    private static let curatedTerms = [
        "landscape", "mountains", "ocean", "forest", "sunset", "clouds", "desert", "lake",
    ]

    /// Commons' own "recognised picture" categories, strongest aesthetic bar first.
    /// Featured Pictures are judged on "wow factor", not just technical correctness,
    /// so they read as photography rather than the documentary/reference material
    /// that makes up most of Commons — but the category is small enough that a
    /// narrow search term can come up short, which is what Quality Images backs up.
    private static let featuredCategory = "Featured pictures on Wikimedia Commons"
    private static let qualityCategory = "Quality images"

    func search(query: String, perPage: Int = 30) async throws -> [CommonsPhoto] {
        try await curatedSearch(text: query, perPage: perPage)
    }

    /// A rotating set of curated, high-quality photos for the launch grid — picks a
    /// random term on every call so the picker isn't identical on every launch.
    func curatedPhotos(perPage: Int = 12) async throws -> [CommonsPhoto] {
        let term = Self.curatedTerms.randomElement()!
        let photos = try await curatedSearch(text: term, perPage: perPage * 3)
        return Array(photos.shuffled().prefix(perPage))
    }

    /// Searches Featured Pictures first and only tops up with the broader Quality
    /// Images tier when that alone doesn't fill the page — best-effort: a failed
    /// top-up still returns the Featured Pictures results rather than failing the
    /// whole search.
    private func curatedSearch(text: String, perPage: Int) async throws -> [CommonsPhoto] {
        let featured = try await run(params: [
            "generator": "search",
            "gsrsearch": "\(text) filetype:bitmap deepcategory:\"\(Self.featuredCategory)\"",
            "gsrnamespace": "6",
            "gsrlimit": String(perPage),
        ], thumbWidth: 400)
        guard featured.count < perPage else { return featured }

        let seen = Set(featured.map(\.pageid))
        let quality = (try? await run(params: [
            "generator": "search",
            "gsrsearch": "\(text) filetype:bitmap deepcategory:\"\(Self.qualityCategory)\"",
            "gsrnamespace": "6",
            "gsrlimit": String(perPage),
        ], thumbWidth: 400)) ?? []
        return featured + quality.filter { !seen.contains($0.pageid) }
    }

    /// Above this, the true original is impractical to download on demand (some
    /// Commons scans/panoramas run to several hundred MB) — below it, downloading
    /// the original outright beats Commons' auto-generated thumbnail, which both
    /// caps out around 3840px on a large source (well short of the 6016px wallpaper
    /// master, silently — the API's `thumbwidth` keeps echoing the requested size
    /// even when it had to cap it) and re-compresses harder than most originals.
    private static let maxOriginalDownloadBytes = 40_000_000

    /// Re-fetches a single file at full working resolution — the search results
    /// above only carry a small thumbnail so the grid stays cheap to load. Tries
    /// the best-quality source first and falls back to the other rendition on
    /// failure, so one bad/oversized file doesn't make a photo unselectable.
    func loadImage(title: String) async throws -> CGImage {
        let photos = try await run(params: ["titles": title], thumbWidth: wallpaperMasterSide)
        guard let photo = photos.first else { throw CommonsError.badResponse }

        let preferOriginal = (photo.fileSize ?? .max) <= Self.maxOriginalDownloadBytes
        let candidates = preferOriginal
            ? [photo.fullURL, photo.thumbURL]
            : [photo.thumbURL, photo.fullURL]

        for candidate in candidates.compactMap({ $0 }) {
            guard let url = URL(string: candidate) else { continue }
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let image = NSImage(data: data),
               let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cg
            }
        }
        throw CommonsError.imageDecode
    }

    private func run(params: [String: String], thumbWidth: Int) async throws -> [CommonsPhoto] {
        var comps = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        var items = params.map { URLQueryItem(name: $0, value: $1) }
        items.append(contentsOf: [
            .init(name: "action", value: "query"),
            .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "url|size|extmetadata"),
            .init(name: "iiurlwidth", value: String(thumbWidth)),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
        ])
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CommonsError.badResponse }
        guard http.statusCode == 200 else { throw CommonsError.http(http.statusCode) }

        let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)
        return decoded.query?.pages?.filter { !$0.imageinfo.isEmpty } ?? []
    }

    private struct QueryResponse: Decodable {
        let query: Query?
        struct Query: Decodable { let pages: [CommonsPhoto]? }
    }
}
