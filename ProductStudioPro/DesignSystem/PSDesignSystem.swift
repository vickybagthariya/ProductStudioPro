import SwiftUI

/// Umbrella namespace for the Product Studio design system.
///
/// Prefer `PSDesignColors`, `PSDesignTypography`, `PSDesignSpacing`, and component
/// types (`PrimaryButton`, `FeatureCard`, etc.) in future screen work.
///
/// Legacy `DS` tokens remain active for existing screens until they are migrated.
enum PSDesignSystem {
    typealias Colors = PSDesignColors
    typealias Typography = PSDesignTypography
    typealias Spacing = PSDesignSpacing
    typealias Radius = PSDesignRadius
    typealias Shadow = PSDesignShadow
    typealias Motion = PSDesignMotion
    typealias Haptics = PSDesignHaptics
    typealias Icons = PSDesignIcons
}

#if DEBUG
struct PSDesignSystemPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PSDesignSpacing.lg) {
                Text("Design System")
                    .psLargeTitle()

                FeatureCard(title: "Capture", subtitle: "Single product workflow", systemImage: PSDesignIcons.capture) {
                    Text("Premium catalog photography for retail teams.")
                        .psCallout()
                }

                HStack(spacing: PSDesignSpacing.sm) {
                    FilterChip(title: "Front", systemImage: "viewfinder", isSelected: true) {}
                    FilterChip(title: "Back", isSelected: false) {}
                    CategoryChip(title: "Amazon", isSelected: true)
                }

                HStack(spacing: PSDesignSpacing.sm) {
                    StatusChip(title: "Ready", systemImage: PSDesignIcons.success, tone: .success)
                    StatusChip(title: "Processing", tone: .accent)
                }

                PrimaryButton("Export Package", systemImage: PSDesignIcons.export) {}
                SecondaryButton("Share JPG", systemImage: PSDesignIcons.share) {}
                GhostButton("Learn more", systemImage: PSDesignIcons.info) {}

                HStack(spacing: PSDesignSpacing.md) {
                    CircularIconButton(systemName: PSDesignIcons.back, accessibilityLabel: "Back") {}
                    CircularIconButton(systemName: PSDesignIcons.settings, accessibilityLabel: "Settings", style: .filled) {}
                }
            }
            .padding(PSDesignSpacing.md)
        }
        .background(PSDesignColors.background)
    }
}

#Preview("Design System Gallery") {
    PSDesignSystemPreviewGallery()
}
#endif
