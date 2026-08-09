import ImageIO
import SwiftUI
import UIKit

// MARK: - Photos-style preview info (ⓘ)

struct PreviewPhotoInfoSheet: View {
    let product: CapturedProduct
    let displayImage: UIImage
    let namingMode: ImageNamingMode
    let queueIndex: Int
    let queueTotal: Int
    let showsLivePreviewDraft: Bool
    let exportJPEGQuality: Double
    /// When set (live draft), Canvas size row reflects the pending panel size instead of the last applied product size.
    var liveCanvasWidth: Int? = nil
    var liveCanvasHeight: Int? = nil

    @State private var copyToastMessage: String?
    @State private var copyToastDismissTask: Task<Void, Never>?

    private var sections: [PreviewPhotoInfoSection] {
        PreviewPhotoMetadataBuilder.sections(
            product: product,
            displayImage: displayImage,
            namingMode: namingMode,
            queueIndex: queueIndex,
            queueTotal: queueTotal,
            showsLivePreviewDraft: showsLivePreviewDraft,
            exportJPEGQuality: exportJPEGQuality,
            liveCanvasWidth: liveCanvasWidth,
            liveCanvasHeight: liveCanvasHeight
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.section) {
                        ForEach(sections) { section in
                            infoSection(section)
                        }
                    }
                    .padding(.horizontal, DS.Space.screenHorizontal)
                    .padding(.vertical, DS.Space.stack)
                    .padding(.bottom, copyToastMessage == nil ? 0 : 52)
                }
                .background(DS.ColorToken.groupedBackground)

                copyToastOverlay
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { copyAllSections() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            copyToastDismissTask?.cancel()
        }
    }

    @ViewBuilder
    private var copyToastOverlay: some View {
        if let copyToastMessage {
            Text(copyToastMessage)
                .font(DS.TypeScale.caption.weight(.semibold))
                .foregroundStyle(DS.ColorToken.label)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: 1))
                .shadow(color: DS.Shadow.card.color, radius: 8, y: 3)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func infoSection(_ section: PreviewPhotoInfoSection) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(DS.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .textCase(.uppercase)
                Spacer(minLength: 8)
                Button("Copy") {
                    copySection(section)
                }
                .font(DS.TypeScale.micro.weight(.semibold))
                .foregroundStyle(DS.ColorToken.accent)
                .buttonStyle(.plainPressable)
                .accessibilityLabel("Copy \(section.title) section")
            }

            DSCard(padding: DS.Space.cardPadding) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().padding(.vertical, 6)
                        }
                        infoRow(row)
                    }
                }
            }
        }
    }

    private func infoRow(_ row: PreviewPhotoInfoRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(row.title)
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.secondaryLabel)
                .frame(width: 118, alignment: .leading)
            Text(row.value)
                .font(DS.TypeScale.caption.weight(.medium))
                .foregroundStyle(DS.ColorToken.label)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyAllSections() {
        copyToClipboard(
            PreviewPhotoMetadataBuilder.clipboardText(sections: sections),
            toastMessage: "All info copied"
        )
    }

    private func copySection(_ section: PreviewPhotoInfoSection) {
        copyToClipboard(
            section.clipboardText(),
            toastMessage: "\(section.title) copied"
        )
    }

    private func copyToClipboard(_ text: String, toastMessage: String) {
        UIPasteboard.general.string = text
        InteractionHaptics.tap()
        presentCopyToast(toastMessage)
    }

    private func presentCopyToast(_ message: String) {
        copyToastDismissTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            copyToastMessage = message
        }
        copyToastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.22)) {
                    copyToastMessage = nil
                }
            }
        }
    }
}

struct PreviewPhotoInfoRow: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

struct PreviewPhotoInfoSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [PreviewPhotoInfoRow]

    func clipboardText() -> String {
        var lines = [title]
        for row in rows {
            lines.append("\(row.title): \(row.value)")
        }
        return lines.joined(separator: "\n")
    }
}

enum PreviewPhotoMetadataBuilder {
    static func clipboardText(sections: [PreviewPhotoInfoSection]) -> String {
        sections.map { $0.clipboardText() }.joined(separator: "\n\n")
    }

