import SwiftUI

/// Reusable elevation shadows for cards and floating controls.
enum PSDesignShadow {
    /// Subtle lift for inline cards and list rows.
    static let small = ShadowSpec(color: DS.ColorToken.elevatedShadow, radius: 4, x: 0, y: 2)

    /// Standard card elevation.
    static let medium = ShadowSpec(color: DS.ColorToken.elevatedShadow, radius: 8, x: 0, y: 3)

    /// Floating toolbars, action sheets, and modals.
    static let floating = ShadowSpec(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)

    struct ShadowSpec {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

extension View {
    func psShadow(_ spec: PSDesignShadow.ShadowSpec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
    }

    func psShadowSmall() -> some View {
        psShadow(PSDesignShadow.small)
    }

    func psShadowMedium() -> some View {
        psShadow(PSDesignShadow.medium)
    }

    func psShadowFloating() -> some View {
        psShadow(PSDesignShadow.floating)
    }
}
