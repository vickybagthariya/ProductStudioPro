import SwiftUI

/// Scroll targets for the guided capture workflow.
enum CaptureScrollID {
    /// Primary Retake Photo button — post-capture auto-scroll anchor.
    static let retakePhoto = "retakePhoto"
    static let identifyProduct = "identifyProduct"
}

/// Capture-specific screen chrome using PSDesign tokens.
struct CaptureFlowScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let queueCount: Int
    let onBack: () -> Void
    let onQueue: () -> Void
    var scrollDismissesKeyboardInteractively: Bool = false
    @Binding var scrollTargetID: String?
    var scrollAnchor: UnitPoint = .top
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    content()
                        .padding(.horizontal, PSDesignSpacing.screenHorizontal)
                        .padding(.top, PSDesignSpacing.sm)
                        .padding(.bottom, PSDesignSpacing.xxl)
                }
                .scrollDismissesKeyboard(scrollDismissesKeyboardInteractively ? .interactively : .never)
                .onChange(of: scrollTargetID) { _, targetID in
                    guard let targetID else { return }
                    withAnimation(PSDesignMotion.springSoft) {
                        proxy.scrollTo(targetID, anchor: scrollAnchor)
                    }
                    DispatchQueue.main.async {
                        scrollTargetID = nil
                    }
                }
            }
        }
        .background(PSDesignColors.background)
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: PSDesignSpacing.sm) {
            CircularIconButton(
                systemName: PSDesignIcons.back,
                accessibilityLabel: "Back",
                style: .ghost,
                action: onBack
            )

            VStack(alignment: .leading, spacing: PSDesignSpacing.xs) {
                Text(title)
                    .font(PSDesignTypography.headline)
                    .foregroundStyle(PSDesignColors.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .psCaption()
                        .lineLimit(2)
                }
            }

            Spacer(minLength: PSDesignSpacing.sm)

            Button(action: onQueue) {
                HStack(spacing: PSDesignSpacing.xs) {
                    Image(systemName: PSDesignIcons.queue)
                        .font(.caption.weight(.semibold))
                    Text("Queue")
                        .font(PSDesignTypography.caption)
                    if queueCount > 0 {
                        Text("\(queueCount)")
                            .font(PSDesignTypography.footnote.weight(.bold))
                            .foregroundStyle(PSDesignColors.onPrimaryAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PSDesignColors.primaryAccent, in: Capsule())
                    }
                }
                .foregroundStyle(PSDesignColors.primaryAccent)
                .padding(.horizontal, PSDesignSpacing.sm + 2)
                .padding(.vertical, PSDesignSpacing.sm)
                .background(PSDesignColors.cardBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Queue, \(queueCount) items")
        }
        .padding(.horizontal, PSDesignSpacing.screenHorizontal)
        .padding(.top, PSDesignSpacing.sm)
        .padding(.bottom, PSDesignSpacing.sm)
    }
}

// MARK: - Toast

struct CaptureFlowToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PSDesignTypography.headline)
            .foregroundStyle(PSDesignColors.onPrimaryAccent)
            .padding(.horizontal, PSDesignSpacing.md)
            .padding(.vertical, PSDesignSpacing.sm + 2)
            .background(Capsule().fill(PSDesignColors.primaryButtonFill))
            .psShadowMedium()
    }
}
