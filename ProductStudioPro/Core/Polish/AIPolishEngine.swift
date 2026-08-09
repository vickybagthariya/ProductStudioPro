import CoreImage
import UIKit

// MARK: - Engine

enum AIPolishEngine {
    /// Injectable backend — defaults to on-device Core Image. Swap for cloud without UI changes.
    private(set) static var backend: AIPolishEnhancing = LocalAIPolishBackend.shared

    static func useBackend(_ backend: AIPolishEnhancing) {
        self.backend = backend
    }

    static func enhance(_ image: UIImage, pass: AIPolishPass, provider: AIPolishProvider = .onDevice) -> UIImage {
        backend.enhance(AIPolishRequest(image: image, pass: pass, provider: provider))
    }
}

// MARK: - Local backend

final class LocalAIPolishBackend: AIPolishEnhancing {
    static let shared = LocalAIPolishBackend()

    private let context = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    func enhance(_ request: AIPolishRequest) -> UIImage {
        switch request.provider {
        case .onDevice:
            return enhanceOnDevice(request.image, pass: request.pass)
        case .cloud:
            // Cloud provider can be wired here later; fall back to on-device for now.
            return enhanceOnDevice(request.image, pass: request.pass)
        }
    }

    private func enhanceOnDevice(_ image: UIImage, pass: AIPolishPass) -> UIImage {
        switch pass {
        case .preComposite:
            return preCompositePass(image)
        case .postComposite:
            return postCompositePass(image)
        }
    }

    // MARK: Pre-composite (full stack)

    private func preCompositePass(_ image: UIImage) -> UIImage {
        guard let cg = ImageProcessor.normalizedCGImage(image) else { return image }
        let profile = analyzeProfile(for: image)
        var ci = CIImage(cgImage: cg)
        ci = autoWhiteBalance(ci)

        let strength: Float = 0.52
        let exposureEV = Float((profile.isDark ? 0.14 : 0.05) + (profile.isVeryDark ? 0.10 : 0.0)) * strength
        let shadowAmount = Float(min(0.48, (profile.shadowDepth > 0.24 ? 0.30 : 0.18) + (profile.isVeryDark ? 0.08 : 0.0))) * strength
        let highlightAmount = Float(profile.averageBrightness > 0.72 ? 0.78 : 0.88)
        let vibranceAmount = Float((profile.isLowColor ? 0.12 : 0.06) * Double(strength))
        let contrastAmount = Float(profile.isFlat ? 1.06 : 1.03)
        let brightnessAmount = Float(profile.isDark ? 0.010 : 0.003)
        let noiseLevel = Float((profile.isDark ? 0.038 : 0.015) * Double(strength))
        let noiseSharpness = Float(profile.isSoft ? 0.30 : 0.42)
        let sharpenAmount: Float = {
            if profile.isAlreadySharp { return 0.12 }
            if profile.isSoft { return 0.17 }
            return 0.14
        }()
        let clarityIntensity: Float = profile.isSoft ? 0.06 : 0.04

        ci = applyExposure(ci, ev: exposureEV)
        ci = applyHighlightShadow(ci, shadowAmount: shadowAmount, highlightAmount: highlightAmount)
        ci = applyVibrance(ci, amount: vibranceAmount)
        ci = applyColorControls(ci, saturation: 1.0, brightness: brightnessAmount, contrast: contrastAmount)
        ci = applyNoiseReduction(ci, noiseLevel: noiseLevel, sharpness: noiseSharpness)
        ci = applyLocalClarity(ci, intensity: clarityIntensity)
        ci = applySharpen(ci, amount: sharpenAmount)

        return render(ci, source: image) ?? image
    }

    // MARK: Post-composite (light finish)

    private func postCompositePass(_ image: UIImage) -> UIImage {
        guard let cg = ImageProcessor.normalizedCGImage(image) else { return image }
        var ci = CIImage(cgImage: cg)
        ci = applyVibrance(ci, amount: 0.02)
        ci = applySharpen(ci, amount: 0.08)
        ci = applyColorControls(ci, saturation: 1.0, brightness: 0, contrast: 1.0)
        return render(ci, source: image) ?? image
    }

    // MARK: CI helpers

    private func applyExposure(_ image: CIImage, ev: Float) -> CIImage {
        let filter = CIFilter.exposureAdjust()
        filter.inputImage = image
        filter.ev = ev
        return filter.outputImage ?? image
    }

    private func applyHighlightShadow(_ image: CIImage, shadowAmount: Float, highlightAmount: Float) -> CIImage {
        let filter = CIFilter.highlightShadowAdjust()
        filter.inputImage = image
        filter.shadowAmount = shadowAmount
        filter.highlightAmount = highlightAmount
        return filter.outputImage ?? image
    }

