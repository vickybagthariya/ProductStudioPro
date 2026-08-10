import Foundation
import SwiftUI
import UIKit
import ImageIO
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import LinkPresentation
import UniformTypeIdentifiers

extension UIColor {
    convenience init?(hexString: String) {
        var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}



extension UIColor {
    func lighter(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return UIColor(hue: h, saturation: max(0, s * 0.65), brightness: min(1, b + amount), alpha: a)
        }
        return self
    }

    func darker(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return UIColor(hue: h, saturation: s, brightness: max(0, b - amount), alpha: a)
        }
        return self
    }
}

// MARK: - App Modes

enum CaptureMode: String, CaseIterable, Identifiable {
    case single = "Single"
    case batch = "Batch Mode"
    var id: String { rawValue }
}

enum ImageNamingMode: String, CaseIterable, Identifiable {
    case scannedUPC = "Scan UPC"
    case randomName = "Random Name"
    case manualInput = "Manual Input"
    var id: String { rawValue }
}

/// Studio AI has been removed from the product. Only Standard Clean remains; any legacy
/// `"Studio AI"` raw value read from disk / UserDefaults fails to match and callers fall back
/// to `.standardClean` via `?? .standardClean` (see `CatalogProcessingBaseline.mode`).
enum PhotoEnhancementMode: String, CaseIterable, Identifiable {
    case standardClean = "Standard Clean"

    var id: String { rawValue }

    var description: String {
        "Fast on-device cleanup for normal website images."
    }

    /// Settings helper text for the fast+good performance profile.
    var settingsGuidanceText: String {
        "Fast cleanup with basic edge tidy — tuned for speed and lower memory use."
    }
}

/// Vestigial — Smart Upscale / Studio AI strength selection has been removed from the UI and
/// from the polish pipeline. Kept only so on-disk session records and existing API signatures
/// stay source/data compatible; the value is never branched on for pixel output anymore.
enum StudioAIStrength: String, CaseIterable, Identifiable {
    case natural = "Natural"
    case strong = "Strong"
    case ultra = "Ultra"

    var id: String { rawValue }
}

/// Product-centric photo adjustments for e-commerce and marketplace sellers.
enum ExportPhotoFilter: String, CaseIterable, Identifiable, Codable {
    case none = "Original"
    /// Standard / unfiltered — same as Original (internal / legacy).
    case standard = "Standard"

    // Product Studio Collection
    case auto = "Auto"
    case trueWhiteBackdrop = "True White Backdrop"
    case pureBlackShadow = "Pure Black Shadow"
    case fabricGrainPop = "Fabric Grain Pop"
    case metallicShimmer = "Metallic Shimmer"
    case trueNeutralizer = "True Neutralizer"
    case antiGlare = "Anti Glare"
    case studioLight = "Studio Light"
    case premiumRetail = "Premium Retail"
    case luxuryMatte = "Luxury Matte"
    case jewelryShine = "Jewelry Shine"
    case watchStudio = "Watch Studio"
    case premiumCatalog = "Premium Catalog"

    // Social Media
    case socialMedia = "Social Media"
    case instagramPop = "Instagram Pop"
    case tiktokBright = "TikTok Bright"
    case creatorMode = "Creator Mode"

    // Modern Looks
    case photosNatural = "Photos Natural"
    case photosVibrant = "Photos Vibrant"
    case photosLuminous = "Photos Luminous"
    case warmLuxury = "Warm Luxury"
    case coolEditorial = "Cool Editorial"
    case eCommerceVivid = "eCommerce Vivid"

    // Dramatic Looks
    case dramatic = "Dramatic"
    case dramaticCool = "Dramatic Cool"
    case vantage = "Vantage"
    case chrome = "Chrome"

    // Film Collection
    case kodachrome = "Kodachrome"
    case crossProcess = "Cross Process"
    case polaroidVintage = "Polaroid Vintage"
    case lomo = "Lomo"
    case film = "Film"
    case portra400 = "Portra 400"
    case fujiClassic = "Fuji Classic"
    case cineStill = "CineStill"

    // Monochrome
    case noir = "Noir"
    case highKeyLightMono = "High Key Mono"
    case stageLightMono = "Stage Light Mono"

    // Creative
    case photosCozy = "Photos Cozy"
    case photosEthereal = "Photos Ethereal"
    case sunriseGlow = "Sunrise Glow"
    case gotham = "Gotham"
    case thermal = "Thermal"
    case invert = "Invert"
    case posterize = "Posterize"
    case negative = "Negative"

    var id: String { rawValue }

    /// Fast strip in the adjust sheet — product-studio essentials.
    static let adjustSheetStyleStripCases: [ExportPhotoFilter] = [
        .none,
        .auto,
        .trueWhiteBackdrop,
        .premiumRetail,
        .eCommerceVivid,
        .warmLuxury,
    ]

    /// Horizontal style strip — curated product-selling adjustments.
    static let photosStylePickerCases: [ExportPhotoFilter] = pickerCases

    /// Curated picker order (Product Studio → Social → Modern → Dramatic → Film → Mono → Creative).
    static let pickerCases: [ExportPhotoFilter] = [
        // Product Studio Collection
        .none, .auto,
        .trueWhiteBackdrop, .pureBlackShadow,
        .fabricGrainPop, .metallicShimmer,
        .trueNeutralizer, .antiGlare, .studioLight,
        .premiumRetail, .luxuryMatte, .jewelryShine, .watchStudio, .premiumCatalog,
        // Social Media
        .socialMedia, .instagramPop, .tiktokBright, .creatorMode,
        // Modern Looks
        .photosNatural, .photosVibrant, .photosLuminous,
        .warmLuxury, .coolEditorial, .eCommerceVivid,
        // Dramatic Looks
        .dramatic, .dramaticCool, .vantage, .chrome,
        // Film Collection
        .kodachrome, .crossProcess, .polaroidVintage, .lomo,
        .film, .portra400, .fujiClassic, .cineStill,
        // Monochrome
        .noir, .highKeyLightMono, .stageLightMono,
        // Creative
        .photosCozy, .photosEthereal, .sunriseGlow, .gotham,
        .thermal, .invert, .posterize, .negative,
    ]

    /// Maps persisted filter names; retired or duplicate filters map to the closest active look.
    static func resolved(from raw: String?) -> ExportPhotoFilter {
        guard let raw, !raw.isEmpty else { return .none }
        let aliases: [String: ExportPhotoFilter] = [
            // Legacy names → current display names
            "TrueWhite": .trueWhiteBackdrop,
            "Pure Black Matte": .pureBlackShadow,
            "Anti-Glare": .antiGlare,
            "Fabric & Grain": .fabricGrainPop,
            "E-Commerce Vivid": .eCommerceVivid,
            "Natural": .photosNatural,
            "Vibrant": .photosVibrant,
            "Luminous": .photosLuminous,
            "Cozy": .photosCozy,
            "Ethereal": .photosEthereal,
            "Polaroid": .polaroidVintage,
            "High-Key Light Mono": .highKeyLightMono,
            "Sunrise": .sunriseGlow,
            "Autocorrect": .auto,
            // Merged looks
            "Vivid Warm": .warmLuxury,
            "Dramatic Warm": .dramatic,
            // Retired → closest active look
            "Warm": .warmLuxury,
            "Cool": .coolEditorial,
            "Pleasant": .warmLuxury,
            "Orange Peel": .warmLuxury,
            "Lord Kelvin": .warmLuxury,
            "Vivid Cool": .coolEditorial,
            "Technicolor": .photosVibrant,
            "Hemingway": .photosNatural,
            "Vintage Fade": .polaroidVintage,
            "Tonal": .noir,
            "Muted B&W": .noir,
            "Sharpen": .fabricGrainPop,
            "Clarity": .fabricGrainPop,
            "Brighten": .photosLuminous,
            "Contrast+": .eCommerceVivid,
            "HDR Look": .vantage,
            "Crystallize": .none,
            // Other legacy aliases
            "Dark Border": .none,
            "Light Border": .none,
            "Standard": .none,
            "Vivid": .eCommerceVivid,
            "Mono": .noir,
            "Silvertone": .noir,
            "Stark B&W": .noir,
            "Strictly B&W": .noir,
            "Fade": .polaroidVintage,
            "Instant": .polaroidVintage,
            "Transfer": .warmLuxury,
            "Process": .dramatic,
            "Comic": .none,
            "Sin City": .noir,
            "Art": .none,
            "Night Vision": .none,
            "Heatmap": .none,
            "Pixelate": .none,
            "Edge Sketch": .none,
            "Edges": .none,
            "Nostalgia": .polaroidVintage,
            "Old Paper": .polaroidVintage,
            "Brownie": .polaroidVintage,
            "Hazy Days": .polaroidVintage,
            "Solarize": .none,
            "Jarques": .photosNatural,
            "Her Majesty": .warmLuxury,
            "Love": .warmLuxury,
            "Pinhole": .noir,
            "Quiet": .photosNatural,
            "Glowing Sun": .sunriseGlow,
            "Grungy": .gotham,
            "Sepia": .polaroidVintage,
            "Vignette": .vantage,
            "Bloom": .photosEthereal,
            "Gloom": .gotham,
        ]
        if let mapped = aliases[raw] { return mapped }
        return ExportPhotoFilter(rawValue: raw) ?? .none
    }
}

enum BackgroundCanvasStyle: String, CaseIterable, Identifiable {
    case solid = "Solid Color"
    case linearGradient = "Gradient Backdrop"
    case seamless = "Seamless"
    case seamlessMono = "Seamless Mono"
    case colorBackdrop = "Color Backdrop"
    case duotone = "Duotone"
    case colorWash = "Color Wash"
    case overprint = "Overprint"
    case studio = "Studio"
    case blackWhite = "Black & White"
    case diagonalGradient = "Diagonal Gradient"
    case radialGradient = "Radial Spotlight"
    case doubleHalo = "Premium Halo"
    case softFloor = "Soft Floor"
    case shelfPlinth = "Shelf Plinth"

    var id: String { rawValue }

    /// Maps legacy saved style names and UserDefaults strings.
    static func fromStored(_ raw: String?) -> BackgroundCanvasStyle {
        guard let raw else { return .solid }
        if raw == "Podium Stage" { return .softFloor }
        return BackgroundCanvasStyle(rawValue: raw) ?? .solid
    }

    var minimumColorCount: Int { self == .solid || self == .blackWhite ? 1 : 2 }
    var supportsColorStops: Bool { self != .blackWhite }

    var description: String {
        switch self {
        case .solid:
            return "One clean background color. Only one color picker is shown."
        case .linearGradient:
            return "PowerPoint-style gradient stops. Add as many colors as you want."
        case .seamless:
            return "Soft Apple-wallpaper style seamless backdrop with gentle depth."
        case .seamlessMono:
            return "Single-family seamless backdrop using lighter/darker tones of your color."
        case .colorBackdrop:
            return "Premium product backdrop with soft color falloff behind the item."
        case .duotone:
            return "Two-color hero style backdrop with smooth blended lighting."
        case .colorWash:
            return "Light washed background with subtle color movement."
        case .overprint:
            return "Layered print-like color blend for a modern hero look."
        case .studio:
            return "Clean studio sweep with soft top light and floor depth."
        case .blackWhite:
            return "Neutral black-to-white editorial style. No color pickers needed."
        case .diagonalGradient:
            return "Diagonal gradient with a subtle studio highlight."
        case .radialGradient:
            return "Soft spotlight gradient behind the product."
        case .doubleHalo:
            return "Dual spotlight halo for premium hero images."
        case .softFloor:
            return "Warm studio gradient with a soft floor shadow — no hard stage shape."
        case .shelfPlinth:
            return "Adds a wider retail shelf/plinth stage with soft depth."
        }
    }

    /// Matches `ImageProcessor.drawBackground` linear gradient axis for SwiftUI previews.
    var usesDiagonalBlendAxis: Bool {
        switch self {
        case .diagonalGradient, .duotone, .overprint:
            return true
        default:
            return false
        }
    }

    var usesRadialBlendPreview: Bool {
        switch self {
        case .radialGradient, .doubleHalo:
            return true
        default:
            return false
        }
    }
}

/// Curated “premium” looks (catalog, hero, editorial). Applies style + color stops in one tap.
enum BackgroundQuickPreset: String, CaseIterable, Identifiable {
    case catalogWhite = "Catalog White"
    case studioMist = "Studio Mist"
    case warmSeamless = "Warm Seamless"
    case steelMono = "Steel Mono"
    case midnightHalo = "Midnight Halo"
    case sunsetDiagonal = "Sunset Diagonal"
    case sageBackdrop = "Sage Backdrop"
    case duotoneInk = "Duotone Ink"
    case iceRadial = "Ice Spotlight"
    case sandLinear = "Sand Linear"
    case warmFloor = "Warm Floor"
    case shelfRetail = "Retail Shelf"
    case porcelain = "Porcelain"
    case linenSoft = "Soft Linen"
    case parisGray = "Paris Gray"
    case marbleHero = "Marble Hero"
    case champagneFloor = "Champagne Floor"
    case roseQuartz = "Rose Quartz"
    case mintFresh = "Mint Fresh"
    case oceanFade = "Ocean Fade"
    case skyMint = "Sky / Mint"
    case lavenderHaze = "Lavender Haze"
    case peachCream = "Peach Cream"
    case copperGlow = "Copper Glow"
    case forestStudio = "Forest Studio"
    case slateNoir = "Slate Noir"
    case onyxHero = "Onyx Hero"
    case obsidianRadial = "Obsidian Spot"
    case gradientPalette = "Tropic Mango"
    case berryDuotone = "Berry Duotone"
    case neonNight = "Neon Night"
    case galaxyHalo = "Galaxy Halo"
    case auroraDiagonal = "Aurora Diagonal"
    case gildedFloor = "Gilded Floor"
    case retailMatte = "Retail Matte"
    case craftPaper = "Craft Paper"
    case editorialPearl = "Editorial Pearl"
    case shopFloorNeutral = "Shop Floor Neutral"
    case winterMist = "Winter Mist"
    case springDew = "Spring Dew"
    case marketplaceAmber = "Marketplace Amber"
    case listingNoir = "Listing Noir"

    var id: String { rawValue }

    /// Presets shown in Premium / quick-preset menus (unique style + palette pairs).
    static let menuCases: [BackgroundQuickPreset] = [
        .catalogWhite, .studioMist, .warmSeamless, .steelMono,
        .midnightHalo, .sunsetDiagonal, .sageBackdrop, .duotoneInk,
        .iceRadial, .sandLinear, .warmFloor, .shelfRetail,
        .marbleHero, .roseQuartz, .oceanFade, .copperGlow,
        .slateNoir, .onyxHero, .neonNight, .auroraDiagonal,
        .craftPaper, .editorialPearl, .winterMist, .springDew,
        .marketplaceAmber, .listingNoir,
    ]

    var style: BackgroundCanvasStyle {
        switch self {
        case .catalogWhite: return .solid
        case .studioMist: return .studio
        case .warmSeamless: return .seamless
        case .steelMono: return .seamlessMono
        case .midnightHalo: return .doubleHalo
        case .sunsetDiagonal: return .diagonalGradient
        case .sageBackdrop: return .colorBackdrop
        case .duotoneInk: return .duotone
        case .iceRadial: return .radialGradient
        case .sandLinear: return .linearGradient
        case .warmFloor: return .softFloor
        case .shelfRetail: return .shelfPlinth
        case .porcelain: return .seamless
        case .linenSoft: return .seamlessMono
        case .parisGray: return .seamlessMono
        case .marbleHero: return .colorBackdrop
        case .champagneFloor: return .softFloor
        case .roseQuartz: return .colorBackdrop
        case .mintFresh: return .seamless
        case .oceanFade: return .linearGradient
        case .skyMint: return .diagonalGradient
        case .lavenderHaze: return .colorWash
        case .peachCream: return .softFloor
        case .copperGlow: return .radialGradient
        case .forestStudio: return .colorBackdrop
        case .slateNoir: return .seamlessMono
        case .onyxHero: return .duotone
        case .obsidianRadial: return .radialGradient
        case .gradientPalette: return .linearGradient
        case .berryDuotone: return .duotone
        case .neonNight: return .doubleHalo
        case .galaxyHalo: return .doubleHalo
        case .auroraDiagonal: return .diagonalGradient
        case .gildedFloor: return .softFloor
        case .retailMatte: return .shelfPlinth
        case .craftPaper: return .seamless
        case .editorialPearl: return .studio
        case .shopFloorNeutral: return .seamlessMono
        case .winterMist: return .linearGradient
        case .springDew: return .colorWash
        case .marketplaceAmber: return .softFloor
        case .listingNoir: return .duotone
        }
    }

    var hexes: [String] {
        switch self {
        case .catalogWhite:
            return ["#FFFFFF"]
        case .studioMist:
            return ["#F7F8FB", "#E4E8F0", "#D0D6E4"]
        case .warmSeamless:
            return ["#FFF9F0", "#F3E6D4", "#E8D4BC"]
        case .steelMono:
            return ["#F4F4F4", "#C8C8C8", "#8A8A8A"]
        case .midnightHalo:
            return ["#0E111A", "#2A3358", "#6B7FD7"]
        case .sunsetDiagonal:
            return ["#FFE8CC", "#FFB199", "#C86FB4"]
        case .sageBackdrop:
            return ["#EAF7EF", "#BFE8CF", "#5FAE7A"]
        case .duotoneInk:
            return ["#1A0F2E", "#4B2A86", "#E04D9C"]
        case .iceRadial:
            return ["#EAF3FF", "#FFFFFF", "#D4E4FF"]
        case .sandLinear:
            return ["#FBF6EE", "#EADCC4", "#D2C2A8"]
        case .warmFloor:
            return ["#FFFDF8", "#EDE6DC", "#D8CFC0"]
        case .shelfRetail:
            return ["#F6F6F6", "#E2E2E2", "#CFCFCF"]
        case .porcelain:
            return ["#FFFFFF", "#F4F1ED", "#E8E2D9"]
        case .linenSoft:
            return ["#FAF6F0", "#EFE7DA", "#DCCFB9"]
        case .parisGray:
            return ["#F2F2F2", "#D8D8D8", "#A8A8A8"]
        case .marbleHero:
            return ["#FFFFFF", "#EFEFEF", "#D5D7DA", "#B8BCC4"]
        case .champagneFloor:
            return ["#FBF1E0", "#F1DFC2", "#E0C499"]
        case .roseQuartz:
            return ["#FFF1F1", "#FFD6DD", "#F4A6B6"]
        case .mintFresh:
            return ["#F1FBF6", "#D6F1E2", "#A7DDC0"]
        case .oceanFade:
            return ["#E8F4FB", "#9CC8E0", "#3F7FAE"]
        case .skyMint:
            return ["#E5F5FF", "#D7F2E5", "#9DDDC6"]
        case .lavenderHaze:
            return ["#F4EDFB", "#D9C5F0", "#9C7BD2"]
        case .peachCream:
            return ["#FFF4EA", "#FFD9B7", "#F5A878"]
        case .copperGlow:
            return ["#FFE5C2", "#E89A4D", "#7C3D14"]
        case .forestStudio:
            return ["#EEF6EE", "#B6D5B7", "#3F6B40"]
        case .slateNoir:
            return ["#202325", "#15181A", "#0A0B0C"]
        case .onyxHero:
            return ["#0B0B0F", "#1A1A22", "#3A3A48"]
        case .obsidianRadial:
            return ["#000000", "#1F1F28", "#3D3D55"]
        case .gradientPalette:
            return ["#FFF1B6", "#FFB36B", "#FF6F4D", "#C9255A"]
        case .berryDuotone:
            return ["#1B0F25", "#5A1E5B", "#C7458C"]
        case .neonNight:
            return ["#02021A", "#1F1366", "#7E5BFF", "#F857A6"]
        case .galaxyHalo:
            return ["#02030C", "#1B1B5C", "#6C5CE7", "#FAB1A0"]
        case .auroraDiagonal:
            return ["#0E5C4F", "#28C7A6", "#7EE8C2", "#FFE3B0"]
        case .gildedFloor:
            return ["#FFF7E2", "#F5DEA3", "#C2922F"]
        case .retailMatte:
            return ["#FAFAFA", "#E0E0E0", "#BFBFBF"]
        case .craftPaper:
            return ["#F4E4C1", "#E2C99B", "#B89968"]
        case .editorialPearl:
            return ["#FFFFFF", "#F0F1F5", "#D9DDE6"]
        case .shopFloorNeutral:
            return ["#EFEFEF", "#D6D6D6", "#ABABAB"]
        case .winterMist:
            return ["#EAF3FF", "#CFE0FF", "#7A9BCF"]
        case .springDew:
            return ["#F5FFF8", "#E2FCE3", "#9ED4A8"]
        case .marketplaceAmber:
            return ["#FFF6E8", "#F5E0C2", "#D9A66E"]
        case .listingNoir:
            return ["#0D0D12", "#242430", "#5C5C70"]
        }
    }

    /// Categorical grouping for the picker UI.
    var category: BackgroundQuickPresetCategory {
        switch self {
        case .catalogWhite, .porcelain, .linenSoft, .parisGray, .retailMatte, .craftPaper, .marbleHero:
            return .clean
        case .studioMist, .warmSeamless, .steelMono, .iceRadial, .sandLinear, .warmFloor, .shelfRetail, .champagneFloor:
            return .studio
        case .sageBackdrop, .mintFresh, .roseQuartz, .peachCream, .lavenderHaze, .skyMint, .oceanFade, .copperGlow, .forestStudio:
            return .colorful
        case .midnightHalo, .duotoneInk, .slateNoir, .onyxHero, .obsidianRadial, .berryDuotone, .neonNight, .galaxyHalo, .gildedFloor, .listingNoir:
            return .premium
        case .sunsetDiagonal, .auroraDiagonal, .gradientPalette:
            return .gradient
        case .editorialPearl, .shopFloorNeutral, .marketplaceAmber:
            return .marketplace
        case .winterMist, .springDew:
            return .seasonal
        }
    }
}

enum BackgroundQuickPresetCategory: String, CaseIterable, Identifiable {
    case clean = "Clean & Catalog"
    case studio = "Studio"
    case colorful = "Colorful"
    case gradient = "Gradient"
    case premium = "Premium / Hero"
    case marketplace = "Marketplace"
    case seasonal = "Seasonal"

    var id: String { rawValue }
}

enum ProductAngle: String, CaseIterable, Identifiable, Hashable {
    case none = "Standard"
    case front = "Front"
    case back = "Back"
    case side1 = "Side 1"
    case side2 = "Side 2"

    var id: String { rawValue }

    /// Legacy filename suffix (older sessions). New multi-angle captures use numeric `-1`, `-2`, … via `multiAngleOrdinal`.
    var suffix: String {
        switch self {
        case .none: return ""
        case .front: return "-front"
        case .back: return "-back"
        case .side1: return "-side1"
        case .side2: return "-side2"
        }
    }

    /// Short badge label for queue rows.
    var badgeTitle: String {
        switch self {
        case .none: return ""
        case .front: return "Front"
        case .back: return "Back"
        case .side1: return "Side 1"
        case .side2: return "Side 2"
        }
    }

    static let captureAngles: [ProductAngle] = [.front, .back, .side1, .side2]
}

// MARK: - Manual tone (Lightroom-lite)

/// Non-destructive tone row applied after polish / auto-enhance and before Style filters.
struct ManualToneAdjustments: Equatable, Hashable, Codable {
    var exposure: Double
    var contrast: Double
    var highlights: Double
    var shadows: Double
    var vibrance: Double
    var warmth: Double

    static let neutral = ManualToneAdjustments(
        exposure: 0, contrast: 0, highlights: 0, shadows: 0, vibrance: 0, warmth: 0
    )

    var isNeutral: Bool { self == .neutral }

    init(
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        vibrance: Double = 0,
        warmth: Double = 0
    ) {
        self.exposure = min(2, max(-2, exposure))
        self.contrast = min(1, max(-1, contrast))
        self.highlights = min(1, max(-1, highlights))
        self.shadows = min(1, max(-1, shadows))
        self.vibrance = min(1, max(-1, vibrance))
        self.warmth = min(1, max(-1, warmth))
    }
}

