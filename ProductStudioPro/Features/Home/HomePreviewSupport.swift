import SwiftUI
import UIKit

#if DEBUG
@MainActor
enum HomePreviewSupport {
    static func makeSession(productCount: Int) -> CaptureSessionStore {
        let session = CaptureSessionStore()
        guard productCount > 0 else { return session }

        let image = makePreviewImage()
        session.beginSessionPersistenceBatch()
        var products: [CapturedProduct] = []
        for index in 0..<productCount {
            let upc: String
            if index == 0 {
                upc = "Organic Cold-Pressed Extra Virgin Olive Oil With A Very Long Product Name"
            } else {
                upc = "SKU-\(1000 + index)"
            }
            let angle: ProductAngle = index == 1 ? .front : .none
            let product = CapturedProduct(
                sequence: index + 1,
                upc: upc,
                angle: angle,
                image: image,
                originalImage: image,
                capturedAt: Date().addingTimeInterval(Double(-index) * 3600),
                backgroundRemoved: index % 2 == 0
            )
            products.append(product)
        }
        session.products = products
        session.endSessionPersistenceBatch()
        return session
    }

    private static func makePreviewImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { ctx in
            UIColor(white: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor(white: 0.25, alpha: 1).setFill()
            ctx.fill(CGRect(x: 100, y: 100, width: 200, height: 200))
        }
    }
}
#endif
