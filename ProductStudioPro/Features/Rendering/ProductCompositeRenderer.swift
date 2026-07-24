import CoreImage
import UIKit

enum ImageBackgroundRenderer {
    static func draw(in rect: CGRect, context: CGContext, selection: ImageBackgroundSelection, maxBackgroundLongEdge: CGFloat? = nil) {
        let definition = resolvedDefinition(for: selection)
        let source = ImageBackgroundAssetLoader.imageForComposition(
            definition: definition,
            customRef: selection.customImageRef,
            canvasSize: rect.size,
            maxLongEdge: maxBackgroundLongEdge
        )
        let cropped = croppedImage(source, crop: selection.backgroundCrop ?? .full) ?? source
        let image = selection.backgroundBlur > 0.5
            ? (blurredImage(cropped, radius: CGFloat(selection.backgroundBlur)) ?? cropped)
            : cropped

        if let transform = selection.backgroundTransform {
            drawImage(image, transform: transform, in: rect, context: context)
        } else {
            let drawRect = aspectFillRect(imageSize: image.size, canvasRect: rect)
            context.saveGState()
            context.interpolationQuality = .high
            image.draw(in: drawRect)
            context.restoreGState()
        }
    }

    static func resolvedDefinition(for selection: ImageBackgroundSelection) -> ImageBackgroundDefinition {
        if selection.backgroundID.hasPrefix("custom."),
           let recordID = selection.customImageRef ?? selection.backgroundID.split(separator: ".").last.map(String.init),
           let record = ImageBackgroundStore.shared.record(id: recordID) {
            return ImageBackgroundStore.shared.definition(for: record)
        }
        if let customRef = selection.customImageRef,
           let record = ImageBackgroundStore.shared.record(id: customRef) {
            return ImageBackgroundStore.shared.definition(for: record)
        }
        return ImageBackgroundFolderCatalog.definition(id: selection.backgroundID)
            ?? placeholderDefinition(for: selection.backgroundID)
    }

    static func aspectFillTransform(imageSize: CGSize, canvasSize: CGSize) -> CompositeLayerTransform {
        let scale = max(canvasSize.width / max(imageSize.width, 1), canvasSize.height / max(imageSize.height, 1))
        let drawW = imageSize.width * scale
        return CompositeLayerTransform(centerX: 0.5, centerY: 0.5, scale: Double(drawW / max(canvasSize.width, 1)), rotationRadians: 0)
    }

    static func croppedBackgroundImage(_ source: UIImage, crop: ImageBackgroundCropSpec?) -> UIImage {
        croppedImage(source, crop: crop ?? .full) ?? source
    }

    private static func placeholderDefinition(for id: String) -> ImageBackgroundDefinition {
        let slug = id.split(separator: "/").first.map(String.init) ?? ImageBackgroundFolderCatalog.defaultCategorySlug
        return ImageBackgroundDefinition(
            id: id,
            title: "Background",
            categorySlug: slug,
            resourcePath: nil,
            isStaging: false,
            surfaceLineY: nil,
            defaultScale: 0.88,
            defaultX: 0.5,
            defaultY: 0.52
        )
    }

    private static func aspectFillRect(imageSize: CGSize, canvasRect: CGRect) -> CGRect {
        let scale = max(canvasRect.width / max(imageSize.width, 1), canvasRect.height / max(imageSize.height, 1))
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: canvasRect.midX - drawSize.width / 2,
            y: canvasRect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    private static func drawImage(_ image: UIImage, transform: CompositeLayerTransform, in canvasRect: CGRect, context: CGContext) {
        let pixelRect = CompositeLayoutEngine.absoluteDrawRect(
            transform: transform,
            cutoutSize: image.size,
            canvasSize: canvasRect.size
        )
        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: pixelRect.midX, y: pixelRect.midY)
        context.rotate(by: CGFloat(transform.rotationRadians))
        context.translateBy(x: -pixelRect.width / 2, y: -pixelRect.height / 2)
        image.draw(in: CGRect(origin: .zero, size: pixelRect.size))
        context.restoreGState()
    }

