import Foundation
import UIKit
import ImageIO
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Image Processing

enum ImageProcessingLimits {
    /// Stored original cap — high enough for export, low enough for rapid multi-capture.
    /// Lowered from 4096 as part of the fast+good / lower-memory-pressure profile.
    static let cameraOriginalMaxLongEdge: CGFloat = 3072
    /// Vision / polish input — matches stored original so first-pass quality equals Apply.
    static let cameraProcessingMaxLongEdge: CGFloat = cameraOriginalMaxLongEdge
    /// Bulk import decode / process cap — same as camera for consistent catalog quality.
    static let importMaxLongEdge: CGFloat = cameraOriginalMaxLongEdge
    /// Unified long-edge used by all capture / import / reprocess entry points.
    static var unifiedProcessingMaxLongEdge: CGFloat { cameraProcessingMaxLongEdge }
}

enum ImageProcessor {
    /// Optional UI hook for Vision / pipeline failures (wired by `AppOperationalAlerts`).
    static var onOperationalFailure: ((String) -> Void)?

    /// Shared GPU-backed context — avoid allocating a new CIContext per filter pass.
    static let sharedCIContext: CIContext = {
        CIContext(options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB(),
            .useSoftwareRenderer: false
        ])
    }()

    private static func reportCutoutFailure(_ detail: String? = nil) {
        if let detail, !detail.isEmpty {
            onOperationalFailure?("Background removal failed: \(detail)")
        } else {
            onOperationalFailure?("Couldn’t remove the background for a photo. Kept the original framing.")
        }
    }

    /// Caps input pixel dimensions before Vision cutout / polish to reduce peak memory on multi-import.
    static func downsampleIfNeededForImportPipeline(_ image: UIImage, maxLongEdgePixels: CGFloat) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let longest = max(w, h)
        guard longest > maxLongEdgePixels else { return image }
        let scale = maxLongEdgePixels / longest
        let ciBase = CIImage(cgImage: cg).oriented(forExifOrientation: exifOrientation(from: image.imageOrientation))
        let scaled = ciBase.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ctx = sharedCIContext
        guard let out = ctx.createCGImage(scaled, from: scaled.extent) else { return image }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }

    /// Core Image auto-adjustment stack on a `CIImage` (e.g. Autocorrect style preset).
    static func ciImageAutoAdjustmentChain(_ input: CIImage, extent: CGRect) -> CIImage {
        var ci = input.cropped(to: extent)
        let filters = ci.autoAdjustmentFilters(options: nil)
        guard !filters.isEmpty else { return ci }
        for f in filters {
            f.setValue(ci, forKey: kCIInputImageKey)
            if let out = f.outputImage {
                ci = out.cropped(to: extent)
            }
        }
        return ci
    }

    private static func exifOrientation(from orientation: UIImage.Orientation) -> Int32 {
        switch orientation {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }

    /// Rejects memory-pressure placeholders and other non-exportable bitmaps.
    static func isValidExportBitmap(_ image: UIImage) -> Bool {
        if image === CapturedProduct.diskBackedOriginalPlaceholder { return false }
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        return w > 8 && h > 8
    }

    /// Long-edge cap for live preview — keeps polish/Vision off full 12MP originals during slider/enhance passes.
    static func previewSourceLongEdgeCap(canvasWidth: Int, canvasHeight: Int, preferInteractive: Bool) -> CGFloat {
        let canvasLong = CGFloat(max(canvasWidth, canvasHeight, 280))
        let multiplier: CGFloat = preferInteractive ? 1.15 : 1.55
        let cap = canvasLong * multiplier
        return min(max(640, cap), ImageProcessingLimits.unifiedProcessingMaxLongEdge)
    }

    /// Thread-safe normalization using Core Image (no main-thread `UIGraphicsImageRenderer`).
    static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        guard let baseCG = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: baseCG).oriented(forExifOrientation: exifOrientation(from: image.imageOrientation))
        let ctx = sharedCIContext
        return ctx.createCGImage(ciImage, from: ciImage.extent)
    }

    static func imageByApplyingRotationDegrees(_ image: UIImage, degrees: Double) -> UIImage {
        let norm = degrees.truncatingRemainder(dividingBy: 360)
        guard abs(norm) > 0.001, let cg = normalizedCGImage(image) else { return image }
        let radians = CGFloat(norm * .pi / 180)
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rotatedBounds = CGRect(x: 0, y: 0, width: w, height: h).applying(CGAffineTransform(rotationAngle: radians))
        let outSize = CGSize(width: ceil(abs(rotatedBounds.width)), height: ceil(abs(rotatedBounds.height)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.interpolationQuality = .high
            c.translateBy(x: outSize.width / 2, y: outSize.height / 2)
            c.rotate(by: radians)
            c.translateBy(x: -w / 2, y: -h / 2)
            c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    /// Fill used when compositing: matches the user’s `baseFill` unless the rotated subject’s axis-aligned bounds would extend past the canvas, in which case returns the largest fill ≤ `baseFill` that fits (down to ~0.30).
    static func effectiveLayoutFillRatio(
        canvasWidth: Int,
        canvasHeight: Int,
        imageSize: CGSize,
        rotationDegrees: Double,
        baseFill: Double
    ) -> Double {
        let base = min(1.0, max(0.30, baseFill))
        let cw = CGFloat(max(1, canvasWidth))
        let ch = CGFloat(max(1, canvasHeight))
        let lw = max(imageSize.width, 1)
        let lh = max(imageSize.height, 1)
        let rad = CGFloat(abs(rotationDegrees) * .pi / 180)
        let c = abs(cos(rad))
        let s = abs(sin(rad))

        func fits(_ fill: CGFloat) -> Bool {
            let f = min(1, max(0.30, fill))
            let fitW = cw * f
            let fitH = ch * f
            let scale = min(fitW / CGFloat(lw), fitH / CGFloat(lh))
            let dw = CGFloat(lw) * scale
            let dh = CGFloat(lh) * scale
            let halfW = abs(dw * 0.5 * c) + abs(dh * 0.5 * s)
            let halfH = abs(dw * 0.5 * s) + abs(dh * 0.5 * c)
            let eps: CGFloat = 0.5
            return halfW <= cw * 0.5 + eps && halfH <= ch * 0.5 + eps
        }

        let cgBase = CGFloat(base)
        if fits(cgBase) { return base }
        var lo: CGFloat = 0.30
        var hi = cgBase
        guard fits(lo) else { return 0.30 }
        for _ in 0..<30 {
            let mid = (lo + hi) * 0.5
            if fits(mid) { lo = mid } else { hi = mid }
        }
        return Double(lo)
    }

    private static func applyAutoEnhanceIfNeeded(_ image: UIImage, enabled: Bool) -> UIImage {
        guard enabled else { return image }
        guard let cg = normalizedCGImage(image) else { return image }
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height))
        var ci = CIImage(cgImage: cg).cropped(to: bounds)
        // Closest public equivalent to Photos’ “auto magic wand”: Core Image’s auto-adjustment stack
        // (exposure, contrast, highlights/shadows, etc.), not a single brightness tweak.
        // Image is normalized to `.up` so default auto-adjustment options apply correctly.
        let filters = ci.autoAdjustmentFilters(options: nil)
        guard !filters.isEmpty else { return image }
        for f in filters {
            f.setValue(ci, forKey: kCIInputImageKey)
            if let out = f.outputImage {
                ci = out.cropped(to: bounds)
            }
        }
        let ctx = sharedCIContext
        guard let outCG = ctx.createCGImage(ci, from: bounds) else { return image }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: .up)
    }

    private static func finishPhotoExportTuning(
        _ image: UIImage,
        photoFilter: ExportPhotoFilter,
        photoFilterIntensity: Double,
        adjustAutoEnhance: Bool,
        toneAdjustments: ManualToneAdjustments = .neutral,
        applyBrandMark: Bool = true,
        imageNameText: String? = nil
    ) -> UIImage {
        // Adjust → Tone → Styles: auto-enhance, then manual tone row, then Style blend.
        let adjusted = applyAutoEnhanceIfNeeded(image, enabled: adjustAutoEnhance)
        let toned = applyManualToneAdjustments(adjusted, tones: toneAdjustments)
        let filtered = applyPhotoExportFilter(toned, filter: photoFilter, intensity: photoFilterIntensity)
        guard applyBrandMark else { return filtered }
        return BrandMarkRenderer.applyIfNeeded(filtered, imageNameText: imageNameText)
    }

    /// Applies auto-enhance + tone + export filter to an already-composited raster without re-running the full canvas pipeline.
    static func applyExportTuning(
        to image: UIImage,
        photoFilter: ExportPhotoFilter,
        photoFilterIntensity: Double,
        adjustAutoEnhance: Bool,
        toneAdjustments: ManualToneAdjustments = .neutral,
        applyBrandMark: Bool = true,
        imageNameText: String? = nil
    ) -> UIImage {
        finishPhotoExportTuning(
            image,
            photoFilter: photoFilter,
            photoFilterIntensity: photoFilterIntensity,
            adjustAutoEnhance: adjustAutoEnhance,
            toneAdjustments: toneAdjustments,
            applyBrandMark: applyBrandMark,
            imageNameText: imageNameText
        )
    }

    /// Lightroom-lite tone chain (exposure, contrast, highlights/shadows, vibrance, warmth).
    static func applyManualToneAdjustments(_ image: UIImage, tones: ManualToneAdjustments) -> UIImage {
        guard !tones.isNeutral, let cg = normalizedCGImage(image) else { return image }
        let extent = CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height))
        var ci = CIImage(cgImage: cg).cropped(to: extent)

        if abs(tones.exposure) > 0.001 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = ci
            exposure.ev = Float(tones.exposure)
            ci = exposure.outputImage?.cropped(to: extent) ?? ci
        }

        if abs(tones.highlights) > 0.001 || abs(tones.shadows) > 0.001 {
            let hs = CIFilter.highlightShadowAdjust()
            hs.inputImage = ci
            // Map −1…+1 → shadow/highlight amounts Core Image expects.
            hs.highlightAmount = Float(1.0 - tones.highlights * 0.55)
            hs.shadowAmount = Float(tones.shadows * 0.65)
            ci = hs.outputImage?.cropped(to: extent) ?? ci
        }

        if abs(tones.contrast) > 0.001 || abs(tones.vibrance) > 0.001 {
            if abs(tones.vibrance) > 0.001 {
                let vibrance = CIFilter.vibrance()
                vibrance.inputImage = ci
                vibrance.amount = Float(tones.vibrance * 0.85)
                ci = vibrance.outputImage?.cropped(to: extent) ?? ci
            }
            if abs(tones.contrast) > 0.001 {
                let color = CIFilter.colorControls()
                color.inputImage = ci
                color.contrast = Float(1.0 + tones.contrast * 0.35)
                color.saturation = 1.0
                color.brightness = 0
                ci = color.outputImage?.cropped(to: extent) ?? ci
            }
        }

        if abs(tones.warmth) > 0.001 {
            let warm = CIFilter.temperatureAndTint()
            warm.inputImage = ci
            warm.neutral = CIVector(x: 6500, y: 0)
            warm.targetNeutral = CIVector(x: 6500 - tones.warmth * 1400, y: tones.warmth * 8)
            ci = warm.outputImage?.cropped(to: extent) ?? ci
        }

        guard let out = sharedCIContext.createCGImage(ci, from: extent) else { return image }
        return UIImage(cgImage: out, scale: image.scale, orientation: .up)
    }

    /// Small preview for the Photos-style style strip (always full intensity).
    static func stylePreviewThumbnail(from image: UIImage, filter: ExportPhotoFilter, maxPixel: CGFloat = 160) -> UIImage {
        guard let base = StylePreviewPipeline.prepareThumbnailBase(from: image, maxLongEdge: maxPixel) else {
            return image
        }
        return StylePreviewPipeline.applyFilter(filter, to: base)
    }

    /// Filter pass on an already-downsampled bitmap (style strip pipeline).
    static func applyPhotoExportFilterForStylePreview(_ image: UIImage, filter: ExportPhotoFilter) -> UIImage {
        applyPhotoExportFilter(image, filter: filter, intensity: 1)
    }

    /// Clamps near-white backdrop pixels to pure white so filter/blend passes do not leave purple-gray JPEG halos.
    static func suppressNearWhiteBackdropArtifacts(_ image: UIImage, backdrop: UIColor = .white) -> UIImage {
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        backdrop.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        guard ba >= 0.98, br >= 0.90, bg >= 0.90, bb >= 0.90 else { return image }
        guard let cg = normalizedCGImage(image) else { return image }
        let width = cg.width, height = cg.height
        let bytesPerPixel = 4, bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let minChannel: UInt8 = 238
        let maxChroma: UInt8 = 28
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * bytesPerPixel
                let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
                let hi = max(r, max(g, b))
                let lo = min(r, min(g, b))
                if hi >= minChannel, hi - lo <= maxChroma {
                    pixels[i] = 255
                    pixels[i + 1] = 255
                    pixels[i + 2] = 255
                    pixels[i + 3] = 255
                }
            }
        }

        guard let out = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage() else { return image }
        return UIImage(cgImage: out, scale: image.scale, orientation: .up)
    }

    private static func applyPhotoExportFilter(_ image: UIImage, filter: ExportPhotoFilter, intensity: Double) -> UIImage {
        guard filter != .none, filter != .standard else { return image }
        let t = CGFloat(min(1, max(0, intensity)))
        guard t > 0.001, let cg = normalizedCGImage(image) else { return image }
        let extentRect = CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height))
        let ci = CIImage(cgImage: cg).cropped(to: extentRect)
        let filteredCI: CIImage?
        switch filter {
        case .none, .standard:
            filteredCI = nil
        case .trueWhiteBackdrop:
            filteredCI = ci
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.85 * Double(t),
                    "inputShadowAmount": 0.08 * Double(t),
                ])
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.18 * t])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + 0.12 * t,
                    kCIInputBrightnessKey: 0.10 * t,
                ])
        case .pureBlackShadow:
            filteredCI = ci
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + 0.32 * t,
                    kCIInputBrightnessKey: 0.08 * t,
                ])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputShadowAmount": 0.22 * Double(t),
                    "inputHighlightAmount": 0.12 * Double(t),
                ])
                .applyingFilter("CIToneCurve", parameters: [
                    "inputPoint0": CIVector(x: 0, y: 0),
                    "inputPoint1": CIVector(x: 0.12, y: 0.02 * t),
                    "inputPoint2": CIVector(x: 0.5, y: 0.5),
                    "inputPoint3": CIVector(x: 0.88, y: 0.95),
                    "inputPoint4": CIVector(x: 1, y: 1),
                ])
        case .fabricGrainPop:
            filteredCI = ci
                .applyingFilter("CIUnsharpMask", parameters: [
                    kCIInputRadiusKey: 2.0,
                    kCIInputIntensityKey: 0.55 * t,
                ])
                .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.42 * t])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1 + 0.08 * t])
        case .metallicShimmer:
            filteredCI = ci
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + 0.22 * t,
                    kCIInputSaturationKey: 1 - 0.04 * t,
                ])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.18 * Double(t),
                    "inputShadowAmount": -0.08 * Double(t),
                ])
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.18 * t])
        case .trueNeutralizer:
            var neutralized = ciImageAutoAdjustmentChain(ci.cropped(to: extentRect), extent: extentRect)
            neutralized = neutralized.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500, y: 0),
            ])
            filteredCI = neutralized
        case .antiGlare:
            filteredCI = ci
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": -0.55 * Double(t),
                    "inputShadowAmount": 0.08 * Double(t),
                ])
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.06 * t])
        case .warmLuxury:
            filteredCI = ci
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5200 - 280 * Double(t), y: 4 * Double(t)),
                ])
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.15 * t])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1 + 0.06 * t,
                    kCIInputContrastKey: 1 + 0.04 * t,
                ])
        case .coolEditorial:
            filteredCI = ci
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7600 + 300 * Double(t), y: -6 * Double(t)),
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + 0.16 * t,
                    kCIInputSaturationKey: 1 - 0.06 * t,
                ])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputShadowAmount": 0.12 * Double(t),
                    "inputHighlightAmount": 0.08 * Double(t),
                ])
        case .eCommerceVivid:
            filteredCI = ci
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.65 * t])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputShadowAmount": 0.18 * Double(t),
                    "inputHighlightAmount": 0.10 * Double(t),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1 + 0.06 * t])
        case .auto:
            filteredCI = ImageProcessor.ciImageAutoAdjustmentChain(ci.cropped(to: extentRect), extent: extentRect)
        case .premiumRetail:
            filteredCI = ci
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.45 * t])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + 0.08 * t,
                    kCIInputSaturationKey: 1 + 0.05 * t,
                ])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputShadowAmount": 0.15 * Double(t),
                    "inputHighlightAmount": 0.12 * Double(t),
                ])
        case .luxuryMatte:
            filteredCI = ci
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1 - 0.12 * t,
                    kCIInputContrastKey: 1 + 0.06 * t,
                ])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": -0.08 * Double(t),
                    "inputShadowAmount": 0.1 * Double(t),
                ])
        case .jewelryShine:
            filteredCI = ci
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + 0.28 * t,
                    kCIInputSaturationKey: 1 - 0.02 * t,
                ])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.35 * Double(t),
                ])
                .applyingFilter("CIUnsharpMask", parameters: [
                    kCIInputRadiusKey: 1.5,
                    kCIInputIntensityKey: 0.35 * t,
                ])
        case .watchStudio:
            filteredCI = ci
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.28 * Double(t),
                    "inputShadowAmount": 0.35 * Double(t),
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + 0.18 * t,
                    kCIInputBrightnessKey: 0.04 * t,
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 6200, y: 0),
                ])
        case .premiumCatalog:
            filteredCI = ci
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.7 * Double(t),
                    "inputShadowAmount": 0.05 * Double(t),
                ])
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.12 * t])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1 + 0.06 * t])
        case .socialMedia:
            filteredCI = ci
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.5 * t])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1 + 0.14 * t,
                    kCIInputContrastKey: 1 + 0.1 * t,
                ])
        case .instagramPop:
            filteredCI = ci
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.62 * t])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5400 - 200 * Double(t), y: 0),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1 + 0.12 * t])
        case .tiktokBright:
            filteredCI = ci
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.32 * t])
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.48 * t])
                .applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": 0.22 * Double(t)])
        case .creatorMode:
            filteredCI = ci
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.35 * t])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1 + 0.08 * t,
                    kCIInputContrastKey: 1 + 0.05 * t,
                    kCIInputBrightnessKey: 0.03 * t,
                ])
        case .dramatic:
            filteredCI = ci.applyingFilter("CIPhotoEffectProcess", parameters: [:])
        case .dramaticCool:
            filteredCI = ci.applyingFilter("CIPhotoEffectProcess", parameters: [:])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 8200 + 480 * Double(t), y: 0),
                ])
        case .chrome:
            filteredCI = ci.applyingFilter("CIPhotoEffectChrome", parameters: [:])
        case .noir:
            filteredCI = ci.applyingFilter("CIPhotoEffectNoir", parameters: [:])
        case .vantage:
            filteredCI = ci
                .applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": 0.22 * Double(t), "inputShadowAmount": 0.28 * Double(t)])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + 0.08 * t, kCIInputContrastKey: 1 + 0.12 * t, kCIInputBrightnessKey: 0.02 * t])
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.35 * t])
                .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.55 * t, kCIInputRadiusKey: 2.0])
        case .highKeyLightMono:
            filteredCI = ci
                .applyingFilter("CIPhotoEffectMono", parameters: [:])
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.42 * t])
                .applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": 0.28 * Double(t), "inputShadowAmount": 0.52 * Double(t)])
        case .studioLight:
            filteredCI = ci
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.35 * Double(t),
                    "inputShadowAmount": 0.55 * Double(t),
                ])
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.18 * t])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5600 - 350 * Double(t), y: 0),
                ])
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.55 * t])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + 0.12 * t,
                    kCIInputSaturationKey: 1 + 0.08 * t,
                ])
        case .stageLightMono:
            filteredCI = ci
                .applyingFilter("CIPhotoEffectMono", parameters: [:])
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.28 * Double(t),
                    "inputShadowAmount": 0.48 * Double(t),
                ])
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.22 * t])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + 0.32 * t,
                    kCIInputBrightnessKey: 0.10 * t,
                ])
                .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.65 * t, kCIInputRadiusKey: 1.4])
        case .polaroidVintage:
            filteredCI = ci
                .applyingFilter("CIPhotoEffectFade", parameters: [:])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 - 0.18 * t, kCIInputBrightnessKey: 0.05 * t])
        case .lomo:
            filteredCI = ci
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.55 * t])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + 0.18 * t, kCIInputContrastKey: 1 + 0.15 * t])
                .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.85 * t, kCIInputRadiusKey: 1.0])
        case .kodachrome:
            filteredCI = ci
                .applyingFilter("CIPhotoEffectChrome", parameters: [:])
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.45 * t])
        case .crossProcess:
            filteredCI = ci
                .applyingFilter("CIPhotoEffectProcess", parameters: [:])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7200 + 400 * Double(t), y: 8 * Double(t)),
                ])
        case .film:
            filteredCI = ci
                .applyingFilter("CIPhotoEffectProcess", parameters: [:])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1 - 0.08 * t,
                    kCIInputContrastKey: 1 + 0.05 * t,
                ])
        case .portra400:
            filteredCI = ci
                .applyingFilter("CIPhotoEffectFade", parameters: [:])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5500 - 300 * Double(t), y: 4 * Double(t)),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + 0.06 * t])
        case .fujiClassic:
            filteredCI = ci
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7000 + 200 * Double(t), y: -4 * Double(t)),
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1 + 0.1 * t,
                    kCIInputSaturationKey: 1 - 0.04 * t,
                ])
        case .cineStill:
            filteredCI = ci
                .applyingFilter("CIPhotoEffectProcess", parameters: [:])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7500 + 350 * Double(t), y: 10 * Double(t)),
                ])
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.25 * t])
        case .gotham:
            filteredCI = ci
                .applyingFilter("CIPhotoEffectNoir", parameters: [:])
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.08 * t])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1 + 0.28 * t])
        case .sunriseGlow:
            filteredCI = ci
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.12 * t])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 4800 - 500 * Double(t), y: -10 * Double(t)),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + 0.1 * t])
        case .photosVibrant:
            filteredCI = ci
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.55 * t])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + 0.18 * t, kCIInputContrastKey: 1 + 0.1 * t])
        case .photosNatural:
            filteredCI = ci.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1 + 0.06 * t,
                kCIInputContrastKey: 1 + 0.04 * t,
                kCIInputBrightnessKey: 0.02 * t,
            ])
        case .photosLuminous:
            filteredCI = ci
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.35 * t])
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.35 * t])
                .applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": 0.2 * Double(t), "inputHighlightAmount": 0.15 * Double(t)])
        case .photosCozy:
            filteredCI = ci
                .applyingFilter("CIPhotoEffectTransfer", parameters: [:])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5200 - 280 * Double(t), y: 8 * Double(t)),
                ])
        case .photosEthereal:
            filteredCI = ci
                .applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 8 * t, kCIInputIntensityKey: 0.35 * t])
                .applyingFilter("CIPhotoEffectFade", parameters: [:])
                .applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: 0.2 * t])
        case .thermal:
            filteredCI = ci.applyingFilter("CIThermal", parameters: [:])
        case .invert:
            filteredCI = ci.applyingFilter("CIColorInvert", parameters: [:])
        case .negative:
            filteredCI = ci.applyingFilter("CIColorInvert", parameters: [:])
        case .posterize:
            let levels = Float(8 + 20 * (1 - t))
            filteredCI = ci.applyingFilter("CIColorPosterize", parameters: ["inputLevels": levels])
        }
        guard let rawOut = filteredCI else { return image }
        let out = rawOut.cropped(to: extentRect)
        let context = sharedCIContext
        guard let outCG = context.createCGImage(out, from: extentRect) else { return image }
        let filtered = UIImage(cgImage: outCG, scale: 1, orientation: .up)
        let sz = image.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: sz, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: sz), blendMode: .normal, alpha: 1)
            filtered.draw(in: CGRect(origin: .zero, size: sz), blendMode: .normal, alpha: t)
        }
    }

    static func processForExport(
        _ image: UIImage,
        removeBackground: Bool,
        canvasWidth: Int,
        canvasHeight: Int,
        rotationDegrees: Double = 0,
        fillRatio: Double,
        polishEnabled: Bool = true,
        enhancementMode: PhotoEnhancementMode = .standardClean,
        studioAIStrength: StudioAIStrength = .strong,
        backgroundColor: UIColor = .white,
        secondaryBackgroundColor: UIColor = UIColor(white: 0.94, alpha: 1.0),
        backgroundStyle: BackgroundCanvasStyle = .solid,
        gradientColorHexes: [String] = ["#FFFFFF"],
        backgroundFillSpec: BackgroundFillSpec? = nil,
        smartColorAccuracy: Bool = true,
        smartUpscale: Bool = false,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        photoFilter: ExportPhotoFilter = .none,
        photoFilterIntensity: Double = 1.0,
        adjustAutoEnhance: Bool = false,
        toneAdjustments: ManualToneAdjustments = .neutral,
        cutoutFeather: Double = 0.35,
        cutoutBrushMaskData: Data? = nil,
        studioShadow: SoftSyntheticShadowSettings = .studioDefault,
        applyBrandMark: Bool = true,
        imageNameText: String? = nil,
        maxSourceLongEdge: CGFloat = ImageProcessingLimits.unifiedProcessingMaxLongEdge
    ) -> (image: UIImage, didRemoveBackground: Bool) {
        let fillSpec = backgroundFillSpec ?? BackgroundFillSpec.fromLegacy(style: backgroundStyle, hexes: gradientColorHexes)
        let resolvedStudioShadow = polishEnabled ? SoftSyntheticShadowSettings.off : studioShadow
        let capped = downsampleIfNeededForImportPipeline(image, maxLongEdgePixels: maxSourceLongEdge)
        let input = polishEnabled ? AIPolishEngine.enhance(capped, pass: .preComposite) : capped
        let layoutFill = effectiveLayoutFillRatio(
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            imageSize: input.size,
            rotationDegrees: rotationDegrees,
            baseFill: fillRatio
        )

        if removeBackground,
           let bgRemoved = appleSubjectOnWhiteSquare(
            input,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            fillRatio: layoutFill,
            mode: enhancementMode,
            strength: studioAIStrength,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: backgroundStyle,
            gradientColorHexes: gradientColorHexes,
            backgroundFillSpec: fillSpec,
            subjectRotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            cutoutFeather: cutoutFeather,
            cutoutBrushMaskData: cutoutBrushMaskData,
            studioShadow: resolvedStudioShadow
           ) {
            let polished = polishEnabled ? AIPolishEngine.enhance(bgRemoved, pass: .postComposite) : bgRemoved
            let tuned = finishPhotoExportTuning(
                polished,
                photoFilter: photoFilter,
                photoFilterIntensity: photoFilterIntensity,
                adjustAutoEnhance: adjustAutoEnhance,
                toneAdjustments: toneAdjustments,
                applyBrandMark: applyBrandMark,
                imageNameText: imageNameText
            )
            return (tuned, true)
        }

        let squared = whiteSquare(
            input,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            fillRatio: layoutFill,
            mode: enhancementMode,
            strength: studioAIStrength,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: backgroundStyle,
            gradientColorHexes: gradientColorHexes,
            backgroundFillSpec: fillSpec,
            subjectRotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical
        )
        let polished = polishEnabled ? AIPolishEngine.enhance(squared, pass: .postComposite) : squared
        let tuned = finishPhotoExportTuning(
            polished,
            photoFilter: photoFilter,
            photoFilterIntensity: photoFilterIntensity,
            adjustAutoEnhance: adjustAutoEnhance,
            toneAdjustments: toneAdjustments,
            applyBrandMark: applyBrandMark,
            imageNameText: imageNameText
        )
        return (tuned, false)
    }

    /// Lays the pristine capture on the same canvas geometry as the processed preview (no polish, cutout, or filters).
    /// Letterboxing uses a neutral gray so Before never mimics After’s studio fill.
    static func comparisonOriginalOnCanvas(
        _ image: UIImage,
        canvasWidth: Int,
        canvasHeight: Int,
        rotationDegrees: Double = 0,
        fillRatio: Double,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        backgroundColor: UIColor = UIColor(white: 0.55, alpha: 1.0),
        secondaryBackgroundColor: UIColor = UIColor(white: 0.48, alpha: 1.0),
        backgroundStyle: BackgroundCanvasStyle = .solid,
        gradientColorHexes: [String] = ["#8C8C8C"],
        backgroundFillSpec: BackgroundFillSpec? = nil
    ) -> UIImage {
        // Ignore After’s studio/image fill — Before must show the raw capture, not a second processed look.
        let neutralFill = BackgroundFillSpec.fromLegacy(style: .solid, hexes: ["#8C8C8C"])
        return processForExport(
            image,
            removeBackground: false,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            rotationDegrees: rotationDegrees,
            fillRatio: fillRatio,
            polishEnabled: false,
            enhancementMode: .standardClean,
            studioAIStrength: .natural,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: .solid,
            gradientColorHexes: ["#8C8C8C"],
            backgroundFillSpec: neutralFill,
            smartColorAccuracy: false,
            smartUpscale: false,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            photoFilter: .none,
            photoFilterIntensity: 1.0,
            adjustAutoEnhance: false,
            applyBrandMark: false
        ).image
    }

    /// Pixel bounds of the detected subject in the normalized original image (Vision foreground mask).
    /// Uses a downsampled proxy so large originals do not exhaust memory.
    static func subjectBoundsInOriginal(from image: UIImage, maxAnalysisEdge: CGFloat = 768) -> CGRect? {
        guard #available(iOS 17.0, *), let cg = normalizedCGImage(image) else { return nil }
        let ow = CGFloat(cg.width)
        let oh = CGFloat(cg.height)
        let longest = max(ow, oh, 1)
        let scaleDown = longest > maxAnalysisEdge ? maxAnalysisEdge / longest : 1
        let analysisCG: CGImage
        if scaleDown < 1 {
            let tw = max(1, Int((ow * scaleDown).rounded()))
            let th = max(1, Int((oh * scaleDown).rounded()))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil,
                width: tw,
                height: th,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
            guard let scaled = ctx.makeImage() else { return nil }
            analysisCG = scaled
        } else {
            analysisCG = cg
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: analysisCG, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
            let width = CVPixelBufferGetWidth(mask)
            let height = CVPixelBufferGetHeight(mask)
            CVPixelBufferLockBaseAddress(mask, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
            let rowBytes = CVPixelBufferGetBytesPerRow(mask)
            var minX = width, minY = height, maxX = 0, maxY = 0
            for y in 0..<height {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    if row[x] > 18 {
                        minX = min(minX, x)
                        minY = min(minY, y)
                        maxX = max(maxX, x)
                        maxY = max(maxY, y)
                    }
                }
            }
            guard minX < maxX, minY < maxY else { return nil }
            let pad = 2
            minX = max(0, minX - pad)
            minY = max(0, minY - pad)
            maxX = min(width - 1, maxX + pad)
            maxY = min(height - 1, maxY + pad)
            let scaleX = ow / CGFloat(max(width, 1))
            let scaleY = oh / CGFloat(max(height, 1))
            return CGRect(
                x: CGFloat(minX) * scaleX,
                y: CGFloat(minY) * scaleY,
                width: CGFloat(maxX - minX + 1) * scaleX,
                height: CGFloat(maxY - minY + 1) * scaleY
            )
        } catch {
            return nil
        }
    }

    /// Bounding box of the processed subject in an After preview (differs from studio/canvas background).
    /// Coordinates are in the normalized CGImage pixel space of `image`.
    static func contentBoundsInProcessedPreview(_ image: UIImage, maxAnalysisEdge: CGFloat = 768) -> CGRect? {
        guard isValidExportBitmap(image), let cg = normalizedCGImage(image) else { return nil }
        let ow = CGFloat(cg.width)
        let oh = CGFloat(cg.height)
        guard ow >= 2, oh >= 2 else { return nil }
        let longest = max(ow, oh, 1)
        let scaleDown = longest > maxAnalysisEdge ? maxAnalysisEdge / longest : 1
        let tw = max(1, Int((ow * scaleDown).rounded()))
        let th = max(1, Int((oh * scaleDown).rounded()))
        guard tw >= 2, th >= 2 else { return nil }
        let bytesPerPixel = 4
        let bytesPerRow = tw * bytesPerPixel
        let pixelCount = th * bytesPerRow
        guard pixelCount >= bytesPerPixel * 4 else { return nil }
        var pixels = [UInt8](repeating: 0, count: pixelCount)
        guard let ctx = CGContext(
            data: &pixels,
            width: tw,
            height: th,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))

        func sample(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let cx = min(max(0, x), tw - 1)
            let cy = min(max(0, y), th - 1)
            let i = (cy * bytesPerRow) + (cx * bytesPerPixel)
            guard i + 2 < pixels.count else { return (0, 0, 0) }
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        let insetX = min(max(1, tw / 50), tw - 1)
        let insetY = min(max(1, th / 50), th - 1)
        let corners = [
            sample(insetX, insetY),
            sample(tw - 1 - insetX, insetY),
            sample(insetX, th - 1 - insetY),
            sample(tw - 1 - insetX, th - 1 - insetY),
            sample(tw / 2, insetY),
            sample(tw / 2, th - 1 - insetY),
            sample(insetX, th / 2),
            sample(tw - 1 - insetX, th / 2),
        ]
        let bgR = corners.reduce(0) { $0 + $1.0 } / corners.count
        let bgG = corners.reduce(0) { $0 + $1.1 } / corners.count
        let bgB = corners.reduce(0) { $0 + $1.2 } / corners.count

        var minX = tw, minY = th, maxX = 0, maxY = 0
        // Near-white studio fills need a slightly higher threshold so soft shadows don’t inflate the box.
        let threshold = 22
        for y in 0..<th {
            let row = y * bytesPerRow
            for x in 0..<tw {
                let i = row + x * bytesPerPixel
                guard i + 3 < pixels.count else { continue }
                let a = Int(pixels[i + 3])
                if a < 12 { continue }
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                let dr = abs(r - bgR)
                let dg = abs(g - bgG)
                let db = abs(b - bgB)
                if max(dr, max(dg, db)) > threshold || (dr + dg + db) > threshold * 2 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard minX < maxX, minY < maxY else { return nil }
        let pad = 1
        minX = max(0, minX - pad)
        minY = max(0, minY - pad)
        maxX = min(tw - 1, maxX + pad)
        maxY = min(th - 1, maxY + pad)
        let sx = ow / CGFloat(tw)
        let sy = oh / CGFloat(th)
        let bounds = CGRect(
            x: CGFloat(minX) * sx,
            y: CGFloat(minY) * sy,
            width: CGFloat(maxX - minX + 1) * sx,
            height: CGFloat(maxY - minY + 1) * sy
        )
        if bounds.width > ow * 0.97 && bounds.height > oh * 0.97 { return nil }
        if bounds.width < 4 || bounds.height < 4 { return nil }
        return bounds
    }

    /// Pixel size of an image’s normalized bitmap (orientation baked in).
    static func normalizedPixelSize(of image: UIImage) -> CGSize {
        if let cg = normalizedCGImage(image) {
            return CGSize(width: cg.width, height: cg.height)
        }
        return CGSize(
            width: max(1, image.size.width * image.scale),
            height: max(1, image.size.height * image.scale)
        )
    }

    /// Full original photo (background intact) aligned so the subject sits at the same canvas position/size as the processed cutout.
    static func comparisonOriginalAlignedToCutout(
        _ original: UIImage,
        canvasWidth: Int,
        canvasHeight: Int,
        rotationDegrees: Double = 0,
        fillRatio: Double,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        backgroundFillSpec: BackgroundFillSpec? = nil,
        backgroundStyle: BackgroundCanvasStyle = .solid,
        gradientColorHexes: [String] = ["#FFFFFF"],
        cutoutSize: CGSize? = nil,
        afterImage: UIImage? = nil
    ) -> UIImage {
        // Prefer After’s real pixel canvas so Before/After share identical bitmap dimensions.
        let canvasSize: CGSize = {
            if let afterImage {
                let px = normalizedPixelSize(of: afterImage)
                if px.width > 1, px.height > 1 { return px }
            }
            return CGSize(width: max(1, canvasWidth), height: max(1, canvasHeight))
        }()
        let outW = Int(canvasSize.width.rounded())
        let outH = Int(canvasSize.height.rounded())

        guard let normalized = normalizedCGImage(original) else {
            return comparisonOriginalOnCanvas(
                original,
                canvasWidth: outW,
                canvasHeight: outH,
                rotationDegrees: rotationDegrees,
                fillRatio: fillRatio,
                flipHorizontal: flipHorizontal,
                flipVertical: flipVertical
            )
        }
        let orientedOriginal = UIImage(cgImage: normalized, scale: 1, orientation: .up)

        // Same full-resolution cutout mask After uses — not the downsampled Vision proxy (that caused corner-zoom).
        guard let cutoutResult = extractForegroundCutoutAndSourceBounds(from: orientedOriginal) else {
            return comparisonOriginalOnCanvas(
                original,
                canvasWidth: outW,
                canvasHeight: outH,
                rotationDegrees: rotationDegrees,
                fillRatio: fillRatio,
                flipHorizontal: flipHorizontal,
                flipVertical: flipVertical
            )
        }
        let subjectBounds = cutoutResult.sourceBounds
        let cutout = cutoutResult.cutout

        // Where the subject sits in After (ground truth), else the same layout math After uses.
        let productRect: CGRect = {
            if let afterImage,
               isValidExportBitmap(afterImage),
               let afterBounds = contentBoundsInProcessedPreview(afterImage),
               afterBounds.width > 4, afterBounds.height > 4 {
                return afterBounds
            }
            let layoutSize: CGSize = {
                if let cutoutSize, cutoutSize.width > 4, cutoutSize.height > 4 {
                    return cutoutSize
                }
                return cutout.size
            }()
            let layoutFill = effectiveLayoutFillRatio(
                canvasWidth: outW,
                canvasHeight: outH,
                imageSize: layoutSize,
                rotationDegrees: rotationDegrees,
                baseFill: fillRatio
            )
            let fillSpec = backgroundFillSpec ?? BackgroundFillSpec.fromLegacy(style: backgroundStyle, hexes: gradientColorHexes)
            if fillSpec.fillKind == .image,
               let selection = fillSpec.imageSelection {
                let definition = ImageBackgroundRenderer.resolvedDefinition(for: selection)
                return ProductCompositeRenderer.productDrawRect(
                    cutoutSize: layoutSize,
                    canvasSize: canvasSize,
                    fillRatio: layoutFill,
                    background: definition,
                    selection: selection
                )
            }
            let fitW = canvasSize.width * CGFloat(max(0.30, min(layoutFill, 1.0)))
            let fitH = canvasSize.height * CGFloat(max(0.30, min(layoutFill, 1.0)))
            let lw = max(layoutSize.width, 1)
            let lh = max(layoutSize.height, 1)
            let scale = min(fitW / lw, fitH / lh)
            let drawSize = CGSize(width: lw * scale, height: lh * scale)
            return CGRect(
                x: (canvasSize.width - drawSize.width) / 2,
                y: (canvasSize.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
        }()

        let ow = orientedOriginal.size.width
        let oh = orientedOriginal.size.height
        let bx = subjectBounds.minX
        let by = subjectBounds.minY
        let bw = max(subjectBounds.width, 1)
        let bh = max(subjectBounds.height, 1)
        let pw = max(productRect.width, 1)
        let ph = max(productRect.height, 1)

        // Exact map: original subject rect → After subject rect (same as stretching the cutout into productRect).
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.interpolationQuality = .high
            context.setShouldAntialias(true)
            UIColor(white: 0.55, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))

            let radians = CGFloat(rotationDegrees * .pi / 180)
            let sx: CGFloat = flipHorizontal ? -1 : 1
            let sy: CGFloat = flipVertical ? -1 : 1
            context.saveGState()
            context.translateBy(x: productRect.midX, y: productRect.midY)
            context.rotate(by: radians)
            context.scaleBy(x: sx, y: sy)

            // Same local placement After uses when drawing the cutout into productRect.
            let localOrigin = CGPoint(
                x: -pw / 2 - (bx / bw) * pw,
                y: -ph / 2 - (by / bh) * ph
            )
            let localSize = CGSize(width: (ow / bw) * pw, height: (oh / bh) * ph)
            orientedOriginal.draw(in: CGRect(origin: localOrigin, size: localSize))
            context.restoreGState()
        }
    }

    static func comparisonOriginalForProcessedPreview(
        _ original: UIImage,
        canvasWidth: Int,
        canvasHeight: Int,
        rotationDegrees: Double = 0,
        fillRatio: Double,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        alignToCutout: Bool,
        backgroundFillSpec: BackgroundFillSpec? = nil,
        backgroundStyle: BackgroundCanvasStyle = .solid,
        gradientColorHexes: [String] = ["#FFFFFF"],
        cutoutSize: CGSize? = nil,
        afterImage: UIImage? = nil
    ) -> UIImage {
        if alignToCutout, #available(iOS 17.0, *) {
            return comparisonOriginalAlignedToCutout(
                original,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
                rotationDegrees: rotationDegrees,
                fillRatio: fillRatio,
                flipHorizontal: flipHorizontal,
                flipVertical: flipVertical,
                backgroundFillSpec: backgroundFillSpec,
                backgroundStyle: backgroundStyle,
                gradientColorHexes: gradientColorHexes,
                cutoutSize: cutoutSize,
                afterImage: afterImage
            )
        }
        return comparisonOriginalOnCanvas(
            original,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            rotationDegrees: rotationDegrees,
            fillRatio: fillRatio,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical
        )
    }

    static func comparisonOriginalOnCanvasAsync(
        _ image: UIImage,
        canvasWidth: Int,
        canvasHeight: Int,
        rotationDegrees: Double = 0,
        fillRatio: Double,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        alignToCutout: Bool = false,
        backgroundColor: UIColor = .white,
        secondaryBackgroundColor: UIColor = UIColor(white: 0.94, alpha: 1.0),
        backgroundStyle: BackgroundCanvasStyle = .solid,
        gradientColorHexes: [String] = ["#FFFFFF"],
        backgroundFillSpec: BackgroundFillSpec? = nil,
        cutoutSize: CGSize? = nil,
        afterImage: UIImage? = nil
    ) async -> UIImage {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = autoreleasepool {
                    comparisonOriginalForProcessedPreview(
                        image,
                        canvasWidth: canvasWidth,
                        canvasHeight: canvasHeight,
                        rotationDegrees: rotationDegrees,
                        fillRatio: fillRatio,
                        flipHorizontal: flipHorizontal,
                        flipVertical: flipVertical,
                        alignToCutout: alignToCutout,
                        backgroundFillSpec: backgroundFillSpec,
                        backgroundStyle: backgroundStyle,
                        gradientColorHexes: gradientColorHexes,
                        cutoutSize: cutoutSize,
                        afterImage: afterImage
                    )
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Caps preview compare bitmap size to avoid OOM while swiping large queues.
    static func cappedPreviewCompareCanvas(width: Int, height: Int, maxEdge: Int = 1024) -> (width: Int, height: Int) {
        let w = max(1, width)
        let h = max(1, height)
        let longest = max(w, h)
        guard longest > maxEdge else { return (w, h) }
        let scale = Double(maxEdge) / Double(longest)
        return (
            max(320, Int((Double(w) * scale).rounded())),
            max(320, Int((Double(h) * scale).rounded()))
        )
    }

    /// Runs the full export pipeline off the main actor so live preview stays responsive.
    static func processForExportAsync(
        _ image: UIImage,
        removeBackground: Bool,
        canvasWidth: Int,
        canvasHeight: Int,
        rotationDegrees: Double = 0,
        fillRatio: Double,
        polishEnabled: Bool = true,
        enhancementMode: PhotoEnhancementMode = .standardClean,
        studioAIStrength: StudioAIStrength = .strong,
        backgroundColor: UIColor = .white,
        secondaryBackgroundColor: UIColor = UIColor(white: 0.94, alpha: 1.0),
        backgroundStyle: BackgroundCanvasStyle = .solid,
        gradientColorHexes: [String] = ["#FFFFFF"],
        backgroundFillSpec: BackgroundFillSpec? = nil,
        smartColorAccuracy: Bool = true,
        smartUpscale: Bool = false,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        photoFilter: ExportPhotoFilter = .none,
        photoFilterIntensity: Double = 1.0,
        adjustAutoEnhance: Bool = false,
        toneAdjustments: ManualToneAdjustments = .neutral,
        cutoutFeather: Double = 0.35,
        cutoutBrushMaskData: Data? = nil,
        studioShadow: SoftSyntheticShadowSettings = .studioDefault,
        applyBrandMark: Bool = true,
        imageNameText: String? = nil,
        qos: DispatchQoS.QoSClass = .userInitiated,
        maxSourceLongEdge: CGFloat = ImageProcessingLimits.unifiedProcessingMaxLongEdge
    ) async -> (image: UIImage, didRemoveBackground: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: qos).async {
                let result = autoreleasepool {
                    processForExport(
                        image,
                        removeBackground: removeBackground,
                        canvasWidth: canvasWidth,
                        canvasHeight: canvasHeight,
                        rotationDegrees: rotationDegrees,
                        fillRatio: fillRatio,
                        polishEnabled: polishEnabled,
                        enhancementMode: enhancementMode,
                        studioAIStrength: studioAIStrength,
                        backgroundColor: backgroundColor,
                        secondaryBackgroundColor: secondaryBackgroundColor,
                        backgroundStyle: backgroundStyle,
                        gradientColorHexes: gradientColorHexes,
                        backgroundFillSpec: backgroundFillSpec,
                        smartColorAccuracy: smartColorAccuracy,
                        smartUpscale: smartUpscale,
                        flipHorizontal: flipHorizontal,
                        flipVertical: flipVertical,
                        photoFilter: photoFilter,
                        photoFilterIntensity: photoFilterIntensity,
                        adjustAutoEnhance: adjustAutoEnhance,
                        toneAdjustments: toneAdjustments,
                        cutoutFeather: cutoutFeather,
                        cutoutBrushMaskData: cutoutBrushMaskData,
                        studioShadow: studioShadow,
                        applyBrandMark: applyBrandMark,
                        imageNameText: imageNameText,
                        maxSourceLongEdge: maxSourceLongEdge
                    )
                }
                continuation.resume(returning: result)
            }
        }
    }

    static func whiteSquare(_ image: UIImage, canvasWidth: Int = 1200, canvasHeight: Int = 1200, fillRatio: Double = 0.95, mode: PhotoEnhancementMode = .standardClean, strength: StudioAIStrength = .strong, backgroundColor: UIColor = .white, secondaryBackgroundColor: UIColor = UIColor(white: 0.94, alpha: 1.0), backgroundStyle: BackgroundCanvasStyle = .solid, gradientColorHexes: [String] = ["#FFFFFF"], backgroundFillSpec: BackgroundFillSpec? = nil, subjectRotationDegrees: Double = 0, flipHorizontal: Bool = false, flipVertical: Bool = false, studioShadow: SoftSyntheticShadowSettings = .off) -> UIImage {
        drawImageOnCanvas(image, canvasWidth: canvasWidth, canvasHeight: canvasHeight, fillRatio: fillRatio, strength: strength, backgroundColor: backgroundColor, secondaryBackgroundColor: secondaryBackgroundColor, backgroundStyle: backgroundStyle, gradientColorHexes: gradientColorHexes, backgroundFillSpec: backgroundFillSpec, subjectRotationDegrees: subjectRotationDegrees, flipHorizontal: flipHorizontal, flipVertical: flipVertical, studioShadow: studioShadow)
    }

    static func subjectOnWhiteSquare(_ subject: UIImage, canvasWidth: Int = 1200, canvasHeight: Int = 1200, fillRatio: Double = 0.95, mode: PhotoEnhancementMode = .standardClean, strength: StudioAIStrength = .strong, backgroundColor: UIColor = .white, secondaryBackgroundColor: UIColor = UIColor(white: 0.94, alpha: 1.0), backgroundStyle: BackgroundCanvasStyle = .solid, gradientColorHexes: [String] = ["#FFFFFF"], backgroundFillSpec: BackgroundFillSpec? = nil, subjectRotationDegrees: Double = 0, flipHorizontal: Bool = false, flipVertical: Bool = false, studioShadow: SoftSyntheticShadowSettings = .studioDefault) -> UIImage {
        let cleaned = cleanupTransparentEdges(subject, mode: mode, strength: strength)
        let cropped = cropTransparentMargins(cleaned) ?? cleaned
        return drawImageOnCanvas(cropped, canvasWidth: canvasWidth, canvasHeight: canvasHeight, fillRatio: fillRatio, strength: strength, backgroundColor: backgroundColor, secondaryBackgroundColor: secondaryBackgroundColor, backgroundStyle: backgroundStyle, gradientColorHexes: gradientColorHexes, backgroundFillSpec: backgroundFillSpec, subjectRotationDegrees: subjectRotationDegrees, flipHorizontal: flipHorizontal, flipVertical: flipVertical, studioShadow: studioShadow)
    }

    private static func drawImageOnCanvas(_ image: UIImage, canvasWidth: Int, canvasHeight: Int, fillRatio: Double, strength: StudioAIStrength, backgroundColor: UIColor, secondaryBackgroundColor: UIColor, backgroundStyle: BackgroundCanvasStyle, gradientColorHexes: [String] = ["#FFFFFF"], backgroundFillSpec: BackgroundFillSpec? = nil, subjectRotationDegrees: Double = 0, flipHorizontal: Bool = false, flipVertical: Bool = false, studioShadow: SoftSyntheticShadowSettings = .studioDefault) -> UIImage {
        let fillSpec = backgroundFillSpec ?? BackgroundFillSpec.fromLegacy(style: backgroundStyle, hexes: gradientColorHexes)
        let bgCap: CGFloat? = fillSpec.fillKind == .image
            ? CGFloat(max(canvasWidth, canvasHeight)) * 1.35
            : nil
        return ProductCompositeRenderer.composite(
            cutout: image,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            fillRatio: fillRatio,
            backgroundColor: backgroundColor,
            secondaryBackgroundColor: secondaryBackgroundColor,
            backgroundStyle: backgroundStyle,
            gradientColorHexes: gradientColorHexes,
            backgroundFillSpec: backgroundFillSpec,
            subjectRotationDegrees: subjectRotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            studioShadow: studioShadow,
            maxBackgroundLongEdge: bgCap
        )
    }

    static func drawShelfPlinthPublic(in canvas: CGRect, productRect: CGRect, context: CGContext, primary: UIColor, secondary: UIColor) {
        drawShelfPlinth(in: canvas, productRect: productRect, context: context, primary: primary, secondary: secondary)
    }


    private static func drawBackground(in rect: CGRect, context: CGContext, primary: UIColor, secondary: UIColor, style: BackgroundCanvasStyle, gradientColorHexes: [String] = ["#FFFFFF"]) {
        func linear(_ colors: [CGColor], _ locations: [CGFloat], _ start: CGPoint, _ end: CGPoint) {
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }
            context.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
        func radial(_ colors: [CGColor], _ locations: [CGFloat], _ center: CGPoint, _ radius: CGFloat) {
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
        let pickedUIColors = gradientColorHexes.compactMap { UIColor(hexString: $0) }
        let pickedColors = pickedUIColors.map { $0.cgColor }
        let gradientColors: [CGColor]
        if style == .solid {
            gradientColors = [(pickedUIColors.first ?? primary).cgColor]
        } else if pickedColors.count >= 2 {
            gradientColors = pickedColors
        } else {
            let base = pickedUIColors.first ?? primary
            gradientColors = [base.lighter(by: 0.20).cgColor, base.cgColor, base.darker(by: 0.10).cgColor]
        }
        let gradientLocations: [CGFloat] = gradientColors.count == 1 ? [0] : (0..<gradientColors.count).map { CGFloat($0) / CGFloat(max(1, gradientColors.count - 1)) }
        func gradientLocationsFor(_ colors: [CGColor]) -> [CGFloat] {
            colors.count == 1 ? [0] : (0..<colors.count).map { CGFloat($0) / CGFloat(max(1, colors.count - 1)) }
        }

        switch style {
        case .solid:
            primary.setFill(); context.fill(rect)

        case .linearGradient:
            linear(gradientColors, gradientLocations, CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
            radial([UIColor.white.withAlphaComponent(0.12).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.32, y: rect.height * 0.22), rect.width * 0.48)
            radial([UIColor.black.withAlphaComponent(0.05).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.68, y: rect.height * 0.92), rect.width * 0.50)

        case .diagonalGradient:
            linear(gradientColors, gradientLocations, CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
            radial([UIColor.white.withAlphaComponent(0.14).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.28, y: rect.height * 0.22), rect.width * 0.45)
            radial([UIColor.black.withAlphaComponent(0.04).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.84, y: rect.height * 0.85), rect.width * 0.48)

        case .radialGradient:
            primary.setFill(); context.fill(rect)
            radial(Array(gradientColors.reversed()), gradientLocations, CGPoint(x: rect.midX, y: rect.height * 0.42), rect.width * 0.72)
            radial([UIColor.white.withAlphaComponent(0.22).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.height * 0.34), rect.width * 0.42)

        case .seamless:
            let colors = gradientColors.count >= 2 ? gradientColors : [primary.cgColor, primary.lighter(by: 0.18).cgColor]
            linear(colors, gradientLocationsFor(colors), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
            radial([UIColor.white.withAlphaComponent(0.32).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.height * 0.28), rect.width * 0.70)
            radial([UIColor.black.withAlphaComponent(0.07).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.height * 1.05), rect.width * 0.55)
            linear([UIColor.white.withAlphaComponent(0.12).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))

        case .seamlessMono:
            let colors = gradientColors.count >= 2 ? gradientColors : [primary.cgColor, secondary.cgColor]
            linear(colors, gradientLocationsFor(colors), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
            context.saveGState()
            context.setBlendMode(.color)
            UIColor(white: 0.55, alpha: 0.22).setFill()
            context.fill(rect)
            context.restoreGState()
            radial([UIColor.white.withAlphaComponent(0.20).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.height * 0.30), rect.width * 0.65)

        case .colorBackdrop:
            let colors = gradientColors.count >= 2 ? gradientColors : [primary.lighter(by: 0.12).cgColor, primary.cgColor, primary.darker(by: 0.08).cgColor]
            linear(colors, gradientLocationsFor(colors), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
            radial([UIColor.white.withAlphaComponent(0.38).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.height * 0.36), rect.width * 0.58)
            radial([UIColor.black.withAlphaComponent(0.14).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.08), rect.width * 0.78)

        case .colorWash:
            let washTop = (pickedUIColors.first ?? primary).withAlphaComponent(0.55)
            linear([washTop.cgColor, primary.cgColor, secondary.withAlphaComponent(0.35).cgColor], [0, 0.55, 1], CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
            radial([UIColor.white.withAlphaComponent(0.45).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.5, y: rect.height * 0.18), rect.width * 0.62)

        case .duotone:
            linear(gradientColors, gradientLocations, CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
            context.saveGState()
            context.setBlendMode(.screen)
            radial([secondary.withAlphaComponent(0.35).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.72, y: rect.height * 0.22), rect.width * 0.62)
            context.setBlendMode(.softLight)
            radial([primary.withAlphaComponent(0.35).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.20, y: rect.height * 0.80), rect.width * 0.70)
            context.restoreGState()

        case .overprint:
            linear(gradientColors, gradientLocations, CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
            context.saveGState()
            context.setBlendMode(.multiply)
            radial([secondary.withAlphaComponent(0.42).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.78, y: rect.height * 0.25), rect.width * 0.55)
            context.setBlendMode(.overlay)
            radial([primary.withAlphaComponent(0.28).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.18, y: rect.height * 0.78), rect.width * 0.65)
            context.restoreGState()

        case .studio:
            linear(gradientColors, gradientLocations, CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
            linear([UIColor.white.withAlphaComponent(0.42).cgColor, UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.06).cgColor], [0, 0.55, 1], CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
            radial([UIColor.white.withAlphaComponent(0.30).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.height * 0.34), rect.width * 0.52)

        case .blackWhite:
            linear([UIColor.white.cgColor, UIColor(white: 0.90, alpha: 1).cgColor, UIColor(white: 0.12, alpha: 1).cgColor], [0, 0.62, 1], CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))

        case .doubleHalo:
            primary.setFill(); context.fill(rect)
            radial([secondary.withAlphaComponent(0.72).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.36, y: rect.height * 0.34), rect.width * 0.62)
            radial([UIColor.white.withAlphaComponent(0.28).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.66, y: rect.height * 0.23), rect.width * 0.48)
            linear([UIColor.clear.cgColor, secondary.withAlphaComponent(0.18).cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
            radial([UIColor.black.withAlphaComponent(0.10).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.width * 0.52, y: rect.height * 0.92), rect.width * 0.70)

        case .softFloor:
            linear([primary.cgColor, secondary.withAlphaComponent(0.38).cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
            radial([UIColor.white.withAlphaComponent(0.30).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.height * 0.26), rect.width * 0.62)
            radial([UIColor.black.withAlphaComponent(0.06).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.maxY), rect.width * 0.80)

        case .shelfPlinth:
            linear([UIColor(white: 0.97, alpha: 1).cgColor, secondary.withAlphaComponent(0.48).cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
            radial([UIColor.white.withAlphaComponent(0.18).cgColor, UIColor.clear.cgColor], [0, 1], CGPoint(x: rect.midX, y: rect.height * 0.38), rect.width * 0.48)
        }
    }

    private static func drawShelfPlinth(in canvas: CGRect, productRect: CGRect, context: CGContext, primary: UIColor, secondary: UIColor) {
        let width = min(canvas.width * 0.78, max(productRect.width * 1.05, canvas.width * 0.42))
        let height = canvas.height * 0.105
        let x = canvas.midX - width / 2
        let y = min(canvas.height * 0.84, productRect.maxY - height * 0.18)
        let top = CGRect(x: x, y: y, width: width, height: height * 0.74)
        let base = CGRect(x: x + width * 0.06, y: y + height * 0.32, width: width * 0.88, height: height * 1.08)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: canvas.height * 0.016), blur: canvas.width * 0.026, color: UIColor.black.withAlphaComponent(0.17).cgColor)
        secondary.withAlphaComponent(0.64).setFill()
        UIBezierPath(roundedRect: base, cornerRadius: base.height * 0.24).fill()
        UIColor.white.withAlphaComponent(0.25).setFill()
        UIBezierPath(ovalIn: top).fill()
        secondary.withAlphaComponent(0.28).setFill()
        UIBezierPath(ovalIn: top.insetBy(dx: width * 0.08, dy: height * 0.18)).fill()
        context.restoreGState()
    }

    static func cropTransparentMargins(_ image: UIImage) -> UIImage? {
        guard let bounds = opaqueContentBounds(of: image),
              let cg = image.cgImage,
              let cropped = cg.cropping(to: bounds.integral) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    /// Pixel bounds of non-clear content in an image (same criteria as transparent-margin crop).
    static func opaqueContentBounds(of image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        let bytesPerPixel = 4, bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = 0, maxY = 0
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                if alpha > 18 {
                    minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        let pad = 3
        minX = max(0, minX - pad); minY = max(0, minY - pad)
        maxX = min(width - 1, maxX + pad); maxY = min(height - 1, maxY + pad)
        guard minX < maxX, minY < maxY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Transparent PNG cutout using the same Vision foreground mask as background removal (Photos-style subject lift).
    static func extractForegroundCutout(
        from image: UIImage,
        mode: PhotoEnhancementMode = .standardClean,
        strength: StudioAIStrength = .strong,
        cutoutFeather: Double = 0.35,
        cutoutBrushMaskData: Data? = nil
    ) -> UIImage? {
        extractForegroundCutoutAndSourceBounds(
            from: image,
            mode: mode,
            strength: strength,
            cutoutFeather: cutoutFeather,
            cutoutBrushMaskData: cutoutBrushMaskData
        )?.cutout
    }

    // MARK: - Cutout cache

    private static let cutoutCacheLock = NSLock()
    private static var cutoutCache: [String: UIImage] = [:]
    private static var cutoutCacheOrder: [String] = []
    private static let cutoutCacheMaxEntries = 6

    /// Drops Vision cutout bitmaps — called from the memory purge ladder.
    static func clearCutoutCache() {
        cutoutCacheLock.lock()
        cutoutCache.removeAll(keepingCapacity: false)
        cutoutCacheOrder.removeAll(keepingCapacity: false)
        cutoutCacheLock.unlock()
    }

    private static func cutoutCacheKey(
        productID: UUID,
        mode: PhotoEnhancementMode,
        strength: StudioAIStrength,
        image: UIImage,
        cutoutFeather: Double,
        brushMaskBytes: Int
    ) -> String {
        let w = Int(image.size.width.rounded())
        let h = Int(image.size.height.rounded())
        let featherKey = Int((cutoutFeather * 100).rounded())
        return "\(productID.uuidString)|\(mode.rawValue)|\(strength.rawValue)|\(w)x\(h)|f\(featherKey)|b\(brushMaskBytes)"
    }

    static func invalidateCutoutCache(productID: UUID) {
        cutoutCacheLock.lock()
        defer { cutoutCacheLock.unlock() }
        let prefix = productID.uuidString
        cutoutCacheOrder.removeAll { key in
            if key.hasPrefix(prefix) {
                cutoutCache.removeValue(forKey: key)
                return true
            }
            return false
        }
    }

    /// Cached Vision cutout for export / reuse — avoids re-running mask generation.
    static func cachedForegroundCutout(
        for product: CapturedProduct,
        from image: UIImage,
        mode: PhotoEnhancementMode,
        strength: StudioAIStrength
    ) -> UIImage? {
        let key = cutoutCacheKey(
            productID: product.id,
            mode: mode,
            strength: strength,
            image: image,
            cutoutFeather: product.cutoutFeather,
            brushMaskBytes: product.cutoutBrushMaskData?.count ?? 0
        )
        cutoutCacheLock.lock()
        if let hit = cutoutCache[key] {
            cutoutCacheLock.unlock()
            return hit
        }
        cutoutCacheLock.unlock()

        guard let raw = extractForegroundCutout(
            from: image,
            mode: mode,
            strength: strength,
            cutoutFeather: product.cutoutFeather,
            cutoutBrushMaskData: product.cutoutBrushMaskData
        ) else { return nil }
        let scrubbed = scrubCutoutMatteFringe(raw)
        let final = cropTransparentMargins(scrubbed) ?? scrubbed

        cutoutCacheLock.lock()
        cutoutCache[key] = final
        cutoutCacheOrder.removeAll { $0 == key }
        cutoutCacheOrder.append(key)
        while cutoutCacheOrder.count > cutoutCacheMaxEntries {
            let oldest = cutoutCacheOrder.removeFirst()
            cutoutCache.removeValue(forKey: oldest)
        }
        cutoutCacheLock.unlock()
        return final
    }

    /// Cutout plus the subject rect in the source image’s normalized pixel space (pre-crop).
    static func extractForegroundCutoutAndSourceBounds(
        from image: UIImage,
        mode: PhotoEnhancementMode = .standardClean,
        strength: StudioAIStrength = .strong,
        cutoutFeather: Double = 0.35,
        cutoutBrushMaskData: Data? = nil
    ) -> (cutout: UIImage, sourceBounds: CGRect)? {
        guard #available(iOS 17.0, *) else { return nil }
        guard let cg = normalizedCGImage(image) else {
            reportCutoutFailure("couldn’t read the image")
            return nil
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            // Soft miss (no subject) — silent; expected for some lifestyle / cluttered frames.
            guard let observation = request.results?.first else { return nil }
            let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
            let ciImage = CIImage(cgImage: cg)
            var ciMask = smoothMask(
                CIImage(cvPixelBuffer: mask),
                mode: mode,
                strength: strength,
                feather: cutoutFeather
            ).cropped(to: ciImage.extent)
            if let brushData = cutoutBrushMaskData,
               let brushImage = UIImage(data: brushData),
               let brushCG = normalizedCGImage(brushImage) {
                let brushCI = CIImage(cgImage: brushCG)
                let scaledBrush = brushCI.transformed(by: CGAffineTransform(
                    scaleX: ciImage.extent.width / max(brushCI.extent.width, 1),
                    y: ciImage.extent.height / max(brushCI.extent.height, 1)
                )).cropped(to: ciImage.extent)
                let multiply = CIFilter.multiplyCompositing()
                multiply.inputImage = ciMask
                multiply.backgroundImage = scaledBrush
                ciMask = multiply.outputImage?.cropped(to: ciImage.extent) ?? ciMask
            }
            let filter = CIFilter.blendWithMask()
            filter.inputImage = ciImage
            filter.maskImage = ciMask
            filter.backgroundImage = CIImage(color: .clear).cropped(to: ciImage.extent)
            let context = sharedCIContext
            guard let output = filter.outputImage, let outCG = context.createCGImage(output, from: output.extent) else {
                reportCutoutFailure("mask blend failed")
                return nil
            }
            let masked = UIImage(cgImage: outCG, scale: 1, orientation: .up)
            guard let sourceBounds = opaqueContentBounds(of: masked),
                  sourceBounds.width > 4, sourceBounds.height > 4 else { return nil }
            let cutout = cropTransparentMargins(masked) ?? masked
            return (cutout, sourceBounds)
        } catch {
            reportCutoutFailure(error.localizedDescription)
            return nil
        }
    }

    static func appleSubjectOnWhiteSquare(_ image: UIImage, canvasWidth: Int = 1200, canvasHeight: Int = 1200, fillRatio: Double = 0.95, mode: PhotoEnhancementMode = .standardClean, strength: StudioAIStrength = .strong, backgroundColor: UIColor = .white, secondaryBackgroundColor: UIColor = UIColor(white: 0.94, alpha: 1.0), backgroundStyle: BackgroundCanvasStyle = .solid, gradientColorHexes: [String] = ["#FFFFFF"], backgroundFillSpec: BackgroundFillSpec? = nil, subjectRotationDegrees: Double = 0, flipHorizontal: Bool = false, flipVertical: Bool = false, cutoutFeather: Double = 0.35, cutoutBrushMaskData: Data? = nil, studioShadow: SoftSyntheticShadowSettings = .studioDefault) -> UIImage? {
        guard let subject = extractForegroundCutout(
            from: image,
            mode: mode,
            strength: strength,
            cutoutFeather: cutoutFeather,
            cutoutBrushMaskData: cutoutBrushMaskData
        ) else { return nil }
        return subjectOnWhiteSquare(subject, canvasWidth: canvasWidth, canvasHeight: canvasHeight, fillRatio: fillRatio, mode: mode, strength: strength, backgroundColor: backgroundColor, secondaryBackgroundColor: secondaryBackgroundColor, backgroundStyle: backgroundStyle, gradientColorHexes: gradientColorHexes, backgroundFillSpec: backgroundFillSpec, subjectRotationDegrees: subjectRotationDegrees, flipHorizontal: flipHorizontal, flipVertical: flipVertical, studioShadow: studioShadow)
    }

    private static func adaptiveProfile(for image: UIImage) -> AdaptiveImageProfile {
        guard let cg = normalizedCGImage(image) else {
            return AdaptiveImageProfile(averageBrightness: 0.56, contrast: 0.28, blurScore: 0.70, shadowDepth: 0.20, saturation: 0.22)
        }
        let target = 72
        let width = target
        let height = max(1, Int(Double(cg.height) / Double(max(cg.width, 1)) * Double(target)))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return AdaptiveImageProfile(averageBrightness: 0.56, contrast: 0.28, blurScore: 0.70, shadowDepth: 0.20, saturation: 0.22)
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luminance = [Double](repeating: 0, count: width * height)
        var lumSum = 0.0, satSum = 0.0
        var shadows = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * bytesPerPixel
                let r = Double(pixels[i]) / 255.0
                let g = Double(pixels[i + 1]) / 255.0
                let b = Double(pixels[i + 2]) / 255.0
                let maxc = max(r, max(g, b))
                let minc = min(r, min(g, b))
                let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
                luminance[y * width + x] = l
                lumSum += l
                satSum += maxc == 0 ? 0 : (maxc - minc) / maxc
                if l < 0.24 { shadows += 1 }
            }
        }
        let count = Double(max(1, width * height))
        let avg = lumSum / count
        let contrast = sqrt(luminance.reduce(0) { $0 + pow($1 - avg, 2) } / count)
        var lapValues: [Double] = []
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let c = luminance[y * width + x] * 4
                lapValues.append(c - luminance[y * width + x - 1] - luminance[y * width + x + 1] - luminance[(y - 1) * width + x] - luminance[(y + 1) * width + x])
            }
        }
        let lapMean = lapValues.reduce(0, +) / Double(max(1, lapValues.count))
        let lapVar = lapValues.reduce(0) { $0 + pow($1 - lapMean, 2) } / Double(max(1, lapValues.count))
        let blurScore = max(0.0, min(1.0, lapVar / 0.010))
        return AdaptiveImageProfile(averageBrightness: avg, contrast: contrast, blurScore: blurScore, shadowDepth: shadows / count, saturation: satSum / count)
    }

    private static func smoothMask(
        _ mask: CIImage,
        mode: PhotoEnhancementMode,
        strength: StudioAIStrength,
        feather: Double = 0.35
    ) -> CIImage {
        let t = min(1, max(0, feather))
        // Hard edge when feather ≈ 0, otherwise soften.
        if t < 0.02 { return mask }

        let baseRadius: Float = 0.55
        let contrast: Float = 1.10
        let brightness: Float = 0.006
        let blurRadius = baseRadius * Float(0.25 + t * 1.75)

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = mask.clampedToExtent()
        blur.radius = blurRadius

        let controls = CIFilter.colorControls()
        controls.inputImage = blur.outputImage?.cropped(to: mask.extent)
        controls.contrast = contrast
        controls.brightness = brightness
        controls.saturation = 0.0

        return controls.outputImage?.cropped(to: mask.extent) ?? mask
    }

    private static func cleanupTransparentEdges(_ image: UIImage, mode: PhotoEnhancementMode, strength: StudioAIStrength) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let width = cg.width, height = cg.height
        let bytesPerPixel = 4, bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Standard Clean gets a gentle edge tidy — fixes soft halo on the cutout corners.
        let transparentCutoff: UInt8 = 18
        let boostLimit: UInt8 = 200
        let alphaBoost: Int = 10

        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * bytesPerPixel
                let a = pixels[i + 3]
                if a > 0 && a < transparentCutoff {
                    pixels[i + 3] = 0
                } else if a >= transparentCutoff && a < boostLimit {
                    pixels[i + 3] = UInt8(min(255, Int(a) + alphaBoost))
                }
            }
        }

        guard let out = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() else { return image }
        return UIImage(cgImage: out, scale: image.scale, orientation: .up)
    }

    /// Variance-of-Laplacian sharpness score (higher = sharper).
    static func sharpnessScore(_ image: UIImage) -> Double {
        adaptiveProfile(for: image).blurScore
    }

    /// Removes soft-matte / white-edge fringe so background changes don’t leave “stains”.
    /// Important: do **not** boost mid-alphas — that makes white halo more opaque against colored fills.
    static func scrubCutoutMatteFringe(_ image: UIImage) -> UIImage {
        guard let cg = normalizedCGImage(image) else { return image }
        let width = cg.width, height = cg.height
        guard width > 2, height > 2 else { return image }
        let bytesPerPixel = 4, bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Pass 1: clear weak alphas fully (premultiplied RGB + A).
        let clearBelow: UInt8 = 36
        for i in stride(from: 3, to: pixels.count, by: 4) {
            let a = pixels[i]
            if a > 0 && a < clearBelow {
                pixels[i - 3] = 0; pixels[i - 2] = 0; pixels[i - 1] = 0; pixels[i] = 0
            }
        }

        // Pass 2: on subject silhouette edge, kill near-white / high-luma fringe (classic BG-removal stain).
        var out = pixels
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * bytesPerRow + x * bytesPerPixel
                let a = pixels[i + 3]
                guard a > 0, a < 252 else { continue }

                var nextToClear = false
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let ni = (y + dy) * bytesPerRow + (x + dx) * bytesPerPixel
                        if pixels[ni + 3] < 18 { nextToClear = true; break }
                    }
                    if nextToClear { break }
                }
                guard nextToClear else { continue }

                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                // Un-premultiply for color tests when alpha is partial.
                let invA = a > 0 ? 255.0 / Double(a) : 0
                let ur = min(255.0, Double(r) * invA)
                let ug = min(255.0, Double(g) * invA)
                let ub = min(255.0, Double(b) * invA)
                let luma = 0.299 * ur + 0.587 * ug + 0.114 * ub
                let chroma = max(ur, max(ug, ub)) - min(ur, min(ug, ub))

                // Soft edge next to transparent: clear light fringe, or shrink mid alpha.
                let isLightFringe = luma >= 200 && chroma <= 40
                let isPaleFringe = luma >= 170 && chroma <= 55 && a < 200
                if isLightFringe || isPaleFringe || a < 110 {
                    out[i] = 0; out[i + 1] = 0; out[i + 2] = 0; out[i + 3] = 0
                } else if a < 180 {
                    // Slight erosion of remaining soft edge without whitening.
                    let na = UInt8(max(0, Int(a) - 28))
                    if na < clearBelow {
                        out[i] = 0; out[i + 1] = 0; out[i + 2] = 0; out[i + 3] = 0
                    } else {
                        let scale = Double(na) / Double(a)
                        out[i] = UInt8(Double(r) * scale)
                        out[i + 1] = UInt8(Double(g) * scale)
                        out[i + 2] = UInt8(Double(b) * scale)
                        out[i + 3] = na
                    }
                }
            }
        }

        guard let outCG = CGContext(
            data: &out,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage() else { return image }
        return UIImage(cgImage: outCG, scale: 1, orientation: .up)
    }

    /// One-tap edge polish: gentle luma sharpen to reduce soft halos on exported squares.
    static func applyDefringeSharpen(_ image: UIImage) -> UIImage {
        guard let ciIn = CIImage(image: image) else { return image }
        let sharpened = ciIn.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.58, "inputRadius": 1.2])
        let ctx = sharedCIContext
        guard let cg = ctx.createCGImage(sharpened, from: sharpened.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }
}
