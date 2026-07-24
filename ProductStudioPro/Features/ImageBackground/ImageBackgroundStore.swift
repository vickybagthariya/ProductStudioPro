import Foundation
import UIKit

struct StoredBackgroundRecord: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var source: ImageBackgroundSource
    var importedAt: Date
    var fileName: String
    var thumbnailFileName: String
    var provenance: ImageBackgroundProvenance?

    enum CodingKeys: String, CodingKey {
        case id, title, source, importedAt, fileName, thumbnailFileName, provenance
    }

    init(
        id: String,
        title: String,
        source: ImageBackgroundSource,
        importedAt: Date,
        fileName: String,
        thumbnailFileName: String,
        provenance: ImageBackgroundProvenance? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.importedAt = importedAt
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.provenance = provenance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        source = try c.decode(ImageBackgroundSource.self, forKey: .source)
        importedAt = try c.decode(Date.self, forKey: .importedAt)
        fileName = try c.decode(String.self, forKey: .fileName)
        thumbnailFileName = try c.decode(String.self, forKey: .thumbnailFileName)
        provenance = try c.decodeIfPresent(ImageBackgroundProvenance.self, forKey: .provenance)
    }
}

/// Persists user-imported and online backgrounds in Application Support.
final class ImageBackgroundStore {
    static let shared = ImageBackgroundStore()

    private let folderName = "ProductStudioBackgrounds"
    private let manifestName = "manifest.json"
    private let recentKey = "imageBackgroundRecentIDs"
    private let maxRecent = 20

    private var records: [StoredBackgroundRecord] = []
    private var loaded = false

    private init() {}

    // MARK: - Public API

    var allRecords: [StoredBackgroundRecord] {
        loadIfNeeded()
        return records.sorted { $0.importedAt > $1.importedAt }
    }