    private static let capturedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    static func sections(
        product: CapturedProduct,
        displayImage: UIImage,
        namingMode: ImageNamingMode,
        queueIndex: Int,
        queueTotal: Int,
        showsLivePreviewDraft: Bool,
        exportJPEGQuality: Double,
        liveCanvasWidth: Int? = nil,
        liveCanvasHeight: Int? = nil
    ) -> [PreviewPhotoInfoSection] {
        var result: [PreviewPhotoInfoSection] = []

        result.append(
            PreviewPhotoInfoSection(title: "Photo", rows: [
                .init(title: "Filename", value: product.filename(for: namingMode)),
                .init(title: "Queue position", value: "\(queueIndex + 1) of \(max(1, queueTotal))"),
                .init(title: "Sequence", value: "#\(product.sequence)"),
                .init(title: "Identifier", value: product.upc.isEmpty ? "—" : product.upc),
                .init(title: "Angle", value: product.angle.rawValue),
                .init(title: "Duplicate copy", value: product.duplicateCopyIndex > 1 ? "\(product.duplicateCopyIndex)" : "Primary"),
                .init(title: "Captured", value: capturedFormatter.string(from: product.capturedAt)),
                .init(title: "Photo ID", value: product.id.uuidString),
            ])
        )

        if showsLivePreviewDraft {
            result.append(
                PreviewPhotoInfoSection(title: "Preview state", rows: [
                    .init(title: "On screen", value: "Live preview (unsaved edits)"),
                    .init(title: "Queue file", value: "Last applied version until you tap Apply"),
                ])
            )
        }

        result.append(imageSection(title: "Display image", image: displayImage, exportQuality: exportJPEGQuality))

        if !imagesMatchPixels(displayImage, product.image) {
            result.append(imageSection(title: "Queue image", image: product.image, exportQuality: exportJPEGQuality))
        }

        if !product.isOriginalEvicted,
           !imagesMatchPixels(product.uncompressedOriginalImage, displayImage)
            && !imagesMatchPixels(product.uncompressedOriginalImage, product.image),
           let source = QueueImageResolver.uncompressedOriginal(for: product) {
            result.append(imageSection(title: "Source original", image: source, exportQuality: 1.0))
        } else if product.isOriginalEvicted,
                  let source = QueueImageResolver.uncompressedOriginal(for: product),
                  !imagesMatchPixels(source, displayImage),
                  !imagesMatchPixels(source, product.image) {
            result.append(imageSection(title: "Source original", image: source, exportQuality: 1.0))
        }

        if let disk = diskFileSection(productID: product.id) {
            result.append(disk)
        }

        let fill = product.resolvedBackgroundFillSpec
        var processingRows: [PreviewPhotoInfoRow] = [
            .init(title: "AI Polish", value: product.polishEnabled ? "Enhanced" : "Off"),
            .init(title: "Background removed", value: product.backgroundRemoved ? "Yes" : "No"),
            .init(title: "Style filter", value: product.photoFilter == .none ? "None" : product.photoFilter.rawValue),
            .init(title: "Filter intensity", value: product.photoFilter == .none ? "—" : "\(Int(product.photoFilterIntensity * 100))%"),
            .init(title: "Auto enhance", value: product.adjustAutoEnhance ? "On" : "Off"),
        ]
        if product.upscaled {
            processingRows.insert(
                .init(title: "Legacy upscale", value: "Applied (descale from More menu)"),
                at: 3
            )
        }
        result.append(PreviewPhotoInfoSection(title: "Processing", rows: processingRows))

        let canvasW = liveCanvasWidth ?? product.canvasWidth
        let canvasH = liveCanvasHeight ?? product.canvasHeight
        let canvasLabel: String = {
            if showsLivePreviewDraft,
               let liveW = liveCanvasWidth,
               let liveH = liveCanvasHeight,
               liveW != product.canvasWidth || liveH != product.canvasHeight {
                return "\(liveW) × \(liveH) px (live preview)"
            }
            return "\(canvasW) × \(canvasH) px"
        }()
        result.append(
            PreviewPhotoInfoSection(title: "Canvas & layout", rows: [
                .init(title: "Canvas size", value: canvasLabel),
                .init(title: "Object fill", value: "\(Int(product.fillRatio * 100))%"),
                .init(title: "Rotation", value: "\(Int(product.rotationDegrees))°"),
                .init(title: "Flip", value: flipSummary(horizontal: product.flipHorizontal, vertical: product.flipVertical)),
                .init(title: "Background fill", value: backgroundFillLabel(fill.fillKind)),
                .init(title: "Background style", value: product.backgroundStyle.rawValue),
                .init(title: "Primary color", value: product.backgroundColor.hexString),
                .init(title: "Secondary color", value: product.secondaryBackgroundColor.hexString),
            ] + gradientDetailRows(fill: fill))
        )

        if product.upscaled,
           product.preUpscaleCanvasWidth != nil || product.preUpscaleEnhancementMode != nil {
            result.append(
                PreviewPhotoInfoSection(title: "Before legacy upscale", rows: [
                    .init(title: "Canvas", value: preUpscaleCanvas(product)),
                    .init(title: "Quality", value: preUpscaleQuality(product)),
                ])
            )
        }

        return result
    }

