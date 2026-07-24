import SwiftUI

/// Slide-up Tone controls so the main preview stays visible while adjusting.
struct ToneAdjustSheet: View {
    @Binding var tones: ManualToneAdjustments
    var histogram: ExposureHistogramSnapshot?
    /// Lightweight live preview while dragging.
    var onInteractive: (() -> Void)? = nil
    /// Higher-quality pass when the finger lifts.
    var onCommit: () -> Void
    var onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Drag for a live preview; release for a sharper update.")
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    if let histogram {
                        HistogramDockRow(snapshot: histogram)
                    }

                    toneSlider("Exposure", keyPath: \.exposure, range: -2...2)
                    toneSlider("Contrast", keyPath: \.contrast, range: -1...1)
                    toneSlider("Highlights", keyPath: \.highlights, range: -1...1)
                    toneSlider("Shadows", keyPath: \.shadows, range: -1...1)
                    toneSlider("Vibrance", keyPath: \.vibrance, range: -1...1)
                    toneSlider("Warmth", keyPath: \.warmth, range: -1...1)

                    if !tones.isNeutral {
                        Button("Reset tone") {
                            tones = .neutral
                            onReset()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.accent)
                    }
                }
                .padding(.horizontal, DS.Space.screenHorizontal)
                .padding(.vertical, 16)
            }
            .background(DS.ColorToken.backgroundSecondary)
            .navigationTitle("Tone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func toneSlider(
        _ title: String,
        keyPath: WritableKeyPath<ManualToneAdjustments, Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.label)
                Spacer()
                Text(String(format: "%+.2f", tones[keyPath: keyPath]))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { tones[keyPath: keyPath] },
                    set: { newValue in
                        tones[keyPath: keyPath] = newValue
                        onInteractive?()
                    }
                ),
                in: range
            ) { editing in
                if !editing { onCommit() }
            }
            .tint(DS.ColorToken.accent)
        }
    }
}
