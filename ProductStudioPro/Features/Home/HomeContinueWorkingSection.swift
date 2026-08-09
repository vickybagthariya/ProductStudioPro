import SwiftUI

/// Display model for a recent queue item on Home.
struct HomeRecentItem: Identifiable {
    let id: UUID
    let productName: String
    let subtitle: String
    let statusLabel: String
    let statusTone: StatusChip.Tone
    let thumbnail: UIImage
    let queueIndex: Int
}

/// Recent work list with empty state and See All action.
struct HomeContinueWorkingSection: View {
    let items: [HomeRecentItem]
    let onSeeAll: () -> Void
    let onSelectItem: (Int) -> Void
    let onCapture: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Continue Working")
                    .psHeadline()
                Spacer(minLength: PSDesignSpacing.sm)
                if !items.isEmpty {
                    Button("See All") {
                        PSDesignHaptics.selection()
                        onSeeAll()
                    }
                    .font(PSDesignTypography.callout.weight(.semibold))
                    .foregroundStyle(PSDesignColors.primaryAccent)
                }
            }

            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: PSDesignSpacing.sm - 2) {
                    ForEach(items) { item in
                        Button {
                            PSDesignHaptics.selection()
                            onSelectItem(item.queueIndex)
                        } label: {
                            ListCard(compact: true) {
                                recentRow(item)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.productName), \(item.subtitle)")
                        .accessibilityHint("Opens product preview")
                    }
                }
            }
        }
    }

    private func recentRow(_ item: HomeRecentItem) -> some View {
        HStack(spacing: PSDesignSpacing.sm) {
            Image(uiImage: item.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
                        .stroke(PSDesignColors.divider, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: PSDesignSpacing.xs - 2) {
                Text(item.productName)
                    .font(Font.subheadline.weight(.medium))
                    .foregroundStyle(PSDesignColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(item.subtitle)
                    .psCaption()
                    .lineLimit(1)

                StatusChip(
                    title: item.statusLabel,
                    tone: item.statusTone
                )
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PSDesignColors.textTertiary)
        }
    }

    private var emptyState: some View {
        FeatureCard(
            title: "No products yet",
            subtitle: "Capture or import your first product to begin building your catalog.",
            systemImage: PSDesignIcons.product
        ) {
            VStack(spacing: PSDesignSpacing.sm) {
                PrimaryButton("Capture Products", systemImage: PSDesignIcons.capture) {
                    PSDesignHaptics.tap()
                    onCapture()
                }
                SecondaryButton("Import Photos", systemImage: PSDesignIcons.importPhotos) {
                    PSDesignHaptics.tap()
                    onImport()
                }
            }
            .padding(.top, PSDesignSpacing.xs)
        }
    }
}
