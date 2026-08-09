import Foundation
import UIKit

struct ExportPackageContext {
    let projectName: String
    let marketplaceProfile: MarketplaceExportProfileID
    let brandName: String
    let namingMode: ImageNamingMode
    let jpegQuality: Double
    var imageProvider: ((CapturedProduct) -> UIImage)? = nil
    var csvColumns: [CSVExportColumn] = CSVExportColumn.packageDefault
    var metadataSnapshot: MetadataExportSnapshot? = nil
}

struct ExportPackageImageResult {
    let archivePath: String
    let data: Data
    let exportWidth: Int
    let exportHeight: Int
    let rowContext: CSVExportRowContext
}

/// Assembles marketplace-ready ZIP packages: `Images/`, `products.csv`, and `manifest.json`.
enum ExportPackageEngine {
    static func exportPackageURL(
        products: [CapturedProduct],
        context: ExportPackageContext
    ) -> URL? {
        guard !products.isEmpty else { return nil }

        let profile = MarketplaceExportProfile.profile(for: context.marketplaceProfile)
        let exportDate = Date()
        let quality = max(profile.minimumJPEGQuality, min(1.0, context.jpegQuality))

        var zipEntries: [ZipExporter.Entry] = []
        var csvRows: [CSVExportRowContext] = []

        for product in products {
            guard let packaged = packageImage(
                for: product,
                profile: profile,
                context: context,
                quality: quality,
                exportDate: exportDate
            ) else { continue }

            zipEntries.append(.init(archivePath: packaged.archivePath, data: packaged.data))
            csvRows.append(packaged.rowContext)
        }

        guard !zipEntries.isEmpty else { return nil }

        if let csvData = CSVExporter.csvData(rows: csvRows, columns: context.csvColumns) {
            zipEntries.append(.init(archivePath: CSVExporter.packageFilename, data: csvData))
        }

        let manifest = ManifestGenerator.generate(
            projectName: context.projectName,
            profile: profile,
            products: products,
            exportDate: exportDate
        )
        if let manifestData = ManifestGenerator.jsonData(for: manifest) {
            zipEntries.append(.init(archivePath: ZipExporter.manifestFilename, data: manifestData))
        }

        let zipName = ZipExporter.legacyExportZipFilename(productCount: products.count)
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipName)
        guard ZipExporter.makePackageZip(entries: zipEntries, zipDestination: zipURL) else { return nil }
        return zipURL
    }

    private static func packageImage(
        for product: CapturedProduct,
        profile: MarketplaceExportProfile,
        context: ExportPackageContext,
        quality: Double,
        exportDate: Date
    ) -> ExportPackageImageResult? {
        let source = context.imageProvider?(product) ?? QueueImageResolver.processedDisplay(for: product)
        guard ImageProcessor.isValidExportBitmap(source) else { return nil }
        let optimized = optimizedImage(source, profile: profile)
        guard let data = imageData(for: optimized, format: profile.format, quality: quality) else { return nil }

        let filename = product.filename(for: context.namingMode, format: profile.format)
        let archivePath = "\(ZipExporter.imagesFolderName)/\(filename)"
        let width = max(1, Int(round(optimized.size.width * optimized.scale)))
        let height = max(1, Int(round(optimized.size.height * optimized.scale)))

        let row = CSVExportRowContext(
            product: product,
            namingMode: context.namingMode,
            format: profile.format,
            archivePath: archivePath,
            byteCount: data.count,
            exportWidth: width,
            exportHeight: height,
            marketplaceProfile: profile.id,
            brandName: context.brandName,
            exportDate: exportDate
        )
        let enrichedRow = context.metadataSnapshot.map {
            CSVExporter.rowContext(row, snapshot: $0)
        } ?? row

        return ExportPackageImageResult(
            archivePath: archivePath,
            data: data,
            exportWidth: width,
            exportHeight: height,
            rowContext: enrichedRow
        )
    }

    private static func optimizedImage(_ image: UIImage, profile: MarketplaceExportProfile) -> UIImage {
        guard profile.resizesImages,
              let width = profile.targetCanvasWidth,
              let height = profile.targetCanvasHeight else {
            return image
        }
        return resize(image, canvasWidth: width, canvasHeight: height)
    }

    private static func resize(_ image: UIImage, canvasWidth: Int, canvasHeight: Int) -> UIImage {
        let target = CGSize(width: canvasWidth, height: canvasHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
            let source = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
            let scale = min(target.width / max(source.width, 1), target.height / max(source.height, 1))
            let drawSize = CGSize(width: source.width * scale, height: source.height * scale)
            let origin = CGPoint(
                x: (target.width - drawSize.width) / 2,
                y: (target.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    private static func imageData(for image: UIImage, format: ExportImageFormat, quality: Double) -> Data? {
        switch format {
        case .jpg:
            return image.jpegDataForOpaqueExport(compressionQuality: CGFloat(quality))
        case .png:
            return image.pngDataForExport()
        }
    }

}
