import Foundation

/// On-disk bundle for a catalog session's metadata graph.
struct SessionMetadataBundle: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let filename = "metadata.json"

    var schemaVersion: Int
    var project: ProjectMetadata
    var products: [Product]
    var imageAssets: [ImageAsset]

    init(
        schemaVersion: Int = SessionMetadataBundle.currentSchemaVersion,
        project: ProjectMetadata,
        products: [Product] = [],
        imageAssets: [ImageAsset] = []
    ) {
        self.schemaVersion = schemaVersion
        self.project = project
        self.products = products
        self.imageAssets = imageAssets
    }

    func product(forImageAssetID imageAssetID: UUID) -> Product? {
        guard let asset = imageAssets.first(where: { $0.id == imageAssetID }) else { return nil }
        return products.first(where: { $0.id == asset.productID })
    }

    func imageAsset(forID id: UUID) -> ImageAsset? {
        imageAssets.first(where: { $0.id == id })
    }

    func product(forID id: UUID) -> Product? {
        products.first(where: { $0.id == id })
    }
}

/// Persists session metadata bundles to disk alongside image manifests.
enum MetadataStore {
    private static let ioQueue = DispatchQueue(label: "com.productstudiopro.metadatastore", qos: .utility)

    static func metadataURL(sessionID: UUID) -> URL {
        SessionDiskStore.sessionFolderURL(sessionID: sessionID)
            .appendingPathComponent(SessionMetadataBundle.filename)
    }

    static func load(sessionID: UUID) -> SessionMetadataBundle? {
        let url = metadataURL(sessionID: sessionID)
        guard let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(SessionMetadataBundle.self, from: data) else {
            return nil
        }
        return bundle
    }

    static func save(_ bundle: SessionMetadataBundle, sessionID: UUID) {
        let url = metadataURL(sessionID: sessionID)
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(bundle) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func saveAsync(_ bundle: SessionMetadataBundle, sessionID: UUID) {
        ioQueue.async {
            save(bundle, sessionID: sessionID)
        }
    }

    /// Loads existing metadata or migrates from legacy manifest rows.
    static func loadOrMigrate(
        sessionID: UUID,
        sessionName: String,
        capturedProducts: [CapturedProduct],
        brandName: String,
        marketplace: String
    ) -> SessionMetadataBundle {
        if let existing = load(sessionID: sessionID), !existing.products.isEmpty || !capturedProducts.isEmpty {
            return MetadataMigrator.reconcile(
                existing: existing,
                capturedProducts: capturedProducts,
                sessionName: sessionName,
                brandName: brandName,
                marketplace: marketplace
            )
        }
        return MetadataMigrator.migrateFromLegacy(
            sessionID: sessionID,
            sessionName: sessionName,
            capturedProducts: capturedProducts,
            brandName: brandName,
            marketplace: marketplace
        )
    }

    /// Moves product metadata entries from one session to another.
    static func transferProducts(
        imageAssetIDs: [UUID],
        from sourceSessionID: UUID,
        to destinationSessionID: UUID
    ) {
        guard sourceSessionID != destinationSessionID,
              var source = load(sessionID: sourceSessionID) else { return }
        var destination = load(sessionID: destinationSessionID) ?? emptyBundle(
            sessionID: destinationSessionID,
            sessionName: destinationProjectName(for: destinationSessionID)
        )

        let movingAssets = source.imageAssets.filter { imageAssetIDs.contains($0.id) }
        let movingProductIDs = Set(movingAssets.map(\.productID))
        let movingProducts = source.products.filter { movingProductIDs.contains($0.id) }

        source.imageAssets.removeAll { imageAssetIDs.contains($0.id) }
        source.products.removeAll { movingProductIDs.contains($0.id) }
        source.project.numberOfProducts = source.products.count
        source.project.numberOfImages = source.imageAssets.count
        source.project.lastModified = Date()

        destination.products.insert(contentsOf: movingProducts, at: 0)
        destination.imageAssets.insert(contentsOf: movingAssets, at: 0)
        destination.project.numberOfProducts = destination.products.count
        destination.project.numberOfImages = destination.imageAssets.count
        destination.project.lastModified = Date()

        save(source, sessionID: sourceSessionID)
        save(destination, sessionID: destinationSessionID)
    }

    static func deleteSession(sessionID: UUID) {
        let url = metadataURL(sessionID: sessionID)
        try? FileManager.default.removeItem(at: url)
    }

    private static func emptyBundle(sessionID: UUID, sessionName: String) -> SessionMetadataBundle {
        SessionMetadataBundle(
            project: ProjectMetadata(
                id: sessionID,
                projectName: sessionName,
                createdDate: Date(),
                lastModified: Date()
            )
        )
    }

    private static func destinationProjectName(for sessionID: UUID) -> String {
        let restored = SessionDiskStore.loadSessionsIndex()
        return restored.sessions.first(where: { $0.id == sessionID })?.name ?? "Session"
    }
}

/// Builds and reconciles metadata from legacy queue items.
enum MetadataMigrator {
    static func migrateFromLegacy(
        sessionID: UUID,
        sessionName: String,
        capturedProducts: [CapturedProduct],
        brandName: String,
        marketplace: String
    ) -> SessionMetadataBundle {
        let now = Date()
        var products: [Product] = []
        var imageAssets: [ImageAsset] = []

        for captured in capturedProducts {
            let pair = makeEntities(
                from: captured,
                brandName: brandName,
                marketplace: marketplace,
                existingProduct: nil,
                existingAsset: nil
            )
            products.append(pair.product)
            imageAssets.append(pair.imageAsset)
        }

        let project = ProjectMetadata(
            id: sessionID,
            projectName: sessionName,
            createdDate: now,
            lastModified: now,
            numberOfProducts: products.count,
            numberOfImages: imageAssets.count
        )

        return SessionMetadataBundle(project: project, products: products, imageAssets: imageAssets)
    }

