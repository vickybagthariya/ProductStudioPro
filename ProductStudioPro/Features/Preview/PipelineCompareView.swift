#if DEBUG
import SwiftUI
import UIKit

/// Compact DEBUG compare: Final Individual vs Grouped Cover, production replay, stored asset, write chain.
struct PipelineCompareView: View {
    let product: CapturedProduct

    @Environment(\.dismiss) private var dismiss
    @State private var report: PipelineForensics.Report?
    @State private var isRunning = true
    @State private var errorMessage: String?
    @State private var inspectedArtifact: PipelineForensics.StageArtifact?
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if isRunning {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Running pipeline compare…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Compare failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if let report {
                    resultsScroll(report)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pipeline Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        shareDiagnostic()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(report == nil || isRunning)
                }
            }
            .sheet(item: $inspectedArtifact) { artifact in
                stageInspector(artifact)
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: shareItems)
            }
        }
        .task { await runCompare() }
    }

    @ViewBuilder
    private func resultsScroll(_ report: PipelineForensics.Report) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard(report.summary)
                writeForensicsCard(productID: product.id)

                Text("Stages")
                    .font(.title3.weight(.semibold))
                ForEach(report.artifacts) { artifact in
                    stageCard(artifact)
                }

                if !report.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                            Text("• \(note)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                }
            }
            .padding()
        }
    }

    private func summaryCard(_ summary: PipelineForensics.CompareSummary) -> some View {
        let healthy = summary.conclusion.hasPrefix("HEALTHY")
        return VStack(alignment: .leading, spacing: 10) {
            Text("Conclusion")
                .font(.headline)
            Text(summary.conclusion)
                .font(.title3.weight(.bold))
                .foregroundStyle(healthy ? Color.primary : Color.orange)
            if !summary.writeForensicsNote.isEmpty {
                Text(summary.writeForensicsNote)
                    .font(.caption)
                    .foregroundStyle(summary.writeForensicsNote.contains("alert") ? Color.orange : Color.secondary)
            }

            Group {
                deltaRow("F vs H subject ΔL", summary.fVsHSubjectDeltaL)
                deltaRow("F vs M subject ΔL", summary.fVsMSubjectDeltaL)
                deltaRow("M vs I subject ΔL", summary.mVsISubjectDeltaL)
                if let rgb = summary.fVsHMeanAbsRGB {
                    deltaRow("F vs H meanAbsRGB", rgb, isDeltaL: false)
                }
                if let rgb = summary.fVsMMeanAbsRGB {
                    deltaRow("F vs M meanAbsRGB", rgb, isDeltaL: false)
                }
                if let rgb = summary.mVsIMeanAbsRGB {
                    deltaRow("M vs I meanAbsRGB", rgb, isDeltaL: false)
                }
                if let rgb = summary.mVsJPEGMeanAbsRGB {
                    deltaRow("M vs JPEG meanAbsRGB", rgb, isDeltaL: false)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func writeForensicsCard(productID: UUID) -> some View {
        let lines = ProcessedWriteForensics.summaryLines(productID: productID)
        let first = ProcessedWriteForensics.firstStrongBoundaryDivergence(productID: productID)
        let events = ProcessedWriteForensics.trace(for: productID).events
        return VStack(alignment: .leading, spacing: 10) {
            Text("Write chain")
                .font(.headline)
            Text("FINAL_RENDER → PRODUCT_ASSIGNMENT → JPEG_INPUT → JPEG_DECODE_IN_MEMORY → DISK_RELOAD")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("Writes this session: \(events.count)")
                .font(.subheadline.weight(.semibold))
            if let first {
                Text("Strong boundary: \(first.from) → \(first.to)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.orange)
            } else if !events.isEmpty {
                Text("No strong write boundary (meanAbsRGB threshold 0.02)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No writes recorded yet for this product in this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(lines.prefix(12).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func deltaRow(_ label: String, _ value: Double?, isDeltaL: Bool = true) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value.map { String(format: isDeltaL ? "%+.4f" : "%.4f", $0) } ?? "n/a")
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(deltaColor(value, isDeltaL: isDeltaL))
        }
    }

    private func deltaColor(_ value: Double?, isDeltaL: Bool) -> Color {
        guard let value else { return .secondary }
        let mag = abs(value)
        let warn = isDeltaL ? 0.03 : 0.02
        if mag >= warn { return .orange }
        return .secondary
    }

    private func stageCard(_ artifact: PipelineForensics.StageArtifact) -> some View {
        Button {
            inspectedArtifact = artifact
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(uiImage: artifact.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(artifact.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(artifact.stats.dimensions)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let L = artifact.stats.meanLuminanceSubject {
                        Text(String(format: "subject L = %.4f", L))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(artifact.stats.note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    private func stageInspector(_ artifact: PipelineForensics.StageArtifact) -> some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: artifact.image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .navigationTitle(artifact.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { inspectedArtifact = nil }
                }
            }
        }
    }

    private func runCompare() async {
        isRunning = true
        errorMessage = nil
        let product = self.product
        let result = await Task.detached(priority: .userInitiated) {
            PipelineForensics.runForProduct(product)
        }.value
        report = result
        isRunning = false
    }

    private func shareDiagnostic() {
        guard let report else { return }
        if let zip = PipelineForensics.makeShareZip(for: report) {
            shareItems = [zip]
            showShareSheet = true
        }
    }
}

extension PipelineForensics.StageArtifact: Hashable {
    static func == (lhs: PipelineForensics.StageArtifact, rhs: PipelineForensics.StageArtifact) -> Bool {
        lhs.key == rhs.key
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}
#endif
