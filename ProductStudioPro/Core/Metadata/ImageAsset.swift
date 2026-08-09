import Foundation

/// An image file belonging to a product — linked to on-disk `orig_` / `proc_` files by `id`.
struct ImageAsset: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var productID: UUID
    var metadata: ImageMetadata
    var isPrimary: Bool

    init(
        id: UUID = UUID(),
        productID: UUID,
        metadata: ImageMetadata,
        isPrimary: Bool = true
    ) {
        self.id = id
        self.productID = productID
        self.metadata = metadata
        self.isPrimary = isPrimary
    }
}