    private static func imageSection(title: String, image: UIImage, exportQuality: Double) -> PreviewPhotoInfoSection {
        PreviewPhotoInfoSection(title: title, rows: pixelRows(for: image, exportQuality: exportQuality))
    }

    private static func pixelRows(for image: UIImage, exportQuality: Double) -> [PreviewPhotoInfoRow] {
        let cg = image.cgImage
        let w = cg?.width ?? Int(image.size.width * image.scale)
        let h = cg?.height ?? Int(image.size.height * image.scale)
        let mp = Double(w * h) / 1_000_000.0
        let orient = orientationLabel(image.imageOrientation)
        let colorSpace = (cg?.colorSpace?.name as String?) ?? "—"
        let hasAlpha = cg.map { $0.alphaInfo != .none && $0.alphaInfo != .noneSkipFirst && $0.alphaInfo != .noneSkipLast } ?? false
        let estBytes = estimatedJPEGBytes(image: image, quality: exportQuality)

        return [
            .init(title: "Dimensions", value: "\(w) × \(h) px"),
            .init(title: "Megapixels", value: String(format: "%.2f MP", mp)),
            .init(title: "Point size", value: String(format: "%.0f × %.0f pt @%.0fx", image.size.width, image.size.height, image.scale)),
            .init(title: "Orientation", value: orient),
            .init(title: "Color space", value: colorSpace),
            .init(title: "Alpha channel", value: hasAlpha ? "Yes" : "No"),
            .init(title: "Est. JPEG size", value: estBytes),
        ]
    }

    private static func diskFileSection(productID: UUID) -> PreviewPhotoInfoSection? {
        var rows: [PreviewPhotoInfoRow] = []
        if let orig = SessionDiskStore.originalImageFileURL(for: productID),
           let attrs = try? FileManager.default.attributesOfItem(atPath: orig.path),
           let size = attrs[.size] as? Int64 {
            rows.append(.init(title: "Original file", value: orig.lastPathComponent))
            rows.append(.init(title: "Original bytes", value: byteCount(size)))
            rows.append(contentsOf: imageIOPropertyRows(url: orig, prefix: "Original"))
        }
        if let proc = SessionDiskStore.processedImageFileURL(for: productID),
           let attrs = try? FileManager.default.attributesOfItem(atPath: proc.path),
           let size = attrs[.size] as? Int64 {
            rows.append(.init(title: "Processed file", value: proc.lastPathComponent))
            rows.append(.init(title: "Processed bytes", value: byteCount(size)))
            rows.append(contentsOf: imageIOPropertyRows(url: proc, prefix: "Processed"))
        }
        guard !rows.isEmpty else { return nil }
        return PreviewPhotoInfoSection(title: "On-device files", rows: rows)
    }

