import Foundation
import SwiftUI

// MARK: - Preset category

/// Top-level Studio Preset category — configures the full production pipeline (future).
enum StudioPresetID: String, CaseIterable, Identifiable, Codable {
    case defaultStudio = "default"
    case amazon
    case shopify
    case ebay
    case wholesaleCatalog = "wholesale"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .defaultStudio: return "Default Studio"
        case .amazon: return "Amazon"
        case .shopify: return "Shopify"
        case .ebay: return "eBay"
        case .wholesaleCatalog: return "Wholesale Catalog"
        case .custom: return "Custom"
        }
    }

    /// Preset categories shown on Home.
    static var homeCategories: [StudioPresetID] {
        [.defaultStudio, .amazon, .shopify, .ebay, .wholesaleCatalog, .custom]
    }

    /// Resolves legacy persisted values from the Workflow Preset era.
    static func migrated(from raw: String) -> StudioPresetID {
        StudioPresetID(rawValue: raw) ?? .defaultStudio
    }
}

// MARK: - Pipeline defaults (future-ready)

/// Placeholder pipeline configuration for a Studio Preset.
///
/// Behavior is not implemented yet — fields document the intended architecture
/// for Capture, Studio, Background, Canvas, Export, Metadata, and Marketplace.
struct StudioPresetPipelineDefaults: Equatable, Codable {
    var defaultStylePackID: String?
    // Capture defaults
    // Background preset
    // Canvas dimensions
    // Shadow style
    // AI enhancement mode
    // Export dimensions / format
    // File naming rules
    // Metadata defaults
    // Marketplace export profile
}

// MARK: - Preset definition

/// Full definition of a Studio Preset category and its included styles.
struct StudioPresetDefinition: Identifiable, Equatable {
    let id: StudioPresetID
    let displayName: String
    let stylePackIDs: [String]
    let pipeline: StudioPresetPipelineDefaults

    /// Visual style cards (`CatalogTemplatePack`) for the expanded Preset Styles row.
    func stylePacks(activeStyleID: String?) -> [CatalogTemplatePack] {
        StudioPresetLibrary.stylePacks(for: id, stylePackIDs: stylePackIDs, activeStyleID: activeStyleID)
    }

    /// Default style applied when the user selects this preset category.
    var defaultStylePack: CatalogTemplatePack {
        stylePacks(activeStyleID: nil).first ?? CatalogTemplateLibrary.appDefaults
    }
}

// MARK: - Library

enum StudioPresetLibrary {
    static func definition(for id: StudioPresetID) -> StudioPresetDefinition {
        let styleIDs = stylePackIDs(for: id)
        return StudioPresetDefinition(
            id: id,
            displayName: id.displayName,
            stylePackIDs: styleIDs,
            pipeline: StudioPresetPipelineDefaults(defaultStylePackID: styleIDs.first)
        )
    }

    static func stylePackIDs(for id: StudioPresetID) -> [String] {
        switch id {
        case .defaultStudio:
            return [CatalogTemplateLibrary.appDefaultsID]
        case .amazon:
            return ["amazon-white", "amazon-studio", "amazon-noir"]
        case .shopify:
            return ["editorial-pearl"]
        case .ebay:
            return ["marketplace-amber"]
        case .wholesaleCatalog:
            return ["jewelry", "watch", "marketplace-amber"]
        case .custom:
            return []
        }
    }

    static func stylePacks(
        for presetID: StudioPresetID,
        stylePackIDs: [String],
        activeStyleID: String?
    ) -> [CatalogTemplatePack] {
        if presetID == .custom, let activeStyleID,
           let active = CatalogTemplateLibrary.all.first(where: { $0.id == activeStyleID }) {
            return [active]
        }

        var ordered: [CatalogTemplatePack] = []
        var seen = Set<String>()
        for id in stylePackIDs {
            if let pack = CatalogTemplateLibrary.all.first(where: { $0.id == id }), seen.insert(id).inserted {
                ordered.append(pack)
            }
        }
        if let activeStyleID,
           let active = CatalogTemplateLibrary.all.first(where: { $0.id == activeStyleID }),
           active.id != CatalogTemplateLibrary.appDefaultsID,
           seen.insert(active.id).inserted {
            ordered.insert(active, at: min(1, ordered.count))
        }
        return ordered.isEmpty ? [CatalogTemplateLibrary.appDefaults] : ordered
    }

    /// Maps an applied catalog style back to the best-fit preset category.
    static func matchingPreset(for pack: CatalogTemplatePack) -> StudioPresetID {
        switch pack.id {
        case CatalogTemplateLibrary.appDefaultsID:
            return .defaultStudio
        case "amazon-white", "amazon-studio", "amazon-noir":
            return .amazon
        case "editorial-pearl":
            return .shopify
        case "marketplace-amber":
            return .ebay
        case "jewelry", "watch":
            return .wholesaleCatalog
        default:
            return .custom
        }
    }
}

// MARK: - Legacy alias

@available(*, deprecated, renamed: "StudioPresetID")
typealias WorkflowPresetID = StudioPresetID
