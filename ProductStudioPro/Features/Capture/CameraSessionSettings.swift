import AVFoundation
import UIKit

/// Snapshot of native camera controls preserved across captures in a batch session.
struct CameraSessionSettings: Equatable, Codable {
    var usesFrontCamera: Bool = false
    var zoomFactor: Double = 1.0
    /// 0 = auto, 1 = on, 2 = off
    var flashMode: Int = 0
    var torchEnabled: Bool = false
    var exposureBias: Float = 0

    static let `default` = CameraSessionSettings()

    var captureDevicePosition: AVCaptureDevice.Position {
        usesFrontCamera ? .front : .back
    }

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch flashMode {
        case 1: return .on
        case 2: return .off
        default: return .auto
        }
    }

    var legacyPickerDevice: UIImagePickerController.CameraDevice {
        usesFrontCamera ? .front : .rear
    }

    var legacyPickerFlash: UIImagePickerController.CameraFlashMode {
        switch flashMode {
        case 1: return .on
        case 2: return .off
        default: return .auto
        }
    }

    init(
        usesFrontCamera: Bool = false,
        zoomFactor: Double = 1.0,
        flashMode: Int = 0,
        torchEnabled: Bool = false,
        exposureBias: Float = 0
    ) {
        self.usesFrontCamera = usesFrontCamera
        self.zoomFactor = max(1, zoomFactor)
        self.flashMode = min(2, max(0, flashMode))
        self.torchEnabled = torchEnabled
        self.exposureBias = exposureBias
    }

    init(legacyDevice: UIImagePickerController.CameraDevice, legacyFlash: UIImagePickerController.CameraFlashMode) {
        usesFrontCamera = legacyDevice == .front
        zoomFactor = 1
        switch legacyFlash {
        case .on: flashMode = 1
        case .off: flashMode = 2
        default: flashMode = 0
        }
        torchEnabled = false
        exposureBias = 0
    }

    /// Replaces each field with the latest user-adjusted values from a capture session.
    mutating func applyLatestSession(_ latest: CameraSessionSettings) {
        self = latest
    }

    func displayZoomLabel() -> String {
        if zoomFactor < 1.05 { return "1×" }
        if abs(zoomFactor - round(zoomFactor)) < 0.08 {
            return String(format: "%.0f×", zoomFactor)
        }
        return String(format: "%.1f×", zoomFactor)
    }
}

enum BatchAutoOpenCameraPreference: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Auto-open camera"
        case .manual: return "Tap to open each time"
        }
    }

    var settingsDescription: String {
        switch self {
        case .automatic:
            return "Opens the camera immediately when you enter Batch Mode and after each product is queued."
        case .manual:
            return "Shows the capture screen; tap Capture Product Photo to open the camera each time."
        }
    }
}
