import UIKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Configuration

enum StylePreviewStripConfig {
    static let previewLongEdge: CGFloat = 96

    /// Instant strip looks — pre-warmed on canvas display.
    static let coreFilters = ExportPhotoFilter.adjustSheetStyleStripCases

    /// Full Photos-style library (core first, then extended).
    static let allStripFilters: [ExportPhotoFilter] = ExportPhotoFilter.photosStylePickerCases

    static let extendedFilters: [ExportPhotoFilter] = {
        let coreIDs = Set(coreFilters.map(\.rawValue))
        return allStripFilters.filter { !coreIDs.contains($0.rawValue) }
    }()
}

// MARK: - Revision & keys

@MainActor
final class StylePreviewCacheRevisionStore {
    static let shared = StylePreviewCacheRevisionStore()

    private var revisions: [UUID: Int] = [:]

    private init() {}

    func revision(for productID: UUID) -> Int {
        revisions[productID] ?? 0
    }

    func cacheKey(for productID: UUID) -> String {
        "\(productID.uuidString)-r\(revision(for: productID))"
    }

    /// Bumps revision and drops cached thumbs for this product so pre-warm regenerates the new look.
    func invalidate(productID: UUID, reason: String) {
        revisions[productID, default: 0] += 1
        StylePreviewThumbnailCache.shared.invalidate(productID: productID)
    }
}

// MARK: - Cache

/// In-memory cache so reopening Adjust on the same photo feels instant (Photos-like).
final class StylePreviewThumbnailCache: @unchecked Sendable {
    static let shared = StylePreviewThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var keysByProductID: [String: Set<String>] = [:]

    private init() {
        cache.countLimit = 64
        cache.totalCostLimit = 12 * 1024 * 1024
    }

    func image(cacheKey: String, filter: ExportPhotoFilter) -> UIImage? {
        cache.object(forKey: compositeKey(cacheKey, filter: filter))
    }

    func store(_ image: UIImage, productID: UUID, cacheKey: String, filter: ExportPhotoFilter) {
        let key = compositeKey(cacheKey, filter: filter)
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
        cache.setObject(image, forKey: key, cost: cost)
        let productKey = productID.uuidString
        lock.lock()
        keysByProductID[productKey, default: []].insert(key as String)
        lock.unlock()
    }

    func isComplete(productID: UUID, cacheKey: String, filters: [ExportPhotoFilter]) -> Bool {
        filters.allSatisfy { image(cacheKey: cacheKey, filter: $0) != nil }
    }

    func invalidate(productID: UUID) {
        let productKey = productID.uuidString
        lock.lock()
        let keys = keysByProductID.removeValue(forKey: productKey) ?? []
        lock.unlock()
        for key in keys {
            cache.removeObject(forKey: key as NSString)
        }
    }

    func removeAll() {
        lock.lock()
        keysByProductID.removeAll()
        lock.unlock()
        cache.removeAllObjects()
    }

    private func compositeKey(_ cacheKey: String, filter: ExportPhotoFilter) -> NSString {
        "\(cacheKey)|\(filter.rawValue)|lanczos-v3" as NSString
    }
}

// MARK: - Pipeline (small bitmap → filter → thumb)

enum StylePreviewPipeline {
    /// `highQualityDownsample` keeps crisp edges on the 96px proxy without slowing the streaming render.
    private static let ciContext = CIContext(options: [
        .cacheIntermediates: true,
        .useSoftwareRenderer: false,
        .highQualityDownsample: true,
    ])

    /// Downsample once; all strip filters run on this tiny bitmap (not full export resolution).
    ///
    /// Uses `kCIFilterLanczosScaleTransform` so the small proxy keeps sharp edge fidelity that
    /// matches the high-res style output — plain affine downsampling produced soft/blurry thumbs.
    static func prepareThumbnailBase(from image: UIImage, maxLongEdge: CGFloat) -> UIImage? {
        guard let source = ImageProcessor.normalizedCGImage(image) else { return nil }
        let w = CGFloat(source.width), h = CGFloat(source.height)
        guard w > 0, h > 0 else { return nil }

        let scale = min(1, maxLongEdge / max(w, h))
        let tw: Int
        let th: Int
        if scale >= 0.999 {
            tw = Int(w)
            th = Int(h)
        } else {
            tw = max(1, Int(floor(w * scale)))
            th = max(1, Int(floor(h * scale)))
        }

        let ci = CIImage(cgImage: source)
        let scaled: CIImage
        if scale >= 0.999 {
            scaled = ci
        } else {
            scaled = lanczosScaled(ci, scale: scale, fallbackTargetSize: (tw, th), sourceSize: (w, h))
        }
        let rect = CGRect(x: 0, y: 0, width: tw, height: th)
        guard let out = ciContext.createCGImage(scaled, from: rect) else { return nil }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }

