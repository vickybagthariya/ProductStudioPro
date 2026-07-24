import SwiftUI

private enum CaptureWizardStep: Int, CaseIterable, Identifiable {
    case scan = 0
    case shoot = 1
    case review = 2
    case confirm = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .scan: return "Scan"
        case .shoot: return "Shoot"
        case .review: return "Review"
        case .confirm: return "Confirm"
        }
    }
}

struct CaptureFlowView: View {
    @EnvironmentObject private var session: CaptureSessionStore
    let mode: CaptureMode

    @FocusState private var manualUPCFocused: Bool
    @FocusState private var manualNameFocused: Bool

    @State private var activeMode: CaptureMode
    @State private var showNativeCamera = false
    @State private var showScanner = false
    @State private var showAddedToast = false
    @State private var showBatchSummaryToast = false
    @State private var batchSummaryMessage = ""
    @State private var sharePayload: SharePayload?
    @State private var instruction = "Tap Capture Product Photo to begin."
    @State private var pendingDuplicateName = ""
    @State private var manualNameInput = ""
    @State private var previewIndex: Int?
    @State private var qualityReport: CaptureQualityReport?
    @State private var activeOverlay: CaptureFlowOverlay?
    @State private var showBatchCameraAlert = false
    @State private var pendingAutoOpenCamera = false
    @State private var batchContinuousPaused = false
    @State private var batchSessionStartCount = 0
    @State private var batchQualityWarnings = 0
    @State private var pendingExitAction: (() -> Void)?
    @State private var pendingAfterCameraWorkItem: DispatchWorkItem?
    @State private var didInitializeCaptureFlow = false
    @State private var queueInFlight = false
    @State private var nameEntryHint: String?
    @State private var captureUsesCustomName = false
    @State private var showManualUPCEntry = false
    @State private var pendingOpenCamera = false
    @State private var pendingScannerWorkItem: DispatchWorkItem?
    @State private var pendingCameraWorkItem: DispatchWorkItem?
    @State private var autoOpenRetryCount = 0
    @State private var scannerEpoch = 0

    init(mode: CaptureMode) {
        self.mode = mode
        _activeMode = State(initialValue: mode)
    }

    private var screenTitle: String {
        activeMode == .batch ? "Batch Mode" : "Single Product Capture"
    }

    private var canSwitchCaptureMode: Bool {
        session.currentImage == nil
            && !showScanner
            && !showManualUPCEntry
            && !session.isAwaitingMultiAngleName
            && !queueInFlight
            && session.pendingMultiAngleCaptures.isEmpty
            && activeOverlay == nil
            && !showNativeCamera
    }

    private var screenSubtitle: String {
        if session.multiAngleEnabled {
            let done = session.pendingMultiAngleCaptures.count
            let total = session.activeAngles.count
            if session.isAwaitingMultiAngleName {
                return "Name set · Product #\(session.nextSequence)"
            }
            return "\(session.currentAngleLabel) \(done)/\(total) · Product #\(session.nextSequence)"
        }
        return "Product #\(session.nextSequence)"
    }

    private var isInConfirmStep: Bool {
        if showManualUPCEntry { return true }
        if session.isAwaitingMultiAngleName && session.imageNamingMode == .manualInput { return true }
        if session.currentImage != nil && session.imageNamingMode == .manualInput && !showScanner { return true }
        return false
    }

    private var isInScanStep: Bool {
        showScanner
            || (session.isAwaitingMultiAngleName && session.imageNamingMode == .scannedUPC && !showManualUPCEntry)
    }

    private var currentWizardStep: CaptureWizardStep {
        if isInScanStep { return .scan }
        if isInConfirmStep { return .confirm }
        if qualityReport != nil, session.currentImage != nil { return .review }
        return .shoot
    }

    private var showsStudioGuidelines: Bool {
        !(session.currentImage != nil && session.imageNamingMode == .scannedUPC)
    }

    var body: some View {
        ZStack {
            AppScreenScaffold(
                title: screenTitle,
                subtitle: screenSubtitle,
                showsHome: false,
                onBack: { requestBatchExit { session.popNavigation() } },
                onHome: { requestBatchExit { session.goHome() } },
                layout: .scroll,
                scrollDismissesKeyboardInteractively: showManualUPCEntry || (session.currentImage != nil && session.imageNamingMode == .manualInput),
                headerAccessory: { queueHeaderButton }
            ) {
                captureModeToggle
                captureWizardProgress
                multiAngleCaptureControls
                instructionBar
                angleProgressBar

                if showScanner || (session.isAwaitingMultiAngleName && session.imageNamingMode == .scannedUPC && !showManualUPCEntry) {
                    // Scanner first so it is on-screen without scrolling (faster perceived scan).
                    DSCard(padding: 0) {
                        BarcodeScannerView { code in handleName(code) }
                            .id(scannerEpoch)
                            .frame(maxWidth: .infinity)
                            .frame(height: 360)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card - 2, style: .continuous))
                    }
                    pendingMultiAngleStrip
                    if let image = session.currentImage {
                        capturedPreview(image)
                    }
                    if showsStudioGuidelines {
                        DSStudioGuidelinesPanel()
                    }
                    quickQueueButton
                    manualUPCPanel
                } else if showManualUPCEntry, session.currentImage != nil || session.isAwaitingMultiAngleName {
                    pendingMultiAngleStrip
                    namingAfterCapturePanel
                } else if session.isAwaitingMultiAngleName && session.imageNamingMode == .manualInput {
                    pendingMultiAngleStrip
                    manualNamePanel
                } else {
                    captureReadyPanel
                    if session.currentImage != nil && session.imageNamingMode == .manualInput {
                        manualNamePanel
                    }
                }
            }
            .navigationBarHidden(true)

