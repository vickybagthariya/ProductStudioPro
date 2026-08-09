import ImageIO
import UIKit

private let importDecodeMaxLongEdgeCap = Int(ImageProcessingLimits.importMaxLongEdge)

/// Decodes photos at a bounded pixel size to avoid full-resolution `UIImage(data:)` peaks during bulk import.
enum ImageImportDecoder {
    static func uiImage(from data: Data, maxLongEdgeRequested: Int = importDecodeMaxLongEdgeCap) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let longest = max(w, h)
        guard longest > 0 else { return UIImage(data: data) }
        // `kCGImageSourceThumbnailMaxPixelSize` must not exceed the image’s pixel longest side or ImageIO logs an error and can fail.
        let maxPL = min(maxLongEdgeRequested, longest)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPL, 1)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    /// Full-resolution decode for camera capture data (no thumbnail downscale).
    static func fullResolutionUIImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: true
        ]
        guard let cg = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = uiOrientation(fromEXIF: (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1)
        let image = UIImage(cgImage: cg, scale: 1, orientation: orientation)
        if let normalized = ImageProcessor.normalizedCGImage(image) {
            return UIImage(cgImage: normalized, scale: 1, orientation: .up)
        }
        return image
    }

    private static func uiOrientation(fromEXIF value: Int) -> UIImage.Orientation {
        switch value {
        case 2: return .upMirrored
        case 3: return .down
        case 4: return .downMirrored
        case 5: return .leftMirrored
        case 6: return .right
        case 7: return .rightMirrored
        case 8: return .left
        default: return .up
        }
    }
}