    var recentIDs: [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    func records(for source: ImageBackgroundSource) -> [StoredBackgroundRecord] {
        allRecords.filter { $0.source == source }
    }

    func record(id: String) -> StoredBackgroundRecord? {
        allRecords.first { $0.id == id }
    }

    func record(provider: OnlineBackgroundProvider, photoID: String) -> StoredBackgroundRecord? {
        allRecords.first {
            guard let provenance = $0.provenance else { return false }
            return provenance.provider == provider && provenance.providerPhotoID == photoID
        }
    }

    @discardableResult
    func importImage(
        _ image: UIImage,
        source: ImageBackgroundSource,
        title: String? = nil,
        provenance: ImageBackgroundProvenance? = nil
    ) throws -> StoredBackgroundRecord {
        loadIfNeeded()

        if let provenance,
           let existing = record(provider: provenance.provider, photoID: provenance.providerPhotoID) {
            markRecentlyUsed(existing.id)
            return existing
        }

        let id = UUID().uuidString
        let fileName = "custom_\(id).jpg"
        let thumbName = "custom_\(id)_thumb.jpg"

        guard let fullData = jpegData(from: image, maxLongEdge: 2048, quality: 0.88) else {
            throw ImageBackgroundStoreError.encodeFailed
        }
        try write(data: fullData, fileName: fileName)

        let thumbImage = downscale(image, maxLongEdge: 256)
        guard let thumbData = jpegData(from: thumbImage, maxLongEdge: 256, quality: 0.82) else {
            throw ImageBackgroundStoreError.encodeFailed
        }
        try write(data: thumbData, fileName: thumbName)

        let record = StoredBackgroundRecord(
            id: id,
            title: title ?? defaultTitle(for: source),
            source: source,
            importedAt: Date(),
            fileName: fileName,
            thumbnailFileName: thumbName,
            provenance: provenance
        )
        records.insert(record, at: 0)
        try saveManifest()
        markRecentlyUsed(id)
        ImageBackgroundAssetLoader.invalidateCache()
        return record
    }

    func image(for id: String) -> UIImage? {
        guard let record = record(id: id) else { return nil }
        let url = fileURL(for: record.fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ImageImportDecoder.uiImage(from: data) ?? UIImage(data: data)
    }

    func thumbnail(for id: String) -> UIImage? {
        guard let record = record(id: id) else { return nil }
        let url = fileURL(for: record.thumbnailFileName)
        guard let data = try? Data(contentsOf: url) else { return image(for: id) }
        return ImageImportDecoder.uiImage(from: data) ?? UIImage(data: data)
    }

    func delete(id: String) {
        loadIfNeeded()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records.remove(at: index)
        try? FileManager.default.removeItem(at: fileURL(for: record.fileName))
        try? FileManager.default.removeItem(at: fileURL(for: record.thumbnailFileName))
        try? saveManifest()
        removeFromRecent(id)
        ImageBackgroundAssetLoader.invalidateCache()
    }

    func markRecentlyUsed(_ id: String) {
        var recent = recentIDs.filter { $0 != id }
        recent.insert(id, at: 0)
        if recent.count > maxRecent {
            recent = Array(recent.prefix(maxRecent))
        }
        UserDefaults.standard.set(recent, forKey: recentKey)
    }

    func definition(for record: StoredBackgroundRecord) -> ImageBackgroundDefinition {
        // Online stock: fixed 95% fill via fillRatio — don't shrink via staging/defaultScale.
        if record.source == .online {
            return ImageBackgroundDefinition(
                id: "custom.\(record.id)",
                title: record.title,
                categorySlug: ImageBackgroundCategory.importedCustom.slug,
                resourcePath: nil,
                isStaging: false,
                surfaceLineY: nil,
                defaultScale: 1.0,
                defaultX: 0.5,
                defaultY: 0.52
            )
        }

        let stagingHints = ["shelf", "table", "counter", "desk", "marble", "wood", "surface"]
        let haystack = record.title.lowercased()
        let isStaging = stagingHints.contains { haystack.contains($0) }
        return ImageBackgroundDefinition(
            id: "custom.\(record.id)",
            title: record.title,
            categorySlug: ImageBackgroundCategory.importedCustom.slug,
            resourcePath: nil,
            isStaging: isStaging,
            surfaceLineY: isStaging ? 0.78 : nil,
            defaultScale: isStaging ? 0.82 : 0.88,
            defaultX: 0.5,
            defaultY: isStaging ? 0.78 : 0.52
        )
    }

    // MARK: - Private

    enum ImageBackgroundStoreError: LocalizedError {
        case encodeFailed
        case folderUnavailable

        var errorDescription: String? {
            switch self {
            case .encodeFailed: return "Could not save the imported image."
            case .folderUnavailable: return "Background storage is unavailable."
            }
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        ensureFolder()
        let url = manifestURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([StoredBackgroundRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    private func saveManifest() throws {
        ensureFolder()
        let data = try JSONEncoder().encode(records)
        try data.write(to: manifestURL(), options: .atomic)
    }

    private func ensureFolder() {
        let url = folderURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func folderURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    private func manifestURL() -> URL {
        folderURL().appendingPathComponent(manifestName)
    }

    private func fileURL(for fileName: String) -> URL {
        folderURL().appendingPathComponent(fileName)
    }

    private func write(data: Data, fileName: String) throws {
        ensureFolder()
        try data.write(to: fileURL(for: fileName), options: .atomic)
    }

    private func defaultTitle(for source: ImageBackgroundSource) -> String {
        switch source {
        case .photos: return "Imported Photo"
        case .files: return "Imported File"
        case .clipboard: return "Clipboard Image"
        case .url: return "Imported URL"
        case .saved: return "Saved Background"
        case .bundled: return "Custom Background"
        case .online: return "Online Background"
        }
    }

    private func removeFromRecent(_ id: String) {
        let recent = recentIDs.filter { $0 != id }
        UserDefaults.standard.set(recent, forKey: recentKey)
    }

    private func downscale(_ image: UIImage, maxLongEdge: Int) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > CGFloat(maxLongEdge) else { return image }
        let scale = CGFloat(maxLongEdge) / longest
        let newSize = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func jpegData(from image: UIImage, maxLongEdge: Int, quality: CGFloat) -> Data? {
        let scaled = downscale(image, maxLongEdge: maxLongEdge)
        return scaled.jpegData(compressionQuality: quality)
    }
}
