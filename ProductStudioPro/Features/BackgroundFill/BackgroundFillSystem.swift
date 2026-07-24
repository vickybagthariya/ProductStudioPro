import SwiftUI
import UIKit

// MARK: - PowerPoint-style fill model

enum BackgroundFillKind: String, CaseIterable, Identifiable, Codable {
    case solid = "Solid fill"
    case gradient = "Gradient fill"
    case image = "Image fill"

    var id: String { rawValue }

    /// Short label for Format Background segmented control.
    var formatBackgroundShortTitle: String {
        switch self {
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        case .image: return "Image"
        }
    }
}

/// Top-level Format Background tabs (Color / Gradient / Scene / Online).
enum FormatBackgroundTab: String, CaseIterable, Identifiable {
    case color = "Color"
    case gradient = "Gradient"
    case scene = "Scene"
    case online = "Online"

    var id: String { rawValue }

    var fillKind: BackgroundFillKind {
        switch self {
        case .color: return .solid
        case .gradient: return .gradient
        case .scene, .online: return .image
        }
    }

    static func resolved(from spec: BackgroundFillSpec, prefersOnline: Bool = false) -> FormatBackgroundTab {
        switch spec.fillKind {
        case .solid: return .color
        case .gradient: return .gradient
        case .image: return prefersOnline ? .online : .scene
        }
    }
}

enum GradientFillType: String, CaseIterable, Identifiable, Codable {
    case linear = "Linear"
    case radial = "Radial"
    case angular = "Angular"
    case mesh = "Mesh"
    /// Legacy studio chip preset (not shown in Format Background type picker).
    case shadeFromTitle = "Shade from title"

    var id: String { rawValue }

    /// Types shown in Format Background.
    static var formatBackgroundPickerCases: [GradientFillType] {
        [.linear, .radial, .angular, .mesh]
    }

    var supportsDirection: Bool {
        switch self {
        case .linear, .radial, .angular, .mesh: return true
        case .shadeFromTitle: return false
        }
    }

    var supportsAngle: Bool {
        switch self {
        case .linear, .angular: return true
        case .radial, .mesh, .shadeFromTitle: return false
        }
    }

    static func migrated(from raw: String) -> GradientFillType {
        switch raw {
        case "Linear": return .linear
        case "Radial": return .radial
        case "Angular", "Rectangular": return .angular
        case "Mesh", "Path": return .mesh
        case "Shade from title": return .shadeFromTitle
        default: return GradientFillType(rawValue: raw) ?? .linear
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self.migrated(from: try container.decode(String.self))
    }
}

enum GradientFillDirection: String, CaseIterable, Identifiable, Codable {
    case top = "Top"
    case bottom = "Bottom"
    case leading = "Leading"
    case trailing = "Trailing"
    case topLeading = "Top Leading"
    case topTrailing = "Top Trailing"
    case bottomLeading = "Bottom Leading"
    case bottomTrailing = "Bottom Trailing"
    case center = "Center"

    var id: String { rawValue }

    static var formatBackgroundPickerCases: [GradientFillDirection] {
        [.top, .bottom, .leading, .trailing, .topLeading, .topTrailing, .bottomLeading, .bottomTrailing, .center]
    }

    static func migrated(from raw: String) -> GradientFillDirection {
        switch raw {
        case "Top", "To top": return .top
        case "Bottom", "To bottom": return .bottom
        case "Leading", "To left": return .leading
        case "Trailing", "To right": return .trailing
        case "Top Leading", "To top left": return .topLeading
        case "Top Trailing", "To top right": return .topTrailing
        case "Bottom Leading", "To bottom left": return .bottomLeading
        case "Bottom Trailing", "To bottom right": return .bottomTrailing
        case "Center", "To center": return .center
        default: return GradientFillDirection(rawValue: raw) ?? .bottomTrailing
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self.migrated(from: try container.decode(String.self))
    }

    func linearPoints(in rect: CGRect) -> (CGPoint, CGPoint) {
        let m = CGPoint(x: rect.midX, y: rect.midY)
        switch self {
        case .center: return (CGPoint(x: rect.minX, y: m.y), CGPoint(x: rect.maxX, y: m.y))
        case .top: return (CGPoint(x: m.x, y: rect.maxY), CGPoint(x: m.x, y: rect.minY))
        case .bottom: return (CGPoint(x: m.x, y: rect.minY), CGPoint(x: m.x, y: rect.maxY))
        case .leading: return (CGPoint(x: rect.maxX, y: m.y), CGPoint(x: rect.minX, y: m.y))
        case .trailing: return (CGPoint(x: rect.minX, y: m.y), CGPoint(x: rect.maxX, y: m.y))
        case .topTrailing: return (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY))
        case .topLeading: return (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY))
        case .bottomTrailing: return (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomLeading: return (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY))
        }
    }

    func radialCenter(in rect: CGRect) -> CGPoint {
        switch self {
        case .center: return CGPoint(x: rect.midX, y: rect.midY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY * 0.88)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY * 0.12)
        case .leading: return CGPoint(x: rect.maxX * 0.88, y: rect.midY)
        case .trailing: return CGPoint(x: rect.minX * 0.12, y: rect.midY)
        case .topTrailing: return CGPoint(x: rect.minX, y: rect.maxY)
        case .topLeading: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomTrailing: return CGPoint(x: rect.minX, y: rect.minY)
        case .bottomLeading: return CGPoint(x: rect.maxX, y: rect.minY)
        }
    }

    /// Normalized center (0…1) for mesh / radial highlight origin.
    func unitCenter() -> CGPoint {
        switch self {
        case .center: return CGPoint(x: 0.5, y: 0.5)
        case .top: return CGPoint(x: 0.5, y: 1.0)
        case .bottom: return CGPoint(x: 0.5, y: 0.0)
        case .leading: return CGPoint(x: 1.0, y: 0.5)
        case .trailing: return CGPoint(x: 0.0, y: 0.5)
        case .topTrailing: return CGPoint(x: 0.0, y: 1.0)
        case .topLeading: return CGPoint(x: 1.0, y: 1.0)
        case .bottomTrailing: return CGPoint(x: 0.0, y: 0.0)
        case .bottomLeading: return CGPoint(x: 1.0, y: 0.0)
        }
    }

    /// Second axis for angular (conic-style cross blend).
    func angularCrossPoints(in rect: CGRect) -> (CGPoint, CGPoint) {
        switch self {
        case .center, .top, .bottom, .topTrailing, .topLeading, .bottomTrailing, .bottomLeading:
            return (CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY))
        case .leading, .trailing:
            return (CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
        }
    }

    /// Default angle when direction changes (0° = leading → trailing). Premium default: bottomTrailing @ 135°.
    var defaultAngleDegrees: Double {
        switch self {
        case .center: return 0
        case .trailing: return 0
        case .bottom: return 90
        case .leading: return 180
        case .top: return 270
        case .bottomTrailing: return 135
        case .bottomLeading: return 45
        case .topTrailing: return 315
        case .topLeading: return 225
        }
    }
}

