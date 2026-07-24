import Foundation
import UIKit

/// Copyright-safe online background search via Pexels and Pixabay.
enum OnlineBackgroundService {
    struct SearchResult: Identifiable, Equatable {
        let id: String
        let provider: OnlineBackgroundProvider
        let providerPhotoID: String
        let title: String
        let photographerName: String
        let photographerURL: URL?
        let photoPageURL: URL?
        let thumbURL: URL
        let downloadURL: URL
        let query: String
        let licenseName: String
        let licenseURL: URL?
        let attributionRequired: Bool

        var attributionLine: String {
            let name = photographerName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                return "Photo via \(provider.displayName)"
            }
            return "Photo by \(name) / \(provider.displayName)"
        }

        func provenance(fetchedAt: Date = Date()) -> ImageBackgroundProvenance {
            ImageBackgroundProvenance(
                provider: provider,
                providerPhotoID: providerPhotoID,
                photographerName: photographerName,
                photographerURL: photographerURL?.absoluteString,
                photoPageURL: photoPageURL?.absoluteString,
                licenseName: licenseName,
                licenseURL: licenseURL?.absoluteString,
                thumbURL: thumbURL.absoluteString,
                downloadURL: downloadURL.absoluteString,
                query: query,
                attributionRequired: attributionRequired,
                fetchedAt: fetchedAt
            )
        }
    }

    struct CollectionChip: Identifiable, Hashable {
        let id: String
        let title: String
        let query: String
    }

    /// Preset tags biased toward empty product / scene backgrounds (not people, products, or clutter).
    static let collectionChips: [CollectionChip] = [
        CollectionChip(
            id: "studio",
            title: "Studio",
            query: "empty photo studio seamless backdrop background white gray paper"
        ),
        CollectionChip(
            id: "staging",
            title: "Staging",
            query: "empty product staging tabletop surface podium background"
        ),
        CollectionChip(
            id: "natural",
            title: "Natural",
            query: "empty natural wood marble stone surface background texture"
        ),
        CollectionChip(
            id: "neutral",
            title: "Neutral",
            query: "empty seamless white gray beige paper backdrop background"
        ),
        CollectionChip(
            id: "shelves",
            title: "Shelves",
            query: "empty retail shelf store display background no products"
        ),
        CollectionChip(
            id: "lifestyle",
            title: "Lifestyle",
            query: "empty lifestyle table counter desk surface background"
        )
    ]

    /// Keeps free-text search focused on usable backgrounds.
    static func backgroundBiasedQuery(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let lower = trimmed.lowercased()
        let alreadyBiased =
            lower.contains("background")
            || lower.contains("backdrop")
            || lower.contains("seamless")
            || lower.contains("tabletop")
            || lower.contains("surface")
        if alreadyBiased { return trimmed }
        return "\(trimmed) empty background backdrop"
    }

    enum ServiceError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case httpStatus(Int)
        case decodeFailed
        case downloadFailed
        case unsupportedImage
        case allProvidersFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add Pexels/Pixabay API keys in Config/Secrets.local.xcconfig to search online backgrounds."
            case .invalidResponse:
                return "Unexpected response from a stock provider."
            case .httpStatus(let code):
                return "Stock search request failed (\(code))."
            case .decodeFailed:
                return "Couldn’t read search results."
            case .downloadFailed:
                return "Couldn’t download that background."
            case .unsupportedImage:
                return "Downloaded file isn’t a supported image."
            case .allProvidersFailed(let detail):
                return detail
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
        return URLSession(configuration: config)
    }()

    static var pexelsAPIKey: String { infoString("PexelsAPIKey") }
    static var pixabayAPIKey: String { infoString("PixabayAPIKey") }

    /// True when at least one free-stock provider key is configured.
    static var isConfigured: Bool { !pexelsAPIKey.isEmpty || !pixabayAPIKey.isEmpty }

    static var configuredProviderDisplayNames: [String] {
        var names: [String] = []
        if !pexelsAPIKey.isEmpty { names.append("Pexels") }
        if !pixabayAPIKey.isEmpty { names.append("Pixabay") }
        return names
    }

    static var attributionFooter: String {
        let names = configuredProviderDisplayNames
        if names.isEmpty {
            return "Free stock via Pexels & Pixabay when API keys are configured."
        }
        let joined = names.joined(separator: " & ")
        return "Free stock via \(joined). Commercial use allowed under each provider’s license."
    }

    /// Searches all configured providers in parallel and interleaves results.
    static func search(query: String, perPage: Int = 30) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard isConfigured else { throw ServiceError.missingAPIKey }

        let providerCount = max(configuredProviderDisplayNames.count, 1)
        let perSource = min(max(perPage / providerCount, 12), 40)

        var buckets: [OnlineBackgroundProvider: [SearchResult]] = [:]
        var failures: [String] = []

        await withTaskGroup(of: (OnlineBackgroundProvider, Result<[SearchResult], Error>).self) { group in
            if !pexelsAPIKey.isEmpty {
                group.addTask {
                    do {
                        let items = try await searchPexels(query: trimmed, perPage: perSource)
                        return (.pexels, .success(items))
                    } catch {
                        return (.pexels, .failure(error))
                    }
                }
            }
            if !pixabayAPIKey.isEmpty {
                group.addTask {
                    do {
                        let items = try await searchPixabay(query: trimmed, perPage: perSource)
                        return (.pixabay, .success(items))
                    } catch {
                        return (.pixabay, .failure(error))
                    }
                }
            }
            for await (provider, result) in group {
                switch result {
                case .success(let items):
                    buckets[provider] = items
                case .failure(let error):
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    failures.append("\(provider.displayName): \(message)")
                }
            }
        }

        let ordered = interleave(arrays: [
            buckets[.pexels] ?? [],
            buckets[.pixabay] ?? []
        ])

        if ordered.isEmpty {
            if failures.isEmpty {
                return []
            }
            throw ServiceError.allProvidersFailed(failures.joined(separator: " "))
        }
        return ordered
    }

    static func downloadImage(from url: URL) async throws -> UIImage {
        var request = URLRequest(url: url)
        request.setValue("ProductStudioPro/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.downloadFailed
        }
        guard let image = ImageImportDecoder.uiImage(from: data) ?? UIImage(data: data) else {
            throw ServiceError.unsupportedImage
        }
        return image
    }

    // MARK: - Providers

    private static func searchPexels(query: String, perPage: Int) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://api.pexels.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "orientation", value: "square")
        ]
        guard let url = components.url else { throw ServiceError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue(pexelsAPIKey, forHTTPHeaderField: "Authorization")
        request.setValue("ProductStudioPro/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.httpStatus(http.statusCode) }

        let decoded: PexelsSearchResponse
        do {
            decoded = try JSONDecoder().decode(PexelsSearchResponse.self, from: data)
        } catch {
            throw ServiceError.decodeFailed
        }

        return decoded.photos.compactMap { photo in
            guard let thumb = URL(string: photo.src.medium ?? photo.src.small ?? ""),
                  let download = URL(string: photo.src.large2x ?? photo.src.large ?? photo.src.original ?? "")
            else { return nil }

            let title: String
            if let alt = photo.alt?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
                title = String(alt.prefix(48))
            } else {
                title = "Pexels \(photo.id)"
            }

            return SearchResult(
                id: "pexels-\(photo.id)",
                provider: .pexels,
                providerPhotoID: String(photo.id),
                title: title,
                photographerName: photo.photographer ?? "Pexels photographer",
                photographerURL: photo.photographerURL.flatMap(URL.init(string:)),
                photoPageURL: photo.url.flatMap(URL.init(string:)),
                thumbURL: thumb,
                downloadURL: download,
                query: query,
                licenseName: "Pexels License",
                licenseURL: URL(string: "https://www.pexels.com/license/"),
                attributionRequired: false
            )
        }
    }

    private static func searchPixabay(query: String, perPage: Int) async throws -> [SearchResult] {
        // Pixabay allows 3...200 per_page.
        let clamped = min(max(perPage, 3), 200)
        var components = URLComponents(string: "https://pixabay.com/api/")!
        components.queryItems = [
            URLQueryItem(name: "key", value: pixabayAPIKey),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "image_type", value: "photo"),
            URLQueryItem(name: "orientation", value: "all"),
            URLQueryItem(name: "safesearch", value: "true"),
            URLQueryItem(name: "per_page", value: String(clamped))
        ]
        guard let url = components.url else { throw ServiceError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("ProductStudioPro/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.httpStatus(http.statusCode) }

        let decoded: PixabaySearchResponse
        do {
            decoded = try JSONDecoder().decode(PixabaySearchResponse.self, from: data)
        } catch {
            throw ServiceError.decodeFailed
        }

        return decoded.hits.compactMap { hit in
            let thumbString = hit.previewURL ?? hit.webformatURL
            let downloadString = hit.largeImageURL ?? hit.fullHDURL ?? hit.webformatURL
            guard let thumbString,
                  let downloadString,
                  let thumb = URL(string: thumbString),
                  let download = URL(string: downloadString)
            else { return nil }

            let title: String
            if let tags = hit.tags?.trimmingCharacters(in: .whitespacesAndNewlines), !tags.isEmpty {
                title = String(tags.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48) ?? "Pixabay \(hit.id)")
            } else {
                title = "Pixabay \(hit.id)"
            }

            let user = hit.user?.trimmingCharacters(in: .whitespacesAndNewlines)
            let photographer = (user?.isEmpty == false) ? user! : "Pixabay photographer"
            let photographerURL: URL? = {
                guard let user, !user.isEmpty, let userID = hit.userID else { return nil }
                return URL(string: "https://pixabay.com/users/\(user)-\(userID)/")
            }()

            return SearchResult(
                id: "pixabay-\(hit.id)",
                provider: .pixabay,
                providerPhotoID: String(hit.id),
                title: title,
                photographerName: photographer,
                photographerURL: photographerURL,
                photoPageURL: hit.pageURL.flatMap(URL.init(string:)),
                thumbURL: thumb,
                downloadURL: download,
                query: query,
                licenseName: "Pixabay Content License",
                licenseURL: URL(string: "https://pixabay.com/service/license/"),
                attributionRequired: false
            )
        }
    }

    // MARK: - Helpers

    private static func infoString(_ key: String) -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty || raw.hasPrefix("$(") { return "" }
        return raw
    }

    private static func interleave(arrays: [[SearchResult]]) -> [SearchResult] {
        var out: [SearchResult] = []
        var seen = Set<String>()
        let maxCount = arrays.map(\.count).max() ?? 0
        for index in 0..<maxCount {
            for array in arrays {
                guard index < array.count else { continue }
                let item = array[index]
                if seen.insert(item.id).inserted {
                    out.append(item)
                }
            }
        }
        return out
    }
}

