import CoreGraphics

/// 8-point grid spacing constants for consistent layout rhythm.
enum PSDesignSpacing {
    /// 4pt — tight inline gaps, icon-to-label padding.
    static let xs: CGFloat = 4

    /// 8pt — compact stacks, chip padding.
    static let sm: CGFloat = 8

    /// 16pt — standard section padding, card insets.
    static let md: CGFloat = 16

    /// 24pt — section separation, screen margins on tablets.
    static let lg: CGFloat = 24

    /// 32pt — major section breaks.
    static let xl: CGFloat = 32

    /// 48pt — hero spacing, empty-state breathing room.
    static let xxl: CGFloat = 48

    // MARK: - Screen layout helpers

    /// Default horizontal screen inset (18pt — legacy compat until screens migrate).
    static let screenHorizontal: CGFloat = DS.Space.screenHorizontal

    /// Default vertical screen inset.
    static let screenVertical: CGFloat = DS.Space.screenVertical
}
