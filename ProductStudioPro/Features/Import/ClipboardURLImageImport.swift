import Foundation
import UIKit

enum ClipboardURLImageImportError: LocalizedError {
    case nothingToImport
    case invalidURL
    case downloadFailed
    case unsupportedImage

    var errorDescription: String? {
        switch self {
        case .nothingToImport:
            return "Copy an image or image URL, then try again."
        case .invalidURL:
            return "That link doesn’t look like a valid image URL."
        case .downloadFailed:
            return "Couldn’t download the image from that URL."
        case .unsupportedImage:
            return "The downloaded data isn’t a supported image format."
        }
    }
}

/// Reads copied images / URLs and downloads remote image bytes for catalog import.
enum ClipboardURLImageImport {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 90
        return URLSession(configuration: config)
    }()

    struct ClipboardSnapshot {
        let images: [UIImage]
        let urls: [URL]
        let suggestedURLText: String

        var hasContent: Bool { !images.isEmpty || !urls.isEmpty }
        var totalImportCount: Int { images.count + urls.count }
    }

    static func readClipboard() -> ClipboardSnapshot {
        let images = imagesFromPasteboard()
        let string = UIPasteboard.general.string ?? ""
        let urls = httpURLs(in: string)
        let suggested = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClipboardSnapshot(images: images, urls: urls, suggestedURLText: suggested)
    }

    static func imagesFromPasteboard() -> [UIImage] {
        if let images = UIPasteboard.general.images?.filter({ $0.size.width > 1 && $0.size.height > 1 }), !images.isEmpty {
            return images
        }
        if let image = UIPasteboard.general.image, image.size.width > 1, image.size.height > 1 {
            return [image]
        }
        return []
    }

    static func httpURLs(in text: String) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()

        func append(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  !seen.contains(trimmed)
            else { return }
            seen.insert(trimmed)
            found.append(url)
        }

        append(text)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match, let url = match.url else { return }
                append(url.absoluteString)
            }
        }

        if let direct = UIPasteboard.general.url {
            append(direct.absoluteString)
        }

        return found
    }

    static func parseURL(from text: String) -> URL? {
        httpURLs(in: text).first
    }

    static func downloadImage(from url: URL) async throws -> UIImage {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
            throw ClipboardURLImageImportError.downloadFailed
        }
        let image: UIImage? = autoreleasepool {
            ImageImportDecoder.uiImage(from: data) ?? UIImage(data: data)
        }
        guard let image else { throw ClipboardURLImageImportError.unsupportedImage }
        return image
    }
}
