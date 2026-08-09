import SwiftUI

/// SF Symbol catalog and consistency recommendations for Product Studio.
///
/// Use these constants during screen redesigns to replace inconsistent icon choices.
enum PSDesignIcons {
    // MARK: - Navigation

    static let home = "house.fill"
    static let back = "chevron.left"
    static let close = "xmark"
    static let settings = "gearshape.fill"
    static let more = "ellipsis.circle"

    // MARK: - Catalog workflow

    static let capture = "camera.fill"
    static let importPhotos = "photo.on.rectangle.angled"
    static let queue = "square.stack.3d.up.fill"
    static let export = "square.and.arrow.up"
    static let share = "square.and.arrow.up"
    static let barcode = "barcode.viewfinder"
    static let product = "shippingbox.fill"
    static let folder = "folder.fill"

    // MARK: - Editing

    static let polish = "sparkles"
    static let background = "paintpalette.fill"
    static let cutout = "scissors"
    static let shadow = "shadow"
    static let rotate = "rotate.right"
    static let flip = "arrow.left.and.right.righttriangle.left.righttriangle.right"
    static let filter = "camera.filters"
    static let markup = "pencil.tip.crop.circle"

    // MARK: - Status

    static let success = "checkmark.circle.fill"
    static let warning = "exclamationmark.triangle.fill"
    static let error = "xmark.circle.fill"
    static let info = "info.circle.fill"
    static let loading = "arrow.triangle.2.circlepath"

    // MARK: - Marketplace / export

    static let marketplace = "storefront.fill"
    static let zip = "doc.zipper"
    static let csv = "tablecells"
    static let manifest = "doc.text.fill"

    // MARK: - Replacements

    /// Maps legacy or inconsistent symbols to recommended SF Symbols.
    static let replacements: [String: String] = [
        "photo": importPhotos,
        "photo.fill": importPhotos,
        "camera": capture,
        "gear": settings,
        "ellipsis": more,
        "square.and.arrow.up.on.square": export,
        "doc.text": manifest,
        "sparkle": polish,
        "wand.and.stars": polish,
        "barcode": barcode,
        "qrcode.viewfinder": barcode,
        "folder": folder,
        "house": home,
        "chevron.backward": back,
        "multiply": close,
        "xmark.circle": close,
    ]

    /// Returns the recommended symbol, falling back to the input when no mapping exists.
    static func resolved(_ systemName: String) -> String {
        replacements[systemName] ?? systemName
    }

    /// Standard symbol rendering — monochrome accent for toolbar and list icons.
    static func toolbarIcon(_ systemName: String, size: CGFloat = 17) -> some View {
        Image(systemName: resolved(systemName))
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(PSDesignColors.primaryAccent)
    }
}
