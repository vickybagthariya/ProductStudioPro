import UIKit

enum ContactShadowRenderer {
    struct ShadowParams {
        let opacity: CGFloat
        let blur: CGFloat
        let offsetY: CGFloat
        let widthScale: CGFloat
        let heightScale: CGFloat
    }

    static func params(for strength: ContactShadowStrength) -> ShadowParams? {
        switch strength {
        case .off:
            return nil
        case .soft:
            return ShadowParams(opacity: 0.18, blur: 12, offsetY: 4, widthScale: 0.72, heightScale: 0.10)
        case .medium:
            return ShadowParams(opacity: 0.28, blur: 18, offsetY: 6, widthScale: 0.78, heightScale: 0.12)
        case .strong:
            return ShadowParams(opacity: 0.42, blur: 26, offsetY: 10, widthScale: 0.86, heightScale: 0.15)
        }
    }

    static func draw(below productRect: CGRect, strength: ContactShadowStrength, in context: CGContext) {
        guard let params = params(for: strength) else { return }

        let shadowWidth = productRect.width * params.widthScale
        let shadowHeight = max(6, productRect.height * params.heightScale)
        let shadowRect = CGRect(
            x: productRect.midX - shadowWidth / 2,
            y: productRect.maxY - shadowHeight * 0.35 + params.offsetY,
            width: shadowWidth,
            height: shadowHeight
        )

        context.saveGState()
        context.setShadow(offset: .zero, blur: params.blur, color: UIColor.black.withAlphaComponent(params.opacity).cgColor)
        context.setFillColor(UIColor.black.withAlphaComponent(params.opacity).cgColor)
        context.fillEllipse(in: shadowRect)
        context.restoreGState()
    }
}