enum BackgroundPresetOverlay: String, Codable, CaseIterable, Identifiable {
    case none
    case studio
    case shelfPlinth
    case halo
    case duotone
    case blackWhite

    var id: String { rawValue }
}

/// One gradient stop — matches PowerPoint (color, position %, transparency %, brightness %).
struct GradientColorStop: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var colorHex: String
    /// 0…1 along the gradient axis.
    var position: Double
    /// 0 = opaque, 1 = fully transparent (PPT transparency slider).
    var transparency: Double
    /// 1 = 100% brightness (PPT brightness slider).
    var brightness: Double

    init(
        id: UUID = UUID(),
        colorHex: String,
        position: Double,
        transparency: Double = 0,
        brightness: Double = 1
    ) {
        self.id = id
        self.colorHex = colorHex
        self.position = min(1, max(0, position))
        self.transparency = min(1, max(0, transparency))
        self.brightness = min(2, max(0, brightness))
    }

    static func evenDistribution(hexes: [String]) -> [GradientColorStop] {
        let colors = hexes.isEmpty ? ["#FFFFFF", "#E8E8E8"] : hexes
        if colors.count == 1 {
            return [GradientColorStop(colorHex: colors[0], position: 0)]
        }
        return colors.enumerated().map { index, hex in
            let t = colors.count == 1 ? 0.0 : Double(index) / Double(colors.count - 1)
            return GradientColorStop(colorHex: hex, position: t)
        }
    }

    func uiColor() -> UIColor {
        guard let base = UIColor(hexString: colorHex) else { return .white }
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        base.getRed(&r, green: &g, blue: &b, alpha: &a)
        let factor = CGFloat(brightness)
        r = min(1, max(0, r * factor))
        g = min(1, max(0, g * factor))
        b = min(1, max(0, b * factor))
        a = min(1, max(0, a * CGFloat(1 - transparency)))
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

struct BackgroundFillSpec: Equatable, Codable {
    var fillKind: BackgroundFillKind = .gradient
    var gradientType: GradientFillType = .linear
    var gradientDirection: GradientFillDirection = .bottomTrailing
    var gradientAngleDegrees: Double = 135
    /// Subtle film grain (0…1). Default 0.02 reduces banding on export.
    var gradientNoise: Double = 0.02
    var overlay: BackgroundPresetOverlay = .none
    var gradientStops: [GradientColorStop] = GradientColorStop.evenDistribution(hexes: ["#FFFFFF", "#ECEFF5"])
    /// Active image background when `fillKind == .image`.
    var imageSelection: ImageBackgroundSelection?

    var colorHexes: [String] { gradientStops.map(\.colorHex) }

    var minimumStopCount: Int { fillKind == .solid ? 1 : 2 }
    var minimumColorCount: Int { minimumStopCount }

    static let catalogWhite = BackgroundFillSpec(
        fillKind: .solid,
        gradientType: .linear,
        gradientDirection: .bottomTrailing,
        overlay: .none,
        gradientStops: [GradientColorStop(colorHex: "#FFFFFF", position: 0)]
    )

    mutating func normalizeStops() {
        if fillKind == .image {
            normalizeImageSelection()
            return
        }
        if fillKind == .solid {
            let hex = gradientStops.first?.colorHex ?? "#FFFFFF"
            gradientStops = [GradientColorStop(colorHex: hex, position: 0)]
            return
        }
        if gradientStops.count < 2 {
            let a = gradientStops.first?.colorHex ?? "#FFFFFF"
            let b = gradientStops.last?.colorHex ?? "#E8E8E8"
            gradientStops = [
                GradientColorStop(colorHex: a, position: 0, transparency: gradientStops.first?.transparency ?? 0, brightness: gradientStops.first?.brightness ?? 1),
                GradientColorStop(colorHex: b, position: 1, transparency: gradientStops.last?.transparency ?? 0, brightness: gradientStops.last?.brightness ?? 1),
            ]
        }
        gradientStops.sort { $0.position < $1.position }
        pinEdgeStopPositions()
    }

    /// PPT keeps the first and last stops at 0% and 100%.
    mutating func pinEdgeStopPositions() {
        guard fillKind == .gradient, gradientStops.count >= 2 else { return }
        gradientStops.sort { $0.position < $1.position }
        gradientStops[0].position = 0
        gradientStops[gradientStops.count - 1].position = 1
    }

    mutating func normalizeImageSelection() {
        guard fillKind == .image else { return }
        if imageSelection == nil {
            imageSelection = .defaultSelection()
        }
        guard var selection = imageSelection else { return }
        selection.placement.scaleMultiplier = max(0.25, min(selection.placement.scaleMultiplier, 2.5))
        selection.placement.offsetXNormalized = max(-1, min(selection.placement.offsetXNormalized, 1))
        selection.placement.offsetYNormalized = max(-1, min(selection.placement.offsetYNormalized, 1))
        selection.backgroundBlur = max(0, min(selection.backgroundBlur, 40))
        selection.reflectionOpacity = max(0, min(selection.reflectionOpacity, 1))
        imageSelection = selection
    }

    func legacyCanvasStyle() -> BackgroundCanvasStyle {
        if fillKind == .image { return .solid }
        if fillKind == .solid { return .solid }
        switch overlay {
        case .shelfPlinth: return .shelfPlinth
        case .blackWhite: return .blackWhite
        case .studio: return .studio
        case .halo: return .doubleHalo
        case .duotone: return .duotone
        case .none:
            switch gradientType {
            case .linear:
                return gradientDirection == .bottomTrailing || gradientDirection == .topLeading ? .diagonalGradient : .linearGradient
            case .radial: return .radialGradient
            case .angular: return .colorBackdrop
            case .mesh: return .seamless
            case .shadeFromTitle: return .studio
            }
        }
    }

    static func fromLegacy(style: BackgroundCanvasStyle, hexes: [String]) -> BackgroundFillSpec {
        let colors = hexes.isEmpty ? ["#FFFFFF"] : hexes
        var spec: BackgroundFillSpec
        switch style {
        case .solid:
            spec = BackgroundFillSpec(fillKind: .solid, gradientStops: [GradientColorStop(colorHex: colors[0], position: 0)])
        case .linearGradient:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .linear, gradientDirection: .bottom, gradientStops: GradientColorStop.evenDistribution(hexes: colors))
        case .diagonalGradient:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .linear, gradientDirection: .bottomTrailing, gradientStops: GradientColorStop.evenDistribution(hexes: colors))
        case .radialGradient:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .radial, gradientDirection: .center, gradientStops: GradientColorStop.evenDistribution(hexes: colors))
        case .seamless, .seamlessMono, .colorBackdrop, .colorWash:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .linear, gradientDirection: .bottom, gradientStops: GradientColorStop.evenDistribution(hexes: colors))
        case .duotone:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .linear, gradientDirection: .bottomTrailing, overlay: .duotone, gradientStops: GradientColorStop.evenDistribution(hexes: colors))
        case .overprint:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .linear, gradientDirection: .topLeading, overlay: .duotone, gradientStops: GradientColorStop.evenDistribution(hexes: colors))
        case .studio:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .shadeFromTitle, gradientDirection: .bottom, overlay: .studio, gradientStops: GradientColorStop.evenDistribution(hexes: colors))
        case .blackWhite:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .linear, gradientDirection: .bottom, overlay: .blackWhite, gradientStops: GradientColorStop.evenDistribution(hexes: ["#FFFFFF", "#161616"]))
        case .doubleHalo:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .radial, gradientDirection: .bottom, overlay: .halo, gradientStops: GradientColorStop.evenDistribution(hexes: colors))
        case .softFloor:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .linear, gradientDirection: .bottom, overlay: .studio, gradientStops: GradientColorStop.evenDistribution(hexes: colors))
        case .shelfPlinth:
            spec = BackgroundFillSpec(fillKind: .gradient, gradientType: .linear, gradientDirection: .bottom, overlay: .shelfPlinth, gradientStops: GradientColorStop.evenDistribution(hexes: colors))
        }
        spec.gradientAngleDegrees = spec.gradientDirection.defaultAngleDegrees
        return spec
    }
}

