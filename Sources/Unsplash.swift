import Foundation
import AppKit

// MARK: - API models

struct UnsplashPhoto: Identifiable, Decodable {
    let id: String
    let slug: String?
    let width: Int
    let height: Int
    let color: String?
    let description: String?
    let alt_description: String?
    let urls: URLs
    let user: User
    let links: Links?

    struct URLs: Decodable {
        let raw: String
        let full: String
        let regular: String
        let small: String
        let thumb: String
    }
    struct User: Decodable {
        let name: String
        let username: String?
        let links: UserLinks?
        struct UserLinks: Decodable { let html: String? }
    }
    struct Links: Decodable {
        let download_location: String?
    }

    var displayTitle: String {
        description ?? alt_description ?? "Foto von \(user.name)"
    }
}

private struct SearchResponse: Decodable {
    let total: Int
    let total_pages: Int
    let results: [UnsplashPhoto]
}

// MARK: - Errors

enum UnsplashError: LocalizedError {
    case missingKey
    case invalidKey
    case rateLimited
    case http(Int)
    case badResponse
    case imageDecode

    var errorDescription: String? {
        switch self {
        case .missingKey:  return "Kein Unsplash Access-Key hinterlegt. Öffne die Einstellungen (⌘,)."
        case .invalidKey:  return "Unsplash lehnt den Access-Key ab (401). Bitte in den Einstellungen prüfen."
        case .rateLimited: return "Unsplash-Ratenlimit erreicht (403). Bitte etwas warten."
        case .http(let c): return "Unsplash-Fehler (HTTP \(c))."
        case .badResponse: return "Unerwartete Antwort von Unsplash."
        case .imageDecode: return "Das Bild konnte nicht geladen werden."
        }
    }
}

// MARK: - Service

struct UnsplashService {
    let accessKey: String

    private var authHeader: String { "Client-ID \(accessKey)" }

    func search(query: String, page: Int = 1, perPage: Int = 30) async throws -> [UnsplashPhoto] {
        let key = accessKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw UnsplashError.missingKey }

        var comps = URLComponents(string: "https://api.unsplash.com/search/photos")!
        comps.queryItems = [
            .init(name: "query", value: query),
            .init(name: "page", value: String(page)),
            .init(name: "per_page", value: String(perPage)),
            .init(name: "content_filter", value: "high"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("v1", forHTTPHeaderField: "Accept-Version")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UnsplashError.badResponse }
        switch http.statusCode {
        case 200: break
        case 401: throw UnsplashError.invalidKey
        case 403: throw UnsplashError.rateLimited
        default:  throw UnsplashError.http(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.results
    }

    /// Downloads a source image (no auth needed for the image CDN).
    func loadImage(from urlString: String) async throws -> CGImage {
        guard let url = URL(string: urlString) else { throw UnsplashError.badResponse }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw UnsplashError.imageDecode
        }
        return cg
    }

    /// Unsplash API guideline: ping the download endpoint when a photo is used.
    func trackDownload(_ downloadLocation: String) async {
        guard let url = URL(string: downloadLocation) else { return }
        var req = URLRequest(url: url)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }
}
