#if DEBUG
import UIKit
import CoreGraphics

/// DEBUG-only fingerprint + write-sequence log for processed-image persistence
/// (`FINAL_RENDER` → `PRODUCT_ASSIGNMENT` → `JPEG_INPUT` → `JPEG_DECODE_IN_MEMORY` → `DISK_RELOAD`).
enum ProcessedWriteForensics {
    enum Boundary: String, CaseIterable {
        case finalRender = "FINAL_RENDER"
        case productAssignment = "PRODUCT_ASSIGNMENT"
        case jpegInput = "JPEG_INPUT"
        case jpegDecodeInMemory = "JPEG_DECODE_IN_MEMORY"
        case diskReload = "DISK_RELOAD"
    }

    struct Fingerprint {
        let productID: UUID
        let boundary: String
        let reason: String
        let timestamp: Date
        let width: Int
        let height: Int
        let colorSpace: String
        let alphaInfo: String
        let bitmapInfo: String
        let orientation: Int
        let scale: CGFloat
        let sourceKind: String
        let meanLuminance: Double?
        let meanRGB: (r: Double, g: Double, b: Double)?
        let subjectMeanLuminance: Double?
        let isPlaceholder: Bool
        let backgroundRemoved: Bool?
        let backgroundStyle: String?
        let backgroundColorHex: String?
        let photoFilter: String?
        let autoEnhance: Bool?
        let polishEnabled: Bool?

        var dimensionSummary: String { "\(width)×\(height)" }
    }

    struct BoundaryDelta: Equatable {
        let from: String
        let to: String
        let subjectDeltaL: Double?
        let meanAbsRGB: Double?
        let rmsRGB: Double?
        let maxRGB: Double?
        /// Strong = material bitmap change. When meanAbsRGB is available it is authoritative
        /// (threshold 0.02). SubjectΔL alone is not used then — studio-plate subject proxies
        /// can flicker across near-white cutoffs without a real persistence failure.
        var isStrong: Bool {
            if let meanAbsRGB {
                return meanAbsRGB > 0.02
            }
            return (subjectDeltaL.map { abs($0) } ?? 0) > 0.02
        }
    }

    struct WriteEvent: Identifiable {
        let id = UUID()
        let sequence: Int
        let productID: UUID
        let reason: String
        let beganAt: Date
        var endedAt: Date?
        var inputFingerprint: Fingerprint?
        var decodeFingerprint: Fingerprint?
        var diskFingerprint: Fingerprint?
        var skippedAsPlaceholder: Bool
        var byteCount: Int?
        var fileName: String
    }

    struct ProductWriteTrace {
        var events: [WriteEvent] = []
        var boundaryChain: [Fingerprint] = []
        var lastFinalRender: Fingerprint?
        var lastAssignment: Fingerprint?
    }

    private static let lock = NSLock()
    private static var writeCounters: [UUID: Int] = [:]
    private static var traces: [UUID: ProductWriteTrace] = [:]
    private static var openWrites: [UUID: WriteEvent] = [:]

    // MARK: - Public API

    static func reset(productID: UUID? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let productID {
            writeCounters[productID] = 0
            traces[productID] = ProductWriteTrace()
            openWrites = openWrites.filter { $0.value.productID != productID }
        } else {
            writeCounters.removeAll()
            traces.removeAll()
            openWrites.removeAll()
        }
    }

    static func trace(for productID: UUID) -> ProductWriteTrace {
        lock.lock()
        defer { lock.unlock() }
        return traces[productID] ?? ProductWriteTrace()
    }

    static func recordBoundary(
        _ boundary: Boundary,
        image: UIImage,
        productID: UUID,
        reason: String,
        product: CapturedProduct? = nil
    ) {
        let fp = makeFingerprint(
            image: image,
            productID: productID,
            boundary: boundary.rawValue,
            reason: reason,
            product: product
        )
        lock.lock()
        var trace = traces[productID] ?? ProductWriteTrace()
        trace.boundaryChain.append(fp)
        switch boundary {
        case .finalRender: trace.lastFinalRender = fp
        case .productAssignment: trace.lastAssignment = fp
        default: break
        }
        traces[productID] = trace
        lock.unlock()
        NSLog("[ProcessedWriteForensics] %@ id=%@ reason=%@ %@ L=%@ placeholder=%@",
              boundary.rawValue,
              productID.uuidString,
              reason,
              fp.dimensionSummary,
              fp.meanLuminance.map { String(format: "%.4f", $0) } ?? "nil",
              fp.isPlaceholder ? "YES" : "no")
    }

