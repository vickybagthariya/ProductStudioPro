import Foundation

struct ExportPackageManifest: Codable, Equatable {
    let projectName: String
    let marketplace: String
    let exportProfile: String
    let imageCount: Int
    let backgroundType: String
    let enhancementSettings: ExportPackageEnhancementSummary
    let shadowEnabled: Bool
    let appVersion: String
    let exportTimestamp: String
    let csvFilename: String
    let imagesFolder: String
}

struct ExportPackageEnhancementSummary: Codable, Equatable {
    let polishEnabledCount: Int
    let backgroundRemovedCount: Int
    let dominantEnhancementMode: String
    let dominantStudioStrength: String
}

enum ManifestGenerator {
    static func generate(
        projectName: String,
        profile: MarketplaceExportProfile,
        products: [CapturedProduct],
        exportDate: Date = Date()
    ) -> ExportPackageManifest {
        let polishCount = products.filter(\.polishEnabled).count
        let bgRemovedCount = products.filter(\.backgroundRemoved).count
        let shadowEnabled = products.contains(where: { $0.studioShadow.isEnabled })
        let dominantMode = mostCommon(products.map(\.enhancementMode.rawValue)) ?? PhotoEnhancementMode.standardClean.rawValue
        let dominantStrength = mostCommon(products.map(\.studioAIStrength.rawValue)) ?? StudioAIStrength.strong.rawValue
        let backgroundType = dominantBackgroundType(for: products)

        return ExportPackageManifest(
            projectName: projectName,
            marketplace: profile.id.displayName,
            exportProfile: profile.id.rawValue,
            imageCount: products.count,
            backgroundType: backgroundType,
            enhancementSettings: ExportPackageEnhancementSummary(
                polishEnabledCount: polishCount,
                backgroundRemovedCount: bgRemovedCount,
                dominantEnhancementMode: dominantMode,
                dominantStudioStrength: dominantStrength
            ),
            shadowEnabled: shadowEnabled,
            appVersion: AppMetadata.marketingVersion,
            exportTimestamp: ISO8601DateFormatter().string(from: exportDate),
            csvFilename: CSVExporter.packageFilename,
            imagesFolder: ZipExporter.imagesFolderName
        )
    }

    static func jsonData(for manifest: ExportPackageManifest) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(manifest)
    }

    private static func dominantBackgroundType(for products: [CapturedProduct]) -> String {
        let labels = products.map { product -> String in
            switch product.resolvedBackgroundFillSpec.fillKind {
            case .solid: return "Solid"
            case .gradient: return "Gradient"
            case .image: return "Image"
            }
        }
        return mostCommon(labels) ?? "Solid"
    }

    private static func mostCommon(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

enum AppMetadata {
    static var marketingVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }
}
