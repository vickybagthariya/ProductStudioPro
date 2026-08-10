import XCTest
@testable import ProductStudioPro

#if DEBUG
final class ProcessedWriteForensicsTests: XCTestCase {
    /// Proves the eviction overwrite bug: after processed RAM eviction, a queue save
    /// must NOT replace a good proc_*.jpg with the 1×1 placeholder encode.
    func testSaveQueueDoesNotOverwriteProcWithEvictionPlaceholder() throws {
        let id = UUID()
        let bright = makeSolidImage(color: UIColor(white: 0.92, alpha: 1), size: CGSize(width: 64, height: 64))
        let original = makeSolidImage(color: .gray, size: CGSize(width: 64, height: 64))

        SessionDiskStore.writeProcessedImage(bright, for: id, reason: "test.initialGoodWrite")
        guard let beforeURL = SessionDiskStore.processedImageFileURL(for: id),
              let beforeData = try? Data(contentsOf: beforeURL),
              let beforeImg = UIImage(data: beforeData) else {
            return XCTFail("Expected initial proc write")
        }
        let beforeL = meanLuminance(beforeImg)
        XCTAssertGreaterThan(beforeL, 0.8, "Seed image should be bright")

        let evicted = CapturedProduct(
            id: id,
            sequence: 1,
            upc: "TEST-EVICT",
            angle: .none,
            image: CapturedProduct.diskBackedOriginalPlaceholder,
            originalImage: original,
            backgroundRemoved: true
        )
        XCTAssertTrue(evicted.isProcessedEvicted)

        // Full snapshot save — previously re-encoded the placeholder and destroyed proc_*.jpg.
        SessionDiskStore.saveQueueAndWait([evicted], generation: UInt64(Date().timeIntervalSince1970), pruneStaleFiles: false)

        guard let afterURL = SessionDiskStore.processedImageFileURL(for: id),
              let afterData = try? Data(contentsOf: afterURL),
              let afterImg = UIImage(data: afterData) else {
            return XCTFail("proc file missing after save")
        }
        let afterL = meanLuminance(afterImg)
        XCTAssertEqual(afterImg.size.width, beforeImg.size.width, accuracy: 1)
        XCTAssertEqual(afterImg.size.height, beforeImg.size.height, accuracy: 1)
        XCTAssertGreaterThan(afterL, 0.8, "Proc must remain bright — not overwritten by placeholder")
        XCTAssertLessThan(abs(afterL - beforeL), 0.05)
    }

    func testEncodedPathDoesNotDuplicateJPEGInputLabel() {
        let id = UUID()
        ProcessedWriteForensics.reset(productID: id)
        let bright = makeSolidImage(color: UIColor(white: 0.9, alpha: 1), size: CGSize(width: 48, height: 48))

        ProcessedWriteForensics.recordFinalRender(image: bright, productID: id, reason: "test")
        ProcessedWriteForensics.recordAssignment(image: bright, productID: id, reason: "test")
        ProcessedWriteForensics.recordBoundary(.jpegInput, image: bright, productID: id, reason: "encodedProcessedData")

        guard let data = bright.jpegDataForOpaqueExport(compressionQuality: 0.92),
              let decoded = UIImage(data: data) else {
            return XCTFail("jpeg encode failed")
        }
        // Previously this incorrectly called beginWrite(decoded) → second JPEG_INPUT.
        _ = ProcessedWriteForensics.recordPostEncodeWrite(
            jpegData: data,
            decoded: decoded,
            productID: id,
            reason: "appendProductAndManifest",
            diskReloaded: decoded
        )

        let labels = ProcessedWriteForensics.trace(for: id).boundaryChain.map(\.boundary)
        XCTAssertEqual(labels.filter { $0 == "JPEG_INPUT" }.count, 1, "JPEG_INPUT must appear once: \(labels)")
        XCTAssertTrue(labels.contains("JPEG_DECODE_IN_MEMORY"))
        XCTAssertTrue(labels.contains("DISK_RELOAD"))
        XCTAssertFalse(
            ProcessedWriteForensics.boundaryDeltas(productID: id).contains { $0.from == $0.to },
            "No same-label adjacent comparisons"
        )
        // Healthy encode: meanAbsRGB between input and decode should be under strong threshold.
        let strong = ProcessedWriteForensics.firstStrongBoundaryDivergence(productID: id)
        XCTAssertNil(strong, "Solid near-white plate should not flag strong write boundary; got \(String(describing: strong))")
    }

    func testWriteProcessedImageBlocksPlaceholder() {
        let id = UUID()
        let bright = makeSolidImage(color: .white, size: CGSize(width: 32, height: 32))
        SessionDiskStore.writeProcessedImage(bright, for: id, reason: "test.seed")
        SessionDiskStore.writeProcessedImage(
            CapturedProduct.diskBackedOriginalPlaceholder,
            for: id,
            reason: "test.blockedPlaceholder"
        )
        guard let url = SessionDiskStore.processedImageFileURL(for: id),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else {
            return XCTFail("missing proc")
        }
        XCTAssertGreaterThan(meanLuminance(img), 0.9)
        XCTAssertGreaterThan(img.size.width, 2)
    }

    private func makeSolidImage(color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func meanLuminance(_ image: UIImage) -> Double {
        guard let cg = ImageProcessor.normalizedCGImage(image) else { return 0 }
        let w = cg.width, h = cg.height
        let bpr = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bpr)
        guard let ctx = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        let n = w * h
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255
            let g = Double(pixels[i + 1]) / 255
            let b = Double(pixels[i + 2]) / 255
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return sum / Double(n)
    }
}
#endif
