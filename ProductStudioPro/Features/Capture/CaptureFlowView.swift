import SwiftUI

struct CaptureFlowView: View {
    @EnvironmentObject private var session: CaptureSessionStore
    let mode: CaptureMode

    @FocusState private var manualUPCFocused: Bool
    @FocusState private var manualNameFocused: Bool

    @State private var activeMode: CaptureMode
    @State private var selectedCaptureMode: CaptureMode?
    @State private var workflowKind: CaptureWorkflowKind?
    @State private var hasConfirmedWorkflow = false
    @State private var skippedWorkflowSelection = false
    @State private var enteredViaMultiAngleShortcut = false
    @State private var showMultiAngleHomeSetup = false
    @State private var showNativeCamera = false
    @State private var showScanner = false
    @State private var showAddedToast = false
    @State private var showBatchSummaryToast = false
    @State private var batchSummaryMessage = ""
    @State private var sharePayload: SharePayload?
    @State private var instruction = "Tap Capture to begin."
    @State private var pendingDuplicateName = ""
    @State private var manualNameInput = ""
    @State private var previewIndex: Int?
    @State private var activeOverlay: CaptureFlowOverlay?
    @State private var showBatchCameraAlert = false
    @State private var pendingAutoOpenCamera = false
    @State private var batchContinuousPaused = false
    @State private var batchSessionStartCount = 0
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
    @State private var scrollTargetID: String?
    @State private var captureAutoScrollGeneration = 0
    @State private var consumedAutoScrollGeneration = 0

    init(mode: CaptureMode) {
        self.mode = mode
        _activeMode = State(initialValue: mode)
        _selectedCaptureMode = State(initialValue: nil)
    }

    // MARK: - Derived state

    private var stepContext: CaptureStepContext {
        CaptureStepContext(
            hasConfirmedWorkflow: hasConfirmedWorkflow,
            showsIdentification: shouldShowIdentification,
            isReadyToQueue: isReadyToQueue
        )
    }

    private var batchCapturedThisSession: Int {
        max(0, session.products.count - batchSessionStartCount)
    }

    private var shouldShowIdentification: Bool {
        guard hasConfirmedWorkflow else { return false }
        if session.isAwaitingMultiAngleName { return true }
        if session.currentImage != nil { return true }
        return showScanner || showManualUPCEntry
    }

    private var isReadyToQueue: Bool {
        if session.imageNamingMode == .randomName { return session.currentImage != nil || session.isAwaitingMultiAngleName }
        if showManualUPCEntry || (session.imageNamingMode == .manualInput && (session.currentImage != nil || session.isAwaitingMultiAngleName)) {
            let text = session.imageNamingMode == .manualInput && !showManualUPCEntry ? manualNameInput : session.currentUPC
            return !FileNameRules.captureLabel(from: text).isEmpty
        }
        return false
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
            && hasConfirmedWorkflow
    }

    private var screenTitle: String {
        guard hasConfirmedWorkflow, let workflowKind else { return "Capture" }
        switch workflowKind {
        case .standardCapture:
            return activeMode == .batch ? "Batch Capture" : "Single Capture"
        case .multiAngle:
            return activeMode == .batch ? "Multi-Angle Batch" : "Multi-Angle Capture"
        }
    }

    private var screenSubtitle: String? {
        guard hasConfirmedWorkflow else { return nil }
        if session.multiAngleEnabled {
            let total = session.activeAngles.count
            if session.isAwaitingMultiAngleName {
                return "All angles captured · Product #\(session.nextSequence)"
            }
            let current = min(session.currentAngleIndex + 1, total)
            return "\(session.currentAngleLabel) · \(current)/\(total) · Product #\(session.nextSequence)"
        }
        return "Product #\(session.nextSequence)"
    }

    private var completedAngleSet: Set<ProductAngle> {
        Set(session.pendingMultiAngleCaptures.map(\.angle))
    }

    private var captureHeadline: String {
        if session.currentImage != nil { return "Photo ready" }
        if session.multiAngleEnabled { return "Capture \(session.currentAngleLabel)" }
        return "Capture product photo"
    }

    private var captureDetail: String {
        if session.currentImage != nil || session.isAwaitingMultiAngleName {
            return "Identify the product below."
        }
        return instruction
    }

