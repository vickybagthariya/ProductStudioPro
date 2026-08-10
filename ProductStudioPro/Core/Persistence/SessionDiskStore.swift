import Foundation
import UIKit

/// Lightweight named queue folder (one product list per session).
struct NamedCatalogSession: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
}

/// Persists queue originals + metadata so a session survives app restarts.
/// Disk layout:
/// `{AppSupport}/ProductStudioSessions/index.json`
/// `{AppSupport}/ProductStudioSessions/{sessionUUID}/manifest.json` + `orig_*.png` / `proc_*.jpg`
enum SessionDiskStore {
    /// Optional UI hook for persistence failures (wired by `AppOperationalAlerts`).
    static var onOperationalFailure: ((String) -> Void)?

    private static let legacyFolderName = "ProductStudioSession"
    private static let sessionsRootName = "ProductStudioSessions"
    private static let indexName = "index.json"
    private static let manifestName = "manifest.json"

    private static func reportFailure(_ message: String) {
        onOperationalFailure?(message)
    }

    @discardableResult
    private static func writeDataAtomically(_ data: Data, to url: URL, failureMessage: String) -> Bool {
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            reportFailure(failureMessage)
            return false
        }
    }
    /// Serial queue so disk saves never interleave (avoids race that could delete a freshly-written file).
    private static let ioQueueKey = DispatchSpecificKey<UInt8>()
    private static let ioQueue: DispatchQueue = {
        let q = DispatchQueue(label: "com.productstudiopro.sessiondiskstore", qos: .utility)
        q.setSpecific(key: ioQueueKey, value: 1)
        return q
    }()
    /// Monotonic save token — stale queued saves must not overwrite manifest or delete files.
    private static var latestSaveGeneration: UInt64 = 0
    private static let generationLock = NSLock()
    private static let sessionLock = NSLock()
    private static var activeSessionID: UUID?

    private static var isOnIOQueue: Bool {
        DispatchQueue.getSpecific(key: ioQueueKey) != nil
    }

    /// Runs work on `ioQueue`, re-entering if already there (avoids deadlock with nested disk calls).
    @discardableResult
    private static func performOnIOQueue<T>(_ work: () -> T) -> T {
        if isOnIOQueue { return work() }
        return ioQueue.sync(execute: work)
    }

    private static var applicationSupport: URL {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport
        }
        return FileManager.default.temporaryDirectory
    }

    private static var sessionsRoot: URL {
        applicationSupport.appendingPathComponent(sessionsRootName, isDirectory: true)
    }

    private static var legacyBaseFolder: URL {
        applicationSupport.appendingPathComponent(legacyFolderName, isDirectory: true)
    }

    private static var indexURL: URL {
        sessionsRoot.appendingPathComponent(indexName)
    }

    /// Active session folder (images + manifest).
    private static var baseFolder: URL {
        sessionLock.lock()
        let id = activeSessionID
        sessionLock.unlock()
        let sid = id ?? UUID()
        return sessionsRoot.appendingPathComponent(sid.uuidString, isDirectory: true)
    }

    static func currentActiveSessionID() -> UUID? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return activeSessionID
    }

    static func setActiveSessionID(_ id: UUID) {
        sessionLock.lock()
        activeSessionID = id
        sessionLock.unlock()
        let folder = sessionsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let create = {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return
        }
        if isOnIOQueue {
            create()
        } else {
            // Keep main-thread callers free of launch-blocking mkdir I/O.
            ioQueue.async(execute: create)
        }
    }

    // MARK: - Sessions index

    private struct SessionsIndexFile: Codable {
        var activeSessionID: UUID
        var sessions: [NamedCatalogSession]
    }

    /// Ensures sessions root + index exist; migrates legacy single-queue folder once.
    /// Disk work always runs on `ioQueue` (never the main thread).
    @discardableResult
    static func bootstrapSessions() -> (activeID: UUID, sessions: [NamedCatalogSession]) {
        performOnIOQueue { bootstrapSessionsOnIOQueue() }
    }

    /// Bootstrap + load active queue in one background hop (used at app launch).
    static func restoreActiveSession() -> (activeID: UUID, sessions: [NamedCatalogSession], products: [CapturedProduct]?) {
        performOnIOQueue {
            let boot = bootstrapSessionsOnIOQueue()
            let products = loadQueueIfAvailableOnIOQueue()
            return (boot.activeID, boot.sessions, products)
        }
    }

    private static func bootstrapSessionsOnIOQueue() -> (activeID: UUID, sessions: [NamedCatalogSession]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: indexURL),
           let index = try? JSONDecoder().decode(SessionsIndexFile.self, from: data),
           !index.sessions.isEmpty {
            let active = index.sessions.contains(where: { $0.id == index.activeSessionID })
                ? index.activeSessionID
                : index.sessions[0].id
            setActiveSessionID(active)
            let renamed = index.sessions.map { session -> NamedCatalogSession in
                guard session.name == "Imported Queue" else { return session }
                var updated = session
                updated.name = "Default Queue"
                return updated
            }
            let didRename = renamed != index.sessions
            if active != index.activeSessionID || didRename {
                saveSessionsIndex(activeID: active, sessions: renamed)
            }
            return (active, renamed)
        }

        // Migrate legacy ProductStudioSession/ → ProductStudioSessions/{uuid}/
        let migratedID = UUID()
        let migratedName: String
        let legacyManifest = legacyBaseFolder.appendingPathComponent(manifestName)
        if fm.fileExists(atPath: legacyManifest.path) {
            let dest = sessionsRoot.appendingPathComponent(migratedID.uuidString, isDirectory: true)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) == false {
                try? fm.moveItem(at: legacyBaseFolder, to: dest)
            } else {
                // Destination exists — copy contents then remove legacy.
                if let items = try? fm.contentsOfDirectory(atPath: legacyBaseFolder.path) {
                    for name in items {
                        let src = legacyBaseFolder.appendingPathComponent(name)
                        let dst = dest.appendingPathComponent(name)
                        try? fm.removeItem(at: dst)
                        try? fm.moveItem(at: src, to: dst)
                    }
                }
                try? fm.removeItem(at: legacyBaseFolder)
            }
            migratedName = "Default Queue"
        } else {
            try? fm.createDirectory(
                at: sessionsRoot.appendingPathComponent(migratedID.uuidString, isDirectory: true),
                withIntermediateDirectories: true
            )
            migratedName = "Default Queue"
        }

        let now = Date()
        let session = NamedCatalogSession(id: migratedID, name: migratedName, createdAt: now, updatedAt: now)
        saveSessionsIndex(activeID: migratedID, sessions: [session])
        setActiveSessionID(migratedID)
        return (migratedID, [session])
    }

    static func loadSessionsIndex() -> (activeID: UUID, sessions: [NamedCatalogSession]) {
        bootstrapSessions()
    }

    static func saveSessionsIndex(activeID: UUID, sessions: [NamedCatalogSession]) {
        try? FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        let index = SessionsIndexFile(activeSessionID: activeID, sessions: sessions)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    static func deleteSessionFolder(id: UUID) {
        let folder = sessionsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    static func productCountOnDisk(sessionID: UUID) -> Int {
        let folder = sessionsRoot.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        let manifestURL = folder.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return 0 }
        return manifest.products.count
    }

    static func sessionFolderURL(sessionID: UUID) -> URL {
        sessionsRoot.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    /// Creates an empty session folder + manifest without changing the active session.
    static func ensureEmptySessionFolder(sessionID: UUID) {
        let folder = sessionFolderURL(sessionID: sessionID)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifestURL = folder.appendingPathComponent(manifestName)
        if FileManager.default.fileExists(atPath: manifestURL.path) { return }
        let manifest = Manifest(products: [])
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    private static func loadManifestRecords(sessionID: UUID) -> [PersistedProduct] {
        let manifestURL = sessionFolderURL(sessionID: sessionID).appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.products
    }

    private static func saveManifestRecords(_ records: [PersistedProduct], sessionID: UUID) {
        let folder = sessionFolderURL(sessionID: sessionID)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = Manifest(products: records)
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: folder.appendingPathComponent(manifestName), options: .atomic)
        }
    }

    private static func copyImageFileIfPresent(named fileName: String, from sourceFolder: URL, to destFolder: URL) {
        let src = sourceFolder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        let dst = destFolder.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: src, to: dst)
    }

    /// Copies product image files + appends manifest rows into `sessionID` (does not touch the active in-memory queue).
    static func appendProductsToSession(_ products: [CapturedProduct], sessionID: UUID) {
        guard !products.isEmpty else { return }
        let destFolder = sessionFolderURL(sessionID: sessionID)
        try? FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFolder = baseFolder

        var records = loadManifestRecords(sessionID: sessionID)
        let existingIDs = Set(records.map(\.id))

        for product in products {
            let record = persistedRecord(from: product)
            // Prefer copying existing on-disk files; fall back to encoding from memory.
            let pngName = "orig_\(product.id.uuidString).png"
            let jpgName = "proc_\(product.id.uuidString).jpg"
            let legacyOrig = "orig_\(product.id.uuidString).jpg"

            copyImageFileIfPresent(named: pngName, from: sourceFolder, to: destFolder)
            copyImageFileIfPresent(named: jpgName, from: sourceFolder, to: destFolder)
            copyImageFileIfPresent(named: legacyOrig, from: sourceFolder, to: destFolder)

            let destOrigPNG = destFolder.appendingPathComponent(pngName)
            if !FileManager.default.fileExists(atPath: destOrigPNG.path),
               let data = encodedOriginalData(for: product) {
                try? data.write(to: destOrigPNG, options: .atomic)
            }
            let destProc = destFolder.appendingPathComponent(jpgName)
            if !FileManager.default.fileExists(atPath: destProc.path),
               let data = encodedProcessedData(for: product) {
                try? data.write(to: destProc, options: .atomic)
            }

            if existingIDs.contains(record.id) {
                if let idx = records.firstIndex(where: { $0.id == record.id }) {
                    records[idx] = record
                }
            } else {
                records.insert(record, at: 0)
            }
        }

        saveManifestRecords(records, sessionID: sessionID)
    }

    /// On-disk lossless/legacy original for metadata reads (PNG or legacy JPEG).
    static func originalImageFileURL(for id: UUID) -> URL? {
        let png = imageURL(id, original: true)
        if FileManager.default.fileExists(atPath: png.path) { return png }
        let legacy = legacyOriginalJPEGURL(id)
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return nil
    }

    /// On-disk processed JPEG for this queue item, if persisted.
    static func processedImageFileURL(for id: UUID) -> URL? {
        let url = imageURL(id, original: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Loads one original from disk for bulk reprocess/reset — avoids holding duplicate bitmaps in memory.
    static func loadOriginalImage(id: UUID) -> UIImage? {
        guard let url = originalImageFileURL(for: id) else { return nil }
        return autoreleasepool { UIImage(contentsOfFile: url.path) }
    }

    /// Loads the processed display JPEG when it was evicted from RAM under memory pressure.
    static func loadProcessedImage(id: UUID) -> UIImage? {
        guard let url = processedImageFileURL(for: id) else { return nil }
        return autoreleasepool { UIImage(contentsOfFile: url.path) }
    }

    /// Writes a single processed JPEG during bulk ops so memory-heavy full-queue saves are not needed mid-batch.
    static func writeProcessedImage(_ image: UIImage, for id: UUID, reason: String = "writeProcessedImage") {
        // Never persist the RAM-eviction sentinel — that would destroy a good proc_*.jpg.
        guard image !== CapturedProduct.diskBackedOriginalPlaceholder else {
            #if DEBUG
            let seq = ProcessedWriteForensics.beginWrite(
                image: image,
                productID: id,
                reason: reason + " [BLOCKED_PLACEHOLDER]"
            )
            ProcessedWriteForensics.endWrite(
                productID: id,
                sequence: seq,
                jpegData: nil,
                decoded: nil,
                diskReloaded: nil,
                skippedAsPlaceholder: true
            )
            #endif
            return
        }

        let folder = baseFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = imageURL(id, original: false)
        #if DEBUG
        let seq = ProcessedWriteForensics.beginWrite(image: image, productID: id, reason: reason)
        #endif
        let data = autoreleasepool {
            image.jpegDataForOpaqueExport(compressionQuality: 0.92)
        }
        guard let data else {
            #if DEBUG
            ProcessedWriteForensics.endWrite(
                productID: id,
                sequence: seq,
                jpegData: nil,
                decoded: nil,
                diskReloaded: nil,
                skippedAsPlaceholder: false
            )
            #endif
            return
        }
        try? data.write(to: url, options: .atomic)
        #if DEBUG
        let decoded = UIImage(data: data)
        let reloaded = UIImage(contentsOfFile: url.path)
        ProcessedWriteForensics.endWrite(
            productID: id,
            sequence: seq,
            jpegData: data,
            decoded: decoded,
            diskReloaded: reloaded,
            skippedAsPlaceholder: false
        )
        #endif
    }

    private static func imageURL(_ id: UUID, original: Bool) -> URL {
        // Originals are stored losslessly (PNG) so repeated edits across relaunches never accumulate
        // generational JPEG artifacts. Processed/display bitmaps remain JPEG.
        baseFolder.appendingPathComponent(original ? "orig_\(id.uuidString).png" : "proc_\(id.uuidString).jpg")
    }

    /// Pre-existing sessions persisted originals as JPEG; used as a read fallback when migrating.
    private static func legacyOriginalJPEGURL(_ id: UUID) -> URL {
        baseFolder.appendingPathComponent("orig_\(id.uuidString).jpg")
    }

    struct PersistedProduct: Codable {
        var id: UUID
        var sequence: Int
        var upc: String
        var angleRaw: String
        var multiAngleOrdinal: Int?
        var capturedAt: Date
        var backgroundRemoved: Bool
        var duplicateCopyIndex: Int
        var polishEnabled: Bool
        var enhancementModeRaw: String
        var studioAIStrengthRaw: String
        /// Legacy single edge length; used when `canvasWidth` / `canvasHeight` are absent.
        var canvasSize: Int?
        var canvasWidth: Int?
        var canvasHeight: Int?
        var rotationDegrees: Double?
        var flipHorizontal: Bool?
        var flipVertical: Bool?
        var photoFilterRaw: String?
        var photoFilterIntensity: Double?
        var adjustAutoEnhance: Bool?
        var toneExposure: Double?
        var toneContrast: Double?
        var toneHighlights: Double?
        var toneShadows: Double?
        var toneVibrance: Double?
        var toneWarmth: Double?
        var cutoutFeather: Double?
        var cutoutBrushMaskData: Data?
        var studioShadowEnabled: Bool?
        var studioShadowOpacity: Double?
        var studioShadowBlur: Double?
        var preUpscaleCanvasWidth: Int?
        var preUpscaleCanvasHeight: Int?
        var preUpscaleEnhancementModeRaw: String?
        var preUpscaleStudioAIStrengthRaw: String?
        var fillRatio: Double
        var backgroundColorHex: String
        var secondaryBackgroundColorHex: String
        var backgroundStyleRaw: String
        var gradientColorHexes: [String]
        var backgroundFillData: Data?
        /// Legacy session fields (ignored on load).
        var depthLiftEnabled: Bool?
        var floorShadowStyleRaw: String?
        var upscaled: Bool?
        var isCompositeBundle: Bool?
        var compositeLayoutData: Data?
        var suppressBrandMark: Bool?
    }

    private struct Manifest: Codable {
        var products: [PersistedProduct]
    }

    static func persistedRecord(from product: CapturedProduct) -> PersistedProduct {
        PersistedProduct(
            id: product.id,
            sequence: product.sequence,
            upc: product.upc,
            angleRaw: product.angle.rawValue,
            multiAngleOrdinal: product.multiAngleOrdinal,
            capturedAt: product.capturedAt,
            backgroundRemoved: product.backgroundRemoved,
            duplicateCopyIndex: product.duplicateCopyIndex,
            polishEnabled: product.polishEnabled,
            enhancementModeRaw: product.enhancementMode.rawValue,
            studioAIStrengthRaw: product.studioAIStrength.rawValue,
            canvasSize: product.canvasSize,
            canvasWidth: product.canvasWidth,
            canvasHeight: product.canvasHeight,
            rotationDegrees: product.rotationDegrees,
            flipHorizontal: product.flipHorizontal,
            flipVertical: product.flipVertical,
            photoFilterRaw: product.photoFilter.rawValue,
            photoFilterIntensity: product.photoFilterIntensity,
            adjustAutoEnhance: product.adjustAutoEnhance,
            toneExposure: product.toneAdjustments.exposure,
            toneContrast: product.toneAdjustments.contrast,
            toneHighlights: product.toneAdjustments.highlights,
            toneShadows: product.toneAdjustments.shadows,
            toneVibrance: product.toneAdjustments.vibrance,
            toneWarmth: product.toneAdjustments.warmth,
            cutoutFeather: product.cutoutFeather,
            cutoutBrushMaskData: product.cutoutBrushMaskData,
            studioShadowEnabled: product.studioShadow.isEnabled,
            studioShadowOpacity: product.studioShadow.opacity,
            studioShadowBlur: product.studioShadow.blur,
            preUpscaleCanvasWidth: product.preUpscaleCanvasWidth,
            preUpscaleCanvasHeight: product.preUpscaleCanvasHeight,
            preUpscaleEnhancementModeRaw: product.preUpscaleEnhancementMode?.rawValue,
            preUpscaleStudioAIStrengthRaw: product.preUpscaleStudioAIStrength?.rawValue,
            fillRatio: product.fillRatio,
            backgroundColorHex: product.backgroundColor.hexString,
            secondaryBackgroundColorHex: product.secondaryBackgroundColor.hexString,
            backgroundStyleRaw: product.backgroundStyle.rawValue,
            gradientColorHexes: product.gradientColorHexes,
            backgroundFillData: product.backgroundFillData,
            upscaled: product.upscaled,
            isCompositeBundle: product.isCompositeBundle,
            compositeLayoutData: product.compositeLayoutData,
            suppressBrandMark: product.suppressBrandMark
        )
    }

    /// Lossless/legacy original bytes for disk write — reads existing file when RAM was evicted.
    private static func encodedOriginalData(for product: CapturedProduct) -> Data? {
        autoreleasepool {
            if product.isOriginalEvicted {
                guard let url = originalImageFileURL(for: product.id) else { return nil }
                return try? Data(contentsOf: url)
            }
            return product.uncompressedOriginalImage.pngData()
                ?? product.uncompressedOriginalImage.jpegDataForOpaqueExport(compressionQuality: 1.0)
        }
    }

    /// Processed JPEG bytes for disk write — reads existing file when RAM was evicted
    /// (mirrors `encodedOriginalData`). Re-encoding the 1×1 placeholder would overwrite a good `proc_*.jpg`.
    private static func encodedProcessedData(for product: CapturedProduct) -> Data? {
        autoreleasepool {
            if product.isProcessedEvicted {
                #if DEBUG
                NSLog(
                    "[ProcessedWriteForensics] encodedProcessedData REUSE_DISK id=%@ (processed evicted — skip re-encode)",
                    product.id.uuidString
                )
                #endif
                guard let url = processedImageFileURL(for: product.id) else { return nil }
                return try? Data(contentsOf: url)
            }
            if product.image === CapturedProduct.diskBackedOriginalPlaceholder {
                return nil
            }
            #if DEBUG
            ProcessedWriteForensics.recordBoundary(
                .jpegInput,
                image: product.image,
                productID: product.id,
                reason: "encodedProcessedData",
                product: product
            )
            #endif
            return product.image.jpegDataForOpaqueExport(compressionQuality: 0.92)
        }
    }

    private static func writeSnapshot(
        _ products: [CapturedProduct],
        generation: UInt64,
        pruneStaleFiles: Bool,
        waitUntilDone: Bool
    ) {
        let work = {
            autoreleasepool {
                let snapshot = products.map { product -> (PersistedProduct, Data?, Data?) in
                    let record = persistedRecord(from: product)
                    let origData = encodedOriginalData(for: product)
                    let procData = encodedProcessedData(for: product)
                    return (record, origData, procData)
                }

                let fm = FileManager.default
                let folder = baseFolder
                do {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                } catch {
                    reportFailure("Couldn’t create the session folder on disk.")
                    return
                }

                var records: [PersistedProduct] = []
                var keepFilenames: Set<String> = [manifestName]
                var wroteAnyFailure = false
                for (record, origData, procData) in snapshot {
                    let origURL = imageURL(record.id, original: true)
                    let procURL = imageURL(record.id, original: false)
                    keepFilenames.insert(origURL.lastPathComponent)
                    keepFilenames.insert(procURL.lastPathComponent)
                    if let d = origData {
                        if !writeDataAtomically(d, to: origURL, failureMessage: "Couldn’t save an original photo to disk.") {
                            wroteAnyFailure = true
                        }
                    }
                    if let d = procData {
                        if !writeDataAtomically(d, to: procURL, failureMessage: "Couldn’t save a processed photo to disk.") {
                            wroteAnyFailure = true
                        }
                        #if DEBUG
                        Self.debugTraceEncodedProcWrite(data: d, id: record.id, reason: "saveQueue/writeSnapshot", diskURL: procURL)
                        #endif
                    }
                    records.append(record)
                }
                _ = wroteAnyFailure

                generationLock.lock()
                let isLatest = generation == latestSaveGeneration
                generationLock.unlock()
                guard isLatest else { return }

                let manifest = Manifest(products: records)
                if let data = try? JSONEncoder().encode(manifest) {
                    _ = writeDataAtomically(
                        data,
                        to: folder.appendingPathComponent(manifestName),
                        failureMessage: "Couldn’t save the session manifest. Recent edits may be lost if the app quits."
                    )
                } else {
                    reportFailure("Couldn’t encode the session manifest.")
                }

                guard pruneStaleFiles else { return }
                if let existing = try? fm.contentsOfDirectory(atPath: folder.path) {
                    for name in existing where !keepFilenames.contains(name) {
                        try? fm.removeItem(at: folder.appendingPathComponent(name))
                    }
                }
            }
        }

        if waitUntilDone {
            ioQueue.sync(execute: work)
        } else {
            ioQueue.async(execute: work)
        }
    }

    /// After bulk reprocess/reset — updates manifest + processed JPEGs only (skips re-encoding PNG originals).
    @discardableResult
    static func saveManifestAndProcessedImages(_ products: [CapturedProduct], generation: UInt64? = nil, pruneStaleFiles: Bool = false) -> UInt64 {
        let gen: UInt64
        if let generation {
            gen = generation
        } else {
            generationLock.lock()
            latestSaveGeneration &+= 1
            gen = latestSaveGeneration
            generationLock.unlock()
        }

        let snapshot = products.map { product -> (PersistedProduct, Data?) in
            let record = persistedRecord(from: product)
            // Use eviction-safe encoder (must not re-encode the RAM placeholder).
            let procData = encodedProcessedData(for: product)
            return (record, procData)
        }

        ioQueue.async {
            let fm = FileManager.default
            let folder = baseFolder
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                reportFailure("Couldn’t create the session folder on disk.")
                return
            }

            var records: [PersistedProduct] = []
            var keepFilenames: Set<String> = [manifestName]
            for (record, procData) in snapshot {
                let procURL = imageURL(record.id, original: false)
                keepFilenames.insert(imageURL(record.id, original: true).lastPathComponent)
                keepFilenames.insert(procURL.lastPathComponent)
                if let d = procData {
                    _ = writeDataAtomically(d, to: procURL, failureMessage: "Couldn’t save a processed photo to disk.")
                    #if DEBUG
                    Self.debugTraceEncodedProcWrite(data: d, id: record.id, reason: "saveManifestAndProcessedImages", diskURL: procURL)
                    #endif
                }
                records.append(record)
            }

            generationLock.lock()
            let isLatest = gen == latestSaveGeneration
            generationLock.unlock()
            guard isLatest else { return }

            let manifest = Manifest(products: records)
            if let data = try? JSONEncoder().encode(manifest) {
                _ = writeDataAtomically(
                    data,
                    to: folder.appendingPathComponent(manifestName),
                    failureMessage: "Couldn’t save the session manifest. Recent edits may be lost if the app quits."
                )
            } else {
                reportFailure("Couldn’t encode the session manifest.")
            }

            guard pruneStaleFiles else { return }
            if let existing = try? fm.contentsOfDirectory(atPath: folder.path) {
                for name in existing where !keepFilenames.contains(name) {
                    try? fm.removeItem(at: folder.appendingPathComponent(name))
                }
            }
        }
        return gen
    }

    /// Returns the generation token for this save. Only the latest generation may commit manifest + stale cleanup.
    @discardableResult
    static func saveQueue(_ products: [CapturedProduct], generation: UInt64? = nil, pruneStaleFiles: Bool = false) -> UInt64 {
        let gen: UInt64
        generationLock.lock()
        if let generation {
            gen = generation
            latestSaveGeneration = max(latestSaveGeneration, generation)
        } else {
            latestSaveGeneration &+= 1
            gen = latestSaveGeneration
        }
        generationLock.unlock()

        writeSnapshot(products, generation: gen, pruneStaleFiles: pruneStaleFiles, waitUntilDone: false)
        return gen
    }

    /// Writes one new queue item's images + manifest immediately (no stale-file cleanup).
    static func appendProductAndManifest(
        _ product: CapturedProduct,
        allProducts: [CapturedProduct],
        generation: UInt64,
        onComplete: (() -> Void)? = nil
    ) {
        generationLock.lock()
        latestSaveGeneration = max(latestSaveGeneration, generation)
        generationLock.unlock()

        let allRecords = allProducts.map { persistedRecord(from: $0) }

        ioQueue.async {
            autoreleasepool {
                let record = persistedRecord(from: product)
                let origData = encodedOriginalData(for: product)
                let procData = encodedProcessedData(for: product)

                let fm = FileManager.default
                let folder = baseFolder
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

                let origURL = imageURL(record.id, original: true)
                let procURL = imageURL(record.id, original: false)
                if let d = origData {
                    try? d.write(to: origURL, options: .atomic)
                }
                if let d = procData {
                    try? d.write(to: procURL, options: .atomic)
                    #if DEBUG
                    Self.debugTraceEncodedProcWrite(data: d, id: record.id, reason: "appendProductAndManifest", diskURL: procURL)
                    #endif
                }

                generationLock.lock()
                let isLatest = generation == latestSaveGeneration
                generationLock.unlock()
                if isLatest {
                    let manifest = Manifest(products: allRecords)
                    if let data = try? JSONEncoder().encode(manifest) {
                        try? data.write(to: folder.appendingPathComponent(manifestName), options: .atomic)
                    }
                }
            }
            if let onComplete {
                DispatchQueue.main.async(execute: onComplete)
            }
        }
    }

    #if DEBUG
    /// Fingerprints post-encode decode (+ disk reload). `JPEG_INPUT` was already recorded
    /// in `encodedProcessedData` for the pre-encode UIImage — do not relabel the decode as input.
    private static func debugTraceEncodedProcWrite(data: Data, id: UUID, reason: String, diskURL: URL) {
        guard let decoded = UIImage(data: data) else { return }
        let reloaded = UIImage(contentsOfFile: diskURL.path)
        let placeholder = decoded === CapturedProduct.diskBackedOriginalPlaceholder
            || (decoded.size.width <= 2 && decoded.size.height <= 2)
        _ = ProcessedWriteForensics.recordPostEncodeWrite(
            jpegData: data,
            decoded: decoded,
            productID: id,
            reason: reason,
            diskReloaded: reloaded,
            skippedAsPlaceholder: placeholder
        )
    }
    #endif

    /// Blocks until the queue snapshot is fully written — used before backgrounding or termination.
    static func saveQueueAndWait(_ products: [CapturedProduct], generation: UInt64, pruneStaleFiles: Bool = true) {
        generationLock.lock()
        latestSaveGeneration = max(latestSaveGeneration, generation)
        generationLock.unlock()

        writeSnapshot(products, generation: generation, pruneStaleFiles: pruneStaleFiles, waitUntilDone: true)
    }

    static func loadQueueIfAvailable() -> [CapturedProduct]? {
        performOnIOQueue { loadQueueIfAvailableOnIOQueue() }
    }

    private static func loadQueueIfAvailableOnIOQueue() -> [CapturedProduct]? {
        let folder = baseFolder
        let manifestURL = folder.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              !manifest.products.isEmpty else { return nil }
        let placeholder = CapturedProduct.diskBackedOriginalPlaceholder
        var out: [CapturedProduct] = []
        for r in manifest.products {
            guard originalImageFileURL(for: r.id) != nil else { continue }
            let procURL = imageURL(r.id, original: false)
            let processed: UIImage
            if let procData = try? Data(contentsOf: procURL), let img = UIImage(data: procData) {
                processed = img
            } else if let legacy = loadOriginalImage(id: r.id) {
                processed = legacy
            } else {
                continue
            }
            let angle = ProductAngle(rawValue: r.angleRaw) ?? .none
            let mode = PhotoEnhancementMode(rawValue: r.enhancementModeRaw) ?? .standardClean
            let strength = StudioAIStrength(rawValue: r.studioAIStrengthRaw) ?? CatalogProcessingBaseline.strength
            let bg = UIColor(hexString: r.backgroundColorHex) ?? .white
            let bg2 = UIColor(hexString: r.secondaryBackgroundColorHex) ?? UIColor(white: 0.94, alpha: 1.0)
            let style = BackgroundCanvasStyle.fromStored(r.backgroundStyleRaw)
            let legacy = r.canvasSize ?? 1200
            let cw = r.canvasWidth ?? legacy
            let ch = r.canvasHeight ?? legacy
            let rot = r.rotationDegrees ?? 0
            let flipH = r.flipHorizontal ?? false
            let flipV = r.flipVertical ?? false
            let filt = ExportPhotoFilter.resolved(from: r.photoFilterRaw)
            let filtI = r.photoFilterIntensity ?? 1.0
            let autoAdj = r.adjustAutoEnhance ?? false
            let tones = ManualToneAdjustments(
                exposure: r.toneExposure ?? 0,
                contrast: r.toneContrast ?? 0,
                highlights: r.toneHighlights ?? 0,
                shadows: r.toneShadows ?? 0,
                vibrance: r.toneVibrance ?? 0,
                warmth: r.toneWarmth ?? 0
            )
            let feather = r.cutoutFeather ?? 0.35
            let shadow = SoftSyntheticShadowSettings(
                isEnabled: r.studioShadowEnabled ?? true,
                opacity: r.studioShadowOpacity ?? SoftSyntheticShadowSettings.studioDefault.opacity,
                blur: r.studioShadowBlur ?? SoftSyntheticShadowSettings.studioDefault.blur
            ).clamped()
            let preMode = r.preUpscaleEnhancementModeRaw.flatMap { PhotoEnhancementMode(rawValue: $0) }
            let preStr = r.preUpscaleStudioAIStrengthRaw.flatMap { StudioAIStrength(rawValue: $0) }
            out.append(
                CapturedProduct(
                    id: r.id,
                    sequence: r.sequence,
                    upc: r.upc,
                    angle: angle,
                    multiAngleOrdinal: r.multiAngleOrdinal ?? 0,
                    image: processed,
                    originalImage: placeholder,
                    uncompressedOriginalImage: placeholder,
                    capturedAt: r.capturedAt,
                    backgroundRemoved: r.backgroundRemoved,
                    duplicateCopyIndex: r.duplicateCopyIndex,
                    polishEnabled: r.polishEnabled,
                    enhancementMode: mode,
                    studioAIStrength: strength,
                    canvasWidth: cw,
                    canvasHeight: ch,
                    rotationDegrees: rot,
                    flipHorizontal: flipH,
                    flipVertical: flipV,
                    photoFilter: filt,
                    photoFilterIntensity: filtI,
                    adjustAutoEnhance: autoAdj,
                    toneAdjustments: tones,
                    cutoutFeather: feather,
                    cutoutBrushMaskData: r.cutoutBrushMaskData,
                    studioShadow: shadow,
                    preUpscaleCanvasWidth: r.preUpscaleCanvasWidth,
                    preUpscaleCanvasHeight: r.preUpscaleCanvasHeight,
                    preUpscaleEnhancementMode: preMode,
                    preUpscaleStudioAIStrength: preStr,
                    fillRatio: r.fillRatio,
                    backgroundColor: bg,
                    secondaryBackgroundColor: bg2,
                    backgroundStyle: style,
                    gradientColorHexes: r.gradientColorHexes.isEmpty ? ["#FFFFFF"] : r.gradientColorHexes,
                    backgroundFillData: r.backgroundFillData,
                    upscaled: r.upscaled ?? false,
                    isCompositeBundle: r.isCompositeBundle ?? false,
                    compositeLayoutData: r.compositeLayoutData,
                    suppressBrandMark: r.suppressBrandMark ?? false
                )
            )
        }
        return out.isEmpty ? nil : out
    }

    static func clearPersistedSession() {
        try? FileManager.default.removeItem(at: baseFolder)
    }
}

