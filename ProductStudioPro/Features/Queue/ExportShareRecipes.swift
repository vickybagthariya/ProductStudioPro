import SwiftUI
import UIKit

/// One-tap share recipes — export-time geometry/format without mutating session Settings.
enum ExportShareRecipe: String, CaseIterable, Identifiable {
    case amazonReady
    case transparentPNG
    case shopify2048

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amazonReady: return "Amazon ready"
        case .transparentPNG: return "Transparent PNG cutout"
        case .shopify2048: return "Shopify 2048"
        }
    }

    var subtitle: String {
        switch self {
        case .amazonReady: return "2000×2000 JPG · marketplace white"
        case .transparentPNG: return "PNG with alpha when BG removed"
        case .shopify2048: return "2048×2048 JPG · product square"
        }
    }

    var systemImage: String {
        switch self {
        case .amazonReady: return "cart.fill"
        case .transparentPNG: return "circle.dashed"
        case .shopify2048: return "bag.fill"
        }
    }

    var canvasWidth: Int {
        switch self {
        case .amazonReady: return 2000
        case .transparentPNG: return 0 // keep product size
        case .shopify2048: return 2048
        }
    }

    var canvasHeight: Int {
        switch self {
        case .amazonReady: return 2000
        case .transparentPNG: return 0
        case .shopify2048: return 2048
        }
    }

    var format: ExportImageFormat {
        switch self {
        case .amazonReady, .shopify2048: return .jpg
        case .transparentPNG: return .png
        }
    }
}

enum ExportShareRecipeRunner {
    /// Builds share file URLs for a recipe without changing session canvas settings.
    static func exportURLs(
        products: [CapturedProduct],
        recipe: ExportShareRecipe,
        namingMode: ImageNamingMode,
        jpgQuality: Double
    ) -> [URL] {
        switch recipe {
        case .transparentPNG:
            return products.compactMap { product in
                let image = ExportManager.transparentCutoutImage(for: product) ?? product.image
                let name = product.filename(for: namingMode, format: .png)
                return ExportManager.pngURL(for: image, filename: name)
            }
        case .amazonReady, .shopify2048:
            let w = recipe.canvasWidth
            let h = recipe.canvasHeight
            return products.compactMap { product in
                let resized = resizeForRecipe(product.image, width: w, height: h)
                let name = product.filename(for: namingMode, format: .jpg)
                return ExportManager.jpegURL(for: resized, filename: name, quality: max(0.92, jpgQuality))
            }
        }
    }

    private static func resizeForRecipe(_ image: UIImage, width: Int, height: Int) -> UIImage {
        let target = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
            let imgSize = image.size
            guard imgSize.width > 1, imgSize.height > 1 else { return }
            let scale = min(target.width / imgSize.width, target.height / imgSize.height)
            let draw = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let origin = CGPoint(
                x: (target.width - draw.width) / 2,
                y: (target.height - draw.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: draw))
        }
    }
}
