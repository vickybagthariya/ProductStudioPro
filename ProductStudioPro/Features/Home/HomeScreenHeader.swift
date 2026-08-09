import SwiftUI

/// Top header for the redesigned Home dashboard.
struct HomeScreenHeader: View {
    let sessionName: String
    let queuedCount: Int
    var showsBranding: Bool = false
    var businessLine: String? = nil
    var brandMarkActive: Bool = false
    let onManageSessions: () -> Void
    let onOpenQueue: () -> Void
    let onOpenSettings: () -> Void
    let onOpenBrandKit: () -> Void
    let onShowAbout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.md) {
            VStack(alignment: .leading, spacing: PSDesignSpacing.xs) {
                Text("Product Studio Pro")
                    .psLargeTitle()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Create catalog-ready product images")
                    .psCallout()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsBranding, let businessLine, !businessLine.isEmpty {
                Text(businessLine)
                    .psFootnote()
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
                sessionChipsRow

                HStack {
                    Spacer(minLength: 0)
                    headerActions
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerActions: some View {
        HStack(spacing: PSDesignSpacing.sm) {
            CircularIconButton(
                systemName: brandMarkActive ? "seal.fill" : "seal",
                accessibilityLabel: brandMarkActive ? "Brand Kit, active" : "Brand Kit",
                size: 40,
                iconSize: 16,
                style: .material
            ) {
                PSDesignHaptics.tap()
                onOpenBrandKit()
            }

            CircularIconButton(
                systemName: PSDesignIcons.settings,
                accessibilityLabel: "Settings",
                size: 40,
                iconSize: 16,
                style: .material
            ) {
                PSDesignHaptics.tap()
                onOpenSettings()
            }

            CircularIconButton(
                systemName: PSDesignIcons.info,
                accessibilityLabel: "Help",
                size: 40,
                iconSize: 16,
                style: .material
            ) {
                PSDesignHaptics.tap()
                onShowAbout()
            }
        }
    }

    private var sessionChipsRow: some View {
        HStack(spacing: PSDesignSpacing.sm) {
            Button {
                PSDesignHaptics.selection()
                onManageSessions()
            } label: {
                HStack(spacing: PSDesignSpacing.xs) {
                    Image(systemName: PSDesignIcons.folder)
                        .font(.caption.weight(.semibold))
                    Text(sessionName)
                        .psCaption(color: PSDesignColors.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, PSDesignSpacing.sm + 2)
                .padding(.vertical, PSDesignSpacing.sm - 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(PSDesignColors.cardBackground)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(PSDesignColors.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Manage session \(sessionName)")

            Button {
                PSDesignHaptics.selection()
                onOpenQueue()
            } label: {
                StatusChip(
                    title: "\(queuedCount) in Queue",
                    systemImage: PSDesignIcons.queue,
                    tone: queuedCount > 0 ? .accent : .neutral
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(queuedCount) products in queue")

            Spacer(minLength: 0)
        }
    }
}
