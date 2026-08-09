import Foundation

/// Marketplace-oriented export package profile (image geometry + delivery metadata).
enum MarketplaceExportProfileID: String, CaseIterable, Codable, Identifiable {
    case amazon
    case shopify
    case etsy
    case ebay
    case facebookMarketplace
    case instagram
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amazon: return "Amazon"
        case .shopify: return "Shopify"
        case .etsy: return "Etsy"
        case .ebay: return "eBay"
        case .facebookMarketplace: return "Facebook Marketplace"
        case .instagram: return "Instagram"
        case .custom: return "Custom"
        }
    }

    /// Maps the Settings export channel picker to a package profile when no explicit profile is set.
    static func from(exportChannel: ExportChannelProfile) -> MarketplaceExportProfileID {
        switch exportChannel {
        case .amazon: return .amazon
        case .shopify: return .shopify
        case .walmart, .custom: return .custom
        }
    }
}

struct MarketplaceExportProfile: Equatable {
    let id: MarketplaceExportProfileID
    let targetCanvasWidth: Int?
    let targetCanvasHeight: Int?
    let format: ExportImageFormat
    let minimumJPEGQuality: Double

    static func profile(for id: MarketplaceExportProfileID) -> MarketplaceExportProfile {
        switch id {
        case .amazon:
            return MarketplaceExportProfile(id: id, targetCanvasWidth: 2000, targetCanvasHeight: 2000, format: .jpg, minimumJPEGQuality: 0.92)
        case .shopify:
            return MarketplaceExportProfile(id: id, targetCanvasWidth: 2048, targetCanvasHeight: 2048, format: .jpg, minimumJPEGQuality: 0.90)
        case .etsy:
            return MarketplaceExportProfile(id: id, targetCanvasWidth: 2000, targetCanvasHeight: 2000, format: .jpg, minimumJPEGQuality: 0.90)
        case .ebay:
            return MarketplaceExportProfile(id: id, targetCanvasWidth: 1600, targetCanvasHeight: 1600, format: .jpg, minimumJPEGQuality: 0.90)
        case .facebookMarketplace:
            return MarketplaceExportProfile(id: id, targetCanvasWidth: 1080, targetCanvasHeight: 1080, format: .jpg, minimumJPEGQuality: 0.88)
        case .instagram:
            return MarketplaceExportProfile(id: id, targetCanvasWidth: 1080, targetCanvasHeight: 1080, format: .jpg, minimumJPEGQuality: 0.90)
        case .custom:
            return MarketplaceExportProfile(id: id, targetCanvasWidth: nil, targetCanvasHeight: nil, format: .jpg, minimumJPEGQuality: 0.90)
        }
    }

    var resizesImages: Bool {
        targetCanvasWidth != nil && targetCanvasHeight != nil
    }
}