    static func reconcile(
        existing: SessionMetadataBundle,
        capturedProducts: [CapturedProduct],
        sessionName: String,
        brandName: String,
        marketplace: String
    ) -> SessionMetadataBundle {
        var bundle = existing
        bundle.project.projectName = sessionName
        bundle.project.lastModified = Date()

        var productsByAssetID: [UUID: Product] = [:]
        for product in bundle.products {
            for assetID in product.imageAssetIDs {
                productsByAssetID[assetID] = product
            }
        }

        var updatedProducts: [Product] = []
        var updatedAssets: [ImageAsset] = []
        var seenProductIDs = Set<UUID>()

        for captured in capturedProducts {
            let existingAsset = bundle.imageAssets.first(where: { $0.id == captured.id })
            let existingProduct = existingAsset.flatMap { asset in
                bundle.products.first(where: { $0.id == asset.productID })
            }

            let pair = makeEntities(
                from: captured,
                brandName: brandName,
                marketplace: marketplace,
                existingProduct: existingProduct,
                existingAsset: existingAsset
            )

            updatedAssets.append(pair.imageAsset)
            if !seenProductIDs.contains(pair.product.id) {
                updatedProducts.append(pair.product)
                seenProductIDs.insert(pair.product.id)
            } else if let idx = updatedProducts.firstIndex(where: { $0.id == pair.product.id }) {
                updatedProducts[idx] = pair.product
            }
        }

        bundle.products = updatedProducts
        bundle.imageAssets = updatedAssets
        bundle.project.numberOfProducts = updatedProducts.count
        bundle.project.numberOfImages = updatedAssets.count
        return bundle
    }