            if showAddedToast {
                VStack {
                    Spacer()
                    DSCaptureToast(text: "Added: \(lastAddedText)")
                        .padding(.bottom, 34)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showBatchSummaryToast {
                VStack {
                    Spacer()
                    DSCaptureToast(text: batchSummaryMessage)
                        .padding(.bottom, 34)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }

            if let overlay = activeOverlay {
                captureFlowOverlay(for: overlay)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showManualUPCEntry {
                manualUPCEntryBar
            } else if session.currentImage != nil && session.imageNamingMode == .manualInput {
                manualNameEntryBar
            }
        }
        // Keyboard accessory only for manual image-name mode — UPC entry bar already has its own controls.
        // Duplicating both caused the floating "Any Name / Done" overlay and TUIKeyplane constraint errors.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if !showManualUPCEntry {
                    Spacer()
                    Button("Done") {
                        manualUPCFocused = false
                        manualNameFocused = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .fullScreenCover(isPresented: $showNativeCamera) {
            CameraCaptureView(
                settings: activeCameraSettings,
                batchProductNumber: activeMode == .batch ? session.nextSequence : nil,
                showsDoneBatch: false,
                vibrateOnShutter: session.vibrateEnabled,
                beepOnShutter: session.beepEnabled,
                onSettingsCaptured: { settings in
                    rememberCameraSettings(settings)
                },
                onCapture: { image in
                    showNativeCamera = false
                    handleCameraCapture(image)
                },
                onCancel: {
                    showNativeCamera = false
                    instruction = batchContinuousPaused
                        ? "Batch capture paused. Tap Capture Product Photo when ready."
                        : "Capture cancelled. Tap Capture Product Photo when ready."
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: showNativeCamera) { _, isOpen in
            if !isOpen {
                runPendingAfterCameraAction()
            }
        }
        .sheet(item: $sharePayload) { payload in ActivityView(activityItems: payload.items, onComplete: nil) }
        .sheet(isPresented: Binding(
            get: { previewIndex != nil },
            set: { if !$0 { previewIndex = nil } }
        )) {
            ImagePreviewPagerView(initialIndex: previewIndex ?? 0)
                .environmentObject(session)
        }
        .alert("Batch Mode camera", isPresented: $showBatchCameraAlert) {
            Button(BatchAutoOpenCameraPreference.automatic.title) {
                session.setBatchAutoOpenPreference(.automatic)
                scheduleAutoOpenCamera(after: 0.5)
            }
            Button(BatchAutoOpenCameraPreference.manual.title, role: .cancel) {
                session.setBatchAutoOpenPreference(.manual)
            }
        } message: {
            Text("Open the camera automatically after each product is queued? Flash and front/back camera settings are remembered between shots.")
        }
        .onChange(of: showScanner) { _, isShowing in
            if !isShowing {
                manualUPCFocused = false
            }
        }
        .onAppear {
            guard !didInitializeCaptureFlow else { return }
            didInitializeCaptureFlow = true
            session.beginCaptureFlow(mode: activeMode)
            manualNameInput = ""
            batchContinuousPaused = false
            if activeMode == .batch {
                prepareBatchSession(promptIfNeeded: true)
            }
            resetCaptureStatusText()
        }
        .onDisappear {
            pendingAutoOpenCamera = false
            pendingOpenCamera = false
            pendingAfterCameraWorkItem?.cancel()
            pendingScannerWorkItem?.cancel()
            pendingCameraWorkItem?.cancel()
            pendingScannerWorkItem = nil
            pendingCameraWorkItem = nil
        }
        .onChange(of: previewIndex) { _, newValue in
            if newValue == nil {
                finishPreviewAndResumeCapture()
            }
        }
    }

    private func finishPreviewAndResumeCapture() {
        showScanner = false
        showManualUPCEntry = false
        captureUsesCustomName = false
        nameEntryHint = nil
        manualUPCFocused = false
        manualNameFocused = false
        qualityReport = nil
        activeOverlay = nil
        showBatchCameraAlert = false
        resetCaptureStatusText()
        instruction = startInstruction
    }

    private var activeCameraSettings: CameraSessionSettings {
        activeMode == .batch ? session.batchCameraSettings : session.preferredCameraSettings
    }

    private func rememberCameraSettings(_ settings: CameraSessionSettings) {
        if activeMode == .batch {
            session.rememberBatchCameraSettings(from: settings)
        } else {
            session.rememberCameraPreferences(from: settings)
        }
    }

    private var canPresentBlockingUI: Bool {
        !showNativeCamera && activeOverlay == nil && !showBatchCameraAlert && previewIndex == nil && sharePayload == nil
    }

    private func openCamera() {
        manualUPCFocused = false
        manualNameFocused = false
        showManualUPCEntry = false
        nameEntryHint = nil
        pendingScannerWorkItem?.cancel()
        pendingScannerWorkItem = nil
        guard !pendingOpenCamera else { return }
        if showScanner {
            // Release AVCaptureSession before UIImagePicker takes the camera.
            showScanner = false
            pendingOpenCamera = true
            pendingCameraWorkItem?.cancel()
            let work = DispatchWorkItem {
                pendingOpenCamera = false
                presentNativeCameraIfReady()
            }
            pendingCameraWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
            return
        }
        presentNativeCameraIfReady()
    }

    private func presentNativeCameraIfReady() {
        guard canPresentBlockingUI else {
            scheduleAutoOpenCamera(after: 0.55)
            return
        }
        pendingAutoOpenCamera = false
        autoOpenRetryCount = 0
        showNativeCamera = true
    }

    private func presentScannerSoon(after delay: TimeInterval = 0.4, message: String? = nil) {
        pendingScannerWorkItem?.cancel()
        showManualUPCEntry = false
        manualUPCFocused = false
        let work = DispatchWorkItem {
            guard session.currentImage != nil, !showNativeCamera else { return }
            scannerEpoch += 1
            showScanner = true
            if let message {
                instruction = message
            }
        }
        pendingScannerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func handleCameraCapture(_ image: UIImage) {
        let capped = ImageProcessor.downsampleIfNeededForImportPipeline(
            image,
            maxLongEdgePixels: CaptureQualityLimits.cameraOriginalMaxLongEdge
        )
        session.currentImage = capped
        pendingAfterCameraWorkItem?.cancel()

        Task.detached(priority: .userInitiated) {
            let report = ImageQualityAnalyzer.analyze(capped)
            await MainActor.run {
                guard session.currentImage != nil else { return }
                qualityReport = report
                pendingAfterCameraWorkItem?.cancel()
                let work = DispatchWorkItem {
                    guard !showNativeCamera, activeOverlay == nil else { return }
                    if report.shouldWarn {
                        instruction = "Capture quality warning. Retake recommended or use anyway."
                        dismissCaptureKeyboard()
                        activeOverlay = .qualityWarning
                    } else {
                        handlePhotoCaptured()
                    }
                }
                pendingAfterCameraWorkItem = work
                if !showNativeCamera {
                    work.perform()
                }
            }
        }
    }

    private func runPendingAfterCameraAction() {
        guard let work = pendingAfterCameraWorkItem, !work.isCancelled else { return }
        pendingAfterCameraWorkItem = nil
        if !showNativeCamera {
            work.perform()
        }
    }

    private func scheduleAutoOpenCamera(after delay: TimeInterval) {
        guard activeMode == .batch, session.batchAutoOpenCamera, !batchContinuousPaused else { return }
        pendingAutoOpenCamera = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard pendingAutoOpenCamera, activeMode == .batch, session.batchAutoOpenCamera, !batchContinuousPaused else { return }
            guard canPresentBlockingUI else {
                autoOpenRetryCount += 1
                // Cap retries so a stuck overlay can never loop forever.
                if autoOpenRetryCount < 12 {
                    scheduleAutoOpenCamera(after: 0.45)
                } else {
                    pendingAutoOpenCamera = false
                    autoOpenRetryCount = 0
                    instruction = "Tap Capture Product Photo when ready."
                }
                return
            }
            pendingAutoOpenCamera = false
            autoOpenRetryCount = 0
            qualityReport = nil
            openCamera()
        }
    }

    private var shouldOfferContinuousCapture: Bool {
        activeMode == .batch && session.batchAutoOpenCamera && !batchContinuousPaused
    }

    private func pauseBatchContinuousCapture() {
        batchContinuousPaused = true
        pendingAutoOpenCamera = false
        showNativeCamera = false
        instruction = "Batch capture paused. Tap Capture Product Photo when ready, or go back for a session summary."
    }

    private func recordBatchQualityWarning() {
        guard activeMode == .batch else { return }
        batchQualityWarnings += 1
    }

    private func requestBatchExit(then action: @escaping () -> Void) {
        guard activeMode == .batch else {
            action()
            return
        }
        let captured = max(0, session.products.count - batchSessionStartCount)
        guard captured > 0 else {
            action()
            return
        }
        let warningLabel = batchQualityWarnings == 1 ? "quality warning" : "quality warnings"
        batchSummaryMessage = "\(captured) products captured · \(batchQualityWarnings) \(warningLabel)"
        pendingExitAction = action
        withAnimation { showBatchSummaryToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { showBatchSummaryToast = false }
            pendingExitAction?()
            pendingExitAction = nil
        }
    }

    private var queueHeaderButton: some View {
        Button {
            session.navigationPath.append(AppRoute.queue)
        } label: {
            Text("Queue (\(session.products.count))")
                .font(DS.TypeScale.caption.weight(.semibold))
                .foregroundStyle(DS.ColorToken.accent)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(DS.ColorToken.backgroundTertiary, in: Capsule())
                .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: 1))
        }
        .buttonStyle(.plainPressable)
    }

    private var lastAddedText: String {
        session.products.last?.filename ?? "image queued"
    }

    private func resetCaptureStatusText() {
        activeOverlay = nil
        qualityReport = nil
        if !showScanner { instruction = startInstruction }
    }

    private func dismissCaptureKeyboard() {
        manualUPCFocused = false
        manualNameFocused = false
    }

    @ViewBuilder
    private func captureFlowOverlay(for overlay: CaptureFlowOverlay) -> some View {
        switch overlay {
        case .duplicate:
            CaptureFlowPromptOverlay(
                icon: "doc.on.doc.fill",
                iconColor: DS.ColorToken.warning,
                title: "Duplicate image already in queue",
                message: "This filename and angle are already in the queue. Replace the existing entry, or add a copy (the new file will be suffixed with -copy2).",
                primaryTitle: "Replace Existing",
                primaryRole: .destructive,
                secondaryTitle: "Add Anyway",
                cancelTitle: "Cancel",
                onPrimary: {
                    activeOverlay = nil
                    queueCapturedName(pendingDuplicateName, action: .replaceExisting)
                },
                onSecondary: {
                    activeOverlay = nil
                    queueCapturedName(pendingDuplicateName, action: .addCopy)
                },
                onCancel: {
                    activeOverlay = nil
                    instruction = "Cancelled. Capture or scan again when ready."
                    showManualUPCEntry = false
                    presentScannerSoon(after: 0.35)
                }
            )
        case .qualityWarning:
            CaptureFlowPromptOverlay(
                icon: "exclamationmark.triangle.fill",
                iconColor: DS.ColorToken.warning,
                title: "Retake Recommended",
                message: qualityReport?.summary ?? "This photo may not polish well.",
                primaryTitle: "Retake",
                primaryRole: .destructive,
                secondaryTitle: "Use Anyway",
                cancelTitle: "Cancel",
                onPrimary: {
                    activeOverlay = nil
                    qualityReport = nil
                    instruction = startInstruction
                    openCamera()
                },
                onSecondary: {
                    activeOverlay = nil
                    recordBatchQualityWarning()
                    handlePhotoCaptured()
                },
                onCancel: {
                    activeOverlay = nil
                    resetCaptureStatusText()
                }
            )
        }
    }

    private var startInstruction: String {
        if session.multiAngleEnabled {
            if session.isAwaitingMultiAngleName {
                return "All angles captured. Scan or enter one UPC to name them as UPC-1, UPC-2, …"
            }
            if shouldOfferContinuousCapture {
                return "Camera opens for each angle. Capture every angle first, then scan one UPC for the set."
            }
            return "Take each angle photo first. After the last angle, scan one UPC to name the set."
        }
        if shouldOfferContinuousCapture {
            return "Camera opens automatically after each product. Use the system camera controls for flash and zoom."
        }
        return "Tap Capture Product Photo to open the system camera."
    }

    private var multiAngleCaptureControls: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.stack) {
                Toggle("Multi-angle set", isOn: Binding(
                    get: { session.multiAngleEnabled },
                    set: { enabled in
                        session.multiAngleEnabled = enabled
                        instruction = enabled
                            ? session.multiAngleStatusLine
                            : startInstruction
                        if enabled {
                            session.startNextProduct()
                        }
                    }
                ))
                .tint(DS.ColorToken.accent)
                if session.multiAngleEnabled {
                    Text(session.multiAngleStatusLine)
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Capture all angles, then one UPC names files as UPC-1, UPC-2, …")
                        .font(DS.TypeScale.micro)
                        .foregroundStyle(DS.ColorToken.tertiaryLabel)
                }
            }
        }
    }