    private static func imageIOPropertyRows(url: URL, prefix: String) -> [PreviewPhotoInfoRow] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return []
        }
        var rows: [PreviewPhotoInfoRow] = []
        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            rows.append(.init(title: "\(prefix) pixels", value: "\(w) × \(h)"))
        }
        if let dpiW = props[kCGImagePropertyDPIWidth] as? Double, dpiW > 0 {
            let dpiH = (props[kCGImagePropertyDPIHeight] as? Double) ?? dpiW
            rows.append(.init(title: "\(prefix) DPI", value: String(format: "%.0f × %.0f", dpiW, dpiH)))
        }
        if let depth = props[kCGImagePropertyDepth] as? Int {
            rows.append(.init(title: "\(prefix) bit depth", value: "\(depth)"))
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if let make = tiff[kCGImagePropertyTIFFMake] as? String, !make.isEmpty {
                rows.append(.init(title: "Camera make", value: make))
            }
            if let model = tiff[kCGImagePropertyTIFFModel] as? String, !model.isEmpty {
                rows.append(.init(title: "Camera model", value: model))
            }
            if let software = tiff[kCGImagePropertyTIFFSoftware] as? String, !software.isEmpty {
                rows.append(.init(title: "Software", value: software))
            }
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let lens = exif[kCGImagePropertyExifLensModel] as? String, !lens.isEmpty {
                rows.append(.init(title: "Lens", value: lens))
            }
            if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
                rows.append(.init(title: "Focal length", value: String(format: "%.1f mm", focal)))
            }
            if let fnum = exif[kCGImagePropertyExifFNumber] as? Double {
                rows.append(.init(title: "Aperture", value: String(format: "f/%.1f", fnum)))
            }
            if let isoNum = exif[kCGImagePropertyExifISOSpeedRatings] as? NSNumber {
                rows.append(.init(title: "ISO", value: "\(isoNum.intValue)"))
            } else if let isoArr = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoArr.first {
                rows.append(.init(title: "ISO", value: "\(iso)"))
            }
            if let exp = exif[kCGImagePropertyExifExposureTime] as? Double {
                rows.append(.init(title: "Exposure", value: exposureLabel(exp)))
            }
            if let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String, !date.isEmpty {
                rows.append(.init(title: "Taken (EXIF)", value: date))
            }
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any], !gps.isEmpty {
            rows.append(.init(title: "GPS", value: "Present in file"))
        }
        return rows
    }

    private static func backgroundFillLabel(_ kind: BackgroundFillKind) -> String {
        switch kind {
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        case .image: return "Image"
        }
    }

    private static func gradientDetailRows(fill: BackgroundFillSpec) -> [PreviewPhotoInfoRow] {
        if fill.fillKind == .image, let selection = fill.imageSelection {
            let title = ImageBackgroundFolderCatalog.definition(id: selection.backgroundID)?.title ?? selection.backgroundID
            return [
                .init(title: "Image background", value: title),
                .init(title: "Shadow", value: selection.shadow.rawValue),
                .init(title: "Scale", value: String(format: "%.0f%%", selection.placement.scaleMultiplier * 100)),
            ]
        }
        guard fill.fillKind == .gradient else { return [] }
        return [
            .init(title: "Gradient type", value: fill.gradientType.rawValue),
            .init(title: "Direction", value: fill.gradientDirection.rawValue),
            .init(title: "Angle", value: "\(Int(fill.gradientAngleDegrees))°"),
            .init(title: "Color stops", value: "\(fill.gradientStops.count)"),
        ]
    }

    private static func flipSummary(horizontal: Bool, vertical: Bool) -> String {
        switch (horizontal, vertical) {
        case (false, false): return "None"
        case (true, false): return "Horizontal"
        case (false, true): return "Vertical"
        case (true, true): return "Horizontal + vertical"
        }
    }

    private static func preUpscaleCanvas(_ product: CapturedProduct) -> String {
        guard let w = product.preUpscaleCanvasWidth, let h = product.preUpscaleCanvasHeight else { return "—" }
        return "\(w) × \(h) px"
    }

    private static func preUpscaleQuality(_ product: CapturedProduct) -> String {
        guard product.preUpscaleEnhancementMode != nil else { return "—" }
        return PhotoEnhancementMode.standardClean.rawValue
    }

    private static func imagesMatchPixels(_ a: UIImage, _ b: UIImage) -> Bool {
        guard let ac = a.cgImage, let bc = b.cgImage else { return false }
        return ac.width == bc.width && ac.height == bc.height
    }

    private static func orientationLabel(_ o: UIImage.Orientation) -> String {
        switch o {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .upMirrored: return "Up (mirrored)"
        case .downMirrored: return "Down (mirrored)"
        case .leftMirrored: return "Left (mirrored)"
        case .rightMirrored: return "Right (mirrored)"
        @unknown default: return "Unknown"
        }
    }

    private static func exposureLabel(_ seconds: Double) -> String {
        if seconds >= 1 { return String(format: "%.1f s", seconds) }
        if seconds > 0 { return String(format: "1/%.0f s", 1.0 / seconds) }
        return "—"
    }

    private static func estimatedJPEGBytes(image: UIImage, quality: Double) -> String {
        let q = min(1, max(0.5, quality))
        guard let data = image.jpegDataForOpaqueExport(compressionQuality: q) else { return "—" }
        return byteCount(Int64(data.count))
    }

    private static func byteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
