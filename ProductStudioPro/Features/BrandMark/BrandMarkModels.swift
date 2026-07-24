import Foundation
import UIKit

/// Nine-slot placement for text / logo watermarks on catalog exports.
enum BrandMarkPosition: String, CaseIterable, Codable, Identifiable, Hashable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case middleCenter
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .middleCenter: return "Center"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }

    var gridLetter: String {
        switch self {
        case .topLeft: return "TL"
        case .topCenter: return "TC"
        case .topRight: return "TR"
        case .middleLeft: return "ML"
        case .middleCenter: return "C"
        case .middleRight: return "MR"
        case .bottomLeft: return "BL"
        case .bottomCenter: return "BC"
        case .bottomRight: return "BR"
        }
    }

    static var gridRows: [[BrandMarkPosition]] {
        [
            [.topLeft, .topCenter, .topRight],
            [.middleLeft, .middleCenter, .middleRight],
            [.bottomLeft, .bottomCenter, .bottomRight]
        ]
    }
}

/// Watermark text weight / italic style.
enum BrandMarkFontStyle: String, CaseIterable, Codable, Identifiable, Hashable {
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case italic
    case boldItalic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        case .heavy: return "Heavy"
        case .italic: return "Italic"
        case .boldItalic: return "Bold Italic"
        }
    }

    var weight: UIFont.Weight {
        switch self {
        case .light: return .light
        case .regular, .italic: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold, .boldItalic: return .bold
        case .heavy: return .heavy
        }
    }

    var isItalic: Bool {
        self == .italic || self == .boldItalic
    }
}

/// Typeface resolution for Brand Mark text (full system font list via UIFontPicker, same as Markup).
enum BrandMarkFontCatalog {
    /// Display title for the Font tab.
    static func displayName(postScriptName: String?) -> String {
        guard let postScriptName, !postScriptName.isEmpty,
              let font = UIFont(name: postScriptName, size: 17) else {
            return "System"
        }
        return font.familyName
    }

    static func uiFont(
        postScriptName: String?,
        size: CGFloat,
        style: BrandMarkFontStyle
    ) -> UIFont {
        let pointSize = max(1, size)

        // System (no custom font picked) — weight/italic must track Style exactly.
        guard let postScriptName, !postScriptName.isEmpty,
              let seed = UIFont(name: postScriptName, size: pointSize) else {
            return systemFont(size: pointSize, style: style)
        }

        let family = seed.familyName
        let faces = UIFont.fontNames(forFamilyName: family)

        // 1) Prefer an installed face whose weight/italic class matches the Style control.
        if let face = bestFace(in: faces, style: style),
           let matched = UIFont(name: face, size: pointSize) {
            return matched
        }

        // 2) Ask Core Text for family + weight (+ italic) via descriptor.
        if let fromDescriptor = fontFromFamilyDescriptor(family: family, size: pointSize, style: style) {
            return fromDescriptor
        }

        // 3) Last resort: start from the picked face and force traits.
        if let traited = applyTraits(to: seed, style: style) {
            return traited
        }
        return seed
    }

    private static func systemFont(size: CGFloat, style: BrandMarkFontStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: style.weight)
        guard style.isItalic else { return base }
        if let italicDesc = base.fontDescriptor.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: italicDesc, size: size)
        }
        return base
    }

    private static func fontFromFamilyDescriptor(
        family: String,
        size: CGFloat,
        style: BrandMarkFontStyle
    ) -> UIFont? {
        let weighted = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: style.weight]
        ])
        let descriptor: UIFontDescriptor
        if style.isItalic {
            guard let italic = weighted.withSymbolicTraits(.traitItalic) else { return nil }
            descriptor = italic
        } else {
            descriptor = weighted
        }
        let font = UIFont(descriptor: descriptor, size: size)
        // Reject fallbacks that silently jumped to a different family (e.g. Times).
        guard font.familyName.caseInsensitiveCompare(family) == .orderedSame else { return nil }
        return font
    }

    /// Weight bucket used to match Style → installed face names.
    private enum WeightBucket: Int, Comparable {
        case ultraLight = 0
        case thin = 1
        case light = 2
        case regular = 3
        case medium = 4
        case semibold = 5
        case bold = 6
        case heavy = 7
        case black = 8

        static func < (lhs: WeightBucket, rhs: WeightBucket) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        static func from(style: BrandMarkFontStyle) -> WeightBucket {
            switch style {
            case .light: return .light
            case .regular, .italic: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold, .boldItalic: return .bold
            case .heavy: return .heavy
            }
        }

        static func from(faceName: String) -> WeightBucket {
            let l = faceName.lowercased()
            if l.contains("ultralight") || l.contains("extra light") { return .ultraLight }
            if l.contains("thin") { return .thin }
            if l.contains("light") { return .light }
            if l.contains("black") || l.contains("extra bold") || l.contains("ultrabold") { return .black }
            if l.contains("heavy") { return .heavy }
            if l.contains("semibold") || l.contains("demi") { return .semibold }
            // "bold" after semibold check so "Bold" ≠ "Semibold"
            if l.contains("bold") { return .bold }
            if l.contains("medium") { return .medium }
            if l.contains("regular") || l.contains("book") || l.contains("roman") || l.contains("normal") {
                return .regular
            }
            // Bare family faces (e.g. "Futura") usually read as medium/regular.
            return .regular
        }
    }

    private static func bestFace(in faces: [String], style: BrandMarkFontStyle) -> String? {
        guard !faces.isEmpty else { return nil }
        let wantWeight = WeightBucket.from(style: style)
        let wantItalic = style.isItalic

        let ranked = faces.map { face -> (String, Int) in
            (face, faceScore(face, wantWeight: wantWeight, wantItalic: wantItalic))
        }
        .sorted { $0.1 > $1.1 }

        guard let best = ranked.first, best.1 > 0 else { return nil }
        return best.0
    }

    private static func faceScore(
        _ face: String,
        wantWeight: WeightBucket,
        wantItalic: Bool
    ) -> Int {
        let lower = face.lowercased()
        let faceWeight = WeightBucket.from(faceName: face)
        let faceItalic = lower.contains("italic") || lower.contains("oblique")

        var score = 0

        // Strong weight match — this is what makes Light/Medium/Bold actually differ.
        let weightDelta = abs(faceWeight.rawValue - wantWeight.rawValue)
        switch weightDelta {
        case 0: score += 100
        case 1: score += 35
        case 2: score += 5
        default: score -= 40
        }

        if wantItalic == faceItalic {
            score += 50
        } else {
            score -= 60
        }

        // Prefer non-condensed / non-display variants for catalog stamps.
        if lower.contains("condensed") || lower.contains("compressed") || lower.contains("narrow") {
            score -= 25
        }
        if lower.contains("display") || lower.contains("poster") {
            score -= 10
        }

        return score
    }

    private static func applyTraits(to font: UIFont, style: BrandMarkFontStyle) -> UIFont? {
        let base = font.fontDescriptor
        var symbolic = base.symbolicTraits
        if style.isItalic {
            symbolic.insert(.traitItalic)
        } else {
            symbolic.remove(.traitItalic)
        }
        if style.weight.rawValue >= UIFont.Weight.bold.rawValue {
            symbolic.insert(.traitBold)
        } else {
            symbolic.remove(.traitBold)
        }
        guard let withSymbolic = base.withSymbolicTraits(symbolic) else { return nil }
        let weighted = withSymbolic.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: style.weight]
        ])
        return UIFont(descriptor: weighted, size: font.pointSize)
    }

    /// Migrates legacy System / Rounded / Serif / Mono design picks into a postscript name.
    static func postScriptName(fromLegacyFamilyRaw raw: String?) -> String? {
        guard let raw,
              let family = LegacyBrandMarkFontFamily(rawValue: raw) else { return nil }
        switch family {
        case .system:
            return nil
        case .rounded, .serif, .monospaced:
            let design: UIFontDescriptor.SystemDesign = {
                switch family {
                case .rounded: return .rounded
                case .serif: return .serif
                case .monospaced: return .monospaced
                case .system: return .default
                }
            }()
            let base = UIFont.systemFont(ofSize: 17, weight: .regular)
            let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
            return UIFont(descriptor: descriptor, size: 17).fontDescriptor.postscriptName
        }
    }

    private enum LegacyBrandMarkFontFamily: String {
        case system, rounded, serif, monospaced
    }
}