// MARK: - Built-in PPT preset gradients (Office-style)

struct PPTBuiltinGradient: Identifiable {
    let id: String
    let title: String
    let spec: BackgroundFillSpec
}

enum PPTBuiltinGradientLibrary {
    static let all: [PPTBuiltinGradient] = [
        PPTBuiltinGradient(id: "ppt-pearl", title: "Pearl", spec: make(.linear, .bottom, ["#FFFFFF", "#E8ECF2"])),
        PPTBuiltinGradient(id: "ppt-silver", title: "Silver", spec: make(.linear, .bottom, ["#F5F5F5", "#B0B0B0"])),
        PPTBuiltinGradient(id: "ppt-gold", title: "Gold", spec: make(.linear, .bottomTrailing, ["#FFF4D6", "#C9A227"])),
        PPTBuiltinGradient(id: "ppt-sunset", title: "Sunset", spec: make(.linear, .bottomTrailing, ["#FFE8A3", "#FF6B6B", "#8E44AD"])),
        PPTBuiltinGradient(id: "ppt-ocean", title: "Ocean", spec: make(.linear, .bottom, ["#E0F4FF", "#2193B0", "#0B3C5D"])),
        PPTBuiltinGradient(id: "ppt-forest", title: "Forest", spec: make(.linear, .bottom, ["#E8F5E9", "#43A047", "#1B5E20"])),
        PPTBuiltinGradient(id: "ppt-royal", title: "Royal", spec: make(.radial, .center, ["#4A148C", "#7B1FA2", "#E1BEE7"])),
        PPTBuiltinGradient(id: "ppt-charcoal", title: "Charcoal", spec: make(.linear, .bottom, ["#616161", "#212121"])),
        PPTBuiltinGradient(id: "ppt-blush", title: "Blush", spec: make(.radial, .center, ["#FFF0F3", "#F8BBD0", "#EC407A"])),
        PPTBuiltinGradient(id: "ppt-sky", title: "Sky", spec: make(.radial, .center, ["#E3F2FD", "#90CAF9", "#1565C0"])),
        PPTBuiltinGradient(id: "ppt-mint", title: "Mint", spec: make(.linear, .trailing, ["#E0F7FA", "#80DEEA", "#00838F"])),
        PPTBuiltinGradient(id: "ppt-lavender", title: "Lavender", spec: make(.linear, .bottomLeading, ["#F3E5F5", "#CE93D8", "#6A1B9A"])),
    ]

    private static func make(_ type: GradientFillType, _ dir: GradientFillDirection, _ hexes: [String]) -> BackgroundFillSpec {
        var spec = BackgroundFillSpec(
            fillKind: .gradient,
            gradientType: type,
            gradientDirection: dir,
            gradientAngleDegrees: dir.defaultAngleDegrees,
            overlay: .none,
            gradientStops: GradientColorStop.evenDistribution(hexes: hexes)
        )
        spec.normalizeStops()
        return spec
    }
}

