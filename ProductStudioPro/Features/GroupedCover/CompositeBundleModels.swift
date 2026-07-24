import Foundation

struct CompositeLayoutMatrix: Equatable, Codable {
    let rows: Int
    let columns: Int

    var cellCount: Int { rows * columns }

    var label: String { "\(rows)×\(columns)" }

    static let presets: [CompositeLayoutMatrix] = [
        CompositeLayoutMatrix(rows: 1, columns: 2),
        CompositeLayoutMatrix(rows: 1, columns: 3),
        CompositeLayoutMatrix(rows: 1, columns: 4),
        CompositeLayoutMatrix(rows: 1, columns: 5),
        CompositeLayoutMatrix(rows: 2, columns: 1),
        CompositeLayoutMatrix(rows: 3, columns: 1),
        CompositeLayoutMatrix(rows: 4, columns: 1),
        CompositeLayoutMatrix(rows: 5, columns: 1),
        CompositeLayoutMatrix(rows: 2, columns: 2),
        CompositeLayoutMatrix(rows: 2, columns: 3),
        CompositeLayoutMatrix(rows: 2, columns: 4),
        CompositeLayoutMatrix(rows: 2, columns: 5),
        CompositeLayoutMatrix(rows: 3, columns: 2),
        CompositeLayoutMatrix(rows: 3, columns: 3),
        CompositeLayoutMatrix(rows: 3, columns: 4),
        CompositeLayoutMatrix(rows: 4, columns: 2),
        CompositeLayoutMatrix(rows: 4, columns: 3),
        CompositeLayoutMatrix(rows: 4, columns: 4),
        CompositeLayoutMatrix(rows: 4, columns: 5),
        CompositeLayoutMatrix(rows: 5, columns: 4),
    ]

    static func presets(forProductCount count: Int) -> [CompositeLayoutMatrix] {
        presets
            .filter { $0.cellCount >= count }
            .sorted { lhs, rhs in
                let wasteL = lhs.cellCount - count
                let wasteR = rhs.cellCount - count
                if wasteL != wasteR { return wasteL < wasteR }
                let balanceL = abs(lhs.rows - lhs.columns)
                let balanceR = abs(rhs.rows - rhs.columns)
                if balanceL != balanceR { return balanceL < balanceR }
                if lhs.rows != rhs.rows { return lhs.rows < rhs.rows }
                return lhs.columns < rhs.columns
            }
    }

    static func defaultMatrix(forProductCount count: Int) -> CompositeLayoutMatrix {
        presets(forProductCount: count).first ?? CompositeLayoutMatrix(rows: 2, columns: 2)
    }
}

struct CompositeLayerTransform: Equatable, Codable {
    var centerX: Double
    var centerY: Double
    /// Drawn width relative to canvas width (0…1+).
    var scale: Double
    var rotationRadians: Double

    static let identity = CompositeLayerTransform(centerX: 0.5, centerY: 0.5, scale: 0.5, rotationRadians: 0)
}

struct CompositeLayerItem: Equatable, Codable, Identifiable {
    var id: UUID { sourceProductID }
    var sourceProductID: UUID
    var gridIndex: Int
    var zIndex: Int
    var transform: CompositeLayerTransform
    /// Cutout pixel aspect captured at layout time (used for export placement).
    var cutoutAspectWidth: Double
    var cutoutAspectHeight: Double

    init(
        sourceProductID: UUID,
        gridIndex: Int,
        zIndex: Int,
        transform: CompositeLayerTransform,
        cutoutAspectWidth: Double = 0,
        cutoutAspectHeight: Double = 0
    ) {
        self.sourceProductID = sourceProductID
        self.gridIndex = gridIndex
        self.zIndex = zIndex
        self.transform = transform
        self.cutoutAspectWidth = cutoutAspectWidth
        self.cutoutAspectHeight = cutoutAspectHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceProductID = try container.decode(UUID.self, forKey: .sourceProductID)
        gridIndex = try container.decode(Int.self, forKey: .gridIndex)
        zIndex = try container.decode(Int.self, forKey: .zIndex)
        transform = try container.decode(CompositeLayerTransform.self, forKey: .transform)
        cutoutAspectWidth = try container.decodeIfPresent(Double.self, forKey: .cutoutAspectWidth) ?? 0
        cutoutAspectHeight = try container.decodeIfPresent(Double.self, forKey: .cutoutAspectHeight) ?? 0
    }