    /// High-fidelity Lanczos downscale; falls back to affine transform if the filter is unavailable.
    private static func lanczosScaled(
        _ image: CIImage,
        scale: CGFloat,
        fallbackTargetSize: (Int, Int),
        sourceSize: (CGFloat, CGFloat)
    ) -> CIImage {
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = image
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = 1
        if let output = lanczos.outputImage {
            let (tw, th) = fallbackTargetSize
            let crop = CGRect(x: 0, y: 0, width: tw, height: th)
            return output.cropped(to: crop)
        }
        let (tw, th) = fallbackTargetSize
        let (w, h) = sourceSize
        return image.transformed(by: CGAffineTransform(scaleX: CGFloat(tw) / w, y: CGFloat(th) / h))
    }

    /// Independent bitmap for cache entries (avoids sharing backing store with proxy base).
    static func uniqueImageCopy(from image: UIImage) -> UIImage? {
        guard let source = ImageProcessor.normalizedCGImage(image) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        guard let out = ciContext.createCGImage(CIImage(cgImage: source), from: rect) else { return nil }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }

    static func applyFilter(_ filter: ExportPhotoFilter, to base: UIImage) -> UIImage {
        if filter == .none || filter == .standard {
            return uniqueImageCopy(from: base) ?? base
        }
        return ImageProcessor.applyPhotoExportFilterForStylePreview(base, filter: filter)
    }
}

// MARK: - Actor

/// Off-main-thread style strip: downsample once, stream thumbnails one-by-one (Photos-like perceived speed).
actor StylePreviewThumbnailRenderer {
    static let shared = StylePreviewThumbnailRenderer()

    private var activePrewarmID: String?

    /// Fill cache for core adjust-sheet styles without touching the UI (canvas pre-warm).
    func prewarm(
        productID: UUID,
        from image: UIImage,
        cacheKey: String,
        imageID: String,
        filters: [ExportPhotoFilter] = StylePreviewStripConfig.coreFilters,
        maxLongEdge: CGFloat = StylePreviewStripConfig.previewLongEdge
    ) async {
        if StylePreviewThumbnailCache.shared.isComplete(productID: productID, cacheKey: cacheKey, filters: filters) {
            print("🎨 DesignSystem: Style cache pre-warmed for [\(imageID)]")
            return
        }

        activePrewarmID = imageID
        defer {
            if activePrewarmID == imageID { activePrewarmID = nil }
        }

        for await (filter, thumb) in streamThumbnails(
            from: image,
            productID: productID,
            filters: filters,
            extendedFilters: [],
            maxLongEdge: maxLongEdge,
            cacheKey: cacheKey
        ) {
            if Task.isCancelled { return }
            _ = (filter, thumb)
        }

        guard !Task.isCancelled, activePrewarmID == imageID else { return }
        print("🎨 DesignSystem: Style cache pre-warmed for [\(imageID)]")
    }

    /// One-time 96px proxy for a source image (shared across core + extended phases).
    func prepareThumbnailBase(from image: UIImage, maxLongEdge: CGFloat = StylePreviewStripConfig.previewLongEdge) -> UIImage? {
        autoreleasepool {
            StylePreviewPipeline.prepareThumbnailBase(from: image, maxLongEdge: maxLongEdge)
        }
    }

    /// Single-filter thumbnail for a visibility-driven strip cell (cache → render → store).
    func thumbnail(
        for filter: ExportPhotoFilter,
        proxyBase: UIImage,
        productID: UUID,
        cacheKey: String
    ) async -> UIImage {
        if let cached = StylePreviewThumbnailCache.shared.image(cacheKey: cacheKey, filter: filter) {
            return cached
        }
        let thumb: UIImage = autoreleasepool {
            StylePreviewPipeline.applyFilter(filter, to: proxyBase)
        }
        StylePreviewThumbnailCache.shared.store(thumb, productID: productID, cacheKey: cacheKey, filter: filter)
        return thumb
    }

    /// Progressive delivery — core filters first, then extended library (single downsample pass).
    func streamThumbnails(
        from image: UIImage,
        productID: UUID,
        filters: [ExportPhotoFilter],
        extendedFilters: [ExportPhotoFilter] = [],
        maxLongEdge: CGFloat,
        cacheKey: String
    ) -> AsyncStream<(ExportPhotoFilter, UIImage)> {
        AsyncStream { continuation in
            let work = Task(priority: .utility) {
                guard let base = prepareThumbnailBase(from: image, maxLongEdge: maxLongEdge) else {
                    continuation.finish()
                    return
                }
                streamFilterPhases(
                    base: base,
                    productID: productID,
                    phases: [filters, extendedFilters].filter { !$0.isEmpty },
                    cacheKey: cacheKey,
                    continuation: continuation
                )
            }
            continuation.onTermination = { @Sendable _ in
                work.cancel()
            }
        }
    }

    /// Stream filters using an already-downsampled proxy (no second full-image downsample).
    func streamThumbnails(
        fromPreparedBase base: UIImage,
        productID: UUID,
        filters: [ExportPhotoFilter],
        cacheKey: String
    ) -> AsyncStream<(ExportPhotoFilter, UIImage)> {
        AsyncStream { continuation in
            let work = Task {
                streamFilterPhases(
                    base: base,
                    productID: productID,
                    phases: [filters],
                    cacheKey: cacheKey,
                    continuation: continuation
                )
            }
            continuation.onTermination = { @Sendable _ in
                work.cancel()
            }
        }
    }

    private func streamFilterPhases(
        base: UIImage,
        productID: UUID,
        phases: [[ExportPhotoFilter]],
        cacheKey: String,
        continuation: AsyncStream<(ExportPhotoFilter, UIImage)>.Continuation
    ) {
        for filterList in phases {
            if Task.isCancelled { break }
            for filter in filterList {
                if Task.isCancelled { break }

                if let cached = StylePreviewThumbnailCache.shared.image(cacheKey: cacheKey, filter: filter) {
                    continuation.yield((filter, cached))
                    continue
                }

                let thumb: UIImage = autoreleasepool {
                    StylePreviewPipeline.applyFilter(filter, to: base)
                }

                StylePreviewThumbnailCache.shared.store(thumb, productID: productID, cacheKey: cacheKey, filter: filter)
                continuation.yield((filter, thumb))
            }
        }
        continuation.finish()
    }
}