    private static func croppedImage(_ image: UIImage, crop: ImageBackgroundCropSpec) -> UIImage? {
        let c = crop.clamped()
        if c.x == 0, c.y == 0, c.width == 1, c.height == 1 { return image }
        guard let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let rect = CGRect(x: c.x * w, y: c.y * h, width: c.width * w, height: c.height * h).integral
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func blurredImage(_ image: UIImage, radius: CGFloat) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: nil)
        let extent = ci.extent
        guard let cg = context.createCGImage(output.cropped(to: extent), from: extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}

enum ProductCompositeRenderer {
    static func composite(
        cutout: UIImage,
        canvasWidth: Int,
        canvasHeight: Int,
        fillRatio: Double,
        backgroundColor: UIColor,
        secondaryBackgroundColor: UIColor,
        backgroundStyle: BackgroundCanvasStyle,
        gradientColorHexes: [String],
        backgroundFillSpec: BackgroundFillSpec?,
        subjectRotationDegrees: Double,
        flipHorizontal: Bool,
        flipVertical: Bool,
        maxBackgroundLongEdge: CGFloat? = nil
    ) -> UIImage {
        // Always despill soft-matte fringe once so Format/reset/Apply never paint white edge stains.
        let cleanedCutout = ImageProcessor.scrubCutoutMatteFringe(cutout)
        let canvas = CGSize(width: canvasWidth, height: canvasHeight)
        let fillSpec = backgroundFillSpec ?? BackgroundFillSpec.fromLegacy(style: backgroundStyle, hexes: gradientColorHexes)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { rendererContext in
            let ctx = rendererContext.cgContext
            ctx.interpolationQuality = .high
            ctx.setShouldAntialias(true)
            ctx.setAllowsAntialiasing(true)
            let canvasRect = CGRect(origin: .zero, size: canvas)

            if fillSpec.fillKind == .image, let selection = fillSpec.imageSelection {
                ImageBackgroundRenderer.draw(
                    in: canvasRect,
                    context: ctx,
                    selection: selection,
                    maxBackgroundLongEdge: maxBackgroundLongEdge
                )
                let definition = ImageBackgroundRenderer.resolvedDefinition(for: selection)
                let productRect = productDrawRect(
                    cutoutSize: cleanedCutout.size,
                    canvasSize: canvas,
                    fillRatio: fillRatio,
                    background: definition,
                    selection: selection
                )
                if selection.reflectionOpacity > 0.01 {
                    drawReflection(
                        cleanedCutout,
                        below: productRect,
                        opacity: selection.reflectionOpacity,
                        rotationDegrees: subjectRotationDegrees,
                        flipH: flipHorizontal,
                        flipV: flipVertical,
                        context: ctx
                    )
                }
                ContactShadowRenderer.draw(below: productRect, strength: selection.shadow, in: ctx)
                drawProduct(cleanedCutout, in: productRect, rotationDegrees: subjectRotationDegrees, flipH: flipHorizontal, flipV: flipVertical, context: ctx)
            } else {
                BackgroundFillRenderer.draw(in: canvasRect, context: ctx, primary: backgroundColor, secondary: secondaryBackgroundColor, spec: fillSpec)
                let fitW = CGFloat(canvasWidth) * CGFloat(max(0.30, min(fillRatio, 1.0)))
                let fitH = CGFloat(canvasHeight) * CGFloat(max(0.30, min(fillRatio, 1.0)))
                let lw = max(cleanedCutout.size.width, 1)
                let lh = max(cleanedCutout.size.height, 1)
                let scale = min(fitW / lw, fitH / lh)
                let drawSize = CGSize(width: lw * scale, height: lh * scale)
                let rect = CGRect(
                    x: (canvas.width - drawSize.width) / 2,
                    y: (canvas.height - drawSize.height) / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
                if BackgroundFillRenderer.needsShelfPlinth(fillSpec) {
                    ImageProcessor.drawShelfPlinthPublic(in: canvasRect, productRect: rect, context: ctx, primary: backgroundColor, secondary: secondaryBackgroundColor)
                }
                drawProduct(cleanedCutout, in: rect, rotationDegrees: subjectRotationDegrees, flipH: flipHorizontal, flipV: flipVertical, context: ctx)
            }
        }
    }

    static func productDrawRect(
        cutoutSize: CGSize,
        canvasSize: CGSize,
        fillRatio: Double,
        background: ImageBackgroundDefinition,
        selection: ImageBackgroundSelection
    ) -> CGRect {
        if let transform = selection.productTransform {
            return CompositeLayoutEngine.absoluteDrawRect(
                transform: transform,
                cutoutSize: cutoutSize,
                canvasSize: canvasSize
            )
        }
        return ProductPlacementEngine.computeDrawRect(
            cutoutSize: cutoutSize,
            canvasSize: canvasSize,
            fillRatio: fillRatio,
            background: background,
            placement: selection.placement
        )
    }

    private static func drawReflection(
        _ image: UIImage,
        below productRect: CGRect,
        opacity: Double,
        rotationDegrees: Double,
        flipH: Bool,
        flipV: Bool,
        context: CGContext
    ) {
        let reflectionHeight = productRect.height * 0.42
        guard reflectionHeight > 2 else { return }
        let reflectionRect = CGRect(
            x: productRect.minX,
            y: productRect.maxY,
            width: productRect.width,
            height: reflectionHeight
        )

        context.saveGState()
        context.clip(to: reflectionRect)
        context.translateBy(x: productRect.midX, y: productRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -productRect.width / 2, y: -productRect.height)

        let radians = CGFloat(rotationDegrees * .pi / 180)
        let sx: CGFloat = flipH ? -1 : 1
        let sy: CGFloat = flipV ? -1 : 1
        context.translateBy(x: productRect.width / 2, y: productRect.height / 2)
        context.rotate(by: radians)
        context.scaleBy(x: sx, y: sy)
        context.translateBy(x: -productRect.width / 2, y: -productRect.height / 2)

        context.setAlpha(CGFloat(opacity * 0.55))
        image.draw(in: CGRect(origin: .zero, size: productRect.size))

        context.restoreGState()

        context.saveGState()
        context.clip(to: reflectionRect)
        let colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(CGFloat(min(1, opacity))).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: reflectionRect.midX, y: reflectionRect.minY),
                end: CGPoint(x: reflectionRect.midX, y: reflectionRect.maxY),
                options: []
            )
        }
        context.restoreGState()
    }

    private static func drawProduct(
        _ image: UIImage,
        in rect: CGRect,
        rotationDegrees: Double,
        flipH: Bool,
        flipV: Bool,
        context: CGContext
    ) {
        let radians = CGFloat(rotationDegrees * .pi / 180)
        let sx: CGFloat = flipH ? -1 : 1
        let sy: CGFloat = flipV ? -1 : 1
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: radians)
        context.scaleBy(x: sx, y: sy)
        context.translateBy(x: -rect.width / 2, y: -rect.height / 2)
        image.draw(in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
