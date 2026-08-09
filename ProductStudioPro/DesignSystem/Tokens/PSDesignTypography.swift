import SwiftUI

/// Dynamic Type–aware typography modifiers for the Product Studio design system.
///
/// All styles scale with the user's accessibility text size settings.
enum PSDesignTypography {
    // MARK: - Font styles (Dynamic Type)

    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.semibold)
    static let headline = Font.headline
    static let bodyFont = Font.body
    static let callout = Font.callout
    static let caption = Font.caption.weight(.medium)
    static let footnote = Font.footnote

    // MARK: - View modifiers

    struct LargeTitleModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(largeTitle)
                .foregroundStyle(PSDesignColors.textPrimary)
        }
    }

    struct TitleModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(title)
                .foregroundStyle(PSDesignColors.textPrimary)
        }
    }

    struct HeadlineModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(headline)
                .foregroundStyle(PSDesignColors.textPrimary)
        }
    }

    struct BodyModifier: ViewModifier {
        var color: Color = PSDesignColors.textPrimary

        func body(content: Content) -> some View {
            content
                .font(PSDesignTypography.bodyFont)
                .foregroundStyle(color)
        }
    }

    struct CalloutModifier: ViewModifier {
        var color: Color = PSDesignColors.textSecondary

        func body(content: Content) -> some View {
            content
                .font(callout)
                .foregroundStyle(color)
        }
    }

    struct CaptionModifier: ViewModifier {
        var color: Color = PSDesignColors.textSecondary

        func body(content: Content) -> some View {
            content
                .font(caption)
                .foregroundStyle(color)
        }
    }

    struct FootnoteModifier: ViewModifier {
        var color: Color = PSDesignColors.textTertiary

        func body(content: Content) -> some View {
            content
                .font(footnote)
                .foregroundStyle(color)
        }
    }
}

extension View {
    func psLargeTitle() -> some View {
        modifier(PSDesignTypography.LargeTitleModifier())
    }

    func psTitle() -> some View {
        modifier(PSDesignTypography.TitleModifier())
    }

    func psHeadline() -> some View {
        modifier(PSDesignTypography.HeadlineModifier())
    }

    func psBody(color: Color = PSDesignColors.textPrimary) -> some View {
        modifier(PSDesignTypography.BodyModifier(color: color))
    }

    func psCallout(color: Color = PSDesignColors.textSecondary) -> some View {
        modifier(PSDesignTypography.CalloutModifier(color: color))
    }

    func psCaption(color: Color = PSDesignColors.textSecondary) -> some View {
        modifier(PSDesignTypography.CaptionModifier(color: color))
    }

    func psFootnote(color: Color = PSDesignColors.textTertiary) -> some View {
        modifier(PSDesignTypography.FootnoteModifier(color: color))
    }
}
