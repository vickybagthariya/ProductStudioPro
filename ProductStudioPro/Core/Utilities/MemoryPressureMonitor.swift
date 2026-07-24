import Foundation
import UIKit
import Darwin

/// Device-class memory budget and live pressure level for catalog pipelines.
/// Goal: keep a healthy OS headroom — never aim for “max available” RAM.
enum MemoryPressureLevel: Int, Comparable, CaseIterable {
    case normal = 0
    case caution = 1
    case critical = 2

    static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .caution: return "Elevated"
        case .critical: return "High"
        }
    }
}

enum DeviceMemoryTier: String {
    case compact
    case standard
    case pro

    /// Soft working-set budget for resident processed bitmaps + caches (bytes).
    var residentWorkingBudgetBytes: UInt64 {
        switch self {
        case .compact: return 180 * 1024 * 1024
        case .standard: return 320 * 1024 * 1024
        case .pro: return 480 * 1024 * 1024
        }
    }

    /// Free memory required before starting one heavy Vision / Studio AI pass.
    var heavyPassHeadroomBytes: UInt64 {
        switch self {
        case .compact: return 120 * 1024 * 1024
        case .standard: return 160 * 1024 * 1024
        case .pro: return 200 * 1024 * 1024
        }
    }

    var maxImportConcurrency: Int {
        switch self {
        case .compact: return 1
        case .standard: return 2
        case .pro: return 3
        }
    }

    /// Max processed display bitmaps to keep in RAM under pressure (newest first).
    var keepProcessedInMemoryCount: Int {
        switch self {
        case .compact: return 8
        case .standard: return 14
        case .pro: return 20
        }
    }

    static var current: DeviceMemoryTier {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        if gb < 3.5 { return .compact }
        if gb < 5.5 { return .standard }
        return .pro
    }
}

/// Snapshot used by capacity gates and the guidance sheet.
struct MemoryPressureSnapshot: Equatable {
    var level: MemoryPressureLevel
    var tier: DeviceMemoryTier
    var availableBytes: UInt64
    var physicalBytes: UInt64
    var estimatedResidentBytes: UInt64
    var queueCount: Int
    var softQueueCap: Int
    var thermalState: ProcessInfo.ThermalState
    var isLowPowerMode: Bool

    var availableMegabytes: Int { Int(availableBytes / (1024 * 1024)) }

    var recommendedActions: [String] {
        var actions: [String] = []
        if queueCount > softQueueCap / 2 {
            actions.append("Export finished photos, then clear or start a new session folder.")
            actions.append("Move older items into another session to keep this queue lighter.")
        }
        actions.append("Close Preview / Markup when you are done editing.")
        if level >= .caution {
            actions.append("Pause bulk Enhance / Reprocess until memory recovers.")
            actions.append("Import or capture fewer photos at a time.")
        }
        if level == .critical {
            actions.append("Remove unused queue photos before adding more.")
        }
        if thermalState == .serious || thermalState == .critical {
            actions.append("Let the phone cool — heavy polish is limited while hot.")
        }
        if isLowPowerMode {
            actions.append("Turn off Low Power Mode for smoother Studio AI.")
        }
        return Array(actions.prefix(5))
    }
}

enum CatalogCapacityDecision: Equatable {
    case allowed
    /// Near budget — allow this add, but surface tips.
    case allowedWithGuidance(MemoryPressureSnapshot)
    case softCapExceeded(limit: Int, wouldBe: Int)
    case memoryBlocked(MemoryPressureSnapshot)

    var isBlocked: Bool {
        switch self {
        case .softCapExceeded, .memoryBlocked: return true
        case .allowed, .allowedWithGuidance: return false
        }
    }

    var userMessage: String {
        switch self {
        case .allowed:
            return ""
        case .allowedWithGuidance:
            return "Session memory is elevated. Follow the tips to keep the app smooth."
        case .softCapExceeded(let limit, _):
            return "Queue soft limit is \(limit) photos. Remove some items, export, or use another session folder."
        case .memoryBlocked(let snap):
            return "Not enough free memory to add more photos safely (\(snap.availableMegabytes) MB free). Export, remove items, or start a new session — then try again."
        }
    }
}

/// Central memory budget helper. Query before capture/import/AI; purge on pressure.
@MainActor
final class MemoryPressureMonitor: ObservableObject {
    static let shared = MemoryPressureMonitor()

    @Published private(set) var latest: MemoryPressureSnapshot

    /// UI reserve so the OS / SwiftUI stay responsive.
    private let uiReserveBytes: UInt64 = 64 * 1024 * 1024
    private var thermalObserver: NSObjectProtocol?
    private var memoryObserver: NSObjectProtocol?