// MARK: - Grouped gradient libraries (Format Background swiper)

struct GradientPresetGroup: Identifiable {
    let id: String
    let title: String
    let presets: [BackgroundScenePreset]
}

enum GradientPresetGroupLibrary {
    static let all: [GradientPresetGroup] =
        GradientPresetCatalog.extendedGroups + [
            GradientPresetGroup(id: "studio", title: "Product Studio", presets: studioPresets),
            GradientPresetGroup(id: "classic", title: "Classic", presets: classicPresets),
            GradientPresetGroup(id: "holo-light", title: "Holographic Light", presets: holographicLightPresets),
            GradientPresetGroup(id: "holo-dark", title: "Holographic Dark", presets: holographicDarkPresets),
            GradientPresetGroup(id: "cool", title: "Cool Gradients", presets: coolGradientPresets),
        ]

    static func group(id: String) -> GradientPresetGroup? {
        all.first { $0.id == id }
    }

    static func groupContainingPreset(id presetID: String) -> GradientPresetGroup? {
        all.first { group in group.presets.contains { $0.id == presetID } }
    }

    /// Shared builder for catalog + inline preset tables.
    static func catalogPreset(
        _ id: String,
        _ title: String,
        _ hexes: [String],
        type: GradientFillType = .linear,
        dir: GradientFillDirection = .bottomTrailing,
        angle: Double = 135
    ) -> BackgroundScenePreset {
        preset(id, title, hexes, type: type, dir: dir, angle: angle)
    }

    private static let studioPresets: [BackgroundScenePreset] = BackgroundScenePresetLibrary.all.filter {
        $0.category != "Classic"
    }

    private static let classicPresets: [BackgroundScenePreset] = PPTBuiltinGradientLibrary.all.map {
        BackgroundScenePreset(id: "ppt-\($0.id)", title: $0.title, category: "Classic", spec: $0.spec)
    }

    private static let holographicLightPresets: [BackgroundScenePreset] = [
        preset("holo-light-aurora", "Aurora Mist", ["#FFE5F1", "#C9F0FF", "#E8D5FF", "#FFF8E7"]),
        preset("holo-light-pearl", "Pearl Shift", ["#FFFFFF", "#F0E6FF", "#E0F7FA", "#FFF0F5"]),
        preset("holo-light-cotton", "Cotton Candy", ["#FFD6E8", "#D4F1FF", "#F5E6FF"]),
        preset("holo-light-mint", "Mint Prism", ["#E8FFF8", "#C5F5E8", "#B8E8FF", "#F0E8FF"]),
        preset("holo-light-sunrise", "Sunrise Holo", ["#FFF4E6", "#FFE0EC", "#E0F0FF", "#F5E0FF"]),
        preset("holo-light-ice", "Ice Crystal", ["#F8FDFF", "#E3F4FF", "#EDE7FF", "#F0FFF8"]),
        preset("holo-light-blush", "Blush Wave", ["#FFF0F3", "#F8E1FF", "#E1F5FE"]),
        preset("holo-light-lemon", "Lemon Haze", ["#FFFDE7", "#E8F5E9", "#E1F5FE", "#F3E5F5"]),
        preset("holo-light-opal", "Opal Glow", ["#FAFAFA", "#E8EAF6", "#E0F2F1", "#FCE4EC"]),
        preset("holo-light-sky", "Sky Iridescent", ["#E3F2FD", "#F3E5F5", "#E8F5E9", "#FFF8E1"]),
        preset("holo-light-rose", "Rose Quartz", ["#FCE4EC", "#F3E5F5", "#E1F5FE"]),
        preset("holo-light-champagne", "Champagne Holo", ["#FFF8E7", "#F5F0FF", "#E8F4F8"]),
    ]

    private static let holographicDarkPresets: [BackgroundScenePreset] = [
        preset("holo-dark-nebula", "Nebula", ["#0D0221", "#261447", "#4A148C", "#880E4F"], type: .radial, dir: .center),
        preset("holo-dark-midnight", "Midnight Prism", ["#0A0E27", "#1A237E", "#4A148C", "#006064"]),
        preset("holo-dark-void", "Void Shift", ["#050508", "#1A1A2E", "#16213E", "#0F3460"]),
        preset("holo-dark-amethyst", "Amethyst", ["#120338", "#2D1B69", "#6A1B9A", "#AD1457"]),
        preset("holo-dark-ocean", "Deep Ocean Holo", ["#0B132B", "#1C2541", "#3A506B", "#5BC0BE"]),
        preset("holo-dark-ember", "Ember Holo", ["#1A0A0A", "#4A1942", "#7B2D8E", "#C74B50"]),
        preset("holo-dark-forest", "Forest Night", ["#0B1F0E", "#1B4332", "#2D6A4F", "#40916C"]),
        preset("holo-dark-cosmic", "Cosmic", ["#0F0C29", "#302B63", "#24243E", "#8360C3"]),
        preset("holo-dark-teal", "Teal Abyss", ["#0A1628", "#0D2137", "#1A535C", "#4ECDC4"]),
        preset("holo-dark-wine", "Wine Holo", ["#1A0A10", "#4A0E2E", "#7B1F4D", "#C2185B"]),
        preset("holo-dark-slate", "Slate Prism", ["#0F1419", "#1E293B", "#334155", "#475569"]),
        preset("holo-dark-aurora", "Dark Aurora", ["#0B1026", "#1B1464", "#6C3483", "#1ABC9C"]),
    ]

