import UIKit

/// Derives background fill colors from product subject colors (cutout-first).
enum ProductColorPaletteExtractor {
    enum ExtractError: Error {
        case insufficientColor
    }

    /// Resolution used for palette sampling (keeps brand accents).
    private static let paletteLongEdge: CGFloat = 320
    /// Cheaper proxy for Vision cutout when no preferred cutout is supplied.
    private static let cutoutPrepLongEdge: CGFloat = 512
    private static let hueBinCount = 18
    private static let grayBinCount = 6
    private static let minimumUsablePixels = 28
    private static let minimumBinWeight = 0.03
    /// ~40° separation across 18 hue bins.
    private static let minimumHueSeparation = 2

    /// - Parameters:
    ///   - image: Fallback capture (usually uncompressed original).
    ///   - preferredCutout: Transparent subject cutout when already available (preferred).
    ///   - template: Current fill spec — gradient type/direction/angle are preserved; stops replaced.
    static func fillSpec(
        from image: UIImage,
        preferredCutout: UIImage? = nil,
        preserving template: BackgroundFillSpec
    ) -> Result<BackgroundFillSpec, ExtractError> {
        let sampleImage = prepareSampleImage(from: image, preferredCutout: preferredCutout)

        switch template.fillKind {
        case .solid:
            guard let color = dominantSolidColor(from: sampleImage) else {
                return .failure(.insufficientColor)
            }
            var spec = template
            spec.fillKind = .solid
            spec.overlay = .none
            spec.gradientStops = [GradientColorStop(colorHex: color.hexString, position: 0)]
            spec.normalizeStops()
            return .success(spec)

        case .gradient:
            guard let palette = extractPalette(from: sampleImage, targetCount: 3), !palette.isEmpty else {
                return .failure(.insufficientColor)
            }
            var spec = template
            spec.fillKind = .gradient
            // Preserve gradientType / direction / angle from template; replace colors only.
            spec.gradientStops = GradientColorStop.evenDistribution(hexes: palette.map(\.hexString))
            spec.normalizeStops()
            return .success(spec)

        case .image:
            return .failure(.insufficientColor)
        }
    }

    // MARK: - Sample prep

    private static func prepareSampleImage(from image: UIImage, preferredCutout: UIImage?) -> UIImage {
        // Ignore opaque “cutouts” (e.g. CompositeBundleCutoutLoader falling back to composited product.image).
        if let preferredCutout, hasTransparentSubject(preferredCutout) {
            let cropped = ImageProcessor.cropTransparentMargins(preferredCutout) ?? preferredCutout
            return ImageProcessor.downsampleIfNeededForImportPipeline(
                cropped,
                maxLongEdgePixels: paletteLongEdge
            )
        }

        let cutoutProxy = ImageProcessor.downsampleIfNeededForImportPipeline(
            image,
            maxLongEdgePixels: cutoutPrepLongEdge
        )
        if let cutout = ImageProcessor.extractForegroundCutout(from: cutoutProxy) {
            let cropped = ImageProcessor.cropTransparentMargins(cutout) ?? cutout
            return ImageProcessor.downsampleIfNeededForImportPipeline(
                cropped,
                maxLongEdgePixels: paletteLongEdge
            )
        }

        // No cutout — sample a centered inset of the original to avoid table/edge backdrop bias.
        let downsampled = ImageProcessor.downsampleIfNeededForImportPipeline(
            image,
            maxLongEdgePixels: paletteLongEdge
        )
        return centerInset(downsampled, insetFraction: 0.14) ?? downsampled
    }

    /// True when the image has enough clear pixels to be a real subject cutout (not a full-bleed composite).
    private static func hasTransparentSubject(_ image: UIImage) -> Bool {
        guard let cg = ImageProcessor.normalizedCGImage(image) else { return false }
        let alphaInfo = cg.alphaInfo
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }

