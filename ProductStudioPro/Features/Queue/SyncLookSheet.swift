import SwiftUI

/// Batch Sync Look: preview source before/after, then apply look to other selected items.
struct SyncLookSheet: View {
    @EnvironmentObject private var session: CaptureSessionStore
    @Environment(\.dismiss) private var dismiss

    let source: CapturedProduct
    let targetIDs: Set<UUID>
    var onSync: () -> Void

    @State private var beforeImage: UIImage?
    @State private var isLoadingBefore = true

    private var targetCount: Int {
        targetIDs.subtracting([source.id]).filter { id in
            session.products.contains { $0.id == id && !$0.isCompositeBundle }
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    Text("Copies polish, canvas, fill, background, style, tone, and edge feather from the source onto \(targetCount) other selected photo\(targetCount == 1 ? "" : "s"). Each target is reprocessed from its original.")
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Source · \(source.upc)")
                        .font(DS.TypeScale.bodyEmphasis)
                        .foregroundStyle(DS.ColorToken.label)

                    HStack(spacing: 10) {
                        comparisonTile(title: "Before", image: beforeImage, placeholder: isLoadingBefore)
                        comparisonTile(title: "After", image: source.image, placeholder: false)
                    }

                    DSHelperText("Source is the first selected item in queue order. Per-photo rotation, flips, and custom edge brush strokes are kept on targets.")
                }
                .padding(.horizontal, DS.Space.screenHorizontal)
                .padding(.vertical, 16)
            }
            .background(DS.ColorToken.backgroundSecondary)
            .navigationTitle("Sync Look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sync Look") {
                        onSync()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(targetCount == 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: source.id) {
            await loadBeforeImage()
        }
    }

    private func comparisonTile(title: String, image: UIImage?, placeholder: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DS.TypeScale.micro.weight(.semibold))
                .foregroundStyle(DS.ColorToken.secondaryLabel)
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(DS.ColorToken.backgroundTertiary)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if placeholder {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .stroke(DS.ColorToken.separator, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func loadBeforeImage() async {
        isLoadingBefore = true
        let product = source
        let original = await QueueImageResolver.uncompressedOriginal(for: product) ?? product.originalImage
        let image = await ImageProcessor.comparisonOriginalOnCanvasAsync(
            original,
            canvasWidth: product.canvasWidth,
            canvasHeight: product.canvasHeight,
            rotationDegrees: product.rotationDegrees,
            fillRatio: product.fillRatio,
            flipHorizontal: product.flipHorizontal,
            flipVertical: product.flipVertical,
            alignToCutout: product.backgroundRemoved,
            backgroundFillSpec: product.resolvedBackgroundFillSpec,
            afterImage: product.image
        )
        await MainActor.run {
            beforeImage = image
            isLoadingBefore = false
        }
    }
}
