import Foundation

/// Persists starred background IDs (bundled paths or `custom.{uuid}`).
enum ImageBackgroundFavoritesStore {
    private static let key = "imageBackgroundFavoriteIDs"

    static var favoriteIDs: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func isFavorite(_ backgroundID: String) -> Bool {
        favoriteIDs.contains(backgroundID)
    }

    static func toggleFavorite(_ backgroundID: String) {
        var ids = favoriteIDs
        if let index = ids.firstIndex(of: backgroundID) {
            ids.remove(at: index)
        } else {
            ids.insert(backgroundID, at: 0)
        }
        UserDefaults.standard.set(ids, forKey: key)
    }
}
