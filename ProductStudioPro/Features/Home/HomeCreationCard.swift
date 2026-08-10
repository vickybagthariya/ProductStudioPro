import SwiftUI
import PhotosUI

/// Primary hero card — capture and import entry points.
struct HomeCreationCard: View {
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    var isImporting: Bool
    let onCapture: () -> Void
    let onImportFiles: () -> Void
    let onImportURL: () -> Void
    let onImportClipboard: () -> Void

    private var moreImportSources: [HomeImportSourceOption] {
        HomeImportSourceCatalog.homeScreenSources(
            isImporting: isImporting,
            onImportFiles: onImportFiles,
            onImportURL: onImportURL,
            onImportClipboard: onImportClipboard
        )
    }

    var body: some View {
        FeatureCard(
            title: "Create Product Photos",
            subtitle: "Capture or import products and prepare them for your catalog.",
            systemImage: PSDesignIcons.capture
        ) {
            VStack(spacing: PSDesignSpacing.sm + 2) {
                PrimaryButton(
                    "Capture Products",
                    systemImage: PSDesignIcons.capture,
                    action: {
                        PSDesignHaptics.tap()
                        onCapture()
                    }
                )

                // PhotosPicker must own the control; apply the same secondary chrome as SecondaryButton
                // (no nested Background — that caused the double halo around Import Photos).
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 100,
                    matching: .images
                ) {
                    HStack(spacing: PSButtonMetrics.iconSpacing) {
                        if isImporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(PSDesignColors.textPrimary)
                                .scaleEffect(0.85)
                            Text("Importing…")
                        } else {
                            Label("Import Photos", systemImage: PSDesignIcons.importPhotos)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PSButtonMetrics.actionVerticalPadding)
                    .padding(.horizontal, PSButtonMetrics.horizontalPadding)
                }
                .buttonStyle(PSSecondaryButtonStyle())
                .disabled(isImporting)
                .opacity(isImporting ? PSDesignMotion.disabledOpacity : 1)
                .accessibilityLabel(isImporting ? "Importing photos" : "Import Photos")

                HomeMoreImportOptions(
                    sources: moreImportSources,
                    isImporting: isImporting
                )
            }
            .padding(.top, PSDesignSpacing.xs)
        }
    }
}