    private var captureButtonTitle: String {
        session.currentImage == nil ? "Capture Photo" : "Retake Photo"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            CaptureFlowScaffold(
                title: screenTitle,
                subtitle: screenSubtitle,
                queueCount: session.products.count,
                onBack: handleBack,
                onQueue: { session.navigationPath.append(AppRoute.queue) },
                scrollDismissesKeyboardInteractively: showManualUPCEntry
                    || ((session.currentImage != nil || session.isAwaitingMultiAngleName)
                        && session.imageNamingMode == .manualInput),
                scrollTargetID: $scrollTargetID
            ) {
                VStack(alignment: .leading, spacing: PSDesignSpacing.lg) {
                    if hasConfirmedWorkflow {
                        CaptureProgressIndicator(context: stepContext)
                            .padding(.bottom, PSDesignSpacing.xs)
                    }

                    if showMultiAngleHomeSetup {
                        CaptureMultiAngleSetupSection(selectedCaptureMode: $selectedCaptureMode) {
                            confirmMultiAngleHomeSetup()
                        }
                    } else if !hasConfirmedWorkflow {
                        CaptureWorkflowSelectionSection(
                            selectedWorkflow: $workflowKind,
                            selectedCaptureMode: $selectedCaptureMode,
                            onContinue: { confirmWorkflowSelection() }
                        )
                    } else {
                        guidedCaptureContent
                    }
                }
            }

            if showAddedToast {
                VStack {
                    Spacer()
                    CaptureFlowToast(text: "Added: \(lastAddedText)")
                        .padding(.bottom, 34)
                }
                .transition(PSDesignMotion.slideUp)
            }

            if showBatchSummaryToast {
                VStack {
                    Spacer()
                    CaptureFlowToast(text: batchSummaryMessage)
                        .padding(.bottom, 34)
                }
                .transition(PSDesignMotion.slideUp)
                .zIndex(2)
            }

            if let overlay = activeOverlay {
                captureFlowOverlay(for: overlay)
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
                        ? "Batch capture paused. Tap Capture when ready."
                        : "Capture cancelled. Tap Capture when ready."
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: showNativeCamera) { _, isOpen in
            if !isOpen { runPendingAfterCameraAction() }
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
            initializeCaptureEntry()
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
            if newValue == nil { finishPreviewAndResumeCapture() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    manualUPCFocused = false
                    manualNameFocused = false
                }
                .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Guided content

    @ViewBuilder
    private var guidedCaptureContent: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
            if activeMode == .batch {
                CaptureBatchProgressBanner(
                    productNumber: session.nextSequence,
                    capturedThisSession: batchCapturedThisSession
                )
            }

            if session.multiAngleEnabled {
                CaptureAngleProgressSection(
                    angles: session.activeAngles,
                    currentIndex: session.currentAngleIndex,
                    completedAngles: completedAngleSet
                )
                .transition(PSDesignMotion.slideDown)
            }

            postCaptureBlock

            if canSwitchCaptureMode, workflowKind == .standardCapture {
                CaptureModeSwitchSection(activeMode: activeMode, onSelect: selectCaptureMode)
            }

            if stepContext.isReadyToQueue && session.imageNamingMode == .scannedUPC && !showScanner && !showManualUPCEntry {
                PrimaryButton("Add to Queue", systemImage: PSDesignIcons.queue, isDisabled: queueInFlight, isLoading: queueInFlight) {
                    submitNameFromBar()
                }
                .transition(PSDesignMotion.scaleFade)
            }

            SecondaryButton("Review Queue", systemImage: PSDesignIcons.queue) {
                session.navigationPath.append(AppRoute.queue)
            }
            .accessibilityHint("Review captured products before export")
        }
    }