/// Preset watermark text sizes in canvas pixels (Custom… allows any value in range).
enum BrandMarkFontSizePreset {
    static let options: [Int] = [12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72]
    static let `default` = 36
    static let minimum = 8
    static let maximum = 200

    static func clamped(_ value: Int) -> Int {
        min(maximum, max(minimum, value))
    }

    static func isPreset(_ value: Int) -> Bool {
        options.contains(value)
    }
}

/// Safe ranges for Brand Kit layer opacities (caption plate vs logo are independent).
enum BrandMarkOpacityRange {
    static let logoMin = 0.15
    static let logoMax = 0.70
    static let logoDefault = 0.38
    static let plateMin = 0.12
    static let plateMax = 0.55
    /// Soft chip that stays readable without fogging the product.
    static let plateDefault = 0.28

    static func clampLogo(_ value: Double) -> Double {
        min(logoMax, max(logoMin, value))
    }

    static func clampPlate(_ value: Double) -> Double {
        min(plateMax, max(plateMin, value))
    }
}

/// Edge inset as a fraction of canvas short edge (pairs with ~95% product fill → ~2.5% gutter).
enum BrandMarkEdgePaddingRange {
    static let minimum = 0.01
    static let maximum = 0.06
    /// Sits in the free gutter around a 95% fill product.
    static let `default` = 0.025

    static func clamp(_ value: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}

/// Logo size as a fraction of canvas short edge (UI shows as percent).
enum BrandMarkLogoScaleRange {
    static let minimum = 0.08
    static let maximum = 0.28
    static let `default` = 0.12

    static func clamp(_ value: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}

/// Paired text + caption-plate colors for one-tap Brand Kit styling.
struct BrandMarkColorPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let fontColorHex: String
    let plateColorHex: String
    /// Suggested caption plate opacity when the preset is applied.
    let plateOpacity: Double

    static let all: [BrandMarkColorPreset] = [
        BrandMarkColorPreset(
            id: "classic-light",
            name: "Classic Light",
            fontColorHex: "#FFFFFF",
            plateColorHex: "#1A1A1A",
            plateOpacity: BrandMarkOpacityRange.plateDefault
        ),
        BrandMarkColorPreset(
            id: "classic-dark",
            name: "Classic Dark",
            fontColorHex: "#141414",
            plateColorHex: "#F5F5F5",
            plateOpacity: BrandMarkOpacityRange.plateDefault
        ),
        BrandMarkColorPreset(
            id: "forest",
            name: "Forest",
            fontColorHex: "#1B4332",
            plateColorHex: "#D8F3DC",
            plateOpacity: 0.32
        ),
        BrandMarkColorPreset(
            id: "ocean",
            name: "Ocean",
            fontColorHex: "#0A2540",
            plateColorHex: "#D6E8FF",
            plateOpacity: 0.32
        ),
        BrandMarkColorPreset(
            id: "teal",
            name: "Teal",
            fontColorHex: "#0D4F4F",
            plateColorHex: "#D4F5F0",
            plateOpacity: 0.30
        ),
        BrandMarkColorPreset(
            id: "warm",
            name: "Warm",
            fontColorHex: "#3D2914",
            plateColorHex: "#FFF3D6",
            plateOpacity: 0.32
        ),
        BrandMarkColorPreset(
            id: "berry",
            name: "Berry",
            fontColorHex: "#4A1528",
            plateColorHex: "#FCE4EC",
            plateOpacity: 0.32
        ),
        BrandMarkColorPreset(
            id: "slate",
            name: "Slate",
            fontColorHex: "#E8EEF4",
            plateColorHex: "#243447",
            plateOpacity: 0.34
        )
    ]