    private static let coolGradientPresets: [BackgroundScenePreset] = [
        preset("cool-arctic", "Arctic", ["#E0F7FA", "#80DEEA", "#0097A7", "#004D40"]),
        preset("cool-glacier", "Glacier", ["#E3F2FD", "#90CAF9", "#1565C0", "#0D47A1"]),
        preset("cool-steel", "Steel Blue", ["#ECEFF1", "#90A4AE", "#546E7A", "#263238"]),
        preset("cool-mint", "Cool Mint", ["#E0F2F1", "#80CBC4", "#00897B", "#004D40"]),
        preset("cool-twilight", "Twilight", ["#E8EAF6", "#7986CB", "#3949AB", "#1A237E"]),
        preset("cool-ocean", "Ocean Cool", ["#B2EBF2", "#4DD0E1", "#0097A7", "#006064"]),
        preset("cool-frost", "Frost", ["#F5FDFF", "#B3E5FC", "#4FC3F7", "#0288D1"]),
        preset("cool-petrol", "Petrol", ["#263238", "#37474F", "#546E7A", "#78909C"]),
        preset("cool-iceberg", "Iceberg", ["#E1F5FE", "#81D4FA", "#29B6F6", "#0277BD"]),
        preset("cool-slate", "Slate Cool", ["#CFD8DC", "#78909C", "#455A64", "#263238"]),
        preset("cool-azure", "Azure", ["#E3F2FD", "#64B5F6", "#1976D2", "#0D47A1"]),
        preset("cool-teal", "Teal Cool", ["#B2DFDB", "#4DB6AC", "#00897B", "#00695C"]),
    ]

    fileprivate static func preset(
        _ id: String,
        _ title: String,
        _ hexes: [String],
        type: GradientFillType = .linear,
        dir: GradientFillDirection = .bottomTrailing,
        angle: Double? = nil
    ) -> BackgroundScenePreset {
        var spec = BackgroundFillSpec(
            fillKind: .gradient,
            gradientType: type,
            gradientDirection: dir,
            gradientAngleDegrees: angle ?? dir.defaultAngleDegrees,
            overlay: .none,
            gradientStops: GradientColorStop.evenDistribution(hexes: hexes)
        )
        spec.normalizeStops()
        return BackgroundScenePreset(id: id, title: title, category: "Gradients", spec: spec)
    }
}

// MARK: - Product Studio presets (all premium + gradient chips)

struct BackgroundScenePreset: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
    let spec: BackgroundFillSpec

    static func == (lhs: BackgroundScenePreset, rhs: BackgroundScenePreset) -> Bool {
        lhs.id == rhs.id
    }
}

enum BackgroundScenePresetLibrary {
    /// Every curated Product Studio look (premium quick presets + gradient chips).
    static let all: [BackgroundScenePreset] = premiumPresets + gradientChipPresets

    static var categories: [String] {
        Array(Set(all.map(\.category))).sorted()
    }

    static func presets(in category: String) -> [BackgroundScenePreset] {
        all.filter { $0.category == category }
    }

    private static let premiumPresets: [BackgroundScenePreset] = BackgroundQuickPreset.allCases.map { quick in
        BackgroundScenePreset(
            id: "premium-\(quick.rawValue)",
            title: quick.rawValue,
            category: quick.category.rawValue,
            spec: BackgroundFillSpec.fromLegacy(style: quick.style, hexes: quick.hexes)
        )
    }

    private static let gradientChipPresets: [BackgroundScenePreset] = ProductGradientChip.allCases.map { chip in
        BackgroundScenePreset(
            id: "chip-\(chip.rawValue)",
            title: chip.title,
            category: "Gradient chips",
            spec: chip.spec
        )
    }
}

