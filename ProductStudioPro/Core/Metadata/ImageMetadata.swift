import Foundation

/// Image orientation derived from pixel dimensions.
enum ImageOrientation: String, Codable, CaseIterable, Sendable {
    case portrait
    case landscape
    case square
    case unknown

    static func from(width: Int, height: Int) -> ImageOrientation {
        guard width > 0, height > 0 else { return .unknown }
        if width == height { return .square }
        return width > height ? .landscape : .portrait
    }
}

/// On-disk or export image format.
enum ImageAssetFormat: String, Codable, CaseIterable, Sendable {
    case jpeg
    case png
    case heic
    case unknown

    init(exportFormat: ExportImageFormat) {
        switch exportFormat {
        case .jpg: self = .jpeg
        case .png: self = .png
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .unknown: return "jpg"
        }
    }
}

/// Per-image metadata — processing state, export attributes, and duplicate-detection hooks.
struct ImageMetadata: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var filename: String
    var width: Int
    var height: Int
    var fileSize: Int
    var orientation: ImageOrientation
    var format: ImageAssetFormat
    var backgroundType: String
    var canvasProfile: String
    var enhancementApplied: String
    var upscaled: Bool
    var cropped: Bool
    var edited: Bool
    var exported: Bool
    var checksum: String?

    // Processing snapshot fields — populated during sync for CSV and ERP export.
    var sequence: Int
    var angle: String
    var capturedAt: Date
    var backgroundRemoved: Bool
    var enhancementMode: String
    var studioAIStrength: String
    var canvasWidth: Int
    var canvasHeight: Int
    var fillRatio: Double
    var backgroundStyle: String
    var shadowApplied: Bool

    init(
        id: UUID = UUID(),
        filename: String = "",
        width: Int = 0,
        height: Int = 0,
        fileSize: Int = 0,
        orientation: ImageOrientation = .unknown,
        format: ImageAssetFormat = .jpeg,
        backgroundType: String = "",
        canvasProfile: String = "",
        enhancementApplied: String = "",
        upscaled: Bool = false,
        cropped: Bool = false,
        edited: Bool = false,
        exported: Bool = false,
        checksum: String? = nil,
        sequence: Int = 0,
        angle: String = "",
        capturedAt: Date = Date(),
        backgroundRemoved: Bool = false,
        enhancementMode: String = "",
        studioAIStrength: String = "",
        canvasWidth: Int = 0,
        canvasHeight: Int = 0,
        fillRatio: Double = 0,
        backgroundStyle: String = "",
        shadowApplied: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.orientation = orientation
        self.format = format
        self.backgroundType = backgroundType
        self.canvasProfile = canvasProfile
        self.enhancementApplied = enhancementApplied
        self.upscaled = upscaled
        self.cropped = cropped
        self.edited = edited
        self.exported = exported
        self.checksum = checksum
        self.sequence = sequence
        self.angle = angle
        self.capturedAt = capturedAt
        self.backgroundRemoved = backgroundRemoved
        self.enhancementMode = enhancementMode
        self.studioAIStrength = studioAIStrength
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.fillRatio = fillRatio
        self.backgroundStyle = backgroundStyle
        self.shadowApplied = shadowApplied
    }
}
