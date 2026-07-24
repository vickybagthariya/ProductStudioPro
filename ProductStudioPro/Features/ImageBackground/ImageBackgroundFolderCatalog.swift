import Foundation

/// Discovers built-in backgrounds from `BackgroundAssets/{category}/*.{png,jpg,jpeg}` in the app bundle.
enum ImageBackgroundFolderCatalog {
    static let bundleFolderName = "BackgroundAssets"
    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg"]

    private static let lock = NSLock()
    private static var cachedCategories: [ImageBackgroundCategory] = []
    private static var cachedDefinitions: [ImageBackgroundDefinition] = []
    private static var cachedDefinitionsByID: [String: ImageBackgroundDefinition] = [:]
    private static var hasLoaded = false

    // MARK: - Public API

    static var categories: [ImageBackgroundCategory] {
        loadIfNeeded()
        if cachedCategories.contains(where: { $0.slug == ImageBackgroundCategory.importedCustom.slug }) {
            return cachedCategories
        }
        return cachedCategories + [.importedCustom]
    }

    static var all: [ImageBackgroundDefinition] {
        loadIfNeeded()
        return cachedDefinitions
    }

    static let essentialsSlug = "essentials"

    static var essentialsCategory: ImageBackgroundCategory {
        ImageBackgroundCategory(slug: essentialsSlug, displayName: "Essentials")
    }

    static var defaultBackgroundID: String {
        loadIfNeeded()
        if let essentialsFirst = cachedDefinitions.first(where: { $0.categorySlug == essentialsSlug }) {
            return essentialsFirst.id
        }
        return cachedDefinitions.first?.id ?? "placeholder/default"
    }

    static var defaultCategorySlug: String {
        loadIfNeeded()
        if cachedCategories.contains(where: { $0.slug == essentialsSlug }) {
            return essentialsSlug
        }
        return cachedCategories.first?.slug ?? ImageBackgroundCategory.importedCustom.slug
    }

    static var essentialDefinitions: [ImageBackgroundDefinition] {
        loadIfNeeded()
        let essentials = cachedDefinitions.filter { $0.categorySlug == essentialsSlug }
        if !essentials.isEmpty { return essentials }
        return cachedDefinitions
    }

    static func definition(id: String) -> ImageBackgroundDefinition? {
        loadIfNeeded()
        if id.hasPrefix("custom."), let recordID = id.split(separator: ".").last.map(String.init) {
            return ImageBackgroundStore.shared.record(id: recordID).map {
                ImageBackgroundStore.shared.definition(for: $0)
            }
        }
        return cachedDefinitionsByID[id]
    }

    static func presets(in category: ImageBackgroundCategory) -> [ImageBackgroundDefinition] {
        loadIfNeeded()
        switch category.slug {
        case ImageBackgroundCategory.recentlyUsed.slug:
            return recentPresets()
        case ImageBackgroundCategory.favorites.slug:
            return favoritePresets()
        case ImageBackgroundCategory.importedCustom.slug:
            let bundled = cachedDefinitions.filter { $0.categorySlug == category.slug }
            let imported = ImageBackgroundStore.shared.allRecords.map {
                ImageBackgroundStore.shared.definition(for: $0)
            }
            return bundled + imported
        default:
            return cachedDefinitions.filter { $0.categorySlug == category.slug }
        }
    }

    static var pickerCategories: [ImageBackgroundCategory] {
        [.recentlyUsed, .favorites] + categories
    }

    static func recentPresets() -> [ImageBackgroundDefinition] {
        ImageBackgroundRecentStore.ids.compactMap { definition(id: $0) }
    }

    static func favoritePresets() -> [ImageBackgroundDefinition] {
        ImageBackgroundFavoritesStore.favoriteIDs.compactMap { definition(id: $0) }
    }

    static func listItems(for ids: [String]) -> [ImageBackgroundListItem] {
        ids.compactMap { id in
            if id.hasPrefix("custom."), let recordID = id.split(separator: ".").last.map(String.init),
               let record = ImageBackgroundStore.shared.record(id: recordID) {
                return ImageBackgroundListItem.custom(record)
            }
            guard let def = definition(id: id) else { return nil }
            return ImageBackgroundListItem.bundled(def)
        }
    }

    static func category(forBackgroundID id: String) -> ImageBackgroundCategory {
        if id.hasPrefix("custom.") {
            return .importedCustom
        }
        if let def = definition(id: id) {
            return categories.first { $0.slug == def.categorySlug }
                ?? ImageBackgroundCategory(slug: def.categorySlug, displayName: displayName(fromFolderSlug: def.categorySlug))
        }
        if let slug = id.split(separator: "/").first.map(String.init) {
            return categories.first { $0.slug == slug }
                ?? ImageBackgroundCategory(slug: slug, displayName: displayName(fromFolderSlug: slug))
        }
        return categories.first ?? .importedCustom
    }

    static func categorySlug(forBackgroundID id: String) -> String {
        category(forBackgroundID: id).slug
    }