    static func recordAssignment(image: UIImage, productID: UUID, reason: String, product: CapturedProduct? = nil) {
        recordBoundary(.productAssignment, image: image, productID: productID, reason: reason, product: product)
    }

    static func recordFinalRender(image: UIImage, productID: UUID, reason: String, product: CapturedProduct? = nil) {
        recordBoundary(.finalRender, image: image, productID: productID, reason: reason, product: product)
    }

    /// Begins a write whose `image` is the true pre-encode UIImage (`JPEG_INPUT`).
    @discardableResult
    static func beginWrite(image: UIImage, productID: UUID, reason: String, product: CapturedProduct? = nil) -> Int {
        let seq = nextSequence(for: productID)
        let input = makeFingerprint(
            image: image,
            productID: productID,
            boundary: Boundary.jpegInput.rawValue,
            reason: reason,
            product: product
        )
        let event = WriteEvent(
            sequence: seq,
            productID: productID,
            reason: reason,
            beganAt: Date(),
            endedAt: nil,
            inputFingerprint: input,
            decodeFingerprint: nil,
            diskFingerprint: nil,
            skippedAsPlaceholder: input.isPlaceholder,
            byteCount: nil,
            fileName: "proc_\(productID.uuidString).jpg"
        )
        lock.lock()
        openWrites[productID] = event
        var trace = traces[productID] ?? ProductWriteTrace()
        trace.boundaryChain.append(input)
        traces[productID] = trace
        lock.unlock()
        NSLog("[ProcessedWriteForensics] WRITE BEGIN #%@ id=%@ reason=%@ %@ L=%@ placeholder=%@",
              "\(seq)",
              productID.uuidString,
              reason,
              input.dimensionSummary,
              input.meanLuminance.map { String(format: "%.4f", $0) } ?? "nil",
              input.isPlaceholder ? "YES" : "no")
        return seq
    }

    /// Records decode (+ optional disk reload) after JPEG bytes already exist.
    /// Does **not** append another `JPEG_INPUT` — that stage must be the pre-encode UIImage only
    /// (typically recorded by `encodedProcessedData` / `beginWrite`).
    @discardableResult
    static func recordPostEncodeWrite(
        jpegData: Data,
        decoded: UIImage,
        productID: UUID,
        reason: String,
        diskReloaded: UIImage?,
        skippedAsPlaceholder: Bool = false
    ) -> Int {
        let seq = nextSequence(for: productID)
        let decodeFP = makeFingerprint(
            image: decoded,
            productID: productID,
            boundary: Boundary.jpegDecodeInMemory.rawValue,
            reason: reason,
            product: nil
        )
        let diskFP = diskReloaded.map {
            makeFingerprint(
                image: $0,
                productID: productID,
                boundary: Boundary.diskReload.rawValue,
                reason: reason,
                product: nil
            )
        }
        // Prefer the most recent true JPEG_INPUT already on the chain as this write's input.
        let priorInput: Fingerprint? = {
            lock.lock()
            defer { lock.unlock() }
            return traces[productID]?.boundaryChain.last(where: { $0.boundary == Boundary.jpegInput.rawValue })
        }()
        let event = WriteEvent(
            sequence: seq,
            productID: productID,
            reason: reason,
            beganAt: Date(),
            endedAt: Date(),
            inputFingerprint: priorInput,
            decodeFingerprint: decodeFP,
            diskFingerprint: diskFP,
            skippedAsPlaceholder: skippedAsPlaceholder,
            byteCount: jpegData.count,
            fileName: "proc_\(productID.uuidString).jpg"
        )
        lock.lock()
        var trace = traces[productID] ?? ProductWriteTrace()
        trace.boundaryChain.append(decodeFP)
        if let diskFP {
            trace.boundaryChain.append(diskFP)
        }
        if let idx = trace.events.firstIndex(where: { $0.sequence == seq }) {
            trace.events[idx] = event
        } else {
            trace.events.append(event)
        }
        traces[productID] = trace
        lock.unlock()
        NSLog("[ProcessedWriteForensics] POST-ENCODE WRITE #%@ id=%@ reason=%@ bytes=%d",
              "\(seq)", productID.uuidString, reason, jpegData.count)
        return seq
    }