    @ViewBuilder
    private var postCaptureBlock: some View {
        let compactTransition = shouldShowIdentification
            && (session.currentImage != nil || session.isAwaitingMultiAngleName)

        VStack(alignment: .leading, spacing: compactTransition ? PSDesignSpacing.sm : PSDesignSpacing.lg) {
            if !session.isAwaitingMultiAngleName || session.currentImage != nil {
                CaptureCameraSection(
                    headline: captureHeadline,
                    detail: captureDetail,
                    previewImage: session.currentImage,
                    captureButtonTitle: captureButtonTitle,
                    isMultiAngle: session.multiAngleEnabled,
                    currentAngleLabel: session.currentAngleLabel,
                    onCapture: retakeOrCapturePhoto
                )
            }

            if !session.pendingMultiAngleCaptures.isEmpty {
                CaptureBufferedImagesStrip(
                    captures: session.pendingMultiAngleCaptures,
                    totalCount: session.activeAngles.count
                )
                .transition(PSDesignMotion.slideUp)
            }

            if shouldShowIdentification {
                CaptureProductIdentificationSection(
                    session: session,
                    showsScanner: showScanner || (session.isAwaitingMultiAngleName && session.imageNamingMode == .scannedUPC && !showManualUPCEntry),
                    showManualEntry: showManualUPCEntry,
                    captureUsesCustomName: captureUsesCustomName,
                    nameEntryHint: nameEntryHint,
                    recentBarcodes: session.recentBarcodes,
                    lastUsedUPC: session.lastUsedUPC,
                    onScanResult: handleName,
                    onOpenScanner: openScannerFromManualEntry,
                    onManualUPC: { activateManualUPCEntry(useCustomName: false) },
                    onManualName: { activateManualUPCEntry(useCustomName: true) },
                    onUseLastUPC: {
                        manualUPCFocused = false
                        session.currentUPC = session.lastUsedUPC
                        handleName(session.lastUsedUPC)
                    },
                    onRecentBarcode: { code in
                        manualUPCFocused = false
                        session.currentUPC = code
                        handleName(code)
                    },
                    manualUPCText: $session.currentUPC,
                    manualNameText: $manualNameInput,
                    manualUPCFocused: $manualUPCFocused,
                    manualNameFocused: $manualNameFocused,
                    onSubmit: {
                        if session.imageNamingMode == .manualInput && !showManualUPCEntry && !session.isAwaitingMultiAngleName {
                            submitManualName()
                        } else {
                            submitNameFromBar()
                        }
                    },
                    onToggleNameMode: toggleCaptureNameMode,
                    queueInFlight: queueInFlight,
                    scannerEpoch: scannerEpoch
                )
                .id(CaptureScrollID.identifyProduct)
                .transition(PSDesignMotion.slideUp)
            }
        }
    }

    private func retakeOrCapturePhoto() {
        if session.currentImage != nil {
            session.currentUPC = ""
            if session.imageNamingMode == .manualInput { manualNameInput = "" }
            showScanner = false
            showManualUPCEntry = false
        }
        openCamera()
    }

    // MARK: - Back navigation

    private func handleBack() {
        switch stepContext.currentStep {
        case .chooseWorkflow:
            requestBatchExit { session.popNavigation() }
        case .capturePhotos:
            goBackToWorkflowSelection()
        case .identifyProduct:
            goBackToCaptureFromIdentification()
        case .addToQueue:
            goBackToIdentifyFromQueue()
        }
    }

    private func goBackToWorkflowSelection() {
        if skippedWorkflowSelection {
            requestBatchExit { session.popNavigation() }
            return
        }

        withAnimation(PSDesignMotion.springSoft) {
            hasConfirmedWorkflow = false
            resetIdentificationState()
            session.startNextProduct()

            if enteredViaMultiAngleShortcut {
                showMultiAngleHomeSetup = true
                selectedCaptureMode = nil
                session.multiAngleEnabled = true
                session.enabledAngles = ProductAngle.captureAngles
            } else {
                showMultiAngleHomeSetup = false
                selectedCaptureMode = nil
                session.multiAngleEnabled = false
            }
        }
    }

    private func goBackToCaptureFromIdentification() {
        withAnimation(PSDesignMotion.springSoft) {
            resetIdentificationState()
            if session.isAwaitingMultiAngleName {
                session.restoreLastMultiAngleShotForRetake()
            } else {
                session.currentImage = nil
            }
        }
    }

    private func goBackToIdentifyFromQueue() {
        withAnimation(PSDesignMotion.springSoft) {
            session.currentUPC = ""
            manualNameInput = ""
            nameEntryHint = nil
            showManualUPCEntry = false
            captureUsesCustomName = false
            manualUPCFocused = false
            manualNameFocused = false
        }
    }

    private func resetIdentificationState() {
        showScanner = false
        showManualUPCEntry = false
        captureUsesCustomName = false
        nameEntryHint = nil
        session.currentUPC = ""
        manualNameInput = ""
        manualUPCFocused = false
        manualNameFocused = false
        pendingScannerWorkItem?.cancel()
        pendingScannerWorkItem = nil
    }