/// All in-app gradient chip presets (restored full set).
enum ProductGradientChip: String, CaseIterable, Identifiable {
    case cleanStudio, softSky, midnightLuxury, sunsetPremium, emeraldGlow, violetNeon
    case copperWarm, tealMarket, noirShelf, roseMist, goldMist, slateWash
    case sageMeadow, rustSun, auroraFlow, peachFuzzBlend, oceanDepth, lilacDream
    case forestCanopy, sunsetCoral, icyMint, berryWine, charcoalRose, goldenHourHaze, neonTwilight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleanStudio: return "Studio"
        case .softSky: return "Sky"
        case .midnightLuxury: return "Midnight"
        case .sunsetPremium: return "Sunset"
        case .emeraldGlow: return "Emerald"
        case .violetNeon: return "Neon"
        case .copperWarm: return "Copper"
        case .tealMarket: return "Teal"
        case .noirShelf: return "Noir"
        case .roseMist: return "Rose"
        case .goldMist: return "Gold"
        case .slateWash: return "Slate"
        case .sageMeadow: return "Sage"
        case .rustSun: return "Rust"
        case .auroraFlow: return "Aurora"
        case .peachFuzzBlend: return "Peach Fuzz"
        case .oceanDepth: return "Ocean"
        case .lilacDream: return "Lilac"
        case .forestCanopy: return "Forest"
        case .sunsetCoral: return "Coral"
        case .icyMint: return "Icy Mint"
        case .berryWine: return "Berry"
        case .charcoalRose: return "Charcoal Rose"
        case .goldenHourHaze: return "Golden Haze"
        case .neonTwilight: return "Neon Dusk"
        }
    }

    var spec: BackgroundFillSpec {
        let hexes: [String]
        let type: GradientFillType
        let dir: GradientFillDirection
        let overlay: BackgroundPresetOverlay
        switch self {
        case .cleanStudio:
            hexes = ["#FFFFFF", "#ECEFF5", "#D8DDE8"]; type = .shadeFromTitle; dir = .bottom; overlay = .studio
        case .softSky:
            hexes = ["#D7E7FF", "#F3F8FF", "#DCEBFF"]; type = .radial; dir = .bottom; overlay = .none
        case .midnightLuxury:
            hexes = ["#131625", "#2D345E", "#7080C7"]; type = .radial; dir = .bottom; overlay = .halo
        case .sunsetPremium:
            hexes = ["#FFD1A4", "#FFAA8A", "#D27BCF"]; type = .linear; dir = .bottomTrailing; overlay = .none
        case .emeraldGlow:
            hexes = ["#D2FFE7", "#8BEBC0", "#2FAE90"]; type = .linear; dir = .bottom; overlay = .none
        case .violetNeon:
            hexes = ["#2A114A", "#7026C5", "#E03BFF"]; type = .radial; dir = .topTrailing; overlay = .none
        case .copperWarm:
            hexes = ["#FFF4E8", "#E8C9A0", "#B87333"]; type = .linear; dir = .bottom; overlay = .none
        case .tealMarket:
            hexes = ["#E8F7F4", "#B8E3DA", "#3D8B7E"]; type = .linear; dir = .bottom; overlay = .none
        case .noirShelf:
            hexes = ["#1A1A1E", "#2E2E36", "#5A5A68"]; type = .linear; dir = .bottom; overlay = .shelfPlinth
        case .roseMist:
            hexes = ["#FFF5F8", "#FAD6E0", "#E86B9A"]; type = .linear; dir = .bottom; overlay = .none
        case .goldMist:
            hexes = ["#FFF9EC", "#F3E0B8", "#C9A227"]; type = .linear; dir = .bottom; overlay = .studio
        case .slateWash:
            hexes = ["#ECEEF2", "#C5CAD3", "#6B7380"]; type = .linear; dir = .bottom; overlay = .none
        case .sageMeadow:
            hexes = ["#F2FFF6", "#C8EDD4", "#4FA86C"]; type = .linear; dir = .bottom; overlay = .none
        case .rustSun:
            hexes = ["#FFF1E6", "#E8A06A", "#B84A1A"]; type = .radial; dir = .top; overlay = .none
        case .auroraFlow:
            hexes = ["#0B1026", "#3D2B7A", "#00C9B7", "#7AFCF4"]; type = .linear; dir = .bottomTrailing; overlay = .none
        case .peachFuzzBlend:
            hexes = ["#FFF8F2", "#F7D7C4", "#E8A598", "#C76B5E"]; type = .radial; dir = .bottom; overlay = .none
        case .oceanDepth:
            hexes = ["#02111E", "#0B3C5D", "#328CC1", "#D9E8F5"]; type = .linear; dir = .bottom; overlay = .none
        case .lilacDream:
            hexes = ["#F7F0FF", "#DCC4F7", "#9B6BFF", "#4E1A8C"]; type = .radial; dir = .bottom; overlay = .none
        case .forestCanopy:
            hexes = ["#E9F5E3", "#7CB342", "#1B3D1E", "#0D1F12"]; type = .linear; dir = .bottom; overlay = .none
        case .sunsetCoral:
            hexes = ["#FFF4EC", "#FF9B85", "#FF6B6B", "#5C1A3D"]; type = .linear; dir = .bottomTrailing; overlay = .none
        case .icyMint:
            hexes = ["#F2FFFE", "#B2F5EA", "#38B2AC", "#1A4D48"]; type = .linear; dir = .bottom; overlay = .none
        case .berryWine:
            hexes = ["#FFF0F5", "#C4717C", "#6B1E3F", "#2D0B1F"]; type = .radial; dir = .bottomLeading; overlay = .none
        case .charcoalRose:
            hexes = ["#FCEFF3", "#B5838D", "#3A2E39", "#1C1420"]; type = .linear; dir = .bottom; overlay = .none
        case .goldenHourHaze:
            hexes = ["#FFF9E6", "#FFD27F", "#F4A259", "#BC6C25"]; type = .radial; dir = .top; overlay = .none
        case .neonTwilight:
            hexes = ["#120826", "#3D2066", "#FF00AA", "#00E5FF"]; type = .radial; dir = .bottom; overlay = .halo
        }
        var spec = BackgroundFillSpec(
            fillKind: .gradient,
            gradientType: type,
            gradientDirection: dir,
            gradientAngleDegrees: dir.defaultAngleDegrees,
            overlay: overlay,
            gradientStops: GradientColorStop.evenDistribution(hexes: hexes)
        )
        spec.normalizeStops()
        return spec
    }
}

// MARK: - Rendering

enum BackgroundFillRenderer {
    static func draw(
        in rect: CGRect,
        context: CGContext,
        primary: UIColor,
        secondary: UIColor,
        spec: BackgroundFillSpec
    ) {
        var working = spec
        working.normalizeStops()

        func linear(_ colors: [CGColor], _ locations: [CGFloat], _ start: CGPoint, _ end: CGPoint) {
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }
            context.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
        func radial(_ colors: [CGColor], _ locations: [CGFloat], _ center: CGPoint, _ radius: CGFloat) {
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }

        let stops = working.gradientStops
        if working.fillKind == .image, let selection = working.imageSelection {
            ImageBackgroundRenderer.draw(in: rect, context: context, selection: selection)
            return
        }
        if working.fillKind == .solid {
            (stops.first?.uiColor() ?? primary).setFill()
            context.fill(rect)
            return
        }

        let colors = stops.map { $0.uiColor().cgColor }
        let locations = stops.map { CGFloat($0.position) }

        switch working.gradientType {
        case .linear:
            let (start, end) = angleLine(in: rect, degrees: working.gradientAngleDegrees)
            linear(colors, locations, start, end)

        case .radial:
            drawRadialGradient(in: rect, context: context, stops: stops, direction: working.gradientDirection)

        case .angular:
            let (start, end) = angleLine(in: rect, degrees: working.gradientAngleDegrees)
            linear(colors, locations, start, end)
            let (crossStart, crossEnd) = working.gradientDirection.angularCrossPoints(in: rect)
            context.saveGState()
            context.setBlendMode(.softLight)
            context.setAlpha(0.55)
            linear(colors, locations, crossStart, crossEnd)
            context.restoreGState()

        case .mesh:
            drawMeshGradient(in: rect, context: context, stops: stops, direction: working.gradientDirection)

        case .shadeFromTitle:
            linear(
                colors,
                locations,
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.midX, y: rect.maxY)
            )
            radial(
                [UIColor.white.withAlphaComponent(0.45).cgColor, UIColor.clear.cgColor],
                [0, 1],
                CGPoint(x: rect.midX, y: rect.height * 0.12),
                max(rect.width, rect.height) * 0.72
            )
        }