// MARK: - Product Model

struct CapturedProduct: Identifiable {
    let id: UUID
    let sequence: Int
    let upc: String
    let angle: ProductAngle
    /// 1-based capture order for multi-angle sets (`upc-1.jpg`). 0 = legacy / single-angle naming.
    let multiAngleOrdinal: Int
    let image: UIImage
    let originalImage: UIImage
    /// Pristine, never-recompressed source bitmap. Every adjustment / background fill is rendered
    /// from this so repeated edits never accumulate generational blur. Defaults to `originalImage`.
    let uncompressedOriginalImage: UIImage
    let capturedAt: Date
    let backgroundRemoved: Bool
    let duplicateCopyIndex: Int
    let polishEnabled: Bool
    let enhancementMode: PhotoEnhancementMode
    let studioAIStrength: StudioAIStrength
    let canvasWidth: Int
    let canvasHeight: Int
    let rotationDegrees: Double
    let flipHorizontal: Bool
    let flipVertical: Bool
    let photoFilter: ExportPhotoFilter
    let photoFilterIntensity: Double
    /// Core Image auto-adjustment chain (public `CIImage.autoAdjustmentFilters`) — best-effort vs Photos “Auto”.
    let adjustAutoEnhance: Bool
    /// Lightroom-lite tone row (exposure / contrast / highlights / shadows / vibrance / warmth).
    let toneAdjustments: ManualToneAdjustments
    /// Cutout edge feather 0…1 (0 = hard Vision edge, 1 = soft studio matte).
    let cutoutFeather: Double
    /// Optional grayscale brush mask (PNG) multiplied into the Vision cutout mask. White = keep, black = remove.
    let cutoutBrushMaskData: Data?
    /// Soft synthetic studio shadow under the cutout (after background removal).
    let studioShadow: SoftSyntheticShadowSettings
    let preUpscaleCanvasWidth: Int?
    let preUpscaleCanvasHeight: Int?
    let preUpscaleEnhancementMode: PhotoEnhancementMode?
    let preUpscaleStudioAIStrength: StudioAIStrength?
    let fillRatio: Double
    let backgroundColor: UIColor
    let secondaryBackgroundColor: UIColor
    let backgroundStyle: BackgroundCanvasStyle
    let gradientColorHexes: [String]
    /// Full PowerPoint-style fill (stops, transparency, type, direction). Nil for legacy sessions.
    let backgroundFillData: Data?
    /// Legacy flag: true if a since-removed upscale pass was applied to this item in an
    /// older app version. Drives the "Remove upscale (descale)" action for old sessions.
    let upscaled: Bool
    /// True when this queue item is a multi-product grouped cover composite.
    let isCompositeBundle: Bool
    /// JSON-encoded `CompositeBundleLayout` for grouped cover items.
    let compositeLayoutData: Data?
    /// When true, skip session Brand Mark on this item even if Brand Mark is enabled globally.
    let suppressBrandMark: Bool

    var resolvedBackgroundFillSpec: BackgroundFillSpec {
        BackgroundFillSpec.decoded(from: backgroundFillData)
            ?? BackgroundFillSpec.fromLegacy(style: backgroundStyle, hexes: gradientColorHexes)
    }

    /// Largest canvas edge (used for upscale math and legacy display).
    var canvasSize: Int { max(canvasWidth, canvasHeight) }

    var compositeBundleLayout: CompositeBundleLayout? {
        CompositeBundleLayout.decoded(from: compositeLayoutData)
    }

    /// Grouped cover when flagged or layout JSON is present (covers legacy/partial metadata).
    var isGroupedCoverItem: Bool {
        isCompositeBundle || compositeBundleLayout != nil
    }

    init(
        id: UUID = UUID(),
        sequence: Int,
        upc: String,
        angle: ProductAngle,
        multiAngleOrdinal: Int = 0,
        image: UIImage,
        originalImage: UIImage,
        uncompressedOriginalImage: UIImage? = nil,
        capturedAt: Date = Date(),
        backgroundRemoved: Bool,
        duplicateCopyIndex: Int = 1,
        polishEnabled: Bool = true,
        enhancementMode: PhotoEnhancementMode = .standardClean,
        studioAIStrength: StudioAIStrength = CatalogProcessingBaseline.strength,
        canvasWidth: Int = 1200,
        canvasHeight: Int = 1200,
        rotationDegrees: Double = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        photoFilter: ExportPhotoFilter = .none,
        photoFilterIntensity: Double = 1.0,
        adjustAutoEnhance: Bool = false,
        toneAdjustments: ManualToneAdjustments = .neutral,
        cutoutFeather: Double = 0.35,
        cutoutBrushMaskData: Data? = nil,
        studioShadow: SoftSyntheticShadowSettings = .studioDefault,
        preUpscaleCanvasWidth: Int? = nil,
        preUpscaleCanvasHeight: Int? = nil,
        preUpscaleEnhancementMode: PhotoEnhancementMode? = nil,
        preUpscaleStudioAIStrength: StudioAIStrength? = nil,
        fillRatio: Double = 0.95,
        backgroundColor: UIColor = .white,
        secondaryBackgroundColor: UIColor = UIColor(white: 0.96, alpha: 1.0),
        backgroundStyle: BackgroundCanvasStyle = .solid,
        gradientColorHexes: [String] = ["#FFFFFF"],
        backgroundFillData: Data? = nil,
        upscaled: Bool = false,
        isCompositeBundle: Bool = false,
        compositeLayoutData: Data? = nil,
        suppressBrandMark: Bool = false
    ) {
        self.id = id
        self.sequence = sequence
        self.upc = upc
        self.angle = angle
        self.multiAngleOrdinal = max(0, multiAngleOrdinal)
        self.image = image
        self.originalImage = originalImage
        self.uncompressedOriginalImage = uncompressedOriginalImage ?? originalImage
        self.capturedAt = capturedAt
        self.backgroundRemoved = backgroundRemoved
        self.duplicateCopyIndex = max(1, duplicateCopyIndex)
        self.polishEnabled = polishEnabled
        self.enhancementMode = enhancementMode
        self.studioAIStrength = studioAIStrength
        self.canvasWidth = max(100, canvasWidth)
        self.canvasHeight = max(100, canvasHeight)
        self.rotationDegrees = rotationDegrees
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.photoFilter = photoFilter
        self.photoFilterIntensity = min(1, max(0, photoFilterIntensity))
        self.adjustAutoEnhance = adjustAutoEnhance
        self.toneAdjustments = toneAdjustments
        self.cutoutFeather = min(1, max(0, cutoutFeather))
        self.cutoutBrushMaskData = cutoutBrushMaskData
        self.studioShadow = studioShadow.clamped()
        self.preUpscaleCanvasWidth = preUpscaleCanvasWidth
        self.preUpscaleCanvasHeight = preUpscaleCanvasHeight
        self.preUpscaleEnhancementMode = preUpscaleEnhancementMode
        self.preUpscaleStudioAIStrength = preUpscaleStudioAIStrength
        self.fillRatio = fillRatio
        self.backgroundColor = backgroundColor
        self.secondaryBackgroundColor = secondaryBackgroundColor
        self.backgroundStyle = backgroundStyle
        self.gradientColorHexes = gradientColorHexes
        self.backgroundFillData = backgroundFillData
        self.upscaled = upscaled
        self.isCompositeBundle = isCompositeBundle
        self.compositeLayoutData = compositeLayoutData
        self.suppressBrandMark = suppressBrandMark
    }

    var filename: String {
        FileNameRules.strictJPGName(
            baseName: upc,
            angle: angle,
            duplicateCopyIndex: duplicateCopyIndex,
            multiAngleOrdinal: multiAngleOrdinal
        )
    }

    func filename(for namingMode: ImageNamingMode, format: ExportImageFormat = .jpg) -> String {
        FileNameRules.strictImageName(
            baseName: FileNameRules.baseName(for: self, namingMode: namingMode),
            angle: angle,
            duplicateCopyIndex: duplicateCopyIndex,
            format: format,
            multiAngleOrdinal: multiAngleOrdinal
        )
    }

    func identifierPrefix(for namingMode: ImageNamingMode, format: ExportImageFormat = .jpg) -> String {
        let name = filename(for: namingMode, format: format)
        return String(name.dropLast(4))
    }

    /// Shared 1×1 sentinel — originals evicted from RAM after disk persist still decode from disk on demand.
    static let diskBackedOriginalPlaceholder: UIImage = {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }()

    /// True when full-resolution originals were written to disk and released from RAM.
    var isOriginalEvicted: Bool {
        originalImage === Self.diskBackedOriginalPlaceholder
    }

    /// True when the processed display bitmap was released and must be reloaded from `proc_*.jpg`.
    var isProcessedEvicted: Bool {
        image === Self.diskBackedOriginalPlaceholder
    }

    func withOriginalImages(_ original: UIImage, uncompressed: UIImage? = nil) -> CapturedProduct {
        CapturedProduct(
            id: id,
            sequence: sequence,
            upc: upc,
            angle: angle,
            multiAngleOrdinal: multiAngleOrdinal,
            image: image,
            originalImage: original,
            uncompressedOriginalImage: uncompressed ?? original,
            capturedAt: capturedAt,
            backgroundRemoved: backgroundRemoved,
            duplicateCopyIndex: duplicateCopyIndex,
            polishEnabled: polishEnabled,
            enhancementMode: enhancementMode,
            studioAIStrength: studioAIStrength,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            photoFilter: photoFilter,
            photoFilterIntensity: photoFilterIntensity,
            adjustAutoEnhance: adjustAutoEnhance,
            toneAdjustments: toneAdjustments,
            cutoutFeather: cutoutFeather,
            cutoutBrushMaskData: cutoutBrushMaskData,
            studioShadow: studioShadow,
            preUpscaleCanvasWidth: preUpscaleCanvasWidth,
            preUpscaleCanvasHeight: preUpscaleCanvasHeight,
            preUpscaleEnhancementMode: preUpscaleEnhancementMode,
            preUpscaleStudioAIStrength: preUpscaleStudioAIStrength,
            fillRatio: fillRatio,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: backgroundStyle,
            gradientColorHexes: gradientColorHexes,
            backgroundFillData: backgroundFillData,
            upscaled: upscaled,
            isCompositeBundle: isCompositeBundle,
            compositeLayoutData: compositeLayoutData,
            suppressBrandMark: suppressBrandMark
        )
    }

    /// Replaces only the processed display bitmap — preserves fill, composite, and original metadata.
    func replacingProcessedImage(_ newImage: UIImage) -> CapturedProduct {
        CapturedProduct(
            id: id,
            sequence: sequence,
            upc: upc,
            angle: angle,
            multiAngleOrdinal: multiAngleOrdinal,
            image: newImage,
            originalImage: originalImage,
            uncompressedOriginalImage: uncompressedOriginalImage,
            capturedAt: capturedAt,
            backgroundRemoved: backgroundRemoved,
            duplicateCopyIndex: duplicateCopyIndex,
            polishEnabled: polishEnabled,
            enhancementMode: enhancementMode,
            studioAIStrength: studioAIStrength,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            photoFilter: photoFilter,
            photoFilterIntensity: photoFilterIntensity,
            adjustAutoEnhance: adjustAutoEnhance,
            toneAdjustments: toneAdjustments,
            cutoutFeather: cutoutFeather,
            cutoutBrushMaskData: cutoutBrushMaskData,
            studioShadow: studioShadow,
            preUpscaleCanvasWidth: preUpscaleCanvasWidth,
            preUpscaleCanvasHeight: preUpscaleCanvasHeight,
            preUpscaleEnhancementMode: preUpscaleEnhancementMode,
            preUpscaleStudioAIStrength: preUpscaleStudioAIStrength,
            fillRatio: fillRatio,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: backgroundStyle,
            gradientColorHexes: gradientColorHexes,
            backgroundFillData: backgroundFillData,
            upscaled: upscaled,
            isCompositeBundle: isCompositeBundle,
            compositeLayoutData: compositeLayoutData,
            suppressBrandMark: suppressBrandMark
        )
    }

    func evictingOriginalFromMemory() -> CapturedProduct {
        guard !isOriginalEvicted else { return self }
        let placeholder = Self.diskBackedOriginalPlaceholder
        return withOriginalImages(placeholder, uncompressed: placeholder)
    }

    func evictingProcessedFromMemory() -> CapturedProduct {
        guard !isProcessedEvicted else { return self }
        return replacingProcessedImage(Self.diskBackedOriginalPlaceholder)
    }
}

/// Resolves queue bitmaps — prefers in-memory originals, falls back to disk after capture persist eviction.
enum QueueImageResolver {
    static func uncompressedOriginal(for product: CapturedProduct, fallbackToProcessed: Bool = true) -> UIImage? {
        if !product.isOriginalEvicted {
            return product.uncompressedOriginalImage
        }
        if let fromDisk = SessionDiskStore.loadOriginalImage(id: product.id) {
            return fromDisk
        }
        return fallbackToProcessed ? product.image : nil
    }

    static func uncompressedOriginal(for product: CapturedProduct, fallbackToProcessed: Bool = true) async -> UIImage? {
        if !product.isOriginalEvicted {
            return product.uncompressedOriginalImage
        }
        let fromDisk = await Task.detached(priority: .utility) {
            autoreleasepool { SessionDiskStore.loadOriginalImage(id: product.id) }
        }.value
        if let fromDisk { return fromDisk }
        return fallbackToProcessed ? product.image : nil
    }

    /// Original capture for re-export / reprocess — never returns the 1×1 RAM placeholder.
    static func reliableOriginalForReprocess(_ product: CapturedProduct) -> UIImage? {
        if let fromDisk = SessionDiskStore.loadOriginalImage(id: product.id),
           ImageProcessor.isValidExportBitmap(fromDisk) {
            return fromDisk
        }
        if !product.isOriginalEvicted,
           ImageProcessor.isValidExportBitmap(product.uncompressedOriginalImage) {
            return product.uncompressedOriginalImage
        }
        return nil
    }

    /// Display / export bitmap — reloads from disk after memory-pressure eviction.
    static func processedDisplay(for product: CapturedProduct) -> UIImage {
        if !product.isProcessedEvicted { return product.image }
        if let fromDisk = SessionDiskStore.loadProcessedImage(id: product.id) {
            return fromDisk
        }
        return product.image
    }

    static func processedDisplay(for product: CapturedProduct) async -> UIImage {
        if !product.isProcessedEvicted { return product.image }
        let fromDisk = await Task.detached(priority: .utility) {
            autoreleasepool { SessionDiskStore.loadProcessedImage(id: product.id) }
        }.value
        return fromDisk ?? product.image
    }

    /// Pixel dimensions without decoding the full original bitmap (used for layout math when evicted).
    static func sourcePixelSize(for product: CapturedProduct) -> CGSize {
        if !product.isOriginalEvicted {
            return product.uncompressedOriginalImage.size
        }
        if let url = SessionDiskStore.originalImageFileURL(for: product.id),
           let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
           w > 0, h > 0 {
            return CGSize(width: w, height: h)
        }
        return product.image.size
    }
}

enum BarcodeCanonicalForm {
    /// GTIN check digit validation (UPC/EAN/GTIN-14).
    static func isValidGTINCheckDigit(_ digits: String) -> Bool {
        let values = digits.compactMap { Int(String($0)) }
        guard values.count == digits.count, values.count >= 8 else { return false }
        let checkDigit = values.last!
        let body = values.dropLast().reversed()
        var sum = 0
        for (index, digit) in body.enumerated() {
            sum += digit * (index % 2 == 0 ? 3 : 1)
        }
        let calculated = (10 - (sum % 10)) % 10
        return calculated == checkDigit
    }

    /// Digits as printed on the product label (text-safe string, never parsed as Int).
    ///
    /// UPC-A barcodes are often returned as 13-digit EAN-13 with a leading `0` compatibility prefix.
    /// That extra zero is not printed on US retail labels — strip it so filenames and CSV match the package.
    static func labelDigits(from digits: String, symbology: String? = nil) -> String {
        guard !digits.isEmpty else { return digits }
        let sym = symbology?.uppercased() ?? ""

        if digits.count == 13 && digits.hasPrefix("0") {
            let upcA = String(digits.dropFirst())
            if upcA.count == 12, isValidGTINCheckDigit(upcA) {
                return upcA
            }
        }

        // UPC-E on the package is the compressed symbol — keep scanned length (6/7/8), not expanded GTIN.
        if sym.contains("UPCE") || sym.contains("UPC-E") {
            return digits
        }

        return digits
    }

    /// Validates and returns canonical label digits for scanner output.
    static func canonicalProductCode(from raw: String, symbology: String? = nil) -> String? {
        let digits = raw.filter(\.isNumber)
        guard [8, 12, 13, 14].contains(digits.count) else { return nil }
        guard isValidGTINCheckDigit(digits) else { return nil }
        return labelDigits(from: digits, symbology: symbology)
    }

    /// Normalizes manual or scanned input for storage (preserves exact label text as a String).
    static func normalizeForStorage(_ raw: String, symbology: String? = nil) -> String {
        if let canonical = canonicalProductCode(from: raw, symbology: symbology) {
            return canonical
        }
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if [8, 12, 13, 14].contains(digits.count), isValidGTINCheckDigit(digits) {
            return labelDigits(from: digits, symbology: symbology)
        }
        return digits
    }
}

enum FileNameRules {
    /// Sanitized bundle display name for automatic import / random filenames (no spaces).
    static var appFilenamePrefix: String {
        let raw =
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "ProductStudioPro"
        let allowed = CharacterSet.alphanumerics
        let folded = raw.folding(options: .diacriticInsensitive, locale: .current)
        let cleaned = String(
            folded.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        )
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = cleaned.isEmpty ? "ProductStudio" : cleaned
        return String(base.prefix(24))
    }

    /// True when `upc` holds an auto-generated base name from this app or the legacy `IMG_` scheme.
    static func isAutoGeneratedImportBaseName(_ upc: String) -> Bool {
        if upc.hasPrefix("IMG_") { return true }
        if upc.hasPrefix("\(importAutoNamePrefix)_") { return true }
        // Legacy prefix derived from the full app display name (e.g. Product-Studio-Pro_…).
        let legacy = appFilenamePrefix + "_"
        return upc.hasPrefix(legacy)
    }

    /// ERP-safe filename rule. Prevents accidental double extensions, spaces, and unsafe characters.
    static func angleFileSuffix(angle: ProductAngle, multiAngleOrdinal: Int) -> String {
        if multiAngleOrdinal > 0 { return "-\(multiAngleOrdinal)" }
        return angle.suffix
    }

    static func strictImageName(
        baseName: String,
        angle: ProductAngle,
        duplicateCopyIndex: Int = 1,
        format: ExportImageFormat,
        multiAngleOrdinal: Int = 0
    ) -> String {
        var cleaned = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: ".jpeg", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: ".jpg", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: ".png", with: "", options: .caseInsensitive)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        cleaned = String(cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        while cleaned.contains("--") { cleaned = cleaned.replacingOccurrences(of: "--", with: "-") }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-_")).isEmpty ? randomNativeName() : cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        let copySuffix = duplicateCopyIndex > 1 ? "-copy\(duplicateCopyIndex)" : ""
        let anglePart = angleFileSuffix(angle: angle, multiAngleOrdinal: multiAngleOrdinal)
        return "\(cleaned)\(anglePart)\(copySuffix).\(format.fileExtension)"
    }

    /// ERP-safe filename rule. Always `.jpg` only.
    static func strictJPGName(baseName: String, angle: ProductAngle, duplicateCopyIndex: Int = 1, multiAngleOrdinal: Int = 0) -> String {
        strictImageName(baseName: baseName, angle: angle, duplicateCopyIndex: duplicateCopyIndex, format: .jpg, multiAngleOrdinal: multiAngleOrdinal)
    }

    /// ERP-safe filename rule. Always `.png` only.
    static func strictPNGName(baseName: String, angle: ProductAngle, duplicateCopyIndex: Int = 1, multiAngleOrdinal: Int = 0) -> String {
        strictImageName(baseName: baseName, angle: angle, duplicateCopyIndex: duplicateCopyIndex, format: .png, multiAngleOrdinal: multiAngleOrdinal)
    }

    /// Short prefix for auto-generated import / random filenames (`PSP_20260804_205803_739`).
    static let importAutoNamePrefix = "PSP"

    static func randomNativeName() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return "\(importAutoNamePrefix)_\(df.string(from: Date()))"
    }

    /// User-entered queue label — UPC, SKU, or any custom text. No check-digit validation.
    static func captureLabel(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let canonical = BarcodeCanonicalForm.canonicalProductCode(from: trimmed) {
            return canonical
        }

        let digitsOnly = trimmed.filter(\.isNumber)
        if digitsOnly.count >= 3, trimmed.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
            return BarcodeCanonicalForm.labelDigits(from: digitsOnly)
        }

        var cleaned = trimmed
        for ext in [".jpeg", ".jpg", ".png"] {
            if cleaned.lowercased().hasSuffix(ext) {
                cleaned = String(cleaned.dropLast(ext.count))
            }
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        cleaned = String(cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        while cleaned.contains("--") { cleaned = cleaned.replacingOccurrences(of: "--", with: "-") }
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
    }

    /// Unique grouped-cover name: `PS_CoverPhoto_yyyyMMdd_HHmmss`
    static func generatedGroupedCoverName(date: Date = Date()) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyyMMdd_HHmmss"
        return "PS_CoverPhoto_\(df.string(from: date))"
    }

    static func baseName(for product: CapturedProduct, namingMode: ImageNamingMode) -> String {
        switch namingMode {
        case .scannedUPC:
            let trimmed = product.upc.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? randomNativeName() : trimmed
        case .randomName:
            // Keep already random names stable across re-export.
            if isAutoGeneratedImportBaseName(product.upc) { return product.upc }
            return randomNativeName()
        case .manualInput:
            let cleaned = product.upc.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? randomNativeName() : cleaned
        }
    }
}


// MARK: - Histogram & clipping (preview / quality)

struct ExposureHistogramSnapshot: Sendable {
    let bins: [Int]
    /// Fraction of pixels nearly clipped to black (very low luminance).
    let shadowClipFraction: Double
    /// Fraction nearly clipped to white (very high luminance).
    let highlightClipFraction: Double

    var hasShadowClipping: Bool { shadowClipFraction > 0.012 }
    var hasHighlightClipping: Bool { highlightClipFraction > 0.012 }
}

enum ExposureHistogramAnalyzer {
    /// 32-bin luminance histogram plus simple highlight/shadow clipping estimates (0…1 scale).
    static func analyze(_ image: UIImage) -> ExposureHistogramSnapshot {
        guard let cg = ImageProcessor.normalizedCGImage(image) else {
            return ExposureHistogramSnapshot(bins: Array(repeating: 0, count: 32), shadowClipFraction: 0, highlightClipFraction: 0)
        }
        let target = 96
        let width = target
        let height = max(1, Int(Double(cg.height) / Double(max(cg.width, 1)) * Double(target)))
        let bpp = 4
        let row = width * bpp
        var pixels = [UInt8](repeating: 0, count: height * row)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: row, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return ExposureHistogramSnapshot(bins: Array(repeating: 0, count: 32), shadowClipFraction: 0, highlightClipFraction: 0)
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var bins = [Int](repeating: 0, count: 32)
        var shadowPx = 0, highlightPx = 0, total = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = y * row + x * bpp
                let r = Double(pixels[i]) / 255.0
                let g = Double(pixels[i + 1]) / 255.0
                let b = Double(pixels[i + 2]) / 255.0
                let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let li = min(31, max(0, Int(l * 32.0)))
                bins[li] += 1
                total += 1
                if l < 0.02 { shadowPx += 1 }
                if l > 0.985 { highlightPx += 1 }
            }
        }
        let t = Double(max(1, total))
        return ExposureHistogramSnapshot(
            bins: bins,
            shadowClipFraction: Double(shadowPx) / t,
            highlightClipFraction: Double(highlightPx) / t
        )
    }
}

// MARK: - Adaptive Apple Native Pro Engine

struct AdaptiveImageProfile {
    let averageBrightness: Double
    let contrast: Double
    let blurScore: Double
    let shadowDepth: Double
    let saturation: Double