    func matches(fontHex: String, plateHex: String) -> Bool {
        fontHex.caseInsensitiveCompare(fontColorHex) == .orderedSame
            && plateHex.caseInsensitiveCompare(plateColorHex) == .orderedSame
    }
}

/// Optional filename / UPC label stamped like Brand Mark text (no logo).
struct ImageNameStampConfiguration: Equatable {
    var isEnabled: Bool
    var position: BrandMarkPosition
    var captionPlateOpacity: Double
    var fontSizePx: Int
    var fontColorHex: String
    var captionPlateColorHex: String
    var textCaptionPlateEnabled: Bool
    var fontStyle: BrandMarkFontStyle
    var fontPostScriptName: String?
    /// When false, draw a single truncated line (default).
    var lineWrapEnabled: Bool
    /// Edge inset vs short edge (default 2.5% for 95% fill gutter).
    var edgePaddingFraction: Double

    static let `default` = ImageNameStampConfiguration(
        isEnabled: false,
        position: .bottomCenter,
        captionPlateOpacity: BrandMarkOpacityRange.plateDefault,
        fontSizePx: 12,
        fontColorHex: "#FFFFFF",
        captionPlateColorHex: "#1A1A1A",
        textCaptionPlateEnabled: true,
        fontStyle: .semibold,
        fontPostScriptName: nil,
        lineWrapEnabled: false,
        edgePaddingFraction: BrandMarkEdgePaddingRange.default
    )

    var fontColor: UIColor {
        UIColor(hexString: fontColorHex) ?? .white
    }

    var captionPlateColor: UIColor {
        UIColor(hexString: captionPlateColorHex)
            ?? BrandMarkPlateColor.contrasting(for: fontColor)
    }

    var fontDisplayName: String {
        BrandMarkFontCatalog.displayName(postScriptName: fontPostScriptName)
    }

    var matchedColorPreset: BrandMarkColorPreset? {
        BrandMarkColorPreset.all.first {
            $0.matches(fontHex: fontColorHex, plateHex: captionPlateColorHex)
        }
    }

    func shouldRender(label: String?) -> Bool {
        guard isEnabled else { return false }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }
}

enum BrandMarkPositionConflict {
    /// Prefer opposite corners so Brand Mark + Image Name stay readable.
    private static let fallbackOrder: [BrandMarkPosition] = [
        .bottomLeft, .bottomRight, .topLeft, .topRight,
        .bottomCenter, .topCenter, .middleLeft, .middleRight, .middleCenter
    ]

    static func resolved(_ proposed: BrandMarkPosition, blockedBy other: BrandMarkPosition?) -> BrandMarkPosition {
        guard let other, proposed == other else { return proposed }
        return fallbackOrder.first { $0 != other } ?? .bottomLeft
    }

    static func isBlocked(_ position: BrandMarkPosition, by other: BrandMarkPosition?) -> Bool {
        guard let other else { return false }
        return position == other
    }
}

struct BrandMarkConfiguration: Equatable {
    var isEnabled: Bool
    var text: String
    var position: BrandMarkPosition
    /// Logo watermark opacity (0.15…0.70). Text stays solid when the caption plate is on.
    var logoOpacity: Double
    /// Caption plate fill opacity (0.12…0.55) — keeps product visible under the chip.
    var captionPlateOpacity: Double
    var showText: Bool
    var showLogo: Bool
    /// Logo size vs canvas short edge (≈0.08 small → 0.28 large).
    var logoScale: Double
    /// Text size in points (same unit as Markup). Scaled to the export canvas like Markup bake.
    var fontSizePx: Int
    /// Hex fill for watermark text (drawn near-opaque when caption plate is on).
    var fontColorHex: String
    /// Caption plate fill color (paired with font color / presets).
    var captionPlateColorHex: String
    /// Semi-transparent caption plate behind text for contrast on any backdrop (default on).
    var textCaptionPlateEnabled: Bool
    var fontStyle: BrandMarkFontStyle
    /// UIFont postscript name from the system font picker (nil = SF System).
    var fontPostScriptName: String?
    /// On-disk logo filename inside Application Support (nil = no logo).
    var logoFileName: String?
    /// When false, Brand Mark text is a single truncated line (default).
    var textLineWrapEnabled: Bool
    /// Edge inset vs short edge for the Brand Mark stack (default 2.5%).
    var edgePaddingFraction: Double
    /// Optional image-name / UPC caption (separate position from Brand Mark).
    var imageName: ImageNameStampConfiguration

    static let `default` = BrandMarkConfiguration(
        isEnabled: false,
        text: "",
        position: .middleCenter,
        logoOpacity: BrandMarkOpacityRange.logoDefault,
        captionPlateOpacity: BrandMarkOpacityRange.plateDefault,
        showText: true,
        showLogo: true,
        logoScale: BrandMarkLogoScaleRange.default,
        fontSizePx: 18,
        fontColorHex: "#FFFFFF",
        captionPlateColorHex: "#1A1A1A",
        textCaptionPlateEnabled: true,
        fontStyle: .semibold,
        fontPostScriptName: nil,
        logoFileName: nil,
        textLineWrapEnabled: false,
        edgePaddingFraction: BrandMarkEdgePaddingRange.default,
        imageName: .default
    )

    /// Reference view short-edge (pt) — matches Markup’s on-screen editor scale when baking to export.
    static let designShortEdge: CGFloat = 390

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var fontColor: UIColor {
        UIColor(hexString: fontColorHex) ?? .white
    }

    var captionPlateColor: UIColor {
        UIColor(hexString: captionPlateColorHex)
            ?? BrandMarkPlateColor.contrasting(for: fontColor)
    }

    var fontDisplayName: String {
        BrandMarkFontCatalog.displayName(postScriptName: fontPostScriptName)
    }

    var matchedColorPreset: BrandMarkColorPreset? {
        BrandMarkColorPreset.all.first {
            $0.matches(fontHex: fontColorHex, plateHex: captionPlateColorHex)
        }
    }

