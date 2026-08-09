import SwiftUI

struct CanvasPreset: Identifiable, Hashable {
    var id: String { "\(width)x\(height)-\(label)" }
    /// Realistic / marketplace-oriented name shown first in menus.
    let label: String
    /// Technical aspect ratio (kept for clarity alongside px).
    let technicalLabel: String
    let width: Int
    let height: Int

    var menuTitle: String { label }
    var menuSubtitle: String { "\(width)×\(height) · \(technicalLabel)" }
}

enum CanvasPresetCatalog {
    /// Lowered from 3200 as part of the fast+good / lower-memory-pressure profile — the largest
    /// marketplace preset kept is Shopify's 2048×2048.
    static let dimensionBounds: ClosedRange<Int> = 300...2048

    static let all: [CanvasPreset] = [
        CanvasPreset(label: "Catalog square", technicalLabel: "1:1", width: 1200, height: 1200),
        CanvasPreset(label: "Catalog square HD", technicalLabel: "1:1", width: 1600, height: 1600),
        CanvasPreset(label: "Amazon square", technicalLabel: "1:1", width: 2000, height: 2000),
        CanvasPreset(label: "Shopify square", technicalLabel: "1:1", width: 2048, height: 2048),
        CanvasPreset(label: "Instagram story", technicalLabel: "9:16", width: 1080, height: 1920),
        CanvasPreset(label: "YouTube / hero banner", technicalLabel: "16:9", width: 1920, height: 1080),
        CanvasPreset(label: "Wide product banner", technicalLabel: "16:9", width: 1600, height: 900),
        CanvasPreset(label: "Cinema panoramic", technicalLabel: "1.85:1", width: 1998, height: 1080),
        CanvasPreset(label: "Print 5×4", technicalLabel: "5:4", width: 1500, height: 1200),
        CanvasPreset(label: "Print 7×5", technicalLabel: "7:5", width: 1400, height: 1000),
        CanvasPreset(label: "Classic 4×3", technicalLabel: "4:3", width: 1600, height: 1200),
        CanvasPreset(label: "Photo 3×2", technicalLabel: "3:2", width: 1800, height: 1200),
        CanvasPreset(label: "Landscape 5×3", technicalLabel: "5:3", width: 1500, height: 900),
        CanvasPreset(label: "Poster portrait", technicalLabel: "2:3", width: 1200, height: 1800),
        CanvasPreset(label: "Poster landscape", technicalLabel: "3:2", width: 1800, height: 1200),
        CanvasPreset(label: "Social link cover", technicalLabel: "1.91:1", width: 1200, height: 628),
    ]

    /// Clamps into `dimensionBounds` while preserving aspect ratio (independent edge clamps distort presets like 21:9).
    static func clampDimensions(width: Int, height: Int) -> (width: Int, height: Int) {
        let lo = dimensionBounds.lowerBound
        let hi = dimensionBounds.upperBound
        var w = max(1, width)
        var h = max(1, height)

        let longest = max(w, h)
        if longest > hi {
            let scale = Double(hi) / Double(longest)
            w = max(1, Int((Double(w) * scale).rounded()))
            h = max(1, Int((Double(h) * scale).rounded()))
        }

        let shortest = min(w, h)
        if shortest < lo {
            let scale = Double(lo) / Double(shortest)
            w = max(1, Int((Double(w) * scale).rounded()))
            h = max(1, Int((Double(h) * scale).rounded()))
            let longestAfter = max(w, h)
            if longestAfter > hi {
                let down = Double(hi) / Double(longestAfter)
                w = max(1, Int((Double(w) * down).rounded()))
                h = max(1, Int((Double(h) * down).rounded()))
            }
        }

        return (
            min(max(w, lo), hi),
            min(max(h, lo), hi)
        )
    }

    static func actionItems(
        currentWidth: Int,
        currentHeight: Int,
        includeOriginalAspect: Bool = false
    ) -> [DSDropdownActionItem] {
        var items: [DSDropdownActionItem] = [
            .header("\(currentWidth)×\(currentHeight) px"),
        ]
        if includeOriginalAspect {
            items.append(.action("original-aspect", "Original aspect", subtitle: "from import"))
            items.append(.divider("original-divider"))
        }
        for preset in all {
            items.append(
                .action(
                    preset.id,
                    preset.menuTitle,
                    subtitle: preset.menuSubtitle,
                    isSelected: preset.width == currentWidth && preset.height == currentHeight
                )
            )
        }
        items.append(.divider("custom-divider"))
        items.append(.action("custom-size", "Custom Size…", systemImage: "slider.horizontal.below.rectangle"))
        return items
    }

    static func settingsActionItems(currentWidth: Int, currentHeight: Int) -> [DSDropdownActionItem] {
        all.map { preset in
            .action(
                preset.id,
                preset.menuTitle,
                subtitle: preset.menuSubtitle,
                isSelected: preset.width == currentWidth && preset.height == currentHeight
            )
        }
    }
}

struct DSDropdownCanvasPresetMenu<Label: View>: View {
    let currentWidth: Int
    let currentHeight: Int
    var includeOriginalAspect: Bool = false
    let onOriginalAspect: (() -> Void)?
    let onSelect: (_ width: Int, _ height: Int) -> Void
    let onCustom: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        DSDropdownActionMenu(
            label: label,
            items: CanvasPresetCatalog.actionItems(
                currentWidth: currentWidth,
                currentHeight: currentHeight,
                includeOriginalAspect: includeOriginalAspect
            ),
            prefersFullWidth: true
        ) { item in
            switch item.id {
            case "original-aspect":
                onOriginalAspect?()
            case "custom-size":
                onCustom()
            default:
                if let preset = CanvasPresetCatalog.all.first(where: { $0.id == item.id }) {
                    onSelect(preset.width, preset.height)
                }
            }
        }
    }
}