    private static func makeEntities(
        from captured: CapturedProduct,
        brandName: String,
        marketplace: String,
        existingProduct: Product?,
        existingAsset: ImageAsset?
    ) -> (product: Product, imageAsset: ImageAsset) {
        let now = Date()
        let namingMode: ImageNamingMode = .scannedUPC
        let productName = FileNameRules.baseName(for: captured, namingMode: namingMode)
        let fileSize = processedFileSize(for: captured.id)

        var productMetadata = existingProduct?.metadata ?? ProductMetadata(
            id: existingProduct?.metadata.id ?? UUID(),
            sku: captured.upc,
            barcode: captured.upc,
            productName: productName,
            brand: brandName,
            marketplace: marketplace,
            createdDate: captured.capturedAt,
            modifiedDate: now,
            captureDate: captured.capturedAt,
            lastEditedDate: now
        )

        productMetadata.sku = captured.upc
        productMetadata.barcode = captured.upc
        productMetadata.productName = productName
        if !brandName.isEmpty { productMetadata.brand = brandName }
        if !marketplace.isEmpty { productMetadata.marketplace = marketplace }
        productMetadata.captureDate = captured.capturedAt
        productMetadata.modifiedDate = now
        productMetadata.lastEditedDate = now

        let imageMeta = buildImageMetadata(
            from: captured,
            existing: existingAsset?.metadata,
            fileSize: fileSize
        )

        let productID = existingProduct?.id ?? UUID()
        let product = Product(
            id: productID,
            metadata: productMetadata,
            imageAssetIDs: [captured.id],
            editHistory: existingProduct?.editHistory ?? [],
            exportHistory: existingProduct?.exportHistory ?? [],
            notes: existingProduct?.notes ?? productMetadata.notes
        )

        let imageAsset = ImageAsset(
            id: captured.id,
            productID: productID,
            metadata: imageMeta,
            isPrimary: true
        )

        return (product, imageAsset)
    }

    static func buildImageMetadata(
        from captured: CapturedProduct,
        existing: ImageMetadata?,
        fileSize: Int
    ) -> ImageMetadata {
        let spec = captured.resolvedBackgroundFillSpec
        let backgroundType: String = {
            switch spec.fillKind {
            case .solid: return "Solid"
            case .gradient: return "Gradient"
            case .image: return "Image"
            }
        }()

        var enhancementParts: [String] = []
        if captured.polishEnabled { enhancementParts.append("AI Polish") }
        enhancementParts.append(captured.enhancementMode.rawValue)
        if captured.studioAIStrength != .natural {
            enhancementParts.append(captured.studioAIStrength.rawValue)
        }

        let pixelWidth = max(captured.canvasWidth, Int(captured.image.size.width * captured.image.scale))
        let pixelHeight = max(captured.canvasHeight, Int(captured.image.size.height * captured.image.scale))
        let hasEdits = captured.backgroundRemoved
            || captured.polishEnabled
            || captured.photoFilter != .none
            || captured.adjustAutoEnhance
            || captured.toneAdjustments != .neutral
            || captured.cutoutBrushMaskData != nil
            || captured.studioShadow.isEnabled
        let hasCrop = captured.rotationDegrees != 0
            || captured.flipHorizontal
            || captured.flipVertical

        return ImageMetadata(
            id: captured.id,
            filename: captured.filename,
            width: pixelWidth,
            height: pixelHeight,
            fileSize: fileSize > 0 ? fileSize : (existing?.fileSize ?? 0),
            orientation: ImageOrientation.from(width: pixelWidth, height: pixelHeight),
            format: .jpeg,
            backgroundType: backgroundType,
            canvasProfile: "\(captured.canvasWidth)x\(captured.canvasHeight)",
            enhancementApplied: enhancementParts.joined(separator: ", "),
            upscaled: captured.upscaled,
            cropped: hasCrop,
            edited: hasEdits,
            exported: existing?.exported ?? false,
            checksum: existing?.checksum,
            sequence: captured.sequence,
            angle: captured.angle.rawValue,
            capturedAt: captured.capturedAt,
            backgroundRemoved: captured.backgroundRemoved,
            enhancementMode: captured.enhancementMode.rawValue,
            studioAIStrength: captured.studioAIStrength.rawValue,
            canvasWidth: captured.canvasWidth,
            canvasHeight: captured.canvasHeight,
            fillRatio: captured.fillRatio,
            backgroundStyle: captured.backgroundStyle.rawValue,
            shadowApplied: captured.studioShadow.isEnabled
        )
    }

    private static func processedFileSize(for productID: UUID) -> Int {
        guard let url = SessionDiskStore.processedImageFileURL(for: productID),
              let data = try? Data(contentsOf: url) else { return 0 }
        return data.count
    }
}