    var shouldRender: Bool {
        guard isEnabled else { return false }
        let hasText = showText && !trimmedText.isEmpty
        let hasLogo = showLogo && BrandMarkLogoStore.logoExists(fileName: logoFileName)
        return hasText || hasLogo
    }
}

enum BrandMarkPlateColor {
    /// Dark plate behind light text; light plate behind dark text.
    static func contrasting(for fill: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard fill.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return UIColor(white: 0.08, alpha: 1)
        }
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.55 ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.96, alpha: 1)
    }

    static func contrastingHex(for fillHex: String) -> String {
        let fill = UIColor(hexString: fillHex) ?? .white
        return contrasting(for: fill).hexString
    }
}

/// Persists the optional company logo beside Brand Mark settings.
enum BrandMarkLogoStore {
    private static let folderName = "ProductStudioBrandMark"
    static let defaultLogoFileName = "brand_logo.png"

    static func folderURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func fileURL(for fileName: String) -> URL {
        folderURL().appendingPathComponent(fileName)
    }

    static func logoExists(fileName: String?) -> Bool {
        guard let fileName, !fileName.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: fileURL(for: fileName).path)
    }

    static func loadLogo(fileName: String?) -> UIImage? {
        guard let fileName, logoExists(fileName: fileName) else { return nil }
        let url = fileURL(for: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    @discardableResult
    static func saveLogo(_ image: UIImage, fileName: String = defaultLogoFileName) -> String? {
        let longest = max(image.size.width, image.size.height)
        let scaled: UIImage
        if longest > 1024 {
            let scale = 1024 / longest
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = false
            scaled = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            scaled = image
        }
        guard let data = scaled.pngData() else { return nil }
        let url = fileURL(for: fileName)
        do {
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    static func deleteLogo(fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: fileURL(for: fileName))
    }
}

/// Persisted Brand Mark settings (also mirrored on `CaptureSessionStore` for SwiftUI).
enum BrandMarkSettings {
    private static let enabledKey = "brandMarkEnabled"
    private static let textKey = "brandMarkText"
    private static let positionKey = "brandMarkPosition"
    /// Legacy shared opacity — migrated into `logoOpacity` / `captionPlateOpacity`.
    private static let legacyOpacityKey = "brandMarkOpacity"
    private static let logoOpacityKey = "brandMarkLogoOpacity"
    private static let captionPlateOpacityKey = "brandMarkCaptionPlateOpacity"
    private static let showTextKey = "brandMarkShowText"
    private static let showLogoKey = "brandMarkShowLogo"
    /// Legacy shared scale — migrated into `logoScale` / `fontSize` when new keys are absent.
    private static let legacyMarkScaleKey = "brandMarkScale"
    private static let logoScaleKey = "brandMarkLogoScale"
    private static let fontSizeKey = "brandMarkFontSize"
    private static let fontSizePxKey = "brandMarkFontSizePx"
    private static let fontColorHexKey = "brandMarkFontColorHex"
    private static let captionPlateColorHexKey = "brandMarkCaptionPlateColorHex"
    private static let textCaptionPlateEnabledKey = "brandMarkTextCaptionPlateEnabled"
    /// Legacy outline toggle — migrated into caption plate when the new key is absent.
    private static let legacyTextOutlineEnabledKey = "brandMarkTextOutlineEnabled"
    private static let fontStyleKey = "brandMarkFontStyle"
    private static let fontFamilyKey = "brandMarkFontFamily"
    private static let fontPostScriptNameKey = "brandMarkFontPostScriptName"
    private static let logoFileNameKey = "brandMarkLogoFileName"
    private static let textLineWrapEnabledKey = "brandMarkTextLineWrapEnabled"
    private static let edgePaddingFractionKey = "brandMarkEdgePaddingFraction"
    private static let imageNameEnabledKey = "brandMarkImageNameEnabled"
    private static let imageNamePositionKey = "brandMarkImageNamePosition"
    private static let imageNameCaptionPlateOpacityKey = "brandMarkImageNameCaptionPlateOpacity"
    private static let imageNameFontSizePxKey = "brandMarkImageNameFontSizePx"
    private static let imageNameFontColorHexKey = "brandMarkImageNameFontColorHex"
    private static let imageNameCaptionPlateColorHexKey = "brandMarkImageNameCaptionPlateColorHex"
    private static let imageNameTextCaptionPlateEnabledKey = "brandMarkImageNameTextCaptionPlateEnabled"
    private static let imageNameFontStyleKey = "brandMarkImageNameFontStyle"
    private static let imageNameFontPostScriptNameKey = "brandMarkImageNameFontPostScriptName"
    private static let imageNameLineWrapEnabledKey = "brandMarkImageNameLineWrapEnabled"
    private static let imageNameEdgePaddingFractionKey = "brandMarkImageNameEdgePaddingFraction"

    private static let lock = NSLock()
    private static var cached: BrandMarkConfiguration?

    static var configuration: BrandMarkConfiguration {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let cached { return cached }
            let loaded = loadFromDefaults()
            cached = loaded
            return loaded
        }
        set {
            lock.lock()
            cached = newValue
            lock.unlock()
            UserDefaults.standard.set(newValue.isEnabled, forKey: enabledKey)
            UserDefaults.standard.set(newValue.text, forKey: textKey)
            UserDefaults.standard.set(newValue.position.rawValue, forKey: positionKey)
            UserDefaults.standard.set(newValue.logoOpacity, forKey: logoOpacityKey)
            UserDefaults.standard.set(newValue.captionPlateOpacity, forKey: captionPlateOpacityKey)
            UserDefaults.standard.set(newValue.showText, forKey: showTextKey)
            UserDefaults.standard.set(newValue.showLogo, forKey: showLogoKey)
            UserDefaults.standard.set(newValue.logoScale, forKey: logoScaleKey)
            UserDefaults.standard.set(newValue.fontSizePx, forKey: fontSizePxKey)
            UserDefaults.standard.set(newValue.fontColorHex, forKey: fontColorHexKey)
            UserDefaults.standard.set(newValue.captionPlateColorHex, forKey: captionPlateColorHexKey)
            UserDefaults.standard.set(newValue.textCaptionPlateEnabled, forKey: textCaptionPlateEnabledKey)
            UserDefaults.standard.set(newValue.fontStyle.rawValue, forKey: fontStyleKey)
            UserDefaults.standard.set(newValue.fontPostScriptName, forKey: fontPostScriptNameKey)
            UserDefaults.standard.set(newValue.logoFileName, forKey: logoFileNameKey)
            UserDefaults.standard.set(newValue.textLineWrapEnabled, forKey: textLineWrapEnabledKey)
            UserDefaults.standard.set(newValue.edgePaddingFraction, forKey: edgePaddingFractionKey)
            let imageName = newValue.imageName
            UserDefaults.standard.set(imageName.isEnabled, forKey: imageNameEnabledKey)
            UserDefaults.standard.set(imageName.position.rawValue, forKey: imageNamePositionKey)
            UserDefaults.standard.set(imageName.captionPlateOpacity, forKey: imageNameCaptionPlateOpacityKey)
            UserDefaults.standard.set(imageName.fontSizePx, forKey: imageNameFontSizePxKey)
            UserDefaults.standard.set(imageName.fontColorHex, forKey: imageNameFontColorHexKey)
            UserDefaults.standard.set(imageName.captionPlateColorHex, forKey: imageNameCaptionPlateColorHexKey)
            UserDefaults.standard.set(imageName.textCaptionPlateEnabled, forKey: imageNameTextCaptionPlateEnabledKey)
            UserDefaults.standard.set(imageName.fontStyle.rawValue, forKey: imageNameFontStyleKey)
            UserDefaults.standard.set(imageName.fontPostScriptName, forKey: imageNameFontPostScriptNameKey)
            UserDefaults.standard.set(imageName.lineWrapEnabled, forKey: imageNameLineWrapEnabledKey)
            UserDefaults.standard.set(imageName.edgePaddingFraction, forKey: imageNameEdgePaddingFractionKey)
        }
    }

    static func refreshFromDefaults() {
        lock.lock()
        cached = loadFromDefaults()
        lock.unlock()
    }

    private static func loadFromDefaults() -> BrandMarkConfiguration {
        let enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false
        let text = UserDefaults.standard.string(forKey: textKey) ?? ""
        let position = BrandMarkPosition(rawValue: UserDefaults.standard.string(forKey: positionKey) ?? "")
            ?? BrandMarkConfiguration.default.position
        let legacyOpacity = UserDefaults.standard.object(forKey: legacyOpacityKey) as? Double
        let logoOpacity: Double = {
            if let stored = UserDefaults.standard.object(forKey: logoOpacityKey) as? Double {
                return BrandMarkOpacityRange.clampLogo(stored)
            }
            if let legacy = legacyOpacity {
                return BrandMarkOpacityRange.clampLogo(legacy)
            }
            return BrandMarkOpacityRange.logoDefault
        }()
        let captionPlateOpacity: Double = {
            if let stored = UserDefaults.standard.object(forKey: captionPlateOpacityKey) as? Double {
                return BrandMarkOpacityRange.clampPlate(stored)
            }
            return BrandMarkOpacityRange.plateDefault
        }()
        let showText = UserDefaults.standard.object(forKey: showTextKey) as? Bool ?? true
        let showLogo = UserDefaults.standard.object(forKey: showLogoKey) as? Bool ?? true

        let legacyScale = UserDefaults.standard.object(forKey: legacyMarkScaleKey) as? Double
        let clampedLegacy = legacyScale.map { BrandMarkLogoScaleRange.clamp($0) }
        let rawLogoScale = UserDefaults.standard.object(forKey: logoScaleKey) as? Double
            ?? clampedLegacy
            ?? BrandMarkLogoScaleRange.default
        let logoScale = BrandMarkLogoScaleRange.clamp(rawLogoScale)

        let fontSizePx: Int = {
            if let px = UserDefaults.standard.object(forKey: fontSizePxKey) as? Int {
                return BrandMarkFontSizePreset.clamped(px)
            }
            if let pxDouble = UserDefaults.standard.object(forKey: fontSizePxKey) as? Double {
                return BrandMarkFontSizePreset.clamped(Int(pxDouble.rounded()))
            }
            // Legacy relative fraction (0.02…0.08) stored under brandMarkFontSize.
            if let fraction = UserDefaults.standard.object(forKey: fontSizeKey) as? Double, fraction > 0, fraction <= 1 {
                return BrandMarkFontSizePreset.clamped(Int((1200 * fraction).rounded()))
            }
            if let legacy = clampedLegacy {
                return BrandMarkFontSizePreset.clamped(Int((1200 * legacy * 0.22).rounded()))
            }
            return BrandMarkConfiguration.default.fontSizePx
        }()

        let fontColorHex = UserDefaults.standard.string(forKey: fontColorHexKey) ?? "#FFFFFF"
        let captionPlateColorHex = UserDefaults.standard.string(forKey: captionPlateColorHexKey)
            ?? BrandMarkPlateColor.contrastingHex(for: fontColorHex)
        let textCaptionPlateEnabled: Bool = {
            if let stored = UserDefaults.standard.object(forKey: textCaptionPlateEnabledKey) as? Bool {
                return stored
            }
            // Prefer caption plate; only honor an explicit legacy "outline off".
            if let legacyOutline = UserDefaults.standard.object(forKey: legacyTextOutlineEnabledKey) as? Bool {
                return legacyOutline
            }
            return true
        }()
        let fontStyle = BrandMarkFontStyle(rawValue: UserDefaults.standard.string(forKey: fontStyleKey) ?? "") ?? .semibold
        let fontPostScriptName: String? = {
            if let name = UserDefaults.standard.string(forKey: fontPostScriptNameKey), !name.isEmpty {
                return name
            }
            return BrandMarkFontCatalog.postScriptName(
                fromLegacyFamilyRaw: UserDefaults.standard.string(forKey: fontFamilyKey)
            )
        }()
        let logoFileName = UserDefaults.standard.string(forKey: logoFileNameKey)
        let textLineWrapEnabled = UserDefaults.standard.object(forKey: textLineWrapEnabledKey) as? Bool ?? false
        let edgePaddingFraction: Double = {
            if let stored = UserDefaults.standard.object(forKey: edgePaddingFractionKey) as? Double {
                return BrandMarkEdgePaddingRange.clamp(stored)
            }
            return BrandMarkEdgePaddingRange.default
        }()

        let imageNameFontColorHex = UserDefaults.standard.string(forKey: imageNameFontColorHexKey) ?? "#FFFFFF"
        let imageName = ImageNameStampConfiguration(
            isEnabled: UserDefaults.standard.object(forKey: imageNameEnabledKey) as? Bool ?? false,
            position: BrandMarkPosition(rawValue: UserDefaults.standard.string(forKey: imageNamePositionKey) ?? "")
                ?? ImageNameStampConfiguration.default.position,
            captionPlateOpacity: {
                if let stored = UserDefaults.standard.object(forKey: imageNameCaptionPlateOpacityKey) as? Double {
                    return BrandMarkOpacityRange.clampPlate(stored)
                }
                return BrandMarkOpacityRange.plateDefault
            }(),
            fontSizePx: {
                if let px = UserDefaults.standard.object(forKey: imageNameFontSizePxKey) as? Int {
                    return BrandMarkFontSizePreset.clamped(px)
                }
                return ImageNameStampConfiguration.default.fontSizePx
            }(),
            fontColorHex: imageNameFontColorHex,
            captionPlateColorHex: UserDefaults.standard.string(forKey: imageNameCaptionPlateColorHexKey)
                ?? BrandMarkPlateColor.contrastingHex(for: imageNameFontColorHex),
            textCaptionPlateEnabled: UserDefaults.standard.object(forKey: imageNameTextCaptionPlateEnabledKey) as? Bool ?? true,
            fontStyle: BrandMarkFontStyle(rawValue: UserDefaults.standard.string(forKey: imageNameFontStyleKey) ?? "") ?? .semibold,
            fontPostScriptName: {
                if let name = UserDefaults.standard.string(forKey: imageNameFontPostScriptNameKey), !name.isEmpty {
                    return name
                }
                return nil
            }(),
            lineWrapEnabled: UserDefaults.standard.object(forKey: imageNameLineWrapEnabledKey) as? Bool ?? false,
            edgePaddingFraction: {
                if let stored = UserDefaults.standard.object(forKey: imageNameEdgePaddingFractionKey) as? Double {
                    return BrandMarkEdgePaddingRange.clamp(stored)
                }
                return BrandMarkEdgePaddingRange.default
            }()
        )

        // Keep Brand Mark + Image Name on different slots after load.
        let safeImageNamePosition = BrandMarkPositionConflict.resolved(
            imageName.position,
            blockedBy: (enabled && (showText || showLogo)) ? position : nil
        )
        var resolvedImageName = imageName
        resolvedImageName.position = safeImageNamePosition

        return BrandMarkConfiguration(
            isEnabled: enabled,
            text: text,
            position: position,
            logoOpacity: logoOpacity,
            captionPlateOpacity: captionPlateOpacity,
            showText: showText,
            showLogo: showLogo,
            logoScale: logoScale,
            fontSizePx: fontSizePx,
            fontColorHex: fontColorHex,
            captionPlateColorHex: captionPlateColorHex,
            textCaptionPlateEnabled: textCaptionPlateEnabled,
            fontStyle: fontStyle,
            fontPostScriptName: fontPostScriptName,
            logoFileName: logoFileName,
            textLineWrapEnabled: textLineWrapEnabled,
            edgePaddingFraction: edgePaddingFraction,
            imageName: resolvedImageName
        )
    }
}

/// Draws Brand Mark text and/or logo onto a composited catalog image.
enum BrandMarkRenderer {
    static func applyIfNeeded(
        _ image: UIImage,
        configuration: BrandMarkConfiguration = BrandMarkSettings.configuration,
        imageNameText: String? = nil
    ) -> UIImage {
        let drawBrand = configuration.shouldRender
        let drawName = configuration.imageName.shouldRender(label: imageNameText)
        guard drawBrand || drawName else { return image }
        return apply(image, configuration: configuration, imageNameText: imageNameText)
    }

    /// Brand Kit editor preview — stamps on the sample photo (downsampled) so sizing matches export.
    static func previewImage(
        configuration: BrandMarkConfiguration,
        canvasSize: CGSize = CGSize(width: 720, height: 720),
        sampleProduct: UIImage? = nil,
        imageNameText: String? = "Image-Name"
    ) -> UIImage {
        if let sampleProduct {
            let previewBase = ImageProcessor.downsampleIfNeededForImportPipeline(
                sampleProduct,
                maxLongEdgePixels: 960
            )
            return applyIfNeeded(previewBase, configuration: configuration, imageNameText: imageNameText)
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let base = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let colors = [UIColor(white: 0.93, alpha: 1).cgColor, UIColor(white: 0.78, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: []
                )
            }
            let product = CGRect(
                x: canvasSize.width * 0.35,
                y: canvasSize.height * 0.28,
                width: canvasSize.width * 0.30,
                height: canvasSize.height * 0.42
            )
            UIColor(white: 0.55, alpha: 0.35).setFill()
            UIBezierPath(roundedRect: product, cornerRadius: 14).fill()
        }
        return applyIfNeeded(base, configuration: configuration, imageNameText: imageNameText)
    }

    static func apply(
        _ image: UIImage,
        configuration: BrandMarkConfiguration,
        imageNameText: String? = nil
    ) -> UIImage {
        let size = image.size
        guard size.width > 1, size.height > 1 else { return image }

        let logo = configuration.shouldRender && configuration.showLogo
            ? BrandMarkLogoStore.loadLogo(fileName: configuration.logoFileName)
            : nil
        let text = configuration.shouldRender && configuration.showText ? configuration.trimmedText : ""
        let nameLabel = configuration.imageName.shouldRender(label: imageNameText)
            ? (imageNameText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : ""
        guard logo != nil || !text.isEmpty || !nameLabel.isEmpty else { return image }

        // Avoid stacking both stamps on the same slot at bake time.
        var nameConfig = configuration.imageName
        if configuration.shouldRender, !nameLabel.isEmpty {
            nameConfig.position = BrandMarkPositionConflict.resolved(
                nameConfig.position,
                blockedBy: configuration.position
            )
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))

            let shortEdge = min(size.width, size.height)
            let designScale = shortEdge / BrandMarkConfiguration.designShortEdge
            let brandMargin = shortEdge * CGFloat(BrandMarkEdgePaddingRange.clamp(configuration.edgePaddingFraction))
            let nameMargin = shortEdge * CGFloat(BrandMarkEdgePaddingRange.clamp(nameConfig.edgePaddingFraction))

            if logo != nil || !text.isEmpty {
                drawBrandStack(
                    canvas: size,
                    shortEdge: shortEdge,
                    designScale: designScale,
                    margin: brandMargin,
                    configuration: configuration,
                    logo: logo,
                    text: text
                )
            }

            if !nameLabel.isEmpty {
                drawTextChip(
                    text: nameLabel,
                    canvas: size,
                    shortEdge: shortEdge,
                    designScale: designScale,
                    margin: nameMargin,
                    position: nameConfig.position,
                    fontSizePx: nameConfig.fontSizePx,
                    fontStyle: nameConfig.fontStyle,
                    fontPostScriptName: nameConfig.fontPostScriptName,
                    fontColor: nameConfig.fontColor,
                    usePlate: nameConfig.textCaptionPlateEnabled,
                    plateColor: nameConfig.captionPlateColor,
                    plateOpacity: BrandMarkOpacityRange.clampPlate(nameConfig.captionPlateOpacity),
                    softTextOpacity: 0.85,
                    lineWrapEnabled: nameConfig.lineWrapEnabled
                )
            }
        }
    }

    private static func drawBrandStack(
        canvas: CGSize,
        shortEdge: CGFloat,
        designScale: CGFloat,
        margin: CGFloat,
        configuration: BrandMarkConfiguration,
        logo: UIImage?,
        text: String
    ) {
        let logoScale = CGFloat(BrandMarkLogoScaleRange.clamp(configuration.logoScale))
        let logoAlpha = CGFloat(BrandMarkOpacityRange.clampLogo(configuration.logoOpacity))
        let spacing = shortEdge * 0.012
        let usePlate = configuration.textCaptionPlateEnabled

        var logoDrawSize = CGSize.zero
        if let logo {
            let maxLogo = shortEdge * logoScale
            let aspect = logo.size.width / max(logo.size.height, 1)
            if aspect >= 1 {
                logoDrawSize = CGSize(width: maxLogo, height: maxLogo / aspect)
            } else {
                logoDrawSize = CGSize(width: maxLogo * aspect, height: maxLogo)
            }
        }

        var textSize = CGSize.zero
        var textAttrs: [NSAttributedString.Key: Any] = [:]
        var platePadding = CGSize.zero
        var pointSize: CGFloat = 0
        if !text.isEmpty {
            pointSize = max(8, CGFloat(BrandMarkFontSizePreset.clamped(configuration.fontSizePx)) * designScale)
            let font = BrandMarkFontCatalog.uiFont(
                postScriptName: configuration.fontPostScriptName,
                size: pointSize,
                style: configuration.fontStyle
            )
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            if !configuration.textLineWrapEnabled {
                paragraph.lineBreakMode = .byTruncatingTail
            }
            let textAlpha: CGFloat = usePlate ? 0.96 : logoAlpha
            textAttrs = [
                .font: font,
                .foregroundColor: configuration.fontColor.withAlphaComponent(textAlpha),
                .paragraphStyle: paragraph
            ]
            let maxWidth = canvas.width * 0.7
            textSize = measureText(
                text,
                attributes: textAttrs,
                maxWidth: maxWidth,
                lineWrapEnabled: configuration.textLineWrapEnabled
            )
            platePadding = CGSize(
                width: max(6, pointSize * 0.34),
                height: max(4, pointSize * 0.20)
            )
        }

        let textBlockWidth = textSize.width + (usePlate && !text.isEmpty ? platePadding.width * 2 : 0)
        let textBlockHeight = textSize.height + (usePlate && !text.isEmpty ? platePadding.height * 2 : 0)
        let stackWidth = max(logoDrawSize.width, textBlockWidth)
        var stackHeight = logoDrawSize.height
        if logoDrawSize.height > 0, textBlockHeight > 0 { stackHeight += spacing }
        stackHeight += textBlockHeight

        let stackOrigin = originForStack(
            stackSize: CGSize(width: stackWidth, height: stackHeight),
            canvas: canvas,
            position: configuration.position,
            margin: margin
        )

        var cursorY = stackOrigin.y
        if let logo, logoDrawSize.width > 0 {
            let logoX = stackOrigin.x + (stackWidth - logoDrawSize.width) / 2
            let logoRect = CGRect(x: logoX, y: cursorY, width: logoDrawSize.width, height: logoDrawSize.height)
            logo.draw(in: logoRect, blendMode: .normal, alpha: logoAlpha)
            cursorY = logoRect.maxY + (textBlockHeight > 0 ? spacing : 0)
        }

        if !text.isEmpty {
            let blockX = stackOrigin.x + (stackWidth - textBlockWidth) / 2
            let blockRect = CGRect(x: blockX, y: cursorY, width: textBlockWidth, height: textBlockHeight)
            paintTextBlock(
                text: text,
                blockRect: blockRect,
                textSize: textSize,
                textAttrs: textAttrs,
                usePlate: usePlate,
                plateColor: configuration.captionPlateColor,
                plateOpacity: BrandMarkOpacityRange.clampPlate(configuration.captionPlateOpacity),
                platePadding: platePadding,
                softTextOpacity: logoAlpha,
                cornerHint: max(6, CGFloat(configuration.fontSizePx) * designScale * 0.35)
            )
        }
    }

    private static func drawTextChip(
        text: String,
        canvas: CGSize,
        shortEdge: CGFloat,
        designScale: CGFloat,
        margin: CGFloat,
        position: BrandMarkPosition,
        fontSizePx: Int,
        fontStyle: BrandMarkFontStyle,
        fontPostScriptName: String?,
        fontColor: UIColor,
        usePlate: Bool,
        plateColor: UIColor,
        plateOpacity: Double,
        softTextOpacity: CGFloat,
        lineWrapEnabled: Bool
    ) {
        let pointSize = max(8, CGFloat(BrandMarkFontSizePreset.clamped(fontSizePx)) * designScale)
        let font = BrandMarkFontCatalog.uiFont(
            postScriptName: fontPostScriptName,
            size: pointSize,
            style: fontStyle
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        if !lineWrapEnabled {
            paragraph.lineBreakMode = .byTruncatingTail
        }
        let textAlpha: CGFloat = usePlate ? 0.96 : softTextOpacity
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fontColor.withAlphaComponent(textAlpha),
            .paragraphStyle: paragraph
        ]
        let maxWidth = canvas.width * 0.7
        let textSize = measureText(
            text,
            attributes: textAttrs,
            maxWidth: maxWidth,
            lineWrapEnabled: lineWrapEnabled
        )
        let platePadding = CGSize(
            width: max(6, pointSize * 0.34),
            height: max(4, pointSize * 0.20)
        )
        let blockWidth = textSize.width + (usePlate ? platePadding.width * 2 : 0)
        let blockHeight = textSize.height + (usePlate ? platePadding.height * 2 : 0)
        let origin = originForStack(
            stackSize: CGSize(width: blockWidth, height: blockHeight),
            canvas: canvas,
            position: position,
            margin: margin
        )
        let blockRect = CGRect(origin: origin, size: CGSize(width: blockWidth, height: blockHeight))
        paintTextBlock(
            text: text,
            blockRect: blockRect,
            textSize: textSize,
            textAttrs: textAttrs,
            usePlate: usePlate,
            plateColor: plateColor,
            plateOpacity: plateOpacity,
            platePadding: platePadding,
            softTextOpacity: softTextOpacity,
            cornerHint: max(6, CGFloat(fontSizePx) * designScale * 0.35)
        )
    }

    private static func measureText(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        maxWidth: CGFloat,
        lineWrapEnabled: Bool
    ) -> CGSize {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        if lineWrapEnabled {
            return attributed.boundingRect(
                with: CGSize(width: maxWidth, height: maxWidth * 0.5),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).integral.size
        }
        // Single line — measure natural width, then clamp to max so truncation applies when drawing.
        let natural = attributed.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral.size
        return CGSize(width: min(natural.width, maxWidth), height: natural.height)
    }

    private static func paintTextBlock(
        text: String,
        blockRect: CGRect,
        textSize: CGSize,
        textAttrs: [NSAttributedString.Key: Any],
        usePlate: Bool,
        plateColor: UIColor,
        plateOpacity: Double,
        platePadding: CGSize,
        softTextOpacity: CGFloat,
        cornerHint: CGFloat
    ) {
        let plateAlpha = CGFloat(plateOpacity)
        if usePlate {
            let corner = min(blockRect.height * 0.45, cornerHint)
            let platePath = UIBezierPath(roundedRect: blockRect, cornerRadius: corner)
            let shadowPath = UIBezierPath(roundedRect: blockRect.offsetBy(dx: 0, dy: 1.2), cornerRadius: corner)
            UIColor.black.withAlphaComponent(0.10 + plateAlpha * 0.18).setFill()
            shadowPath.fill()
            plateColor.withAlphaComponent(plateAlpha).setFill()
            platePath.fill()
        } else {
            let shadowDark: [NSAttributedString.Key: Any] = [
                .font: textAttrs[.font] as Any,
                .foregroundColor: UIColor.black.withAlphaComponent(softTextOpacity * 0.45),
                .paragraphStyle: textAttrs[.paragraphStyle] as Any
            ]
            let shadowLight: [NSAttributedString.Key: Any] = [
                .font: textAttrs[.font] as Any,
                .foregroundColor: UIColor.white.withAlphaComponent(softTextOpacity * 0.35),
                .paragraphStyle: textAttrs[.paragraphStyle] as Any
            ]
            let textRect = CGRect(
                x: blockRect.minX,
                y: blockRect.minY,
                width: textSize.width,
                height: textSize.height
            )
            NSAttributedString(string: text, attributes: shadowLight)
                .draw(in: textRect.offsetBy(dx: -0.8, dy: -0.8))
            NSAttributedString(string: text, attributes: shadowDark)
                .draw(in: textRect.offsetBy(dx: 1, dy: 1))
        }

        let textRect = CGRect(
            x: blockRect.minX + (usePlate ? platePadding.width : 0),
            y: blockRect.minY + (usePlate ? platePadding.height : 0),
            width: textSize.width,
            height: textSize.height
        )
        NSAttributedString(string: text, attributes: textAttrs).draw(in: textRect)
    }

    private static func originForStack(
        stackSize: CGSize,
        canvas: CGSize,
        position: BrandMarkPosition,
        margin: CGFloat
    ) -> CGPoint {
        let maxX = max(margin, canvas.width - stackSize.width - margin)
        let maxY = max(margin, canvas.height - stackSize.height - margin)
        let midX = (canvas.width - stackSize.width) / 2
        let midY = (canvas.height - stackSize.height) / 2

        switch position {
        case .topLeft: return CGPoint(x: margin, y: margin)
        case .topCenter: return CGPoint(x: midX, y: margin)
        case .topRight: return CGPoint(x: maxX, y: margin)
        case .middleLeft: return CGPoint(x: margin, y: midY)
        case .middleCenter: return CGPoint(x: midX, y: midY)
        case .middleRight: return CGPoint(x: maxX, y: midY)
        case .bottomLeft: return CGPoint(x: margin, y: maxY)
        case .bottomCenter: return CGPoint(x: midX, y: maxY)
        case .bottomRight: return CGPoint(x: maxX, y: maxY)
        }
    }
}