    private init() {
        let tier = DeviceMemoryTier.current
        latest = MemoryPressureSnapshot(
            level: .normal,
            tier: tier,
            availableBytes: Self.readAvailableBytes(),
            physicalBytes: ProcessInfo.processInfo.physicalMemory,
            estimatedResidentBytes: 0,
            queueCount: 0,
            softQueueCap: CaptureSessionStore.CatalogSessionLimits.softQueueCap,
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh(queueCount: self?.latest.queueCount ?? 0, estimatedResidentBytes: self?.latest.estimatedResidentBytes ?? 0) }
        }
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh(
                    queueCount: self.latest.queueCount,
                    estimatedResidentBytes: self.latest.estimatedResidentBytes,
                    forceCritical: true
                )
            }
        }
    }

    deinit {
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
    }

    static func readAvailableBytes() -> UInt64 {
        UInt64(os_proc_available_memory())
    }

    /// Rough RGBA footprint for a bitmap (conservative).
    static func estimatedBitmapBytes(for image: UIImage?) -> UInt64 {
        guard let cg = image?.cgImage else { return 0 }
        let bytes = UInt64(cg.bytesPerRow) * UInt64(cg.height)
        return max(bytes, 1)
    }

    static func estimateQueueResidentBytes(products: [CapturedProduct]) -> UInt64 {
        var total: UInt64 = 0
        for product in products {
            if !product.isProcessedEvicted {
                total += estimatedBitmapBytes(for: product.image)
            }
            if !product.isOriginalEvicted {
                total += estimatedBitmapBytes(for: product.uncompressedOriginalImage)
            }
        }
        return total
    }

    @discardableResult
    func refresh(
        queueCount: Int,
        estimatedResidentBytes: UInt64,
        forceCritical: Bool = false
    ) -> MemoryPressureSnapshot {
        let tier = DeviceMemoryTier.current
        let available = Self.readAvailableBytes()
        let thermal = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let softCap = CaptureSessionStore.CatalogSessionLimits.softQueueCap
        let budget = tier.residentWorkingBudgetBytes

        var level: MemoryPressureLevel = .normal
        if forceCritical
            || available < tier.heavyPassHeadroomBytes
            || estimatedResidentBytes > (budget * 9) / 10
            || thermal == .critical {
            level = .critical
        } else if available < tier.heavyPassHeadroomBytes + uiReserveBytes
            || estimatedResidentBytes > (budget * 7) / 10
            || queueCount >= (softCap * 3) / 4
            || thermal == .serious
            || lowPower {
            level = .caution
        }

        let snap = MemoryPressureSnapshot(
            level: level,
            tier: tier,
            availableBytes: available,
            physicalBytes: ProcessInfo.processInfo.physicalMemory,
            estimatedResidentBytes: estimatedResidentBytes,
            queueCount: queueCount,
            softQueueCap: softCap,
            thermalState: thermal,
            isLowPowerMode: lowPower
        )
        latest = snap
        return snap
    }

    var recommendedImportConcurrency: Int {
        switch latest.level {
        case .normal: return latest.tier.maxImportConcurrency
        case .caution: return 1
        case .critical: return 1
        }
    }

    /// Long-edge cap for Vision / Studio AI under pressure (keeps peak tensors smaller).
    var recommendedProcessingLongEdge: CGFloat {
        switch latest.level {
        case .normal: return CaptureQualityLimits.unifiedProcessingMaxLongEdge
        case .caution: return min(CaptureQualityLimits.unifiedProcessingMaxLongEdge, 3072)
        case .critical: return min(CaptureQualityLimits.unifiedProcessingMaxLongEdge, 2048)
        }
    }

    func allowsSubjectLift() -> Bool {
        guard latest.level < .critical else { return false }
        if latest.isLowPowerMode { return false }
        if latest.thermalState == .serious || latest.thermalState == .critical { return false }
        return true
    }

    func canStartHeavyPass() -> Bool {
        let available = Self.readAvailableBytes()
        return available >= latest.tier.heavyPassHeadroomBytes + uiReserveBytes / 2
    }

    func evaluateAdding(
        count: Int,
        currentQueueCount: Int,
        estimatedResidentBytes: UInt64
    ) -> CatalogCapacityDecision {
        let adding = max(0, count)
        let wouldBe = currentQueueCount + adding
        let softCap = CaptureSessionStore.CatalogSessionLimits.softQueueCap
        if wouldBe > softCap {
            return .softCapExceeded(limit: softCap, wouldBe: wouldBe)
        }

        let snap = refresh(queueCount: currentQueueCount, estimatedResidentBytes: estimatedResidentBytes)
        let available = snap.availableBytes
        let need = snap.tier.heavyPassHeadroomBytes + uiReserveBytes

        if snap.level == .critical || available < need {
            return .memoryBlocked(snap)
        }
        if snap.level == .caution || wouldBe >= (softCap * 3) / 4 {
            return .allowedWithGuidance(snap)
        }
        return .allowed
    }
}
