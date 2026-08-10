#if DEBUG
import CoreGraphics
import UIKit

/// Compact DEBUG compare for Final Individual vs Grouped Cover + stored/write health.
/// Entry: Preview → ⋯ → Pipeline Compare.
enum PipelineForensics {
    struct StageArtifact: Identifiable {
        var id: String { key }
        let key: String
        let title: String
        let image: UIImage
        let stats: StageStats
    }

    struct StageStats {
        let name: String
        let meanLuminanceSubject: Double?
        let meanLuminanceAll: Double?
        let dimensions: String
        let colorSpace: String
        let note: String
    }

    struct PixelDiffStats {
        let meanAbsRGB: Double
        let rmsRGB: Double
        let maxRGB: Double
        let meanAbsLuminance: Double
    }

    struct CompareSummary {
        let fVsHSubjectDeltaL: Double?
        let fVsMSubjectDeltaL: Double?
        let mVsISubjectDeltaL: Double?
        let fVsHMeanAbsRGB: Double?
        let fVsMMeanAbsRGB: Double?
        let mVsIMeanAbsRGB: Double?
        let mVsJPEGMeanAbsRGB: Double?
        let conclusion: String
        let writeForensicsNote: String
    }

    struct Report {
        let directory: URL
        let artifacts: [StageArtifact]
        let summary: CompareSummary
        let caseVerdict: String
        let notes: [String]
    }

