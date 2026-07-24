import UIKit

/// Memory-conscious cutout extraction for grouped-cover preview and export.
enum CompositeBundleCutoutLoader {
    /// Vision input cap for editor preload (avoids full-resolution masks in memory).
    private static let previewSourceMaxLongEdge: CGFloat = 2048
    /// Vision input cap for final export — aligned with unified processing limits.
    private static let exportSourceMaxLongEdge: CGFloat = CaptureQualityLimits.unifiedProcessingMaxLongEdge

    static func previewMaxLongEdge(canvasWidth: Int, canvasHeight: Int) -> CGFloat {
        let canvasLong = CGFloat(max(canvasWidth, canvasHeight))
        return min(1536, max(768, canvasLong * 0.85))
    }

    static func previewCutout(
        for product: CapturedProduct,
        canvasWidth: Int,
        canvasHeight: Int
    ) -> (image: UIImage, pixelSize: CGSize)? {
        autoreleasepool {
            let previewCap = previewMaxLongEdge(canvasWidth: canvasWidth, canvasHeight: canvasHeight)
            guard let cutout = extractCutout(
                from: product,
                sourceMaxLongEdge: previewSourceMaxLongEdge,
                outputMaxLongEdge: previewCap
            ) else { return nil }
            return (cutout, cutout.size)
        }
    }

    static func exportCutout(
        for product: CapturedProduct,
        drawSize: CGSize
    ) -> UIImage? {
        autoreleasepool {
            let drawLong = max(drawSize.width, drawSize.height)
            let outputCap = min(exportSourceMaxLongEdge, max(384, drawLong * 2.5))
            let sourceCap = min(exportSourceMaxLongEdge, max(outputCap * 1.5, 768))
            return extractCutout(
                from: product,
                sourceMaxLongEdge: sourceCap,
                outputMaxLongEdge: outputCap
            )
        }
    }

    private static func extractCutout(
        from product: CapturedProduct,
        sourceMaxLongEdge: CGFloat,
        outputMaxLongEdge: CGFloat
    ) -> UIImage? {
        guard let original = QueueImageResolver.uncompressedOriginal(for: product) else { return nil }
        let source = ImageProcessor.downsampleIfNeededForImportPipeline(
            original,
            maxLongEdgePixels: sourceMaxLongEdge
        )
        let cutout: UIImage
        if let lifted = ImageProcessor.cachedForegroundCutout(
            for: product,
            from: source,
            mode: product.enhancementMode,
            strength: product.studioAIStrength
        ) {
            cutout = lifted
        } else if let lifted = ImageProcessor.extractForegroundCutout(
            from: source,
            mode: product.enhancementMode,
            strength: product.studioAIStrength
        ) {
            cutout = ImageProcessor.cropTransparentMargins(lifted) ?? lifted
        } else {
            cutout = ImageProcessor.downsampleIfNeededForImportPipeline(
                product.image,
                maxLongEdgePixels: sourceMaxLongEdge
            )
        }
        return ImageProcessor.downsampleIfNeededForImportPipeline(
            cutout,
            maxLongEdgePixels: outputMaxLongEdge
        )
    }
}