    var isDark: Bool { averageBrightness < 0.42 }
    var isVeryDark: Bool { averageBrightness < 0.30 }
    var isFlat: Bool { contrast < 0.18 }
    var isAlreadySharp: Bool { blurScore > 0.72 }
    var isSoft: Bool { blurScore < 0.48 }
    var isLowColor: Bool { saturation < 0.16 }
}

// MARK: - Session Store

struct ActiveImportState: Equatable {
    var completed: Int
    var total: Int
    var message: String
}

enum ExportChannelProfile: String, CaseIterable, Identifiable {
    case custom
    case amazon
    case shopify
    case walmart

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .custom: return "Custom (use Settings below)"
        case .amazon: return "Amazon-style (2000×2000)"
        case .shopify: return "Shopify-style (2048×2048)"
        case .walmart: return "Walmart-style (2048×2048)"
        }
    }

    var settingsGuidanceText: String {
        switch self {
        case .custom:
            return "Use your canvas size, fill, and JPG quality below."
        case .amazon:
            return "Sets 2000×2000, ~92% fill, ~86% JPG, compress on — marketplace-style packaging."
        case .shopify:
            return "Sets 2048×2048, ~94% fill, ~88% JPG, compress on — storefront-ready squares."
        case .walmart:
            return "Sets 2048×2048, ~93% fill, ~90% JPG, compress on — larger catalog squares."
        }
    }
}

struct LookPresetSlot: Codable, Equatable {
    var name: String
    var styleRaw: String
    var primaryHex: String
    var secondaryHex: String
    var gradientHexes: [String]
}

struct MemoryGuidancePresentation: Identifiable, Equatable {
    let id: UUID
    let snapshot: MemoryPressureSnapshot
    let isBlocking: Bool

    init(snapshot: MemoryPressureSnapshot, isBlocking: Bool) {
        self.id = UUID()
        self.snapshot = snapshot
        self.isBlocking = isBlocking
    }
}

@MainActor
final class CaptureSessionStore: ObservableObject {
    private enum DefaultsKey {
        static let imageNamingMode = "imageNamingMode"
        static let multiAngleEnabled = "multiAngleEnabled"
        static let enabledAngles = "enabledAngles"
        static let vibrateEnabled = "vibrateEnabled"
        static let beepEnabled = "beepEnabled"
        static let autoBackgroundRemoval = "autoBackgroundRemoval"
        static let subjectLiftEnabledInPreview = SubjectLiftSafety.preferenceKey
        static let outputCanvasSize = "outputCanvasSize"
        static let outputCanvasWidth = "outputCanvasWidth"
        static let outputCanvasHeight = "outputCanvasHeight"
        static let outputFillRatio = "outputFillRatio"
        static let compressBeforeShare = "compressBeforeShare"
        static let jpegQuality = "jpegQuality"
        static let lastUsedUPC = "lastUsedUPC"
        static let barcodeHistory = "barcodeHistory"
        static let preferredCameraDevice = "preferredCameraDevice"
        static let preferredCameraFlashMode = "preferredCameraFlashMode"
        static let preferredCameraSettingsJSON = "preferredCameraSettingsJSON"
        static let batchAutoOpenCamera = "batchAutoOpenCamera"
        static let hasBatchAutoOpenPreference = "hasBatchAutoOpenPreference"
        static let hasCompletedFirstLaunch = "hasCompletedFirstLaunch"
        static let resetBackgroundToWhiteOnLaunch = "resetBackgroundToWhiteOnLaunch"
        static let studioPreset = "studioPreset"
        static let legacyWorkflowPreset = "workflowPreset"
    }

    /// Soft limits that keep large sessions responsive without hard-blocking power users.
    enum CatalogSessionLimits {
        static let softQueueCap = 80
        /// Upper bound — live concurrency comes from `MemoryPressureMonitor`.
        static let importConcurrency = 3
        static let maxPhotosPickerSelection = 100
    }

    /// Proactive memory / capacity guidance sheet (bound at app root).
    @Published var memoryGuidance: MemoryGuidancePresentation?

    @Published private(set) var catalogSessions: [NamedCatalogSession] = []
    @Published private(set) var activeCatalogSessionID: UUID = UUID()

    /// Single source of truth for product, image, and project metadata within the active session.
    let metadataManager = MetadataManager()

    var activeCatalogSessionName: String {
        catalogSessions.first(where: { $0.id == activeCatalogSessionID })?.name ?? "Session"
    }

    private var persistWorkItem: DispatchWorkItem?
    private var persistSaveGeneration: UInt64 = 0
    /// While > 0, `products` changes do not schedule disk saves (bulk import coalesces to one write at the end).
    private var sessionPersistenceSuspendDepth = 0
    /// When true, batch end writes manifest + processed JPEGs only (avoids re-encoding every PNG original).
    private var sessionPersistenceProcessedImagesOnly = false

    @Published var products: [CapturedProduct] = [] {
        didSet {
            if sessionPersistenceSuspendDepth > 0 { return }
            schedulePersistToDisk()
            syncMetadataFromProducts()
        }
    }

    private func metadataMarketplaceName() -> String {
        MarketplaceExportProfileID.from(exportChannel: exportChannelProfile).displayName
    }

    private func syncMetadataFromProducts() {
        metadataManager.syncFromCapturedProducts(
            products,
            sessionID: activeCatalogSessionID,
            sessionName: activeCatalogSessionName,
            brandName: brandMarkText,
            marketplace: metadataMarketplaceName()
        )
    }