    static func endWrite(
        productID: UUID,
        sequence: Int,
        jpegData: Data?,
        decoded: UIImage?,
        diskReloaded: UIImage?,
        skippedAsPlaceholder: Bool
    ) {
        if let decoded {
            recordBoundary(.jpegDecodeInMemory, image: decoded, productID: productID, reason: "write#\(sequence)")
        }
        if let diskReloaded {
            recordBoundary(.diskReload, image: diskReloaded, productID: productID, reason: "write#\(sequence)")
        }
        lock.lock()
        var event = openWrites.removeValue(forKey: productID) ?? WriteEvent(
            sequence: sequence,
            productID: productID,
            reason: "unknown",
            beganAt: Date(),
            skippedAsPlaceholder: skippedAsPlaceholder,
            fileName: "proc_\(productID.uuidString).jpg"
        )
        event.endedAt = Date()
        event.byteCount = jpegData?.count
        event.skippedAsPlaceholder = skippedAsPlaceholder
        if let decoded {
            event.decodeFingerprint = makeFingerprint(
                image: decoded,
                productID: productID,
                boundary: Boundary.jpegDecodeInMemory.rawValue,
                reason: "write#\(sequence)",
                product: nil
            )
        }
        if let diskReloaded {
            event.diskFingerprint = makeFingerprint(
                image: diskReloaded,
                productID: productID,
                boundary: Boundary.diskReload.rawValue,
                reason: "write#\(sequence)",
                product: nil
            )
        }
        var trace = traces[productID] ?? ProductWriteTrace()
        if let idx = trace.events.firstIndex(where: { $0.sequence == sequence }) {
            trace.events[idx] = event
        } else {
            trace.events.append(event)
        }
        traces[productID] = trace
        lock.unlock()
        NSLog("[ProcessedWriteForensics] WRITE END #%@ id=%@ bytes=%@ skippedPlaceholder=%@",
              "\(sequence)",
              productID.uuidString,
              jpegData.map { "\($0.count)" } ?? "nil",
              skippedAsPlaceholder ? "YES" : "no")
    }

    static func firstStrongBoundaryDivergence(productID: UUID) -> BoundaryDelta? {
        let deltas = boundaryDeltas(productID: productID)
        return deltas.first(where: \.isStrong)
    }

    private static func nextSequence(for productID: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let next = (writeCounters[productID] ?? 0) + 1
        writeCounters[productID] = next
        return next
    }

    static func boundaryDeltas(productID: UUID) -> [BoundaryDelta] {
        let chain = canonicalBoundaryChain(for: productID)
        guard chain.count >= 2 else { return [] }
        var out: [BoundaryDelta] = []
        for i in 1..<chain.count {
            let a = chain[i - 1]
            let b = chain[i]
            // Never compare two snapshots that share the same stage label.
            guard a.boundary != b.boundary, let d = compare(a, b) else { continue }
            out.append(d)
        }
        return out
    }

    /// Collapses accidental duplicate stage labels, keeping the earliest of each run.
    private static func canonicalBoundaryChain(for productID: UUID) -> [Fingerprint] {
        let raw = trace(for: productID).boundaryChain
        var out: [Fingerprint] = []
        for fp in raw {
            if out.last?.boundary == fp.boundary { continue }
            out.append(fp)
        }
        return out
    }

    static func summaryLines(productID: UUID) -> [String] {
        let t = trace(for: productID)
        var lines: [String] = []
        lines.append("Processed writes for \(productID.uuidString): \(t.events.count)")
        for e in t.events.sorted(by: { $0.sequence < $1.sequence }) {
            let L = e.inputFingerprint?.meanLuminance.map { String(format: "%.4f", $0) } ?? "?"
            let dim = e.inputFingerprint?.dimensionSummary ?? "?"
            lines.append(String(
                format: "  Write #%d %@ %@ L=%@ placeholder=%@ bytes=%@",
                e.sequence,
                e.reason,
                dim,
                L,
                e.skippedAsPlaceholder ? "YES" : "no",
                e.byteCount.map { "\($0)" } ?? "?"
            ))
        }
        let deltas = boundaryDeltas(productID: productID)
        for d in deltas {
            lines.append(String(
                format: "  %@ → %@ subjectΔL=%@ meanAbsRGB=%@%@ ",
                d.from,
                d.to,
                d.subjectDeltaL.map { String(format: "%+.4f", $0) } ?? "nil",
                d.meanAbsRGB.map { String(format: "%.4f", $0) } ?? "nil",
                d.isStrong ? " ★ STRONG" : ""
            ))
        }
        if let first = firstStrongBoundaryDivergence(productID: productID) {
            lines.append("FIRST STRONG BOUNDARY: \(first.from) → \(first.to)")
        } else if !deltas.isEmpty {
            lines.append("Boundary chain: no strong divergence (meanAbsRGB threshold 0.02)")
        }
        return lines
    }

    // MARK: - Fingerprint helpers

