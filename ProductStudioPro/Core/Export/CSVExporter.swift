import Foundation
import UIKit

/// Configurable CSV columns for export packages and legacy manifest exports.
enum CSVExportColumn: String, CaseIterable, Codable, Identifiable {
    // Legacy manifest columns (preserved for downstream ERP/catalog workflows)
    case sequence
    case identifier
    case filename
    case namePrefix = "name_prefix"
    case imageExt = "image_ext"
    case upc
    case angle
    case capturedAt = "captured_at"
    case backgroundRemoved = "background_removed"
    case enhancementMode = "enhancement_mode"
    case studioAIStrength = "studio_ai_strength"
    case canvasWidth = "canvas_width"
    case canvasHeight = "canvas_height"
    case fillRatio = "fill_ratio"
    case backgroundStyle = "background_style"
    case fileSize = "file_size"
    case fileSizeSuffix = "file_size_suffix"

    // Extended seller deliverable columns
    case sku
    case productName = "product_name"
    case brand
    case category
    case marketplace
    case width
    case height
    case backgroundType = "background_type"
    case enhancementApplied = "enhancement_applied"
    case shadowApplied = "shadow_applied"
    case exportDate = "export_date"
    case fileFormat = "file_format"
    case resolution

    var id: String { rawValue }

    var headerTitle: String {
        switch self {
        case .sequence: return "sequence"
        case .identifier: return "identifier"
        case .filename: return "filename"
        case .namePrefix: return "name_prefix"
        case .imageExt: return "image_ext"
        case .upc: return "upc"
        case .angle: return "angle"
        case .capturedAt: return "captured_at"
        case .backgroundRemoved: return "background_removed"
        case .enhancementMode: return "enhancement_mode"
        case .studioAIStrength: return "studio_ai_strength"
        case .canvasWidth: return "canvas_width"
        case .canvasHeight: return "canvas_height"
        case .fillRatio: return "fill_ratio"
        case .backgroundStyle: return "background_style"
        case .fileSize: return "file_size"
        case .fileSizeSuffix: return "file_size_suffix"
        case .sku: return "SKU"
        case .productName: return "Product Name"
        case .brand: return "Brand"
        case .category: return "Category"
        case .marketplace: return "Marketplace"
        case .width: return "Width"
        case .height: return "Height"
        case .backgroundType: return "Background Type"
        case .enhancementApplied: return "Enhancement Applied"
        case .shadowApplied: return "Shadow Applied"
        case .exportDate: return "Export Date"
        case .fileFormat: return "File Format"
        case .resolution: return "Resolution"
        }
    }

    /// Default column order: legacy columns first, then extended seller columns.
    static let packageDefault: [CSVExportColumn] = {
        let legacy: [CSVExportColumn] = [
            .sequence, .identifier, .filename, .namePrefix, .imageExt, .upc, .angle, .capturedAt,
            .backgroundRemoved, .enhancementMode, .studioAIStrength, .canvasWidth, .canvasHeight,
            .fillRatio, .backgroundStyle, .fileSize, .fileSizeSuffix,
        ]
        let extended: [CSVExportColumn] = [
            .sku, .productName, .brand, .category, .marketplace, .width, .height, .backgroundType,
            .enhancementApplied, .shadowApplied, .exportDate, .fileFormat, .resolution,
        ]
        return legacy + extended
    }()
}

struct CSVExportRowContext {
    let product: CapturedProduct
    let namingMode: ImageNamingMode
    let format: ExportImageFormat
    let archivePath: String
    let byteCount: Int
    let exportWidth: Int
    let exportHeight: Int
    let marketplaceProfile: MarketplaceExportProfileID
    let brandName: String
    let exportDate: Date
    /// When present, metadata drives CSV column values (source of truth).
    var productMetadata: ProductMetadata?
    var imageMetadata: ImageMetadata?
}

enum CSVExporter {
    static let packageFilename = "products.csv"
    static let legacyManifestFilename = ExportManager.manifestCSVFilename

