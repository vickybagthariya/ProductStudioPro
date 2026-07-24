import SwiftUI
import UIKit

/// Presents Apple's system camera (`UIImagePickerController`) for reliable full-quality capture.
struct CameraCaptureView: UIViewControllerRepresentable {
    var settings: CameraSessionSettings
    var batchProductNumber: Int? = nil
    var showsDoneBatch: Bool = false
    var vibrateOnShutter: Bool = true
    var beepOnShutter: Bool = false
    var onSettingsCaptured: ((CameraSessionSettings) -> Void)? = nil
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void
    var onDoneBatch: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> SystemCameraViewController {
        let controller = SystemCameraViewController()
        controller.apply(
            settings: settings,
            batchProductNumber: batchProductNumber,
            showsDoneBatch: showsDoneBatch,
            vibrateOnShutter: vibrateOnShutter,
            beepOnShutter: beepOnShutter,
            onSettingsCaptured: onSettingsCaptured,
            onCapture: onCapture,
            onCancel: onCancel,
            onDoneBatch: onDoneBatch
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: SystemCameraViewController, context: Context) {
        uiViewController.apply(
            settings: settings,
            batchProductNumber: batchProductNumber,
            showsDoneBatch: showsDoneBatch,
            vibrateOnShutter: vibrateOnShutter,
            beepOnShutter: beepOnShutter,
            onSettingsCaptured: onSettingsCaptured,
            onCapture: onCapture,
            onCancel: onCancel,
            onDoneBatch: onDoneBatch
        )
    }
}

// MARK: - System camera presenter

/// Presents `UIImagePickerController` modally — the supported pattern (never embed the picker as a child).
/// Parent SwiftUI must clear the `fullScreenCover` binding from `onCapture` / `onCancel`
/// (do not double-dismiss this host VC — that crashes intermittently).
final class SystemCameraViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private var settings = CameraSessionSettings.default
    private var batchProductNumber: Int?
    private var showsDoneBatch = false
    private var vibrateOnShutter = true
    private var beepOnShutter = false
    private var onSettingsCaptured: ((CameraSessionSettings) -> Void)?
    private var onCapture: ((UIImage) -> Void)?
    private var onCancel: (() -> Void)?
    private var onDoneBatch: (() -> Void)?

    private var didPresentPicker = false
    private var isClosing = false

    func apply(
        settings: CameraSessionSettings,
        batchProductNumber: Int?,
        showsDoneBatch: Bool,
        vibrateOnShutter: Bool,
        beepOnShutter: Bool,
        onSettingsCaptured: ((CameraSessionSettings) -> Void)?,
        onCapture: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void,
        onDoneBatch: (() -> Void)?
    ) {
        self.settings = settings
        self.batchProductNumber = batchProductNumber
        self.showsDoneBatch = showsDoneBatch
        self.vibrateOnShutter = vibrateOnShutter
        self.beepOnShutter = beepOnShutter
        self.onSettingsCaptured = onSettingsCaptured
        self.onCapture = onCapture
        self.onCancel = onCancel
        self.onDoneBatch = onDoneBatch
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // SwiftUI may reuse this host across fullScreenCover presentations.
        if presentedViewController == nil {
            isClosing = false
            didPresentPicker = false
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentCameraIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            didPresentPicker = false
        }
    }

    override var prefersStatusBarHidden: Bool { true }

    private func presentCameraIfNeeded() {
        guard !didPresentPicker, !isClosing, presentedViewController == nil else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            finish(cancelled: true, settings: settings, image: nil)
            return
        }

        didPresentPicker = true
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        if UIImagePickerController.isCameraDeviceAvailable(settings.legacyPickerDevice) {
            picker.cameraDevice = settings.legacyPickerDevice
        }
        picker.cameraFlashMode = settings.legacyPickerFlash
        present(picker, animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        guard !isClosing else { return }
        var latest = settings
        if picker.sourceType == .camera {
            latest = CameraSessionSettings(
                legacyDevice: picker.cameraDevice,
                legacyFlash: picker.cameraFlashMode
            )
        }
        Feedback.photoUseConfirmed(vibrate: vibrateOnShutter, beep: beepOnShutter)
        let image = info[.originalImage] as? UIImage
        dismissPicker(picker) { [weak self] in
            self?.finish(cancelled: image == nil, settings: latest, image: image)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        guard !isClosing else { return }
        let latest = CameraSessionSettings(
            legacyDevice: picker.cameraDevice,
            legacyFlash: picker.cameraFlashMode
        )
        dismissPicker(picker) { [weak self] in
            self?.finish(cancelled: true, settings: latest, image: nil)
        }
    }

    private func dismissPicker(_ picker: UIImagePickerController, completion: @escaping () -> Void) {
        if picker.presentingViewController != nil {
            picker.dismiss(animated: true, completion: completion)
        } else {
            completion()
        }
    }

    private func finish(cancelled: Bool, settings latest: CameraSessionSettings, image: UIImage?) {
        guard !isClosing else { return }
        isClosing = true
        onSettingsCaptured?(latest)
        if cancelled || image == nil {
            onCancel?()
        } else if let image {
            onCapture?(image)
        }
    }
}