// MARK: - Queue list thumbnails (keeps 50+ row scroll light on memory)

enum QueueRowThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 96
        c.totalCostLimit = 6 * 1024 * 1024
        return c
    }()

    private static func cacheKey(productID: UUID, image: UIImage, displayPoints: CGFloat, screenScale: CGFloat) -> NSString {
        let pixelEdge = displayPoints * max(screenScale, 2) * 1.2
        let imageKey = image.cgImage.map { Unmanaged.passUnretained($0).toOpaque() } ?? Unmanaged.passUnretained(image).toOpaque()
        return "\(productID.uuidString)-\(imageKey)-\(Int(pixelEdge))" as NSString
    }

    static func cached(for productID: UUID, image: UIImage, displayPoints: CGFloat = 56) -> UIImage? {
        let scale = UIScreen.main.scale
        return cache.object(forKey: cacheKey(productID: productID, image: image, displayPoints: displayPoints, screenScale: scale))
    }

    static func thumbnail(for productID: UUID, image: UIImage, displayPoints: CGFloat = 56) -> UIImage {
        let scale = UIScreen.main.scale
        let key = cacheKey(productID: productID, image: image, displayPoints: displayPoints, screenScale: scale)
        if let hit = cache.object(forKey: key) { return hit }
        let pixelEdge = displayPoints * max(scale, 2) * 1.2
        guard let thumb = StylePreviewPipeline.prepareThumbnailBase(from: image, maxLongEdge: pixelEdge) else { return image }
        let cost = thumb.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
        cache.setObject(thumb, forKey: key, cost: cost)
        return thumb
    }

    static func thumbnailAsync(for productID: UUID, image: UIImage, displayPoints: CGFloat = 56) async -> UIImage {
        let scale = await MainActor.run { UIScreen.main.scale }
        let key = cacheKey(productID: productID, image: image, displayPoints: displayPoints, screenScale: scale)
        if let hit = cache.object(forKey: key) { return hit }
        let pixelEdge = displayPoints * max(scale, 2) * 1.2
        let thumb = await Task.detached(priority: .utility) {
            autoreleasepool {
                StylePreviewPipeline.prepareThumbnailBase(from: image, maxLongEdge: pixelEdge) ?? image
            }
        }.value
        let cost = thumb.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
        cache.setObject(thumb, forKey: key, cost: cost)
        return thumb
    }

    static func removeAll() {
        cache.removeAllObjects()
    }
}

/// Async queue-row thumbnail — avoids decoding on the main thread during scroll.
struct AsyncQueueRowThumbnail: View {
    let productID: UUID
    let image: UIImage
    var side: CGFloat = 56

    @State private var thumb: UIImage?

    var body: some View {
        Group {
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                DS.ColorToken.backgroundTertiary
                    .overlay { ProgressView().controlSize(.mini) }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                .stroke(DS.ColorToken.separator.opacity(0.85), lineWidth: 1)
        )
        .task(id: productID) {
            let source: UIImage
            if image === CapturedProduct.diskBackedOriginalPlaceholder {
                source = await Task.detached(priority: .utility) {
                    autoreleasepool { SessionDiskStore.loadProcessedImage(id: productID) } ?? image
                }.value
            } else {
                source = image
            }
            if let cached = QueueRowThumbnailCache.cached(for: productID, image: source, displayPoints: side) {
                thumb = cached
                return
            }
            thumb = await QueueRowThumbnailCache.thumbnailAsync(for: productID, image: source, displayPoints: side)
        }
    }
}
