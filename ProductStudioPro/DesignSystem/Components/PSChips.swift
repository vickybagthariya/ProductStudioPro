import SwiftUI

// MARK: - Shared chip base

private struct PSChipLabel: View {
    let title: String
    var systemImage: String? = nil
    var foreground: Color
    var font: Font = PSDesignTypography.caption

    var body: some View {
        HStack(spacing: PSDesignSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(title)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(foreground)
    }
}

private struct PSChipContainer<Content: View>: View {
    var isSelected: Bool
    var selectedFill: Color
    var unselectedFill: Color
    var selectedBorder: Color
    var unselectedBorder: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, PSDesignSpacing.sm + 2)
            .padding(.vertical, PSDesignSpacing.sm - 3)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? selectedFill : unselectedFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? selectedBorder : unselectedBorder, lineWidth: isSelected ? 1.5 : 1)
            )
            .animation(PSDesignMotion.springSnappy, value: isSelected)
    }
}

// MARK: - StatusChip

/// Read-only status indicator — queue state, processing badges.
struct StatusChip: View {
    let title: String
    var systemImage: String? = nil
    var tone: Tone = .neutral

    enum Tone {
        case neutral
        case success
        case warning
        case error
        case accent

        var foreground: Color {
            switch self {
            case .neutral: return PSDesignColors.textSecondary
            case .success: return PSDesignColors.success
            case .warning: return PSDesignColors.warning
            case .error: return PSDesignColors.error
            case .accent: return PSDesignColors.primaryAccent
            }
        }

        var background: Color {
            switch self {
            case .neutral: return PSDesignColors.cardBackground
            case .success: return PSDesignColors.success.opacity(0.12)
            case .warning: return PSDesignColors.warning.opacity(0.14)
            case .error: return PSDesignColors.error.opacity(0.12)
            case .accent: return PSDesignColors.primaryAccent.opacity(0.12)
            }
        }

        var border: Color {
            switch self {
            case .neutral: return PSDesignColors.divider
            default: return foreground.opacity(0.35)
            }
        }
    }

    var body: some View {
        PSChipContainer(
            isSelected: false,
            selectedFill: tone.background,
            unselectedFill: tone.background,
            selectedBorder: tone.border,
            unselectedBorder: tone.border
        ) {
            PSChipLabel(title: title, systemImage: systemImage, foreground: tone.foreground)
        }
        .accessibilityLabel(title)
    }
}

// MARK: - FilterChip

/// Toggleable filter pill — export format, angle, background type.
struct FilterChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            PSDesignHaptics.selection()
            action()
        } label: {
            PSChipContainer(
                isSelected: isSelected,
                selectedFill: PSDesignColors.primaryButtonFill,
                unselectedFill: PSDesignColors.cardBackground,
                selectedBorder: PSDesignColors.primaryAccent,
                unselectedBorder: PSDesignColors.divider
            ) {
                PSChipLabel(
                    title: title,
                    systemImage: systemImage,
                    foreground: isSelected ? PSDesignColors.onPrimaryAccent : PSDesignColors.textPrimary
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - CategoryChip

/// Catalog taxonomy pill — marketplace, category, tag grouping.
struct CategoryChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button {
                    PSDesignHaptics.selection()
                    action()
                } label: {
                    chipBody
                }
                .buttonStyle(.plain)
            } else {
                chipBody
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var chipBody: some View {
        PSChipContainer(
            isSelected: isSelected,
            selectedFill: PSDesignColors.primaryAccent.opacity(0.14),
            unselectedFill: PSDesignColors.elevatedBackground,
            selectedBorder: PSDesignColors.primaryAccent,
            unselectedBorder: PSDesignColors.divider
        ) {
            PSChipLabel(
                title: title,
                systemImage: systemImage,
                foreground: isSelected ? PSDesignColors.primaryAccent : PSDesignColors.textSecondary,
                font: PSDesignTypography.footnote.weight(.semibold)
            )
        }
    }
}