    /// Compare reconstructed Final Individual (F), Grouped Cover on white (H),
    /// production replay (M), and stored processed asset (I).
    @discardableResult
    static func runForProduct(_ product: CapturedProduct) -> Report {
        let dir = makeOutputDirectory(suffix: "product_\(product.id.uuidString.prefix(8))")
        var artifacts: [StageArtifact] = []
        var notes: [String] = []

        guard let loadedOriginal = QueueImageResolver.uncompressedOriginal(for: product, fallbackToProcessed: false)
            ?? SessionDiskStore.loadOriginalImage(id: product.id) else {
            let summary = CompareSummary(
                fVsHSubjectDeltaL: nil, fVsMSubjectDeltaL: nil, mVsISubjectDeltaL: nil,
                fVsHMeanAbsRGB: nil, fVsMMeanAbsRGB: nil, mVsIMeanAbsRGB: nil, mVsJPEGMeanAbsRGB: nil,
                conclusion: "INCONCLUSIVE — original unavailable",
                writeForensicsNote: ""
            )
            return Report(directory: dir, artifacts: [], summary: summary, caseVerdict: summary.conclusion, notes: ["No original image."])
        }

        let canvasW = max(100, product.canvasWidth)
        let canvasH = max(100, product.canvasHeight)
        let fill = min(1.0, max(0.30, product.fillRatio))
        let original = ImageProcessor.downsampleIfNeededForImportPipeline(
            loadedOriginal,
            maxLongEdgePixels: ImageProcessingLimits.unifiedProcessingMaxLongEdge
        )
        let resolvedShadow: SoftSyntheticShadowSettings = product.polishEnabled ? .off : product.studioShadow

        // F — Final Individual (white composite + polish + finish tuning; brand off for clean Δ)
        guard let cutoutRaw = ImageProcessor.extractForegroundCutout(
            from: original,
            mode: product.enhancementMode,
            strength: product.studioAIStrength,
            cutoutFeather: product.cutoutFeather,
            cutoutBrushMaskData: product.cutoutBrushMaskData
        ) else {
            let summary = CompareSummary(
                fVsHSubjectDeltaL: nil, fVsMSubjectDeltaL: nil, mVsISubjectDeltaL: nil,
                fVsHMeanAbsRGB: nil, fVsMMeanAbsRGB: nil, mVsIMeanAbsRGB: nil, mVsJPEGMeanAbsRGB: nil,
                conclusion: "INCONCLUSIVE — Vision cutout failed",
                writeForensicsNote: ""
            )
            return Report(directory: dir, artifacts: [], summary: summary, caseVerdict: summary.conclusion, notes: ["Cutout failed."])
        }

        let compositeRaw = ImageProcessor.subjectOnWhiteSquare(
            cutoutRaw,
            canvasWidth: canvasW,
            canvasHeight: canvasH,
            fillRatio: fill,
            mode: product.enhancementMode,
            strength: product.studioAIStrength,
            backgroundColor: .white,
            secondaryBackgroundColor: UIColor(white: 0.94, alpha: 1),
            backgroundStyle: .solid,
            gradientColorHexes: ["#FFFFFF"],
            backgroundFillSpec: .catalogWhite,
            subjectRotationDegrees: 0,
            flipHorizontal: false,
            flipVertical: false,
            studioShadow: resolvedShadow
        )
        let afterPost = product.polishEnabled
            ? AIPolishEngine.enhance(compositeRaw, pass: .postComposite)
            : compositeRaw
        let finalIndividual = ImageProcessor.applyExportTuning(
            to: afterPost,
            photoFilter: product.photoFilter,
            photoFilterIntensity: product.photoFilterIntensity,
            adjustAutoEnhance: product.adjustAutoEnhance,
            toneAdjustments: product.toneAdjustments,
            applyBrandMark: false,
            imageNameText: nil
        )
        let fStats = analyze(finalIndividual, name: "F", note: "Final Individual (white, brand off)")
        artifacts.append(StageArtifact(key: "F_FINAL_INDIVIDUAL", title: "F — Final Individual", image: finalIndividual, stats: fStats))

        // H — Grouped Cover single-on-white
        var groupedComposite: UIImage?
        do {
            let pair = try CompositeBundleRenderer.debugRenderSingleProductOnWhite(
                product: product,
                canvasWidth: canvasW,
                canvasHeight: canvasH,
                fillRatio: fill,
                backgroundFillSpec: .catalogWhite,
                primaryColor: .white,
                secondaryColor: UIColor(white: 0.94, alpha: 1)
            )
            groupedComposite = pair.composite
            let hStats = analyze(pair.composite, name: "H", note: "Grouped Cover white composite")
            artifacts.append(StageArtifact(key: "H_GROUPED_WHITE", title: "H — Grouped Cover", image: pair.composite, stats: hStats))
        } catch {
            notes.append("Grouped Cover render failed: \(error.localizedDescription)")
        }

        // I — stored processed
        var storedImage: UIImage?
        if let url = SessionDiskStore.processedImageFileURL(for: product.id),
           let img = UIImage(contentsOfFile: url.path) {
            storedImage = img
            let iStats = analyze(img, name: "I", note: "Stored proc_*.jpg")
            artifacts.append(StageArtifact(key: "I_STORED", title: "I — Stored Processed", image: img, stats: iStats))
        } else if !product.isProcessedEvicted {
            storedImage = product.image
            let iStats = analyze(product.image, name: "I", note: "In-memory processed (no proc file)")
            artifacts.append(StageArtifact(key: "I_STORED", title: "I — Processed (memory)", image: product.image, stats: iStats))
        } else {
            notes.append("Stored processed asset unavailable.")
        }

        // M — production processForExport replay (no save)
        let fillSpec = product.resolvedBackgroundFillSpec
        let mResult = ImageProcessor.processForExport(
            original,
            removeBackground: product.backgroundRemoved,
            canvasWidth: canvasW,
            canvasHeight: canvasH,
            rotationDegrees: product.rotationDegrees,
            fillRatio: fill,
            polishEnabled: product.polishEnabled,
            enhancementMode: product.enhancementMode,
            studioAIStrength: product.studioAIStrength,
            backgroundColor: product.backgroundColor,
            secondaryBackgroundColor: product.secondaryBackgroundColor,
            backgroundStyle: product.backgroundStyle,
            gradientColorHexes: product.gradientColorHexes,
            backgroundFillSpec: fillSpec,
            smartColorAccuracy: true,
            smartUpscale: false,
            flipHorizontal: product.flipHorizontal,
            flipVertical: product.flipVertical,
            photoFilter: product.photoFilter,
            photoFilterIntensity: product.photoFilterIntensity,
            adjustAutoEnhance: product.adjustAutoEnhance,
            toneAdjustments: product.toneAdjustments,
            cutoutFeather: product.cutoutFeather,
            cutoutBrushMaskData: product.cutoutBrushMaskData,
            studioShadow: resolvedShadow,
            applyBrandMark: !product.suppressBrandMark,
            imageNameText: product.upc,
            maxSourceLongEdge: ImageProcessingLimits.unifiedProcessingMaxLongEdge
        )
        let mImage = mResult.image
        let mStats = analyze(mImage, name: "M", note: "Production processForExport replay")
        artifacts.append(StageArtifact(key: "M_PRODUCTION_REPLAY", title: "M — Production Replay", image: mImage, stats: mStats))

        let fVsH = groupedComposite.flatMap { pixelDifferenceStats(finalIndividual, $0) }
        let fVsM = pixelDifferenceStats(finalIndividual, mImage)
        let mVsI = storedImage.flatMap { pixelDifferenceStats(mImage, $0) }
        let jpegRT = jpegRoundTripOpaque92(mImage)
        let mVsJPEG = jpegRT.flatMap { pixelDifferenceStats(mImage, $0) }

        let fVsH_L = zipDelta(fStats.meanLuminanceSubject, artifacts.first { $0.key == "H_GROUPED_WHITE" }?.stats.meanLuminanceSubject)
        let fVsM_L = zipDelta(fStats.meanLuminanceSubject, mStats.meanLuminanceSubject)
        let mVsI_L = zipDelta(mStats.meanLuminanceSubject, artifacts.first { $0.key == "I_STORED" }?.stats.meanLuminanceSubject)

        let healthyFH = (fVsH?.meanAbsRGB ?? 0) < 0.02 && (fVsH_L.map { abs($0) } ?? 0) < 0.03
        let healthyFM = (fVsM?.meanAbsRGB ?? 0) < 0.02 && (fVsM_L.map { abs($0) } ?? 0) < 0.03
        let healthyMI = storedImage == nil || ((mVsI?.meanAbsRGB ?? 1) < 0.02 && (mVsI_L.map { abs($0) } ?? 1) < 0.03)

        let conclusion: String
        if healthyFM && healthyMI && (groupedComposite == nil || healthyFH) {
            conclusion = "HEALTHY — Final Individual, production replay, and stored processed match."
        } else if healthyFM && !healthyMI {
            conclusion = "STORED MISMATCH — Production replay OK; stored processed diverges."
        } else if !healthyFH && healthyFM {
            conclusion = "INDIVIDUAL vs GROUPED DIVERGENCE — inspect F vs H."
        } else {
            conclusion = "DIVERGENCE — inspect F / H / M / I metrics."
        }

        let writeLines = ProcessedWriteForensics.summaryLines(productID: product.id)
        let writeNote: String = {
            if let strong = ProcessedWriteForensics.firstStrongBoundaryDivergence(productID: product.id) {
                return "Write boundary alert: \(strong.from) → \(strong.to) meanAbsRGB=\(strong.meanAbsRGB.map { String(format: "%.4f", $0) } ?? "n/a")"
            }
            if writeLines.isEmpty {
                return "No live writes this session (capture/import/Apply to populate FINAL_RENDER → DISK_RELOAD)."
            }
            return "Write chain OK (no strong boundary)."
        }()

        notes.append(contentsOf: writeLines)
        if let v = fVsH_L { notes.append(String(format: "F vs H subjectΔL = %+.4f", v)) }
        if let v = fVsM_L { notes.append(String(format: "F vs M subjectΔL = %+.4f", v)) }
        if let v = mVsI_L { notes.append(String(format: "M vs I subjectΔL = %+.4f", v)) }
        if let p = fVsM { notes.append(String(format: "F vs M meanAbsRGB=%.4f", p.meanAbsRGB)) }
        if let p = mVsI { notes.append(String(format: "M vs I meanAbsRGB=%.4f", p.meanAbsRGB)) }
        if let p = mVsJPEG { notes.append(String(format: "M vs JPEG meanAbsRGB=%.4f", p.meanAbsRGB)) }

        let summary = CompareSummary(
            fVsHSubjectDeltaL: fVsH_L,
            fVsMSubjectDeltaL: fVsM_L,
            mVsISubjectDeltaL: mVsI_L,
            fVsHMeanAbsRGB: fVsH?.meanAbsRGB,
            fVsMMeanAbsRGB: fVsM?.meanAbsRGB,
            mVsIMeanAbsRGB: mVsI?.meanAbsRGB,
            mVsJPEGMeanAbsRGB: mVsJPEG?.meanAbsRGB,
            conclusion: conclusion,
            writeForensicsNote: writeNote
        )

        for a in artifacts {
            save(a.image, name: a.key, in: dir)
        }
        writeTextReport(summary: summary, notes: notes, in: dir)
        return Report(
            directory: dir,
            artifacts: artifacts,
            summary: summary,
            caseVerdict: conclusion,
            notes: notes
        )
    }

