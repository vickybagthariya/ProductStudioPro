import SwiftUI

/// Single polish entry point — one button, no exposed sliders.
struct AIPolishEnhanceButton: View {
    var isEnhanced: Bool
    var isProcessing: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DS.ColorToken.accent)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(isEnhanced ? "Enhanced" : "Enhance")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isEnhanced ? DS.ColorToken.onAccent : DS.ColorToken.label)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.compactControl, style: .continuous)
                    .fill(isEnhanced ? DS.ColorToken.primaryButtonFill : DS.ColorToken.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.compactControl, style: .continuous)
                    .stroke(DS.ColorToken.separator, lineWidth: 1)
            )
        }
        .buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScaleCompact, playsHaptic: true))
        .disabled(isProcessing)
        .opacity(isProcessing ? DS.Motion.disabledOpacity : 1)
        .accessibilityLabel(isEnhanced ? "Photo enhanced" : "Enhance photo")
        .accessibilityHint("Applies on-device AI polish")
    }
}
