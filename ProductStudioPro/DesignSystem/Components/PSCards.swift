import SwiftUI

// MARK: - FeatureCard

/// Hero-style card for dashboard actions and onboarding highlights.
struct FeatureCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
            if title != nil || systemImage != nil {
                HStack(spacing: PSDesignSpacing.sm) {
                    if let systemImage {
                        PSFeatureIconBadge(systemName: systemImage)
                    }
                    VStack(alignment: .leading, spacing: PSDesignSpacing.xs) {
                        if let title {
                            Text(title)
                                .psHeadline()
                        }
                        if let subtitle {
                            Text(subtitle)
                                .psCaption()
                        }
                    }
                }
            }
            content()
        }
        .padding(PSDesignSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PSDesignColors.elevatedBackground, in: RoundedRectangle(cornerRadius: PSDesignRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSDesignRadius.lg, style: .continuous)
                .stroke(PSDesignColors.divider, lineWidth: 1)
        )
        .psShadowMedium()
    }
}

private struct PSFeatureIconBadge: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(PSDesignColors.primaryAccent)
            .frame(width: 44, height: 44)
            .background(PSDesignColors.cardBackground, in: RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
                    .stroke(PSDesignColors.divider, lineWidth: 1)
            )
    }
}

// MARK: - SelectionCard

/// Tappable card with selected/unselected states — presets, templates, modes.
struct SelectionCard<Content: View>: View {
    var isSelected: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if let action {
                Button(action: {
                    PSDesignHaptics.selection()
                    action()
                }) {
                    cardBody
                }
                .buttonStyle(.plain)
            } else {
                cardBody
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardBody: some View {
        content()
            .padding(PSDesignSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                    .fill(isSelected ? PSDesignColors.cardBackground : PSDesignColors.elevatedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                    .stroke(
                        isSelected ? PSDesignColors.primaryAccent : PSDesignColors.divider,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .psShadowSmall()
            .animation(PSDesignMotion.springSoft, value: isSelected)
    }
}

// MARK: - ListCard

/// Compact row card for queues, settings rows, and catalog lists.
struct ListCard<Content: View>: View {
    var isSelected: Bool = false
    var compact: Bool = false
    @ViewBuilder var content: () -> Content

    private var verticalPadding: CGFloat { compact ? PSDesignSpacing.sm - 1 : PSDesignSpacing.md - 4 }
    private var horizontalPadding: CGFloat { compact ? PSDesignSpacing.sm + 2 : PSDesignSpacing.md - 4 }

    var body: some View {
        content()
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
                    .fill(isSelected ? PSDesignColors.cardBackground : PSDesignColors.elevatedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
                    .stroke(
                        isSelected ? PSDesignColors.primaryAccent : PSDesignColors.divider,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .psShadowSmall()
    }
}