    static func makeShareZip(for report: Report) -> URL? {
        let zipURL = report.directory.appendingPathComponent("PipelineCompare.zip")
        var entries: [ZipExporter.Entry] = []
        let reportURL = report.directory.appendingPathComponent("report.txt")
        if let data = try? Data(contentsOf: reportURL) {
            entries.append(.init(archivePath: "report.txt", data: data))
        }
        for artifact in report.artifacts {
            if let data = artifact.image.pngData() {
                entries.append(.init(archivePath: "\(artifact.key).png", data: data))
            }
        }
        guard ZipExporter.makePackageZip(entries: entries, zipDestination: zipURL) else { return nil }
        return zipURL
    }

    // MARK: - Helpers

    private static func analyze(_ image: UIImage, name: String, note: String) -> StageStats {
        let cg = image.cgImage
        let w = cg?.width ?? Int(round(image.size.width * image.scale))
        let h = cg?.height ?? Int(round(image.size.height * image.scale))
        let stats = quickLuminance(image)
        return StageStats(
            name: name,
            meanLuminanceSubject: stats?.subjectL,
            meanLuminanceAll: stats?.meanL,
            dimensions: "\(w)×\(h)",
            colorSpace: cg?.colorSpace?.name.map { String(describing: $0) } ?? "nil",
            note: note
        )
    }

