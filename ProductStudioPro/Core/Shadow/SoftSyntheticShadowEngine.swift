import CoreImage
import UIKit

/// On-device Core Image contact shadow derived from the cutout alpha silhouette.
enum SoftSyntheticShadowEngine {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    struct PerspectiveMetrics: Equatable {
        let verticalSquash: CGFloat
        let downwardShift: CGFloat
        let widthScale: CGFloat
    }

    /// Automatic floor-contact perspective from the product footprint on canvas.
    static func perspectiveMetrics(for productRect: CGRect) -> PerspectiveMetrics {
        let aspect = productRect.width / max(productRect.height, 1)
        let verticalSquash = max(0.085, min(0.145, 0.105 + (aspect - 0.75) * 0.025))
        let downwardShift = max(2, productRect.height * 0.018)
        let widthScale = max(0.88, min(1.02, 0.94 + (aspect - 1.0) * 0.04))
        return PerspectiveMetrics(
            verticalSquash: verticalSquash,
            downwardShift: downwardShift,
            widthScale: widthScale
        )
    }

    static func draw(
        in context: CGContext,
        cutout: UIImage,
        productRect: CGRect,
        canvasSize: CGSize,
        rotationDegrees: Double,
        flipHorizontal: Bool,
        flipVertical: Bool,
        settings: SoftSyntheticShadowSettings
    ) {
        let tuned = settings.clamped()
        guard tuned.isEnabled, tuned.opacity > 0.008 else { return }
        guard let layer = renderLayer(
            cutout: cutout,
            productRect: productRect,
            canvasSize: canvasSize,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            settings: tuned
        ) else { return }

        context.saveGState()
        context.setBlendMode(.multiply)
        layer.draw(in: CGRect(origin: .zero, size: canvasSize))
        context.restoreGState()
    }

    private static func renderLayer(
        cutout: UIImage,
        productRect: CGRect,
        canvasSize: CGSize,
        rotationDegrees: Double,
        flipHorizontal: Bool,
        flipVertical: Bool,
        settings: SoftSyntheticShadowSettings
    ) -> UIImage? {
        guard productRect.width > 1, productRect.height > 1 else { return nil }
        guard let ciCutout = CIImage(image: cutout) else { return nil }

        let maxWorkEdge: CGFloat = 480
        let canvasScale = min(1, maxWorkEdge / max(canvasSize.width, canvasSize.height, 1))
        let workCanvas = CGSize(
            width: max(1, canvasSize.width * canvasScale),
            height: max(1, canvasSize.height * canvasScale)
        )
        let workProductRect = CGRect(
            x: productRect.origin.x * canvasScale,
            y: productRect.origin.y * canvasScale,
            width: productRect.width * canvasScale,
            height: productRect.height * canvasScale
        )

        let metrics = perspectiveMetrics(for: workProductRect)
        let extent = ciCutout.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let scaleX = workProductRect.width / extent.width
        let scaleY = workProductRect.height / extent.height
        let radians = CGFloat(rotationDegrees * .pi / 180)
        let flipX: CGFloat = flipHorizontal ? -1 : 1
        let flipY: CGFloat = flipVertical ? -1 : 1

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: workProductRect.midX, y: workProductRect.maxY + metrics.downwardShift)
        transform = transform.rotated(by: radians)
        transform = transform.scaledBy(x: flipX, y: flipY)
        transform = transform.scaledBy(x: scaleX * metrics.widthScale, y: scaleY * metrics.verticalSquash)
        transform = transform.translatedBy(x: -extent.midX, y: -extent.maxY)

        var silhouette = ciCutout.transformed(by: transform)
        silhouette = blackSilhouette(from: silhouette, opacity: CGFloat(settings.opacity))

        let blurRadius = Float(settings.blur * Double(canvasScale))
        if blurRadius > 0.35 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = silhouette
            blur.radius = blurRadius
            silhouette = blur.outputImage ?? silhouette
        }

        let cropRect = CGRect(origin: .zero, size: workCanvas)
        silhouette = silhouette.cropped(to: cropRect)

        guard let cg = ciContext.createCGImage(silhouette, from: cropRect) else { return nil }
        let workImage = UIImage(cgImage: cg, scale: 1, orientation: .up)

        guard canvasScale < 0.999 else { return workImage }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            workImage.draw(in: CGRect(origin: .zero, size: canvasSize))
        }
    }

    private static func blackSilhouette(from image: CIImage, opacity: CGFloat) -> CIImage {
        let extent = image.extent
        let clear = CIImage(color: .clear).cropped(to: extent)
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: opacity)).cropped(to: extent)
        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = black
        blend.backgroundImage = clear
        blend.maskImage = image
        return blend.outputImage?.cropped(to: extent) ?? image
    }
}
