import Foundation

/// Record of a completed export from a project/session.
struct ExportHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var exportDate: Date
    var format: String
    var marketplace: String
    var productCount: Int
    var imageCount: Int
    var packageFilename: String?

    init(
        id: UUID = UUID(),
        exportDate: Date = Date(),
        format: String = "",
        marketplace: String = "",
        productCount: Int = 0,
        imageCount: Int = 0,
        packageFilename: String? = nil
    ) {
        self.id = id
        self.exportDate = exportDate
        self.format = format
        self.marketplace = marketplace
        self.productCount = productCount
        self.imageCount = imageCount
        self.packageFilename = packageFilename
    }
}

/// Project-level metadata — maps to a catalog session (named queue folder).
struct ProjectMetadata: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var projectName: String
    var client: String
    var location: String
    var projectType: String
    var createdDate: Date
    var lastModified: Date
    var numberOfProducts: Int
    var numberOfImages: Int
    var exportHistory: [ExportHistoryEntry]

    init(
        id: UUID = UUID(),
        projectName: String = "",
        client: String = "",
        location: String = "",
        projectType: String = "",
        createdDate: Date = Date(),
        lastModified: Date = Date(),
        numberOfProducts: Int = 0,
        numberOfImages: Int = 0,
        exportHistory: [ExportHistoryEntry] = []
    ) {
        self.id = id
        self.projectName = projectName
        self.client = client
        self.location = location
        self.projectType = projectType
        self.createdDate = createdDate
        self.lastModified = lastModified
        self.numberOfProducts = numberOfProducts
        self.numberOfImages = numberOfImages
        self.exportHistory = exportHistory
    }
}
