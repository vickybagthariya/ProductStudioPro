import Foundation

// MARK: - Dynamic category (discovered from bundle folders)

struct ImageBackgroundCategory: Identifiable, Hashable, Codable, Equatable {
    /// Folder name inside `BackgroundAssets/` (e.g. `retail-shelves`).
    let slug: String
    /// Human-readable title (e.g. `Retail Shelves`).
    let displayName: String

    var id: String { slug }

    static let recentlyUsed = ImageBackgroundCategory(slug: "__recently_used__", displayName: "Recently Used")
    static let favorites = ImageBackgroundCategory(slug: "__favorites__", displayName: "Favorites")
    static let importedCustom = ImageBackgroundCategory(slug: "custom", displayName: "Custom")
}

enum ImageBackgroundSource: String, Codable, CaseIterable {
    case bundled
    case photos
    case files
    case clipboard
    case url
    case saved
    case online
}

enum OnlineBackgroundProvider: String, Codable, Equatable {
    case pexels
    case unsplash
    case pixabay

    var displayName: String {
        switch self {
        case .pexels: return "Pexels"
        case .unsplash: return "Unsplash"
        case .pixabay: return "Pixabay"
        }
    }
}

struct ImageBackgroundProvenance: Codable, Equatable {
    var provider: OnlineBackgroundProvider
    var providerPhotoID: String
    var photographerName: String
    var photographerURL: String?
    var photoPageURL: String?
    var licenseName: String
    var licenseURL: String?
    var thumbURL: String?
    var downloadURL: String?
    var query: String?
    var attributionRequired: Bool
    var fetchedAt: Date

    var attributionLine: String {
        let name = photographerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Photo via \(provider.displayName)"
        }
        return "Photo by \(name) / \(provider.displayName)"
    }
}

enum ContactShadowStrength: String, CaseIterable, Codable, Identifiable {
    case off = "Off"
    case soft = "Soft"
    case medium = "Medium"
    case strong = "Strong"

    var id: String { rawValue }
}

enum ImageBackgroundEditorLayerKind: String, CaseIterable, Codable, Identifiable {
    case product = "Product"
    case background = "Background"
    case shadow = "Shadow"
    case reflection = "Reflection"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .product: return "cube.transparent"
        case .background: return "photo"
        case .shadow: return "shadow"
        case .reflection: return "reflect.horizontal"
        }
    }
}

// MARK: - Crop + placement

struct ImageBackgroundCropSpec: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 1

    static let full = ImageBackgroundCropSpec()

    func clamped() -> ImageBackgroundCropSpec {
        var c = self
        c.width = max(0.05, min(c.width, 1))
        c.height = max(0.05, min(c.height, 1))
        c.x = max(0, min(c.x, 1 - c.width))
        c.y = max(0, min(c.y, 1 - c.height))
        return c
    }
}

struct ProductPlacementSpec: Codable, Equatable {
    var scaleMultiplier: Double = 1.0
    var offsetXNormalized: Double = 0
    var offsetYNormalized: Double = 0

    static let `default` = ProductPlacementSpec()
}

// MARK: - Background definition

struct ImageBackgroundDefinition: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var categorySlug: String
    var resourcePath: String?
    var isStaging: Bool
    var surfaceLineY: Double?
    var defaultScale: Double
    var defaultX: Double
    var defaultY: Double
}

// MARK: - Active selection

struct ImageBackgroundSelection: Codable, Equatable {
    var backgroundID: String
    var customImageRef: String?
    var placement: ProductPlacementSpec
    var shadow: ContactShadowStrength
    var backgroundTransform: CompositeLayerTransform?
    var productTransform: CompositeLayerTransform?
    var backgroundCrop: ImageBackgroundCropSpec?
    var backgroundBlur: Double
    var reflectionOpacity: Double
    var backgroundLocked: Bool
    var productLocked: Bool

    enum CodingKeys: String, CodingKey {
        case backgroundID, customImageRef, placement, shadow
        case backgroundTransform, productTransform, backgroundCrop
        case backgroundBlur, reflectionOpacity, backgroundLocked, productLocked
    }

    init(
        backgroundID: String,
        customImageRef: String? = nil,
        placement: ProductPlacementSpec = .default,
        shadow: ContactShadowStrength = .off,
        backgroundTransform: CompositeLayerTransform? = nil,
        productTransform: CompositeLayerTransform? = nil,
        backgroundCrop: ImageBackgroundCropSpec? = .full,
        backgroundBlur: Double = 0,
        reflectionOpacity: Double = 0,
        backgroundLocked: Bool = false,
        productLocked: Bool = false
    ) {
        self.backgroundID = backgroundID
        self.customImageRef = customImageRef
        self.placement = placement
        self.shadow = shadow
        self.backgroundTransform = backgroundTransform
        self.productTransform = productTransform
        self.backgroundCrop = backgroundCrop
        self.backgroundBlur = backgroundBlur
        self.reflectionOpacity = reflectionOpacity
        self.backgroundLocked = backgroundLocked
        self.productLocked = productLocked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backgroundID = try c.decode(String.self, forKey: .backgroundID)
        customImageRef = try c.decodeIfPresent(String.self, forKey: .customImageRef)
        placement = try c.decodeIfPresent(ProductPlacementSpec.self, forKey: .placement) ?? .default
        shadow = try c.decodeIfPresent(ContactShadowStrength.self, forKey: .shadow) ?? .off
        backgroundTransform = try c.decodeIfPresent(CompositeLayerTransform.self, forKey: .backgroundTransform)
        productTransform = try c.decodeIfPresent(CompositeLayerTransform.self, forKey: .productTransform)
        backgroundCrop = try c.decodeIfPresent(ImageBackgroundCropSpec.self, forKey: .backgroundCrop)
        backgroundBlur = try c.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 0
        reflectionOpacity = try c.decodeIfPresent(Double.self, forKey: .reflectionOpacity) ?? 0
        backgroundLocked = try c.decodeIfPresent(Bool.self, forKey: .backgroundLocked) ?? false
        productLocked = try c.decodeIfPresent(Bool.self, forKey: .productLocked) ?? false
    }

    static func defaultSelection(backgroundID: String = ImageBackgroundFolderCatalog.defaultBackgroundID) -> ImageBackgroundSelection {
        ImageBackgroundSelection(backgroundID: backgroundID)
    }
}

enum ImageBackgroundRecentStore {
    private static let key = "imageBackgroundRecentBackgroundIDs"
    private static let maxCount = 24

    static var ids: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func markUsed(_ backgroundID: String) {
        var recent = ids.filter { $0 != backgroundID }
        recent.insert(backgroundID, at: 0)
        if recent.count > maxCount {
            recent = Array(recent.prefix(maxCount))
        }
        UserDefaults.standard.set(recent, forKey: key)
    }
}