    private var pendingMultiAngleStrip: some View {
        Group {
            if !session.pendingMultiAngleCaptures.isEmpty {
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.stack) {
                        Text("Buffered angles (\(session.pendingMultiAngleCaptures.count)/\(session.activeAngles.count))")
                            .font(DS.TypeScale.caption.weight(.semibold))
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Space.stack) {
                                ForEach(session.pendingMultiAngleCaptures.sorted(by: { $0.ordinal < $1.ordinal })) { shot in
                                    VStack(spacing: 4) {
                                        Image(uiImage: shot.image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 52, height: 52)
                                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                                        Text("\(shot.ordinal)·\(shot.angle.badgeTitle)")
                                            .font(DS.TypeScale.micro)
                                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var captureModeToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                DSSegmentedChip(title: "Single", isSelected: activeMode == .single) {
                    selectCaptureMode(.single)
                }
                DSSegmentedChip(title: "Batch", isSelected: activeMode == .batch) {
                    selectCaptureMode(.batch)
                }
            }
            .disabled(!canSwitchCaptureMode)
            .opacity(canSwitchCaptureMode ? 1 : 0.45)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Capture mode")

            if !canSwitchCaptureMode {
                Text("Finish or clear the current product to switch modes.")
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(DS.ColorToken.tertiaryLabel)
            }
        }
    }

    private func selectCaptureMode(_ newMode: CaptureMode) {
        guard canSwitchCaptureMode, activeMode != newMode else { return }
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)

        if activeMode == .batch, newMode == .single {
            pendingAutoOpenCamera = false
            batchContinuousPaused = true
        }

        activeMode = newMode
        session.captureMode = newMode

        if newMode == .batch {
            prepareBatchSession(promptIfNeeded: true)
            instruction = session.batchAutoOpenCamera
                ? "Batch mode on. Tap Capture Product Photo, or wait for auto-open."
                : "Batch mode on. Tap Capture Product Photo for each product."
        } else {
            showBatchCameraAlert = false
            instruction = "Single mode. Tap Capture Product Photo to begin."
        }
        resetCaptureStatusText()
    }

    private func prepareBatchSession(promptIfNeeded: Bool) {
        batchSessionStartCount = session.products.count
        batchQualityWarnings = 0
        batchContinuousPaused = false
        session.resetBatchCameraSession()
        guard promptIfNeeded else { return }
        if session.hasBatchAutoOpenPreference {
            if session.batchAutoOpenCamera {
                scheduleAutoOpenCamera(after: 0.5)
            }
        } else {
            showBatchCameraAlert = true
        }
    }

    private var captureWizardProgress: some View {
        let active = currentWizardStep
        let steps = CaptureWizardStep.allCases
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    let isActive = step == active
                    let isPast = step.rawValue < active.rawValue
                    Circle()
                        .fill(isActive || isPast ? DS.ColorToken.accent : DS.ColorToken.backgroundTertiary)
                        .frame(width: isActive ? 12 : 9, height: isActive ? 12 : 9)
                        .overlay(
                            Circle()
                                .stroke(DS.ColorToken.accent.opacity(isActive ? 0.35 : 0), lineWidth: 3)
                                .frame(width: 18, height: 18)
                        )
                        .accessibilityLabel("\(step.title)\(isActive ? ", current step" : "")")

                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(isPast ? DS.ColorToken.accent.opacity(0.55) : DS.ColorToken.separator)
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 18)

            HStack {
                ForEach(steps) { step in
                    Text(step.title)
                        .font(.system(size: 11, weight: step == active ? .semibold : .medium))
                        .foregroundStyle(step == active ? DS.ColorToken.label : DS.ColorToken.secondaryLabel)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capture steps: Scan, Shoot, Review, Confirm. Current: \(active.title)")
    }

    private var instructionBar: some View {
        DSCard {
            Text(instruction)
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.label)
                .tracking(0.1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }

    private var angleProgressBar: some View {
        Group {
            if session.multiAngleEnabled {
                HStack(spacing: DS.Space.stack - 2) {
                    ForEach(Array(session.activeAngles.enumerated()), id: \.element.id) { idx, angle in
                        DSCaptureModeChip(
                            title: angle.rawValue,
                            isSelected: idx == session.currentAngleIndex
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var captureReadyPanel: some View {
        VStack(spacing: DS.Space.section) {
            DSCard(padding: DS.Space.section + 4) {
                VStack(spacing: DS.Space.section) {
                    IconBadge(
                        systemName: session.multiAngleEnabled ? "camera.metering.matrix" : "camera.viewfinder",
                        dimension: 58,
                        iconFontSize: 24
                    )
                    Text(session.currentImage == nil
                         ? (session.multiAngleEnabled ? "Capture \(session.currentAngleLabel)" : "Capture product photo")
                         : "Photo ready")
                        .font(DS.TypeScale.sectionTitle)
                        .foregroundStyle(DS.ColorToken.label)
                    Text(session.currentImage == nil
                         ? capturePanelText
                         : "Retake if needed, or continue to name this product.")
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 168)
            }

            if let image = session.currentImage { capturedPreview(image) }
            if let report = qualityReport { qualityAssistantCard(report) }

            if showsStudioGuidelines {
                DSStudioGuidelinesPanel()
            }

            DSPrimaryActionStack {
                Button(session.currentImage == nil ? "Capture Product Photo" : "Retake / Replace Current Photo") {
                    if session.imageNamingMode == .manualInput { manualNameInput = "" }
                    qualityReport = nil
                    session.currentUPC = ""
                    showScanner = false
                    showManualUPCEntry = false
                    manualUPCFocused = false
                    openCamera()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    session.navigationPath.append(AppRoute.queue)
                } label: {
                    Label("View Queue & Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())

                if session.currentImage != nil && session.imageNamingMode == .scannedUPC {
                    Button("Open UPC Scanner") {
                        showManualUPCEntry = false
                        manualUPCFocused = false
                        presentScannerSoon(after: 0.15)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var capturePanelText: String {
        switch session.imageNamingMode {
        case .scannedUPC:
            if session.multiAngleEnabled {
                return "Capture every angle first. After the last shot, scan one UPC to save UPC-1, UPC-2, …"
            }
            return "After capture, scan or type any UPC, SKU, or custom name."
        case .randomName:
            if session.multiAngleEnabled {
                return "Capture every angle first. Then one random name is applied as name-1, name-2, …"
            }
            return "After capture, the app saves this image using a random native-style IMG name."
        case .manualInput:
            if session.multiAngleEnabled {
                return "Capture every angle first. Then enter one name applied as name-1, name-2, …"
            }
            return "After capture, enter the image name manually. The app will add .jpg automatically."
        }
    }

    private func capturedPreview(_ image: UIImage) -> some View {
        DSCard {
            HStack(spacing: DS.Space.section) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip).stroke(DS.ColorToken.separator.opacity(0.85), lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Photo captured")
                        .font(DS.TypeScale.rowTitle)
                        .foregroundStyle(DS.ColorToken.label)
                    Text("Angle: \(session.currentAngleLabel) · Retake if you need sharper light or framing.")
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private func qualityAssistantCard(_ report: CaptureQualityReport) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.stack) {
                HStack {
                    Label(report.title, systemImage: report.shouldWarn ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(DS.TypeScale.sectionTitle)
                        .foregroundStyle(report.shouldWarn ? DS.ColorToken.warning : DS.ColorToken.success)
                        .labelStyle(.titleAndIcon)
                    Spacer()
                    Text("\(Int(report.overallScore * 100))%")
                        .font(DS.TypeScale.micro)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DS.ColorToken.backgroundTertiary, in: Capsule())
                }
                Text(report.summary)
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.tight) {
                    DSStatusPill(icon: "sun.max", text: "Light \(Int(report.brightnessScore * 100))")
                    DSStatusPill(icon: "camera.aperture", text: "Sharp \(Int(report.blurScore * 100))")
                    DSStatusPill(icon: "viewfinder", text: "Frame \(Int(report.framingScore * 100))")
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(report.shouldWarn ? DS.ColorToken.warning.opacity(0.45) : DS.ColorToken.separator, lineWidth: 1)
        )
    }

    private var quickQueueButton: some View {
        Button {
            session.navigationPath.append(AppRoute.queue)
        } label: {
            Label("View Queue & Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    private var manualUPCPanel: some View {
        DSCard {
            VStack(spacing: DS.Space.stack) {
                Text("Scan the barcode above, or enter a label manually.")
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    activateManualUPCEntry(useCustomName: false)
                } label: {
                    Label("Enter UPC manually", systemImage: "123.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    activateManualUPCEntry(useCustomName: true)
                } label: {
                    Label("Use any name", systemImage: "character.cursor.ibeam")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                if !session.lastUsedUPC.isEmpty {
                    Button {
                        manualUPCFocused = false
                        session.currentUPC = session.lastUsedUPC
                        handleName(session.lastUsedUPC)
                    } label: {
                        Text("Use last UPC: \(session.lastUsedUPC)")
                            .font(DS.TypeScale.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                if !session.recentBarcodes.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.tight) {
                        Text("Recent scans")
                            .font(DS.TypeScale.micro)
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Space.stack - 2) {
                                ForEach(session.recentBarcodes.prefix(12), id: \.self) { code in
                                    Button {
                                        manualUPCFocused = false
                                        session.currentUPC = code
                                        handleName(code)
                                    } label: {
                                        Text(code)
                                            .font(DS.TypeScale.micro)
                                            .monospacedDigit()
                                            .foregroundStyle(DS.ColorToken.label)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(DS.ColorToken.backgroundTertiary, in: Capsule())
                                            .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: 1))
                                    }
                                    .buttonStyle(.plainPressable)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var namingAfterCapturePanel: some View {
        VStack(spacing: DS.Space.section) {
            if let image = session.currentImage {
                capturedPreview(image)
            }
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.stack) {
                    Text(captureUsesCustomName ? "Enter a product name" : "Enter UPC or SKU")
                        .font(DS.TypeScale.sectionTitle)
                        .foregroundStyle(DS.ColorToken.label)
                    Text("Use the field below, or open the scanner to read the barcode with the camera.")
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                openScannerFromManualEntry()
            } label: {
                Label("Scan barcode with camera", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var manualUPCEntryBar: some View {
        VStack(spacing: DS.Space.stack) {
            Divider()
            HStack {
                Button {
                    toggleCaptureNameMode()
                } label: {
                    Label(
                        captureUsesCustomName ? "Enter UPC" : "Use any name",
                        systemImage: captureUsesCustomName ? "123.rectangle" : "character.cursor.ibeam"
                    )
                    .font(DS.TypeScale.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Scan barcode") {
                    openScannerFromManualEntry()
                }
                .font(DS.TypeScale.caption.weight(.semibold))
            }
            if let nameEntryHint {
                Text(nameEntryHint)
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(DS.ColorToken.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: DS.Space.stack) {
                TextField(
                    captureUsesCustomName ? "Product name" : "UPC or SKU",
                    text: $session.currentUPC
                )
                .keyboardType(captureUsesCustomName ? .default : .numberPad)
                .textInputAutocapitalization(captureUsesCustomName ? .words : .never)
                .autocorrectionDisabled(!captureUsesCustomName)
                .textFieldStyle(.roundedBorder)
                .dsSemanticTextField()
                .focused($manualUPCFocused)
                .submitLabel(.done)
                .onSubmit { submitNameFromBar() }
                // Force TextField rebuild so iOS actually swaps numberPad ↔ default keyboard.
                .id(captureUsesCustomName ? "nameField" : "upcField")
                Button("Done") {
                    manualUPCFocused = false
                }
                .font(DS.TypeScale.bodyEmphasis)
                .foregroundStyle(DS.ColorToken.accent)
            }
            Button("Add to Queue") {
                submitNameFromBar()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(queueInFlight)
            .opacity(queueInFlight ? 0.45 : 1)
        }
        .padding(.horizontal, DS.Space.screenHorizontal)
        .padding(.top, DS.Space.stack)
        .padding(.bottom, DS.Space.section)
        .background(DS.ColorToken.background)
    }

    /// Resign focus first, then re-focus so the keyboard type actually changes.
    private func toggleCaptureNameMode() {
        let switchingToCustom = !captureUsesCustomName
        InteractionHaptics.selection(vibrate: session.vibrateEnabled)
        nameEntryHint = nil
        manualUPCFocused = false
        DispatchQueue.main.async {
            captureUsesCustomName = switchingToCustom
            if switchingToCustom {
                // Keep typed digits when switching to name mode; clear only if empty.
            } else {
                session.currentUPC = session.currentUPC.filter(\.isNumber)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                manualUPCFocused = true
            }
        }
    }

    private func openScannerFromManualEntry() {
        pendingCameraWorkItem?.cancel()
        pendingCameraWorkItem = nil
        pendingOpenCamera = false
        if showNativeCamera {
            showNativeCamera = false
        }
        manualUPCFocused = false
        nameEntryHint = nil
        showManualUPCEntry = false
        presentScannerSoon(
            after: 0.45,
            message: "Point the camera at the barcode to scan."
        )
    }

    private var manualNamePanel: some View {
        DSCard {
            Text("Enter image name for \(session.currentAngleLabel). Do not type .jpg — it is added automatically. Use the field below.")
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.secondaryLabel)
        }
    }

    private var manualNameEntryBar: some View {
        VStack(spacing: DS.Space.stack) {
            Divider()
            HStack(spacing: DS.Space.stack) {
                TextField("Image name", text: $manualNameInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .dsSemanticTextField()
                    .focused($manualNameFocused)
                    .submitLabel(.done)
                    .onSubmit { submitManualName() }
                Button("Done") {
                    manualNameFocused = false
                }
                .font(DS.TypeScale.bodyEmphasis)
                .foregroundStyle(DS.ColorToken.accent)
            }
            Button("Use This Name") { submitManualName() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, DS.Space.screenHorizontal)
        .padding(.top, DS.Space.stack)
        .padding(.bottom, DS.Space.section)
        .background(DS.ColorToken.background)
    }

    private func activateManualUPCEntry(useCustomName: Bool) {
        showScanner = false
        showManualUPCEntry = true
        nameEntryHint = nil
        manualUPCFocused = false
        captureUsesCustomName = useCustomName
        if !useCustomName {
            session.currentUPC = session.currentUPC.filter(\.isNumber)
        }
        instruction = useCustomName
            ? "Enter any product name, then Add to Queue."
            : "Enter the UPC or SKU, then Add to Queue."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            manualUPCFocused = true
        }
    }

    private func submitNameFromBar() {
        manualUPCFocused = false
        guard session.currentImage != nil else {
            nameEntryHint = "Capture the product photo first."
            return
        }
        let cleaned = FileNameRules.captureLabel(from: session.currentUPC)
        guard !cleaned.isEmpty else {
            nameEntryHint = captureUsesCustomName
                ? "Enter a name for this product."
                : "Enter a UPC, SKU, or name."
            manualUPCFocused = true
            return
        }
        nameEntryHint = nil
        handleName(cleaned)
    }

    private func submitManualName() {
        manualNameFocused = false
        handleName(manualNameInput)
    }

    private func handlePhotoCaptured() {
        // Multi-angle: buffer every angle first; name once after the last shot.
        if session.multiAngleEnabled {
            let hasMoreAngles = session.bufferCurrentMultiAngleShot()
            qualityReport = nil
            if hasMoreAngles {
                instruction = "Saved \(session.pendingMultiAngleCaptures.count)/\(session.activeAngles.count). Now take \(session.currentAngleLabel)."
                Feedback.success(vibrate: session.vibrateEnabled, beep: session.beepEnabled)
                withAnimation { showAddedToast = true }
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await MainActor.run {
                        withAnimation { showAddedToast = false }
                        if shouldOfferContinuousCapture {
                            scheduleAutoOpenCamera(after: 0.45)
                        }
                    }
                }
            } else {
                Feedback.success(vibrate: session.vibrateEnabled, beep: session.beepEnabled)
                switch session.imageNamingMode {
                case .scannedUPC:
                    instruction = "All angles ready. Scan one UPC to name UPC-1…UPC-\(session.activeAngles.count)."
                    captureUsesCustomName = false
                    showManualUPCEntry = false
                    session.currentUPC = ""
                    manualUPCFocused = false
                    presentScannerSoon(after: 0.35, message: "One scan names the whole multi-angle set.")
                case .randomName:
                    let name = FileNameRules.randomNativeName()
                    instruction = "All angles ready. Applying \(name)-1…"
                    queueMultiAngleSet(name, action: .normal)
                case .manualInput:
                    manualNameInput = ""
                    instruction = "All angles ready. Enter one name for the set."
                }
            }
            return
        }

        switch session.imageNamingMode {
        case .scannedUPC:
            instruction = "Photo captured. Opening scanner…"
            captureUsesCustomName = false
            showManualUPCEntry = false
            session.currentUPC = ""
            manualUPCFocused = false
            presentScannerSoon(
                after: 0.4,
                message: "Point the camera at the barcode — scanning is automatic."
            )
        case .randomName:
            let name = FileNameRules.randomNativeName()
            instruction = "Photo captured. Adding random name \(name).jpg..."
            queueCapturedName(name, action: .normal)
        case .manualInput:
            manualNameInput = ""
            instruction = "Photo captured. Enter image name to add it to queue."
        }
    }

    private func handleName(_ rawName: String) {
        guard !queueInFlight, activeOverlay == nil else { return }

        let cleaned: String
        switch session.imageNamingMode {
        case .scannedUPC, .manualInput:
            cleaned = FileNameRules.captureLabel(from: rawName)
        case .randomName:
            cleaned = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !cleaned.isEmpty else {
            nameEntryHint = "Enter a UPC, SKU, or name."
            instruction = "Enter a label to continue."
            return
        }

        if session.isAwaitingMultiAngleName {
            if session.duplicateUPCExists(cleaned) {
                pendingDuplicateName = cleaned
                instruction = "UPC \(cleaned) already in queue. Replace the set, add copies, or cancel."
                dismissCaptureKeyboard()
                withAnimation { activeOverlay = .duplicate }
                return
            }
            queueMultiAngleSet(cleaned, action: .normal)
            return
        }

        guard session.currentImage != nil else {
            instruction = "Capture product photo first."
            showScanner = false
            return
        }
        let itemAngle = session.multiAngleEnabled ? session.currentCaptureAngle : .none
        if session.duplicateExists(upc: cleaned, angle: itemAngle) {
            pendingDuplicateName = cleaned
            instruction = "Duplicate found for \(cleaned) / \(itemAngle.rawValue). Choose Replace or Add Anyway."
            dismissCaptureKeyboard()
            withAnimation { activeOverlay = .duplicate }
            return
        }
        queueCapturedName(cleaned, action: .normal)
    }

    private func queueMultiAngleSet(_ cleaned: String, action: CaptureSessionStore.DuplicateQueueAction) {
        guard !cleaned.isEmpty, !queueInFlight else { return }
        activeOverlay = nil
        queueInFlight = true
        session.currentUPC = cleaned
        Feedback.success(vibrate: session.vibrateEnabled, beep: session.beepEnabled)
        instruction = "Adding \(session.pendingMultiAngleCaptures.count) angles as \(cleaned)-1…"
        pendingScannerWorkItem?.cancel()
        pendingScannerWorkItem = nil
        showScanner = false
        showManualUPCEntry = false
        captureUsesCustomName = false
        manualUPCFocused = false

        Task {
            let result = await session.commitPendingMultiAngleSet(identifier: cleaned, action: action)
            await MainActor.run {
                queueInFlight = false
                guard result.success else {
                    instruction = "Could not add multi-angle set. Try again."
                    return
                }
                if session.imageNamingMode == .scannedUPC {
                    session.recordSuccessfulBarcode(cleaned)
                }
                qualityReport = nil
                session.startNextProduct()
                withAnimation { showAddedToast = true }

                Task {
                    try? await Task.sleep(nanoseconds: 750_000_000)
                    await MainActor.run {
                        withAnimation { showAddedToast = false }
                        if activeMode == .batch {
                            if shouldOfferContinuousCapture {
                                instruction = "Set complete. Product #\(session.nextSequence) — camera opening…"
                                scheduleAutoOpenCamera(after: 0.65)
                            } else {
                                instruction = "Set complete. Product #\(session.nextSequence) ready. Tap Capture Product Photo."
                            }
                        } else {
                            instruction = "Multi-angle set complete. Opening preview."
                            guard activeOverlay == nil else { return }
                            if let id = result.productID,
                               let index = session.products.firstIndex(where: { $0.id == id }) {
                                previewIndex = index
                            } else {
                                previewIndex = 0
                            }
                        }
                    }
                }
            }
        }
    }

    private func queueCapturedName(_ cleaned: String, action: CaptureSessionStore.DuplicateQueueAction) {
        if session.isAwaitingMultiAngleName {
            queueMultiAngleSet(cleaned, action: action)
            return
        }
        guard !cleaned.isEmpty, !queueInFlight else { return }
        activeOverlay = nil
        queueInFlight = true
        session.currentUPC = cleaned
        if session.multiAngleEnabled && session.currentMultiAngleIdentifier.isEmpty { session.currentMultiAngleIdentifier = cleaned }
        Feedback.success(vibrate: session.vibrateEnabled, beep: session.beepEnabled)
        instruction = "Adding \(session.currentAngleLabel) to queue..."
        pendingScannerWorkItem?.cancel()
        pendingScannerWorkItem = nil
        showScanner = false
        showManualUPCEntry = false
        captureUsesCustomName = false
        manualUPCFocused = false

        Task {
            let result = await session.addCurrentToQueueAsync(action: action)
            await MainActor.run {
                queueInFlight = false
                guard result.success else {
                    if session.memoryGuidance?.isBlocking == true {
                        instruction = "Memory full — export or remove photos, then try again."
                    } else if session.wouldExceedSoftQueueCap(adding: 1) {
                        instruction = "Queue limit reached — remove photos or start a new session."
                    } else {
                        instruction = "Could not add image. Retake photo or enter name again."
                    }
                    return
                }
                if session.imageNamingMode == .scannedUPC {
                    session.recordSuccessfulBarcode(cleaned)
                }
                qualityReport = nil
                let hasNextAngle = session.advanceAfterSuccessfulQueue()
                withAnimation { showAddedToast = true }

                Task {
                    try? await Task.sleep(nanoseconds: 750_000_000)
                    await MainActor.run {
                        withAnimation { showAddedToast = false }
                        if hasNextAngle {
                            instruction = "Added. Now take \(session.currentAngleLabel) photo for the same product."
                            if shouldOfferContinuousCapture {
                                scheduleAutoOpenCamera(after: 0.65)
                            }
                        } else if activeMode == .batch {
                            if shouldOfferContinuousCapture {
                                instruction = "Product complete. Product #\(session.nextSequence) — camera opening..."
                                scheduleAutoOpenCamera(after: 0.65)
                            } else {
                                instruction = "Product complete. Product #\(session.nextSequence) ready. Tap Capture Product Photo."
                            }
                        } else {
                            instruction = "Capture complete. Opening preview."
                            guard activeOverlay == nil else { return }
                            if let id = result.productID,
                               let index = session.products.firstIndex(where: { $0.id == id }) {
                                previewIndex = index
                            } else {
                                previewIndex = 0
                            }
                        }
                    }
                }
            }
        }
    }
}

private enum CaptureFlowOverlay: Identifiable {
    case qualityWarning
    case duplicate

    var id: String {
        switch self {
        case .qualityWarning: return "qualityWarning"
        case .duplicate: return "duplicate"
        }
    }
}
