import SwiftUI

// MARK: - Step progress

struct CaptureProgressIndicator: View {
    let context: CaptureStepContext

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(CaptureGuidedStep.allCases.enumerated()), id: \.element.id) { index, step in
                stepNode(step)
                if index < CaptureGuidedStep.allCases.count - 1 {
                    connector(from: step)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capture progress: \(context.currentStep.title)")
    }

    @ViewBuilder
    private func stepNode(_ step: CaptureGuidedStep) -> some View {
        let completed = context.isCompleted(step)
        let active = context.isActive(step)

        VStack(spacing: PSDesignSpacing.xs) {
            Circle()
                .fill(completed || active ? PSDesignColors.primaryAccent : PSDesignColors.cardBackground)
                .frame(width: active ? 10 : 8, height: active ? 10 : 8)
                .overlay {
                    if completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 5, weight: .bold))
                            .foregroundStyle(PSDesignColors.onPrimaryAccent)
                    }
                }
                .overlay {
                    if active {
                        Circle()
                            .stroke(PSDesignColors.primaryAccent.opacity(0.35), lineWidth: 2)
                            .frame(width: 16, height: 16)
                    }
                }

            Text(step.shortTitle)
                .font(PSDesignTypography.footnote.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? PSDesignColors.textPrimary : PSDesignColors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .animation(PSDesignMotion.springSoft, value: context.currentStep)
    }

    private func connector(from step: CaptureGuidedStep) -> some View {
        Rectangle()
            .fill(context.isCompleted(step) ? PSDesignColors.primaryAccent.opacity(0.5) : PSDesignColors.divider)
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)
    }
}

// MARK: - Prominent capture mode switch

struct CaptureModeSwitchSection: View {
    let activeMode: CaptureMode
    let onSelect: (CaptureMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
            Text("Capture mode")
                .font(PSDesignTypography.caption.weight(.semibold))
                .foregroundStyle(PSDesignColors.textSecondary)

            HStack(spacing: PSDesignSpacing.sm) {
                modeButton(title: "Single", mode: .single)
                modeButton(title: "Batch", mode: .batch)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func modeButton(title: String, mode: CaptureMode) -> some View {
        let isSelected = activeMode == mode
        return Button {
            onSelect(mode)
        } label: {
            Text(title)
                .font(PSDesignTypography.bodyFont.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? PSDesignColors.onPrimaryAccent : PSDesignColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PSDesignSpacing.md - 2)
                .background(
                    RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                        .fill(isSelected ? PSDesignColors.primaryButtonFill : PSDesignColors.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                        .stroke(isSelected ? PSDesignColors.primaryAccent : PSDesignColors.divider, lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) capture mode")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Currently selected" : "Switch to \(title.lowercased()) capture mode")
    }
}

// MARK: - Batch progress

struct CaptureBatchProgressBanner: View {
    let productNumber: Int
    let capturedThisSession: Int

    var body: some View {
        HStack(spacing: PSDesignSpacing.sm) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PSDesignColors.primaryAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Product #\(productNumber)")
                    .font(PSDesignTypography.headline)
                    .foregroundStyle(PSDesignColors.textPrimary)
                if capturedThisSession > 0 {
                    Text("\(capturedThisSession) captured this session")
                        .psFootnote(color: PSDesignColors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(PSDesignSpacing.md - 4)
        .background(
            PSDesignColors.primaryAccent.opacity(0.08),
            in: RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
                .stroke(PSDesignColors.primaryAccent.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Required mode selection

struct CaptureModeSelectionSection: View {
    let prompt: String
    @Binding var selectedMode: CaptureMode?
    var singleTitle: String = "Single"
    var singleDetail: String = "One product at a time"
    var batchTitle: String = "Batch"
    var batchDetail: String = "Many products in one session"
    var onModeSelected: ((CaptureMode) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
            Text(prompt)
                .psCallout()

            VStack(spacing: PSDesignSpacing.sm) {
                modeCard(
                    mode: .single,
                    title: singleTitle,
                    detail: singleDetail,
                    systemImage: "1.circle.fill"
                )
                modeCard(
                    mode: .batch,
                    title: batchTitle,
                    detail: batchDetail,
                    systemImage: "square.stack.3d.up.fill"
                )
            }
        }
    }

    private func modeCard(mode: CaptureMode, title: String, detail: String, systemImage: String) -> some View {
        SelectionCard(isSelected: selectedMode == mode) {
            PSDesignHaptics.selection()
            selectedMode = mode
            onModeSelected?(mode)
        } content: {
            HStack(spacing: PSDesignSpacing.md) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(selectedMode == mode ? PSDesignColors.primaryAccent : PSDesignColors.textSecondary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: PSDesignSpacing.xs) {
                    Text(title)
                        .psHeadline()
                    Text(detail)
                        .psCaption()
                }
                Spacer(minLength: 0)
                if selectedMode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PSDesignColors.primaryAccent)
                }
            }
        }
    }
}

// MARK: - Workflow selection (Step 1)

struct CaptureWorkflowSelectionSection: View {
    @Binding var selectedWorkflow: CaptureWorkflowKind?
    @Binding var selectedCaptureMode: CaptureMode?
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.md) {
            Text("Choose Workflow")
                .psHeadline()

            VStack(spacing: PSDesignSpacing.sm) {
                ForEach(CaptureWorkflowKind.allCases) { workflow in
                    SelectionCard(isSelected: selectedWorkflow == workflow) {
                        PSDesignHaptics.selection()
                        selectedWorkflow = workflow
                        selectedCaptureMode = nil
                    } content: {
                        workflowCardContent(workflow)
                    }
                }
            }

            if selectedWorkflow == .standardCapture {
                CaptureModeSelectionSection(
                    prompt: "How are you photographing today?",
                    selectedMode: $selectedCaptureMode,
                    singleTitle: "Single Capture",
                    singleDetail: "One product, then identify and queue",
                    batchTitle: "Batch Capture",
                    batchDetail: "Continuous capture across many products",
                    onModeSelected: { _ in onContinue() }
                )
                .transition(PSDesignMotion.slideDown)
            }

            if selectedWorkflow == .multiAngle {
                CaptureModeSelectionSection(
                    prompt: "How are you photographing today?",
                    selectedMode: $selectedCaptureMode,
                    singleTitle: "Single Product",
                    singleDetail: "All angles for one item",
                    batchTitle: "Batch Products",
                    batchDetail: "Multi-angle sets across many items",
                    onModeSelected: { _ in onContinue() }
                )
                .transition(PSDesignMotion.slideDown)
            }
        }
        .animation(PSDesignMotion.springSoft, value: selectedWorkflow)
        .animation(PSDesignMotion.springSoft, value: selectedCaptureMode)
    }

    private func workflowCardContent(_ workflow: CaptureWorkflowKind) -> some View {
        HStack(alignment: .top, spacing: PSDesignSpacing.sm) {
            Image(systemName: workflow.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PSDesignColors.primaryAccent)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: PSDesignSpacing.xs) {
                Text(workflow.title)
                    .psHeadline()
                Text(workflow.subtitle)
                    .psCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

