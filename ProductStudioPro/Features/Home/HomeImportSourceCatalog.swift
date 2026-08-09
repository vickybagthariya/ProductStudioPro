import Foundation
import SwiftUI

/// A single import entry for the Home “More Import Options” disclosure.
struct HomeImportSourceOption: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var isAvailable: Bool
    let action: () -> Void
}

/// Registry of Home import sources — add new providers here without redesigning the screen.
enum HomeImportSourceCatalog {
    static func homeScreenSources(
        isImporting: Bool,
        onImportFiles: @escaping () -> Void,
        onImportURL: @escaping () -> Void,
        onImportClipboard: @escaping () -> Void
    ) -> [HomeImportSourceOption] {
        [
            HomeImportSourceOption(
                id: "files",
                title: "Import from Files",
                systemImage: PSDesignIcons.folder,
                isAvailable: !isImporting,
                action: onImportFiles
            ),
            HomeImportSourceOption(
                id: "url",
                title: "Import from URL",
                systemImage: "link",
                isAvailable: !isImporting,
                action: onImportURL
            ),
            HomeImportSourceOption(
                id: "clipboard",
                title: "Import from Clipboard",
                systemImage: "doc.on.clipboard",
                isAvailable: !isImporting,
                action: onImportClipboard
            ),
            // Future sources — flip `isAvailable` and wire `action` when implemented.
            HomeImportSourceOption(
                id: "google-drive",
                title: "Google Drive",
                systemImage: "externaldrive",
                isAvailable: false,
                action: {}
            ),
            HomeImportSourceOption(
                id: "dropbox",
                title: "Dropbox",
                systemImage: "shippingbox",
                isAvailable: false,
                action: {}
            ),
            HomeImportSourceOption(
                id: "onedrive",
                title: "OneDrive",
                systemImage: "cloud",
                isAvailable: false,
                action: {}
            ),
            HomeImportSourceOption(
                id: "camera-roll-album",
                title: "Camera Roll Album",
                systemImage: "photo.on.rectangle.angled",
                isAvailable: false,
                action: {}
            ),
        ]
    }
}
