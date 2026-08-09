import Foundation

/// Thread-safe snapshot of metadata for background export tasks.
struct MetadataExportSnapshot: Sendable {
    let productMetadataByAssetID: [UUID: ProductMetadata]
    let imageMetadataByAssetID: [UUID: ImageMetadata]

    func enrich(_ row: CSVExportRowContext) -> CSVExportRowContext {
        var enriched = row
        enriched.productMetadata = productMetadataByAssetID[row.product.id]
        enriched.imageMetadata = imageMetadataByAssetID[row.product.id]
        return enriched
    }
}

/// Central coordinator for product metadata — syncs capture state, drives CSV export, and records history.
@MainActor
final class MetadataManager: ObservableObject {
    @Published private(set) var bundle: SessionMetadataBundle?
    private var sessionID: UUID?
    private var saveWorkItem: DispatchWorkItem?

    // MARK: - Session lifecycle

    func loadSession(
        id: UUID,
        name: String,
        products: [CapturedProduct],
        brandName: String,
        marketplace: String
    ) {
        sessionID = id
        let loaded = MetadataStore.loadOrMigrate(
            sessionID: id,
            sessionName: name,
            capturedProducts: products,
            brandName: brandName,
            marketplace: marketplace
        )
        bundle = loaded
        MetadataStore.save(loaded, sessionID: id)
    }

    func syncFromCapturedProducts(
        _ products: [CapturedProduct],
        sessionID: UUID,
        sessionName: String,
        brandName: String,
        marketplace: String
    ) {
        self.sessionID = sessionID
        let synced = MetadataStore.loadOrMigrate(
            sessionID: sessionID,
            sessionName: sessionName,
            capturedProducts: products,
            brandName: brandName,
            marketplace: marketplace
        )
        bundle = synced
        scheduleSave(sessionID: sessionID)
    }

    func initializeEmptySession(id: UUID, name: String) {
        sessionID = id
        let empty = SessionMetadataBundle(
            project: ProjectMetadata(
                id: id,
                projectName: name,
                createdDate: Date(),
                lastModified: Date()
            )
        )
        bundle = empty
        MetadataStore.save(empty, sessionID: id)
    }

    func updateProjectName(_ name: String) {
        guard var current = bundle else { return }
        current.project.projectName = name
        current.project.lastModified = Date()
        bundle = current
        if let sessionID { scheduleSave(sessionID: sessionID) }
    }

    func transferProducts(imageAssetIDs: [UUID], to destinationSessionID: UUID) {
        guard let sourceID = sessionID else { return }
        MetadataStore.transferProducts(
            imageAssetIDs: imageAssetIDs,
            from: sourceID,
            to: destinationSessionID
        )
    }

    func clearSession() {
        bundle = nil
        sessionID = nil
    }

    // MARK: - Lookups

    func productMetadata(forCapturedProductID id: UUID) -> ProductMetadata? {
        bundle?.product(forImageAssetID: id)?.metadata
    }

    func imageMetadata(forCapturedProductID id: UUID) -> ImageMetadata? {
        bundle?.imageAsset(forID: id)?.metadata
    }

    func projectMetadata() -> ProjectMetadata? {
        bundle?.project
    }

    /// Captures current metadata for use on background export queues.
    func exportSnapshot() -> MetadataExportSnapshot {
        var products: [UUID: ProductMetadata] = [:]
        var images: [UUID: ImageMetadata] = [:]
        guard let bundle else {
            return MetadataExportSnapshot(
                productMetadataByAssetID: products,
                imageMetadataByAssetID: images
            )
        }
        for asset in bundle.imageAssets {
            images[asset.id] = asset.metadata
            if let product = bundle.product(forImageAssetID: asset.id) {
                products[asset.id] = product.metadata
            }
        }
        return MetadataExportSnapshot(
            productMetadataByAssetID: products,
            imageMetadataByAssetID: images
        )
    }

    // MARK: - Export history

    func recordExport(
        productIDs: [UUID],
        format: String,
        marketplace: String,
        packageFilename: String? = nil
    ) {
        guard var current = bundle else { return }
        let now = Date()
        let entry = ExportHistoryEntry(
            exportDate: now,
            format: format,
            marketplace: marketplace,
            productCount: productIDs.count,
            imageCount: productIDs.count,
            packageFilename: packageFilename
        )
        current.project.exportHistory.insert(entry, at: 0)
        current.project.lastModified = now

        for productID in productIDs {
            if let idx = current.products.firstIndex(where: { $0.imageAssetIDs.contains(productID) }) {
                current.products[idx].metadata.exportCount += 1
                current.products[idx].metadata.lastExportDate = now
                current.products[idx].exportHistory.insert(entry, at: 0)
            }
            if let assetIdx = current.imageAssets.firstIndex(where: { $0.id == productID }) {
                current.imageAssets[assetIdx].metadata.exported = true
            }
        }

        bundle = current
        if let sessionID { scheduleSave(sessionID: sessionID) }
    }

    // MARK: - CSV mapping

    /// Builds CSV column values from metadata when available, preserving legacy column semantics.
    static func csvValues(
        for row: CSVExportRowContext,
        exportWidth: Int,
        exportHeight: Int
    ) -> [String: String]? {
        guard let productMeta = row.productMetadata,
              let imageMeta = row.imageMetadata else {
            return nil
        }

        let dateFormatter = ISO8601DateFormatter()
        let filename = (row.archivePath as NSString).lastPathComponent
        let prefix = String(filename.dropLast(row.format.fileExtension.count + 1))
        let scaledSize = ExportManager.scaledFileSize(fromBytes: row.byteCount)
        let resolution = "\(exportWidth)x\(exportHeight)"

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
            CSVExportColumn.width.rawValue: String(exportWidth),
            CSVExportColumn.height.rawValue: String(exportHeight),
            CSVExportColumn.backgroundType.rawValue: imageMeta.backgroundType,
            CSVExportColumn.enhancementApplied.rawValue: imageMeta.enhancementApplied,
            CSVExportColumn.shadowApplied.rawValue: imageMeta.shadowApplied ? "true" : "false",
            CSVExportColumn.exportDate.rawValue: dateFormatter.string(from: row.exportDate),
            CSVExportColumn.fileFormat.rawValue: row.format.fileExtension.uppercased(),
            CSVExportColumn.resolution.rawValue: resolution,
        ]
    }

    // MARK: - Persistence

    private func scheduleSave(sessionID: UUID, debounce: TimeInterval = 0.35) {
        saveWorkItem?.cancel()
        guard let snapshot = bundle else { return }
        let work = DispatchWorkItem {
            MetadataStore.save(snapshot, sessionID: sessionID)
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounce, execute: work)
    }

    func flushToDisk() {
        saveWorkItem?.cancel()
        guard let sessionID, let snapshot = bundle else { return }
        MetadataStore.save(snapshot, sessionID: sessionID)
    }
}
