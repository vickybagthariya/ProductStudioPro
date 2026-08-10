import SwiftUI

// MARK: - Shared button chrome

enum PSButtonMetrics {
    /// Shared height for primary + secondary action pairs (Capture / Import, etc.).
    static let actionVerticalPadding: CGFloat = 15
    static let ghostVerticalPadding: CGFloat = 11
    static let horizontalPadding: CGFloat = PSDesignSpacing.md
    static let iconSpacing: CGFloat = PSDesignSpacing.sm
    static let circularSize: CGFloat = 44
    static let circularIconSize: CGFloat = 17
}

private struct PSButtonDisabledModifier: ViewModifier {
    let isDisabled: Bool
    let isLoading: Bool

    func body(content: Content) -> some View {
        content
            .disabled(isDisabled || isLoading)
            .opacity(isDisabled || isLoading ? PSDesignMotion.disabledOpacity : 1)
            .saturation(isDisabled || isLoading ? PSDesignMotion.disabledSaturation : 1)
    }
}

private struct PSButtonLoadingIndicator: View {
    var tint: Color = PSDesignColors.onPrimaryAccent

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(tint)
            .scaleEffect(0.85)
    }
}

// MARK: - PrimaryButton

/// Full-width filled call-to-action — export, capture, apply.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isDisabled: Bool = false
    var isLoading: Bool = false
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            guard !isDisabled, !isLoading else { return }
            action()
        } label: {
            HStack(spacing: PSButtonMetrics.iconSpacing) {
                if isLoading {
                    PSButtonLoadingIndicator()
                }
                if let systemImage, !isLoading {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PSButtonMetrics.actionVerticalPadding)
            .padding(.horizontal, PSButtonMetrics.horizontalPadding)
        }
        .buttonStyle(PSPrimaryButtonStyle())
        .modifier(PSButtonDisabledModifier(isDisabled: isDisabled, isLoading: isLoading))
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }
}

struct PSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppTheme.onPrimaryLabel(for: colorScheme))
            .background(
                RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                    .fill(AppTheme.primaryFill(for: colorScheme).opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                    .stroke(PSDesignColors.divider, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? PSDesignMotion.pressScale : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(PSDesignMotion.springSnappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { PSDesignHaptics.tap() }
            }
    }
}

// MARK: - SecondaryButton

/// Bordered neutral action — cancel adjacent paths, secondary flows.
struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isDisabled: Bool = false
    var isLoading: Bool = false
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            guard !isDisabled, !isLoading else { return }
            action()
        } label: {
            HStack(spacing: PSButtonMetrics.iconSpacing) {
                if isLoading {
                    PSButtonLoadingIndicator(tint: PSDesignColors.textPrimary)
                }
                if let systemImage, !isLoading {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PSButtonMetrics.actionVerticalPadding)
            .padding(.horizontal, PSButtonMetrics.horizontalPadding)
        }
        .buttonStyle(PSSecondaryButtonStyle())
        .modifier(PSButtonDisabledModifier(isDisabled: isDisabled, isLoading: isLoading))
    }
}

/// Neutral bordered chrome — same metrics as ``PSPrimaryButtonStyle`` (width/height/radius/padding).
struct PSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(PSDesignColors.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                    .fill(PSDesignColors.cardBackground.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                    .stroke(PSDesignColors.divider, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? PSDesignMotion.pressScale : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(PSDesignMotion.springSnappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { PSDesignHaptics.tap() }
            }
    }
}

// MARK: - GhostButton

/// Text-only or minimal action — tertiary paths, inline links.
struct GhostButton: View {
    let title: String
    var systemImage: String? = nil
    var isDisabled: Bool = false
    var isLoading: Bool = false
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            guard !isDisabled, !isLoading else { return }
            action()
        } label: {
            HStack(spacing: PSButtonMetrics.iconSpacing) {
                if isLoading {
                    PSButtonLoadingIndicator(tint: PSDesignColors.primaryAccent)
                }
                if let systemImage, !isLoading {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .padding(.vertical, PSButtonMetrics.ghostVerticalPadding)
            .padding(.horizontal, PSButtonMetrics.horizontalPadding)
        }
        .buttonStyle(PSGhostButtonStyle())
        .modifier(PSButtonDisabledModifier(isDisabled: isDisabled, isLoading: isLoading))
    }
}

private struct PSGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(PSDesignColors.primaryAccent.opacity(configuration.isPressed ? 0.7 : 1))
            .background(
                RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
                    .fill(PSDesignColors.primaryAccent.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .scaleEffect(configuration.isPressed ? PSDesignMotion.pressScaleCompact : 1)
            .animation(PSDesignMotion.springSnappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { PSDesignHaptics.tap() }
            }
    }
}

// MARK: - CircularIconButton

/// Compact circular icon control — toolbars, dismiss, navigation chrome.
struct CircularIconButton: View {
    let systemName: String
    var accessibilityLabel: String
    var size: CGFloat = PSButtonMetrics.circularSize
    var iconSize: CGFloat = PSButtonMetrics.circularIconSize
    var isDisabled: Bool = false
    var isLoading: Bool = false
    var style: Style = .material
    let action: () -> Void

    enum Style {
        case material
        case filled
        case ghost
    }

    var body: some View {
        Button {
            guard !isDisabled, !isLoading else { return }
            action()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: iconSize, weight: .semibold))
                }
            }
            .foregroundStyle(foregroundColor)
            .frame(width: size, height: size)
            .background(background)
            .clipShape(Circle())
            .overlay(Circle().stroke(PSDesignColors.divider, lineWidth: style == .ghost ? 0 : 1))
        }
        .buttonStyle(FeedbackPressButtonStyle(
            pressedScale: PSDesignMotion.pressScaleIcon,
            playsHaptic: true
        ))
        .modifier(PSButtonDisabledModifier(isDisabled: isDisabled, isLoading: isLoading))
        .accessibilityLabel(accessibilityLabel)
    }

    private var foregroundColor: Color {
        switch style {
        case .material, .ghost: return PSDesignColors.primaryAccent
        case .filled: return PSDesignColors.onPrimaryAccent
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .material:
            Circle().fill(.ultraThinMaterial)
        case .filled:
            Circle().fill(PSDesignColors.primaryButtonFill)
        case .ghost:
            Circle().fill(Color.clear)
        }
    }
}
