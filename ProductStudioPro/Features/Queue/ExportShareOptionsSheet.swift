import SwiftUI

/// Full-width share/export format picker (replaces compact `confirmationDialog` popovers).
struct ExportShareOptionsSheet: View {
    let title: String
    let message: String
    var isSingleImage: Bool = false
    let onZip: () -> Void
    let onJPG: () -> Void
    let onPNG: () -> Void
    let onCSV: () -> Void
    var onCancel: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(DS.TypeScale.sectionTitle)
                    .foregroundStyle(DS.ColorToken.label)
                Text(message)
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.screenHorizontal)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ViewThatFits(in: .vertical) {
                optionsStack
                ScrollView {
                    optionsStack
                }
                .scrollIndicators(.hidden)
            }

            Button {
                onCancel?()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.label)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .fill(DS.ColorToken.backgroundTertiary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .stroke(DS.ColorToken.separator, lineWidth: 1)
                    )
            }
            .buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScaleCompact, playsHaptic: true))
            .padding(.horizontal, DS.Space.screenHorizontal)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(DS.ColorToken.backgroundSecondary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
    }

    private var optionsStack: some View {
        VStack(spacing: 8) {
            shareOptionButton(
                title: "ZIP export",
                subtitle: isSingleImage ? "Images, CSV, and manifest in one archive" : "All selected images in one ZIP",
                systemImage: "doc.zipper",
                emphasis: .primary,
                action: onZip
            )
            shareOptionButton(
                title: isSingleImage ? "JPG image…" : "JPG images…",
                subtitle: "Optional CSV on the next step",
                systemImage: "photo",
                emphasis: .secondary,
                action: onJPG
            )
            shareOptionButton(
                title: isSingleImage ? "PNG transparent cutout…" : "PNG transparent cutouts…",
                subtitle: "Keeps transparency when backgrounds were removed",
                systemImage: "circle.dashed",
                emphasis: .secondary,
                action: onPNG
            )
            shareOptionButton(
                title: "CSV only",
                subtitle: "Inventory list without images",
                systemImage: "tablecells",
                emphasis: .secondary,
                action: onCSV
            )
        }
        .padding(.horizontal, DS.Space.screenHorizontal)
    }

    private enum Emphasis {
        case primary
        case secondary
    }

    private func shareOptionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        emphasis: Emphasis,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(DS.TypeScale.micro)
                        .opacity(0.85)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .opacity(0.45)
            }
            .foregroundStyle(emphasis == .primary ? DS.ColorToken.onAccent : DS.ColorToken.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(emphasis == .primary ? DS.ColorToken.primaryButtonFill : DS.ColorToken.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .stroke(DS.ColorToken.separator, lineWidth: 1)
            )
        }
        .buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScaleCompact, playsHaptic: true))
    }
}
