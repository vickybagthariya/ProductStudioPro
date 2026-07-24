import Foundation
import SwiftUI

/// Marketplace-oriented one-tap look: canvas size + polish + background (+ optional style).
enum CatalogTemplateChannel: String, CaseIterable, Identifiable {
    case amazon
    case etsy
    case instagram
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amazon: return "Amazon"
        case .etsy: return "Etsy"
        case .instagram: return "Instagram"
        case .general: return "Studio"
        }
    }

    var systemImage: String {
        switch self {
        case .amazon: return "cart.fill"
        case .etsy: return "bag.fill"
        case .instagram: return "camera.filters"
        case .general: return "sparkles"
        }
    }
}

struct CatalogTemplatePack: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let channel: CatalogTemplateChannel
    let canvasWidth: Int
    let canvasHeight: Int
    let fillRatio: Double
    let enhancementMode: PhotoEnhancementMode
    let studioStrength: StudioAIStrength
    let backgroundPreset: BackgroundQuickPreset
    let photoFilter: ExportPhotoFilter
    let accentHex: String

    var swatchColors: [Color] {
        backgroundPreset.hexes.prefix(3).compactMap { Color(hex: $0) }
    }
}

enum CatalogTemplateLibrary {
    static let appDefaultsID = "app-defaults"

    /// Pinned first on Home — resets to app baseline (no sticky style filter).
    static let appDefaults = CatalogTemplatePack(
        id: appDefaultsID,
        name: "App Defaults",
        subtitle: "1200² · Standard Clean · Original",
        channel: .general,
        canvasWidth: 1200,
        canvasHeight: 1200,
        fillRatio: 0.95,
        enhancementMode: .standardClean,
        studioStrength: .natural,
        backgroundPreset: .catalogWhite,
        photoFilter: .none,
        accentHex: "#FFFFFF"
    )

