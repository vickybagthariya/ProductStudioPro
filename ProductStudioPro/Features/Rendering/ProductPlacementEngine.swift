import CoreGraphics
import UIKit

enum ProductPlacementEngine {
    /// Computes the product draw rect for image backgrounds.
    static func computeDrawRect(
        cutoutSize: CGSize,
        canvasSize: CGSize,
        fillRatio: Double,
        background: ImageBackgroundDefinition,
        placement: ProductPlacementSpec
    ) -> CGRect {
        let safeFill = CGFloat(max(0.30, min(fillRatio, 1.0)))
        let scaleMultiplier = CGFloat(max(0.25, min(placement.scaleMultiplier, 2.5)))
        let lw = max(cutoutSize.width, 1)
        let lh = max(cutoutSize.height, 1)

        let baseScale = CGFloat(background.defaultScale) * safeFill * scaleMultiplier
        let fitW = canvasSize.width * baseScale
        let fitH = canvasSize.height * baseScale
        let productScale = min(fitW / lw, fitH / lh)
        let drawSize = CGSize(width: lw * productScale, height: lh * productScale)

        let offsetX = CGFloat(placement.offsetXNormalized) * canvasSize.width * 0.15
        let offsetY = CGFloat(placement.offsetYNormalized) * canvasSize.height * 0.10

        if background.isStaging, let surfaceLineY = background.surfaceLineY {
            let surfaceY = canvasSize.height * CGFloat(surfaceLineY)
            let centerX = canvasSize.width * CGFloat(background.defaultX) + offsetX
            let originX = centerX - drawSize.width / 2
            let originY = surfaceY - drawSize.height + offsetY
            return CGRect(x: originX, y: originY, width: drawSize.width, height: drawSize.height)
        }

        // Non-staging: center with comfortable bottom padding (~8%).
        let bottomPadding = canvasSize.height * 0.08
        let centerX = canvasSize.width * CGFloat(background.defaultX) + offsetX
        let centerY = canvasSize.height * CGFloat(background.defaultY) + offsetY
        var originX = centerX - drawSize.width / 2
        var originY = centerY - drawSize.height / 2

        // Nudge upward so product sits above bottom padding.
        let maxBottom = canvasSize.height - bottomPadding
        if originY + drawSize.height > maxBottom {
            originY = maxBottom - drawSize.height
        }

        originX = max(0, min(originX, canvasSize.width - drawSize.width))
        originY = max(0, min(originY, canvasSize.height - drawSize.height))

        return CGRect(x: originX, y: originY, width: drawSize.width, height: drawSize.height)
    }

    static func defaultPlacement(for background: ImageBackgroundDefinition) -> ProductPlacementSpec {
        .default
    }
}
