import SwiftUI

// MARK: - Camera focus section

struct CaptureCameraSection: View {
    let headline: String
    let detail: String
    let previewImage: UIImage?
    let captureButtonTitle: String
    let isMultiAngle: Bool
    let currentAngleLabel: String
    let onCapture: () -> Void

    private var isCompact: Bool { previewImage != nil }

    /// Pre-capture placeholder aspect ratio — slightly wider than tall to conserve vertical space.
    private static let previewAspectRatio: CGFloat = 1.28

    var body: some View {
        VStack(spacing: isCompact ? PSDesignSpacing.sm : PSDesignSpacing.sm) {
            Button(action: onCapture) {
                previewArea
            }
            .buttonStyle(.plain)
            .accessibilityLabel(previewImage == nil ? "Open camera" : "Retake photo")

            if !isCompact {
                VStack(spacing: PSDesignSpacing.xs) {
                    if isMultiAngle {
                        Text("Current angle: \(currentAngleLabel)")
                            .font(PSDesignTypography.caption.weight(.semibold))
                            .foregroundStyle(PSDesignColors.primaryAccent)
                    }
                    Text(headline)
                        .psHeadline()
                    Text(detail)
                        .psCallout()
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }

            captureActionButton
                .padding(.vertical, isCompact ? 0 : PSDesignSpacing.xs)
        }
    }

    @ViewBuilder
    private var captureActionButton: some View {
        if isCompact {
            PrimaryButton(captureButtonTitle, systemImage: PSDesignIcons.capture) {
                onCapture()
            }
            .id(CaptureScrollID.retakePhoto)
            .accessibilityLabel("Retake Photo")
            .accessibilityHint("Discards this photo and opens the camera again")
        } else {
            PrimaryButton(captureButtonTitle, systemImage: PSDesignIcons.capture) {
                onCapture()
            }
            .accessibilityLabel("Capture Photo")
            .accessibilityHint("Opens the camera to capture a product photo")
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PSDesignRadius.lg, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .aspectRatio(isCompact ? 2.4 : Self.previewAspectRatio, contentMode: .fit)
                .overlay {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFill()
                            .accessibilityLabel("Latest captured photo")
                    } else {
                        VStack(spacing: PSDesignSpacing.sm) {
                            Image(systemName: isMultiAngle ? "camera.metering.matrix" : "camera.viewfinder")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(Color.white.opacity(0.55))
                            Text(isMultiAngle ? "Tap to capture \(currentAngleLabel)" : "Tap to capture")
                                .font(PSDesignTypography.caption)
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: PSDesignRadius.lg, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if previewImage == nil {
                        Image(systemName: PSDesignIcons.capture)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(PSDesignSpacing.sm)
                    }
                }
        }
        .psShadowMedium()
    }
}

// MARK: - Angle progression chips

struct CaptureAngleProgressSection: View {
    let angles: [ProductAngle]
    let currentIndex: Int
    let completedAngles: Set<ProductAngle>

    var body: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
            Text("Angles")
                .psCaption()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PSDesignSpacing.sm) {
                    ForEach(Array(angles.enumerated()), id: \.element.id) { index, angle in
                        angleChip(angle: angle, index: index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func angleChip(angle: ProductAngle, index: Int) -> some View {
        let isCurrent = index == currentIndex
        let isCompleted = completedAngles.contains(angle)

        if isCompleted {
            StatusChip(title: angle.badgeTitle, systemImage: "checkmark", tone: .success)
        } else if isCurrent {
            FilterChip(title: angle.badgeTitle, systemImage: "viewfinder", isSelected: true) {}
                .allowsHitTesting(false)
        } else {
            CategoryChip(title: angle.badgeTitle)
        }
    }
}

// MARK: - Buffered multi-angle thumbnails

struct CaptureBufferedImagesStrip: View {
    let captures: [CaptureSessionStore.PendingMultiAngleCapture]
    let totalCount: Int
    @State private var appearedIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
            HStack {
                Text("Captured angles")
                    .psCaption()
                Spacer()
                Text("\(captures.count)/\(totalCount)")
                    .psFootnote(color: PSDesignColors.primaryAccent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PSDesignSpacing.sm) {
                    ForEach(captures.sorted(by: { $0.ordinal < $1.ordinal })) { shot in
                        thumbnail(for: shot)
                    }
                }
            }
        }
    }

    private func thumbnail(for shot: CaptureSessionStore.PendingMultiAngleCapture) -> some View {
        VStack(spacing: PSDesignSpacing.xs) {
            Image(uiImage: shot.image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
                        .stroke(PSDesignColors.divider, lineWidth: 1)
                }

            Text(shot.angle.badgeTitle)
                .font(PSDesignTypography.footnote.weight(.semibold))
                .foregroundStyle(PSDesignColors.textSecondary)
                .lineLimit(1)
        }
        .scaleEffect(appearedIDs.contains(shot.id) ? 1 : 0.85)
        .opacity(appearedIDs.contains(shot.id) ? 1 : 0)
        .onAppear {
            withAnimation(PSDesignMotion.springBouncy) {
                _ = appearedIDs.insert(shot.id)
            }
        }
    }
}
