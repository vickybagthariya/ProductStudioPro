import Foundation

/// Lightweight edit-history entry for version tracking and collaboration.
struct EditHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var action: String
    var detail: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: String,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.detail = detail
    }
}

/// A catalog product — owns metadata, image assets, and history.
///
/// In the current app version each queue item maps 1:1 to a `Product` with one primary
/// `ImageAsset`. The model supports multiple images per product for future multi-angle
/// and variant workflows without schema changes.
struct Product: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var metadata: ProductMetadata
    var imageAssetIDs: [UUID]
    var editHistory: [EditHistoryEntry]
    var exportHistory: [ExportHistoryEntry]
    var notes: String

    init(
        id: UUID = UUID(),
        metadata: ProductMetadata,
        imageAssetIDs: [UUID] = [],
        editHistory: [EditHistoryEntry] = [],
        exportHistory: [ExportHistoryEntry] = [],
        notes: String = ""
    ) {
        self.id = id
        self.metadata = metadata
        self.imageAssetIDs = imageAssetIDs
        self.editHistory = editHistory
        self.exportHistory = exportHistory
        self.notes = notes
    }

    var primaryImageAssetID: UUID? {
        imageAssetIDs.first
    }
}