    // MARK: - Initialization

    private func initializeCaptureEntry() {
        manualNameInput = ""
        batchContinuousPaused = false

        if mode == .batch {
            workflowKind = .standardCapture
            selectedCaptureMode = .batch
            activeMode = .batch
            skippedWorkflowSelection = true
            session.multiAngleEnabled = false
            confirmWorkflowSelection(skipBatchPrompt: false)
            return
        }

        if session.consumeMultiAngleHomeShortcut() {
            workflowKind = .multiAngle
            enteredViaMultiAngleShortcut = true
            selectedCaptureMode = nil
            activeMode = .single
            showMultiAngleHomeSetup = true
            session.multiAngleEnabled = true
            session.enabledAngles = ProductAngle.captureAngles
            return
        }

        selectedCaptureMode = nil
        session.multiAngleEnabled = false
        resetCaptureStatusText()
    }

    private func confirmWorkflowSelection(skipBatchPrompt: Bool = false) {
        guard let workflowKind, let mode = selectedCaptureMode else { return }
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)
        activeMode = mode

        switch workflowKind {
        case .standardCapture:
            session.multiAngleEnabled = false
        case .multiAngle:
            session.multiAngleEnabled = true
            session.enabledAngles = ProductAngle.captureAngles
        }

        session.captureMode = activeMode
        session.beginCaptureFlow(mode: activeMode)
        hasConfirmedWorkflow = true
        instruction = startInstruction