        applyOverlay(working.overlay, in: rect, context: context, primary: primary, secondary: secondary)
        applyNoise(working.gradientNoise, in: rect, context: context)
    }

    static func needsShelfPlinth(_ spec: BackgroundFillSpec) -> Bool {
        spec.overlay == .shelfPlinth
    }

    /// True circular radial (PPT): colors radiate by distance from the direction anchor.
    private static func drawRadialGradient(
        in rect: CGRect,
        context: CGContext,
        stops: [GradientColorStop],
        direction: GradientFillDirection
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        let center = direction.radialCenter(in: rect)
        let ncx = center.x / rect.width
        let ncy = center.y / rect.height
        let maxNorm = max(
            hypot(ncx, ncy),
            hypot(1 - ncx, ncy),
            hypot(ncx, 1 - ncy),
            hypot(1 - ncx, 1 - ncy),
            0.001
        )
        drawDistanceGradient(
            in: rect,
            context: context,
            stops: stops,
            centerNorm: CGPoint(x: ncx, y: ncy)
        ) { cx, cy, nx, ny in
            min(1, hypot(nx - cx, ny - cy) / maxNorm)
        }
    }

    /// Mesh-style falloff from a movable highlight (Chebyshev distance).
    private static func drawMeshGradient(
        in rect: CGRect,
        context: CGContext,
        stops: [GradientColorStop],
        direction: GradientFillDirection
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        let center = direction.unitCenter()
        drawDistanceGradient(
            in: rect,
            context: context,
            stops: stops,
            centerNorm: center
        ) { cx, cy, nx, ny in
            min(1, max(abs(nx - cx) * 2, abs(ny - cy) * 2))
        }
    }

    /// Full canvas resolution (capped) so radial/path fills stay sharp on export — no 512px upscale blur.
    private static func gradientSampleDimensions(for rect: CGRect) -> (Int, Int) {
        let cap = 4096
        let w = min(cap, max(1, Int(ceil(rect.width))))
        let h = min(cap, max(1, Int(ceil(rect.height))))
        return (w, h)
    }

    private static func orderedDitherOffset(x: Int, y: Int) -> CGFloat {
        let matrix: [[CGFloat]] = [[0, 2, 1, 3], [3, 1, 2, 0], [2, 0, 3, 1], [1, 3, 0, 2]]
        return (matrix[y % 4][x % 4] / 4.0 - 0.375) / 255.0
    }

    private static func drawDistanceGradient(
        in rect: CGRect,
        context: CGContext,
        stops: [GradientColorStop],
        centerNorm: CGPoint,
        metric: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGFloat
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        let (sampleW, sampleH) = gradientSampleDimensions(for: rect)
        let cx = centerNorm.x
        let cy = centerNorm.y

        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let data = ctx.data else { return }

        let pixels = data.bindMemory(to: UInt8.self, capacity: sampleW * sampleH * 4)
        for y in 0..<sampleH {
            let ny = (CGFloat(y) + 0.5) / CGFloat(sampleH)
            for x in 0..<sampleW {
                let nx = (CGFloat(x) + 0.5) / CGFloat(sampleW)
                let t = metric(cx, cy, nx, ny)
                var color = interpolatedUIColor(stops: stops, t: CGFloat(min(1, max(0, t))))
                let d = orderedDitherOffset(x: x, y: y)
                color.r = min(1, max(0, color.r + d))
                color.g = min(1, max(0, color.g + d))
                color.b = min(1, max(0, color.b + d))
                let offset = (y * sampleW + x) * 4
                pixels[offset] = UInt8(color.r * 255)
                pixels[offset + 1] = UInt8(color.g * 255)
                pixels[offset + 2] = UInt8(color.b * 255)
                pixels[offset + 3] = UInt8(color.a * 255)
            }
        }
        guard let cgImage = ctx.makeImage() else { return }
        context.saveGState()
        let sameSize = abs(rect.width - CGFloat(sampleW)) < 0.5 && abs(rect.height - CGFloat(sampleH)) < 0.5
        context.interpolationQuality = sameSize ? .none : .default
        context.draw(cgImage, in: rect)
        context.restoreGState()
    }

    private struct RGBA { var r, g, b, a: CGFloat }

    private static func interpolatedUIColor(stops: [GradientColorStop], t: CGFloat) -> RGBA {
        let sorted = stops.sorted { $0.position < $1.position }
        guard let first = sorted.first else { return RGBA(r: 1, g: 1, b: 1, a: 1) }
        if sorted.count == 1 || t <= CGFloat(first.position) { return rgba(first.uiColor()) }
        if let last = sorted.last, t >= CGFloat(last.position) { return rgba(last.uiColor()) }
        for index in 0..<(sorted.count - 1) {
            let a = sorted[index]
            let b = sorted[index + 1]
            let t0 = CGFloat(a.position)
            let t1 = CGFloat(b.position)
            guard t >= t0, t <= t1 else { continue }
            let span = max(0.0001, t1 - t0)
            let u = (t - t0) / span
            return lerp(rgba(a.uiColor()), rgba(b.uiColor()), u)
        }
        return rgba((sorted.last ?? first).uiColor())
    }

    private static func rgba(_ color: UIColor) -> RGBA {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: r, g: g, b: b, a: a)
    }

    private static func lerp(_ a: RGBA, _ b: RGBA, _ t: CGFloat) -> RGBA {
        RGBA(
            r: a.r + (b.r - a.r) * t,
            g: a.g + (b.g - a.g) * t,
            b: a.b + (b.b - a.b) * t,
            a: a.a + (b.a - a.a) * t
        )
    }

    private static func applyNoise(_ amount: Double, in rect: CGRect, context: CGContext) {
        guard amount > 0.0005, rect.width > 1, rect.height > 1 else { return }
        let strength = min(1, max(0, amount)) * 0.35
        context.saveGState()
        context.setBlendMode(.overlay)
        context.setAlpha(CGFloat(strength))
        let w = max(1, Int(ceil(rect.width / 4)))
        let h = max(1, Int(ceil(rect.height / 4)))
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let data = ctx.data else {
            context.restoreGState()
            return
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v = UInt8.random(in: 96...160)
                let offset = (y * w + x) * 4
                pixels[offset] = v
                pixels[offset + 1] = v
                pixels[offset + 2] = v
                pixels[offset + 3] = 255
            }
        }
        if let image = ctx.makeImage() {
            context.interpolationQuality = .none
            context.draw(image, in: rect)
        }
        context.restoreGState()
    }

    private static func angleLine(in rect: CGRect, degrees: Double) -> (CGPoint, CGPoint) {
        let rad = CGFloat(degrees * .pi / 180)
        let dx = cos(rad)
        let dy = sin(rad)
        let m = CGPoint(x: rect.midX, y: rect.midY)
        let len = max(rect.width, rect.height)
        return (
            CGPoint(x: m.x - dx * len, y: m.y - dy * len),
            CGPoint(x: m.x + dx * len, y: m.y + dy * len)
        )
    }

    private static func applyOverlay(
        _ overlay: BackgroundPresetOverlay,
        in rect: CGRect,
        context: CGContext,
        primary: UIColor,
        secondary: UIColor
    ) {
        func linear(_ colors: [CGColor], _ locations: [CGFloat], _ start: CGPoint, _ end: CGPoint) {
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }
            context.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
        func radial(_ colors: [CGColor], _ locations: [CGFloat], _ center: CGPoint, _ radius: CGFloat) {
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }

        switch overlay {
        case .none: break
        case .blackWhite:
            linear(
                [UIColor.white.cgColor, UIColor(white: 0.90, alpha: 1).cgColor, UIColor(white: 0.12, alpha: 1).cgColor],
                [0, 0.62, 1],
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.midX, y: rect.maxY)
            )
        case .studio:
            linear(
                [UIColor.white.withAlphaComponent(0.42).cgColor, UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.06).cgColor],
                [0, 0.55, 1],
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.midX, y: rect.maxY)
            )
            radial(
                [UIColor.white.withAlphaComponent(0.30).cgColor, UIColor.clear.cgColor],
                [0, 1],
                CGPoint(x: rect.midX, y: rect.height * 0.34),
                rect.width * 0.52
            )
        case .halo:
            radial([secondary.withAlphaComponent(0.72).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.36, y: rect.height * 0.34), rect.width * 0.62)
            radial([UIColor.white.withAlphaComponent(0.28).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.66, y: rect.height * 0.23), rect.width * 0.48)
        case .duotone:
            context.saveGState()
            context.setBlendMode(.screen)
            radial([secondary.withAlphaComponent(0.35).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.72, y: rect.height * 0.22), rect.width * 0.62)
            context.setBlendMode(.softLight)
            radial([primary.withAlphaComponent(0.35).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.20, y: rect.height * 0.80), rect.width * 0.70)
            context.restoreGState()
        case .shelfPlinth: break
        }
    }
}

