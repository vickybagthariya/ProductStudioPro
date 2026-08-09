import CoreGraphics

/// Allowed corner radii — only 12, 18, and 24 to maintain visual consistency.
enum PSDesignRadius {
    /// Compact controls, chips, thumbnails.
    static let sm: CGFloat = 12

    /// Cards, buttons, list rows.
    static let md: CGFloat = 18

    /// Feature panels, hero cards, sheets.
    static let lg: CGFloat = 24
}