        if activeMode == .batch {
            prepareBatchSession(promptIfNeeded: !skipBatchPrompt)
        }
    }

    private func confirmMultiAngleHomeSetup() {
        guard let mode = selectedCaptureMode else { return }
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)
        activeMode = mode
        showMultiAngleHomeSetup = false
        session.multiAngleEnabled = true
        session.enabledAngles = ProductAngle.captureAngles
        session.captureMode = activeMode
        session.beginCaptureFlow(mode: activeMode)
        hasConfirmedWorkflow = true
        instruction = startInstruction
        if activeMode == .batch {
            prepareBatchSession(promptIfNeeded: true)
        }
    }

    // MARK: - Camera & capture (preserved logic)

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
            guard session.currentImage != nil || session.isAwaitingMultiAngleName, !showNativeCamera else { return }
            scannerEpoch += 1
            showScanner = true
            if let message { instruction = message }
        }
        pendingScannerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func handleCameraCapture(_ image: UIImage) {
        let capped = ImageProcessor.downsampleIfNeededForImportPipeline(
            image,
            maxLongEdgePixels: ImageProcessingLimits.cameraOriginalMaxLongEdge
        )
        session.currentImage = capped
        pendingAfterCameraWorkItem?.cancel()
        let work = DispatchWorkItem {
            guard !showNativeCamera, activeOverlay == nil else { return }
            handlePhotoCaptured()
        }
        pendingAfterCameraWorkItem = work
        if !showNativeCamera { work.perform() }
    }

    private func runPendingAfterCameraAction() {
        guard let work = pendingAfterCameraWorkItem, !work.isCancelled else { return }
        pendingAfterCameraWorkItem = nil
        if !showNativeCamera { work.perform() }
    }

    private func scheduleAutoOpenCamera(after delay: TimeInterval) {
        guard activeMode == .batch, session.batchAutoOpenCamera, !batchContinuousPaused else { return }
        pendingAutoOpenCamera = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard pendingAutoOpenCamera, activeMode == .batch, session.batchAutoOpenCamera, !batchContinuousPaused else { return }
            guard canPresentBlockingUI else {
                autoOpenRetryCount += 1
                if autoOpenRetryCount < 12 {
                    scheduleAutoOpenCamera(after: 0.45)
                } else {
                    pendingAutoOpenCamera = false
                    autoOpenRetryCount = 0
                    instruction = "Tap Capture when ready."
                }
                return
            }
            pendingAutoOpenCamera = false
            autoOpenRetryCount = 0
            openCamera()
        }
    }

    private var shouldOfferContinuousCapture: Bool {
        activeMode == .batch && session.batchAutoOpenCamera && !batchContinuousPaused
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
        batchSummaryMessage = "\(captured) products captured"
        pendingExitAction = action
        withAnimation { showBatchSummaryToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { showBatchSummaryToast = false }
            pendingExitAction?()
            pendingExitAction = nil
        }
    }

    private var lastAddedText: String {
        session.products.last?.filename ?? "image queued"
    }

    private func resetCaptureStatusText() {
        activeOverlay = nil
        if !showScanner { instruction = startInstruction }
    }

    private func finishPreviewAndResumeCapture() {
        showScanner = false
        showManualUPCEntry = false
        captureUsesCustomName = false
        nameEntryHint = nil
        manualUPCFocused = false
        manualNameFocused = false
        activeOverlay = nil
        showBatchCameraAlert = false
        resetCaptureStatusText()
        instruction = startInstruction
    }

    private var startInstruction: String {
        if session.multiAngleEnabled {
            if session.isAwaitingMultiAngleName {
                return "All angles captured. Identify the product to name UPC-1, UPC-2, …"
            }
            if shouldOfferContinuousCapture {
                return "Capture every angle, then identify the product."
            }
            return "Capture each angle in order."
        }
        if shouldOfferContinuousCapture {
            return "Camera opens automatically after each product."
        }
        return "Tap Capture to open the camera."
    }

    @ViewBuilder
    private func captureFlowOverlay(for overlay: CaptureFlowOverlay) -> some View {
        switch overlay {
        case .duplicate:
            CaptureFlowPromptOverlay(
                icon: "doc.on.doc.fill",
                iconColor: PSDesignColors.warning,
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
                ? "Batch mode on. Tap Capture, or wait for auto-open."
                : "Batch mode on. Tap Capture for each product."
        } else {
            showBatchCameraAlert = false
            instruction = "Single mode. Tap Capture to begin."
        }
        resetCaptureStatusText()
    }

    private func prepareBatchSession(promptIfNeeded: Bool) {
        batchSessionStartCount = session.products.count
        batchContinuousPaused = false
        session.resetBatchCameraSession()
        guard promptIfNeeded else { return }
        if session.hasBatchAutoOpenPreference {
            if session.batchAutoOpenCamera { scheduleAutoOpenCamera(after: 0.5) }
        } else {
            showBatchCameraAlert = true
        }
    }

    private func toggleCaptureNameMode() {
        let switchingToCustom = !captureUsesCustomName
        InteractionHaptics.selection(vibrate: session.vibrateEnabled)
        nameEntryHint = nil
        manualUPCFocused = false
        DispatchQueue.main.async {
            captureUsesCustomName = switchingToCustom
            if !switchingToCustom {
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
        if showNativeCamera { showNativeCamera = false }
        manualUPCFocused = false
        nameEntryHint = nil
        showManualUPCEntry = false
        presentScannerSoon(after: 0.45, message: "Point the camera at the barcode to scan.")
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
        guard session.currentImage != nil || session.isAwaitingMultiAngleName else {
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
        guard session.currentImage != nil || session.isAwaitingMultiAngleName else {
            nameEntryHint = "Capture the product photo first."
            return
        }
        handleName(manualNameInput)
    }

    private func scheduleAutoScrollAfterCapture() {
        captureAutoScrollGeneration += 1
        let generation = captureAutoScrollGeneration

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 80_000_000)

            for _ in 0..<8 {
                guard generation == captureAutoScrollGeneration,
                      generation != consumedAutoScrollGeneration else { return }
                if hasConfirmedWorkflow, shouldShowIdentification { break }
                await Task.yield()
                try? await Task.sleep(nanoseconds: 75_000_000)
            }

            guard generation == captureAutoScrollGeneration,
                  generation != consumedAutoScrollGeneration,
                  hasConfirmedWorkflow,
                  shouldShowIdentification else { return }

            scrollTargetID = postCaptureAutoScrollTarget
            consumedAutoScrollGeneration = generation
        }
    }

    private var postCaptureAutoScrollTarget: String {
        if session.isAwaitingMultiAngleName, session.currentImage == nil {
            return CaptureScrollID.identifyProduct
        }
        if session.currentImage != nil {
            return CaptureScrollID.retakePhoto
        }
        return CaptureScrollID.identifyProduct
    }

    private func handlePhotoCaptured() {
        if session.multiAngleEnabled {
            let hasMoreAngles = session.bufferCurrentMultiAngleShot()
            if hasMoreAngles {
                instruction = "Saved \(session.pendingMultiAngleCaptures.count)/\(session.activeAngles.count). Now capture \(session.currentAngleLabel)."
                Feedback.success(vibrate: session.vibrateEnabled, beep: session.beepEnabled)
                withAnimation { showAddedToast = true }
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await MainActor.run {
                        withAnimation { showAddedToast = false }
                        if shouldOfferContinuousCapture { scheduleAutoOpenCamera(after: 0.45) }
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
                    scheduleAutoScrollAfterCapture()
                case .randomName:
                    let name = FileNameRules.randomNativeName()
                    instruction = "All angles ready. Applying \(name)-1…"
                    queueMultiAngleSet(name, action: .normal)
                case .manualInput:
                    manualNameInput = ""
                    instruction = "All angles ready. Enter one name for the set."
                    scheduleAutoScrollAfterCapture()
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
            presentScannerSoon(after: 0.4, message: "Point the camera at the barcode — scanning is automatic.")
            scheduleAutoScrollAfterCapture()
        case .randomName:
            let name = FileNameRules.randomNativeName()
            instruction = "Photo captured. Adding random name \(name).jpg..."
            queueCapturedName(name, action: .normal)
        case .manualInput:
            manualNameInput = ""
            instruction = "Photo captured. Enter image name to add it to queue."
            scheduleAutoScrollAfterCapture()
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
                manualUPCFocused = false
                manualNameFocused = false
                withAnimation { activeOverlay = .duplicate }
                return
            }
            queueMultiAngleSet(cleaned, action: .normal)
            return
        }

        guard session.currentImage != nil || session.isAwaitingMultiAngleName else {
            instruction = "Capture product photo first."
            showScanner = false
            return
        }
        let itemAngle = session.multiAngleEnabled ? session.currentCaptureAngle : .none
        if session.duplicateExists(upc: cleaned, angle: itemAngle) {
            pendingDuplicateName = cleaned
            instruction = "Duplicate found for \(cleaned) / \(itemAngle.rawValue). Choose Replace or Add Anyway."
            manualUPCFocused = false
            manualNameFocused = false
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
                                instruction = "Set complete. Product #\(session.nextSequence) ready. Tap Capture."
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
                let hasNextAngle = session.advanceAfterSuccessfulQueue()
                withAnimation { showAddedToast = true }

                Task {
                    try? await Task.sleep(nanoseconds: 750_000_000)
                    await MainActor.run {
                        withAnimation { showAddedToast = false }
                        if hasNextAngle {
                            instruction = "Added. Now capture \(session.currentAngleLabel) for the same product."
                            if shouldOfferContinuousCapture { scheduleAutoOpenCamera(after: 0.65) }
                        } else if activeMode == .batch {
                            if shouldOfferContinuousCapture {
                                instruction = "Product complete. Product #\(session.nextSequence) — camera opening..."
                                scheduleAutoOpenCamera(after: 0.65)
                            } else {
                                instruction = "Product complete. Product #\(session.nextSequence) ready. Tap Capture."
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
    case duplicate

    var id: String {
        switch self {
        case .duplicate: return "duplicate"
        }
    }
}

#if DEBUG
#Preview("Empty Capture") {
    NavigationStack {
        CaptureFlowView(mode: .single)
            .environmentObject(CapturePreviewSupport.makeSession())
    }
}

#Preview("Single Product") {
    NavigationStack {
        CaptureFlowView(mode: .single)
            .environmentObject(CapturePreviewSupport.makeSessionWithCurrentImage())
    }
}

#Preview("Batch") {
    NavigationStack {
        CaptureFlowView(mode: .batch)
            .environmentObject(CapturePreviewSupport.makeSession())
    }
}

#Preview("Multi-Angle") {
    NavigationStack {
        CaptureFlowView(mode: .single)
            .environmentObject(CapturePreviewSupport.makeMultiAngleSession())
    }
}

#Preview("Captured Product") {
    NavigationStack {
        CaptureFlowView(mode: .single)
            .environmentObject(CapturePreviewSupport.makeSessionWithCurrentImage())
    }
    .preferredColorScheme(.dark)
}

#Preview("Dark Mode") {
    NavigationStack {
        CaptureFlowView(mode: .single)
            .environmentObject(CapturePreviewSupport.makeSession())
    }
    .preferredColorScheme(.dark)
}
#endif
