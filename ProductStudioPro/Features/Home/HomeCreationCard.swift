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

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 100,
                    matching: .images
                ) {
                    HStack(spacing: PSDesignSpacing.sm) {
                        if isImporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.85)
                        }
                        Label(
                            isImporting ? "Importing…" : "Import Photos",
                            systemImage: PSDesignIcons.importPhotos
                        )
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                    }
                    .foregroundStyle(PSDesignColors.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                            .fill(PSDesignColors.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                            .stroke(PSDesignColors.divider, lineWidth: 1)
                    )
                }
                .disabled(isImporting)
                .opacity(isImporting ? PSDesignMotion.disabledOpacity : 1)

                HomeMoreImportOptions(
                    sources: moreImportSources,
                    isImporting: isImporting
                )
            }
            .padding(.top, PSDesignSpacing.xs)
        }
    }
}
