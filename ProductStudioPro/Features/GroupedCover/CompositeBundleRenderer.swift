import UIKit

enum CompositeBundleRenderError: Error {
    case invalidCanvas
    case backgroundRenderFailed
    case cutoutUnavailable(UUID)
    case compositeFailed
}

enum CompositeBundleRenderer {
    private static let renderQueue = DispatchQueue(label: "com.productstudiopro.compositebundle", qos: .userInitiated)

    static func render(
        layout: CompositeBundleLayout,
        productsByID: [UUID: CapturedProduct],
        canvasWidth: Int,
        canvasHeight: Int,
        fillRatio: Double,
        backgroundFillSpec: BackgroundFillSpec,
        primaryColor: UIColor,
        secondaryColor: UIColor,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        renderQueue.async {
            autoreleasepool {
                do {
                    let image = try renderSync(
                        layout: layout,
                        productsByID: productsByID,
                        canvasWidth: canvasWidth,
                        canvasHeight: canvasHeight,
                        fillRatio: fillRatio,
                        backgroundFillSpec: backgroundFillSpec,
                        primaryColor: primaryColor,
                        secondaryColor: secondaryColor
                    )
                    DispatchQueue.main.async {
                        completion(.success(image))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    private static func renderSync(
        layout: CompositeBundleLayout,
        productsByID: [UUID: CapturedProduct],
        canvasWidth: Int,
        canvasHeight: Int,
        fillRatio: Double,
        backgroundFillSpec: BackgroundFillSpec,
        primaryColor: UIColor,
        secondaryColor: UIColor
    ) throws -> UIImage {
        guard canvasWidth > 0, canvasHeight > 0 else { throw CompositeBundleRenderError.invalidCanvas }

        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let sortedLayers = layout.layers.sorted { $0.zIndex < $1.zIndex }

        return renderer.image { rendererContext in
            let ctx = rendererContext.cgContext
            ctx.interpolationQuality = .high
            ctx.setShouldAntialias(true)

            let canvasRect = CGRect(origin: .zero, size: canvasSize)
            BackgroundFillRenderer.draw(
                in: canvasRect,
                context: ctx,
                primary: primaryColor,
                secondary: secondaryColor,
                spec: backgroundFillSpec
            )

            for layer in sortedLayers {
                autoreleasepool {
                    guard let product = productsByID[layer.sourceProductID] else { return }
                    guard let cutout = CompositeBundleCutoutLoader.exportCutout(
                        for: product,
                        drawSize: estimatedDrawSize(for: layer, canvasSize: canvasSize)
                    ) else { return }

                    let aspectSize = layer.cutoutAspectSize(fallback: cutout.size)
                    let drawRect = CompositeLayoutEngine.absoluteDrawRect(
                        transform: layer.transform,
                        cutoutSize: aspectSize,
                        canvasSize: canvasSize
                    )
                    guard drawRect.width > 1, drawRect.height > 1 else { return }

                    let fitRect = CompositeLayoutEngine.aspectFitDrawRect(
                        imageSize: cutout.size,
                        in: drawRect
                    )

                    ctx.saveGState()
                    ctx.translateBy(x: fitRect.midX, y: fitRect.midY)
                    ctx.rotate(by: CGFloat(layer.transform.rotationRadians))
                    ctx.translateBy(x: -fitRect.width / 2, y: -fitRect.height / 2)
                    cutout.draw(in: CGRect(origin: .zero, size: fitRect.size))
                    ctx.restoreGState()
                }
            }
        }
    }

    private static func estimatedDrawSize(for layer: CompositeLayerItem, canvasSize: CGSize) -> CGSize {
        let aspectSize = layer.cutoutAspectSize(fallback: CGSize(width: 1, height: 1))
        let rect = CompositeLayoutEngine.absoluteDrawRect(
            transform: layer.transform,
            cutoutSize: aspectSize,
            canvasSize: canvasSize
        )
        return rect.size
    }

    #if DEBUG
    /// DEBUG diagnostics: one subject on white via the real `renderSync` + `exportCutout` path.
    static func debugRenderSingleProductOnWhite(
        product: CapturedProduct,
        canvasWidth: Int,
        canvasHeight: Int,
        fillRatio: Double,
        backgroundFillSpec: BackgroundFillSpec = .catalogWhite,
        primaryColor: UIColor = .white,
        secondaryColor: UIColor = UIColor(white: 0.94, alpha: 1)
    ) throws -> (cutout: UIImage, composite: UIImage) {
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
        let fitW = CGFloat(canvasWidth) * CGFloat(max(0.30, min(fillRatio, 1.0)))
        let fitH = CGFloat(canvasHeight) * CGFloat(max(0.30, min(fillRatio, 1.0)))
        let provisionalDraw = CGSize(width: fitW, height: fitH)
        guard let cutout = CompositeBundleCutoutLoader.exportCutout(for: product, drawSize: provisionalDraw) else {
            throw CompositeBundleRenderError.cutoutUnavailable(product.id)
        }
        let targetFrame = CGRect(
            x: (canvasSize.width - fitW) / 2,
            y: (canvasSize.height - fitH) / 2,
            width: fitW,
            height: fitH
        )
        let transform = CompositeLayoutEngine.fitTransform(
            cutoutSize: cutout.size,
            targetFrame: targetFrame,
            canvasSize: canvasSize,
            fillRatio: 1.0
        )
        let aspect = CompositeLayerItem.aspect(from: cutout.size)
        let layer = CompositeLayerItem(
            sourceProductID: product.id,
            gridIndex: 0,
            zIndex: 0,
            transform: transform,
            cutoutAspectWidth: aspect.width,
            cutoutAspectHeight: aspect.height
        )
        let layout = CompositeBundleLayout(
            matrix: CompositeLayoutMatrix(rows: 1, columns: 1),
            layers: [layer],
            isFreeformMode: true,
            sourceProductIDs: [product.id],
            gridGapPoints: 0,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )
        let composite = try renderSync(
            layout: layout,
            productsByID: [product.id: product],
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            fillRatio: fillRatio,
            backgroundFillSpec: backgroundFillSpec,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor
        )
        return (cutout, composite)
    }
    #endif
}
