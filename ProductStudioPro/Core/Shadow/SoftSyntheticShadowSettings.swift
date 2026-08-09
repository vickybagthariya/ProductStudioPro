import Foundation

/// Adjustable studio contact shadow applied after background removal.
struct SoftSyntheticShadowSettings: Equatable, Codable {
    var isEnabled: Bool
    /// Shadow strength 0…1.
    var opacity: Double
    /// Gaussian blur radius in points (Core Image input radius).
    var blur: Double

    static let studioDefault = SoftSyntheticShadowSettings(
        isEnabled: true,
        opacity: 0.22,
        blur: 14
    )

    static let off = SoftSyntheticShadowSettings(
        isEnabled: false,
        opacity: 0.22,
        blur: 14
    )

    func clamped() -> SoftSyntheticShadowSettings {
        SoftSyntheticShadowSettings(
            isEnabled: isEnabled,
            opacity: min(1, max(0, opacity)),
            blur: min(48, max(0, blur))
        )
    }
}
