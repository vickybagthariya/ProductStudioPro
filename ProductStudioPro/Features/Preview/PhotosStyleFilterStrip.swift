import SwiftUI
import UIKit

/// Horizontal Photos-style style picker with live thumbnails of the current image.
struct PhotosStyleFilterStrip: View {
    let productID: UUID
    /// Filter-neutral composite (never the tuned canvas preview).
    let neutralSourceImage: UIImage?
    var adjustAutoEnhance: Bool = false
    @Binding var selectedFilter: ExportPhotoFilter
    var onSelect: () -> Void

    @State private var proxyBase: UIImage?
    @State private var proxyPrepareToken = UUID()
    @State private var proxyPrepareTask: Task<Void, Never>?
    @State private var showExtendedFilters = false

    private let thumbImageSize = CGSize(width: 72, height: 72)
    private let thumbCellWidth: CGFloat = 76

    private var visibleStripFilters: [ExportPhotoFilter] {
        showExtendedFilters ? StylePreviewStripConfig.allStripFilters : StylePreviewStripConfig.coreFilters
    }

    private var cacheKey: String {
        StylePreviewCacheRevisionStore.shared.cacheKey(for: productID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.stack) {
            HStack {
                Text("Filters")
                    .font(DS.TypeScale.dockSection)
                    .foregroundStyle(DS.ColorToken.label)
                Spacer(minLength: 0)
                if !StylePreviewStripConfig.extendedFilters.isEmpty {
                    Button(showExtendedFilters ? "Less" : "More looks") {
                        showExtendedFilters.toggle()
                    }
                    .font(DS.TypeScale.micro.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.accent)
                    .buttonStyle(.plainPressable)
                }
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Space.stack) {
                    ForEach(visibleStripFilters) { filter in
                        if let proxyBase {
                            StyleStripThumbnailCell(
                                filter: filter,
                                productID: productID,
                                cacheKey: cacheKey,
                                proxyBase: proxyBase,
                                proxyGeneration: neutralSourceToken,
                                thumbImageSize: thumbImageSize,
                                thumbCellWidth: thumbCellWidth,
                                isSelected: selectedFilter == filter,
                                onSelect: {
                                    guard selectedFilter != filter else { return }
                                    selectedFilter = filter
                                    onSelect()
                                }
                            )
                        } else {
                            stylePlaceholderCell(filter: filter)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
        .onAppear { scheduleProxyPrepare() }
        .onChange(of: neutralSourceToken) { _, _ in scheduleProxyPrepare(debounced: true) }
        .onChange(of: adjustAutoEnhance) { _, _ in scheduleProxyPrepare(debounced: true) }
        .onDisappear {
            proxyPrepareTask?.cancel()
            proxyPrepareTask = nil
            proxyBase = nil
        }
    }

    /// Changes when the neutral bitmap or cache revision changes.
    private var neutralSourceToken: String {
        guard let neutralSourceImage, let cg = neutralSourceImage.cgImage else { return "nil" }
        let rev = StylePreviewCacheRevisionStore.shared.revision(for: productID)
        return "\(productID.uuidString)-r\(rev)-ae\(adjustAutoEnhance)-\(cg.width)x\(cg.height)-\(cg.bytesPerRow)"
    }

    private func stylePlaceholderCell(filter: ExportPhotoFilter) -> some View {
        let selected = selectedFilter == filter
        return Button {
            guard selectedFilter != filter else { return }
            selectedFilter = filter
            onSelect()
        } label: {
            VStack(spacing: 5) {
                DSStyleThumbnailPlaceholder(size: thumbImageSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                            .strokeBorder(
                                selected ? DS.ColorToken.accent : DS.ColorToken.separator,
                                lineWidth: selected ? 2.5 : 1
                            )
                    )
                Text(filter.rawValue)
                    .font(DS.TypeScale.micro.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? DS.ColorToken.label : DS.ColorToken.secondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: thumbCellWidth)
        }
        .buttonStyle(.plainPressable)
    }

    private func scheduleProxyPrepare(debounced: Bool = false) {
        proxyPrepareTask?.cancel()
        let token = UUID()
        proxyPrepareToken = token

        guard let neutral = neutralSourceImage,
              neutral.cgImage != nil,
              neutral.size.width > 1,
              neutral.size.height > 1
        else {
            proxyBase = nil
            return
        }

        proxyPrepareTask = Task(priority: .utility) {
            if debounced {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled else { return }
            }

            let enhanced = ImageProcessor.applyExportTuning(
                to: neutral,
                photoFilter: .none,
                photoFilterIntensity: 1,
                adjustAutoEnhance: adjustAutoEnhance,
                applyBrandMark: false
            )
            guard let proxy = await StylePreviewThumbnailRenderer.shared.prepareThumbnailBase(from: enhanced) else {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard proxyPrepareToken == token else { return }
                proxyBase = proxy
            }
        }
    }
}

// MARK: - Per-cell lazy thumbnail

private struct StyleStripThumbnailCell: View {
    let filter: ExportPhotoFilter
    let productID: UUID
    let cacheKey: String
    let proxyBase: UIImage
    let proxyGeneration: String
    let thumbImageSize: CGSize
    let thumbCellWidth: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var thumbnail: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadToken = UUID()

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        DSStyleThumbnailPlaceholder(size: thumbImageSize)
                    }
                }
                .frame(width: thumbImageSize.width, height: thumbImageSize.height)
                .clipped()
                .background(DS.ColorToken.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                        .strokeBorder(
                            isSelected ? DS.ColorToken.accent : DS.ColorToken.separator,
                            lineWidth: isSelected ? 2.5 : 1
                        )
                )

                Text(filter.rawValue)
                    .font(DS.TypeScale.micro.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? DS.ColorToken.label : DS.ColorToken.secondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: thumbCellWidth)
        }
        .buttonStyle(.plainPressable)
        .onAppear { beginThumbnailLoad() }
        .onChange(of: proxyGeneration) { _, _ in
            thumbnail = nil
            beginThumbnailLoad()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func beginThumbnailLoad() {
        if let hit = StylePreviewThumbnailCache.shared.image(cacheKey: cacheKey, filter: filter) {
            thumbnail = hit
            return
        }

        loadTask?.cancel()
        let token = UUID()
        loadToken = token
        let pid = productID
        let key = cacheKey
        let base = proxyBase
        let filt = filter

        loadTask = Task(priority: .utility) {
            let img = await StylePreviewThumbnailRenderer.shared.thumbnail(
                for: filt,
                proxyBase: base,
                productID: pid,
                cacheKey: key
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard loadToken == token else { return }
                thumbnail = img
            }
        }
    }
}