    /// Curated one-tap packs for Home — keep short and opinionated.
    static let all: [CatalogTemplatePack] = [
        appDefaults,
        CatalogTemplatePack(
            id: "amazon-white",
            name: "Amazon White",
            subtitle: "2000² · clean catalog",
            channel: .amazon,
            canvasWidth: 2000,
            canvasHeight: 2000,
            fillRatio: 0.92,
            enhancementMode: .standardClean,
            studioStrength: .strong,
            backgroundPreset: .catalogWhite,
            photoFilter: .trueWhiteBackdrop,
            accentHex: "#FFFFFF"
        ),
        CatalogTemplatePack(
            id: "amazon-studio",
            name: "Amazon Studio",
            subtitle: "2000² · soft mist",
            channel: .amazon,
            canvasWidth: 2000,
            canvasHeight: 2000,
            fillRatio: 0.90,
            enhancementMode: .standardClean,
            studioStrength: .strong,
            backgroundPreset: .studioMist,
            photoFilter: .premiumRetail,
            accentHex: "#E4E8F0"
        ),
        CatalogTemplatePack(
            id: "amazon-noir",
            name: "Listing Noir",
            subtitle: "2000² · dark hero",
            channel: .amazon,
            canvasWidth: 2000,
            canvasHeight: 2000,
            fillRatio: 0.88,
            enhancementMode: .standardClean,
            studioStrength: .ultra,
            backgroundPreset: .listingNoir,
            photoFilter: .pureBlackShadow,
            accentHex: "#1A1A22"
        ),
        CatalogTemplatePack(
            id: "etsy-warm",
            name: "Etsy Warm",
            subtitle: "1600² · craft paper",
            channel: .etsy,
            canvasWidth: 1600,
            canvasHeight: 1600,
            fillRatio: 0.88,
            enhancementMode: .standardClean,
            studioStrength: .natural,
            backgroundPreset: .craftPaper,
            photoFilter: .warmLuxury,
            accentHex: "#E2C99B"
        ),
        CatalogTemplatePack(
            id: "etsy-linen",
            name: "Etsy Linen",
            subtitle: "1600² · soft linen",
            channel: .etsy,
            canvasWidth: 1600,
            canvasHeight: 1600,
            fillRatio: 0.90,
            enhancementMode: .standardClean,
            studioStrength: .natural,
            backgroundPreset: .linenSoft,
            photoFilter: .photosNatural,
            accentHex: "#EFE7DA"
        ),
        CatalogTemplatePack(
            id: "etsy-blush",
            name: "Rose Shop",
            subtitle: "1600² · rose quartz",
            channel: .etsy,
            canvasWidth: 1600,
            canvasHeight: 1600,
            fillRatio: 0.88,
            enhancementMode: .standardClean,
            studioStrength: .natural,
            backgroundPreset: .roseQuartz,
            photoFilter: .photosCozy,
            accentHex: "#FFD6DD"
        ),
        CatalogTemplatePack(
            id: "ig-square",
            name: "IG Feed",
            subtitle: "1080² · vivid social",
            channel: .instagram,
            canvasWidth: 1080,
            canvasHeight: 1080,
            fillRatio: 0.90,
            enhancementMode: .standardClean,
            studioStrength: .strong,
            backgroundPreset: .sunsetDiagonal,
            photoFilter: .instagramPop,
            accentHex: "#FFB199"
        ),
        CatalogTemplatePack(
            id: "ig-story",
            name: "IG Story",
            subtitle: "1080×1920 · bright",
            channel: .instagram,
            canvasWidth: 1080,
            canvasHeight: 1920,
            fillRatio: 0.85,
            enhancementMode: .standardClean,
            studioStrength: .strong,
            backgroundPreset: .neonNight,
            photoFilter: .tiktokBright,
            accentHex: "#7E5BFF"
        ),
        CatalogTemplatePack(
            id: "ig-creator",
            name: "Creator Pop",
            subtitle: "1080² · creator mode",
            channel: .instagram,
            canvasWidth: 1080,
            canvasHeight: 1080,
            fillRatio: 0.90,
            enhancementMode: .standardClean,
            studioStrength: .ultra,
            backgroundPreset: .auroraDiagonal,
            photoFilter: .creatorMode,
            accentHex: "#28C7A6"
        ),
        CatalogTemplatePack(
            id: "jewelry",
            name: "Jewelry Shine",
            subtitle: "1600² · luxury black",
            channel: .general,
            canvasWidth: 1600,
            canvasHeight: 1600,
            fillRatio: 0.78,
            enhancementMode: .standardClean,
            studioStrength: .ultra,
            backgroundPreset: .onyxHero,
            photoFilter: .jewelryShine,
            accentHex: "#242430"
        ),
        CatalogTemplatePack(
            id: "watch",
            name: "Watch Studio",
            subtitle: "1600² · steel mono",
            channel: .general,
            canvasWidth: 1600,
            canvasHeight: 1600,
            fillRatio: 0.82,
            enhancementMode: .standardClean,
            studioStrength: .strong,
            backgroundPreset: .steelMono,
            photoFilter: .watchStudio,
            accentHex: "#C8C8C8"
        ),
        CatalogTemplatePack(
            id: "marketplace-amber",
            name: "Marketplace Amber",
            subtitle: "2000² · warm floor",
            channel: .general,
            canvasWidth: 2000,
            canvasHeight: 2000,
            fillRatio: 0.90,
            enhancementMode: .standardClean,
            studioStrength: .strong,
            backgroundPreset: .marketplaceAmber,
            photoFilter: .eCommerceVivid,
            accentHex: "#F5E0C2"
        ),
        CatalogTemplatePack(
            id: "editorial-pearl",
            name: "Editorial Pearl",
            subtitle: "2048² · Shopify ready",
            channel: .general,
            canvasWidth: 2048,
            canvasHeight: 2048,
            fillRatio: 0.92,
            enhancementMode: .standardClean,
            studioStrength: .strong,
            backgroundPreset: .editorialPearl,
            photoFilter: .premiumCatalog,
            accentHex: "#F0F1F5"
        ),
    ]

    static func packs(for channel: CatalogTemplateChannel?) -> [CatalogTemplatePack] {
        guard let channel else { return all }
        return all.filter { $0.channel == channel }
    }

    /// App Defaults pinned first, then the active pack, then the rest (channel filter respected).
    static func orderedPacks(for channel: CatalogTemplateChannel?, activeID: String?) -> [CatalogTemplatePack] {
        let channelPacks = packs(for: channel).filter { $0.id != appDefaultsID }
        var ordered: [CatalogTemplatePack] = [appDefaults]
        let active = activeID.flatMap { id in all.first(where: { $0.id == id }) }
        if let active, active.id != appDefaultsID {
            let activeVisible = channel == nil || active.channel == channel
            if activeVisible {
                ordered.append(active)
            }
        }
        let skip = Set(ordered.map(\.id))
        ordered.append(contentsOf: channelPacks.filter { !skip.contains($0.id) })
        return ordered
    }
}
