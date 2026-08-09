import SwiftUI

/// Centralized spring animations and standard transitions.
enum PSDesignMotion {
    // MARK: - Spring presets

    /// Snappy press feedback — buttons, chips, icon taps.
    static let springSnappy = Animation.spring(response: 0.22, dampingFraction: 0.62)

    /// Soft settle — cards, sheets, content reveals.
    static let springSoft = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// Bouncy emphasis — success states, onboarding highlights.
    static let springBouncy = Animation.spring(response: 0.40, dampingFraction: 0.72)

    // MARK: - Press scale

    static let pressScale: CGFloat = DS.Motion.pressScale
    static let pressScaleCompact: CGFloat = DS.Motion.pressScaleCompact
    static let pressScaleIcon: CGFloat = DS.Motion.pressScaleIcon

    // MARK: - Disabled appearance

    static let disabledOpacity: Double = DS.Motion.disabledOpacity
    static let disabledSaturation: Double = DS.Motion.disabledSaturation

    // MARK: - Standard transitions

    static let fade = AnyTransition.opacity
    static let scaleFade = AnyTransition.opacity.combined(with: .scale(scale: 0.96))
    static let slideUp = AnyTransition.move(edge: .bottom).combined(with: .opacity)
    static let slideDown = AnyTransition.move(edge: .top).combined(with: .opacity)
}

extension View {
    func psSpringSnappy<V: Equatable>(value: V) -> some View {
        animation(PSDesignMotion.springSnappy, value: value)
    }

    func psSpringSoft<V: Equatable>(value: V) -> some View {
        animation(PSDesignMotion.springSoft, value: value)
    }
}