    func cutoutAspectSize(fallback: CGSize) -> CGSize {
        if cutoutAspectWidth > 0, cutoutAspectHeight > 0 {
            return CGSize(width: cutoutAspectWidth, height: cutoutAspectHeight)
        }
        return fallback
    }

    static func aspect(from size: CGSize) -> (width: Double, height: Double) {
        (Double(max(size.width, 1)), Double(max(size.height, 1)))
    }
}

struct CompositeBundleLayout: Equatable, Codable {
    var matrix: CompositeLayoutMatrix
    var layers: [CompositeLayerItem]
    var isFreeformMode: Bool
    var sourceProductIDs: [UUID]
    var gridGapPoints: Double
    var canvasWidth: Int
    var canvasHeight: Int

    init(
        matrix: CompositeLayoutMatrix,
        layers: [CompositeLayerItem],
        isFreeformMode: Bool,
        sourceProductIDs: [UUID],
        gridGapPoints: Double = Double(CompositeLayoutEngine.defaultGridGapPoints),
        canvasWidth: Int = GroupedCoverDefaults.canvasWidth,
        canvasHeight: Int = GroupedCoverDefaults.canvasHeight
    ) {
        self.matrix = matrix
        self.layers = layers
        self.isFreeformMode = isFreeformMode
        self.sourceProductIDs = sourceProductIDs
        self.gridGapPoints = gridGapPoints
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matrix = try container.decode(CompositeLayoutMatrix.self, forKey: .matrix)
        layers = try container.decode([CompositeLayerItem].self, forKey: .layers)
        isFreeformMode = try container.decode(Bool.self, forKey: .isFreeformMode)
        sourceProductIDs = try container.decode([UUID].self, forKey: .sourceProductIDs)
        gridGapPoints = try container.decodeIfPresent(Double.self, forKey: .gridGapPoints)
            ?? Double(CompositeLayoutEngine.defaultGridGapPoints)
        canvasWidth = try container.decodeIfPresent(Int.self, forKey: .canvasWidth) ?? GroupedCoverDefaults.canvasWidth
        canvasHeight = try container.decodeIfPresent(Int.self, forKey: .canvasHeight) ?? GroupedCoverDefaults.canvasHeight
    }

    static func initial(
        products: [CapturedProduct],
        matrix: CompositeLayoutMatrix,
        canvasSize: CGSize,
        gridGapPoints: CGFloat,
        cutoutSizes: [UUID: CGSize]
    ) -> CompositeBundleLayout {
        let frames = CompositeLayoutEngine.computeGridFrames(
            matrix: matrix,
            canvasSize: canvasSize,
            gridGapPoints: gridGapPoints,
            activeCellCount: products.count
        )
        let layers: [CompositeLayerItem] = products.enumerated().map { index, product in
            let gridIndex = index
            let frame = frames.first { $0.gridIndex == gridIndex }?.frame ?? .zero
            let cutoutSize = cutoutSizes[product.id] ?? product.image.size
            let transform = CompositeLayoutEngine.fitTransform(
                cutoutSize: cutoutSize,
                targetFrame: frame,
                canvasSize: canvasSize,
                fillRatio: 1.0
            )
            let aspect = CompositeLayerItem.aspect(from: cutoutSize)
            return CompositeLayerItem(
                sourceProductID: product.id,
                gridIndex: gridIndex,
                zIndex: index,
                transform: transform,
                cutoutAspectWidth: aspect.width,
                cutoutAspectHeight: aspect.height
            )
        }
        return CompositeBundleLayout(
            matrix: matrix,
            layers: layers,
            isFreeformMode: false,
            sourceProductIDs: products.map(\.id),
            gridGapPoints: Double(gridGapPoints),
            canvasWidth: Int(canvasSize.width.rounded()),
            canvasHeight: Int(canvasSize.height.rounded())
        )
    }

    func decodedLayoutData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data?) -> CompositeBundleLayout? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CompositeBundleLayout.self, from: data)
    }
}

enum GroupedCoverDefaults {
    static let canvasWidth = 1200
    static let canvasHeight = 1200
}

extension CompositeBundleLayout {
    var resolvedCanvasWidth: Int {
        max(100, canvasWidth > 0 ? canvasWidth : GroupedCoverDefaults.canvasWidth)
    }

    var resolvedCanvasHeight: Int {
        max(100, canvasHeight > 0 ? canvasHeight : GroupedCoverDefaults.canvasHeight)
    }
}
