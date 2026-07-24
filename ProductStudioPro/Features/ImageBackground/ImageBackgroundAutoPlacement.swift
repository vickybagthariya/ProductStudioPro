import CoreGraphics
import UIKit

/// Suggests product/background transforms when a background is selected.
enum ImageBackgroundAutoPlacement {
    /// Cutout fill used when applying Online (Pexels/Pixabay) backgrounds.
    static let onlineBackgroundFillRatio: Double = 0.95

    static func applyAutoPlacement(
        to selection: inout ImageBackgroundSelection,
        definition: ImageBackgroundDefinition,
        cutoutSize: CGSize,
        canvasSize: CGSize,
        fillRatio: Double
    ) {
        let productRect = ProductPlacementEngine.computeDrawRect(
            cutoutSize: cutoutSize,
            canvasSize: canvasSize,
            fillRatio: fillRatio,
            background: definition,
            placement: .default
        )

        selection.placement = .default
        selection.productTransform = transform(from: productRect, canvasSize: canvasSize, aspect: cutoutSize)
        let bgImage = ImageBackgroundAssetLoader.fullImage(for: definition, customRef: selection.customImageRef)
        selection.backgroundTransform = ImageBackgroundRenderer.aspectFillTransform(imageSize: bgImage.size, canvasSize: canvasSize)
        selection.backgroundCrop = .full
    }

    static func transform(from drawRect: CGRect, canvasSize: CGSize, aspect: CGSize) -> CompositeLayerTransform {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CompositeLayerTransform(centerX: 0.5, centerY: 0.5, scale: 0.5, rotationRadians: 0)
        }
        return CompositeLayerTransform(
            centerX: Double(drawRect.midX / canvasSize.width),
            centerY: Double(drawRect.midY / canvasSize.height),
            scale: Double(drawRect.width / canvasSize.width),
            rotationRadians: 0
        )
    }

    static func drawRect(
        for transform: CompositeLayerTransform,
        cutoutSize: CGSize,
        canvasSize: CGSize
    ) -> CGRect {
        let center = CGPoint(
            x: CGFloat(transform.centerX) * canvasSize.width,
            y: CGFloat(transform.centerY) * canvasSize.height
        )
        let width = CGFloat(transform.scale) * canvasSize.width
        let aspect = cutoutSize.width / max(cutoutSize.height, 1)
        let height = width / max(aspect, 0.01)
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }
}
