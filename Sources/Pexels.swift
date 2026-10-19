import Foundation
import AppKit

// MARK: - API models

/// One photo from Pexels, as returned by `api.pexels.com/v1`.
struct PexelsPhoto: Identifiable, Decodable {
    let id: Int
    let url: String                 // pexels.com page for this photo
    let photographer: String
    let photographerURL: String
    let alt: String?
    let src: Source

    struct Source: Decodable {
        let original: String        // full-resolution upload
        let large2x: String         // ~940px, used for the grid thumbnail
    }

    enum CodingKeys: String, CodingKey {
        case id, url, photographer, alt, src
        case photographerURL = "photographer_url"
    }

    var thumbURL: String { src.large2x }
    var fullURL: String { src.original }
    var displayTitle: String { alt?.isEmpty == false ? alt! : "Foto von \(photographer)" }
}

// MARK: - Attribution

/// Pexels requires a prominent link back to Pexels wherever results are shown;
/// crediting the photographer by name is recommended on top of that.
/// See https://www.pexels.com/api/documentation/#guidelines
enum PexelsAttribution {
    static let host = "pexels.com"

    static var homeURL: URL { URL(string: "https://www.pexels.com")! }

    /// Does this stored attribution URL point at Pexels? That is how a look knows
    /// whether it owes a credit — local files and Photos assets carry no URL.
    static func isPexels(_ raw: String?) -> Bool {
        guard let raw, let host = URL(string: raw)?.host() else { return false }
        return host == Self.host || host.hasSuffix(".\(Self.host)")
    }
}

// MARK: - Errors

enum PexelsError: LocalizedError {
    case rateLimited
    case http(Int)
    case badResponse
    case imageDecode

    var errorDescription: String? {
        switch self {
        case .rateLimited: return L("Pexels-Ratenlimit erreicht (429). Bitte etwas warten.")
        case .http(let c): return L("Pexels-Fehler (HTTP %ld).", c)
        case .badResponse: return L("Unerwartete Antwort von Pexels.")
        case .imageDecode: return L("Das Bild konnte nicht geladen werden.")
        }
    }
}

// MARK: - Service

/// Talks to Pexels through our own caching Worker (`workers/pexels-cache`), never
/// to api.pexels.com directly: the Worker holds the API key, so none ships inside
/// the app, and it caches identical searches so every install shares one upstream
/// request instead of spending Pexels' small per-key quota one search at a time.
/// Only the JSON goes through it — the photos themselves come straight from
/// Pexels' image CDN, which needs no key.
struct PexelsService {
    private static let endpoint = "https://pexels.lurent.app"

    func search(query: String, perPage: Int = 30) async throws -> [PexelsPhoto] {
        try await run(path: "search", params: ["query": query, "per_page": String(perPage)])
    }

    /// Pexels' own hand-picked feed — a random page rotates the launch grid
    /// without the category/shuffle dance Commons needs.
    func curatedPhotos(perPage: Int = 12) async throws -> [PexelsPhoto] {
        try await run(path: "curated", params: [
            "page": String(Int.random(in: 1...30)), "per_page": String(perPage),
        ])
    }

    /// Downloads the original upload directly — Pexels doesn't cap on-the-fly
    /// renditions the way Commons does, so there's no capped-thumbnail fallback
    /// dance needed here.
    func loadImage(from urlString: String) async throws -> CGImage {
        guard let url = URL(string: urlString) else { throw PexelsError.badResponse }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw PexelsError.imageDecode
        }
        return cg
    }

    private func run(path: String, params: [String: String]) async throws -> [PexelsPhoto] {
        var comps = URLComponents(string: "\(Self.endpoint)/\(path)")!
        comps.queryItems = params.map { URLQueryItem(name: $0, value: $1) }

        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse else { throw PexelsError.badResponse }
        switch http.statusCode {
        case 200: break
        case 429: throw PexelsError.rateLimited
        default:  throw PexelsError.http(http.statusCode)
        }
        return try JSONDecoder().decode(SearchResponse.self, from: data).photos
    }

    private struct SearchResponse: Decodable { let photos: [PexelsPhoto] }
}