enum ZipArchiveWriter {
    static func makeZip(urls: [URL], zipDestination: URL) -> Bool {
        let entries: [(path: String, data: Data)] = urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return (url.lastPathComponent, data)
        }
        return makeZip(entries: entries, zipDestination: zipDestination)
    }

    static func makeZip(entries: [(path: String, data: Data)], zipDestination: URL) -> Bool {
        guard !entries.isEmpty else { return false }
        guard let zipData = buildStoredZip(entries: entries) else { return false }
        try? FileManager.default.createDirectory(at: zipDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try zipData.write(to: zipDestination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func buildStoredZip(entries: [(path: String, data: Data)]) -> Data? {
        var data = Data()
        var central = Data()
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = 0

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let nameLen = UInt16(nameData.count)
            let uncompressed = UInt32(entry.data.count)
            let crc = crc32(entry.data)
            let localStart = UInt32(data.count)

            var local = Data()
            local.appendUInt32(0x04034b50)
            local.appendUInt16(20)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt16(dosTime)
            local.appendUInt16(dosDate)
            local.appendUInt32(crc)
            local.appendUInt32(uncompressed)
            local.appendUInt32(uncompressed)
            local.appendUInt16(nameLen)
            local.appendUInt16(0)
            local.append(nameData)
            local.append(entry.data)
            data.append(local)

            central.appendUInt32(0x02014b50)
            central.appendUInt16(0x0314)
            central.appendUInt16(20)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(dosTime)
            central.appendUInt16(dosDate)
            central.appendUInt32(crc)
            central.appendUInt32(uncompressed)
            central.appendUInt32(uncompressed)
            central.appendUInt16(nameLen)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(localStart)
            central.append(nameData)
        }

        let centralSize = UInt32(central.count)
        let centralOffset = UInt32(data.count)
        data.append(central)
        data.appendUInt32(0x06054b50)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(UInt16(entries.count))
        data.appendUInt16(UInt16(entries.count))
        data.appendUInt32(centralSize)
        data.appendUInt32(centralOffset)
        data.appendUInt16(0)
        return data
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ v: UInt16) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendUInt32(_ v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
