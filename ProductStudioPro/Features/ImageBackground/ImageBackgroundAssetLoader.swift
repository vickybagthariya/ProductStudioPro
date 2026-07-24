import UIKit

/// Loads folder-based bundled backgrounds, custom imports, or procedural fallbacks.
enum ImageBackgroundAssetLoader {
    private static let thumbnailCache = NSCache<NSString, UIImage>()
    private static let fullImageCache = NSCache<NSString, UIImage>()

    static func configureCacheLimits() {
        thumbnailCache.countLimit = 48
        thumbnailCache.totalCostLimit = 12 * 1024 * 1024
        fullImageCache.countLimit = 2
        fullImageCache.totalCostLimit = 36 * 1024 * 1024
    }

    static func clearMemoryCaches() {
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
    }

    /// Caps pixel dimensions before compositing — avoids loading 12MP+ backgrounds into RAM.
    static func downsampleIfNeeded(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage? {
        guard maxLongEdge > 0, let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let longest = max(w, h)
        guard longest > maxLongEdge else { return image }
        let target = CGSize(
            width: max(1, (w * maxLongEdge / longest).rounded()),
            height: max(1, (h * maxLongEdge / longest).rounded())
        )
        return downscale(image, to: target)
    }

    static func imageForComposition(
        definition: ImageBackgroundDefinition,
        customRef: String?,
        canvasSize: CGSize,
        maxLongEdge: CGFloat? = nil
    ) -> UIImage {
        let source = fullImage(for: definition, customRef: customRef)
        let cap = maxLongEdge ?? max(canvasSize.width, canvasSize.height) * 1.35
        return downsampleIfNeeded(source, maxLongEdge: cap) ?? source
    }

    static func fullImage(for definition: ImageBackgroundDefinition, customRef: String? = nil) -> UIImage {
        if let customRef, let custom = ImageBackgroundStore.shared.image(for: customRef) {
            return custom
        }
        if let path = definition.resourcePath, let image = loadBundledFullImage(at: path) {
            return image
        }
        return proceduralImage(for: definition, size: CGSize(width: 1200, height: 1200))
    }

    static func thumbnail(for definition: ImageBackgroundDefinition, customRef: String? = nil, size: CGSize = CGSize(width: 144, height: 80)) -> UIImage {
        let cacheKey = "\(definition.id)-\(customRef ?? "bundled")-\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        let source: UIImage
        if let customRef, let thumb = ImageBackgroundStore.shared.thumbnail(for: customRef) {
            source = thumb
        } else if let path = definition.resourcePath, let bundledThumb = loadBundledSiblingThumbnail(for: path) {
            source = bundledThumb
        } else if let path = definition.resourcePath, let bundled = loadBundledFullImage(at: path) {
            source = bundled
        } else {
            source = proceduralImage(for: definition, size: size)
        }

        let thumb = downscale(source, to: size) ?? source
        thumbnailCache.setObject(thumb, forKey: cacheKey)
        return thumb
    }

    static func thumbnail(forRecord record: StoredBackgroundRecord, size: CGSize = CGSize(width: 144, height: 80)) -> UIImage {
        let def = ImageBackgroundStore.shared.definition(for: record)
        return thumbnail(for: def, customRef: record.id, size: size)
    }

    static func invalidateCache() {
        clearMemoryCaches()
    }

    // MARK: - Bundle loading

    private static func loadBundledFullImage(at resourcePath: String) -> UIImage? {
        let cacheKey = resourcePath as NSString
        if let cached = fullImageCache.object(forKey: cacheKey) {
            return cached
        }
        guard let url = ImageBackgroundFolderCatalog.bundleFileURL(for: resourcePath),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        fullImageCache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Prefers `name_thumb.jpg` beside the full asset so browse never decodes multi‑MB sources.
    private static func loadBundledSiblingThumbnail(for resourcePath: String) -> UIImage? {
        let ns = resourcePath as NSString
        let dir = ns.deletingLastPathComponent
        let base = (ns.lastPathComponent as NSString).deletingPathExtension
        let thumbPath = (dir as NSString).appendingPathComponent("\(base)_thumb.jpg")
        guard let url = ImageBackgroundFolderCatalog.bundleFileURL(for: thumbPath),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return image
    }

    // MARK: - Procedural fallback

    private static func proceduralImage(for definition: ImageBackgroundDefinition, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = categoryColors(for: definition.categorySlug)
            let cg = ctx.cgContext

            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [colors.top.cgColor, colors.bottom.cgColor] as CFArray,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: []
                )
            } else {
                colors.top.setFill()
                cg.fill(rect)
            }

            if definition.isStaging, let surfaceY = definition.surfaceLineY {
                let lineY = rect.height * CGFloat(surfaceY)
                cg.setStrokeColor(UIColor(white: 0, alpha: 0.12).cgColor)
                cg.setLineWidth(max(1, rect.height * 0.004))
                cg.move(to: CGPoint(x: rect.minX, y: lineY))
                cg.addLine(to: CGPoint(x: rect.maxX, y: lineY))
                cg.strokePath()

                let surfaceRect = CGRect(x: rect.minX, y: lineY, width: rect.width, height: rect.maxY - lineY)
                cg.setFillColor(UIColor(white: 1, alpha: 0.08).cgColor)
                cg.fill(surfaceRect)
            }

            // Missing asset indicator
            let label = definition.title as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(10, size.width * 0.04), weight: .semibold),
                .foregroundColor: UIColor(white: 0.35, alpha: 0.7)
            ]
            let textSize = label.size(withAttributes: attrs)
            label.draw(
                at: CGPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2),
                withAttributes: attrs
            )
        }
    }

    private struct CategoryColors {
        let top: UIColor
        let bottom: UIColor
    }

    private static func categoryColors(for slug: String) -> CategoryColors {
        let hash = abs(slug.hashValue)
        let hue = CGFloat(hash % 360) / 360.0
        let top = UIColor(hue: hue, saturation: 0.12, brightness: 0.94, alpha: 1)
        let bottom = UIColor(hue: hue, saturation: 0.18, brightness: 0.82, alpha: 1)
        if slug == ImageBackgroundCategory.importedCustom.slug {
            return CategoryColors(top: UIColor(white: 0.90, alpha: 1), bottom: UIColor(white: 0.80, alpha: 1))
        }
        return CategoryColors(top: top, bottom: bottom)
    }

    private static func downscale(_ image: UIImage, to target: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: aspectFillRect(imageSize: image.size, canvasSize: target))
        }
    }

    private static func aspectFillRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
        let scale = max(canvasSize.width / max(imageSize.width, 1), canvasSize.height / max(imageSize.height, 1))
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (canvasSize.width - drawSize.width) / 2,
            y: (canvasSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }
}
