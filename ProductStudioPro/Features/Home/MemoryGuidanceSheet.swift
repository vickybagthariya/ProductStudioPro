import SwiftUI

/// Proactive tips when the session approaches memory / queue budget limits.
struct MemoryGuidanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: MemoryPressureSnapshot
    var isBlocking: Bool = false
    var onGoToQueue: (() -> Void)?
    var onManageSessions: (() -> Void)?

    var body: some View {
        NavigationStack {
            AppScreenScaffold(
                title: isBlocking ? "Can’t Add More Photos" : "Keep the App Smooth",
                showsHome: false,
                layout: .scroll
            ) {
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    statusCard
                    tipsCard
                    actionsCard
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isBlocking ? "OK" : "Got It") { dismiss() }
                        .foregroundStyle(DS.ColorToken.accent)
                }
                .dsHideToolbarSharedBackground()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var statusCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.stack) {
                Label(
                    isBlocking ? "Memory protection" : "Memory tip",
                    systemImage: isBlocking ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.67percent"
                )
                .font(DS.TypeScale.rowTitle)
                .foregroundStyle(DS.ColorToken.label)

                Text(statusBody)
                    .font(DS.TypeScale.body)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)

                HStack(spacing: DS.Space.stack) {
                    metricChip(title: "Pressure", value: snapshot.level.title)
                    metricChip(title: "Free", value: "\(snapshot.availableMegabytes) MB")
                    metricChip(title: "Queued", value: "\(snapshot.queueCount)/\(snapshot.softQueueCap)")
                }
            }
        }
    }

    private var statusBody: String {
        if isBlocking {
            return "Product Studio keeps a safety cushion so the phone stays responsive. Free some space in this session before capturing or importing more."
        }
        return "This session is getting heavy. The app will slow heavy work and free caches automatically — following the tips below helps avoid stalls."
    }

    private var tipsCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.stack) {
                Text("Recommended")
                    .font(DS.TypeScale.rowTitle)
                    .foregroundStyle(DS.ColorToken.label)
                ForEach(Array(snapshot.recommendedActions.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.accent)
                            .padding(.top, 2)
                        Text(tip)
                            .font(DS.TypeScale.body)
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var actionsCard: some View {
        VStack(spacing: DS.Space.stack) {
            if let onGoToQueue {
                Button {
                    dismiss()
                    onGoToQueue()
                } label: {
                    Label("Open Queue", systemImage: "square.stack.3d.up")
                        .font(DS.TypeScale.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if let onManageSessions {
                Button {
                    dismiss()
                    onManageSessions()
                } label: {
                    Label("Manage Sessions", systemImage: "folder")
                        .font(DS.TypeScale.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.TypeScale.micro)
                .foregroundStyle(DS.ColorToken.tertiaryLabel)
            Text(value)
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }
}