        let sample = 48
        let width = sample
        let height = max(1, Int(Double(cg.height) / Double(max(cg.width, 1)) * Double(sample)))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var clearCount = 0
        var opaqueCount = 0
        let total = width * height
        for i in stride(from: 3, to: total * bytesPerPixel, by: bytesPerPixel) {
            if pixels[i] < 24 {
                clearCount += 1
            } else if pixels[i] > 200 {
                opaqueCount += 1
            }
        }
        // Real cutouts have substantial clear margins and a solid subject core.
        return clearCount > total / 12 && opaqueCount > total / 20
    }

    private static func centerInset(_ image: UIImage, insetFraction: CGFloat) -> UIImage? {
        guard let cg = ImageProcessor.normalizedCGImage(image) else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let insetX = w * insetFraction
        let insetY = h * insetFraction
        let rect = CGRect(x: insetX, y: insetY, width: w - insetX * 2, height: h - insetY * 2)
            .integral
        guard rect.width > 8, rect.height > 8,
              let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    // MARK: - Solid

    private static func dominantSolidColor(from image: UIImage) -> UIColor? {
        guard let bins = rankedColorBins(from: image), let top = bins.first else { return nil }
        return studioSafeSolid(top.color)
    }

    /// Clamp only extremes so brand hue/sat stay close; avoid always-pastel wash.
    private static func studioSafeSolid(_ color: UIColor) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return color
        }

        // Mild sat trim only when very punchy; keep near-neutrals as-is.
        let sat = saturation > 0.72 ? saturation * 0.92 : saturation
        var bright = brightness
        if bright < 0.22 { bright = min(1, bright + 0.10) }
        if bright > 0.94 { bright = max(0, bright - 0.08) }

        let adjusted = UIColor(hue: hue, saturation: max(0, min(1, sat)), brightness: max(0, min(1, bright)), alpha: alpha)
        let lum = relativeLuminance(of: adjusted)
        if lum < 0.18 { return adjusted.lighter(by: 0.10) }
        if lum > 0.92 { return adjusted.darker(by: 0.08) }
        return adjusted
    }

    // MARK: - Gradient palette

    private struct ColorBin {
        let index: Int
        let weight: Double
        let color: UIColor
        let hue: CGFloat
        let isNeutral: Bool
    }

    private static func extractPalette(from image: UIImage, targetCount: Int) -> [UIColor]? {
        guard let bins = rankedColorBins(from: image), !bins.isEmpty else { return nil }

        var selected: [ColorBin] = []
        for candidate in bins {
            guard selected.count < targetCount else { break }
            if selected.isEmpty {
                selected.append(candidate)
                continue
            }
            let isDistinct = selected.allSatisfy { existing in
                if existing.isNeutral || candidate.isNeutral {
                    // Neutrals: require meaningfully different luminance.
                    return abs(relativeLuminance(of: existing.color) - relativeLuminance(of: candidate.color)) >= 0.14
                }
                return hueBinDistance(existing.index, candidate.index) >= minimumHueSeparation
            }
            if isDistinct {
                selected.append(candidate)
            }
        }

        // Keep dominance order (primary → secondary → accent). Do not hue-sort.
        var colors = selected.map(\.color)
        colors = supplementPalette(colors, targetCount: targetCount)
        colors = toneBalanceGradient(colors)
        return colors.isEmpty ? nil : colors
    }

    /// If only 1–2 real hues exist:
    /// - 1 color → lighter companion, primary, darker companion (same family) with enough spread to read as a gradient
    /// - 2 colors → lighten on dominant + both hues (keeps brand pair)
    private static func supplementPalette(_ colors: [UIColor], targetCount: Int) -> [UIColor] {
        guard let primary = colors.first else { return [] }
        if colors.count >= targetCount {
            return Array(colors.prefix(targetCount))
        }
        if colors.count == 2 {
            return [
                colors[0].lighter(by: 0.16),
                colors[0],
                colors[1],
            ]
        }
        // Wider luminance spread so a single-hue match still looks like a gradient (not a flat solid).
        return [
            primary.lighter(by: 0.22),
            primary,
            primary.darker(by: 0.18),
        ]
    }

    /// Soft studio clamp without destroying brand order.
    private static func toneBalanceGradient(_ colors: [UIColor]) -> [UIColor] {
        guard !colors.isEmpty else { return colors }
        let lums = colors.map { relativeLuminance(of: $0) }
        let avg = lums.reduce(0, +) / Double(lums.count)

        if avg < 0.28 {
            let boost = CGFloat(0.28 - avg) * 0.7
            return colors.map { $0.lighter(by: boost * 0.65) }
        }
        if avg > 0.88 {
            let reduce = CGFloat(avg - 0.88) * 0.7
            return colors.map { $0.darker(by: reduce * 0.55) }
        }
        return colors
    }

    // MARK: - Binning (chromatic + neutral)

    private static func rankedColorBins(from image: UIImage) -> [ColorBin]? {
        guard let cg = ImageProcessor.normalizedCGImage(image) else { return nil }

        let target = 96
        let width = target
        let height = max(1, Int(Double(cg.height) / Double(max(cg.width, 1)) * Double(target)))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
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

        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hueWeights = [Double](repeating: 0, count: hueBinCount)
        var hueRGBSums = [Double](repeating: 0, count: hueBinCount * 3)
        var grayWeights = [Double](repeating: 0, count: grayBinCount)
        var grayRGBSums = [Double](repeating: 0, count: grayBinCount * 3)
        var usablePixelCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * bytesPerPixel
                let alpha = Double(pixels[i + 3]) / 255.0
                // Prefer opaque subject pixels; allow softer cutout edges.
                guard alpha > 0.35 else { continue }

                let r = Double(pixels[i]) / 255.0
                let g = Double(pixels[i + 1]) / 255.0
                let b = Double(pixels[i + 2]) / 255.0
                let maxc = max(r, max(g, b))
                let minc = min(r, min(g, b))
                let brightness = maxc
                let saturation = maxc == 0 ? 0 : (maxc - minc) / maxc

                // Skip near-clear / noise only — keep blacks, whites, kraft, metallics.
                if alpha < 0.45 && brightness > 0.97 { continue }

                usablePixelCount += 1

                if saturation < 0.12 {
                    // Neutral / metallic / kraft path — brightness bins.
                    let grayIndex = min(grayBinCount - 1, Int(brightness * Double(grayBinCount)))
                    // Mid-grays slightly preferred for backgrounds; still keep extremes.
                    let weight = (0.55 + 0.45 * (1 - abs(brightness - 0.5))) * alpha
                    grayWeights[grayIndex] += weight
                    let base = grayIndex * 3
                    grayRGBSums[base] += r * weight
                    grayRGBSums[base + 1] += g * weight
                    grayRGBSums[base + 2] += b * weight
                    continue
                }

                let weight = saturation * (0.55 + 0.45 * (1 - abs(brightness - 0.48))) * alpha
                guard weight > 0.008 else { continue }

                var hue: CGFloat = 0
                var hSat: CGFloat = 0
                var hBright: CGFloat = 0
                var hAlpha: CGFloat = 0
                UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&hue, saturation: &hSat, brightness: &hBright, alpha: &hAlpha)
                let bin = min(hueBinCount - 1, Int(hue * CGFloat(hueBinCount)))
                hueWeights[bin] += weight
                let base = bin * 3
                hueRGBSums[base] += r * weight
                hueRGBSums[base + 1] += g * weight
                hueRGBSums[base + 2] += b * weight
            }
        }

        guard usablePixelCount >= minimumUsablePixels else { return nil }

        let chromaticWeight = hueWeights.reduce(0, +)
        let neutralWeight = grayWeights.reduce(0, +)
        let totalWeight = chromaticWeight + neutralWeight
        guard totalWeight > 0 else { return nil }

        var bins: [ColorBin] = []

        if chromaticWeight > 0 {
            for index in 0..<hueBinCount {
                let weight = hueWeights[index] / totalWeight
                guard weight >= minimumBinWeight else { continue }
                let base = index * 3
                let denom = max(hueWeights[index], 0.0001)
                let color = UIColor(
                    red: hueRGBSums[base] / denom,
                    green: hueRGBSums[base + 1] / denom,
                    blue: hueRGBSums[base + 2] / denom,
                    alpha: 1
                )
                var sat: CGFloat = 0
                var bright: CGFloat = 0
                var alpha: CGFloat = 0
                var hue: CGFloat = 0
                color.getHue(&hue, saturation: &sat, brightness: &bright, alpha: &alpha)
                bins.append(ColorBin(index: index, weight: weight, color: color, hue: hue, isNeutral: false))
            }
        }

        // Prefer chromatic bins for gradient diversity; only pull neutrals when chroma is weak.
        let includeNeutrals = chromaticWeight / totalWeight < 0.42 || bins.isEmpty
        if includeNeutrals, neutralWeight > 0 {
            for index in 0..<grayBinCount {
                let weight = grayWeights[index] / totalWeight
                guard weight >= minimumBinWeight * 0.75 else { continue }
                let base = index * 3
                let denom = max(grayWeights[index], 0.0001)
                let color = UIColor(
                    red: grayRGBSums[base] / denom,
                    green: grayRGBSums[base + 1] / denom,
                    blue: grayRGBSums[base + 2] / denom,
                    alpha: 1
                )
                bins.append(ColorBin(
                    index: 100 + index,
                    weight: weight,
                    color: color,
                    hue: 0,
                    isNeutral: true
                ))
            }
        }

        guard !bins.isEmpty else { return nil }
        return bins.sorted { $0.weight > $1.weight }
    }

    private static func hueBinDistance(_ a: Int, _ b: Int) -> Int {
        // Neutrals use 100+ indices — distance handled separately by callers.
        guard a < hueBinCount, b < hueBinCount else { return hueBinCount }
        let direct = abs(a - b)
        return min(direct, hueBinCount - direct)
    }

    private static func relativeLuminance(of color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0.5 }
        return Double(0.2126 * red + 0.7152 * green + 0.0722 * blue)
    }
}
