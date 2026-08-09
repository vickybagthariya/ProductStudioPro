import SwiftUI
import UIKit

#if DEBUG
@MainActor
enum CapturePreviewSupport {
    static func makeSession() -> CaptureSessionStore {
        CaptureSessionStore()
    }

    static func makeSessionWithCurrentImage() -> CaptureSessionStore {
        let session = CaptureSessionStore()
        session.currentImage = makePreviewImage()
        return session
    }

    static func makeMultiAngleSession() -> CaptureSessionStore {
        let session = CaptureSessionStore()
        session.multiAngleEnabled = true
        session.enabledAngles = ProductAngle.captureAngles
        let image = makePreviewImage()
        session.currentImage = image
        _ = session.bufferCurrentMultiAngleShot()
        session.currentImage = image
        _ = session.bufferCurrentMultiAngleShot()
        return session
    }

    static func makeAwaitingNameSession() -> CaptureSessionStore {
        let session = CaptureSessionStore()
        session.multiAngleEnabled = true
        session.enabledAngles = ProductAngle.captureAngles
        let image = makePreviewImage()
        for _ in ProductAngle.captureAngles {
            session.currentImage = image
            _ = session.bufferCurrentMultiAngleShot()
        }
        return session
    }

    private static func makePreviewImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 400, height: 500)).image { ctx in
            UIColor(white: 0.15, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 500))
            UIColor(white: 0.85, alpha: 1).setFill()
            ctx.fill(CGRect(x: 80, y: 100, width: 240, height: 300))
        }
    }
}
#endif