    static func csvData(
        rows: [CSVExportRowContext],
        columns: [CSVExportColumn] = CSVExportColumn.packageDefault
    ) -> Data? {
        guard !columns.isEmpty else { return nil }
        let dateFormatter = ISO8601DateFormatter()
        let exportDateFormatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append(columns.map(\.headerTitle).joined(separator: ","))

        for row in rows {
            let values = metadataCSVValues(for: row, dateFormatter: dateFormatter, exportDateFormatter: exportDateFormatter)
                ?? legacyCSVValues(for: row, dateFormatter: dateFormatter, exportDateFormatter: exportDateFormatter)

            let cols = columns.map { column in
                let raw = values[column.rawValue] ?? ""
                let forceText = column == .upc || column == .sku
                return ExportManager.csvField(raw, asText: forceText)
            }
            lines.append(cols.joined(separator: ","))
        }

        let body = lines.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(body.utf8)
    }

    static func writeCSV(
        rows: [CSVExportRowContext],
        to folder: URL,
        filename: String = packageFilename,
        columns: [CSVExportColumn] = CSVExportColumn.packageDefault
    ) -> URL? {
        guard let data = csvData(rows: rows, columns: columns) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// Maps CSV columns from the metadata model when row context includes metadata snapshots.
    static func metadataCSVValues(
        for row: CSVExportRowContext,
        dateFormatter: ISO8601DateFormatter,
        exportDateFormatter: ISO8601DateFormatter
    ) -> [String: String]? {
        guard let productMeta = row.productMetadata,
              let imageMeta = row.imageMetadata else { return nil }

        let filename = (row.archivePath as NSString).lastPathComponent
        let prefix = String(filename.dropLast(row.format.fileExtension.count + 1))
        let scaledSize = ExportManager.scaledFileSize(fromBytes: row.byteCount)
        let resolution = "\(row.exportWidth)x\(row.exportHeight)"

        return [
            CSVExportColumn.sequence.rawValue: String(imageMeta.sequence),
            CSVExportColumn.identifier.rawValue: prefix,
            CSVExportColumn.filename.rawValue: filename,
            CSVExportColumn.namePrefix.rawValue: prefix,
            CSVExportColumn.imageExt.rawValue: row.format.fileExtension,
            CSVExportColumn.upc.rawValue: productMeta.barcode.isEmpty ? productMeta.sku : productMeta.barcode,
            CSVExportColumn.angle.rawValue: imageMeta.angle,
            CSVExportColumn.capturedAt.rawValue: dateFormatter.string(from: imageMeta.capturedAt),
            CSVExportColumn.backgroundRemoved.rawValue: imageMeta.backgroundRemoved ? "true" : "false",
            CSVExportColumn.enhancementMode.rawValue: imageMeta.enhancementMode,
            CSVExportColumn.studioAIStrength.rawValue: imageMeta.studioAIStrength,
            CSVExportColumn.canvasWidth.rawValue: String(imageMeta.canvasWidth),
            CSVExportColumn.canvasHeight.rawValue: String(imageMeta.canvasHeight),
            CSVExportColumn.fillRatio.rawValue: String(format: "%.2f", imageMeta.fillRatio),
            CSVExportColumn.backgroundStyle.rawValue: imageMeta.backgroundStyle,
            CSVExportColumn.fileSize.rawValue: scaledSize.value,
            CSVExportColumn.fileSizeSuffix.rawValue: scaledSize.suffix,
            CSVExportColumn.sku.rawValue: productMeta.sku,
            CSVExportColumn.productName.rawValue: productMeta.productName,
            CSVExportColumn.brand.rawValue: productMeta.brand.isEmpty ? row.brandName : productMeta.brand,
            CSVExportColumn.category.rawValue: productMeta.category,
            CSVExportColumn.marketplace.rawValue: productMeta.marketplace.isEmpty
                ? row.marketplaceProfile.displayName
                : productMeta.marketplace,
            CSVExportColumn.width.rawValue: String(row.exportWidth),
            CSVExportColumn.height.rawValue: String(row.exportHeight),
            CSVExportColumn.backgroundType.rawValue: imageMeta.backgroundType,
            CSVExportColumn.enhancementApplied.rawValue: imageMeta.enhancementApplied,
            CSVExportColumn.shadowApplied.rawValue: imageMeta.shadowApplied ? "true" : "false",
            CSVExportColumn.exportDate.rawValue: exportDateFormatter.string(from: row.exportDate),
            CSVExportColumn.fileFormat.rawValue: row.format.fileExtension.uppercased(),
            CSVExportColumn.resolution.rawValue: resolution,
        ]
    }

    private static func legacyCSVValues(
        for row: CSVExportRowContext,
        dateFormatter: ISO8601DateFormatter,
        exportDateFormatter: ISO8601DateFormatter
    ) -> [String: String] {
        let product = row.product
        let filename = (row.archivePath as NSString).lastPathComponent
        let prefix = product.identifierPrefix(for: row.namingMode, format: row.format)
        let scaledSize = ExportManager.scaledFileSize(fromBytes: row.byteCount)
        let backgroundType = backgroundTypeLabel(for: product)
        let enhancementApplied = enhancementSummary(for: product)
        let resolution = "\(row.exportWidth)x\(row.exportHeight)"

        return [
            CSVExportColumn.sequence.rawValue: String(product.sequence),
            CSVExportColumn.identifier.rawValue: prefix,
            CSVExportColumn.filename.rawValue: filename,
            CSVExportColumn.namePrefix.rawValue: prefix,
            CSVExportColumn.imageExt.rawValue: row.format.fileExtension,
            CSVExportColumn.upc.rawValue: product.upc,
            CSVExportColumn.angle.rawValue: product.angle.rawValue,
            CSVExportColumn.capturedAt.rawValue: dateFormatter.string(from: product.capturedAt),
            CSVExportColumn.backgroundRemoved.rawValue: product.backgroundRemoved ? "true" : "false",
            CSVExportColumn.enhancementMode.rawValue: product.enhancementMode.rawValue,
            CSVExportColumn.studioAIStrength.rawValue: product.studioAIStrength.rawValue,
            CSVExportColumn.canvasWidth.rawValue: String(product.canvasWidth),
            CSVExportColumn.canvasHeight.rawValue: String(product.canvasHeight),
            CSVExportColumn.fillRatio.rawValue: String(format: "%.2f", product.fillRatio),
            CSVExportColumn.backgroundStyle.rawValue: product.backgroundStyle.rawValue,
            CSVExportColumn.fileSize.rawValue: scaledSize.value,
            CSVExportColumn.fileSizeSuffix.rawValue: scaledSize.suffix,
            CSVExportColumn.sku.rawValue: product.upc,
            CSVExportColumn.productName.rawValue: FileNameRules.baseName(for: product, namingMode: row.namingMode),
            CSVExportColumn.brand.rawValue: row.brandName,
            CSVExportColumn.category.rawValue: "",
            CSVExportColumn.marketplace.rawValue: row.marketplaceProfile.displayName,
            CSVExportColumn.width.rawValue: String(row.exportWidth),
            CSVExportColumn.height.rawValue: String(row.exportHeight),
            CSVExportColumn.backgroundType.rawValue: backgroundType,
            CSVExportColumn.enhancementApplied.rawValue: enhancementApplied,
            CSVExportColumn.shadowApplied.rawValue: product.studioShadow.isEnabled ? "true" : "false",
            CSVExportColumn.exportDate.rawValue: exportDateFormatter.string(from: row.exportDate),
            CSVExportColumn.fileFormat.rawValue: row.format.fileExtension.uppercased(),
            CSVExportColumn.resolution.rawValue: resolution,
        ]
    }

    /// Attaches metadata snapshots for CSV export.
    static func rowContext(
        _ base: CSVExportRowContext,
        snapshot: MetadataExportSnapshot
    ) -> CSVExportRowContext {
        snapshot.enrich(base)
    }

    /// Attaches metadata snapshots from a manager for CSV export (main actor only).
    @MainActor
    static func rowContext(
        _ base: CSVExportRowContext,
        metadataManager: MetadataManager
    ) -> CSVExportRowContext {
        rowContext(base, snapshot: metadataManager.exportSnapshot())
    }

    private static func backgroundTypeLabel(for product: CapturedProduct) -> String {
        let spec = product.resolvedBackgroundFillSpec
        switch spec.fillKind {
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        case .image: return "Image"
        }
    }

    private static func enhancementSummary(for product: CapturedProduct) -> String {
        var parts: [String] = []
        if product.polishEnabled { parts.append("AI Polish") }
        parts.append(product.enhancementMode.rawValue)
        if product.studioAIStrength != .natural {
            parts.append(product.studioAIStrength.rawValue)
        }
        return parts.joined(separator: ", ")
    }
}