// MARK: - Pexels DTOs

private struct PexelsSearchResponse: Decodable {
    let photos: [PexelsPhoto]
}

private struct PexelsPhoto: Decodable {
    let id: Int
    let url: String?
    let photographer: String?
    let alt: String?
    let src: PexelsSrc
    let photographerURL: String?

    enum CodingKeys: String, CodingKey {
        case id, url, photographer, alt, src
        case photographerURL = "photographer_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        photographer = try c.decodeIfPresent(String.self, forKey: .photographer)
        photographerURL = try c.decodeIfPresent(String.self, forKey: .photographerURL)
        alt = try c.decodeIfPresent(String.self, forKey: .alt)
        src = try c.decode(PexelsSrc.self, forKey: .src)
    }
}

private struct PexelsSrc: Decodable {
    let original: String?
    let large2x: String?
    let large: String?
    let medium: String?
    let small: String?
}

// MARK: - Pixabay DTOs

private struct PixabaySearchResponse: Decodable {
    let hits: [PixabayHit]
}

private struct PixabayHit: Decodable {
    let id: Int
    let pageURL: String?
    let previewURL: String?
    let webformatURL: String?
    let largeImageURL: String?
    let fullHDURL: String?
    let user: String?
    let userID: Int?
    let tags: String?

    enum CodingKeys: String, CodingKey {
        case id
        case pageURL = "pageURL"
        case previewURL = "previewURL"
        case webformatURL = "webformatURL"
        case largeImageURL = "largeImageURL"
        case fullHDURL = "fullHDURL"
        case user
        case userID = "user_id"
        case tags
    }
}
