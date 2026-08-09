import UIKit

/// Where polish runs in the render graph.
enum AIPolishPass: Equatable {
    /// Before cutout / compositing — exposure recovery and denoise on the source.
    case preComposite
    /// After canvas composite — light finishing pass.
    case postComposite
}

/// Backend selection — UI never branches on this; routing lives in `AIPolishEngine`.
enum AIPolishProvider: Equatable {
    case onDevice
    /// Reserved for a future cloud backend without UI changes.
    case cloud
}

struct AIPolishRequest: Equatable {
    let image: UIImage
    let pass: AIPolishPass
    let provider: AIPolishProvider

    init(image: UIImage, pass: AIPolishPass, provider: AIPolishProvider = .onDevice) {
        self.image = image
        self.pass = pass
        self.provider = provider
    }
}

protocol AIPolishEnhancing {
    func enhance(_ request: AIPolishRequest) -> UIImage
}

/// Adaptive thumbnail analysis that drives conservative, natural polish strength.
struct AIPolishImageProfile: Equatable {
    let averageBrightness: Double
    let contrast: Double
    let blurScore: Double
    let shadowDepth: Double
    let saturation: Double

    var isDark: Bool { averageBrightness < 0.42 }
    var isVeryDark: Bool { averageBrightness < 0.30 }
    var isFlat: Bool { contrast < 0.18 }
    var isAlreadySharp: Bool { blurScore > 0.72 }
    var isSoft: Bool { blurScore < 0.48 }
    var isLowColor: Bool { saturation < 0.16 }
}