    private func applyVibrance(_ image: CIImage, amount: Float) -> CIImage {
        let filter = CIFilter.vibrance()
        filter.inputImage = image
        filter.amount = amount
        return filter.outputImage ?? image
    }

    private func applyColorControls(_ image: CIImage, saturation: Float, brightness: Float, contrast: Float) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = saturation
        filter.brightness = brightness
        filter.contrast = contrast
        return filter.outputImage ?? image
    }

    private func applyNoiseReduction(_ image: CIImage, noiseLevel: Float, sharpness: Float) -> CIImage {
        let filter = CIFilter.noiseReduction()
        filter.inputImage = image
        filter.noiseLevel = noiseLevel
        filter.sharpness = sharpness
        return filter.outputImage ?? image
    }

    private func applyLocalClarity(_ image: CIImage, intensity: Float) -> CIImage {
        let filter = CIFilter.unsharpMask()
        filter.inputImage = image
        filter.radius = 2.0
        filter.intensity = intensity
        return filter.outputImage ?? image
    }

    private func applySharpen(_ image: CIImage, amount: Float) -> CIImage {
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image
        filter.sharpness = amount
        return filter.outputImage ?? image
    }

    private func autoWhiteBalance(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let sampleSize = 20
        var bitmap = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        let sampleRect = CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize)
        let scaleX = CGFloat(sampleSize) / extent.width
        let scaleY = CGFloat(sampleSize) / extent.height
        let sampled = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        context.render(
            sampled,
            toBitmap: &bitmap,
            rowBytes: sampleSize * 4,
            bounds: sampleRect,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        for i in stride(from: 0, to: bitmap.count, by: 4) {
            let rr = Double(bitmap[i]) / 255.0
            let gg = Double(bitmap[i + 1]) / 255.0
            let bb = Double(bitmap[i + 2]) / 255.0
            let maxc = max(rr, max(gg, bb))
            let minc = min(rr, min(gg, bb))
            if maxc > 0.18, maxc < 0.98, (maxc - minc) < 0.42 {
                r += rr
                g += gg
                b += bb
                count += 1
            }
        }
        guard count > 8 else { return image }

        r /= count
        g /= count
        b /= count
        let gray = (r + g + b) / 3.0
        let targetR = min(1.0, max(0.01, r * (gray / max(r, 0.01))))
        let targetG = min(1.0, max(0.01, g * (gray / max(g, 0.01))))
        let targetB = min(1.0, max(0.01, b * (gray / max(b, 0.01))))

        let white = CIFilter.whitePointAdjust()
        white.inputImage = image
        white.color = CIColor(red: targetR, green: targetG, blue: targetB)
        return white.outputImage ?? image
    }

    private func render(_ output: CIImage, source: UIImage) -> UIImage? {
        var extent = output.extent
        if extent.isInfinite || extent.isNull || extent.isEmpty {
            guard let cg = ImageProcessor.normalizedCGImage(source) else { return source }
            extent = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        }
        let bounds = extent.integral
        guard bounds.width > 0, bounds.height > 0 else { return source }
        guard let outCG = context.createCGImage(output, from: bounds) else { return nil }
        return UIImage(cgImage: outCG, scale: source.scale, orientation: .up)
    }

    private func analyzeProfile(for image: UIImage) -> AIPolishImageProfile {
        guard let cg = ImageProcessor.normalizedCGImage(image) else {
            return AIPolishImageProfile(
                averageBrightness: 0.56,
                contrast: 0.28,
                blurScore: 0.70,
                shadowDepth: 0.20,
                saturation: 0.22
            )
        }

        let target = 72
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
        ) else {
            return AIPolishImageProfile(
                averageBrightness: 0.56,
                contrast: 0.28,
                blurScore: 0.70,
                shadowDepth: 0.20,
                saturation: 0.22
            )
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luminance = [Double](repeating: 0, count: width * height)
        var lumSum = 0.0
        var satSum = 0.0
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
                lapValues.append(
                    c - luminance[y * width + x - 1] - luminance[y * width + x + 1]
                        - luminance[(y - 1) * width + x] - luminance[(y + 1) * width + x]
                )
            }
        }
        let lapMean = lapValues.reduce(0, +) / Double(max(1, lapValues.count))
        let lapVar = lapValues.reduce(0) { $0 + pow($1 - lapMean, 2) } / Double(max(1, lapValues.count))
        let blurScore = max(0, min(1, lapVar / 0.010))

        return AIPolishImageProfile(
            averageBrightness: avg,
            contrast: contrast,
            blurScore: blurScore,
            shadowDepth: shadows / count,
            saturation: satSum / count
        )
    }
}