// MARK: - SwiftUI preview

enum BackgroundFillPreview {
    static func renderedImage(spec: BackgroundFillSpec, size: CGSize = CGSize(width: 120, height: 44)) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            BackgroundFillRenderer.draw(
                in: CGRect(origin: .zero, size: size),
                context: ctx.cgContext,
                primary: .white,
                secondary: .lightGray,
                spec: spec
            )
        }
    }

    static func shape(spec: BackgroundFillSpec) -> some ShapeStyle {
        AnyShapeStyle(ImagePaint(image: Image(uiImage: renderedImage(spec: spec)), scale: 1))
    }

    private static func swiftUIDirection(_ d: GradientFillDirection) -> (UnitPoint, UnitPoint) {
        switch d {
        case .center: return (.leading, .trailing)
        case .top: return (.bottom, .top)
        case .bottom: return (.top, .bottom)
        case .leading: return (.trailing, .leading)
        case .trailing: return (.leading, .trailing)
        case .topTrailing: return (.bottomLeading, .topTrailing)
        case .topLeading: return (.bottomTrailing, .topLeading)
        case .bottomTrailing: return (.topLeading, .bottomTrailing)
        case .bottomLeading: return (.topTrailing, .bottomLeading)
        }
    }

    private static func swiftUIAnglePoints(degrees: Double) -> (UnitPoint, UnitPoint) {
        let rad = degrees * .pi / 180
        let dx = cos(rad)
        let dy = sin(rad)
        return (
            UnitPoint(x: 0.5 - dx * 0.5, y: 0.5 + dy * 0.5),
            UnitPoint(x: 0.5 + dx * 0.5, y: 0.5 - dy * 0.5)
        )
    }

    private static func swiftUIRadialCenter(_ d: GradientFillDirection) -> UnitPoint {
        switch d {
        case .center: return UnitPoint(x: 0.5, y: 0.5)
        case .top: return UnitPoint(x: 0.5, y: 0.88)
        case .bottom: return UnitPoint(x: 0.5, y: 0.12)
        case .leading: return UnitPoint(x: 0.88, y: 0.5)
        case .trailing: return UnitPoint(x: 0.12, y: 0.5)
        case .topTrailing: return UnitPoint(x: 0.1, y: 0.9)
        case .topLeading: return UnitPoint(x: 0.9, y: 0.9)
        case .bottomTrailing: return UnitPoint(x: 0.1, y: 0.1)
        case .bottomLeading: return UnitPoint(x: 0.9, y: 0.1)
        }
    }
}

// MARK: - Persistence helpers

extension BackgroundFillSpec {
    static func loadFromUserDefaults(key: String, fallbackStyle: BackgroundCanvasStyle, fallbackHexes: [String]) -> BackgroundFillSpec {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(BackgroundFillSpec.self, from: data) else {
            return fromLegacy(style: fallbackStyle, hexes: fallbackHexes)
        }
        return decoded
    }

    func saveToUserDefaults(key: String) {
        if let data = encodedData() {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func encodedData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data?) -> BackgroundFillSpec? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(BackgroundFillSpec.self, from: data)
    }
}
