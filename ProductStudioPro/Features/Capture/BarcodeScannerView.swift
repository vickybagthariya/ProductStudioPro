import SwiftUI
import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        context.coordinator.controller = vc
        vc.onCode = { [weak coordinator = context.coordinator] code in
            coordinator?.onCode(code)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        uiViewController.onCode = { [weak coordinator = context.coordinator] code in
            coordinator?.onCode(code)
        }
    }

    final class Coordinator {
        var onCode: (String) -> Void
        weak var controller: BarcodeScannerViewController?

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }
    }
}

/// Stable full-frame UPC scanner.
/// - Session work stays off the main thread (no UI freezes / deadlocks with UIImagePicker).
/// - Starts only after non-zero layout (avoids FigCapture singular-matrix faults).
/// - Retries briefly if the system camera still holds the device.
/// - Retail symbologies only for faster metadata detection.
final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.productstudiopro.barcode.session", qos: .userInitiated)
    private let metadataQueue = DispatchQueue(label: "com.productstudiopro.barcode.metadata", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didCapture = false
    private var isConfigured = false
    private var hasStartedAfterLayout = false
    private var wantsRunning = false
    private var startAttempts = 0
    private var retryWorkItem: DispatchWorkItem?

    private let scanBox = UIView()
    private let scanLine = UIView()
    private let permissionContainer = UIView()
    private let permissionTitle = UILabel()
    private let permissionBody = UILabel()
    private let settingsButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.clipsToBounds = true
        setupPermissionContainer()
        addOverlay()
    }

    deinit {
        retryWorkItem?.cancel()
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        previewLayer?.frame = bounds
        guard bounds.width > 2, bounds.height > 2 else { return }
        if !hasStartedAfterLayout {
            hasStartedAfterLayout = true
            wantsRunning = true
            refreshAuthorizationAndSession()
        }
        startScanLineAnimation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didCapture = false
        wantsRunning = true
        startAttempts = 0
        if view.bounds.width > 2, view.bounds.height > 2 {
            hasStartedAfterLayout = true
            refreshAuthorizationAndSession()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // One cheap retry if UIImagePicker still held the camera at first start.
        scheduleStartRetry(after: 0.25)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        wantsRunning = false
        retryWorkItem?.cancel()
        retryWorkItem = nil
        pauseSession()
    }

    private func scheduleStartRetry(after delay: TimeInterval) {
        retryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsRunning, !self.didCapture, self.view.window != nil else { return }
            self.resumeSessionIfNeeded(isRetry: true)
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func pauseSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func resumeSessionIfNeeded(isRetry: Bool = false) {
        guard wantsRunning, !didCapture else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.wantsRunning, !self.didCapture else { return }

            if !self.isConfigured {
                guard self.configureSession() else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.wantsRunning else { return }
                        self.startAttempts += 1
                        if self.startAttempts < 8 {
                            self.scheduleStartRetry(after: 0.3)
                        } else {
                            self.showPermissionBlocker(
                                title: "Camera busy",
                                body: "Close other camera apps, then tap Scan barcode again — or enter the UPC manually.",
                                showSettings: false
                            )
                        }
                    }
                    return
                }
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            if isRetry || self.startAttempts > 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.startAttempts = 0
                    self?.hidePermissionBlocker()
                }
            }
        }
    }

    private func refreshAuthorizationAndSession() {
        guard wantsRunning, !didCapture else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            hidePermissionBlocker()
            ensurePreviewLayer()
            resumeSessionIfNeeded()
        case .denied, .restricted:
            showPermissionBlocker(
                title: "Camera access is off",
                body: "Enable Camera in Settings to scan barcodes.",
                showSettings: true
            )
        case .notDetermined:
            hidePermissionBlocker()
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.wantsRunning else { return }
                    if granted {
                        self.refreshAuthorizationAndSession()
                    } else {
                        self.showPermissionBlocker(
                            title: "Camera access is off",
                            body: "Enable Camera in Settings to scan barcodes.",
                            showSettings: true
                        )
                    }
                }
            }
        @unknown default:
            showPermissionBlocker(title: "Camera unavailable", body: "Camera status could not be determined.", showSettings: true)
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 720p is the sweet spot: fast metadata + enough detail for distant UPCs.
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        } else {
            session.sessionPreset = .vga640x480
        }

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        // Wide-angle only — avoids BackTriple / virtual device faults on Pro phones.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video) else {
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { return false }
            session.addInput(input)
        } catch {
            return false
        }

        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            // Mild optical zoom helps UPC read speed without fighting multi-cam fusion.
            let maxZ = device.activeFormat.videoMaxZoomFactor
            if maxZ >= 1.4 {
                device.videoZoomFactor = min(1.4, maxZ)
            }
            device.unlockForConfiguration()
        } catch {
            // Focus/zoom is optional — session can still run.
        }

        let meta = AVCaptureMetadataOutput()
        guard session.canAddOutput(meta) else { return false }
        session.addOutput(meta)
        // Off-main metadata queue keeps UI snappy; we hop to main only on a hit.
        meta.setMetadataObjectsDelegate(self, queue: metadataQueue)

        // Retail barcodes only — fewer types = faster detection.
        let preferred: [AVMetadataObject.ObjectType] = [
            .ean13, .ean8, .upce, .code128, .code39
        ]
        var types = preferred.filter { meta.availableMetadataObjectTypes.contains($0) }
        if types.isEmpty {
            types = meta.availableMetadataObjectTypes.filter {
                $0 == .ean13 || $0 == .ean8 || $0 == .upce || $0 == .code128
            }
        }
        if types.isEmpty {
            types = Array(meta.availableMetadataObjectTypes)
        }
        guard !types.isEmpty else { return false }
        meta.metadataObjectTypes = types
        meta.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)

        isConfigured = true
        return true
    }

    private func ensurePreviewLayer() {
        if let previewLayer {
            previewLayer.frame = view.bounds
            return
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    private func setupPermissionContainer() {
        permissionContainer.backgroundColor = UIColor(white: 0.06, alpha: 0.94)
        permissionContainer.translatesAutoresizingMaskIntoConstraints = false
        permissionContainer.isHidden = true
        view.addSubview(permissionContainer)

        permissionTitle.textColor = .white
        permissionTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        permissionTitle.textAlignment = .center
        permissionTitle.numberOfLines = 0
        permissionTitle.translatesAutoresizingMaskIntoConstraints = false

        permissionBody.textColor = UIColor.white.withAlphaComponent(0.82)
        permissionBody.font = .systemFont(ofSize: 14, weight: .regular)
        permissionBody.textAlignment = .center
        permissionBody.numberOfLines = 0
        permissionBody.translatesAutoresizingMaskIntoConstraints = false

        settingsButton.setTitle("Open Settings", for: .normal)
        settingsButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        settingsButton.setTitleColor(AppTheme.accentUIColor, for: .normal)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.addAction(UIAction { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }, for: .touchUpInside)

        permissionContainer.addSubview(permissionTitle)
        permissionContainer.addSubview(permissionBody)
        permissionContainer.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            permissionContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            permissionContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            permissionContainer.topAnchor.constraint(equalTo: view.topAnchor),
            permissionContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            permissionTitle.leadingAnchor.constraint(equalTo: permissionContainer.leadingAnchor, constant: 24),
            permissionTitle.trailingAnchor.constraint(equalTo: permissionContainer.trailingAnchor, constant: -24),
            permissionTitle.centerYAnchor.constraint(equalTo: permissionContainer.centerYAnchor, constant: -40),
            permissionBody.leadingAnchor.constraint(equalTo: permissionContainer.leadingAnchor, constant: 24),
            permissionBody.trailingAnchor.constraint(equalTo: permissionContainer.trailingAnchor, constant: -24),
            permissionBody.topAnchor.constraint(equalTo: permissionTitle.bottomAnchor, constant: 10),
            settingsButton.centerXAnchor.constraint(equalTo: permissionContainer.centerXAnchor),
            settingsButton.topAnchor.constraint(equalTo: permissionBody.bottomAnchor, constant: 16)
        ])
    }

    private func showPermissionBlocker(title: String, body: String, showSettings: Bool) {
        permissionTitle.text = title
        permissionBody.text = body
        settingsButton.isHidden = !showSettings
        permissionContainer.isHidden = false
        view.bringSubviewToFront(permissionContainer)
        pauseSession()
    }

    private func hidePermissionBlocker() {
        permissionContainer.isHidden = true
    }

    private func addOverlay() {
        let title = UILabel()
        title.text = "Scan UPC"
        title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        let helper = UILabel()
        helper.text = "Point anywhere near the barcode — scanning is automatic"
        helper.textColor = UIColor.white.withAlphaComponent(0.78)
        helper.font = .systemFont(ofSize: 13, weight: .regular)
        helper.textAlignment = .center
        helper.numberOfLines = 2
        helper.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(helper)

        scanBox.layer.borderColor = AppTheme.accentUIColor.cgColor
        scanBox.layer.borderWidth = 3
        scanBox.layer.cornerRadius = 14
        scanBox.backgroundColor = .clear
        scanBox.isUserInteractionEnabled = false
        scanBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanBox)

        scanLine.backgroundColor = AppTheme.accentUIColor
        scanLine.layer.shadowColor = AppTheme.accentUIColor.cgColor
        scanLine.layer.shadowOpacity = 0.9
        scanLine.layer.shadowRadius = 8
        scanLine.translatesAutoresizingMaskIntoConstraints = false
        scanBox.addSubview(scanLine)

        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            helper.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            helper.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            helper.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            helper.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            scanBox.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanBox.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 8),
            scanBox.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9),
            scanBox.heightAnchor.constraint(equalToConstant: 140),
            scanLine.leadingAnchor.constraint(equalTo: scanBox.leadingAnchor, constant: 12),
            scanLine.trailingAnchor.constraint(equalTo: scanBox.trailingAnchor, constant: -12),
            scanLine.heightAnchor.constraint(equalToConstant: 3),
            scanLine.topAnchor.constraint(equalTo: scanBox.topAnchor, constant: 14)
        ])
    }

    private func startScanLineAnimation() {
        guard scanBox.bounds.height > 20 else { return }
        guard scanLine.layer.animation(forKey: "scan") == nil else { return }
        let maxMove = max(20, scanBox.bounds.height - 30)
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = 0
        animation.toValue = maxMove
        animation.duration = 1.05
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scanLine.layer.add(animation, forKey: "scan")
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didCapture else { return }
        for metadata in metadataObjects {
            guard let obj = metadata as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue,
                  !value.isEmpty else { continue }
            let cleaned = BarcodeCanonicalForm.normalizeForStorage(value, symbology: obj.type.rawValue)
            let label = cleaned.isEmpty ? FileNameRules.captureLabel(from: value) : cleaned
            guard !label.isEmpty else { continue }

            // Latch immediately so concurrent metadata callbacks cannot double-fire.
            didCapture = true
            wantsRunning = false
            retryWorkItem?.cancel()
            pauseSession()
            let callback = onCode
            DispatchQueue.main.async {
                self.scanLine.layer.removeAllAnimations()
                callback?(label)
            }
            return
        }
    }
}