    private func schedulePersistToDisk(debounce: TimeInterval = 0.45) {
        persistWorkItem?.cancel()
        persistSaveGeneration &+= 1
        let gen = persistSaveGeneration
        let snapshot = products
        let work = DispatchWorkItem { [gen] in
            SessionDiskStore.saveQueue(snapshot, generation: gen)
        }
        persistWorkItem = work
        if debounce <= 0 {
            DispatchQueue.global(qos: .utility).async(execute: work)
        } else {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounce, execute: work)
        }
    }

    private func scheduleProcessedImagesPersistToDisk(debounce: TimeInterval = 0) {
        persistWorkItem?.cancel()
        persistSaveGeneration &+= 1
        let gen = persistSaveGeneration
        let snapshot = products
        let work = DispatchWorkItem {
            SessionDiskStore.saveManifestAndProcessedImages(snapshot, generation: gen)
        }
        persistWorkItem = work
        if debounce <= 0 {
            DispatchQueue.global(qos: .utility).async(execute: work)
        } else {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounce, execute: work)
        }
    }

    /// Immediately persists one queue item (images + manifest) on a background queue — survives crash.
    private func persistQueueItemImmediately(productID: UUID) {
        guard let product = products.first(where: { $0.id == productID }) else { return }
        persistSaveGeneration &+= 1
        let gen = persistSaveGeneration
        let snapshot = products
        SessionDiskStore.appendProductAndManifest(product, allProducts: snapshot, generation: gen) { [weak self] in
            DispatchQueue.main.async {
                self?.evictPersistedOriginalFromMemory(productID: productID)
            }
        }
    }

    /// Immediately snapshots the in-memory queue and writes it off the main thread (never blocks UI).
    func flushPersistenceToDisk() {
        persistWorkItem?.cancel()
        persistSaveGeneration &+= 1
        let gen = persistSaveGeneration
        let snapshot = products
        metadataManager.flushToDisk()
        DispatchQueue.global(qos: .userInitiated).async {
            SessionDiskStore.saveQueueAndWait(snapshot, generation: gen, pruneStaleFiles: true)
        }
    }

    /// Releases full-resolution originals from RAM once the lossless file exists on disk.
    func evictPersistedOriginalFromMemory(productID: UUID) {
        guard let idx = products.firstIndex(where: { $0.id == productID }) else { return }
        let current = products[idx]
        guard !current.isOriginalEvicted else { return }
        guard SessionDiskStore.originalImageFileURL(for: productID) != nil else { return }
        sessionPersistenceSuspendDepth += 1
        products[idx] = current.evictingOriginalFromMemory()
        sessionPersistenceSuspendDepth = max(0, sessionPersistenceSuspendDepth - 1)
    }

    /// Drops every persisted original from RAM — invoked on memory pressure.
    func evictAllPersistedOriginalsFromMemory() {
        sessionPersistenceSuspendDepth += 1
        defer { sessionPersistenceSuspendDepth = max(0, sessionPersistenceSuspendDepth - 1) }
        var changed = false
        products = products.map { product in
            guard !product.isOriginalEvicted,
                  SessionDiskStore.originalImageFileURL(for: product.id) != nil else { return product }
            changed = true
            return product.evictingOriginalFromMemory()
        }
        guard changed else { return }
        StylePreviewThumbnailCache.shared.removeAll()
        QueueRowThumbnailCache.removeAll()
        ImageBackgroundAssetLoader.clearMemoryCaches()
    }

    /// Releases off-screen processed bitmaps (keeps newest `keepCount` in RAM). Disk JPEGs remain.
    func evictStaleProcessedImagesFromMemory(keeping keepCount: Int) {
        let keep = max(0, keepCount)
        sessionPersistenceSuspendDepth += 1
        defer { sessionPersistenceSuspendDepth = max(0, sessionPersistenceSuspendDepth - 1) }
        var changed = false
        products = products.enumerated().map { index, product in
            guard index >= keep else { return product }
            guard !product.isProcessedEvicted else { return product }
            if SessionDiskStore.processedImageFileURL(for: product.id) == nil {
                SessionDiskStore.writeProcessedImage(
                    product.image,
                    for: product.id,
                    reason: "evictStaleProcessedImagesFromMemory.ensureOnDisk"
                )
            }
            guard SessionDiskStore.processedImageFileURL(for: product.id) != nil else { return product }
            changed = true
            return product.evictingProcessedFromMemory()
        }
        if changed {
            StylePreviewThumbnailCache.shared.removeAll()
        }
    }

    /// Reloads a processed bitmap into the queue array (preview / share).
    @discardableResult
    func ensureProcessedImageInMemory(productID: UUID) -> UIImage? {
        guard let idx = products.firstIndex(where: { $0.id == productID }) else { return nil }
        let current = products[idx]
        if !current.isProcessedEvicted { return current.image }
        guard let loaded = SessionDiskStore.loadProcessedImage(id: productID) else { return nil }
        sessionPersistenceSuspendDepth += 1
        products[idx] = current.replacingProcessedImage(loaded)
        sessionPersistenceSuspendDepth = max(0, sessionPersistenceSuspendDepth - 1)
        return loaded
    }

    /// Full purge ladder — caches → originals → off-screen processed → cancel bulk under critical.
    func performMemoryPurge(for level: MemoryPressureLevel) {
        ImageBackgroundAssetLoader.clearMemoryCaches()
        ImageProcessor.clearCutoutCache()
        StylePreviewThumbnailCache.shared.removeAll()
        QueueRowThumbnailCache.removeAll()
        evictAllPersistedOriginalsFromMemory()
        // Evict at every level (including `.normal`) — fast+good profile favors keeping
        // fewer processed bitmaps resident over maximizing in-memory hit rate.
        let keep = level == .critical
            ? max(2, DeviceMemoryTier.current.keepProcessedInMemoryCount / 2)
            : DeviceMemoryTier.current.keepProcessedInMemoryCount
        flushPersistenceToDisk()
        evictStaleProcessedImagesFromMemory(keeping: keep)
        if level == .critical {
            cancelActiveBulkWork()
        }
        refreshMemoryPressure()
    }

    @discardableResult
    func refreshMemoryPressure() -> MemoryPressureSnapshot {
        let resident = MemoryPressureMonitor.estimateQueueResidentBytes(products: products)
        return MemoryPressureMonitor.shared.refresh(
            queueCount: products.count,
            estimatedResidentBytes: resident
        )
    }

    func evaluateCapacityForAdding(_ count: Int) -> CatalogCapacityDecision {
        let resident = MemoryPressureMonitor.estimateQueueResidentBytes(products: products)
        return MemoryPressureMonitor.shared.evaluateAdding(
            count: count,
            currentQueueCount: products.count,
            estimatedResidentBytes: resident
        )
    }

    /// Soft-cap or memory block — optionally presents guidance sheet for caution / block.
    @discardableResult
    func gateAddingPhotos(count: Int, presentGuidanceOnCaution: Bool = true) -> CatalogCapacityDecision {
        let decision = evaluateCapacityForAdding(count)
        switch decision {
        case .allowed:
            break
        case .allowedWithGuidance(let snap):
            if presentGuidanceOnCaution {
                presentMemoryGuidance(snapshot: snap, isBlocking: false)
            }
            performMemoryPurge(for: .caution)
        case .softCapExceeded:
            break
        case .memoryBlocked(let snap):
            performMemoryPurge(for: .critical)
            presentMemoryGuidance(snapshot: snap, isBlocking: true)
        }
        return decision
    }

    func presentMemoryGuidance(snapshot: MemoryPressureSnapshot, isBlocking: Bool) {
        memoryGuidance = MemoryGuidancePresentation(snapshot: snapshot, isBlocking: isBlocking)
    }

    func dismissMemoryGuidance() {
        memoryGuidance = nil
    }

    func wouldExceedSoftQueueCap(adding count: Int) -> Bool {
        products.count + max(0, count) > CatalogSessionLimits.softQueueCap
    }

    /// Single navigation path owned by the session. HomeView binds its `NavigationStack` to this so
    /// any screen can pop back to Home by calling `session.goHome()`.
    @Published var navigationPath = NavigationPath()

    func goHome() {
        navigationPath = NavigationPath()
    }

    /// Pops one step back in the navigation hierarchy.
    func popNavigation() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    @Published var activeImport: ActiveImportState?
    /// Full-screen blocking overlay (spinner) while heavy work runs off the main thread.
    @Published private(set) var blockingOperationDepth: Int = 0
    @Published var blockingOperationMessage: String = "Processing…"
    /// Preview wand overlay — rendered at app root so it stays above sheets.
    @Published var showsMagicPreviewOverlay = false
    @Published var magicPreviewOverlayApplying = false
    @Published var magicPreviewOverlayMessage: String?
    /// True while `ImagePreviewPagerView` is visible (sheet).
    @Published var isPreviewPanelOpen = false

    func pushBlockingOperation(_ message: String = "Processing…") {
        blockingOperationMessage = message
        blockingOperationDepth += 1
    }

    func popBlockingOperation() {
        blockingOperationDepth = max(0, blockingOperationDepth - 1)
    }

    func updateActiveImport(completed: Int, total: Int, message: String) {
        let t = max(1, total)
        activeImport = ActiveImportState(completed: min(max(0, completed), t), total: t, message: message)
    }

    func clearActiveImport() {
        activeImport = nil
    }

    func clearMagicPreviewOverlay() {
        showsMagicPreviewOverlay = false
        magicPreviewOverlayApplying = false
        magicPreviewOverlayMessage = nil
    }

    func setPreviewPanelOpen(_ open: Bool) {
        isPreviewPanelOpen = open
        if !open {
            clearMagicPreviewOverlay()
        }
    }

    func beginSessionPersistenceBatch(processedImagesOnly: Bool = false) {
        sessionPersistenceSuspendDepth += 1
        if processedImagesOnly {
            sessionPersistenceProcessedImagesOnly = true
        }
    }

    func endSessionPersistenceBatch() {
        sessionPersistenceSuspendDepth = max(0, sessionPersistenceSuspendDepth - 1)
        guard sessionPersistenceSuspendDepth == 0 else { return }
        let processedOnly = sessionPersistenceProcessedImagesOnly
        sessionPersistenceProcessedImagesOnly = false
        if processedOnly {
            scheduleProcessedImagesPersistToDisk(debounce: 0)
        } else {
            schedulePersistToDisk(debounce: 0)
        }
    }

    /// Lets SwiftUI paint the blocking overlay before heavy work starts.
    private func yieldUIFrame() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 32_000_000)
    }
    @Published var currentImage: UIImage?
    @Published var currentUPC: String = ""
    @Published var captureMode: CaptureMode = .batch

    @Published var preferredCameraDevice: UIImagePickerController.CameraDevice = {
        UserDefaults.standard.integer(forKey: DefaultsKey.preferredCameraDevice) == 1 ? .front : .rear
    }() {
        didSet { UserDefaults.standard.set(preferredCameraDevice == .front ? 1 : 0, forKey: DefaultsKey.preferredCameraDevice) }
    }

    @Published var preferredCameraFlashMode: UIImagePickerController.CameraFlashMode = {
        switch UserDefaults.standard.integer(forKey: DefaultsKey.preferredCameraFlashMode) {
        case 1: return .on
        case 2: return .off
        default: return .auto
        }
    }() {
        didSet {
            let stored: Int
            switch preferredCameraFlashMode {
            case .on: stored = 1
            case .off: stored = 2
            default: stored = 0
            }
            UserDefaults.standard.set(stored, forKey: DefaultsKey.preferredCameraFlashMode)
        }
    }

    @Published var preferredCameraSettings: CameraSessionSettings = CaptureSessionStore.loadPreferredCameraSettings() {
        didSet { CaptureSessionStore.savePreferredCameraSettings(preferredCameraSettings) }
    }

    /// Camera settings preserved across captures within the current Batch Mode visit.
    @Published var batchCameraSettings: CameraSessionSettings = CaptureSessionStore.loadPreferredCameraSettings()

    @Published var batchAutoOpenCamera: Bool = UserDefaults.standard.bool(forKey: DefaultsKey.batchAutoOpenCamera)

    var hasBatchAutoOpenPreference: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.hasBatchAutoOpenPreference)
    }

    func setBatchAutoOpenPreference(_ preference: BatchAutoOpenCameraPreference) {
        batchAutoOpenCamera = preference == .automatic
        UserDefaults.standard.set(batchAutoOpenCamera, forKey: DefaultsKey.batchAutoOpenCamera)
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasBatchAutoOpenPreference)
    }

    func resetBatchCameraSession() {
        batchCameraSettings = preferredCameraSettings
    }

    func rememberCameraPreferences(from settings: CameraSessionSettings) {
        preferredCameraSettings = settings
        preferredCameraDevice = settings.legacyPickerDevice
        preferredCameraFlashMode = settings.legacyPickerFlash
    }

    func rememberBatchCameraSettings(from settings: CameraSessionSettings) {
        batchCameraSettings.applyLatestSession(settings)
    }

    private static func loadPreferredCameraSettings() -> CameraSessionSettings {
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.preferredCameraSettingsJSON),
           let decoded = try? JSONDecoder().decode(CameraSessionSettings.self, from: data) {
            return decoded
        }
        let device: UIImagePickerController.CameraDevice =
            UserDefaults.standard.integer(forKey: DefaultsKey.preferredCameraDevice) == 1 ? .front : .rear
        let flashRaw = UserDefaults.standard.integer(forKey: DefaultsKey.preferredCameraFlashMode)
        let flash: UIImagePickerController.CameraFlashMode
        switch flashRaw {
        case 1: flash = .on
        case 2: flash = .off
        default: flash = .auto
        }
        return CameraSessionSettings(legacyDevice: device, legacyFlash: flash)
    }

    private static func savePreferredCameraSettings(_ settings: CameraSessionSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.preferredCameraSettingsJSON)
        }
        UserDefaults.standard.set(settings.usesFrontCamera ? 1 : 0, forKey: DefaultsKey.preferredCameraDevice)
        UserDefaults.standard.set(settings.flashMode, forKey: DefaultsKey.preferredCameraFlashMode)
    }

    func rememberCameraPreferences(device: UIImagePickerController.CameraDevice, flash: UIImagePickerController.CameraFlashMode) {
        var settings = preferredCameraSettings
        settings.usesFrontCamera = device == .front
        switch flash {
        case .on: settings.flashMode = 1
        case .off: settings.flashMode = 2
        default: settings.flashMode = 0
        }
        rememberCameraPreferences(from: settings)
    }

    @Published var imageNamingMode: ImageNamingMode = ImageNamingMode(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.imageNamingMode) ?? ImageNamingMode.scannedUPC.rawValue) ?? .scannedUPC {
        didSet { UserDefaults.standard.set(imageNamingMode.rawValue, forKey: DefaultsKey.imageNamingMode) }
    }
    @Published var studioPreset: StudioPresetID = {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.studioPreset)
            ?? UserDefaults.standard.string(forKey: DefaultsKey.legacyWorkflowPreset)
            ?? StudioPresetID.defaultStudio.rawValue
        return StudioPresetID.migrated(from: raw)
    }() {
        didSet {
            UserDefaults.standard.set(studioPreset.rawValue, forKey: DefaultsKey.studioPreset)
        }
    }

    /// Legacy accessor — prefer `studioPreset`.
    var workflowPreset: StudioPresetID {
        get { studioPreset }
        set { studioPreset = newValue }
    }
    @Published var selectedAngle: ProductAngle = .none
    @Published var multiAngleEnabled = UserDefaults.standard.object(forKey: DefaultsKey.multiAngleEnabled) as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(multiAngleEnabled, forKey: DefaultsKey.multiAngleEnabled)
            if multiAngleEnabled {
                selectedAngle = enabledAngles.first ?? .front
            } else {
                selectedAngle = .none
                currentMultiAngleIdentifier = ""
                currentAngleIndex = 0
                clearPendingMultiAngleCaptures()
            }
        }
    }
    @Published var enabledAngles: [ProductAngle] = {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.enabledAngles) ?? ""
        let parsed = raw
            .split(separator: "|")
            .compactMap { ProductAngle(rawValue: String($0)) }
            .filter { $0 != .none }
        return parsed.isEmpty ? ProductAngle.captureAngles : parsed
    }() {
        didSet {
            let cleaned = enabledAngles.filter { $0 != .none }
            if cleaned != enabledAngles {
                enabledAngles = cleaned
                return
            }
            let ordered = cleaned.sorted {
                (ProductAngle.captureAngles.firstIndex(of: $0) ?? Int.max)
                    < (ProductAngle.captureAngles.firstIndex(of: $1) ?? Int.max)
            }
            if ordered != enabledAngles {
                enabledAngles = ordered
                return
            }
            UserDefaults.standard.set(ordered.map(\.rawValue).joined(separator: "|"), forKey: DefaultsKey.enabledAngles)
        }
    }
    @Published var currentAngleIndex: Int = 0
    @Published var currentMultiAngleIdentifier: String = ""
    /// Photos captured for the current multi-angle product before the shared UPC/name is assigned.
    @Published private(set) var pendingMultiAngleCaptures: [PendingMultiAngleCapture] = []

    struct PendingMultiAngleCapture: Identifiable {
        let id: UUID
        let angle: ProductAngle
        let ordinal: Int
        let image: UIImage

        init(id: UUID = UUID(), angle: ProductAngle, ordinal: Int, image: UIImage) {
            self.id = id
            self.angle = angle
            self.ordinal = ordinal
            self.image = image
        }
    }

    @Published var vibrateEnabled = UserDefaults.standard.object(forKey: DefaultsKey.vibrateEnabled) as? Bool ?? true {
        didSet { UserDefaults.standard.set(vibrateEnabled, forKey: DefaultsKey.vibrateEnabled) }
    }
    @Published var beepEnabled = UserDefaults.standard.object(forKey: DefaultsKey.beepEnabled) as? Bool ?? true {
        didSet { UserDefaults.standard.set(beepEnabled, forKey: DefaultsKey.beepEnabled) }
    }

    // User requested: branding OFF by default, but editable in Settings.
    @Published var showBranding: Bool = UserDefaults.standard.object(forKey: "showBranding") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showBranding, forKey: "showBranding") }
    }

    @Published var businessName: String = UserDefaults.standard.string(forKey: "businessName") ?? "" {
        didSet { UserDefaults.standard.set(businessName, forKey: "businessName") }
    }

    @Published var developerLine: String = UserDefaults.standard.string(forKey: "developerLine") ?? "" {
        didSet { UserDefaults.standard.set(developerLine, forKey: "developerLine") }
    }

    // MARK: - Brand Mark (catalog image watermark)

    @Published var brandMarkEnabled: Bool = BrandMarkSettings.configuration.isEnabled {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkText: String = {
        let saved = BrandMarkSettings.configuration.text
        if !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return saved }
        return UserDefaults.standard.string(forKey: "businessName") ?? ""
    }() {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkPosition: BrandMarkPosition = BrandMarkSettings.configuration.position {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkLogoOpacity: Double = BrandMarkSettings.configuration.logoOpacity {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkCaptionPlateOpacity: Double = BrandMarkSettings.configuration.captionPlateOpacity {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkShowText: Bool = BrandMarkSettings.configuration.showText {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkShowLogo: Bool = BrandMarkSettings.configuration.showLogo {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkLogoScale: Double = BrandMarkSettings.configuration.logoScale {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkFontSizePx: Int = BrandMarkSettings.configuration.fontSizePx {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkFontColorHex: String = BrandMarkSettings.configuration.fontColorHex {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkCaptionPlateColorHex: String = BrandMarkSettings.configuration.captionPlateColorHex {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkTextCaptionPlateEnabled: Bool = BrandMarkSettings.configuration.textCaptionPlateEnabled {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkFontStyle: BrandMarkFontStyle = BrandMarkSettings.configuration.fontStyle {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkFontPostScriptName: String? = BrandMarkSettings.configuration.fontPostScriptName {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkLogoFileName: String? = BrandMarkSettings.configuration.logoFileName {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkTextLineWrapEnabled: Bool = BrandMarkSettings.configuration.textLineWrapEnabled {
        didSet { syncBrandMarkSettings() }
    }
    @Published var brandMarkEdgePaddingFraction: Double = BrandMarkSettings.configuration.edgePaddingFraction {
        didSet { syncBrandMarkSettings() }
    }
    @Published var imageNameStampEnabled: Bool = BrandMarkSettings.configuration.imageName.isEnabled {
        didSet {
            if imageNameStampEnabled,
               let blocked = brandMarkOccupiedPosition,
               imageNameStampPosition == blocked {
                imageNameStampPosition = BrandMarkPositionConflict.resolved(
                    imageNameStampPosition,
                    blockedBy: blocked
                )
            }
            syncBrandMarkSettings()
        }
    }
    @Published var imageNameStampPosition: BrandMarkPosition = BrandMarkSettings.configuration.imageName.position {
        didSet { syncBrandMarkSettings() }
    }
    @Published var imageNameStampCaptionPlateOpacity: Double = BrandMarkSettings.configuration.imageName.captionPlateOpacity {
        didSet { syncBrandMarkSettings() }
    }
    @Published var imageNameStampFontSizePx: Int = BrandMarkSettings.configuration.imageName.fontSizePx {
        didSet { syncBrandMarkSettings() }
    }
    @Published var imageNameStampFontColorHex: String = BrandMarkSettings.configuration.imageName.fontColorHex {
        didSet { syncBrandMarkSettings() }
    }
    @Published var imageNameStampCaptionPlateColorHex: String = BrandMarkSettings.configuration.imageName.captionPlateColorHex {
        didSet { syncBrandMarkSettings() }
    }
    @Published var imageNameStampTextCaptionPlateEnabled: Bool = BrandMarkSettings.configuration.imageName.textCaptionPlateEnabled {
        didSet { syncBrandMarkSettings() }
    }
    @Published var imageNameStampFontStyle: BrandMarkFontStyle = BrandMarkSettings.configuration.imageName.fontStyle {
        didSet { syncBrandMarkSettings() }
    }
    @Published var imageNameStampFontPostScriptName: String? = BrandMarkSettings.configuration.imageName.fontPostScriptName {
        didSet { syncBrandMarkSettings() }
    }
    @Published var imageNameStampLineWrapEnabled: Bool = BrandMarkSettings.configuration.imageName.lineWrapEnabled {
        didSet { syncBrandMarkSettings() }
    }
    @Published var imageNameStampEdgePaddingFraction: Double = BrandMarkSettings.configuration.imageName.edgePaddingFraction {
        didSet { syncBrandMarkSettings() }
    }

    /// Bumps when the on-disk logo changes so SwiftUI previews refresh.
    @Published private(set) var brandMarkLogoRevision: Int = 0
    /// Bumps on any Brand Kit setting change so Live canvas always re-stamps.
    @Published private(set) var brandMarkSettingsRevision: Int = 0

    var brandMarkConfiguration: BrandMarkConfiguration {
        BrandMarkConfiguration(
            isEnabled: brandMarkEnabled,
            text: brandMarkText,
            position: brandMarkPosition,
            logoOpacity: brandMarkLogoOpacity,
            captionPlateOpacity: brandMarkCaptionPlateOpacity,
            showText: brandMarkShowText,
            showLogo: brandMarkShowLogo,
            logoScale: brandMarkLogoScale,
            fontSizePx: brandMarkFontSizePx,
            fontColorHex: brandMarkFontColorHex,
            captionPlateColorHex: brandMarkCaptionPlateColorHex,
            textCaptionPlateEnabled: brandMarkTextCaptionPlateEnabled,
            fontStyle: brandMarkFontStyle,
            fontPostScriptName: brandMarkFontPostScriptName,
            logoFileName: brandMarkLogoFileName,
            textLineWrapEnabled: brandMarkTextLineWrapEnabled,
            edgePaddingFraction: brandMarkEdgePaddingFraction,
            imageName: ImageNameStampConfiguration(
                isEnabled: imageNameStampEnabled,
                position: imageNameStampPosition,
                captionPlateOpacity: imageNameStampCaptionPlateOpacity,
                fontSizePx: imageNameStampFontSizePx,
                fontColorHex: imageNameStampFontColorHex,
                captionPlateColorHex: imageNameStampCaptionPlateColorHex,
                textCaptionPlateEnabled: imageNameStampTextCaptionPlateEnabled,
                fontStyle: imageNameStampFontStyle,
                fontPostScriptName: imageNameStampFontPostScriptName,
                lineWrapEnabled: imageNameStampLineWrapEnabled,
                edgePaddingFraction: imageNameStampEdgePaddingFraction
            )
        )
    }

    var brandMarkIsActive: Bool {
        brandMarkConfiguration.shouldRender || imageNameStampEnabled
    }

    /// Position currently claimed by Brand Mark text/logo (nil when not rendering).
    var brandMarkOccupiedPosition: BrandMarkPosition? {
        brandMarkConfiguration.shouldRender ? brandMarkPosition : nil
    }

    /// Position claimed by Image Name when enabled.
    var imageNameOccupiedPosition: BrandMarkPosition? {
        imageNameStampEnabled ? imageNameStampPosition : nil
    }

    private func syncBrandMarkSettings() {
        BrandMarkSettings.configuration = brandMarkConfiguration
        brandMarkSettingsRevision &+= 1
    }

    func applyBrandMarkColorPreset(_ preset: BrandMarkColorPreset) {
        brandMarkFontColorHex = preset.fontColorHex
        brandMarkCaptionPlateColorHex = preset.plateColorHex
        brandMarkCaptionPlateOpacity = BrandMarkOpacityRange.clampPlate(preset.plateOpacity)
        brandMarkTextCaptionPlateEnabled = true
    }

    func applyImageNameColorPreset(_ preset: BrandMarkColorPreset) {
        imageNameStampFontColorHex = preset.fontColorHex
        imageNameStampCaptionPlateColorHex = preset.plateColorHex
        imageNameStampCaptionPlateOpacity = BrandMarkOpacityRange.clampPlate(preset.plateOpacity)
        imageNameStampTextCaptionPlateEnabled = true
    }

    /// Restores Brand Kit controls to app defaults (does not restamp the queue).
    func resetBrandKitToDefaults() {
        let defaults = BrandMarkConfiguration.default
        let keptText = brandMarkText
        let keptLogo = brandMarkLogoFileName
        brandMarkEnabled = defaults.isEnabled
        brandMarkText = keptText.isEmpty ? defaults.text : keptText
        brandMarkPosition = defaults.position
        brandMarkLogoOpacity = defaults.logoOpacity
        brandMarkCaptionPlateOpacity = defaults.captionPlateOpacity
        brandMarkShowText = defaults.showText
        brandMarkShowLogo = defaults.showLogo
        brandMarkLogoScale = defaults.logoScale
        brandMarkFontSizePx = defaults.fontSizePx
        brandMarkFontColorHex = defaults.fontColorHex
        brandMarkCaptionPlateColorHex = defaults.captionPlateColorHex
        brandMarkTextCaptionPlateEnabled = defaults.textCaptionPlateEnabled
        brandMarkFontStyle = defaults.fontStyle
        brandMarkFontPostScriptName = defaults.fontPostScriptName
        brandMarkLogoFileName = keptLogo
        brandMarkTextLineWrapEnabled = defaults.textLineWrapEnabled
        brandMarkEdgePaddingFraction = defaults.edgePaddingFraction
        imageNameStampEnabled = defaults.imageName.isEnabled
        imageNameStampPosition = defaults.imageName.position
        imageNameStampCaptionPlateOpacity = defaults.imageName.captionPlateOpacity
        imageNameStampFontSizePx = defaults.imageName.fontSizePx
        imageNameStampFontColorHex = defaults.imageName.fontColorHex
        imageNameStampCaptionPlateColorHex = defaults.imageName.captionPlateColorHex
        imageNameStampTextCaptionPlateEnabled = defaults.imageName.textCaptionPlateEnabled
        imageNameStampFontStyle = defaults.imageName.fontStyle
        imageNameStampFontPostScriptName = defaults.imageName.fontPostScriptName
        imageNameStampLineWrapEnabled = defaults.imageName.lineWrapEnabled
        imageNameStampEdgePaddingFraction = defaults.imageName.edgePaddingFraction
    }

    func setBrandMarkPosition(_ position: BrandMarkPosition) {
        let blocked = imageNameOccupiedPosition
        brandMarkPosition = BrandMarkPositionConflict.resolved(position, blockedBy: blocked)
        if imageNameStampEnabled, imageNameStampPosition == brandMarkPosition {
            imageNameStampPosition = BrandMarkPositionConflict.resolved(
                imageNameStampPosition,
                blockedBy: brandMarkPosition
            )
        }
    }

    func setImageNameStampPosition(_ position: BrandMarkPosition) {
        let blocked = brandMarkOccupiedPosition
        imageNameStampPosition = BrandMarkPositionConflict.resolved(position, blockedBy: blocked)
        if brandMarkConfiguration.shouldRender, brandMarkPosition == imageNameStampPosition {
            brandMarkPosition = BrandMarkPositionConflict.resolved(
                brandMarkPosition,
                blockedBy: imageNameStampPosition
            )
        }
    }

    func brandKitImageNameText(for product: CapturedProduct) -> String? {
        guard imageNameStampEnabled else { return nil }
        return FileNameRules.baseName(for: product, namingMode: imageNamingMode)
    }

    func brandKitImageNameText(forIdentifier identifier: String) -> String? {
        guard imageNameStampEnabled else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    func importBrandMarkLogo(_ image: UIImage) -> Bool {
        guard let name = BrandMarkLogoStore.saveLogo(image) else { return false }
        brandMarkLogoFileName = name
        brandMarkShowLogo = true
        brandMarkLogoRevision &+= 1
        return true
    }

    func clearBrandMarkLogo() {
        BrandMarkLogoStore.deleteLogo(fileName: brandMarkLogoFileName)
        brandMarkLogoFileName = nil
        brandMarkLogoRevision &+= 1
    }

    @Published var autoBackgroundRemoval = UserDefaults.standard.object(forKey: DefaultsKey.autoBackgroundRemoval) as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoBackgroundRemoval, forKey: DefaultsKey.autoBackgroundRemoval) }
    }
    /// Photos-style Subject Lift in Preview only. Default off — VisionKit analysis is optional and pressure-gated.
    @Published var subjectLiftEnabledInPreview: Bool = UserDefaults.standard.object(forKey: DefaultsKey.subjectLiftEnabledInPreview) as? Bool ?? false {
        didSet { UserDefaults.standard.set(subjectLiftEnabledInPreview, forKey: DefaultsKey.subjectLiftEnabledInPreview) }
    }
    @Published var productPolishEnabled: Bool = UserDefaults.standard.object(forKey: "productPolishEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(productPolishEnabled, forKey: "productPolishEnabled") }
    }
    /// Studio AI removed — always Standard Clean. No UserDefaults picker wiring; kept as `@Published`
    /// only because many call sites still pass it through for API stability.
    @Published var photoEnhancementMode: PhotoEnhancementMode = .standardClean
    /// Vestigial — no longer user-facing or used in polish logic. Kept for API stability only.
    @Published var studioAIStrength: StudioAIStrength = CatalogProcessingBaseline.strength
    /// Default style filter for new captures / imports (Settings-owned; templates do not override).
    @Published var preferredExportPhotoFilter: ExportPhotoFilter = {
        let raw = UserDefaults.standard.string(forKey: "preferredExportPhotoFilter")
        if raw == nil { return .none }
        return ExportPhotoFilter.resolved(from: raw)
    }() {
        didSet { UserDefaults.standard.set(preferredExportPhotoFilter.rawValue, forKey: "preferredExportPhotoFilter") }
    }

    /// Home template currently driving session defaults (`app-defaults` when using baseline).
    @Published var activeCatalogTemplatePackID: String = {
        UserDefaults.standard.string(forKey: "lastCatalogTemplatePackID")
            ?? CatalogTemplateLibrary.appDefaultsID
    }() {
        didSet { UserDefaults.standard.set(activeCatalogTemplatePackID, forKey: "lastCatalogTemplatePackID") }
    }
    @Published var smartColorAccuracyEnabled: Bool = UserDefaults.standard.object(forKey: "smartColorAccuracyEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(smartColorAccuracyEnabled, forKey: "smartColorAccuracyEnabled") }
    }
    @Published var backgroundCanvasStyle: BackgroundCanvasStyle = BackgroundCanvasStyle.fromStored(UserDefaults.standard.string(forKey: "backgroundCanvasStyle")) {
        didSet { UserDefaults.standard.set(backgroundCanvasStyle.rawValue, forKey: "backgroundCanvasStyle") }
    }
    @Published var backgroundColor: UIColor = UIColor(hexString: UserDefaults.standard.string(forKey: "backgroundColorHex") ?? "#FFFFFF") ?? .white {
        didSet { UserDefaults.standard.set(backgroundColor.hexString, forKey: "backgroundColorHex") }
    }
    @Published var secondaryBackgroundColor: UIColor = UIColor(hexString: UserDefaults.standard.string(forKey: "secondaryBackgroundColorHex") ?? "#F0F0F0") ?? UIColor(white: 0.94, alpha: 1.0) {
        didSet { UserDefaults.standard.set(secondaryBackgroundColor.hexString, forKey: "secondaryBackgroundColorHex") }
    }

    @Published var gradientColorHexes: [String] = {
        let saved = UserDefaults.standard.string(forKey: "gradientColorHexes") ?? "#FFFFFF"
        let parts = saved.split(separator: "|").map(String.init).filter { !$0.isEmpty }
        return parts.isEmpty ? ["#FFFFFF"] : parts
    }() {
        didSet {
            if gradientColorHexes.isEmpty { gradientColorHexes = ["#FFFFFF"] }
            UserDefaults.standard.set(gradientColorHexes.joined(separator: "|"), forKey: "gradientColorHexes")
            if let first = gradientColorHexes.first, let color = UIColor(hexString: first) { backgroundColor = color }
            if let last = gradientColorHexes.last, let color = UIColor(hexString: last) { secondaryBackgroundColor = color }
        }
    }
    @Published var outputCanvasWidth: Int = {
        let bounds = CanvasPresetCatalog.dimensionBounds
        let w = UserDefaults.standard.integer(forKey: DefaultsKey.outputCanvasWidth)
        if w > 0 { return min(bounds.upperBound, max(bounds.lowerBound, w)) }
        let legacy = UserDefaults.standard.integer(forKey: DefaultsKey.outputCanvasSize)
        return legacy == 0 ? 1200 : min(bounds.upperBound, max(bounds.lowerBound, legacy))
    }() {
        didSet {
            let bounds = CanvasPresetCatalog.dimensionBounds
            let c = min(bounds.upperBound, max(bounds.lowerBound, outputCanvasWidth))
            if c != outputCanvasWidth { outputCanvasWidth = c; return }
            UserDefaults.standard.set(outputCanvasWidth, forKey: DefaultsKey.outputCanvasWidth)
        }
    }
    @Published var outputCanvasHeight: Int = {
        let bounds = CanvasPresetCatalog.dimensionBounds
        let h = UserDefaults.standard.integer(forKey: DefaultsKey.outputCanvasHeight)
        if h > 0 { return min(bounds.upperBound, max(bounds.lowerBound, h)) }
        let legacy = UserDefaults.standard.integer(forKey: DefaultsKey.outputCanvasSize)
        return legacy == 0 ? 1200 : min(bounds.upperBound, max(bounds.lowerBound, legacy))
    }() {
        didSet {
            let bounds = CanvasPresetCatalog.dimensionBounds
            let c = min(bounds.upperBound, max(bounds.lowerBound, outputCanvasHeight))
            if c != outputCanvasHeight { outputCanvasHeight = c; return }
            UserDefaults.standard.set(outputCanvasHeight, forKey: DefaultsKey.outputCanvasHeight)
        }
    }
    @Published var outputFillRatio = {
        let stored = UserDefaults.standard.double(forKey: DefaultsKey.outputFillRatio)
        if stored == 0 { return 0.95 }
        return min(1.0, max(0.80, stored))
    }() {
        didSet {
            let clamped = min(1.0, max(0.80, outputFillRatio))
            if clamped != outputFillRatio { outputFillRatio = clamped; return }
            UserDefaults.standard.set(outputFillRatio, forKey: DefaultsKey.outputFillRatio)
        }
    }
    @Published var compressBeforeShare = UserDefaults.standard.object(forKey: DefaultsKey.compressBeforeShare) as? Bool ?? true {
        didSet { UserDefaults.standard.set(compressBeforeShare, forKey: DefaultsKey.compressBeforeShare) }
    }
    @Published var jpegQuality = {
        let stored = UserDefaults.standard.double(forKey: DefaultsKey.jpegQuality)
        if stored == 0 { return 0.98 }
        return min(1.0, max(0.85, stored))
    }() {
        didSet { UserDefaults.standard.set(jpegQuality, forKey: DefaultsKey.jpegQuality) }
    }

    /// Prevents profile → custom bounce while applying a channel preset.
    private var isApplyingExportChannelProfile = false

    @Published var exportChannelProfile: ExportChannelProfile = {
        let raw = UserDefaults.standard.string(forKey: "exportChannelProfile") ?? ""
        return ExportChannelProfile(rawValue: raw) ?? .custom
    }() {
        didSet { UserDefaults.standard.set(exportChannelProfile.rawValue, forKey: "exportChannelProfile") }
    }

    /// When on, cold launch restores a white studio background instead of the last saved Settings look.
    @Published var resetBackgroundToWhiteOnLaunch = UserDefaults.standard.object(forKey: DefaultsKey.resetBackgroundToWhiteOnLaunch) as? Bool ?? false {
        didSet { UserDefaults.standard.set(resetBackgroundToWhiteOnLaunch, forKey: DefaultsKey.resetBackgroundToWhiteOnLaunch) }
    }

    @Published var recentBarcodes: [String] = []

    @Published var lastUsedUPC: String = UserDefaults.standard.string(forKey: DefaultsKey.lastUsedUPC) ?? "" {
        didSet { UserDefaults.standard.set(lastUsedUPC, forKey: DefaultsKey.lastUsedUPC) }
    }

    /// In-flight bulk reprocess / upscale / match-look work — cancelled when leaving Queue.
    private var activeBulkTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let firstLaunch = !defaults.bool(forKey: DefaultsKey.hasCompletedFirstLaunch)
        if firstLaunch {
            resetBackgroundStyleToDefaultWhite()
            defaults.set(true, forKey: DefaultsKey.hasCompletedFirstLaunch)
        } else if resetBackgroundToWhiteOnLaunch {
            resetBackgroundStyleToDefaultWhite()
        }
        syncBrandMarkSettings()
        ImageBackgroundAssetLoader.configureCacheLimits()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.performMemoryPurge(for: .critical)
                let snap = self.refreshMemoryPressure()
                if snap.level >= .caution {
                    self.presentMemoryGuidance(snapshot: snap, isBlocking: snap.level == .critical)
                }
            }
        }
        refreshMemoryPressure()

        let restored = SessionDiskStore.restoreActiveSession()
        catalogSessions = restored.sessions
        activeCatalogSessionID = restored.activeID
        if let queue = restored.products {
            sessionPersistenceSuspendDepth += 1
            products = queue
            sessionPersistenceSuspendDepth = max(0, sessionPersistenceSuspendDepth - 1)
        }
        metadataManager.loadSession(
            id: restored.activeID,
            name: activeCatalogSessionName,
            products: products,
            brandName: brandMarkText,
            marketplace: metadataMarketplaceName()
        )
        recentBarcodes = (UserDefaults.standard.string(forKey: DefaultsKey.barcodeHistory) ?? "")
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    // MARK: - Named catalog sessions

    private func persistSessionsIndex() {
        SessionDiskStore.saveSessionsIndex(activeID: activeCatalogSessionID, sessions: catalogSessions)
    }

    private func touchActiveSessionTimestamp() {
        guard let idx = catalogSessions.firstIndex(where: { $0.id == activeCatalogSessionID }) else { return }
        catalogSessions[idx].updatedAt = Date()
        persistSessionsIndex()
    }

    @discardableResult
    func createCatalogSession(named name: String? = nil) -> UUID {
        flushPersistenceToDisk()
        cancelActiveBulkWork()
        let id = UUID()
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label: String
        if let trimmed, !trimmed.isEmpty {
            label = trimmed
        } else {
            label = "Session \(catalogSessions.count + 1)"
        }
        let now = Date()
        let meta = NamedCatalogSession(id: id, name: label, createdAt: now, updatedAt: now)
        catalogSessions.insert(meta, at: 0)
        activeCatalogSessionID = id
        SessionDiskStore.setActiveSessionID(id)
        SessionDiskStore.ensureEmptySessionFolder(sessionID: id)
        metadataManager.initializeEmptySession(id: id, name: label)
        persistSessionsIndex()
        sessionPersistenceSuspendDepth += 1
        products = []
        sessionPersistenceSuspendDepth = max(0, sessionPersistenceSuspendDepth - 1)
        return id
    }

    /// Creates a named folder/session **without** switching away from the current queue.
    @discardableResult
    func createCatalogSessionFolder(named name: String? = nil) -> UUID {
        let id = UUID()
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label: String
        if let trimmed, !trimmed.isEmpty {
            label = trimmed
        } else {
            label = "Session \(catalogSessions.count + 1)"
        }
        let now = Date()
        let meta = NamedCatalogSession(id: id, name: label, createdAt: now, updatedAt: now)
        catalogSessions.insert(meta, at: 0)
        SessionDiskStore.ensureEmptySessionFolder(sessionID: id)
        metadataManager.initializeEmptySession(id: id, name: label)
        persistSessionsIndex()
        return id
    }

    enum MoveProductsError: LocalizedError {
        case emptySelection
        case sameSession
        case softCapExceeded(limit: Int, wouldBe: Int)
        case sessionMissing

        var errorDescription: String? {
            switch self {
            case .emptySelection:
                return "No photos selected."
            case .sameSession:
                return "Photos are already in this folder."
            case .softCapExceeded(let limit, let wouldBe):
                return "That folder would exceed the soft limit of \(limit) photos (would be \(wouldBe))."
            case .sessionMissing:
                return "That folder is no longer available."
            }
        }
    }

    /// Moves selected products into another session folder (leaves the current queue).
    @discardableResult
    func moveProducts(ids: Set<UUID>, toSession targetID: UUID) -> Result<Int, MoveProductsError> {
        guard !ids.isEmpty else { return .failure(.emptySelection) }
        guard targetID != activeCatalogSessionID else { return .failure(.sameSession) }
        guard catalogSessions.contains(where: { $0.id == targetID }) else { return .failure(.sessionMissing) }

        let moving = products.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return .failure(.emptySelection) }

        let destCount = catalogSessionProductCount(id: targetID)
        let wouldBe = destCount + moving.count
        if wouldBe > CatalogSessionLimits.softQueueCap {
            return .failure(.softCapExceeded(limit: CatalogSessionLimits.softQueueCap, wouldBe: wouldBe))
        }

        flushPersistenceToDisk()
        SessionDiskStore.appendProductsToSession(moving, sessionID: targetID)
        metadataManager.transferProducts(imageAssetIDs: moving.map(\.id), to: targetID)

        if let idx = catalogSessions.firstIndex(where: { $0.id == targetID }) {
            catalogSessions[idx].updatedAt = Date()
        }
        persistSessionsIndex()

        products.removeAll { ids.contains($0.id) }
        flushPersistenceToDisk()
        StylePreviewThumbnailCache.shared.removeAll()
        QueueRowThumbnailCache.removeAll()
        return .success(moving.count)
    }

    func switchCatalogSession(to id: UUID) {
        guard id != activeCatalogSessionID,
              catalogSessions.contains(where: { $0.id == id }) else { return }
        flushPersistenceToDisk()
        cancelActiveBulkWork()
        activeCatalogSessionID = id
        SessionDiskStore.setActiveSessionID(id)
        persistSessionsIndex()
        sessionPersistenceSuspendDepth += 1
        products = SessionDiskStore.loadQueueIfAvailable() ?? []
        sessionPersistenceSuspendDepth = max(0, sessionPersistenceSuspendDepth - 1)
        metadataManager.loadSession(
            id: id,
            name: activeCatalogSessionName,
            products: products,
            brandName: brandMarkText,
            marketplace: metadataMarketplaceName()
        )
        StylePreviewThumbnailCache.shared.removeAll()
        QueueRowThumbnailCache.removeAll()
    }

    func renameCatalogSession(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = catalogSessions.firstIndex(where: { $0.id == id }) else { return }
        catalogSessions[idx].name = trimmed
        catalogSessions[idx].updatedAt = Date()
        if id == activeCatalogSessionID {
            metadataManager.updateProjectName(trimmed)
        }
        persistSessionsIndex()
    }

    /// Deletes a session folder. Refuses to delete the last remaining session.
    @discardableResult
    func deleteCatalogSession(id: UUID) -> Bool {
        guard catalogSessions.count > 1,
              catalogSessions.contains(where: { $0.id == id }) else { return false }
        if id == activeCatalogSessionID {
            guard let fallback = catalogSessions.first(where: { $0.id != id })?.id else { return false }
            switchCatalogSession(to: fallback)
        }
        catalogSessions.removeAll { $0.id == id }
        SessionDiskStore.deleteSessionFolder(id: id)
        MetadataStore.deleteSession(sessionID: id)
        persistSessionsIndex()
        return true
    }

    func catalogSessionProductCount(id: UUID) -> Int {
        if id == activeCatalogSessionID { return products.count }
        return SessionDiskStore.productCountOnDisk(sessionID: id)
    }

    /// Explicit user action / optional launch preference — white studio background.
    func resetBackgroundStyleToDefaultWhite() {
        backgroundCanvasStyle = .solid
        backgroundColor = .white
        secondaryBackgroundColor = UIColor(white: 0.94, alpha: 1)
        gradientColorHexes = ["#FFFFFF"]
    }

    func cancelActiveBulkWork() {
        activeBulkTask?.cancel()
        activeBulkTask = nil
    }

    func applyExportChannelProfile(_ profile: ExportChannelProfile) {
        isApplyingExportChannelProfile = true
        defer { isApplyingExportChannelProfile = false }
        exportChannelProfile = profile
        switch profile {
        case .custom:
            break
        case .amazon:
            outputCanvasWidth = 2000
            outputCanvasHeight = 2000
            outputFillRatio = 0.92
            jpegQuality = 0.86
            compressBeforeShare = true
        case .shopify:
            outputCanvasWidth = 2048
            outputCanvasHeight = 2048
            outputFillRatio = 0.94
            jpegQuality = 0.88
            compressBeforeShare = true
        case .walmart:
            outputCanvasWidth = 2048
            outputCanvasHeight = 2048
            outputFillRatio = 0.93
            jpegQuality = 0.90
            compressBeforeShare = true
        }
    }

    /// Call when the user manually edits canvas, fill, quality, or compress so the picker stays honest.
    func markExportChannelProfileCustom() {
        guard !isApplyingExportChannelProfile, exportChannelProfile != .custom else { return }
        exportChannelProfile = .custom
    }

    func matchLook(from source: CapturedProduct, to ids: Set<UUID>) {
        let targetIDs = ids.subtracting([source.id])
            .filter { id in products.contains(where: { $0.id == id && !$0.isCompositeBundle }) }
        guard !targetIDs.isEmpty else { return }
        guard let src = products.first(where: { $0.id == source.id }) else { return }

        cancelActiveBulkWork()
        pushBlockingOperation("Matching look…")
        StylePreviewThumbnailCache.shared.removeAll()
        QueueRowThumbnailCache.removeAll()
        beginSessionPersistenceBatch(processedImagesOnly: true)

        let autoRm = autoBackgroundRemoval
        let smartColor = smartColorAccuracyEnabled
        let upscale = false // Smart Upscale removed — kept as a local for minimal-diff call sites below.
        let total = targetIDs.count

        activeBulkTask = Task {
            defer {
                endSessionPersistenceBatch()
                popBlockingOperation()
                if activeBulkTask != nil { activeBulkTask = nil }
            }
            await yieldUIFrame()
            for (index, id) in targetIDs.enumerated() {
                if Task.isCancelled { break }
                blockingOperationMessage = total > 1
                    ? "Matching look \(index + 1) of \(total)…"
                    : "Matching look…"
                guard let row = products.first(where: { $0.id == id }) else { continue }
                guard let sourceImage = await exportSourceImage(for: id) else { continue }
                if Task.isCancelled { break }

                let processed = await ImageProcessor.processForExportAsync(
                    sourceImage,
                    removeBackground: autoRm,
                    canvasWidth: src.canvasWidth,
                    canvasHeight: src.canvasHeight,
                    rotationDegrees: row.rotationDegrees,
                    fillRatio: src.fillRatio,
                    polishEnabled: src.polishEnabled,
                    enhancementMode: src.enhancementMode,
                    studioAIStrength: src.studioAIStrength,
                    backgroundColor: src.backgroundColor,
                    secondaryBackgroundColor: src.secondaryBackgroundColor,
                    backgroundStyle: src.backgroundStyle,
                    gradientColorHexes: src.gradientColorHexes,
                    smartColorAccuracy: smartColor,
                    smartUpscale: upscale,
                    flipHorizontal: row.flipHorizontal,
                    flipVertical: row.flipVertical,
                    photoFilter: src.photoFilter,
                    photoFilterIntensity: src.photoFilterIntensity,
                    adjustAutoEnhance: src.adjustAutoEnhance,
                    toneAdjustments: src.toneAdjustments,
                    cutoutFeather: src.cutoutFeather,
                    cutoutBrushMaskData: row.cutoutBrushMaskData,
                    studioShadow: src.studioShadow,
                    applyBrandMark: !row.suppressBrandMark,
                    imageNameText: brandKitImageNameText(for: row),
                    qos: total > 1 ? .utility : .userInitiated
                )

                await Task.detached(priority: .utility) {
                    autoreleasepool {
                        SessionDiskStore.writeProcessedImage(processed.image, for: id, reason: "matchLook")
                    }
                }.value

                guard let i = products.firstIndex(where: { $0.id == id }) else { continue }
                let p = products[i]
                ImageProcessor.invalidateCutoutCache(productID: id)
                #if DEBUG
                ProcessedWriteForensics.recordFinalRender(
                    image: processed.image,
                    productID: id,
                    reason: "matchLook",
                    product: p
                )
                ProcessedWriteForensics.recordAssignment(
                    image: processed.image,
                    productID: id,
                    reason: "matchLook",
                    product: p
                )
                #endif
                products[i] = CapturedProduct(
                    id: p.id,
                    sequence: p.sequence,
                    upc: p.upc,
                    angle: p.angle,
                    multiAngleOrdinal: p.multiAngleOrdinal,
                    image: processed.image,
                    originalImage: p.originalImage,
                    uncompressedOriginalImage: p.uncompressedOriginalImage,
                    capturedAt: p.capturedAt,
                    backgroundRemoved: processed.didRemoveBackground,
                    duplicateCopyIndex: p.duplicateCopyIndex,
                    polishEnabled: src.polishEnabled,
                    enhancementMode: src.enhancementMode,
                    studioAIStrength: src.studioAIStrength,
                    canvasWidth: src.canvasWidth,
                    canvasHeight: src.canvasHeight,
                    rotationDegrees: p.rotationDegrees,
                    flipHorizontal: p.flipHorizontal,
                    flipVertical: p.flipVertical,
                    photoFilter: src.photoFilter,
                    photoFilterIntensity: src.photoFilterIntensity,
                    adjustAutoEnhance: src.adjustAutoEnhance,
                    toneAdjustments: src.toneAdjustments,
                    cutoutFeather: src.cutoutFeather,
                    cutoutBrushMaskData: p.cutoutBrushMaskData,
                    studioShadow: src.studioShadow,
                    preUpscaleCanvasWidth: p.preUpscaleCanvasWidth,
                    preUpscaleCanvasHeight: p.preUpscaleCanvasHeight,
                    preUpscaleEnhancementMode: p.preUpscaleEnhancementMode,
                    preUpscaleStudioAIStrength: p.preUpscaleStudioAIStrength,
                    fillRatio: src.fillRatio,
                    backgroundColor: src.backgroundColor,
                    secondaryBackgroundColor: src.secondaryBackgroundColor,
                    backgroundStyle: src.backgroundStyle,
                    gradientColorHexes: src.gradientColorHexes,
                    backgroundFillData: src.backgroundFillData,
                    upscaled: p.upscaled,
                    isCompositeBundle: p.isCompositeBundle,
                    compositeLayoutData: p.compositeLayoutData,
                    suppressBrandMark: p.suppressBrandMark
                )
                if total > 1 { await pauseBetweenBulkExportSteps() }
            }
        }
    }

    func applyDefringeSharpen(to product: CapturedProduct) {
        guard let idx = products.firstIndex(where: { $0.id == product.id }) else { return }
        let p = products[idx]
        let sourceImage = p.image
        let productId = p.id
        pushBlockingOperation("Refining edges…")
        Task {
            let refined = await Task.detached(priority: .userInitiated) {
                ImageProcessor.applyDefringeSharpen(sourceImage)
            }.value
            await MainActor.run {
                defer { self.popBlockingOperation() }
                guard let i = self.products.firstIndex(where: { $0.id == productId }) else { return }
                let cur = self.products[i]
                #if DEBUG
                ProcessedWriteForensics.recordFinalRender(
                    image: refined,
                    productID: productId,
                    reason: "applyDefringeSharpen",
                    product: cur
                )
                ProcessedWriteForensics.recordAssignment(
                    image: refined,
                    productID: productId,
                    reason: "applyDefringeSharpen",
                    product: cur
                )
                #endif
                self.products[i] = cur.replacingProcessedImage(refined)
                SessionDiskStore.writeProcessedImage(refined, for: productId, reason: "applyDefringeSharpen")
                StylePreviewCacheRevisionStore.shared.invalidate(productID: productId, reason: "defringe")
                QueueRowThumbnailCache.removeAll()
            }
        }
    }

    func recordSuccessfulBarcode(_ code: String) {
        let cleaned = BarcodeCanonicalForm.normalizeForStorage(code)
        guard !cleaned.isEmpty else { return }
        lastUsedUPC = cleaned
        var list = recentBarcodes.filter { $0 != cleaned }
        list.insert(cleaned, at: 0)
        if list.count > 40 { list = Array(list.prefix(40)) }
        recentBarcodes = list
        UserDefaults.standard.set(list.joined(separator: "|"), forKey: DefaultsKey.barcodeHistory)
    }

    func saveLookPreset(slot: Int, name: String, style: BackgroundCanvasStyle, primary: UIColor, secondary: UIColor, gradientHexes: [String]) {
        guard (0..<3).contains(slot) else { return }
        let preset = LookPresetSlot(name: name, styleRaw: style.rawValue, primaryHex: primary.hexString, secondaryHex: secondary.hexString, gradientHexes: gradientHexes)
        guard let data = try? JSONEncoder().encode(preset) else { return }
        UserDefaults.standard.set(data, forKey: "lookPresetSlot_\(slot)")
        objectWillChange.send()
    }

    func loadLookPreset(slot: Int) {
        guard (0..<3).contains(slot),
              let data = UserDefaults.standard.data(forKey: "lookPresetSlot_\(slot)"),
              let preset = try? JSONDecoder().decode(LookPresetSlot.self, from: data) else { return }
        backgroundCanvasStyle = BackgroundCanvasStyle.fromStored(preset.styleRaw)
        backgroundColor = UIColor(hexString: preset.primaryHex) ?? backgroundColor
        secondaryBackgroundColor = UIColor(hexString: preset.secondaryHex) ?? secondaryBackgroundColor
        gradientColorHexes = preset.gradientHexes.isEmpty ? ["#FFFFFF"] : preset.gradientHexes
        fitGradientColorsToSelectedBackgroundStyle()
    }

    func lookPresetLabel(slot: Int) -> String {
        guard let data = UserDefaults.standard.data(forKey: "lookPresetSlot_\(slot)"),
              let preset = try? JSONDecoder().decode(LookPresetSlot.self, from: data) else { return "Empty" }
        return preset.name
    }

    /// Next sequence label for capture UI (monotonic even when new rows are inserted at the top).
    var nextSequence: Int { (products.map(\.sequence).max() ?? 0) + 1 }
    var activeAngles: [ProductAngle] { multiAngleEnabled ? (enabledAngles.isEmpty ? [.front] : enabledAngles) : [.none] }
    var currentCaptureAngle: ProductAngle { multiAngleEnabled ? activeAngles[min(currentAngleIndex, activeAngles.count - 1)] : .none }
    var currentAngleLabel: String { currentCaptureAngle == .none ? "Product" : currentCaptureAngle.rawValue }

    func resetCurrent(keepMultiAngleIdentifier: Bool = false) {
        currentImage = nil
        currentUPC = ""
        if !keepMultiAngleIdentifier { currentMultiAngleIdentifier = "" }
        selectedAngle = multiAngleEnabled ? currentCaptureAngle : .none
    }

    func startNextProduct() {
        currentImage = nil
        currentUPC = ""
        currentMultiAngleIdentifier = ""
        currentAngleIndex = 0
        clearPendingMultiAngleCaptures()
        selectedAngle = multiAngleEnabled ? currentCaptureAngle : .none
    }

    func clearPendingMultiAngleCaptures() {
        pendingMultiAngleCaptures = []
    }

    /// Buffers the current photo for multi-angle (no UPC yet). Advances to the next angle when more remain.
    /// - Returns: `true` if more angles still need capturing; `false` if the set is complete and ready to name.
    @discardableResult
    func bufferCurrentMultiAngleShot() -> Bool {
        guard multiAngleEnabled, let image = currentImage else { return false }
        let ordinal = currentAngleIndex + 1
        let angle = currentCaptureAngle
        pendingMultiAngleCaptures.append(
            PendingMultiAngleCapture(angle: angle, ordinal: ordinal, image: image)
        )
        currentImage = nil
        if currentAngleIndex < activeAngles.count - 1 {
            currentAngleIndex += 1
            selectedAngle = currentCaptureAngle
            return true
        }
        return false
    }

    var isAwaitingMultiAngleName: Bool {
        multiAngleEnabled
            && !pendingMultiAngleCaptures.isEmpty
            && pendingMultiAngleCaptures.count >= activeAngles.count
            && currentImage == nil
    }

    /// Pops the last buffered multi-angle shot back into the live capture slot for retake.
    func restoreLastMultiAngleShotForRetake() {
        guard multiAngleEnabled, let last = pendingMultiAngleCaptures.popLast() else { return }
        currentImage = last.image
        currentAngleIndex = max(0, last.ordinal - 1)
        selectedAngle = currentCaptureAngle
    }

    var multiAngleStatusLine: String {
        guard multiAngleEnabled else { return "" }
        let total = activeAngles.count
        let done = pendingMultiAngleCaptures.count
        if done >= total, total > 0 {
            return "Multi-angle on — all \(total) shots ready. Scan one UPC to name as UPC-1…UPC-\(total)"
        }
        let next = currentAngleLabel
        if done == 0 {
            return "Multi-angle on — capturing \(next) next (\(total) angles → UPC-1…UPC-\(total))"
        }
        return "Multi-angle on — \(done)/\(total) captured · next: \(next)"
    }

    func advanceAfterSuccessfulQueue() -> Bool {
        if multiAngleEnabled && currentAngleIndex < activeAngles.count - 1 {
            currentAngleIndex += 1
            selectedAngle = currentCaptureAngle
            resetCurrent(keepMultiAngleIdentifier: true)
            return true
        }
        startNextProduct()
        return false
    }

    func toggleAngle(_ angle: ProductAngle, enabled: Bool) {
        guard angle != .none else { return }
        if enabled {
            if !enabledAngles.contains(angle) { enabledAngles.append(angle) }
            enabledAngles.sort {
                (ProductAngle.captureAngles.firstIndex(of: $0) ?? Int.max)
                    < (ProductAngle.captureAngles.firstIndex(of: $1) ?? Int.max)
            }
        } else {
            if enabledAngles.count > 1 { enabledAngles.removeAll { $0 == angle } }
        }
        if currentAngleIndex >= activeAngles.count { currentAngleIndex = max(0, activeAngles.count - 1) }
        selectedAngle = currentCaptureAngle
    }

    enum DuplicateQueueAction { case normal, replaceExisting, addCopy }

    struct QueueInsertResult {
        let success: Bool
        let productID: UUID?
    }

    /// Call once when entering Single/Batch capture from Home or Queue (not on every view re-appear).
    func beginCaptureFlow(mode: CaptureMode) {
        captureMode = mode
        startNextProduct()
    }

    func addCurrentToQueue(action: DuplicateQueueAction = .normal) -> Bool {
        guard let img = currentImage else { return false }
        var identifier = currentUPC.trimmingCharacters(in: .whitespacesAndNewlines)
        if imageNamingMode == .scannedUPC || imageNamingMode == .manualInput {
            identifier = FileNameRules.captureLabel(from: identifier)
        }
        guard !identifier.isEmpty else { return false }

        let source = ImageProcessor.downsampleIfNeededForImportPipeline(
            img,
            maxLongEdgePixels: ImageProcessingLimits.cameraOriginalMaxLongEdge
        )
        let processed = processImageUsingCurrentSettings(
            source,
            imageNameText: brandKitImageNameText(forIdentifier: identifier)
        )
        return insertQueuedCapture(
            identifier: identifier,
            sourceImage: source,
            processed: processed,
            action: action,
            itemAngle: multiAngleEnabled ? currentCaptureAngle : .none,
            multiAngleIdentifier: currentMultiAngleIdentifier,
            enhancementMode: photoEnhancementMode,
            studioAIStrength: studioAIStrength
        ) != nil
    }

    /// Processes capture off the main thread so large queues do not block UI or spike memory on the main actor.
    func addCurrentToQueueAsync(action: DuplicateQueueAction = .normal) async -> QueueInsertResult {
        guard let img = currentImage else { return QueueInsertResult(success: false, productID: nil) }

        let capacity = gateAddingPhotos(count: 1, presentGuidanceOnCaution: true)
        if capacity.isBlocked {
            return QueueInsertResult(success: false, productID: nil)
        }

        currentImage = nil

        var identifier = currentUPC.trimmingCharacters(in: .whitespacesAndNewlines)
        if imageNamingMode == .scannedUPC || imageNamingMode == .manualInput {
            identifier = FileNameRules.captureLabel(from: identifier)
        }
        guard !identifier.isEmpty else { return QueueInsertResult(success: false, productID: nil) }

        let capturedAngle = multiAngleEnabled ? currentCaptureAngle : ProductAngle.none
        let capturedMultiID = currentMultiAngleIdentifier
        let removeBackground = autoBackgroundRemoval
        let cw = outputCanvasWidth
        let ch = outputCanvasHeight
        let fill = outputFillRatio
        let polish = productPolishEnabled
        let mode = photoEnhancementMode
        let strength = studioAIStrength
        let primary = backgroundColor
        let secondary = secondaryBackgroundColor
        let style = backgroundCanvasStyle
        let gradients = gradientColorHexes
        let colorAccuracy = smartColorAccuracyEnabled
        let processingCap = MemoryPressureMonitor.shared.recommendedProcessingLongEdge
        let imageNameText = brandKitImageNameText(forIdentifier: identifier)

        pushBlockingOperation("Adding to queue…")
        defer { popBlockingOperation() }

        let pipeline = await Task.detached(priority: .userInitiated) { () -> (UIImage, (image: UIImage, didRemoveBackground: Bool))? in
            autoreleasepool {
                let source = ImageProcessor.downsampleIfNeededForImportPipeline(
                    img,
                    maxLongEdgePixels: ImageProcessingLimits.cameraOriginalMaxLongEdge
                )
                // Same long-edge as stored original — first-pass quality matches Apply.
                let processInput = ImageProcessor.downsampleIfNeededForImportPipeline(
                    source,
                    maxLongEdgePixels: processingCap
                )
                let processed = ImageProcessor.processForExport(
                    processInput,
                    removeBackground: removeBackground,
                    canvasWidth: cw,
                    canvasHeight: ch,
                    rotationDegrees: 0,
                    fillRatio: fill,
                    polishEnabled: polish,
                    enhancementMode: mode,
                    studioAIStrength: strength,
                    backgroundColor: primary,
                    secondaryBackgroundColor: secondary,
                    backgroundStyle: style,
                    gradientColorHexes: gradients,
                    smartColorAccuracy: colorAccuracy,
                    smartUpscale: false,
                    imageNameText: imageNameText
                )
                return (source, processed)
            }
        }.value

        guard let pipeline else {
            return QueueInsertResult(success: false, productID: nil)
        }

        let productID = insertQueuedCapture(
            identifier: identifier,
            sourceImage: pipeline.0,
            processed: pipeline.1,
            action: action,
            itemAngle: capturedAngle,
            multiAngleIdentifier: capturedMultiID,
            enhancementMode: mode,
            studioAIStrength: strength
        )
        return QueueInsertResult(success: productID != nil, productID: productID)
    }

    @discardableResult
    private func insertQueuedCapture(
        identifier: String,
        sourceImage: UIImage,
        processed: (image: UIImage, didRemoveBackground: Bool),
        action: DuplicateQueueAction,
        itemAngle: ProductAngle? = nil,
        multiAngleIdentifier: String? = nil,
        multiAngleOrdinal: Int = 0,
        enhancementMode: PhotoEnhancementMode? = nil,
        studioAIStrength: StudioAIStrength? = nil
    ) -> UUID? {
        sessionPersistenceSuspendDepth += 1
        defer { sessionPersistenceSuspendDepth = max(0, sessionPersistenceSuspendDepth - 1) }

        let resolvedAngle = itemAngle ?? (multiAngleEnabled ? currentCaptureAngle : .none)
        let copyIndex: Int = (action == .addCopy) ? nextDuplicateCopyIndex(upc: identifier, angle: resolvedAngle) : 1
        let mode = enhancementMode ?? photoEnhancementMode
        let strength = studioAIStrength ?? self.studioAIStrength
        let ordinal = multiAngleOrdinal
        let styleFilter = preferredExportPhotoFilter
        // Brand Kit is already applied inside `processForExport` — do not stamp again here.
        let styledImage: UIImage = {
            guard styleFilter != .none, styleFilter != .standard else { return processed.image }
            return ImageProcessor.applyExportTuning(
                to: processed.image,
                photoFilter: styleFilter,
                photoFilterIntensity: 1,
                adjustAutoEnhance: false,
                applyBrandMark: false
            )
        }()
        let fillData = BackgroundFillSpec.fromLegacy(style: backgroundCanvasStyle, hexes: gradientColorHexes).encodedData()

        if action == .replaceExisting, let idx = products.firstIndex(where: {
            $0.upc == identifier
                && $0.angle == resolvedAngle
                && $0.duplicateCopyIndex == 1
                && $0.multiAngleOrdinal == ordinal
        }) {
            let existingID = products[idx].id
            ImageProcessor.invalidateCutoutCache(productID: existingID)
            #if DEBUG
            ProcessedWriteForensics.recordFinalRender(
                image: processed.image,
                productID: existingID,
                reason: "insertQueuedCapture.replaceExisting"
            )
            ProcessedWriteForensics.recordAssignment(
                image: styledImage,
                productID: existingID,
                reason: "insertQueuedCapture.replaceExisting"
            )
            #endif
            products[idx] = CapturedProduct(
                id: existingID,
                sequence: products[idx].sequence,
                upc: identifier,
                angle: resolvedAngle,
                multiAngleOrdinal: ordinal,
                image: styledImage,
                originalImage: sourceImage,
                capturedAt: Date(),
                backgroundRemoved: processed.didRemoveBackground,
                duplicateCopyIndex: 1,
                polishEnabled: productPolishEnabled,
                enhancementMode: mode,
                studioAIStrength: strength,
                canvasWidth: outputCanvasWidth,
                canvasHeight: outputCanvasHeight,
                photoFilter: styleFilter == .standard ? .none : styleFilter,
                fillRatio: outputFillRatio,
                backgroundColor: backgroundColor,
                secondaryBackgroundColor: secondaryBackgroundColor,
                backgroundStyle: backgroundCanvasStyle,
                gradientColorHexes: gradientColorHexes,
                backgroundFillData: fillData
            )
            persistQueueItemImmediately(productID: existingID)
            return existingID
        } else {
            let newID = UUID()
            #if DEBUG
            ProcessedWriteForensics.recordFinalRender(
                image: processed.image,
                productID: newID,
                reason: "insertQueuedCapture.new"
            )
            ProcessedWriteForensics.recordAssignment(
                image: styledImage,
                productID: newID,
                reason: "insertQueuedCapture.new"
            )
            #endif
            products.insert(
                CapturedProduct(
                    id: newID,
                    sequence: nextSequence,
                    upc: identifier,
                    angle: resolvedAngle,
                    multiAngleOrdinal: ordinal,
                    image: styledImage,
                    originalImage: sourceImage,
                    backgroundRemoved: processed.didRemoveBackground,
                    duplicateCopyIndex: copyIndex,
                    polishEnabled: productPolishEnabled,
                    enhancementMode: mode,
                    studioAIStrength: strength,
                    canvasWidth: outputCanvasWidth,
                    canvasHeight: outputCanvasHeight,
                    photoFilter: styleFilter == .standard ? .none : styleFilter,
                    fillRatio: outputFillRatio,
                    backgroundColor: backgroundColor,
                    secondaryBackgroundColor: secondaryBackgroundColor,
                    backgroundStyle: backgroundCanvasStyle,
                    gradientColorHexes: gradientColorHexes,
                    backgroundFillData: fillData
                ),
                at: 0
            )
            if multiAngleEnabled, let mid = multiAngleIdentifier, !mid.isEmpty, currentMultiAngleIdentifier.isEmpty {
                currentMultiAngleIdentifier = mid
            }
            persistQueueItemImmediately(productID: newID)
            return newID
        }
    }

    /// After all multi-angle photos are buffered, assign one UPC/name and queue every shot as `upc-1`, `upc-2`, …
    func commitPendingMultiAngleSet(identifier rawIdentifier: String, action: DuplicateQueueAction = .normal) async -> QueueInsertResult {
        let shots = pendingMultiAngleCaptures
        guard !shots.isEmpty else { return QueueInsertResult(success: false, productID: nil) }

        let capacity = gateAddingPhotos(count: shots.count, presentGuidanceOnCaution: true)
        if capacity.isBlocked {
            return QueueInsertResult(success: false, productID: nil)
        }

        var identifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if imageNamingMode == .scannedUPC || imageNamingMode == .manualInput {
            identifier = FileNameRules.captureLabel(from: identifier)
        }
        guard !identifier.isEmpty else { return QueueInsertResult(success: false, productID: nil) }

        pushBlockingOperation(shots.count > 1 ? "Adding \(shots.count) angles…" : "Adding photo…")
        beginSessionPersistenceBatch()
        defer {
            endSessionPersistenceBatch()
            popBlockingOperation()
        }

        var firstID: UUID?
        let ordered = shots.sorted { $0.ordinal < $1.ordinal }

        for shot in ordered {
            if Task.isCancelled { break }
            let source = ImageProcessor.downsampleIfNeededForImportPipeline(
                shot.image,
                maxLongEdgePixels: ImageProcessingLimits.cameraOriginalMaxLongEdge
            )
            let processed = await processImageForNewCatalogItemAsync(source, identifier: identifier)
            let perShotAction: DuplicateQueueAction
            switch action {
            case .replaceExisting:
                perShotAction = .replaceExisting
            case .addCopy:
                perShotAction = .addCopy
            case .normal:
                perShotAction = .normal
            }
            let id = insertQueuedCapture(
                identifier: identifier,
                sourceImage: source,
                processed: (processed.image, processed.didRemoveBackground),
                action: perShotAction,
                itemAngle: shot.angle,
                multiAngleIdentifier: identifier,
                multiAngleOrdinal: shot.ordinal
            )
            if firstID == nil { firstID = id }
        }

        clearPendingMultiAngleCaptures()
        currentMultiAngleIdentifier = ""
        currentUPC = ""
        currentImage = nil
        currentAngleIndex = 0
        selectedAngle = multiAngleEnabled ? currentCaptureAngle : .none

        return QueueInsertResult(success: firstID != nil, productID: firstID)
    }

    /// Processes a newly ingested catalog image with current session enhancement settings.
    /// Returns a stable `identifier` used for the queue item and Image Name stamp.
    func processImageForNewCatalogItemAsync(
        _ image: UIImage,
        identifier: String? = nil
    ) async -> (image: UIImage, didRemoveBackground: Bool, identifier: String) {
        let resolvedID = {
            let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? FileNameRules.randomNativeName() : trimmed
        }()
        let processed = await processImageForExportAsync(
            image,
            enhancementMode: photoEnhancementMode,
            studioAIStrength: studioAIStrength,
            maxProcessingLongEdge: MemoryPressureMonitor.shared.recommendedProcessingLongEdge,
            imageNameText: brandKitImageNameText(forIdentifier: resolvedID)
        )
        return (processed.image, processed.didRemoveBackground, resolvedID)
    }

    /// Parallel processing for multi-image imports (concurrency capped for memory safety).
    func processImportImagesInParallel(
        _ images: [UIImage],
        progressMessage: String
    ) async -> [(original: UIImage, processed: UIImage, didRemoveBackground: Bool, identifier: String)] {
        let total = images.count
        guard total > 0 else { return [] }
        refreshMemoryPressure()
        var liveCap = max(1, min(CatalogSessionLimits.importConcurrency, MemoryPressureMonitor.shared.recommendedImportConcurrency))
        var results: [(Int, UIImage, UIImage, Bool, String)] = []
        results.reserveCapacity(total)

        await withTaskGroup(of: (Int, UIImage, UIImage, Bool, String)?.self) { group in
            var nextIndex = 0
            var inFlight = 0

            while nextIndex < total || inFlight > 0 {
                while inFlight < liveCap, nextIndex < total {
                    let index = nextIndex
                    let image = images[index]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        let processed = await self.processImageForNewCatalogItemAsync(image)
                        return (index, image, processed.image, processed.didRemoveBackground, processed.identifier)
                    }
                }
                if inFlight == 0 { break }
                if let item = await group.next() {
                    inFlight -= 1
                    if let item {
                        results.append(item)
                        let completed = results.count
                        liveCap = max(1, min(CatalogSessionLimits.importConcurrency, MemoryPressureMonitor.shared.recommendedImportConcurrency))
                        let note = liveCap == 1 && total > 1
                            ? "\(progressMessage) (one at a time)"
                            : progressMessage
                        updateActiveImport(completed: completed, total: total, message: note)
                    }
                }
            }
        }

        return results
            .sorted { $0.0 < $1.0 }
            .map { (original: $0.1, processed: $0.2, didRemoveBackground: $0.3, identifier: $0.4) }
    }

    /// Decode → process → append → release, one sliding window at a time (never holds the full batch in RAM).
    @discardableResult
    func streamImportCatalogImages(
        total: Int,
        progressMessage: String,
        loadImageAt: @escaping (Int) async -> UIImage?
    ) async -> Int {
        let count = max(0, total)
        guard count > 0 else { return 0 }
        refreshMemoryPressure()
        updateActiveImport(completed: 0, total: count, message: progressMessage)

        var imported = 0
        var nextIndex = 0
        var inFlight = 0
        var liveCap = max(1, min(CatalogSessionLimits.importConcurrency, MemoryPressureMonitor.shared.recommendedImportConcurrency))
        var stopEnqueue = false

        await withTaskGroup(of: (UIImage, UIImage, Bool, String)?.self) { group in
            while (!stopEnqueue && nextIndex < count) || inFlight > 0 {
                while !stopEnqueue, inFlight < liveCap, nextIndex < count {
                    let index = nextIndex
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        guard let image = await loadImageAt(index) else { return nil }
                        let processed = await self.processImageForNewCatalogItemAsync(image)
                        return (image, processed.image, processed.didRemoveBackground, processed.identifier)
                    }
                }
                if inFlight == 0 { break }
                if let item = await group.next() {
                    inFlight -= 1
                    if let item {
                        appendImportedProcessedImage(
                            originalImage: item.0,
                            processedImage: item.1,
                            didRemoveBackground: item.2,
                            identifier: item.3
                        )
                        if let newestID = products.first?.id {
                            evictPersistedOriginalFromMemory(productID: newestID)
                        }
                        imported += 1
                        let snap = refreshMemoryPressure()
                        if snap.level >= .caution {
                            performMemoryPurge(for: snap.level)
                        }
                        liveCap = max(1, min(CatalogSessionLimits.importConcurrency, MemoryPressureMonitor.shared.recommendedImportConcurrency))
                        let note = liveCap == 1 && count > 1
                            ? "\(progressMessage) (one at a time)"
                            : progressMessage
                        updateActiveImport(completed: min(imported, count), total: count, message: note)
                        if snap.level == .critical, !MemoryPressureMonitor.shared.canStartHeavyPass() {
                            stopEnqueue = true
                        }
                    }
                }
            }
        }

        return imported
    }

    func processImageForExportAsync(
        _ image: UIImage,
        enhancementMode: PhotoEnhancementMode,
        studioAIStrength: StudioAIStrength,
        maxProcessingLongEdge: CGFloat = ImageProcessingLimits.unifiedProcessingMaxLongEdge,
        imageNameText: String? = nil
    ) async -> (image: UIImage, didRemoveBackground: Bool) {
        let removeBackground = autoBackgroundRemoval
        let cw = outputCanvasWidth
        let ch = outputCanvasHeight
        let fill = outputFillRatio
        let polish = productPolishEnabled
        let mode = enhancementMode
        let strength = studioAIStrength
        let primary = backgroundColor
        let secondary = secondaryBackgroundColor
        let style = backgroundCanvasStyle
        let gradients = gradientColorHexes
        let colorAccuracy = smartColorAccuracyEnabled
        let stampName = imageNameText
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result: (UIImage, Bool) = autoreleasepool {
                    let capped = ImageProcessor.downsampleIfNeededForImportPipeline(
                        image,
                        maxLongEdgePixels: maxProcessingLongEdge
                    )
                    return ImageProcessor.processForExport(
                        capped,
                        removeBackground: removeBackground,
                        canvasWidth: cw,
                        canvasHeight: ch,
                        rotationDegrees: 0,
                        fillRatio: fill,
                        polishEnabled: polish,
                        enhancementMode: mode,
                        studioAIStrength: strength,
                        backgroundColor: primary,
                        secondaryBackgroundColor: secondary,
                        backgroundStyle: style,
                        gradientColorHexes: gradients,
                        smartColorAccuracy: colorAccuracy,
                        smartUpscale: false,
                        imageNameText: stampName
                    )
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Incremental import path: process off-main, append lightweight on main (session enhancement settings).
    func processImageForCurrentSettingsAsync(_ image: UIImage) async -> (image: UIImage, didRemoveBackground: Bool) {
        await processImageForExportAsync(image, enhancementMode: photoEnhancementMode, studioAIStrength: studioAIStrength)
    }

    /// Inserts a new queue item (Photos “Save as Duplicate”) using the edited bitmap and settings.
    @discardableResult
    func insertDuplicateOfProduct(
        _ source: CapturedProduct,
        image: UIImage,
        polishEnabled: Bool,
        enhancementMode: PhotoEnhancementMode,
        studioAIStrength: StudioAIStrength,
        canvasWidth: Int,
        canvasHeight: Int,
        rotationDegrees: Double,
        fillRatio: Double,
        backgroundColor: UIColor,
        secondaryBackgroundColor: UIColor,
        backgroundStyle: BackgroundCanvasStyle,
        gradientColorHexes: [String],
        backgroundFillSpec: BackgroundFillSpec,
        flipHorizontal: Bool,
        flipVertical: Bool,
        photoFilter: ExportPhotoFilter,
        photoFilterIntensity: Double,
        adjustAutoEnhance: Bool,
        toneAdjustments: ManualToneAdjustments? = nil,
        cutoutFeather: Double? = nil,
        cutoutBrushMaskData: Data? = nil,
        studioShadow: SoftSyntheticShadowSettings? = nil,
        suppressBrandMark: Bool? = nil
    ) -> CapturedProduct {
        let copyIndex = nextDuplicateCopyIndex(upc: source.upc, angle: source.angle)
        let suppressMark = suppressBrandMark ?? source.suppressBrandMark
        let tones = toneAdjustments ?? source.toneAdjustments
        let feather = cutoutFeather ?? source.cutoutFeather
        let brush = cutoutBrushMaskData ?? source.cutoutBrushMaskData
        let shadow = studioShadow ?? source.studioShadow
        // Caller supplies a fully tuned raster (filters / Brand Mark already applied).
        let tuned = ImageProcessor.applyExportTuning(
            to: image,
            photoFilter: photoFilter,
            photoFilterIntensity: photoFilterIntensity,
            adjustAutoEnhance: adjustAutoEnhance,
            toneAdjustments: tones,
            applyBrandMark: false
        )
        let duplicate = CapturedProduct(
            sequence: nextSequence,
            upc: source.upc,
            angle: source.angle,
            multiAngleOrdinal: source.multiAngleOrdinal,
            image: tuned,
            originalImage: source.originalImage,
            capturedAt: Date(),
            backgroundRemoved: source.backgroundRemoved,
            duplicateCopyIndex: copyIndex,
            polishEnabled: polishEnabled,
            enhancementMode: enhancementMode,
            studioAIStrength: studioAIStrength,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            photoFilter: photoFilter,
            photoFilterIntensity: photoFilterIntensity,
            adjustAutoEnhance: adjustAutoEnhance,
            toneAdjustments: tones,
            cutoutFeather: feather,
            cutoutBrushMaskData: brush,
            studioShadow: shadow,
            fillRatio: fillRatio,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: backgroundFillSpec.legacyCanvasStyle(),
            gradientColorHexes: backgroundFillSpec.colorHexes,
            backgroundFillData: backgroundFillSpec.encodedData(),
            upscaled: source.upscaled,
            isCompositeBundle: source.isCompositeBundle,
            compositeLayoutData: source.compositeLayoutData,
            suppressBrandMark: suppressMark
        )
        products.insert(duplicate, at: 0)
        return duplicate
    }

    func appendImportedProcessedImage(
        originalImage: UIImage,
        processedImage: UIImage,
        didRemoveBackground: Bool,
        identifier: String? = nil
    ) {
        let resolvedIdentifier: String = {
            let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? FileNameRules.randomNativeName() : trimmed
        }()
        let identifier = resolvedIdentifier
        let styleFilter = preferredExportPhotoFilter
        // Import pipeline already stamps Brand Kit when enabled — filter pass must not restamp.
        let styledImage: UIImage = {
            guard styleFilter != .none, styleFilter != .standard else { return processedImage }
            return ImageProcessor.applyExportTuning(
                to: processedImage,
                photoFilter: styleFilter,
                photoFilterIntensity: 1,
                adjustAutoEnhance: false,
                applyBrandMark: false
            )
        }()
        let fillData = BackgroundFillSpec.fromLegacy(style: backgroundCanvasStyle, hexes: gradientColorHexes).encodedData()
        let newID = UUID()
        #if DEBUG
        ProcessedWriteForensics.recordFinalRender(
            image: processedImage,
            productID: newID,
            reason: "appendImportedProcessedImage"
        )
        ProcessedWriteForensics.recordAssignment(
            image: styledImage,
            productID: newID,
            reason: "appendImportedProcessedImage"
        )
        #endif
        products.insert(
            CapturedProduct(
                id: newID,
                sequence: nextSequence,
                upc: identifier,
                angle: .none,
                multiAngleOrdinal: 0,
                image: styledImage,
                originalImage: originalImage,
                backgroundRemoved: didRemoveBackground,
                duplicateCopyIndex: 1,
                polishEnabled: productPolishEnabled,
                enhancementMode: photoEnhancementMode,
                studioAIStrength: studioAIStrength,
                canvasWidth: outputCanvasWidth,
                canvasHeight: outputCanvasHeight,
                photoFilter: styleFilter == .standard ? .none : styleFilter,
                fillRatio: outputFillRatio,
                backgroundColor: backgroundColor,
                secondaryBackgroundColor: secondaryBackgroundColor,
                backgroundStyle: backgroundCanvasStyle,
                gradientColorHexes: gradientColorHexes,
                backgroundFillData: fillData
            ),
            at: 0
        )
    }

    @discardableResult
    func insertGroupedCover(
        compositeImage: UIImage,
        layout: CompositeBundleLayout,
        sourceProducts: [CapturedProduct],
        name: String
    ) -> CapturedProduct {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let upc = cleaned.isEmpty ? FileNameRules.randomNativeName() : cleaned
        let item = CapturedProduct(
            sequence: nextSequence,
            upc: upc,
            angle: .none,
            multiAngleOrdinal: 0,
            image: compositeImage,
            originalImage: compositeImage,
            uncompressedOriginalImage: compositeImage,
            backgroundRemoved: false,
            duplicateCopyIndex: 1,
            polishEnabled: productPolishEnabled,
            enhancementMode: photoEnhancementMode,
            studioAIStrength: studioAIStrength,
            canvasWidth: layout.resolvedCanvasWidth,
            canvasHeight: layout.resolvedCanvasHeight,
            fillRatio: outputFillRatio,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: backgroundCanvasStyle,
            gradientColorHexes: gradientColorHexes,
            backgroundFillData: BackgroundFillSpec.fromLegacy(
                style: backgroundCanvasStyle,
                hexes: gradientColorHexes
            ).encodedData(),
            isCompositeBundle: true,
            compositeLayoutData: layout.decodedLayoutData()
        )
        products.insert(item, at: 0)
        return item
    }

    func updateGroupedCover(
        productID: UUID,
        compositeImage: UIImage,
        layout: CompositeBundleLayout,
        name: String? = nil
    ) {
        guard let idx = products.firstIndex(where: { $0.id == productID }) else { return }
        let existing = products[idx]
        let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let upc = cleaned.isEmpty ? existing.upc : cleaned
        products[idx] = CapturedProduct(
            id: existing.id,
            sequence: existing.sequence,
            upc: upc,
            angle: existing.angle,
            multiAngleOrdinal: existing.multiAngleOrdinal,
            image: compositeImage,
            originalImage: compositeImage,
            uncompressedOriginalImage: compositeImage,
            capturedAt: existing.capturedAt,
            backgroundRemoved: false,
            duplicateCopyIndex: existing.duplicateCopyIndex,
            polishEnabled: existing.polishEnabled,
            enhancementMode: existing.enhancementMode,
            studioAIStrength: existing.studioAIStrength,
            canvasWidth: layout.resolvedCanvasWidth,
            canvasHeight: layout.resolvedCanvasHeight,
            rotationDegrees: existing.rotationDegrees,
            flipHorizontal: existing.flipHorizontal,
            flipVertical: existing.flipVertical,
            photoFilter: existing.photoFilter,
            photoFilterIntensity: existing.photoFilterIntensity,
            adjustAutoEnhance: existing.adjustAutoEnhance,
            preUpscaleCanvasWidth: existing.preUpscaleCanvasWidth,
            preUpscaleCanvasHeight: existing.preUpscaleCanvasHeight,
            preUpscaleEnhancementMode: existing.preUpscaleEnhancementMode,
            preUpscaleStudioAIStrength: existing.preUpscaleStudioAIStrength,
            fillRatio: existing.fillRatio,
            backgroundColor: existing.backgroundColor,
            secondaryBackgroundColor: existing.secondaryBackgroundColor,
            backgroundStyle: existing.backgroundStyle,
            gradientColorHexes: existing.gradientColorHexes,
            backgroundFillData: existing.backgroundFillData,
            upscaled: existing.upscaled,
            isCompositeBundle: true,
            compositeLayoutData: layout.decodedLayoutData()
        )
    }

    func remove(_ product: CapturedProduct) { products.removeAll { $0.id == product.id } }

    func removeProducts(ids: Set<UUID>) {
        products.removeAll { ids.contains($0.id) }
    }

    /// Loads the pristine original for export work — disk first so bulk batches do not duplicate in-memory bitmaps.
    private func exportSourceImage(for productID: UUID) async -> UIImage? {
        if let resident = products.first(where: { $0.id == productID }),
           !resident.isOriginalEvicted {
            return resident.uncompressedOriginalImage
        }
        return await Task.detached(priority: .utility) {
            autoreleasepool { SessionDiskStore.loadOriginalImage(id: productID) }
        }.value
    }

    private func pauseBetweenBulkExportSteps() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func reprocessProducts(ids: Set<UUID>) {
        let targetIDs = products
            .filter { ids.contains($0.id) && !$0.isCompositeBundle }
            .map(\.id)
        guard !targetIDs.isEmpty else { return }

        cancelActiveBulkWork()
        pushBlockingOperation("Processing photos…")
        StylePreviewThumbnailCache.shared.removeAll()
        QueueRowThumbnailCache.removeAll()
        beginSessionPersistenceBatch(processedImagesOnly: true)

        let removeBackground = autoBackgroundRemoval
        let cw = outputCanvasWidth
        let ch = outputCanvasHeight
        let fillRatio = outputFillRatio
        let polish = productPolishEnabled
        let mode = photoEnhancementMode
        let strength = studioAIStrength
        let bg = backgroundColor
        let bg2 = secondaryBackgroundColor
        let style = backgroundCanvasStyle
        let hexes = gradientColorHexes
        let smartColor = smartColorAccuracyEnabled
        let upscale = false // Smart Upscale removed — kept as a local for minimal-diff call sites below.
        let total = targetIDs.count

        activeBulkTask = Task {
            defer {
                endSessionPersistenceBatch()
                popBlockingOperation()
                if activeBulkTask != nil { activeBulkTask = nil }
            }
            await yieldUIFrame()
            for (index, id) in targetIDs.enumerated() {
                if Task.isCancelled { break }
                blockingOperationMessage = total > 1
                    ? "Processing \(index + 1) of \(total)…"
                    : "Processing photo…"
                guard let row = products.first(where: { $0.id == id }) else { continue }
                guard let source = await exportSourceImage(for: id) else { continue }
                if Task.isCancelled { break }

                let processed = await ImageProcessor.processForExportAsync(
                    source,
                    removeBackground: removeBackground,
                    canvasWidth: cw,
                    canvasHeight: ch,
                    rotationDegrees: row.rotationDegrees,
                    fillRatio: fillRatio,
                    polishEnabled: polish,
                    enhancementMode: mode,
                    studioAIStrength: strength,
                    backgroundColor: bg,
                    secondaryBackgroundColor: bg2,
                    backgroundStyle: style,
                    gradientColorHexes: hexes,
                    smartColorAccuracy: smartColor,
                    smartUpscale: upscale,
                    flipHorizontal: row.flipHorizontal,
                    flipVertical: row.flipVertical,
                    photoFilter: row.photoFilter,
                    photoFilterIntensity: row.photoFilterIntensity,
                    adjustAutoEnhance: row.adjustAutoEnhance,
                    applyBrandMark: !row.suppressBrandMark,
                    imageNameText: brandKitImageNameText(for: row),
                    qos: total > 1 ? .utility : .userInitiated
                )

                if Task.isCancelled { break }

                await Task.detached(priority: .utility) {
                    autoreleasepool {
                        SessionDiskStore.writeProcessedImage(processed.image, for: id, reason: "bulkReprocess")
                    }
                }.value

                guard let i = products.firstIndex(where: { $0.id == id }) else { continue }
                let p = products[i]
                ImageProcessor.invalidateCutoutCache(productID: id)
                #if DEBUG
                ProcessedWriteForensics.recordFinalRender(
                    image: processed.image,
                    productID: id,
                    reason: "bulkReprocess",
                    product: p
                )
                ProcessedWriteForensics.recordAssignment(
                    image: processed.image,
                    productID: id,
                    reason: "bulkReprocess",
                    product: p
                )
                #endif
                products[i] = CapturedProduct(
                    id: p.id,
                    sequence: p.sequence,
                    upc: p.upc,
                    angle: p.angle,
                    multiAngleOrdinal: p.multiAngleOrdinal,
                    image: processed.image,
                    originalImage: p.originalImage,
                    uncompressedOriginalImage: p.uncompressedOriginalImage,
                    capturedAt: p.capturedAt,
                    backgroundRemoved: processed.didRemoveBackground,
                    duplicateCopyIndex: p.duplicateCopyIndex,
                    polishEnabled: polish,
                    enhancementMode: mode,
                    studioAIStrength: strength,
                    canvasWidth: cw,
                    canvasHeight: ch,
                    rotationDegrees: p.rotationDegrees,
                    flipHorizontal: p.flipHorizontal,
                    flipVertical: p.flipVertical,
                    photoFilter: p.photoFilter,
                    photoFilterIntensity: p.photoFilterIntensity,
                    adjustAutoEnhance: p.adjustAutoEnhance,
                    preUpscaleCanvasWidth: nil,
                    preUpscaleCanvasHeight: nil,
                    preUpscaleEnhancementMode: nil,
                    preUpscaleStudioAIStrength: nil,
                    fillRatio: fillRatio,
                    backgroundColor: bg,
                    secondaryBackgroundColor: bg2,
                    backgroundStyle: style,
                    gradientColorHexes: hexes,
                    backgroundFillData: p.backgroundFillData,
                    upscaled: false,
                    isCompositeBundle: p.isCompositeBundle,
                    compositeLayoutData: p.compositeLayoutData,
                    suppressBrandMark: p.suppressBrandMark
                )
                if total > 1 { await pauseBetweenBulkExportSteps() }
            }
        }
    }

    func renameProduct(_ product: CapturedProduct, to newName: String) {
        guard let idx = products.firstIndex(where: { $0.id == product.id }) else { return }
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let existing = products[idx]
        products[idx] = CapturedProduct(
            id: existing.id,
            sequence: existing.sequence,
            upc: cleaned,
            angle: existing.angle,
            multiAngleOrdinal: existing.multiAngleOrdinal,
            image: existing.image,
            originalImage: existing.originalImage,
            capturedAt: existing.capturedAt,
            backgroundRemoved: existing.backgroundRemoved,
            duplicateCopyIndex: existing.duplicateCopyIndex,
            polishEnabled: existing.polishEnabled,
            enhancementMode: existing.enhancementMode,
            studioAIStrength: existing.studioAIStrength,
            canvasWidth: existing.canvasWidth,
            canvasHeight: existing.canvasHeight,
            rotationDegrees: existing.rotationDegrees,
            flipHorizontal: existing.flipHorizontal,
            flipVertical: existing.flipVertical,
            photoFilter: existing.photoFilter,
            photoFilterIntensity: existing.photoFilterIntensity,
            adjustAutoEnhance: existing.adjustAutoEnhance,
            preUpscaleCanvasWidth: existing.preUpscaleCanvasWidth,
            preUpscaleCanvasHeight: existing.preUpscaleCanvasHeight,
            preUpscaleEnhancementMode: existing.preUpscaleEnhancementMode,
            preUpscaleStudioAIStrength: existing.preUpscaleStudioAIStrength,
            fillRatio: existing.fillRatio,
            backgroundColor: existing.backgroundColor,
            secondaryBackgroundColor: existing.secondaryBackgroundColor,
            backgroundStyle: existing.backgroundStyle,
            gradientColorHexes: existing.gradientColorHexes,
            upscaled: existing.upscaled,
            isCompositeBundle: existing.isCompositeBundle,
            compositeLayoutData: existing.compositeLayoutData,
            suppressBrandMark: existing.suppressBrandMark
        )
    }

    func clearQueue() { products.removeAll(); startNextProduct() }

    func replaceImage(for product: CapturedProduct, with newImage: UIImage) {
        Task { @MainActor in
            guard products.contains(where: { $0.id == product.id }) else { return }
            pushBlockingOperation("Updating photo…")
            let rm = autoBackgroundRemoval
            let cw = outputCanvasWidth
            let ch = outputCanvasHeight
            let fillRatio = outputFillRatio
            let polish = productPolishEnabled
            let mode = photoEnhancementMode
            let strength = studioAIStrength
            let bg = backgroundColor
            let bg2 = secondaryBackgroundColor
            let style = backgroundCanvasStyle
            let hexes = gradientColorHexes
            let smartColor = smartColorAccuracyEnabled
            let upscale = false // Smart Upscale removed — kept as a local for minimal-diff call sites below.
            let productId = product.id
            let suppressMark = product.suppressBrandMark
            Task {
                let processed = await ImageProcessor.processForExportAsync(
                    newImage,
                    removeBackground: rm,
                    canvasWidth: cw,
                    canvasHeight: ch,
                    rotationDegrees: 0,
                    fillRatio: fillRatio,
                    polishEnabled: polish,
                    enhancementMode: mode,
                    studioAIStrength: strength,
                    backgroundColor: bg,
                    secondaryBackgroundColor: bg2,
                    backgroundStyle: style,
                    gradientColorHexes: hexes,
                    smartColorAccuracy: smartColor,
                    smartUpscale: upscale,
                    flipHorizontal: false,
                    flipVertical: false,
                    photoFilter: .none,
                    photoFilterIntensity: 1.0,
                    adjustAutoEnhance: false,
                    applyBrandMark: !suppressMark,
                    imageNameText: brandKitImageNameText(for: product)
                )
                await MainActor.run {
                    defer { self.popBlockingOperation() }
                    guard let i = self.products.firstIndex(where: { $0.id == productId }) else { return }
                    let cur = self.products[i]
                    self.products[i] = CapturedProduct(
                        id: cur.id,
                        sequence: cur.sequence,
                        upc: cur.upc,
                        angle: cur.angle,
                        multiAngleOrdinal: cur.multiAngleOrdinal,
                        image: processed.image,
                        originalImage: newImage,
                        capturedAt: Date(),
                        backgroundRemoved: processed.didRemoveBackground,
                        duplicateCopyIndex: cur.duplicateCopyIndex,
                        polishEnabled: self.productPolishEnabled,
                        enhancementMode: self.photoEnhancementMode,
                        studioAIStrength: self.studioAIStrength,
                        canvasWidth: self.outputCanvasWidth,
                        canvasHeight: self.outputCanvasHeight,
                        rotationDegrees: 0,
                        flipHorizontal: false,
                        flipVertical: false,
                        photoFilter: .none,
                        photoFilterIntensity: 1.0,
                        adjustAutoEnhance: false,
                        preUpscaleCanvasWidth: nil,
                        preUpscaleCanvasHeight: nil,
                        preUpscaleEnhancementMode: nil,
                        preUpscaleStudioAIStrength: nil,
                        fillRatio: self.outputFillRatio,
                        backgroundColor: self.backgroundColor,
                        secondaryBackgroundColor: self.secondaryBackgroundColor,
                        backgroundStyle: self.backgroundCanvasStyle,
                        gradientColorHexes: self.gradientColorHexes,
                        upscaled: false,
                        isCompositeBundle: cur.isCompositeBundle,
                        compositeLayoutData: cur.compositeLayoutData,
                        suppressBrandMark: cur.suppressBrandMark
                    )
                }
            }
        }
    }

    func reprocessProduct(_ product: CapturedProduct) {
        reprocessProducts(ids: [product.id])
    }

    /// Saves a fully rendered preview bitmap (Markup, manual crop, etc.) into the queue without reprocessing from `originalImage`.
    func commitRasterPreview(
        for product: CapturedProduct,
        image: UIImage,
        polishEnabled: Bool,
        enhancementMode: PhotoEnhancementMode,
        studioAIStrength: StudioAIStrength,
        canvasWidth: Int,
        canvasHeight: Int,
        rotationDegrees: Double,
        fillRatio: Double,
        backgroundColor: UIColor,
        secondaryBackgroundColor: UIColor,
        backgroundStyle: BackgroundCanvasStyle,
        gradientColorHexes: [String],
        backgroundFillSpec: BackgroundFillSpec? = nil,
        flipHorizontal: Bool,
        flipVertical: Bool,
        photoFilter: ExportPhotoFilter,
        photoFilterIntensity: Double,
        adjustAutoEnhance: Bool,
        toneAdjustments: ManualToneAdjustments = .neutral,
        cutoutFeather: Double? = nil,
        cutoutBrushMaskData: Data? = nil,
        studioShadow: SoftSyntheticShadowSettings? = nil,
        suppressBrandMark: Bool? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard let idx = products.firstIndex(where: { $0.id == product.id }) else {
            completion?()
            return
        }
        let fillSpec = backgroundFillSpec ?? BackgroundFillSpec.fromLegacy(style: backgroundStyle, hexes: gradientColorHexes)
        let suppressMark = suppressBrandMark ?? products[idx].suppressBrandMark
        guard ImageProcessor.isValidExportBitmap(image) else {
            completion?()
            return
        }
        let tuned = ImageProcessor.applyExportTuning(
            to: image,
            photoFilter: photoFilter,
            photoFilterIntensity: photoFilterIntensity,
            adjustAutoEnhance: adjustAutoEnhance,
            toneAdjustments: toneAdjustments,
            applyBrandMark: !suppressMark,
            imageNameText: brandKitImageNameText(for: product)
        )
        let p = products[idx]
        ImageProcessor.invalidateCutoutCache(productID: p.id)
        products[idx] = CapturedProduct(
            id: p.id,
            sequence: p.sequence,
            upc: p.upc,
            angle: p.angle,
            multiAngleOrdinal: p.multiAngleOrdinal,
            image: tuned,
            originalImage: p.originalImage,
            capturedAt: p.capturedAt,
            backgroundRemoved: p.backgroundRemoved,
            duplicateCopyIndex: p.duplicateCopyIndex,
            polishEnabled: polishEnabled,
            enhancementMode: enhancementMode,
            studioAIStrength: studioAIStrength,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            photoFilter: photoFilter,
            photoFilterIntensity: photoFilterIntensity,
            adjustAutoEnhance: adjustAutoEnhance,
            toneAdjustments: toneAdjustments,
            cutoutFeather: cutoutFeather ?? p.cutoutFeather,
            cutoutBrushMaskData: cutoutBrushMaskData ?? p.cutoutBrushMaskData,
            studioShadow: studioShadow ?? p.studioShadow,
            preUpscaleCanvasWidth: p.preUpscaleCanvasWidth,
            preUpscaleCanvasHeight: p.preUpscaleCanvasHeight,
            preUpscaleEnhancementMode: p.preUpscaleEnhancementMode,
            preUpscaleStudioAIStrength: p.preUpscaleStudioAIStrength,
            fillRatio: fillRatio,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: fillSpec.legacyCanvasStyle(),
            gradientColorHexes: fillSpec.colorHexes,
            backgroundFillData: fillSpec.encodedData(),
            upscaled: p.upscaled,
            isCompositeBundle: p.isCompositeBundle,
            compositeLayoutData: p.compositeLayoutData,
            suppressBrandMark: suppressMark
        )
        completion?()
    }

    func reprocessProduct(
        _ product: CapturedProduct,
        removeBackground: Bool,
        polishEnabled: Bool,
        enhancementMode: PhotoEnhancementMode,
        studioAIStrength: StudioAIStrength,
        canvasWidth: Int,
        canvasHeight: Int,
        rotationDegrees: Double? = nil,
        fillRatio: Double,
        backgroundColor: UIColor = .white,
        secondaryBackgroundColor: UIColor = UIColor(white: 0.94, alpha: 1.0),
        backgroundStyle: BackgroundCanvasStyle = .solid,
        gradientColorHexes: [String]? = nil,
        backgroundFillSpec: BackgroundFillSpec? = nil,
        flipHorizontal: Bool? = nil,
        flipVertical: Bool? = nil,
        photoFilter: ExportPhotoFilter? = nil,
        photoFilterIntensity: Double? = nil,
        adjustAutoEnhance: Bool? = nil,
        toneAdjustments: ManualToneAdjustments? = nil,
        cutoutFeather: Double? = nil,
        cutoutBrushMaskData: Data?? = nil,
        studioShadow: SoftSyntheticShadowSettings? = nil,
        suppressBrandMark: Bool? = nil,
        completion: (() -> Void)? = nil
    ) {
        Task { @MainActor in
            guard let idx = products.firstIndex(where: { $0.id == product.id }) else {
                completion?()
                return
            }
            let activeGradientHexes = gradientColorHexes ?? self.gradientColorHexes
            let fillSpec = backgroundFillSpec
                ?? BackgroundFillSpec.fromLegacy(style: backgroundStyle, hexes: activeGradientHexes)
            let snap = products[idx]
            let rotationSnapshot = rotationDegrees ?? snap.rotationDegrees
            let flipH = flipHorizontal ?? snap.flipHorizontal
            let flipV = flipVertical ?? snap.flipVertical
            let pFilter = photoFilter ?? snap.photoFilter
            let pIntensity = photoFilterIntensity ?? snap.photoFilterIntensity
            let pAdjust = adjustAutoEnhance ?? snap.adjustAutoEnhance
            let pTones = toneAdjustments ?? snap.toneAdjustments
            let pFeather = cutoutFeather ?? snap.cutoutFeather
            let pBrush: Data? = {
                if let cutoutBrushMaskData { return cutoutBrushMaskData }
                return snap.cutoutBrushMaskData
            }()
            let pShadow = polishEnabled ? SoftSyntheticShadowSettings.off : (studioShadow ?? snap.studioShadow)
            let suppressMark = suppressBrandMark ?? snap.suppressBrandMark
            let smartColor = smartColorAccuracyEnabled
            let upscale = false // Smart Upscale removed — kept as a local for minimal-diff call sites below.
            let productId = products[idx].id
            let imageNameText = brandKitImageNameText(for: snap)
            let sourceCap = MemoryPressureMonitor.shared.recommendedProcessingLongEdge
            pushBlockingOperation("Applying…")
            Task.detached(priority: .userInitiated) {
                let original = autoreleasepool {
                    QueueImageResolver.reliableOriginalForReprocess(snap)
                }
                guard let original else {
                    await MainActor.run {
                        self.popBlockingOperation()
                        completion?()
                    }
                    return
                }
                let processed = await HeavyProcessingGate.shared.withExclusiveAccess {
                    await ImageProcessor.processForExportAsync(
                        original,
                        removeBackground: removeBackground,
                        canvasWidth: canvasWidth,
                        canvasHeight: canvasHeight,
                        rotationDegrees: rotationSnapshot,
                        fillRatio: fillRatio,
                        polishEnabled: polishEnabled,
                        enhancementMode: enhancementMode,
                        studioAIStrength: studioAIStrength,
                        backgroundColor: backgroundColor,
                        secondaryBackgroundColor: secondaryBackgroundColor,
                        backgroundStyle: backgroundStyle,
                        gradientColorHexes: activeGradientHexes,
                        backgroundFillSpec: fillSpec,
                        smartColorAccuracy: smartColor,
                        smartUpscale: upscale,
                        flipHorizontal: flipH,
                        flipVertical: flipV,
                        photoFilter: pFilter,
                        photoFilterIntensity: pIntensity,
                        adjustAutoEnhance: pAdjust,
                        toneAdjustments: pTones,
                        cutoutFeather: pFeather,
                        cutoutBrushMaskData: pBrush,
                        studioShadow: pShadow,
                        applyBrandMark: !suppressMark,
                        imageNameText: imageNameText,
                        maxSourceLongEdge: sourceCap
                    )
                }
                await MainActor.run {
                    defer {
                        self.popBlockingOperation()
                        completion?()
                    }
                    guard let i = self.products.firstIndex(where: { $0.id == productId }) else { return }
                    guard ImageProcessor.isValidExportBitmap(processed.image) else { return }
                    let p = self.products[i]
                    ImageProcessor.invalidateCutoutCache(productID: productId)
                    #if DEBUG
                    ProcessedWriteForensics.recordFinalRender(
                        image: processed.image,
                        productID: productId,
                        reason: "reprocessProduct.apply",
                        product: p
                    )
                    ProcessedWriteForensics.recordAssignment(
                        image: processed.image,
                        productID: productId,
                        reason: "reprocessProduct.apply",
                        product: p
                    )
                    #endif
                    self.products[i] = CapturedProduct(
                        id: p.id,
                        sequence: p.sequence,
                        upc: p.upc,
                        angle: p.angle,
                        multiAngleOrdinal: p.multiAngleOrdinal,
                        image: processed.image,
                        originalImage: p.originalImage,
                        capturedAt: p.capturedAt,
                        backgroundRemoved: processed.didRemoveBackground,
                        duplicateCopyIndex: p.duplicateCopyIndex,
                        polishEnabled: polishEnabled,
                        enhancementMode: enhancementMode,
                        studioAIStrength: studioAIStrength,
                        canvasWidth: canvasWidth,
                        canvasHeight: canvasHeight,
                        rotationDegrees: rotationSnapshot,
                        flipHorizontal: flipH,
                        flipVertical: flipV,
                        photoFilter: pFilter,
                        photoFilterIntensity: pIntensity,
                        adjustAutoEnhance: pAdjust,
                        toneAdjustments: pTones,
                        cutoutFeather: pFeather,
                        cutoutBrushMaskData: pBrush,
                        studioShadow: pShadow,
                        preUpscaleCanvasWidth: nil,
                        preUpscaleCanvasHeight: nil,
                        preUpscaleEnhancementMode: nil,
                        preUpscaleStudioAIStrength: nil,
                        fillRatio: fillRatio,
                        backgroundColor: backgroundColor,
                        secondaryBackgroundColor: secondaryBackgroundColor,
                        backgroundStyle: fillSpec.legacyCanvasStyle(),
                        gradientColorHexes: fillSpec.colorHexes,
                        backgroundFillData: fillSpec.encodedData(),
                        upscaled: false,
                        isCompositeBundle: p.isCompositeBundle,
                        compositeLayoutData: p.compositeLayoutData,
                        suppressBrandMark: suppressMark
                    )
                }
            }
        }
    }

    func reprocessAllProducts() {
        reprocessProducts(ids: Set(products.map { $0.id }))
    }

    /// Toggles or sets per-product Brand Mark suppression and reprocesses from the saved look.
    func setSuppressBrandMark(
        _ suppress: Bool,
        for product: CapturedProduct,
        completion: (() -> Void)? = nil
    ) {
        reprocessProduct(
            product,
            removeBackground: product.backgroundRemoved || autoBackgroundRemoval,
            polishEnabled: product.polishEnabled,
            enhancementMode: product.enhancementMode,
            studioAIStrength: product.studioAIStrength,
            canvasWidth: product.canvasWidth,
            canvasHeight: product.canvasHeight,
            rotationDegrees: product.rotationDegrees,
            fillRatio: product.fillRatio,
            backgroundColor: product.backgroundColor,
            secondaryBackgroundColor: product.secondaryBackgroundColor,
            backgroundStyle: product.backgroundStyle,
            gradientColorHexes: product.gradientColorHexes,
            backgroundFillSpec: product.resolvedBackgroundFillSpec,
            flipHorizontal: product.flipHorizontal,
            flipVertical: product.flipVertical,
            photoFilter: product.photoFilter,
            photoFilterIntensity: product.photoFilterIntensity,
            adjustAutoEnhance: product.adjustAutoEnhance,
            suppressBrandMark: suppress,
            completion: completion
        )
    }

    /// Applies Brand Mark suppress/show to many queue items while preserving each item’s saved look.
    func setSuppressBrandMark(_ suppress: Bool, forIDs ids: Set<UUID>) {
        restampBrandMark(forIDs: ids, suppressOverride: suppress)
    }

    /// Re-stamps the current Brand Mark settings onto every non-composite queue photo.
    /// Photos with “Hide Brand Mark” stay unmarked.
    func applyBrandMarkToQueue() {
        let ids = Set(products.filter { !$0.isCompositeBundle }.map(\.id))
        restampBrandMark(forIDs: ids, suppressOverride: nil)
    }

    /// - Parameter suppressOverride: When non-nil, forces that suppress flag; otherwise keeps each item’s flag.
    private func restampBrandMark(forIDs ids: Set<UUID>, suppressOverride: Bool?) {
        let targets = products.filter { ids.contains($0.id) && !$0.isCompositeBundle }
        guard !targets.isEmpty else { return }

        cancelActiveBulkWork()
        let message = suppressOverride == nil
            ? (targets.count > 1 ? "Applying Brand Mark…" : "Applying Brand Mark…")
            : "Updating Brand Mark…"
        pushBlockingOperation(message)
        StylePreviewThumbnailCache.shared.removeAll()
        QueueRowThumbnailCache.removeAll()
        beginSessionPersistenceBatch(processedImagesOnly: true)

        let smartColor = smartColorAccuracyEnabled
        let upscale = false // Smart Upscale removed — kept as a local for minimal-diff call sites below.
        let total = targets.count
        let snapshot = targets

        activeBulkTask = Task {
            defer {
                endSessionPersistenceBatch()
                popBlockingOperation()
                if activeBulkTask != nil { activeBulkTask = nil }
            }
            await yieldUIFrame()
            for (index, item) in snapshot.enumerated() {
                if Task.isCancelled { break }
                blockingOperationMessage = total > 1
                    ? "\(suppressOverride == nil ? "Applying" : "Updating") Brand Mark \(index + 1) of \(total)…"
                    : "\(suppressOverride == nil ? "Applying" : "Updating") Brand Mark…"
                guard let source = await exportSourceImage(for: item.id) else { continue }
                if Task.isCancelled { break }

                let suppress = suppressOverride ?? item.suppressBrandMark
                let processed = await ImageProcessor.processForExportAsync(
                    source,
                    removeBackground: item.backgroundRemoved || autoBackgroundRemoval,
                    canvasWidth: item.canvasWidth,
                    canvasHeight: item.canvasHeight,
                    rotationDegrees: item.rotationDegrees,
                    fillRatio: item.fillRatio,
                    polishEnabled: item.polishEnabled,
                    enhancementMode: item.enhancementMode,
                    studioAIStrength: item.studioAIStrength,
                    backgroundColor: item.backgroundColor,
                    secondaryBackgroundColor: item.secondaryBackgroundColor,
                    backgroundStyle: item.backgroundStyle,
                    gradientColorHexes: item.gradientColorHexes,
                    backgroundFillSpec: item.resolvedBackgroundFillSpec,
                    smartColorAccuracy: smartColor,
                    smartUpscale: upscale,
                    flipHorizontal: item.flipHorizontal,
                    flipVertical: item.flipVertical,
                    photoFilter: item.photoFilter,
                    photoFilterIntensity: item.photoFilterIntensity,
                    adjustAutoEnhance: item.adjustAutoEnhance,
                    applyBrandMark: !suppress,
                    imageNameText: brandKitImageNameText(for: item),
                    qos: total > 1 ? .utility : .userInitiated
                )

                await Task.detached(priority: .utility) {
                    autoreleasepool {
                        SessionDiskStore.writeProcessedImage(processed.image, for: item.id, reason: "brandMarkRestamp")
                    }
                }.value

                guard let i = products.firstIndex(where: { $0.id == item.id }) else { continue }
                let p = products[i]
                ImageProcessor.invalidateCutoutCache(productID: item.id)
                #if DEBUG
                ProcessedWriteForensics.recordFinalRender(
                    image: processed.image,
                    productID: item.id,
                    reason: "brandMarkRestamp",
                    product: p
                )
                ProcessedWriteForensics.recordAssignment(
                    image: processed.image,
                    productID: item.id,
                    reason: "brandMarkRestamp",
                    product: p
                )
                #endif
                products[i] = CapturedProduct(
                    id: p.id,
                    sequence: p.sequence,
                    upc: p.upc,
                    angle: p.angle,
                    multiAngleOrdinal: p.multiAngleOrdinal,
                    image: processed.image,
                    originalImage: p.originalImage,
                    uncompressedOriginalImage: p.uncompressedOriginalImage,
                    capturedAt: p.capturedAt,
                    backgroundRemoved: processed.didRemoveBackground,
                    duplicateCopyIndex: p.duplicateCopyIndex,
                    polishEnabled: p.polishEnabled,
                    enhancementMode: p.enhancementMode,
                    studioAIStrength: p.studioAIStrength,
                    canvasWidth: p.canvasWidth,
                    canvasHeight: p.canvasHeight,
                    rotationDegrees: p.rotationDegrees,
                    flipHorizontal: p.flipHorizontal,
                    flipVertical: p.flipVertical,
                    photoFilter: p.photoFilter,
                    photoFilterIntensity: p.photoFilterIntensity,
                    adjustAutoEnhance: p.adjustAutoEnhance,
                    preUpscaleCanvasWidth: p.preUpscaleCanvasWidth,
                    preUpscaleCanvasHeight: p.preUpscaleCanvasHeight,
                    preUpscaleEnhancementMode: p.preUpscaleEnhancementMode,
                    preUpscaleStudioAIStrength: p.preUpscaleStudioAIStrength,
                    fillRatio: p.fillRatio,
                    backgroundColor: p.backgroundColor,
                    secondaryBackgroundColor: p.secondaryBackgroundColor,
                    backgroundStyle: p.backgroundStyle,
                    gradientColorHexes: p.gradientColorHexes,
                    backgroundFillData: p.backgroundFillData,
                    upscaled: p.upscaled,
                    isCompositeBundle: p.isCompositeBundle,
                    compositeLayoutData: p.compositeLayoutData,
                    suppressBrandMark: suppress
                )
                if total > 1 { await pauseBetweenBulkExportSteps() }
            }
        }
    }

    /// Reverts a legacy upscaled item (from an older app version) back to its pre-upscale
    /// canvas size and settings.
    func revertLegacyUpscale(to product: CapturedProduct, completion: (() -> Void)? = nil) {
        guard let p = products.first(where: { $0.id == product.id }),
              p.upscaled,
              let preW = p.preUpscaleCanvasWidth,
              let preH = p.preUpscaleCanvasHeight,
              let mode = p.preUpscaleEnhancementMode,
              let str = p.preUpscaleStudioAIStrength else { return }
        reprocessProduct(
            p,
            removeBackground: p.backgroundRemoved || autoBackgroundRemoval,
            polishEnabled: p.polishEnabled,
            enhancementMode: mode,
            studioAIStrength: str,
            canvasWidth: preW,
            canvasHeight: preH,
            rotationDegrees: p.rotationDegrees,
            fillRatio: p.fillRatio,
            backgroundColor: p.backgroundColor,
            secondaryBackgroundColor: p.secondaryBackgroundColor,
            backgroundStyle: p.backgroundStyle,
            gradientColorHexes: p.gradientColorHexes,
            completion: completion
        )
    }

    func resetProductToOriginal(_ product: CapturedProduct, completion: (() -> Void)? = nil) {
        reprocessProduct(
            product,
            removeBackground: autoBackgroundRemoval,
            polishEnabled: productPolishEnabled,
            enhancementMode: photoEnhancementMode,
            studioAIStrength: studioAIStrength,
            canvasWidth: outputCanvasWidth,
            canvasHeight: outputCanvasHeight,
            rotationDegrees: 0,
            fillRatio: outputFillRatio,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: backgroundCanvasStyle,
            gradientColorHexes: gradientColorHexes,
            flipHorizontal: false,
            flipVertical: false,
            photoFilter: ExportPhotoFilter.none,
            photoFilterIntensity: 1.0,
            adjustAutoEnhance: false,
            completion: completion
        )
    }

    func resetProductsToOriginal(ids: Set<UUID>) {
        let targetIDs = products
            .filter { ids.contains($0.id) && !$0.isCompositeBundle }
            .map(\.id)
        guard !targetIDs.isEmpty else { return }

        pushBlockingOperation("Resetting photos…")
        StylePreviewThumbnailCache.shared.removeAll()
        QueueRowThumbnailCache.removeAll()
        beginSessionPersistenceBatch(processedImagesOnly: true)

        let removeBackground = autoBackgroundRemoval
        let cw = outputCanvasWidth
        let ch = outputCanvasHeight
        let fillRatio = outputFillRatio
        let polish = productPolishEnabled
        let mode = photoEnhancementMode
        let strength = studioAIStrength
        let bg = backgroundColor
        let bg2 = secondaryBackgroundColor
        let style = backgroundCanvasStyle
        let hexes = gradientColorHexes
        let smartColor = smartColorAccuracyEnabled
        let upscale = false // Smart Upscale removed — kept as a local for minimal-diff call sites below.
        let fillSpec = BackgroundFillSpec.fromLegacy(style: style, hexes: hexes)
        let total = targetIDs.count

        Task {
            await yieldUIFrame()
            for (index, id) in targetIDs.enumerated() {
                blockingOperationMessage = total > 1
                    ? "Resetting \(index + 1) of \(total)…"
                    : "Resetting photo…"
                guard let source = await exportSourceImage(for: id) else { continue }
                guard let row = products.first(where: { $0.id == id }) else { continue }

                let processed = await ImageProcessor.processForExportAsync(
                    source,
                    removeBackground: removeBackground,
                    canvasWidth: cw,
                    canvasHeight: ch,
                    rotationDegrees: 0,
                    fillRatio: fillRatio,
                    polishEnabled: polish,
                    enhancementMode: mode,
                    studioAIStrength: strength,
                    backgroundColor: bg,
                    secondaryBackgroundColor: bg2,
                    backgroundStyle: style,
                    gradientColorHexes: hexes,
                    backgroundFillSpec: fillSpec,
                    smartColorAccuracy: smartColor,
                    smartUpscale: upscale,
                    flipHorizontal: false,
                    flipVertical: false,
                    photoFilter: .none,
                    photoFilterIntensity: 1.0,
                    adjustAutoEnhance: false,
                    applyBrandMark: !row.suppressBrandMark,
                    imageNameText: brandKitImageNameText(for: row),
                    qos: total > 1 ? .utility : .userInitiated
                )

                await Task.detached(priority: .utility) {
                    autoreleasepool {
                        SessionDiskStore.writeProcessedImage(processed.image, for: id, reason: "resetProductsToOriginal")
                    }
                }.value

                guard let i = products.firstIndex(where: { $0.id == id }) else { continue }
                let p = products[i]
                ImageProcessor.invalidateCutoutCache(productID: id)
                #if DEBUG
                ProcessedWriteForensics.recordFinalRender(
                    image: processed.image,
                    productID: id,
                    reason: "resetProductsToOriginal",
                    product: p
                )
                ProcessedWriteForensics.recordAssignment(
                    image: processed.image,
                    productID: id,
                    reason: "resetProductsToOriginal",
                    product: p
                )
                #endif
                products[i] = CapturedProduct(
                    id: p.id,
                    sequence: p.sequence,
                    upc: p.upc,
                    angle: p.angle,
                    multiAngleOrdinal: p.multiAngleOrdinal,
                    image: processed.image,
                    originalImage: p.originalImage,
                    uncompressedOriginalImage: p.uncompressedOriginalImage,
                    capturedAt: p.capturedAt,
                    backgroundRemoved: processed.didRemoveBackground,
                    duplicateCopyIndex: p.duplicateCopyIndex,
                    polishEnabled: polish,
                    enhancementMode: mode,
                    studioAIStrength: strength,
                    canvasWidth: cw,
                    canvasHeight: ch,
                    rotationDegrees: 0,
                    flipHorizontal: false,
                    flipVertical: false,
                    photoFilter: .none,
                    photoFilterIntensity: 1.0,
                    adjustAutoEnhance: false,
                    preUpscaleCanvasWidth: nil,
                    preUpscaleCanvasHeight: nil,
                    preUpscaleEnhancementMode: nil,
                    preUpscaleStudioAIStrength: nil,
                    fillRatio: fillRatio,
                    backgroundColor: bg,
                    secondaryBackgroundColor: bg2,
                    backgroundStyle: style,
                    gradientColorHexes: hexes,
                    backgroundFillData: fillSpec.encodedData(),
                    upscaled: false,
                    isCompositeBundle: p.isCompositeBundle,
                    compositeLayoutData: p.compositeLayoutData,
                    suppressBrandMark: p.suppressBrandMark
                )
                if total > 1 { await pauseBetweenBulkExportSteps() }
            }
            endSessionPersistenceBatch()
            popBlockingOperation()
        }
    }

    private func processImageUsingCurrentSettings(
        _ image: UIImage,
        imageNameText: String? = nil
    ) -> (image: UIImage, didRemoveBackground: Bool) {
        processImageUsingExportSettings(
            image,
            enhancementMode: photoEnhancementMode,
            studioAIStrength: studioAIStrength,
            smartUpscale: false,
            imageNameText: imageNameText
        )
    }

    private func processImageUsingExportSettings(
        _ image: UIImage,
        enhancementMode: PhotoEnhancementMode,
        studioAIStrength: StudioAIStrength,
        smartUpscale: Bool,
        imageNameText: String? = nil
    ) -> (image: UIImage, didRemoveBackground: Bool) {
        ImageProcessor.processForExport(
            image,
            removeBackground: autoBackgroundRemoval,
            canvasWidth: outputCanvasWidth,
            canvasHeight: outputCanvasHeight,
            rotationDegrees: 0,
            fillRatio: outputFillRatio,
            polishEnabled: productPolishEnabled,
            enhancementMode: enhancementMode,
            studioAIStrength: studioAIStrength,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: backgroundCanvasStyle,
            gradientColorHexes: gradientColorHexes,
            smartColorAccuracy: smartColorAccuracyEnabled,
            smartUpscale: smartUpscale,
            imageNameText: imageNameText
        )
    }

    func updateGradientColor(at index: Int, color: UIColor) {
        guard gradientColorHexes.indices.contains(index) else { return }
        gradientColorHexes[index] = color.hexString
    }

    func addGradientColor() {
        gradientColorHexes.append(gradientColorHexes.last ?? "#FFFFFF")
        fitGradientColorsToSelectedBackgroundStyle()
    }

    func setGradientStopCount(_ count: Int) {
        let target = max(backgroundCanvasStyle.minimumColorCount, count)
        if backgroundCanvasStyle == .solid {
            gradientColorHexes = [gradientColorHexes.first ?? "#FFFFFF"]
            return
        }
        while gradientColorHexes.count < target { gradientColorHexes.append(gradientColorHexes.last ?? "#FFFFFF") }
        if gradientColorHexes.count > target { gradientColorHexes = Array(gradientColorHexes.prefix(target)) }
    }

    func removeGradientColor(at index: Int) {
        let minimum = backgroundCanvasStyle.minimumColorCount
        guard gradientColorHexes.count > minimum, gradientColorHexes.indices.contains(index) else { return }
        gradientColorHexes.remove(at: index)
    }

    func fitGradientColorsToSelectedBackgroundStyle() {
        let minimum = backgroundCanvasStyle.minimumColorCount
        if backgroundCanvasStyle == .solid {
            gradientColorHexes = [backgroundColor.hexString]
            return
        }
        if gradientColorHexes.count < minimum {
            while gradientColorHexes.count < minimum { gradientColorHexes.append(gradientColorHexes.last ?? "#FFFFFF") }
        }
    }

    func applyBackgroundQuickPreset(_ preset: BackgroundQuickPreset) {
        backgroundCanvasStyle = preset.style
        gradientColorHexes = preset.hexes
        fitGradientColorsToSelectedBackgroundStyle()
    }

    /// Applies a Home template pack as session defaults for the next capture / import / reprocess.
    /// Style filter stays Settings-owned (except App Defaults, which clears it to Original).
    func applyCatalogTemplate(_ pack: CatalogTemplatePack) {
        let clamped = CanvasPresetCatalog.clampDimensions(width: pack.canvasWidth, height: pack.canvasHeight)
        outputCanvasWidth = clamped.width
        outputCanvasHeight = clamped.height
        outputFillRatio = pack.fillRatio
        photoEnhancementMode = CatalogProcessingBaseline.mode
        studioAIStrength = CatalogProcessingBaseline.strength
        if pack.id == CatalogTemplateLibrary.appDefaultsID {
            preferredExportPhotoFilter = .none
            resetBackgroundStyleToDefaultWhite()
        } else {
            applyBackgroundQuickPreset(pack.backgroundPreset)
        }
        activeCatalogTemplatePackID = pack.id
    }

    func duplicateExists(upc: String, angle: ProductAngle) -> Bool {
        let cleaned = normalizedCaptureLabel(upc)
        return products.contains { $0.upc == cleaned && $0.angle == angle && $0.duplicateCopyIndex == 1 }
    }

    /// True when this UPC already has queue items (used before committing a multi-angle set).
    func duplicateUPCExists(_ upc: String) -> Bool {
        let cleaned = normalizedCaptureLabel(upc)
        return products.contains { $0.upc == cleaned }
    }

    func nextDuplicateCopyIndex(upc: String, angle: ProductAngle) -> Int {
        let cleaned = normalizedCaptureLabel(upc)
        let existing = products.filter { $0.upc == cleaned && $0.angle == angle }.map { $0.duplicateCopyIndex }
        return (existing.max() ?? 1) + 1
    }

    private func normalizedCaptureLabel(_ raw: String) -> String {
        if imageNamingMode == .scannedUPC || imageNamingMode == .manualInput {
            return FileNameRules.captureLabel(from: raw)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


// MARK: - Export

enum ExportImageFormat: String, CaseIterable {
    case jpg
    case png

    var fileExtension: String { rawValue }
}

extension UIImage {
    /// JPEG without alpha so ImageIO does not warn about opaque + premultiplied alpha at decode time.
    func jpegDataForOpaqueExport(compressionQuality: CGFloat) -> Data? {
        let w = max(1, Int(round(size.width * scale)))
        let h = max(1, Int(round(size.height * scale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let flattened = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
        }
        return flattened.jpegData(compressionQuality: compressionQuality)
    }

    /// PNG export preserving alpha when present (e.g. background-removed cutouts).
    func pngDataForExport() -> Data? {
        pngData()
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
    /// Queued products included in this share; used to offer removal after a completed share.
    let productIDsForRemovalPrompt: [UUID]

    init(items: [Any], productIDsForRemovalPrompt: [UUID] = []) {
        self.items = items
        self.productIDsForRemovalPrompt = productIDsForRemovalPrompt
    }
}

/// Presents exported files in the share sheet so destinations keep the on-disk filename.
final class ExportFileActivityItem: NSObject, UIActivityItemSource {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        if let type = UTType(filenameExtension: fileURL.pathExtension) {
            return type.identifier
        }
        return UTType.data.identifier
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = fileURL.lastPathComponent
        metadata.originalURL = fileURL
        metadata.url = fileURL
        return metadata
    }
}

enum ExportManager {
    private static let exportFolderName = "ProductStudioExports"
    private static let singleShareFolderName = "ProductStudioSingleShare"
    /// Same manifest name for JPG+CSV, PNG+CSV, all-formats, ZIP, and CSV-only exports.
    static let manifestCSVFilename = "product_photo_manifest.csv"
    private static let csvLineEnding = "\r\n"

    static func activityItems(from items: [Any]) -> [Any] {
        items.map { item in
            if let url = item as? URL {
                return ExportFileActivityItem(fileURL: url)
            }
            return item
        }
    }

    /// Writes a single in-memory image to a temp JPG (for preview share before “Apply”).
    static func jpegURL(for image: UIImage, filename: String, quality: Double) -> URL? {
        imageURL(for: image, filename: filename, format: .jpg, quality: quality, folderName: singleShareFolderName, cleanFolder: false)
    }

    /// Writes a single in-memory image to a temp PNG (for preview share before “Apply”).
    static func pngURL(for image: UIImage, filename: String) -> URL? {
        imageURL(for: image, filename: filename, format: .png, quality: 1.0, folderName: singleShareFolderName, cleanFolder: false)
    }

    private static func imageURL(
        for image: UIImage,
        filename: String,
        format: ExportImageFormat,
        quality: Double,
        folderName: String,
        cleanFolder: Bool
    ) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        if cleanFolder { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename)
        guard let data = imageData(for: image, format: format, quality: quality) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    private static func imageData(for image: UIImage, format: ExportImageFormat, quality: Double) -> Data? {
        switch format {
        case .jpg:
            image.jpegDataForOpaqueExport(compressionQuality: CGFloat(max(0.90, min(1.0, quality))))
        case .png:
            image.pngDataForExport()
        }
    }

    /// Transparent subject cutout for PNG export when background was removed.
    /// Uses a cached Vision cutout from the original so we never encode the white/composited `product.image`.
    static func transparentCutoutImage(for product: CapturedProduct) -> UIImage? {
        guard product.backgroundRemoved else { return nil }
        let original = QueueImageResolver.uncompressedOriginal(for: product) ?? product.image
        return ImageProcessor.cachedForegroundCutout(
            for: product,
            from: original,
            mode: product.enhancementMode,
            strength: product.studioAIStrength
        )
    }

    /// Image bytes for a product — PNG uses a true transparent cutout when background was removed.
    private static func imageData(for product: CapturedProduct, format: ExportImageFormat, quality: Double) -> Data? {
        switch format {
        case .jpg:
            return imageData(for: product.image, format: .jpg, quality: quality)
        case .png:
            let source = transparentCutoutImage(for: product) ?? product.image
            return imageData(for: source, format: .png, quality: quality)
        }
    }

    static func imageURL(for product: CapturedProduct, namingMode: ImageNamingMode, quality: Double, cleanFolder: Bool = false, format: ExportImageFormat = .jpg) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(exportFolderName, isDirectory: true)
        if cleanFolder { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(product.filename(for: namingMode, format: format))
        guard let data = imageData(for: product, format: format, quality: quality) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    static func exportURLs(
        for products: [CapturedProduct],
        namingMode: ImageNamingMode,
        includeCSV: Bool,
        quality: Double,
        format: ExportImageFormat = .jpg,
        marketplaceProfile: MarketplaceExportProfileID = .custom,
        brandName: String = "",
        metadataSnapshot: MetadataExportSnapshot? = nil
    ) -> [URL] {
        let folder = prepareExportFolder()
        var urls: [URL] = []
        for p in products {
            let url = folder.appendingPathComponent(p.filename(for: namingMode, format: format))
            if let data = imageData(for: p, format: format, quality: quality) {
                try? data.write(to: url, options: .atomic)
                urls.append(url)
            }
        }
        if includeCSV, let csv = csvURL(
            for: products,
            namingMode: namingMode,
            folder: folder,
            formats: [format],
            marketplaceProfile: marketplaceProfile,
            brandName: brandName,
            metadataSnapshot: metadataSnapshot
        ) {
            urls.append(csv)
        }
        return urls
    }

    /// Exports each product as JPG and PNG, with an optional CSV listing both formats.
    static func exportAllFormatsURLs(
        for products: [CapturedProduct],
        namingMode: ImageNamingMode,
        includeCSV: Bool,
        quality: Double,
        marketplaceProfile: MarketplaceExportProfileID = .custom,
        brandName: String = "",
        metadataSnapshot: MetadataExportSnapshot? = nil
    ) -> [URL] {
        let folder = prepareExportFolder()
        var urls: [URL] = []
        for p in products {
            for format in ExportImageFormat.allCases {
                let url = folder.appendingPathComponent(p.filename(for: namingMode, format: format))
                if let data = imageData(for: p, format: format, quality: quality) {
                    try? data.write(to: url, options: .atomic)
                    urls.append(url)
                }
            }
        }
        if includeCSV, let csv = csvURL(
            for: products,
            namingMode: namingMode,
            folder: folder,
            formats: ExportImageFormat.allCases,
            marketplaceProfile: marketplaceProfile,
            brandName: brandName,
            metadataSnapshot: metadataSnapshot
        ) {
            urls.append(csv)
        }
        return urls
    }

    private static func prepareExportFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(exportFolderName, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func csvURL(
        for products: [CapturedProduct],
        namingMode: ImageNamingMode,
        folder: URL? = nil,
        formats: [ExportImageFormat] = [.jpg],
        marketplaceProfile: MarketplaceExportProfileID = .custom,
        brandName: String = "",
        columns: [CSVExportColumn] = CSVExportColumn.packageDefault,
        metadataSnapshot: MetadataExportSnapshot? = nil
    ) -> URL? {
        let folder = folder ?? FileManager.default.temporaryDirectory.appendingPathComponent(exportFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let exportDate = Date()
        var rows: [CSVExportRowContext] = []
        for product in products {
            for format in formats {
                let filename = product.filename(for: namingMode, format: format)
                let imageURL = folder.appendingPathComponent(filename)
                let byteCount = (try? Data(contentsOf: imageURL).count) ?? 0
                let width = format == .png ? product.canvasWidth : product.canvasWidth
                let height = product.canvasHeight
                let base = CSVExportRowContext(
                    product: product,
                    namingMode: namingMode,
                    format: format,
                    archivePath: filename,
                    byteCount: byteCount,
                    exportWidth: width,
                    exportHeight: height,
                    marketplaceProfile: marketplaceProfile,
                    brandName: brandName,
                    exportDate: exportDate
                )
                let row = metadataSnapshot.map { CSVExporter.rowContext(base, snapshot: $0) } ?? base
                rows.append(row)
            }
        }
        return CSVExporter.writeCSV(
            rows: rows,
            to: folder,
            filename: manifestCSVFilename,
            columns: columns
        )
    }

    /// Professional seller ZIP: `Images/`, `products.csv`, and `manifest.json`.
    static func zipExportURL(
        for products: [CapturedProduct],
        context: ExportPackageContext
    ) -> URL? {
        ExportPackageEngine.exportPackageURL(products: products, context: context)
    }

    /// Backward-compatible ZIP entry point used by share flows.
    static func zipExportURL(
        for products: [CapturedProduct],
        namingMode: ImageNamingMode,
        includeCSV: Bool,
        quality: Double,
        projectName: String = "ProductStudioExport",
        marketplaceProfile: MarketplaceExportProfileID = .custom,
        brandName: String = ""
    ) -> URL? {
        var context = ExportPackageContext(
            projectName: projectName,
            marketplaceProfile: marketplaceProfile,
            brandName: brandName,
            namingMode: namingMode,
            jpegQuality: quality
        )
        if !includeCSV {
            context.csvColumns = []
        }
        return zipExportURL(for: products, context: context)
    }

    private static func randomExportZipSuffix(length: Int = 5) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    private static func csvEscaped(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    static func csvField(_ value: String, asText: Bool = false) -> String {
        if asText {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return csvEscaped(value)
    }

    /// Scales raw byte counts for CSV: stays in bytes below 1024, then KB, then MB (1024-based).
    static func scaledFileSize(fromBytes bytes: Int) -> (value: String, suffix: String) {
        guard bytes > 0 else { return ("0", "bytes") }
        if bytes < 1024 {
            return (String(bytes), "bytes")
        }
        let kilobytes = Double(bytes) / 1024.0
        if kilobytes < 1024 {
            return (formatScaledFileSizeValue(kilobytes), "KB")
        }
        let megabytes = kilobytes / 1024.0
        return (formatScaledFileSizeValue(megabytes), "MB")
    }

    private static func formatScaledFileSizeValue(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 0.001 {
            return String(format: "%.0f", rounded)
        }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