    static func makeFingerprint(
        image: UIImage,
        productID: UUID,
        boundary: String,
        reason: String,
        product: CapturedProduct?
    ) -> Fingerprint {
        let cg = image.cgImage
        let w = cg?.width ?? max(1, Int(round(image.size.width * image.scale)))
        let h = cg?.height ?? max(1, Int(round(image.size.height * image.scale)))
        let stats = quickStats(image)
        return Fingerprint(
            productID: productID,
            boundary: boundary,
            reason: reason,
            timestamp: Date(),
            width: w,
            height: h,
            colorSpace: cg?.colorSpace?.name.map { String(describing: $0) } ?? "nil",
            alphaInfo: cg.map { String(describing: $0.alphaInfo.rawValue) } ?? "nil",
            bitmapInfo: cg.map { String(format: "0x%X", $0.bitmapInfo.rawValue) } ?? "nil",
            orientation: image.imageOrientation.rawValue,
            scale: image.scale,
            sourceKind: cg != nil ? "CGImage" : (image.ciImage != nil ? "CIImage" : "unknown"),
            meanLuminance: stats?.meanL,
            meanRGB: stats.map { ($0.meanR, $0.meanG, $0.meanB) },
            subjectMeanLuminance: stats?.subjectL,
            isPlaceholder: image === CapturedProduct.diskBackedOriginalPlaceholder || (w <= 2 && h <= 2),
            backgroundRemoved: product?.backgroundRemoved,
            backgroundStyle: product?.backgroundStyle.rawValue,
            backgroundColorHex: product?.backgroundColor.hexString,
            photoFilter: product?.photoFilter.rawValue,
            autoEnhance: product?.adjustAutoEnhance,
            polishEnabled: product?.polishEnabled
        )
    }

    private static func compare(_ a: Fingerprint, _ b: Fingerprint) -> BoundaryDelta? {
        let subjectDelta: Double? = {
            guard let la = a.subjectMeanLuminance, let lb = b.subjectMeanLuminance else { return nil }
            return lb - la
        }()
        var meanAbs: Double?
        var rms: Double?
        var maxD: Double?
        if let ra = a.meanRGB, let rb = b.meanRGB {
            let dr = abs(ra.r - rb.r), dg = abs(ra.g - rb.g), db = abs(ra.b - rb.b)
            meanAbs = (dr + dg + db) / 3
            rms = sqrt((dr * dr + dg * dg + db * db) / 3)
            maxD = max(dr, dg, db)
        }
        return BoundaryDelta(
            from: a.boundary,
            to: b.boundary,
            subjectDeltaL: subjectDelta,
            meanAbsRGB: meanAbs,
            rmsRGB: rms,
            maxRGB: maxD
        )
    }

    private struct QuickStats {
        let meanL: Double
        let meanR: Double
        let meanG: Double
        let meanB: Double
        let subjectL: Double?
    }

    private static func quickStats(_ image: UIImage) -> QuickStats? {
        guard let cg = ImageProcessor.normalizedCGImage(image) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        // Downsample analysis for speed.
        let maxEdge = 96
        let scale = min(1, CGFloat(maxEdge) / CGFloat(max(w, h)))
        let aw = max(1, Int(CGFloat(w) * scale))
        let ah = max(1, Int(CGFloat(h) * scale))
        let bpr = aw * 4
        var pixels = [UInt8](repeating: 0, count: ah * bpr)
        guard let ctx = CGContext(
            data: &pixels,
            width: aw,
            height: ah,
            bitsPerComponent: 8,
            bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: aw, height: ah))

        var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumL = 0.0
        var sumSubL = 0.0
        var count = 0
        var subCount = 0
        for y in 0..<ah {
            for x in 0..<aw {
                let i = y * bpr + x * 4
                let r = Double(pixels[i]) / 255
                let g = Double(pixels[i + 1]) / 255
                let b = Double(pixels[i + 2]) / 255
                let a = Double(pixels[i + 3]) / 255
                guard a > 0.02 else { continue }
                let L = 0.2126 * r + 0.7152 * g + 0.0722 * b
                sumR += r; sumG += g; sumB += b; sumL += L
                count += 1
                // Non-near-white as crude subject proxy on studio plates.
                if L < 0.97 || abs(r - g) + abs(g - b) > 0.04 {
                    sumSubL += L
                    subCount += 1
                }
            }
        }
        guard count > 0 else { return nil }
        let n = Double(count)
        return QuickStats(
            meanL: sumL / n,
            meanR: sumR / n,
            meanG: sumG / n,
            meanB: sumB / n,
            subjectL: subCount > 0 ? sumSubL / Double(subCount) : nil
        )
    }
}
#endif
