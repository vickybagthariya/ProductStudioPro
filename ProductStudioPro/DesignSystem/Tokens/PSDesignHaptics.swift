import SwiftUI

/// Centralized haptic feedback for the design system.
///
/// Wraps `InteractionHaptics` and respects the user's Vibrate setting.
enum PSDesignHaptics {
    static var isEnabled: Bool { InteractionHaptics.vibrateEnabledFromSettings }

    /// Light tap — buttons, toggles, icon presses.
    static func tap() {
        InteractionHaptics.tap(vibrate: isEnabled)
    }

    /// Picker / chip / segment selection change.
    static func selection() {
        InteractionHaptics.selection(vibrate: isEnabled)
    }

    /// Completed action — export finished, save succeeded.
    static func success() {
        InteractionHaptics.success(vibrate: isEnabled)
    }

    /// Attention needed — soft cap warning, validation hint.
    static func warning() {
        InteractionHaptics.warning(vibrate: isEnabled)
    }

    /// Failure — export error, destructive action blocked.
    static func error() {
        InteractionHaptics.error(vibrate: isEnabled)
    }
}