    private static func zipDelta(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return b - a
    }

    private static func jpegRoundTripOpaque92(_ image: UIImage) -> UIImage? {
        guard let data = image.jpegDataForOpaqueExport(compressionQuality: 0.92) else { return nil }
        return UIImage(data: data)
    }

    private static func pixelDifferenceStats(_ a: UIImage, _ b: UIImage) -> PixelDiffStats? {
        guard let cga = ImageProcessor.normalizedCGImage(a),
              let cgb = ImageProcessor.normalizedCGImage(b) else { return nil }
        let w = min(cga.width, cgb.width)
        let h = min(cga.height, cgb.height)
        guard w > 0, h > 0 else { return nil }
        let maxEdge = 256
        let scale = min(1, CGFloat(maxEdge) / CGFloat(max(w, h)))
        let aw = max(1, Int(CGFloat(w) * scale))
        let ah = max(1, Int(CGFloat(h) * scale))
        func raster(_ cg: CGImage) -> [UInt8]? {
            let bpr = aw * 4
            var px = [UInt8](repeating: 0, count: ah * bpr)
            guard let ctx = CGContext(
                data: &px, width: aw, height: ah,
                bitsPerComponent: 8, bytesPerRow: bpr,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: aw, height: ah))
            return px
        }
        guard let pa = raster(cga), let pb = raster(cgb) else { return nil }
        var sumAbs = 0.0, sumSq = 0.0, sumL = 0.0, maxD = 0.0
        let n = aw * ah
        let bpr = aw * 4
        for y in 0..<ah {
            for x in 0..<aw {
                let i = y * bpr + x * 4
                let dr = abs(Double(pa[i]) - Double(pb[i])) / 255
                let dg = abs(Double(pa[i + 1]) - Double(pb[i + 1])) / 255
                let db = abs(Double(pa[i + 2]) - Double(pb[i + 2])) / 255
                let d = (dr + dg + db) / 3
                sumAbs += d
                sumSq += dr * dr + dg * dg + db * db
                maxD = max(maxD, max(dr, max(dg, db)))
                let la = 0.2126 * Double(pa[i]) + 0.7152 * Double(pa[i + 1]) + 0.0722 * Double(pa[i + 2])
                let lb = 0.2126 * Double(pb[i]) + 0.7152 * Double(pb[i + 1]) + 0.0722 * Double(pb[i + 2])
                sumL += abs(la - lb) / 255
            }
        }
        let count = Double(n)
        return PixelDiffStats(
            meanAbsRGB: sumAbs / count,
            rmsRGB: sqrt(sumSq / (count * 3)),
            maxRGB: maxD,
            meanAbsLuminance: sumL / count
        )
    }

    private struct QuickL {
        let meanL: Double
        let subjectL: Double?
    }

    private static func quickLuminance(_ image: UIImage) -> QuickL? {
        guard let cg = ImageProcessor.normalizedCGImage(image) else { return nil }
        let maxEdge = 96
        let scale = min(1, CGFloat(maxEdge) / CGFloat(max(cg.width, cg.height)))
        let aw = max(1, Int(CGFloat(cg.width) * scale))
        let ah = max(1, Int(CGFloat(cg.height) * scale))
        let bpr = aw * 4
        var pixels = [UInt8](repeating: 0, count: ah * bpr)
        guard let ctx = CGContext(
            data: &pixels, width: aw, height: ah,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: aw, height: ah))
        var sumL = 0.0, sumSub = 0.0, count = 0, subCount = 0
        for y in 0..<ah {
            for x in 0..<aw {
                let i = y * bpr + x * 4
                let a = Double(pixels[i + 3]) / 255
                guard a > 0.02 else { continue }
                let r = Double(pixels[i]) / 255
                let g = Double(pixels[i + 1]) / 255
                let b = Double(pixels[i + 2]) / 255
                let L = 0.2126 * r + 0.7152 * g + 0.0722 * b
                sumL += L
                count += 1
                if L < 0.97 || abs(r - g) + abs(g - b) > 0.04 {
                    sumSub += L
                    subCount += 1
                }
            }
        }
        guard count > 0 else { return nil }
        return QuickL(meanL: sumL / Double(count), subjectL: subCount > 0 ? sumSub / Double(subCount) : nil)
    }

    private static func makeOutputDirectory(suffix: String) -> URL {
        let candidates = [
            URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PipelineCompare", isDirectory: true),
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("PipelineCompare", isDirectory: true)
        ]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for base in candidates {
            let dir = base.appendingPathComponent("\(stamp)_\(suffix)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir
            } catch { continue }
        }
        return candidates[0]
    }

    private static func save(_ image: UIImage, name: String, in dir: URL) {
        if let data = image.pngData() {
            try? data.write(to: dir.appendingPathComponent("\(name).png"), options: .atomic)
        }
    }

    private static func writeTextReport(summary: CompareSummary, notes: [String], in dir: URL) {
        var lines = [
            "Pipeline Compare Report",
            summary.conclusion,
            summary.writeForensicsNote,
            ""
        ]
        lines.append(contentsOf: notes.map { " - \($0)" })
        try? lines.joined(separator: "\n").write(
            to: dir.appendingPathComponent("report.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
#endif
