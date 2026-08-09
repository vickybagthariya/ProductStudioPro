import SwiftUI

/// Semantic color tokens for the Product Studio design system.
///
/// Maps to the existing brand palette (charcoal + mint) while exposing
/// Apple-first semantic names for future screen redesigns.
enum PSDesignColors {
    // MARK: - Brand accents

    /// Primary interactive accent — charcoal in light mode, mint in dark mode.
    static var primaryAccent: Color { AppTheme.brandAccent }

    /// Secondary accent — mint tint for highlights and selection fills.
    static var secondaryAccent: Color {
        AppTheme.mint.opacity(0.72)
    }

    // MARK: - Surfaces

    /// Root screen background.
    static var background: Color { DS.ColorToken.background }

    /// Raised panels, sheets, and grouped sections.
    static var elevatedBackground: Color { DS.ColorToken.backgroundSecondary }

    /// Cards, list rows, and inset containers.
    static var cardBackground: Color { DS.ColorToken.backgroundTertiary }

    /// Hairlines and structural separators.
    static var divider: Color { DS.ColorToken.separator }

    // MARK: - Semantic feedback

    static var success: Color { DS.ColorToken.success }
    static var warning: Color { DS.ColorToken.warning }
    static var error: Color { DS.ColorToken.error }

    // MARK: - Text hierarchy

    static var textPrimary: Color { DS.ColorToken.label }
    static var textSecondary: Color { DS.ColorToken.secondaryLabel }
    static var textTertiary: Color { DS.ColorToken.tertiaryLabel }

    // MARK: - Control helpers

    /// Label on filled primary controls.
    static var onPrimaryAccent: Color { DS.ColorToken.onAccent }

    /// Filled primary button background.
    static var primaryButtonFill: Color { DS.ColorToken.primaryButtonFill }

    /// Modal scrim overlay.
    static var scrim: Color { DS.ColorToken.scrim }
}