    static func reload() {
        lock.lock()
        hasLoaded = false
        cachedCategories = []
        cachedDefinitions = []
        cachedDefinitionsByID = [:]
        lock.unlock()
        loadIfNeeded()
        ImageBackgroundAssetLoader.invalidateCache()
    }

    // MARK: - Discovery

    private static func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !hasLoaded else { return }
        hasLoaded = true
        let discovered = discoverFromBundle()
        cachedCategories = discovered.categories
        cachedDefinitions = discovered.definitions
        cachedDefinitionsByID = Dictionary(uniqueKeysWithValues: discovered.definitions.map { ($0.id, $0) })
    }

    private static func discoverFromBundle() -> (categories: [ImageBackgroundCategory], definitions: [ImageBackgroundDefinition]) {
        guard let rootURL = bundleRootURL() else { return ([], []) }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return ([], []) }

        var categories: [ImageBackgroundCategory] = []
        var definitions: [ImageBackgroundDefinition] = []

        let categoryDirs = entries
            .filter { isDirectory($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for categoryURL in categoryDirs {
            let slug = categoryURL.lastPathComponent
            let category = ImageBackgroundCategory(slug: slug, displayName: displayName(fromFolderSlug: slug))

            guard let files = try? fm.contentsOfDirectory(at: categoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }

            let images = files
                .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                .filter { !($0.deletingPathExtension().lastPathComponent.hasSuffix("_thumb")) }
                .sorted { sortKey(for: $0) < sortKey(for: $1) }

            // Skip empty legacy folders (keep `custom` for virtual imports).
            if images.isEmpty && slug != ImageBackgroundCategory.importedCustom.slug {
                continue
            }

            categories.append(category)

            for fileURL in images {
                let fileName = fileURL.lastPathComponent
                let baseName = fileURL.deletingPathExtension().lastPathComponent
                let resourcePath = "\(bundleFolderName)/\(slug)/\(fileName)"
                let staging = inferStaging(forCategorySlug: slug, fileName: baseName)

                let definition = ImageBackgroundDefinition(
                    id: "\(slug)/\(baseName)",
                    title: displayTitle(fromFileBaseName: baseName),
                    categorySlug: slug,
                    resourcePath: resourcePath,
                    isStaging: staging.isStaging,
                    surfaceLineY: staging.surfaceLineY,
                    defaultScale: staging.defaultScale,
                    defaultX: 0.5,
                    defaultY: staging.isStaging ? (staging.surfaceLineY ?? 0.78) : 0.52
                )
                definitions.append(definition)
            }
        }

        return (categories, definitions)
    }

    static func bundleRootURL() -> URL? {
        if let url = Bundle.main.url(forResource: bundleFolderName, withExtension: nil) {
            return url
        }
        let candidate = Bundle.main.resourceURL?.appendingPathComponent(bundleFolderName, isDirectory: true)
        if let candidate, FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return Bundle.main.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(bundleFolderName, isDirectory: true)
            .takeIf { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func bundleFileURL(for resourcePath: String) -> URL? {
        let components = resourcePath.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }
        let fileName = components.last!
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let subdirectory = components.dropLast().joined(separator: "/")

        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL {
            let direct = resourceURL.appendingPathComponent(resourcePath)
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
        }
        return nil
    }

    // MARK: - Naming & sorting

    static func displayName(fromFolderSlug slug: String) -> String {
        titleCase(slug.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " "))
    }

    static func displayTitle(fromFileBaseName baseName: String) -> String {
        var stripped = baseName
        if let match = baseName.range(of: #"^\d+[-_]"#, options: .regularExpression) {
            stripped = String(baseName[match.upperBound...])
        }
        return titleCase(stripped.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " "))
    }

    private static func sortKey(for url: URL) -> (Int, String) {
        let base = url.deletingPathExtension().lastPathComponent
        let numericPrefix = base.prefix(while: { $0.isNumber })
        let order = Int(numericPrefix) ?? Int.max
        return (order, base.lowercased())
    }

    private static func titleCase(_ text: String) -> String {
        text.split(separator: " ")
            .map { word in
                let w = String(word)
                guard !w.isEmpty else { return w }
                return w.prefix(1).uppercased() + w.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func inferStaging(forCategorySlug slug: String, fileName: String) -> (isStaging: Bool, surfaceLineY: Double?, defaultScale: Double) {
        let haystack = "\(slug)-\(fileName)".lowercased()
        let stagingHints = ["staging", "podium", "shelf", "retail", "counter", "display", "table", "desk", "lifestyle", "smoke", "vape", "store", "cooler", "cabinet", "endcap", "tray", "platform"]
        let isStaging = stagingHints.contains { haystack.contains($0) }
        if isStaging {
            return (true, 0.78, 0.82)
        }
        return (false, nil, 0.88)
    }
}

private extension URL {
    func takeIf(_ predicate: (URL) -> Bool) -> URL? {
        predicate(self) ? self : nil
    }
}
