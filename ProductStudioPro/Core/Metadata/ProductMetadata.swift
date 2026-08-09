import Foundation

/// Physical dimensions for catalog and shipping integrations.
struct ProductDimensions: Codable, Equatable, Hashable, Sendable {
    var length: Double?
    var width: Double?
    var height: Double?
    var unit: DimensionUnit = .centimeters

    enum DimensionUnit: String, Codable, CaseIterable, Sendable {
        case centimeters = "cm"
        case inches = "in"
        case millimeters = "mm"
    }
}

/// Item condition for marketplace and inventory workflows.
enum ProductCondition: String, Codable, CaseIterable, Sendable {
    case new
    case used
    case refurbished
    case openBox = "open_box"
    case unknown
}

/// Canonical product-level metadata — single source of truth for catalog, export, and sync.
///
/// Each `Product` owns one `ProductMetadata` record. Values are synced from capture/edit
/// state and enriched over time by export, marketplace, and collaboration features.
struct ProductMetadata: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var sku: String
    var barcode: String
    var productName: String
    var brand: String
    var category: String
    var subcategory: String
    var vendor: String
    var manufacturer: String
    var tags: [String]
    var description: String
    var notes: String
    var marketplace: String
    var currency: String
    var price: Decimal?
    var cost: Decimal?
    var weight: Double?
    var dimensions: ProductDimensions?
    var color: String
    var material: String
    var condition: ProductCondition
    var countryOfOrigin: String
    var createdDate: Date
    var modifiedDate: Date
    var captureDate: Date
    var lastEditedDate: Date
    var favorite: Bool
    var archived: Bool
    var exportCount: Int
    var lastExportDate: Date?

    init(
        id: UUID = UUID(),
        sku: String = "",
        barcode: String = "",
        productName: String = "",
        brand: String = "",
        category: String = "",
        subcategory: String = "",
        vendor: String = "",
        manufacturer: String = "",
        tags: [String] = [],
        description: String = "",
        notes: String = "",
        marketplace: String = "",
        currency: String = "USD",
        price: Decimal? = nil,
        cost: Decimal? = nil,
        weight: Double? = nil,
        dimensions: ProductDimensions? = nil,
        color: String = "",
        material: String = "",
        condition: ProductCondition = .unknown,
        countryOfOrigin: String = "",
        createdDate: Date = Date(),
        modifiedDate: Date = Date(),
        captureDate: Date = Date(),
        lastEditedDate: Date = Date(),
        favorite: Bool = false,
        archived: Bool = false,
        exportCount: Int = 0,
        lastExportDate: Date? = nil
    ) {
        self.id = id
        self.sku = sku
        self.barcode = barcode
        self.productName = productName
        self.brand = brand
        self.category = category
        self.subcategory = subcategory
        self.vendor = vendor
        self.manufacturer = manufacturer
        self.tags = tags
        self.description = description
        self.notes = notes
        self.marketplace = marketplace
        self.currency = currency
        self.price = price
        self.cost = cost
        self.weight = weight
        self.dimensions = dimensions
        self.color = color
        self.material = material
        self.condition = condition
        self.countryOfOrigin = countryOfOrigin
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.captureDate = captureDate
        self.lastEditedDate = lastEditedDate
        self.favorite = favorite
        self.archived = archived
        self.exportCount = exportCount
        self.lastExportDate = lastExportDate
    }
}
