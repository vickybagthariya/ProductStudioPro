import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

private struct PreviewEditSnapshot {
    let panelPolishEnabled: Bool
    let panelMode: PhotoEnhancementMode
    let panelStrength: StudioAIStrength
    let panelFillRatio: Double
    let panelCanvasWidth: Int
    let panelCanvasHeight: Int
    let panelBackgroundColor: Color
    let panelSecondaryBackgroundColor: Color
    let panelBackgroundStyle: BackgroundCanvasStyle
    let panelGradientHexes: [String]
    let panelBackgroundFillSpec: BackgroundFillSpec
    let panelSelectedPresetID: String?
    let panelRotationDegrees: Double
    let panelFlipHorizontal: Bool
    let panelFlipVertical: Bool
    let panelPhotoFilter: ExportPhotoFilter
    let panelPhotoFilterIntensity: Double
    let panelAdjustAutoEnhance: Bool
    let panelToneAdjustments: ManualToneAdjustments
    let panelCutoutFeather: Double
    let panelCutoutBrushMaskData: Data?
    let panelStudioShadow: SoftSyntheticShadowSettings
    let panelSuppressBrandMark: Bool
    /// Display preview at snapshot time (may include filters on raster).
    let draftJPEG: Data?
    /// Markup merge without filters — used to re-apply filter sliders correctly.
    let draftRasterBaseJPEG: Data?
    let draftIsRasterEdit: Bool
    let draftSourceProductID: UUID?
}

private enum PreviewMarkupConflictKind {
    case backgroundRebuild
    case fullReprocess
}

/// Draft preview cost / blocking tradeoff.
private enum DraftPreviewQuality {
    /// Low-res, no blocking HUD — used while dragging sliders.
    case interactive
    /// Balanced edit preview.
    case standard
    /// Near-export draft resolution.
    case final
}

private struct PreviewMarkupConflict: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let onKeepMarkup: () -> Void
    let onRebuildWithoutMarkup: () -> Void
}

/// Lightweight, value-type snapshot of every active edit that changes how the canvas is composited.
///
/// This is the "instruction set" for the non-destructive pipeline: whenever it changes the preview
/// is re-rendered from scratch off the pristine `uncompressedOriginalImage` via Core Image, so edits
/// never stack on top of an already-processed bitmap (no generational blur). Photo filters / intensity
/// are intentionally excluded — they are tuned on top of the cached filter-neutral composite.
struct EditingAdjustmentState: Equatable {
    var selectedStyle: PhotoEnhancementMode
    var studioStrength: StudioAIStrength
    var polishEnabled: Bool
    var backgroundFillType: BackgroundFillKind
    var backgroundAngle: Double
    var backgroundFillSpec: BackgroundFillSpec
    var primaryBackgroundHex: String
    var secondaryBackgroundHex: String
    var fillRatio: Double
    var canvasWidth: Int
    var canvasHeight: Int
    var flipHorizontal: Bool
    var flipVertical: Bool
}

struct ImagePreviewPagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loadingState) private var loadingState
    @EnvironmentObject private var session: CaptureSessionStore
    let initialIndex: Int

    @State private var selectedIndex: Int = 0
    @State private var sharePayload: SharePayload?
    /// 0 = full processed preview, 1 = full original; in-between shows a split.
    @State private var beforeAfterSplit: CGFloat = 0
    @State private var draftSourceProductID: UUID?
    @State private var panelPolishEnabled = true
    @State private var aiPolishEnhanceApplied = false
    @State private var panelMode: PhotoEnhancementMode = CatalogProcessingBaseline.mode
    @State private var panelStrength: StudioAIStrength = CatalogProcessingBaseline.strength
    @State private var panelFillRatio: Double = 0.95
    @State private var panelCanvasWidth: Int = 1200
    @State private var panelCanvasHeight: Int = 1200
    @State private var panelBackgroundColor: Color = .white
    @State private var panelSecondaryBackgroundColor: Color = Color(UIColor(white: 0.94, alpha: 1.0))
    @State private var panelBackgroundStyle: BackgroundCanvasStyle = .solid
    @State private var panelGradientHexes: [String] = ["#FFFFFF"]
    @State private var panelBackgroundFillSpec: BackgroundFillSpec = .catalogWhite
    @State private var panelSelectedPresetID: String?
    @State private var panelGradientGroupID: String = GradientPresetGroupLibrary.all.first?.id ?? "sunset-vibes"
    @State private var panelRotationDegrees: Double = 0
    @State private var panelFlipHorizontal = false
    @State private var panelFlipVertical = false
    @State private var panelPhotoFilter: ExportPhotoFilter = .none
    @State private var panelPhotoFilterIntensity: Double = 1.0
    @State private var panelAdjustAutoEnhance = false
    @State private var panelToneAdjustments: ManualToneAdjustments = .neutral
    @State private var panelCutoutFeather: Double = 0.35
    @State private var panelCutoutBrushMaskData: Data?
    @State private var panelStudioShadow: SoftSyntheticShadowSettings = .off
    @State private var panelHistogram: ExposureHistogramSnapshot?
    @State private var straightenCommitBaseline: Double?
    @State private var fillCommitBaseline: Double?
    @State private var isDraggingStraighten = false
    @State private var isDraggingFill = false
    @State private var isDraggingStyleIntensity = false
    /// Interactive = low-res / no HUD; standard = edit preview; final = near-export draft.
    @State private var draftPreviewQuality: DraftPreviewQuality = .standard
    @State private var panelSuppressBrandMark = false
    @State private var undoSnapshots: [PreviewEditSnapshot] = []
    @State private var redoSnapshots: [PreviewEditSnapshot] = []

    @State private var hasPendingChanges = false
    @State private var draftPreviewImage: UIImage?
    @State private var isRenderingDraft = false
    @State private var isApplying = false
    @State private var showAppliedToast = false
    @State private var renderTask: Task<Void, Never>?
    @State private var liveRenderTask: Task<Void, Never>?

    @State private var showPendingNavigationAlert = false
    @State private var showPendingDoneAlert = false
    @State private var showRenameAlert = false
    @State private var previewRenameText = ""
    @State private var pendingNavigationIndex: Int?
    @State private var showGradientEditorSheet = false
    @State private var showPreviewShareDialog = false
    @State private var showShareUnsavedOptions = false
    @State private var pendingPreviewCSVAsk: PreviewShareCSVAsk?
    @State private var showMarkupEditor = false
    /// Markup save produced a full bitmap; filter-only tweaks apply on top until canvas/background changes.
    @State private var draftIsRasterEdit = false
    /// Unfiltered Markup merge; photo filters always tune from this, not the last filtered bitmap.
    @State private var draftRasterBaseImage: UIImage?
    /// Composited preview without filters — filter slider changes tune this only (avoids re-cutout stains).
    @State private var draftFilterBaseImage: UIImage?
    @State private var draftRenderGeneration: UInt = 0
    /// Cached subject cutout for fast image-background browsing (Vision runs once per product).
    @State private var draftBackgroundCutout: UIImage?
    @State private var draftBackgroundCutoutProductID: UUID?
    @State private var draftBackgroundCutoutPrepTask: Task<Void, Never>?
    @State private var draftRenderedBackgroundToken: String?
    @State private var showCustomCanvasSizeSheet = false
    @State private var customCanvasWidthText = ""
    @State private var customCanvasHeightText = ""
    @State private var showEditPolishSheet = false
    @State private var gradientPresetScrollRequestID = UUID()
    @State private var showImageBackgroundSheet = false
    @State private var showImageBackgroundVisualEditor = false
    @State private var formatBackgroundSheetDetent: PresentationDetent = .medium
    @State private var formatBackgroundSessionBaseline: BackgroundFillSpec?
    @State private var showFormatBackgroundLeaveAlert = false
    @State private var panelImageCategory: ImageBackgroundCategory = ImageBackgroundFolderCatalog.categories.first ?? .importedCustom
    @State private var imagePresetScrollRequestID = UUID()
    @State private var isMatchingProductColors = false
    @State private var matchColorsGeneration = 0
    @State private var matchProductColorsFailureMessage: String?
    @State private var matchProductColorsFailureClearTask: Task<Void, Never>?
    @State private var previewEditLift: CGFloat = 0
    @State private var showFullScreenZoom = false
    @State private var showPhotoInfoSheet = false
    @State private var showDeleteConfirmAlert = false
    @State private var previewZoomScale: CGFloat = 1
    @State private var pinchMagnificationAnchor: CGFloat = 1
    @State private var previewPanBase: CGSize = .zero
    @State private var previewPanGesture: CGSize = .zero
    @State private var fullscreenZoomResetNonce: String = ""
    /// Rotation baked into the current draft bitmap — live slider delta rotates on top for smooth straighten.
    @State private var draftBakedRotationDegrees: Double = 0
    @State private var straightenRenderTask: Task<Void, Never>?
    @State private var postShareRemovalCandidates: [UUID] = []
    @State private var showPostShareRemoveConfirm = false
    @State private var showReplaceCamera = false
    @State private var markupConflict: PreviewMarkupConflict?
    @State private var showGroupedCoverEditor = false
    #if DEBUG
    @State private var showPipelineCompare = false
    #endif
    @State private var groupedCoverNameText = ""
    @State private var groupedCoverExistingLayout: CompositeBundleLayout?
    @State private var alignedBeforeCompareImage: UIImage?
    /// Token that `alignedBeforeCompareImage` was built for (avoids stale before frames).
    @State private var alignedBeforeCompareToken: BeforeCompareToken?
    @State private var isPreparingBeforeCompare = false
    @State private var beforeCompareUnavailableReason: String?

    /// Stable compare key — must NOT embed `GradientColorStop.id` (normalizeStops regenerates UUIDs).
    private struct BeforeCompareToken: Equatable {
        let productID: UUID
        let canvasW: Int
        let canvasH: Int
        let fillRatio: Double
        let rotation: Double
        let flipH: Bool
        let flipV: Bool
        let alignToCutout: Bool
        let fillFingerprint: String
        /// Busts cache when the After bitmap instance changes (draft re-render).
        let afterImageID: ObjectIdentifier
        /// Bump when Before align algorithm changes so stale bitmaps are discarded.
        let alignVersion: Int
    }

    private var currentProduct: CapturedProduct? {
        guard !session.products.isEmpty else { return nil }
        let safeIndex = min(max(0, selectedIndex), session.products.count - 1)
        return session.products[safeIndex]
    }

    private var hidePhotoFilmstrip: Bool {
        previewBottomSheetOpen
    }

    /// Pinned Format Background or slide-up Edit & Polish — hides canvas overlay hints.
    private var previewBottomSheetOpen: Bool {
        showEditPolishSheet || showGradientEditorSheet
    }

    /// Slide-up / full-screen tool panels — auto-hide the top icon tray.
    private var previewTopToolbarObscured: Bool {
        showEditPolishSheet
            || showGradientEditorSheet
            || showMarkupEditor
            || showCustomCanvasSizeSheet
            || showGroupedCoverEditor
            || showImageBackgroundVisualEditor
    }

    private var groupedCoverEditSources: [CapturedProduct] {
        guard let product = currentProduct, let layout = product.compositeBundleLayout else { return [] }
        return layout.sourceProductIDs.compactMap { id in
            session.products.first { $0.id == id }
        }
    }

    private var canEditGroupedCover: Bool {
        guard let product = currentProduct, product.isGroupedCoverItem else { return false }
        guard let layout = product.compositeBundleLayout, layout.layers.count >= 2 else { return false }
        return groupedCoverEditSources.count >= 2
    }

    private func resetPreviewZoom() {
        previewZoomScale = 1
        pinchMagnificationAnchor = 1
        previewPanBase = .zero
        previewPanGesture = .zero
        fullscreenZoomResetNonce = UUID().uuidString
    }

    private var previewVisualPanOffset: CGSize {
        CGSize(
            width: previewPanBase.width + previewPanGesture.width,
            height: previewPanBase.height + previewPanGesture.height
        )
    }

    /// Extra rotation applied live while straighten slider moves ahead of the baked draft.
    private var previewLiveRotationDelta: Double {
        guard hasPendingChanges, draftSourceProductID == currentProduct?.id else { return 0 }
        return panelRotationDegrees - draftBakedRotationDegrees
    }

    @ViewBuilder
    private func previewZoomableCanvas(
        image: UIImage,
        product: CapturedProduct,
        allowsSubjectLift: Bool,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let liftEnabled = allowsSubjectLift
            && !previewBottomSheetOpen
            && !showPhotoInfoSheet
            && SubjectLiftSafety.allowsSubjectLift
        Group {
            if #available(iOS 17.0, *) {
                PreviewZoomSubjectLiftHost(
                    image: image,
                    allowsSubjectLift: liftEnabled,
                    zoomScale: $previewZoomScale,
                    pinchAnchor: $pinchMagnificationAnchor,
                    panBase: $previewPanBase,
                    panGesture: $previewPanGesture,
                    onReset: resetPreviewZoom,
                    onSwipeUp: { openPreviewPhotoInfoSheet(from: product) }
                )
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .previewCanvasZoomGestures(
                        zoomScale: $previewZoomScale,
                        pinchAnchor: $pinchMagnificationAnchor,
                        panBase: $previewPanBase,
                        panGesture: $previewPanGesture,
                        onReset: resetPreviewZoom
                    )
            }
        }
        .frame(width: width, height: height)
        .scaleEffect(previewZoomScale, anchor: .center)
        .offset(previewVisualPanOffset)
        .frame(width: width, height: height)
        .clipped()
        .rotationEffect(.degrees(previewLiveRotationDelta))
        .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.88), value: previewLiveRotationDelta)
    }

    @ViewBuilder
    private func previewPhotoInfoSwipeOverlay(for product: CapturedProduct) -> some View {
        let enabled = currentProduct?.id == product.id
            && !showPhotoInfoSheet
            && previewZoomScale <= 1.08
        PreviewInfoSwipeUpBridge(isEnabled: enabled) {
            openPreviewPhotoInfoSheet(from: product)
        }
    }

    private var fullscreenZoomResetToken: String {
        guard let product = currentProduct else { return "empty" }
        return "\(product.id.uuidString)-\(fullscreenZoomResetNonce)"
    }

    private func canvasEffectiveFill(for product: CapturedProduct?) -> Double {
        guard let product else { return panelFillRatio }
        return ImageProcessor.effectiveLayoutFillRatio(
            canvasWidth: panelCanvasWidth,
            canvasHeight: panelCanvasHeight,
            imageSize: QueueImageResolver.sourcePixelSize(for: product),
            rotationDegrees: panelRotationDegrees,
            baseFill: panelFillRatio
        )
    }

    @ViewBuilder
    private var previewAppliedToastOverlay: some View {
        if showAppliedToast {
            VStack {
                Spacer()
                Label("Applied", systemImage: "checkmark.circle.fill")
                    .font(DS.TypeScale.bodyEmphasis)
                    .foregroundStyle(DSPhotoOverlay.primaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(DSPhotoOverlay.scrim, in: Capsule())
                    .overlay(Capsule().stroke(DSPhotoOverlay.stroke, lineWidth: 1))
                    .shadow(color: DS.Shadow.card.color, radius: 10, x: 0, y: 4)
                    .padding(.bottom, 120)
            }
            .transition(.opacity)
        }
    }

    private func updatePreviewEditLift() {
        let screenH = UIScreen.main.bounds.height
        let lift: CGFloat = {
            if showEditPolishSheet || showGradientEditorSheet { return -(screenH * 0.26) }
            return 0
        }()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            previewEditLift = lift
        }
    }

    @ViewBuilder
    private func liftedInteractivePreview(for product: CapturedProduct) -> some View {
        photosTabPager
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, hidePhotoFilmstrip ? 0 : 4)
            .offset(y: previewEditLift)
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: previewEditLift)
            .safeAreaInset(edge: .bottom, spacing: 8) {
                if !previewBottomSheetOpen {
                    photosLibraryBottomChrome
                }
            }
    }

    private var previewPagerSelection: Binding<Int> {
        Binding(
            get: { selectedIndex },
            set: { newIndex in
                guard newIndex != selectedIndex else { return }
                if hasPendingChanges {
                    pendingNavigationIndex = newIndex
                    showPendingNavigationAlert = true
                } else {
                    moveToIndex(newIndex)
                }
            }
        )
    }

    private var photosTabPager: some View {
        TabView(selection: previewPagerSelection) {
            ForEach(Array(session.products.enumerated()), id: \.element.id) { index, product in
                previewPhotoPage(for: product)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var photosLibraryBottomChrome: some View {
        Group {
            if !hidePhotoFilmstrip {
                VStack(spacing: 8) {
                    PreviewDockSubtitleText(text: "Long-press object to lift, copy, or share")
                        .padding(.horizontal, DS.Space.screenHorizontal)
                        .accessibilityLabel("Long-press the object to lift, copy, or share it")

                    DSPreviewDockTray {
                        PhotosFilmstripView(
                            products: session.products,
                            selectedIndex: $selectedIndex,
                            thumbnail: { thumbImage(for: $0) },
                            onSelect: { requestNavigation(to: $0) }
                        )
                        PhotosLibraryActionBar(
                            onShare: {
                                if hasPendingChanges { showShareUnsavedOptions = true }
                                else { showPreviewShareDialog = true }
                            },
                            onEnhance: { applyAIPolishEnhancement() },
                            onEdit: { openEditPolishPanel() },
                            onBackground: { openFormatBackgroundPanel() },
                            onMarkup: { showMarkupEditor = true },
                            onInfo: {
                                guard let product = currentProduct else { return }
                                openPreviewPhotoInfoSheet(from: product)
                            },
                            onDelete: { showDeleteConfirmAlert = true },
                            polishEnabled: aiPolishEnhanceApplied,
                            isEnhanceProcessing: isRenderingDraft && aiPolishEnhanceApplied,
                            deleteEnabled: currentProduct != nil
                        )
                    }
                }
            }
        }
    }

    private func thumbImage(for product: CapturedProduct) -> UIImage {
        if let d = draftPreviewImage, draftSourceProductID == product.id { return d }
        return product.image
    }

    private func previewInfoDisplayImage(for product: CapturedProduct) -> UIImage {
        if hasPendingChanges, let draft = draftPreviewImage, draftSourceProductID == product.id {
            return draft
        }
        return product.image
    }

    /// Split from `body` so the Swift type checker can finish in reasonable time.
    private var previewPagerNavigationStack: some View {
        previewPagerRoot
            .onChange(of: showEditPolishSheet) { _, isOpen in
                updatePreviewEditLift()
                resetPreviewZoom()
                syncMagicPreviewOverlay()
                if !isOpen, !hasPendingChanges {
                    cancelDraftRender()
                    draftPreviewImage = nil
                    draftFilterBaseImage = nil
                    draftRasterBaseImage = nil
                    draftSourceProductID = nil
                    isRenderingDraft = false
                    syncMagicPreviewOverlay()
                }
            }
            .onChange(of: showGradientEditorSheet) { _, isOpen in
                updatePreviewEditLift()
                resetPreviewZoom()
                syncMagicPreviewOverlay()
                if isOpen {
                    formatBackgroundSessionBaseline = panelBackgroundFillSpec
                    gradientPresetScrollRequestID = UUID()
                    prepareDraftBackgroundCutoutIfNeeded()
                } else {
                    formatBackgroundSessionBaseline = nil
                }
            }
            .onChange(of: showImageBackgroundVisualEditor) { _, isOpen in
                updatePreviewEditLift()
                if !isOpen {
                    liveRenderTask?.cancel()
                    liveRenderTask = nil
                    if hasPendingChanges, !draftIsRasterEdit {
                        scheduleFastBackgroundPreview(debounceNanoseconds: 0)
                    } else {
                        syncMagicPreviewOverlay()
                    }
                }
            }
            .onChange(of: editingAdjustmentState) { _, _ in handleAdjustmentStateChange() }
            .onAppear {
                selectedIndex = min(max(0, initialIndex), max(0, session.products.count - 1))
                if !session.products.isEmpty {
                    let idx = min(max(0, selectedIndex), session.products.count - 1)
                    session.ensureProcessedImageInMemory(productID: session.products[idx].id)
                }
                resetPreviewZoom()
                resetPanelFromCurrentProduct()
                session.setPreviewPanelOpen(true)
            }
            .onDisappear {
                resetPreviewZoom()
                session.setPreviewPanelOpen(false)
            }
            .onChange(of: session.products.count) { oldCount, newCount in
                guard newCount > 0 else {
                    selectedIndex = 0
                    return
                }
                selectedIndex = min(max(0, selectedIndex), newCount - 1)
                if newCount > oldCount {
                    resetPreviewZoom()
                    resetPanelFromCurrentProduct()
                }
            }
            .onChange(of: "\(currentProduct?.canvasWidth ?? 0)x\(currentProduct?.canvasHeight ?? 0)") { _, _ in
                guard let p = currentProduct else { return }
                guard panelCanvasWidth != p.canvasWidth || panelCanvasHeight != p.canvasHeight else { return }
                panelCanvasWidth = p.canvasWidth
                panelCanvasHeight = p.canvasHeight
                if hasPendingChanges { scheduleDraftRender() }
            }
            .onChange(of: session.blockingOperationDepth) { oldDepth, newDepth in
                if oldDepth > 0, newDepth == 0 {
                    // Do not wipe in-progress canvas drafts when a blocking job ends
                    // (including Apply's popBlocking racing ahead of finishApply).
                    if !hasPendingChanges {
                        resetPanelFromCurrentProduct()
                    }
                }
                syncMagicPreviewOverlay()
            }
            .onChange(of: isRenderingDraft) { _, _ in syncMagicPreviewOverlay() }
            .onChange(of: isApplying) { _, _ in syncMagicPreviewOverlay() }
            .onChange(of: isMatchingProductColors) { _, _ in syncMagicPreviewOverlay() }
    }

    // MARK: - Preview top toolbar (single unified pill, plain icons)

    private struct PreviewTopToolbarMetrics {
        let iconSpacing: CGFloat
        let trackPaddingH: CGFloat
        let trackPaddingV: CGFloat
        let iconSide: CGFloat
        let symbolSize: CGFloat

        static let regular = PreviewTopToolbarMetrics(
            iconSpacing: 4,
            trackPaddingH: 14,
            trackPaddingV: 9,
            iconSide: 38,
            symbolSize: 17
        )
        static let compact = PreviewTopToolbarMetrics(
            iconSpacing: 2,
            trackPaddingH: 12,
            trackPaddingV: 8,
            iconSide: 34,
            symbolSize: 16
        )
        static let tight = PreviewTopToolbarMetrics(
            iconSpacing: 0,
            trackPaddingH: 10,
            trackPaddingV: 7,
            iconSide: 30,
            symbolSize: 15
        )
    }

    /// Approximate height reserved for the floating top chrome (toolbar + apply + filename).
    private var previewTopChromeReservedHeight: CGFloat {
        previewTopToolbarObscured ? 0 : (hasPendingChanges ? 152 : 118)
    }

    @ViewBuilder
    private func previewToolbarIconLabel(_ systemName: String, metrics: PreviewTopToolbarMetrics) -> some View {
        PreviewToolbarIconLabel(
            systemName: systemName,
            side: metrics.iconSide,
            symbolSize: metrics.symbolSize
        )
    }

    @ViewBuilder
    private func previewToolbarTransformMenu(metrics: PreviewTopToolbarMetrics) -> some View {
        DSDropdownActionMenu(
            label: {
                // Rotate glyph — avoid arrow.triangle.2.circlepath, which reads as “refresh”.
                previewToolbarIconLabel("crop.rotate", metrics: metrics)
            },
            items: [
                .action("rotate-left", "Rotate left"),
                .action("rotate-right", "Rotate right"),
                .divider("transform-divider"),
                .action("flip-h", "Flip horizontal"),
                .action("flip-v", "Flip vertical"),
                .action("flip-both", "Flip both axes"),
            ]
        ) { item in
            switch item.id {
            case "rotate-left": bumpPreviewRotation(degrees: -90)
            case "rotate-right": bumpPreviewRotation(degrees: 90)
            case "flip-h": toggleFlipHorizontal()
            case "flip-v": toggleFlipVertical()
            case "flip-both": toggleFlipBoth()
            default: break
            }
        }
        .accessibilityLabel("Transform")
    }

    @ViewBuilder
    private func previewToolbarOverflowMenu(metrics: PreviewTopToolbarMetrics) -> some View {
        DSDropdownActionMenu(
            label: {
                previewToolbarIconLabel("ellipsis", metrics: metrics)
            },
            items: previewToolbarOverflowItems,
            isEnabled: currentProduct != nil
        ) { item in
            handlePreviewToolbarOverflowAction(item)
        }
    }

    private var previewToolbarOverflowItems: [DSDropdownActionItem] {
        // Reset / Share live on dedicated tray buttons — keep More for less-frequent tools.
        var items: [DSDropdownActionItem] = [
            .action("rename", "Edit Name"),
            .action("defringe", "Fix edges (de-fringe)"),
            .divider("overflow-divider-1"),
            .action("standard-clean", "Standard Clean"),
        ]
        if session.brandMarkEnabled {
            items.append(.divider("overflow-brand-mark-divider"))
            items.append(.action(
                "hide-brand-mark",
                "Hide Brand Mark",
                systemImage: "seal.slash",
                isSelected: panelSuppressBrandMark
            ))
        }
        items.append(.divider("overflow-divider-3"))
        items.append(.action("replace", "Replace"))
        if currentProduct?.upscaled == true {
            items.append(.action("descale", "Remove upscale (descale)"))
        }
        #if DEBUG
        items.append(.divider("overflow-debug-divider"))
        items.append(.action(
            "pipeline-compare",
            "Pipeline Compare",
            systemImage: "wrench.and.screwdriver"
        ))
        #endif
        return items
    }

    private func handlePreviewToolbarOverflowAction(_ item: DSDropdownActionItem) {
        switch item.id {
        case "rename": startPreviewRename()
        case "defringe":
            if let p = currentProduct { previewApplyDefringeSharpen(to: p) }
        case "standard-clean": previewQueueQuickApply(mode: .standardClean, strength: CatalogProcessingBaseline.strength)
        case "hide-brand-mark":
            previewToggleHideBrandMark()
        case "replace": previewStartReplace()
        case "descale":
            if let p = currentProduct {
                session.revertLegacyUpscale(to: p) { resetPanelFromCurrentProduct() }
            }
        #if DEBUG
        case "pipeline-compare":
            showPipelineCompare = true
        #endif
        default: break
        }
    }

    private func previewToggleHideBrandMark() {
        guard let product = currentProduct, !isApplying else { return }
        let next = !panelSuppressBrandMark
        cancelDraftRender()
        beforeAfterSplit = 0
        hasPendingChanges = false
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
        draftPreviewImage = nil
        draftFilterBaseImage = nil
        draftRasterBaseImage = nil
        draftIsRasterEdit = false
        panelSuppressBrandMark = next
        StylePreviewCacheRevisionStore.shared.invalidate(productID: product.id, reason: "brand mark override")
        session.setSuppressBrandMark(next, for: product) {
            resetPanelFromCurrentProduct()
        }
    }

    /// Queue & Share row actions (trimmed); reset lives on the top tray; delete on the bottom dock.

    /// True when the on-screen preview has been altered vs a pristine original / saved baseline.
    private func previewImageIsAltered(from product: CapturedProduct) -> Bool {
        if hasPendingChanges { return true }
        if !undoSnapshots.isEmpty || !redoSnapshots.isEmpty { return true }
        if draftIsRasterEdit, draftSourceProductID == product.id { return true }
        if !previewPanelMatchesSavedProduct(product) { return true }
        // Saved product already has post-capture edits worth resetting to original.
        if product.backgroundRemoved { return true }
        if abs(product.rotationDegrees) >= 0.01 { return true }
        if product.flipHorizontal || product.flipVertical { return true }
        if product.photoFilter != .none { return true }
        if product.adjustAutoEnhance { return true }
        if product.upscaled { return true }
        let fillKey = beforeCompareFillFingerprint(product.resolvedBackgroundFillSpec)
        let whiteKey = beforeCompareFillFingerprint(.catalogWhite)
        if fillKey != whiteKey { return true }
        return false
    }

    private func previewResetToSession() {
        guard previewResetEnabled, let product = currentProduct else { return }
        guard !isApplying else { return }
        cancelDraftRender()
        hasPendingChanges = false
        beforeAfterSplit = 0
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
        StylePreviewCacheRevisionStore.shared.invalidate(productID: product.id, reason: "reset to session")
        session.resetProductToOriginal(product) {
            resetPanelFromCurrentProduct()
            resetPreviewZoom()
        }
    }

    private func previewPanelMatchesSavedProduct(_ product: CapturedProduct) -> Bool {
        guard panelPolishEnabled == product.polishEnabled else { return false }
        guard panelMode == product.enhancementMode else { return false }
        guard panelStrength == product.studioAIStrength else { return false }
        guard abs(panelFillRatio - product.fillRatio) < 0.0001 else { return false }
        guard panelCanvasWidth == product.canvasWidth, panelCanvasHeight == product.canvasHeight else { return false }
        guard abs(panelRotationDegrees - product.rotationDegrees) < 0.01 else { return false }
        guard panelFlipHorizontal == product.flipHorizontal, panelFlipVertical == product.flipVertical else { return false }
        guard panelPhotoFilter == product.photoFilter else { return false }
        guard abs(panelPhotoFilterIntensity - product.photoFilterIntensity) < 0.001 else { return false }
        guard panelAdjustAutoEnhance == product.adjustAutoEnhance else { return false }
        guard panelToneAdjustments == product.toneAdjustments else { return false }
        guard abs(panelCutoutFeather - product.cutoutFeather) < 0.001 else { return false }
        guard panelCutoutBrushMaskData == product.cutoutBrushMaskData else { return false }
        guard panelStudioShadow == product.studioShadow else { return false }
        guard panelSuppressBrandMark == product.suppressBrandMark else { return false }
        // Compare content fingerprints — GradientColorStop.id regenerates in normalizeStops and breaks Equatable.
        return beforeCompareFillFingerprint(panelBackgroundFillSpec)
            == beforeCompareFillFingerprint(product.resolvedBackgroundFillSpec)
    }

    private var previewResetEnabled: Bool {
        guard let product = currentProduct else { return false }
        // Do not grey-out during Apply — that looked "inverted" (altered yet untappable).
        return previewImageIsAltered(from: product)
    }

    @ViewBuilder
    private func previewToolbarResetButton(metrics: PreviewTopToolbarMetrics) -> some View {
        let enabled = previewResetEnabled
        FeedbackIconButton(
            systemName: "arrow.counterclockwise",
            side: metrics.iconSide,
            symbolSize: metrics.symbolSize,
            isEnabled: enabled,
            accessibilityLabel: enabled ? "Reset to original" : "Reset unavailable — photo not altered",
            action: {
                previewResetToSession()
            }
        )
    }

    @ViewBuilder
    private func previewTopIconsTrayTrack(metrics: PreviewTopToolbarMetrics) -> some View {
        DSPreviewFloatingToolbar(
            horizontalPadding: metrics.trackPaddingH,
            verticalPadding: metrics.trackPaddingV
        ) {
            HStack(spacing: 0) {
                FeedbackIconButton(
                    systemName: "chevron.left",
                    side: metrics.iconSide,
                    symbolSize: metrics.symbolSize,
                    accessibilityLabel: "Close preview",
                    action: {
                        if hasPendingChanges { showPendingDoneAlert = true } else { dismiss() }
                    }
                )

                Spacer(minLength: metrics.iconSpacing)

                FeedbackIconButton(
                    systemName: "arrow.uturn.backward",
                    side: metrics.iconSide,
                    symbolSize: metrics.symbolSize,
                    isEnabled: !undoSnapshots.isEmpty,
                    accessibilityLabel: "Undo",
                    action: undoLastEditSnapshot
                )

                Spacer(minLength: metrics.iconSpacing)

                FeedbackIconButton(
                    systemName: "arrow.uturn.forward",
                    side: metrics.iconSide,
                    symbolSize: metrics.symbolSize,
                    isEnabled: !redoSnapshots.isEmpty,
                    accessibilityLabel: "Redo",
                    action: redoLastEditSnapshot
                )

                Spacer(minLength: metrics.iconSpacing)

                if canEditGroupedCover {
                    FeedbackIconButton(
                        systemName: "square.grid.2x2",
                        side: metrics.iconSide,
                        symbolSize: metrics.symbolSize,
                        accessibilityLabel: "Edit grouped cover",
                        action: openGroupedCoverEditorForCurrentProduct
                    )

                    Spacer(minLength: metrics.iconSpacing)
                }

                previewToolbarTransformMenu(metrics: metrics)

                Spacer(minLength: metrics.iconSpacing)

                previewToolbarOverflowMenu(metrics: metrics)

                Spacer(minLength: metrics.iconSpacing)

                previewToolbarResetButton(metrics: metrics)

                Spacer(minLength: metrics.iconSpacing)

                FeedbackIconButton(
                    systemName: "plus.square.on.square",
                    side: metrics.iconSide,
                    symbolSize: metrics.symbolSize,
                    isEnabled: !isRenderingDraft && !isApplying && currentProduct != nil,
                    accessibilityLabel: "Save as duplicate",
                    action: saveAsDuplicateFromEditPanel
                )

                Spacer(minLength: metrics.iconSpacing)

                FeedbackIconButton(
                    systemName: "arrow.up.left.and.arrow.down.right",
                    side: metrics.iconSide,
                    symbolSize: metrics.symbolSize,
                    isEnabled: currentProduct != nil,
                    accessibilityLabel: "Fullscreen",
                    action: { showFullScreenZoom = true }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: metrics.iconSide)
        }
    }

    private func openPreviewPhotoInfoSheet(from product: CapturedProduct) {
        guard currentProduct?.id == product.id else { return }
        guard !showPhotoInfoSheet else { return }
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)
        showPhotoInfoSheet = true
    }

    @ViewBuilder
    private var previewFloatingApplyControl: some View {
        if hasPendingChanges || isApplying {
            HStack(spacing: 10) {
                PreviewDiscardButton(isDisabled: isApplying) {
                    discardPendingPreviewChanges()
                }
                .accessibilityLabel("Discard changes")

                Spacer(minLength: 0)

                PreviewApplyButton(isApplying: isApplying) {
                    guard !isApplying else { return }
                    applyCurrentPanelSettings()
                }
                .accessibilityLabel(isApplying ? "Applying changes" : "Apply changes")
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Revert live preview edits back to the saved queue item (does not leave the screen).
    private func discardPendingPreviewChanges() {
        guard hasPendingChanges, !isApplying else { return }
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)
        straightenRenderTask?.cancel()
        cancelDraftRender()
        resetPanelFromCurrentProduct()
        resetPreviewZoom()
        if showGradientEditorSheet {
            formatBackgroundSessionBaseline = panelBackgroundFillSpec
        }
    }

    /// Unified pill tray — stays above canvas content for reliable taps.
    private var previewTopIconsTray: some View {
        ViewThatFits(in: .horizontal) {
            previewTopIconsTrayTrack(metrics: .regular)
            previewTopIconsTrayTrack(metrics: .compact)
            previewTopIconsTrayTrack(metrics: .tight)
        }
        .padding(.horizontal, DS.Space.screenHorizontal)
    }

    @ViewBuilder
    private var previewTopChrome: some View {
        VStack(spacing: 6) {
            previewTopIconsTray
            previewFloatingApplyControl
                .padding(.horizontal, DS.Space.screenHorizontal)
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: hasPendingChanges)
            previewTopMetadataBar
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var previewPagerNavShell: some View {
        NavigationStack {
            ZStack {
                PreviewChrome.pageBackground(for: colorScheme).ignoresSafeArea()
                if session.products.isEmpty {
                    Text("No images to preview")
                        .font(DS.TypeScale.body)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                } else {
                    Group {
                        if session.products.isEmpty == false {
                            liftedInteractivePreview(for: session.products[min(max(0, selectedIndex), session.products.count - 1)])
                                .padding(.top, previewTopChromeReservedHeight)
                        }

                        previewAppliedToastOverlay
                        // Full-screen processing UI lives only in InteractionHUD (above sheets) —
                        // never mount a second MagicPreviewOverlayHost here.
                    }
                }

                if !session.products.isEmpty, !previewTopToolbarObscured {
                    VStack(spacing: 0) {
                        previewTopChrome
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .zIndex(20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.28), value: previewTopToolbarObscured)
            .navigationBarHidden(true)
            .interactiveDismissDisabled(hasPendingChanges)
        }
    }

    private var previewPagerRoot: some View {
        previewPagerNavShell
            .withInteractionFeedback()
            .sheet(isPresented: $showEditPolishSheet) {
                ScrollView {
                    previewEditPolishSheet
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .background(DS.ColorToken.background)
            }
            .sheet(isPresented: $showGradientEditorSheet) {
                ScrollView {
                    previewFormatBackgroundSheet
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .presentationDetents(formatBackgroundPresentationDetents, selection: $formatBackgroundSheetDetent)
                .presentationDragIndicator(.visible)
                .background(DS.ColorToken.background)
                .interactiveDismissDisabled(formatBackgroundSessionHasEdits || showImageBackgroundSheet || showImageBackgroundVisualEditor)
                .onChange(of: showImageBackgroundSheet) { _, isOpen in
                    if isOpen {
                        formatBackgroundSheetDetent = .medium
                        prepareDraftBackgroundCutoutIfNeeded()
                    }
                }
            }
            .sheet(isPresented: $showCustomCanvasSizeSheet) {
                customCanvasSizeSheet
                    .scrollDismissesKeyboard(.interactively)
                    .presentationDetents([.height(320), .medium])
                    .presentationDragIndicator(.visible)
                    .background(DS.ColorToken.background)
            }
            .sheet(isPresented: $showPhotoInfoSheet) {
                if let product = currentProduct {
                    PreviewPhotoInfoSheet(
                        product: product,
                        displayImage: previewInfoDisplayImage(for: product),
                        namingMode: session.imageNamingMode,
                        queueIndex: selectedIndex,
                        queueTotal: session.products.count,
                        showsLivePreviewDraft: hasPendingChanges && draftSourceProductID == product.id && draftPreviewImage != nil,
                        exportJPEGQuality: session.compressBeforeShare ? session.jpegQuality : 1.0,
                        liveCanvasWidth: hasPendingChanges ? panelCanvasWidth : nil,
                        liveCanvasHeight: hasPendingChanges ? panelCanvasHeight : nil
                    )
                    .presentationBackgroundInteraction(.enabled(upThrough: .large))
                }
            }
            #if DEBUG
            .sheet(isPresented: $showPipelineCompare) {
                if let product = currentProduct {
                    PipelineCompareView(product: product)
                }
            }
            #endif
            .alert("Delete this image?", isPresented: $showDeleteConfirmAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteCurrentAndDismissIfNeeded() }
            } message: {
                Text("This removes the photo from the session queue. Files saved elsewhere are not affected.")
            }
            .sheet(item: $sharePayload, onDismiss: {
                loadingState?.endActions(prefix: "preview-export")
                loadingState?.endActions(prefix: "preview-recipe")
            }) { payload in
                ActivityView(activityItems: payload.items) { _, completed, _, _ in
                    Task { @MainActor in
                        sharePayload = nil
                        loadingState?.endActions(prefix: "preview-export")
                        loadingState?.endActions(prefix: "preview-recipe")
                        if completed, !payload.productIDsForRemovalPrompt.isEmpty {
                            postShareRemovalCandidates = payload.productIDsForRemovalPrompt
                            showPostShareRemoveConfirm = true
                        }
                    }
                }
            }
            .alert("Remove shared images from the queue?", isPresented: $showPostShareRemoveConfirm) {
                Button("Keep in queue", role: .cancel) { postShareRemovalCandidates = [] }
                Button("Remove from queue", role: .destructive) {
                    let ids = Set(postShareRemovalCandidates)
                    session.removeProducts(ids: ids)
                    postShareRemovalCandidates = []
                    if session.products.isEmpty { dismiss() }
                    else { selectedIndex = min(selectedIndex, session.products.count - 1); resetPreviewZoom(); resetPanelFromCurrentProduct() }
                }
            } message: {
                Text(postShareRemovalCandidates.count <= 1 ? "Remove the shared photo from this session’s queue? Files you saved elsewhere are not affected." : "Remove \(postShareRemovalCandidates.count) shared photos from this session’s queue? Files you saved elsewhere are not affected.")
            }
            .sheet(isPresented: $showPreviewShareDialog) {
                ExportShareOptionsSheet(
                    title: "Share this image",
                    message: hasPendingChanges && draftPreviewImage != nil && draftSourceProductID == currentProduct?.id
                        ? "Uses the live preview on screen. Recommended: JPG for one photo, ZIP to bundle files."
                        : "Uses the last applied queue pixels. Recommended: JPG for one photo, ZIP to bundle files.",
                    isSingleImage: true,
                    onZip: {
                        runPreviewShare(includeImages: true, includeCSV: true, format: .jpg, asZip: true)
                    },
                    onJPG: { pendingPreviewCSVAsk = .jpg },
                    onPNG: { pendingPreviewCSVAsk = .png },
                    onCSV: { runPreviewShare(includeImages: false, includeCSV: true) }
                )
            }
            .alert("Include CSV manifest?", isPresented: previewCSVAskPresented) {
                Button("Image + CSV") {
                    guard let ask = pendingPreviewCSVAsk else { return }
                    runPreviewShare(includeImages: true, includeCSV: true, format: ask.format)
                    pendingPreviewCSVAsk = nil
                }
                Button("Image only") {
                    guard let ask = pendingPreviewCSVAsk else { return }
                    runPreviewShare(includeImages: true, includeCSV: false, format: ask.format)
                    pendingPreviewCSVAsk = nil
                }
                Button("Cancel", role: .cancel) { pendingPreviewCSVAsk = nil }
            } message: {
                Text(pendingPreviewCSVAsk == .png
                     ? "PNG keeps transparency for cutouts. Add a CSV inventory row?"
                     : "Add a CSV inventory row alongside the JPG?")
            }
            .confirmationDialog("Share with unsaved preview edits?", isPresented: $showShareUnsavedOptions, titleVisibility: .visible) {
                Button("Share original (unprocessed)") { sharePreviewOriginalUnprocessed() }
                Button("Apply changes, then share…") { applyCurrentPanelSettings(openSharePickerOnComplete: true) }
                Button("Share live preview…") { showPreviewShareDialog = true }
                Button("Open share sheet (JPG)") { runPreviewShare(includeImages: true, includeCSV: false, format: .jpg) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Original uses the imported photo. Apply updates the queue first. Live preview and share sheet use what you see on screen.")
            }
            .alert("Unsaved enhancement changes", isPresented: $showPendingNavigationAlert) {
                Button("Cancel", role: .cancel) {
                    pendingNavigationIndex = nil
                }
                Button("Leave Anyway", role: .destructive) {
                    straightenRenderTask?.cancel()
                    if let target = pendingNavigationIndex { moveToIndex(target) }
                    pendingNavigationIndex = nil
                }
                Button("Apply") { applyCurrentPanelSettings(navigateAfterApply: pendingNavigationIndex) }
            } message: {
                Text("You changed this preview but did not apply. Apply the changes, leave anyway, or cancel.")
            }
            .alert("Unsaved changes", isPresented: $showPendingDoneAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Leave Anyway", role: .destructive) { dismiss() }
                Button("Apply") { applyCurrentPanelSettings() }
            } message: {
                Text("Apply your preview changes before leaving, or leave anyway and discard them.")
            }
            .alert("Unsaved changes", isPresented: $showFormatBackgroundLeaveAlert) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) { discardFormatBackgroundSessionEdits() }
                Button("Save") { closeFormatBackgroundSaving() }
            } message: {
                Text("Save your background edits, discard them, or keep editing.")
            }
            .alert("Rename image", isPresented: $showRenameAlert) {
                TextField("Image name", text: $previewRenameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let product = currentProduct { session.renameProduct(product, to: previewRenameText) }
                }
            } message: {
                Text("This changes the exported JPG filename even if the image came from UPC scan or upload.")
            }
            .alert(item: $markupConflict, content: markupConflictAlert)
            .fullScreenCover(isPresented: $showReplaceCamera) {
                CameraCaptureView(
                    settings: session.preferredCameraSettings,
                    onSettingsCaptured: { settings in
                        session.rememberCameraPreferences(from: settings)
                    },
                    onCapture: { image in
                        if let product = currentProduct {
                            cancelDraftRender()
                            hasPendingChanges = false
                            session.replaceImage(for: product, with: image)
                        }
                        showReplaceCamera = false
                    },
                    onCancel: {
                        showReplaceCamera = false
                    }
                )
                .ignoresSafeArea()
            }
    }

    private func markupConflictAlert(_ conflict: PreviewMarkupConflict) -> Alert {
        Alert(
            title: Text(conflict.title),
            message: Text(conflict.message),
            primaryButton: .default(Text("Keep Markup")) { conflict.onKeepMarkup() },
            secondaryButton: .destructive(Text("Remove Markup & apply")) { conflict.onRebuildWithoutMarkup() }
        )
    }

    var body: some View {
        previewPagerNavigationStack
            .fullScreenCover(isPresented: $showFullScreenZoom) {
                if let product = currentProduct {
                    FullScreenZoomView(
                        image: imageForDisplay(product),
                        resetToken: fullscreenZoomResetToken
                    )
                }
            }
            .fullScreenCover(isPresented: $showMarkupEditor) {
                if let base = markupEditorBaseImage() {
                    MarkupEditorSheet(
                        baseImage: base,
                        onSave: { merged in
                            renderTask?.cancel()
                            isRenderingDraft = false
                            draftRasterBaseImage = merged
                            draftPreviewImage = merged
                            draftSourceProductID = currentProduct?.id
                            draftIsRasterEdit = true
                            hasPendingChanges = true
                            captureUndoSnapshot()
                            scheduleDraftRender()
                        },
                        onDiscard: {}
                    )
                    .interactiveDismissDisabled(true)
                }
            }
            .fullScreenCover(isPresented: $showGroupedCoverEditor) {
                if let product = currentProduct {
                    GroupedCoverEditorSheet(
                        sourceProducts: groupedCoverEditSources,
                        canvasWidth: product.canvasWidth,
                        canvasHeight: product.canvasHeight,
                        fillRatio: product.fillRatio,
                        backgroundFillSpec: product.resolvedBackgroundFillSpec,
                        primaryColor: product.backgroundColor,
                        secondaryColor: product.secondaryBackgroundColor,
                        coverName: groupedCoverNameText,
                        existingLayout: groupedCoverExistingLayout,
                        editingProductID: product.id,
                        onSave: { image, layout in
                            session.updateGroupedCover(
                                productID: product.id,
                                compositeImage: image,
                                layout: layout,
                                name: groupedCoverNameText
                            )
                            groupedCoverExistingLayout = nil
                        },
                        onCancel: {
                            groupedCoverExistingLayout = nil
                        }
                    )
                }
            }
    }

    /// Filename and live-preview status below the top toolbar.
    @ViewBuilder
    private var previewTopMetadataBar: some View {
        if let product = currentProduct {
            VStack(spacing: 6) {
                if shouldShowPreviewStatusChip(for: product) {
                    previewStatusChip(for: product)
                }
                Text(product.filename(for: session.imageNamingMode))
                    .font(DS.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(.systemBackground).opacity(0.88), in: Capsule())
                    .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: 1))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.Space.screenHorizontal)
            .padding(.bottom, 4)
        }
    }

    /// Image styling controls in a slide-up sheet (same pattern as gradients).
    private var previewEditPolishSheet: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    showEditPolishSheet = false
                } label: {
                    Text("Done")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.ColorToken.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(DS.ColorToken.primaryButtonFill, in: Capsule())
                }
                .buttonStyle(.plainPressable)
                .accessibilityLabel("Done editing")
            }
            .padding(.vertical, DS.Space.stack)

            Text("Edit & Polish")
                .font(DS.TypeScale.sectionTitle)
                .foregroundStyle(DS.ColorToken.label)
                .frame(maxWidth: .infinity)

            expandedPreviewEditorTray
        }
        .padding(.horizontal, DS.Space.screenHorizontal)
        .padding(.bottom, 12)
    }

    private var previewFormatBackgroundSheet: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Close") { requestFormatBackgroundLeave() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .buttonStyle(.plainPressable)
                Spacer()
                Text("Format Background")
                    .font(DS.TypeScale.sectionTitle)
                    .foregroundStyle(DS.ColorToken.label)
                Spacer()
                Button("Done") { closeFormatBackgroundSaving() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .buttonStyle(.plainPressable)
            }
            .padding(.vertical, DS.Space.stack)

            gradientEditorPanel
        }
        .padding(.horizontal, DS.Space.screenHorizontal)
        .padding(.bottom, 12)
    }

    /// Custom canvas dimensions, presented from the Aspect menu's "Custom Size…" option.
    private var customCanvasSizeSheet: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Custom Size")
                    .font(DS.TypeScale.sectionTitle)
                    .foregroundStyle(DS.ColorToken.label)
                Text("Set the output canvas dimensions in pixels.")
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.stack) {
                    customCanvasDimensionField(title: "Width", text: $customCanvasWidthText)
                    Divider()
                    customCanvasDimensionField(title: "Height", text: $customCanvasHeightText)

                    Text("Allowed range: \(customCanvasBounds.lowerBound)–\(customCanvasBounds.upperBound) px.")
                        .font(DS.TypeScale.micro)
                        .foregroundStyle(customCanvasInputIsValid ? DS.ColorToken.secondaryLabel : DS.ColorToken.error)
                }
            }

            Button {
                applyCustomCanvasSize()
            } label: {
                Label("Apply Custom Size", systemImage: "checkmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(GlassPreviewButtonStyle())
            .disabled(!customCanvasInputIsValid)
            .opacity(customCanvasInputIsValid ? 1 : 0.45)
        }
        .padding(.horizontal, DS.Space.screenHorizontal)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private func customCanvasDimensionField(title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(DS.TypeScale.caption.weight(.semibold))
                .foregroundStyle(DS.ColorToken.label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(DS.ColorToken.label)
                .frame(width: 90)
            Text("px")
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.secondaryLabel)
        }
    }

    private var customCanvasBounds: ClosedRange<Int> { CanvasPresetCatalog.dimensionBounds }

    private func parsedCustomCanvasDimension(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        guard customCanvasBounds.contains(value) else { return nil }
        return value
    }

    private var customCanvasInputIsValid: Bool {
        parsedCustomCanvasDimension(customCanvasWidthText) != nil
            && parsedCustomCanvasDimension(customCanvasHeightText) != nil
    }

    private func openGroupedCoverEditorForCurrentProduct() {
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)
        guard let product = currentProduct, let layout = product.compositeBundleLayout else { return }
        groupedCoverNameText = product.upc
        groupedCoverExistingLayout = layout
        showGroupedCoverEditor = true
    }

    private func openCustomCanvasSizeSheet() {
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)
        customCanvasWidthText = String(panelCanvasWidth)
        customCanvasHeightText = String(panelCanvasHeight)
        showCustomCanvasSizeSheet = true
    }

    private func applyCustomCanvasSize() {
        guard let width = parsedCustomCanvasDimension(customCanvasWidthText),
              let height = parsedCustomCanvasDimension(customCanvasHeightText) else { return }
        showCustomCanvasSizeSheet = false
        applyExportCanvasPreset(width: width, height: height)
    }

    private var expandedPreviewEditorTray: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Before")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PreviewDockChrome.tertiaryLabel)
                // Internal split: 0 = all After, 1 = all Before (revealed from left).
                // Slider UI is inverted so left=Before / right=After matches the thumb.
                Slider(
                    value: Binding(
                        get: { 1 - beforeAfterSplit },
                        set: { beforeAfterSplit = 1 - $0 }
                    ),
                    in: 0...1
                )
                    .tint(PreviewDockChrome.sliderTint)
                    .disabled(!canUseBeforeAfterCompare)
                    .opacity(canUseBeforeAfterCompare ? 1 : DS.Motion.disabledOpacity)
                Text("After")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PreviewDockChrome.tertiaryLabel)
            }
            if let reason = beforeCompareUnavailableReason, currentProduct.map({ !$0.isGroupedCoverItem }) == true {
                Text(reason)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PreviewDockChrome.tertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isPreparingBeforeCompare, beforeAfterSplit > 0.001 {
                Text("Preparing original for compare…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PreviewDockChrome.tertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if canUseBeforeAfterCompare {
                Text("Left = Before (original capture) · Right = After (processed), same framing")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PreviewDockChrome.tertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            stylesEditorContent
        }
    }

    private var stylesEditorContent: some View {
        VStack(spacing: 12) {
            if let product = currentProduct {
                HStack(spacing: 8) {
                    PhotosStyleFilterStrip(
                        productID: product.id,
                        neutralSourceImage: styleStripNeutralSource(for: product),
                        adjustAutoEnhance: panelAdjustAutoEnhance,
                        selectedFilter: $panelPhotoFilter,
                        onSelect: {
                            if panelPhotoFilter == .none {
                                panelPhotoFilterIntensity = 1.0
                            }
                            scheduleFilterOnlyRender()
                        }
                    )
                }
            }

            if panelPhotoFilter != .none {
                VStack(spacing: 2) {
                    HStack {
                        Text("Style intensity")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PreviewDockChrome.secondaryLabel)
                        Spacer()
                        Text("\(Int(panelPhotoFilterIntensity * 100))%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(PreviewDockChrome.primaryLabel)
                            .monospacedDigit()
                    }
                    Slider(value: $panelPhotoFilterIntensity, in: 0...1) { editing in
                        isDraggingStyleIntensity = editing
                        if !editing {
                            scheduleFilterOnlyRender(quality: .standard)
                        }
                    }
                        .tint(PreviewDockChrome.sliderTint)
                        .onChange(of: panelPhotoFilterIntensity) { _, _ in
                            guard isDraggingStyleIntensity else { return }
                            scheduleFilterOnlyRender(quality: .interactive)
                        }
                        .accessibilityLabel("Style intensity")
                        .accessibilityValue("\(Int(panelPhotoFilterIntensity * 100)) percent")
                }
            }

            editPolishCanvasSection

            if session.brandMarkEnabled {
                Toggle(isOn: $panelSuppressBrandMark) {
                    Text("Hide Brand Mark on this photo")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PreviewDockChrome.primaryLabel)
                }
                .tint(PreviewDockChrome.sliderTint)
                .onChange(of: panelSuppressBrandMark) { _, _ in
                    scheduleFilterOnlyRender()
                }
            }

            VStack(spacing: 2) {
                Text("Straighten object \(Int(panelRotationDegrees))°")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PreviewDockChrome.secondaryLabel)
                Slider(value: $panelRotationDegrees, in: -180...180) { editing in
                    isDraggingStraighten = editing
                    if editing {
                        if straightenCommitBaseline == nil {
                            straightenCommitBaseline = panelRotationDegrees
                        }
                    } else {
                        let revert = straightenCommitBaseline ?? panelRotationDegrees
                        straightenCommitBaseline = nil
                        guardedFullReprocess(
                            revert: { panelRotationDegrees = revert },
                            apply: { scheduleGeometryPreview(quality: .standard) }
                        )
                    }
                }
                    .tint(PreviewDockChrome.sliderTint)
                    .onChange(of: panelRotationDegrees) { _, _ in
                        guard isDraggingStraighten else { return }
                        scheduleGeometryPreview(quality: .interactive)
                    }
            }

            VStack(spacing: 4) {
                HStack {
                    Text("Object fill \(Int(panelFillRatio * 100))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PreviewDockChrome.primaryLabel)
                    if let p = currentProduct, abs(canvasEffectiveFill(for: p) - panelFillRatio) > 0.004 {
                        Text("→ \(Int(canvasEffectiveFill(for: p) * 100))% to avoid cropping")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.accent)
                    }
                    Spacer()
                }
                Slider(value: $panelFillRatio, in: 0.70...1.0, step: 0.01) { editing in
                    isDraggingFill = editing
                    if editing {
                        if fillCommitBaseline == nil {
                            fillCommitBaseline = panelFillRatio
                        }
                    } else {
                        let revert = fillCommitBaseline ?? panelFillRatio
                        fillCommitBaseline = nil
                        guardedFullReprocess(
                            revert: { panelFillRatio = revert },
                            apply: { scheduleGeometryPreview(quality: .standard) }
                        )
                    }
                }
                    .tint(PreviewDockChrome.sliderTint)
                    .onChange(of: panelFillRatio) { _, _ in
                        guard isDraggingFill else { return }
                        scheduleGeometryPreview(quality: .interactive)
                    }
            }
        }
    }

    private func previewDisplayImage(for product: CapturedProduct) -> UIImage {
        let editingActive = hasPendingChanges
            || showEditPolishSheet
            || showGradientEditorSheet
        if editingActive,
           let draft = draftPreviewImage,
           draftSourceProductID == product.id {
            return draft
        }
        return product.image
    }

    private var canUseBeforeAfterCompare: Bool {
        guard let product = currentProduct else { return false }
        if product.isGroupedCoverItem || product.isCompositeBundle { return false }
        return beforeCompareUnavailableReason == nil
    }

    private func previewPhotoPage(for product: CapturedProduct) -> some View {
        let afterImage = previewDisplayImage(for: product)
        let showSplit = beforeAfterSplit > 0.001 && canUseBeforeAfterCompare
        let compareToken = beforeCompareToken(for: product, afterImage: afterImage)
        let beforeReady = alignedBeforeCompareImage != nil
            && alignedBeforeCompareToken == compareToken
            && compareToken != nil
        let beforeImage = beforeReady ? alignedBeforeCompareImage : nil

        return GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)
            let split = max(0, min(1, beforeAfterSplit)) * w

            ZStack {
                PreviewChrome.canvasBackground(for: colorScheme)
                Group {
                    if showSplit {
                        ZStack {
                            // After (processed) is always the base — visible on the right of the divider.
                            beforeAfterCompareLayer(image: afterImage, width: w, height: h)
                            if let beforeImage {
                                // Before (original capture) revealed from the left — matches reference: Before | After.
                                beforeAfterCompareLayer(image: beforeImage, width: w, height: h)
                                    .mask(
                                        HStack(spacing: 0) {
                                            Rectangle().fill(DSPhotoOverlay.primaryText).frame(width: split)
                                            Spacer(minLength: 0)
                                        }
                                        .frame(width: w, height: h, alignment: .leading)
                                    )
                            } else {
                                // Preparing / unavailable — do not fake Before with After.
                                Color.black.opacity(0.28)
                                    .mask(
                                        HStack(spacing: 0) {
                                            Rectangle().fill(DSPhotoOverlay.primaryText).frame(width: split)
                                            Spacer(minLength: 0)
                                        }
                                        .frame(width: w, height: h, alignment: .leading)
                                    )
                                if isPreparingBeforeCompare {
                                    Text("Preparing original…")
                                        .font(DS.TypeScale.micro.weight(.semibold))
                                        .foregroundStyle(DSPhotoOverlay.primaryText)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .position(x: max(40, min(w - 40, split * 0.5)), y: h * 0.5)
                                }
                            }
                            Rectangle()
                                .fill(DSPhotoOverlay.primaryText.opacity(0.92))
                                .frame(width: 2, height: min(h * 0.92, w))
                                .position(x: max(1, min(w - 1, split)), y: h / 2)
                        }
                    } else {
                        previewZoomableCanvas(
                            image: afterImage,
                            product: product,
                            allowsSubjectLift: product.backgroundRemoved && session.subjectLiftEnabledInPreview,
                            width: w,
                            height: h
                        )
                    }
                }
                .frame(width: w, height: h)

                VStack(spacing: 7) {
                    Spacer(minLength: 0)
                    // Only when no sheet covers the canvas and HUD isn’t already showing full-screen busy UI.
                    if isRenderingDraft,
                       currentProduct?.id == product.id,
                       !previewBottomSheetOpen,
                       !session.showsMagicPreviewOverlay {
                        InlineLoadingBadge(message: "Generating preview…")
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    if hasPendingChanges {
                        Text("Tap Apply to save edits to this queue item.")
                            .font(DS.TypeScale.micro)
                            .foregroundStyle(DSPhotoOverlay.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 12)
                .frame(width: w, height: h)
                .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .task(id: compareToken) {
            await prepareAlignedBeforeCompare(for: product, afterImage: afterImage, token: compareToken)
        }
        .task(id: stylePrewarmTaskID(for: product)) {
            guard showEditPolishSheet, currentProduct?.id == product.id else { return }
            var waits = 0
            while isRenderingDraft, waits < 120 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if Task.isCancelled { return }
                waits += 1
            }
            guard !Task.isCancelled, !isRenderingDraft, showEditPolishSheet else { return }
            await runStyleCachePrewarm(for: product)
        }
    }

    private func clearBeforeCompareCache() {
        alignedBeforeCompareImage = nil
        alignedBeforeCompareToken = nil
        isPreparingBeforeCompare = false
        beforeCompareUnavailableReason = nil
    }

    private func prepareAlignedBeforeCompare(
        for product: CapturedProduct,
        afterImage: UIImage,
        token: BeforeCompareToken?
    ) async {
        guard let token else {
            alignedBeforeCompareImage = nil
            alignedBeforeCompareToken = nil
            isPreparingBeforeCompare = false
            if product.isGroupedCoverItem || product.isCompositeBundle {
                beforeCompareUnavailableReason = "Compare isn’t available for grouped covers."
            }
            return
        }
        if alignedBeforeCompareToken == token, alignedBeforeCompareImage != nil {
            beforeCompareUnavailableReason = nil
            isPreparingBeforeCompare = false
            return
        }

        isPreparingBeforeCompare = true
        beforeCompareUnavailableReason = nil

        guard ImageProcessor.isValidExportBitmap(afterImage) else {
            guard !Task.isCancelled else { return }
            alignedBeforeCompareImage = nil
            alignedBeforeCompareToken = nil
            isPreparingBeforeCompare = false
            beforeCompareUnavailableReason = "Preview not ready for compare."
            if beforeAfterSplit > 0.001 { beforeAfterSplit = 0 }
            return
        }

        guard let sourceOriginal = await QueueImageResolver.uncompressedOriginal(
            for: product,
            fallbackToProcessed: false
        ) else {
            guard !Task.isCancelled else { return }
            alignedBeforeCompareImage = nil
            alignedBeforeCompareToken = nil
            isPreparingBeforeCompare = false
            beforeCompareUnavailableReason = "Original photo unavailable for compare."
            if beforeAfterSplit > 0.001 { beforeAfterSplit = 0 }
            return
        }

        let layout = beforeCompareLayout(for: product)
        var fillSpec = layout.fillSpec
        fillSpec.normalizeStops()
        let cutoutSize = await resolvedCutoutSizeForBeforeCompare(product: product)
        // After already has base rotation/flips in its pixels. Align to those pixels with
        // identity bake transforms so we don't double-apply (live delta still hits both layers).
        let aligned = await ImageProcessor.comparisonOriginalOnCanvasAsync(
            sourceOriginal,
            canvasWidth: token.canvasW,
            canvasHeight: token.canvasH,
            rotationDegrees: 0,
            fillRatio: token.fillRatio,
            flipHorizontal: false,
            flipVertical: false,
            alignToCutout: true,
            backgroundStyle: fillSpec.legacyCanvasStyle(),
            gradientColorHexes: fillSpec.colorHexes.isEmpty ? ["#FFFFFF"] : fillSpec.colorHexes,
            backgroundFillSpec: fillSpec,
            cutoutSize: cutoutSize,
            afterImage: afterImage
        )
        guard !Task.isCancelled else { return }
        // Re-check with the same stable fingerprint builder (not regenerating stop UUIDs into the key).
        guard beforeCompareToken(for: product, afterImage: afterImage) == token else { return }

        alignedBeforeCompareImage = aligned
        alignedBeforeCompareToken = token
        isPreparingBeforeCompare = false
        beforeCompareUnavailableReason = nil
    }

    /// Content-only fingerprint so BeforeCompareToken stays Equatable-stable across view passes.
    private func beforeCompareFillFingerprint(_ spec: BackgroundFillSpec) -> String {
        let stops = spec.gradientStops
            .sorted { $0.position < $1.position }
            .map { "\($0.colorHex)-\(String(format: "%.4f", $0.position))-\(String(format: "%.3f", $0.transparency))-\(String(format: "%.3f", $0.brightness))" }
            .joined(separator: "|")
        let imageKey: String = {
            guard let sel = spec.imageSelection else { return "none" }
            return "\(sel.backgroundID)-\(sel.customImageRef ?? "")-\(sel.shadow.rawValue)"
        }()
        return "\(spec.fillKind.rawValue)|\(spec.gradientType.rawValue)|\(spec.gradientDirection.rawValue)|\(Int(spec.gradientAngleDegrees.rounded()))|\(spec.overlay.rawValue)|\(stops)|\(imageKey)"
    }

    private func beforeAfterCompareLayer(image: UIImage, width: CGFloat, height: CGFloat) -> some View {
        // Before is baked with the same base rotation as After (`draftBakedRotationDegrees` when drafting).
        // Apply the live straighten delta to both so they stay locked while the slider moves.
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .rotationEffect(.degrees(previewLiveRotationDelta))
            .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.88), value: previewLiveRotationDelta)
    }

    /// Cutout size used to place the original subject identically to After.
    private func resolvedCutoutSizeForBeforeCompare(product: CapturedProduct) async -> CGSize? {
        if draftBackgroundCutoutProductID == product.id, let cutout = draftBackgroundCutout, cutout.size.width > 4 {
            return cutout.size
        }
        let canvasW = panelCanvasWidth
        let canvasH = panelCanvasHeight
        return await Task.detached(priority: .userInitiated) {
            if let loaded = CompositeBundleCutoutLoader.previewCutout(
                for: product,
                canvasWidth: canvasW,
                canvasHeight: canvasH
            ) {
                return loaded.pixelSize
            }
            return nil
        }.value
    }

    /// Always builds a compare token for normal products so Before can precompute (not only after slider move).
    private func beforeCompareToken(for product: CapturedProduct, afterImage: UIImage) -> BeforeCompareToken? {
        if product.isGroupedCoverItem || product.isCompositeBundle { return nil }
        let layout = beforeCompareLayout(for: product)
        // Match After’s pixel canvas exactly so scaledToFit places the subject identically.
        let pixel = ImageProcessor.normalizedPixelSize(of: afterImage)
        let canvasW = max(1, Int(pixel.width.rounded()))
        let canvasH = max(1, Int(pixel.height.rounded()))
        return BeforeCompareToken(
            productID: product.id,
            canvasW: canvasW,
            canvasH: canvasH,
            fillRatio: layout.fillRatio,
            rotation: layout.rotation,
            flipH: layout.flipH,
            flipV: layout.flipV,
            alignToCutout: shouldAlignBeforeToCutout(for: product),
            fillFingerprint: beforeCompareFillFingerprint(layout.fillSpec),
            afterImageID: ObjectIdentifier(afterImage),
            alignVersion: 7
        )
    }

    /// Prefer cutout alignment whenever we can detect the subject, so Before/After share framing.
    private func shouldAlignBeforeToCutout(for product: CapturedProduct) -> Bool {
        if product.isGroupedCoverItem || product.isCompositeBundle { return false }
        if #available(iOS 17.0, *) { return true }
        return product.backgroundRemoved
            || session.autoBackgroundRemoval
            || (draftBackgroundCutoutProductID == product.id && draftBackgroundCutout != nil)
    }

    private func beforeCompareLayout(for product: CapturedProduct) -> (
        fillRatio: Double,
        rotation: Double,
        flipH: Bool,
        flipV: Bool,
        fillSpec: BackgroundFillSpec
    ) {
        if hasPendingChanges || showEditPolishSheet || showGradientEditorSheet {
            // Bake at the same rotation as the current After draft so live delta applies equally.
            let bakedRotation: Double = {
                if draftSourceProductID == product.id {
                    return draftBakedRotationDegrees
                }
                return panelRotationDegrees
            }()
            return (panelFillRatio, bakedRotation, panelFlipHorizontal, panelFlipVertical, panelBackgroundFillSpec)
        }
        return (
            product.fillRatio,
            product.rotationDegrees,
            product.flipHorizontal,
            product.flipVertical,
            product.resolvedBackgroundFillSpec
        )
    }

    /// Filter-neutral composite for style strip thumbnails (never the tuned canvas preview).
    private func styleStripNeutralSource(for product: CapturedProduct) -> UIImage? {
        if beforeAfterSplit > 0.55 { return nil }
        if draftSourceProductID == product.id, let base = draftFilterBaseImage {
            return base
        }
        return product.image
    }

    private func stylePrewarmTaskID(for product: CapturedProduct) -> String {
        let revision = StylePreviewCacheRevisionStore.shared.revision(for: product.id)
        let busy = (currentProduct?.id == product.id && isRenderingDraft) ? "busy" : "ready"
        let dimensions: String = {
            guard let neutral = styleStripNeutralSource(for: product),
                  let cg = neutral.cgImage else { return "pending" }
            return "\(cg.width)x\(cg.height)"
        }()
        return "\(product.id.uuidString)-r\(revision)-\(busy)-\(dimensions)-ae\(panelAdjustAutoEnhance)"
    }

    private func runStyleCachePrewarm(for product: CapturedProduct) async {
        guard let image = styleStripNeutralSource(for: product),
              let cg = image.cgImage, cg.width > 1, cg.height > 1 else { return }
        let cacheKey = StylePreviewCacheRevisionStore.shared.cacheKey(for: product.id)
        let imageID = product.id.uuidString
        let enhanced = ImageProcessor.applyExportTuning(
            to: image,
            photoFilter: .none,
            photoFilterIntensity: 1,
            adjustAutoEnhance: panelAdjustAutoEnhance,
            applyBrandMark: false
        )
        await Task(priority: .background) {
            await StylePreviewThumbnailRenderer.shared.prewarm(
                productID: product.id,
                from: enhanced,
                cacheKey: cacheKey,
                imageID: imageID
            )
        }.value
    }

    private func imageForDisplay(_ product: CapturedProduct) -> UIImage {
        previewDisplayImage(for: product)
    }

    private func shouldShowPreviewStatusChip(for product: CapturedProduct) -> Bool {
        if isRenderingDraft { return true }
        if beforeAfterSplit > 0.001 { return true }
        if hasPendingChanges { return true }
        return false
    }

    private func statusText(for product: CapturedProduct) -> String {
        if isRenderingDraft { return "Updating preview…" }
        if beforeAfterSplit > 0.001 {
            if beforeCompareUnavailableReason != nil {
                return beforeCompareUnavailableReason ?? "Original unavailable"
            }
            if isPreparingBeforeCompare || alignedBeforeCompareToken != beforeCompareToken(for: product, afterImage: previewDisplayImage(for: product)) {
                return "Preparing original for compare…"
            }
            if beforeAfterSplit > 0.55 {
                return "Before (left): original capture · After (right): processed"
            }
            return "Before = original capture (left) · After = processed (right)"
        }
        if hasPendingChanges { return "Live preview — Apply saves to queue; Share uses on-screen look" }
        return ""
    }

    /// Status chip below the top toolbar (live preview or compare mode).
    @ViewBuilder
    private func previewStatusChip(for product: CapturedProduct) -> some View {
        let text = statusText(for: product)
        if !text.isEmpty {
            DSPhotoOverlayBadge(
                text: text,
                multiline: true,
                highlighted: false,
                lightSurface: hasPendingChanges
            )
            .padding(.horizontal, 8)
        }
    }

    private func currentPanelFillSpec() -> BackgroundFillSpec {
        panelBackgroundFillSpec
    }

    private func applyPanelFillSpec(_ spec: BackgroundFillSpec, presetID: String? = nil) {
        var normalized = spec
        normalized.normalizeStops()
        panelBackgroundFillSpec = normalized
        panelSelectedPresetID = presetID
        syncLegacyFieldsFromFillSpec()
    }

    private func syncLegacyFieldsFromFillSpec() {
        panelBackgroundStyle = panelBackgroundFillSpec.legacyCanvasStyle()
        if panelBackgroundFillSpec.fillKind == .solid {
            let hex = panelBackgroundFillSpec.gradientStops.first?.colorHex ?? "#FFFFFF"
            panelGradientHexes = [hex]
            let uiColor = UIColor(hexString: hex) ?? .white
            panelBackgroundColor = Color(uiColor: uiColor)
            panelSecondaryBackgroundColor = Color(uiColor: uiColor)
            return
        }
        panelGradientHexes = panelBackgroundFillSpec.colorHexes.isEmpty ? ["#FFFFFF"] : panelBackgroundFillSpec.colorHexes
        if let first = panelBackgroundFillSpec.gradientStops.first {
            panelBackgroundColor = Color(uiColor: first.uiColor())
        }
        if let last = panelBackgroundFillSpec.gradientStops.last {
            panelSecondaryBackgroundColor = Color(uiColor: last.uiColor())
        }
    }

    private func panelFillSpecDidChange() {
        syncLegacyFieldsFromFillSpec()
        hasPendingChanges = true
        beforeAfterSplit = 0
        draftPreviewQuality = .standard
        // Force a fresh composite even if a prior draft token matched (Reset → white stains fix).
        draftRenderedBackgroundToken = nil
        scheduleFastBackgroundPreview(debounceNanoseconds: 0)
    }

    /// Fast debounced preview while color picker / sliders are active.
    private func panelFillSpecLiveChange() {
        syncLegacyFieldsFromFillSpec()
        if draftIsRasterEdit { return }
        draftPreviewQuality = .interactive
        let debounceNanoseconds: UInt64 = (showGradientEditorSheet || showImageBackgroundSheet) ? 16_000_000 : 30_000_000
        scheduleFastBackgroundPreview(debounceNanoseconds: debounceNanoseconds)
    }

    /// Composite-only Format Background preview (solid / gradient / image) — no Vision re-cutout.
    private func scheduleFastBackgroundPreview(debounceNanoseconds: UInt64 = 30_000_000) {
        guard !isApplying else { return }
        guard let product = currentProduct else { return }
        guard !draftIsRasterEdit else { return }
        if panelBackgroundFillSpec.fillKind == .image,
           panelBackgroundFillSpec.imageSelection == nil {
            return
        }

        hasPendingChanges = true
        beforeAfterSplit = 0
        prepareDraftBackgroundCutoutIfNeeded()

        let token = backgroundEditorRefreshToken
        if token == draftRenderedBackgroundToken, draftPreviewImage != nil, draftSourceProductID == product.id {
            return
        }

        draftRenderGeneration &+= 1
        let generation = draftRenderGeneration
        if isRenderingDraft {
            isRenderingDraft = false
            syncMagicPreviewOverlay()
        }
        renderTask?.cancel()

        var fillSpec = panelBackgroundFillSpec
        fillSpec.normalizeStops()
        let previewCanvas = draftPreviewCanvasSize(for: fillSpec)
        let cutoutProductID = product.id
        let rot = panelRotationDegrees
        let flipH = panelFlipHorizontal
        let flipV = panelFlipVertical
        let fill = panelFillRatio
        let bgColor = UIColor(panelBackgroundColor)
        let bg2Color = UIColor(panelSecondaryBackgroundColor)
        let bgStyle = panelBackgroundStyle
        let gradientHexes = panelGradientHexes
        let skipTuning = panelPhotoFilter == .none
            && !panelAdjustAutoEnhance
            && panelToneAdjustments.isNeutral
            && !shouldSuppressBackdropFringe()
        let shadow = effectiveStudioShadow
        let bgLongEdge = fillSpec.fillKind == .image
            ? CGFloat(max(previewCanvas.width, previewCanvas.height)) * 1.2
            : nil

        renderTask = Task {
            defer {
                Task { @MainActor in
                    finishDraftRenderIfCurrent(generation: generation)
                }
            }
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            if Task.isCancelled { return }

            let cutout: UIImage? = await MainActor.run {
                guard draftBackgroundCutoutProductID == cutoutProductID else { return nil }
                return draftBackgroundCutout
            }
            guard let cutout else {
                await MainActor.run {
                    guard generation == draftRenderGeneration else { return }
                    performFullPipelineDraftRender(
                        previewDebounceNanoseconds: 0,
                        generation: generation
                    )
                }
                return
            }

            let composed = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    // Composite path also scrubs; keep a single pass here for clarity.
                    return ProductCompositeRenderer.composite(
                        cutout: cutout,
                        canvasWidth: previewCanvas.width,
                        canvasHeight: previewCanvas.height,
                        fillRatio: fill,
                        backgroundColor: bgColor,
                        secondaryBackgroundColor: bg2Color,
                        backgroundStyle: bgStyle,
                        gradientColorHexes: gradientHexes,
                        backgroundFillSpec: fillSpec,
                        subjectRotationDegrees: rot,
                        flipHorizontal: flipH,
                        flipVertical: flipV,
                        studioShadow: shadow,
                        maxBackgroundLongEdge: bgLongEdge
                    )
                }
            }.value
            if Task.isCancelled { return }

            let output: UIImage
            if skipTuning {
                output = composed
            } else {
                output = await applyPreviewTuningAsync(to: composed)
            }
            if Task.isCancelled { return }

            await MainActor.run {
                guard generation == draftRenderGeneration, currentProduct?.id == cutoutProductID else { return }
                // Keep pre-filter composite so tone/style can re-tune without Vision.
                draftFilterBaseImage = composed
                withAnimation(.easeInOut(duration: 0.1)) {
                    draftPreviewImage = output
                    draftSourceProductID = cutoutProductID
                    draftBakedRotationDegrees = rot
                    draftRenderedBackgroundToken = token
                }
            }
        }
    }

    private func prepareDraftBackgroundCutoutIfNeeded() {
        guard let product = currentProduct else { return }
        if draftBackgroundCutoutProductID == product.id, draftBackgroundCutout != nil { return }
        // Don't cancel an in-flight prep for the same product — Match / Format BG rely on it.
        if draftBackgroundCutoutProductID == product.id, draftBackgroundCutoutPrepTask != nil { return }
        draftBackgroundCutoutPrepTask?.cancel()
        draftBackgroundCutout = nil
        draftBackgroundCutoutProductID = product.id
        let canvasW = panelCanvasWidth
        let canvasH = panelCanvasHeight
        draftBackgroundCutoutPrepTask = Task.detached(priority: .userInitiated) {
            let cutout = autoreleasepool {
                let raw = CompositeBundleCutoutLoader.previewCutout(
                    for: product,
                    canvasWidth: canvasW,
                    canvasHeight: canvasH
                )?.image
                return raw.map { ImageProcessor.scrubCutoutMatteFringe($0) }
            }
            await MainActor.run {
                guard !Task.isCancelled, currentProduct?.id == product.id else { return }
                draftBackgroundCutout = cutout
                draftBackgroundCutoutProductID = product.id
                draftBackgroundCutoutPrepTask = nil
                if hasPendingChanges {
                    scheduleFastBackgroundPreview(debounceNanoseconds: 0)
                }
            }
        }
    }

    /// Waits for the subject cutout used by Match product colors (avoids solid-looking gradient when sampling the full frame).
    @MainActor
    private func resolvedDraftCutoutForMatching(
        productID: UUID,
        generation: Int,
        timeoutNanoseconds: UInt64 = 3_000_000_000
    ) async -> UIImage? {
        if draftBackgroundCutoutProductID == productID, let cutout = draftBackgroundCutout {
            return cutout
        }
        prepareDraftBackgroundCutoutIfNeeded()
        let steps = Int(timeoutNanoseconds / 40_000_000)
        for _ in 0..<max(steps, 1) {
            guard generation == matchColorsGeneration else { return nil }
            if draftBackgroundCutoutProductID == productID, let cutout = draftBackgroundCutout {
                return cutout
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        guard generation == matchColorsGeneration else { return nil }
        guard draftBackgroundCutoutProductID == productID else { return nil }
        return draftBackgroundCutout
    }

    private func invalidateDraftBackgroundCutout() {
        draftBackgroundCutoutPrepTask?.cancel()
        draftBackgroundCutoutPrepTask = nil
        draftBackgroundCutout = nil
        draftBackgroundCutoutProductID = nil
        draftRenderedBackgroundToken = nil
    }

    /// Background edits must rebuild from the original — never reuse filter-only cache.
    private func markBackgroundPendingAndRender(
        previewDebounceNanoseconds: UInt64 = 40_000_000,
        invalidateStyleCache: Bool = false
    ) {
        guard let product = currentProduct else { return }
        draftPreviewQuality = .standard
        if invalidateStyleCache {
            StylePreviewCacheRevisionStore.shared.invalidate(productID: product.id, reason: "background")
        }
        clearFilterPreviewBase()
        hasPendingChanges = true
        beforeAfterSplit = 0
        scheduleFastBackgroundPreview(debounceNanoseconds: previewDebounceNanoseconds)
    }

    private func syncMagicPreviewOverlay() {
        // Single full-screen host = InteractionHUD (above every sheet).
        // Matching / Apply / standard drafts drive HUD — interactive drags stay unblocked.
        let matchingBusy = isMatchingProductColors
        let draftBlocksUI = isRenderingDraft && draftPreviewQuality != .interactive
        let showBlocking = (isApplying || matchingBusy || draftBlocksUI)
            && session.blockingOperationDepth == 0
        session.showsMagicPreviewOverlay = showBlocking
        session.magicPreviewOverlayApplying = isApplying || matchingBusy || draftBlocksUI
        if matchingBusy {
            session.magicPreviewOverlayMessage = "Matching product colors…"
        } else if isApplying {
            session.magicPreviewOverlayMessage = "Applying…"
        } else if draftBlocksUI {
            session.magicPreviewOverlayMessage = "Updating preview…"
        } else {
            session.magicPreviewOverlayMessage = nil
        }
    }

    private func matchBackgroundToProductColors() {
        guard let product = currentProduct, !product.isGroupedCoverItem else { return }
        guard !isMatchingProductColors else { return }
        guard panelBackgroundFillSpec.fillKind != .image else { return }

        captureUndoSnapshot()
        isMatchingProductColors = true
        matchProductColorsFailureMessage = nil
        matchProductColorsFailureClearTask?.cancel()
        syncMagicPreviewOverlay()

        let generation = matchColorsGeneration + 1
        matchColorsGeneration = generation
        // Capture fill kind up front — UI selection must win even if sampling was weak.
        let template = panelBackgroundFillSpec
        let intendedKind = template.fillKind
        let productSnapshot = product

        Task { @MainActor in
            // Wait for subject cutout so gradient Match isn't sampling table/white canvas
            // (that path often collapses to a flat "solid" look). Solid→then→gradient worked
            // because the cutout finished during the first Match.
            let preferredCutout = await resolvedDraftCutoutForMatching(
                productID: productSnapshot.id,
                generation: generation
            )
            guard generation == matchColorsGeneration else { return }

            let result = await Task.detached(priority: .userInitiated) {
                let sourceImage = await QueueImageResolver.uncompressedOriginal(for: productSnapshot) ?? productSnapshot.image
                return ProductColorPaletteExtractor.fillSpec(
                    from: sourceImage,
                    preferredCutout: preferredCutout,
                    preserving: template
                )
            }.value

            guard generation == matchColorsGeneration else { return }
            isMatchingProductColors = false
            syncMagicPreviewOverlay()
            switch result {
            case .success(var spec):
                switch intendedKind {
                case .solid:
                    spec.fillKind = .solid
                    spec.overlay = .none
                    if let hex = spec.gradientStops.first?.colorHex {
                        spec.gradientStops = [GradientColorStop(colorHex: hex, position: 0)]
                    }
                case .gradient:
                    spec.fillKind = .gradient
                    if spec.gradientStops.count < 2 {
                        let hex = spec.gradientStops.first?.colorHex ?? "#FFFFFF"
                        let base = UIColor(hexString: hex) ?? .white
                        spec.gradientStops = GradientColorStop.evenDistribution(hexes: [
                            base.lighter(by: 0.14).hexString,
                            hex,
                            base.darker(by: 0.12).hexString,
                        ])
                    }
                case .image:
                    break
                }
                spec.normalizeStops()
                panelSelectedPresetID = nil
                applyPanelFillSpec(spec)
                markBackgroundPendingAndRender()
            case .failure:
                matchProductColorsFailureMessage = "Not enough product color to match"
                matchProductColorsFailureClearTask = Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if matchProductColorsFailureMessage == "Not enough product color to match" {
                            matchProductColorsFailureMessage = nil
                        }
                    }
                }
            }
        }
    }

    private func openFormatBackgroundPanel() {
        showEditPolishSheet = false
        gradientPresetScrollRequestID = UUID()
        imagePresetScrollRequestID = UUID()
        if panelBackgroundFillSpec.fillKind == .image,
           let bgID = panelBackgroundFillSpec.imageSelection?.backgroundID {
            panelImageCategory = ImageBackgroundFolderCatalog.category(forBackgroundID: bgID)
        }
        prepareDraftBackgroundCutoutIfNeeded()
        withAnimation(.easeInOut(duration: 0.22)) {
            showGradientEditorSheet = true
        }
    }

    private var effectiveStudioShadow: SoftSyntheticShadowSettings {
        panelPolishEnabled ? .off : panelStudioShadow
    }

    private func applyAIPolishEnhancement() {
        guard currentProduct != nil, !isApplying else { return }
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)
        panelPolishEnabled = true
        panelStudioShadow = .off
        aiPolishEnhanceApplied = true
        panelAdjustAutoEnhance = false
        panelToneAdjustments = .neutral
        draftPreviewQuality = .interactive
        clearFilterPreviewBase()
        markPendingAndRender(
            clearRasterEdit: false,
            invalidateStyleCache: false,
            quality: .interactive
        )
    }

    private func openEditPolishPanel() {
        showGradientEditorSheet = false
        showEditPolishSheet = true
        prepareDraftBackgroundCutoutIfNeeded()
        if let product = currentProduct,
           draftSourceProductID != product.id {
            draftFilterBaseImage = product.image
            draftPreviewImage = product.image
            draftSourceProductID = product.id
            draftBakedRotationDegrees = panelRotationDegrees
            cancelDraftRender()
        }
    }

    private var gradientEditorPanel: some View {
        PowerPointBackgroundFillEditor(
            spec: $panelBackgroundFillSpec,
            selectedScenePresetID: $panelSelectedPresetID,
            onLiveSpecChange: { panelFillSpecLiveChange() },
            onSpecChange: { panelFillSpecDidChange() },
            onCaptureUndo: { captureUndoSnapshot() },
            selectedGradientGroupID: $panelGradientGroupID,
            presetScrollRequestID: gradientPresetScrollRequestID,
            matchProductColorsEnabled: currentProduct.map { !$0.isGroupedCoverItem } ?? false,
            isMatchingProductColors: isMatchingProductColors,
            matchProductColorsFailureMessage: matchProductColorsFailureMessage,
            onMatchProductColors: { matchBackgroundToProductColors() },
            showImageBackgroundSheet: $showImageBackgroundSheet,
            showImageBackgroundVisualEditor: $showImageBackgroundVisualEditor,
            selectedImageCategory: $panelImageCategory,
            imagePresetScrollRequestID: imagePresetScrollRequestID,
            canvasWidth: panelCanvasWidth,
            canvasHeight: panelCanvasHeight,
            fillRatio: panelFillRatio,
            cutoutSize: imageBackgroundEditorCutout()?.size ?? CGSize(width: 1, height: 1),
            cutoutImage: imageBackgroundEditorCutout()?.image
        )
    }

    private var formatBackgroundPresentationDetents: Set<PresentationDetent> {
        if showImageBackgroundSheet || showImageBackgroundVisualEditor {
            return [.medium]
        }
        return [.medium, .large]
    }

    private var formatBackgroundSessionHasEdits: Bool {
        guard let formatBackgroundSessionBaseline else { return false }
        return panelBackgroundFillSpec != formatBackgroundSessionBaseline
    }

    private func requestFormatBackgroundLeave() {
        guard formatBackgroundSessionHasEdits else {
            showGradientEditorSheet = false
            return
        }
        showFormatBackgroundLeaveAlert = true
    }

    private func closeFormatBackgroundSaving() {
        showGradientEditorSheet = false
    }

    private func discardFormatBackgroundSessionEdits() {
        if let baseline = formatBackgroundSessionBaseline {
            applyPanelFillSpec(baseline)
            markBackgroundPendingAndRender()
        }
        showGradientEditorSheet = false
    }

    private func imageBackgroundEditorCutout() -> (image: UIImage, size: CGSize)? {
        guard let product = currentProduct else { return nil }
        if let loaded = CompositeBundleCutoutLoader.previewCutout(
            for: product,
            canvasWidth: panelCanvasWidth,
            canvasHeight: panelCanvasHeight
        ) {
            return (loaded.image, loaded.pixelSize)
        }
        let fallback = product.image
        return (fallback, fallback.size)
    }

    /// Forces preview + editor refresh when nested struct fields change (type, angle, stops).
    private var backgroundEditorRefreshToken: String {
        let s = panelBackgroundFillSpec
        let stopKey = s.gradientStops.map { "\($0.colorHex)-\($0.position)" }.joined(separator: "|")
        let imageKey: String = {
            guard let sel = s.imageSelection else { return "none" }
            let bgT = sel.backgroundTransform.map { "\($0.centerX)-\($0.centerY)-\($0.scale)-\($0.rotationRadians)" } ?? "nil"
            let pT = sel.productTransform.map { "\($0.centerX)-\($0.centerY)-\($0.scale)-\($0.rotationRadians)" } ?? "nil"
            let crop = sel.backgroundCrop.map { "\($0.x)-\($0.y)-\($0.width)-\($0.height)" } ?? "full"
            return "\(sel.backgroundID)-\(sel.customImageRef ?? "")-\(sel.shadow.rawValue)-\(bgT)-\(pT)-\(crop)-\(sel.backgroundBlur)-\(sel.reflectionOpacity)"
        }()
        return "\(s.fillKind.rawValue)-\(s.gradientType.rawValue)-\(s.gradientDirection.rawValue)-\(Int(s.gradientAngleDegrees))-\(s.overlay.rawValue)-\(stopKey)-\(imageKey)-shadow:\(effectiveStudioShadow.isEnabled)-\(Int(effectiveStudioShadow.opacity * 1000))-\(Int(effectiveStudioShadow.blur))"
    }

    private func removeBackgroundWhenPreviewing(product: CapturedProduct) -> Bool {
        product.backgroundRemoved || session.autoBackgroundRemoval
    }

    private var hasBakedMarkupRaster: Bool {
        draftIsRasterEdit
            && draftPreviewImage != nil
            && draftSourceProductID == currentProduct?.id
    }

    private func conflictCopy(_ kind: PreviewMarkupConflictKind) -> (String, String) {
        switch kind {
        case .backgroundRebuild:
            return (
                "Markup & background",
                "This photo includes saved Markup (text and drawing). Rebuilding the background or gradient uses the original capture and removes that Markup.\n\n• Keep Markup — cancel this change\n• Remove Markup & apply — rebuild background (then re-add Markup if needed)"
            )
        case .fullReprocess:
            return (
                "Markup & canvas settings",
                "This photo includes saved Markup. Changing enhancement mode, canvas size, fill, or rotation rebuilds from the original photo and removes Markup.\n\n• Keep Markup — cancel\n• Remove Markup & apply — reprocess without Markup"
            )
        }
    }

    private func guardedBackgroundRebuild(revert: @escaping () -> Void, apply: @escaping () -> Void) {
        guard hasBakedMarkupRaster else {
            apply()
            return
        }
        let copy = conflictCopy(.backgroundRebuild)
        markupConflict = PreviewMarkupConflict(
            title: copy.0,
            message: copy.1,
            onKeepMarkup: { revert() },
            onRebuildWithoutMarkup: {
                clearRasterMarkupDraft()
                apply()
            }
        )
    }

    private func guardedFullReprocess(revert: @escaping () -> Void, apply: @escaping () -> Void) {
        guard hasBakedMarkupRaster else {
            apply()
            return
        }
        let copy = conflictCopy(.fullReprocess)
        markupConflict = PreviewMarkupConflict(
            title: copy.0,
            message: copy.1,
            onKeepMarkup: { revert() },
            onRebuildWithoutMarkup: {
                clearRasterMarkupDraft()
                apply()
            }
        )
    }

    private func clearRasterMarkupDraft() {
        draftIsRasterEdit = false
        draftRasterBaseImage = nil
        draftFilterBaseImage = nil
    }

    private func clearFilterPreviewBase() {
        draftFilterBaseImage = nil
    }

    private func shouldSuppressBackdropFringe() -> Bool {
        panelBackgroundStyle == .solid && {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(panelBackgroundColor).getRed(&r, green: &g, blue: &b, alpha: &a)
            return a >= 0.98 && r >= 0.90 && g >= 0.90 && b >= 0.90
        }()
    }

    private func applyPreviewTuning(to base: UIImage) -> UIImage {
        let imageNameText: String? = {
            guard !panelSuppressBrandMark, let product = currentProduct else { return nil }
            return session.brandKitImageNameText(for: product)
        }()
        var image = ImageProcessor.applyExportTuning(
            to: base,
            photoFilter: panelPhotoFilter,
            photoFilterIntensity: panelPhotoFilterIntensity,
            adjustAutoEnhance: panelAdjustAutoEnhance,
            toneAdjustments: panelToneAdjustments,
            applyBrandMark: !panelSuppressBrandMark,
            imageNameText: imageNameText
        )
        let suppress = shouldSuppressBackdropFringe()
        if suppress {
            image = ImageProcessor.suppressNearWhiteBackdropArtifacts(image, backdrop: UIColor(panelBackgroundColor))
        }
        refreshHistogram(from: image)
        return image
    }

    private func applyPreviewTuningAsync(to base: UIImage) async -> UIImage {
        let filter = panelPhotoFilter
        let intensity = panelPhotoFilterIntensity
        let autoEnhance = panelAdjustAutoEnhance
        let tones = panelToneAdjustments
        let applyMark = !panelSuppressBrandMark
        let imageNameText: String? = {
            guard !panelSuppressBrandMark, let product = currentProduct else { return nil }
            return session.brandKitImageNameText(for: product)
        }()
        let suppressFringe = shouldSuppressBackdropFringe()
        let backdrop = UIColor(panelBackgroundColor)
        let image = await Task.detached(priority: .userInitiated) {
            var image = ImageProcessor.applyExportTuning(
                to: base,
                photoFilter: filter,
                photoFilterIntensity: intensity,
                adjustAutoEnhance: autoEnhance,
                toneAdjustments: tones,
                applyBrandMark: applyMark,
                imageNameText: imageNameText
            )
            if suppressFringe {
                image = ImageProcessor.suppressNearWhiteBackdropArtifacts(image, backdrop: backdrop)
            }
            return image
        }.value
        await MainActor.run { refreshHistogram(from: image) }
        return image
    }

    private func refreshHistogram(from image: UIImage) {
        panelHistogram = ExposureHistogramAnalyzer.analyze(image)
    }

    private var editPolishCanvasSection: some View {
        DSDropdownCanvasPresetMenu(
            currentWidth: panelCanvasWidth,
            currentHeight: panelCanvasHeight,
            includeOriginalAspect: true,
            onOriginalAspect: { applyOriginalAspectCanvasPreset() },
            onSelect: { width, height in applyExportCanvasPreset(width: width, height: height) },
            onCustom: { presentToolSheetAfterDismissingEdit { openCustomCanvasSizeSheet() } }
        ) {
            Label(
                "Canvas · \(panelCanvasWidth)×\(panelCanvasHeight)",
                systemImage: "rectangle.ratio.3.to.4"
            )
            .font(.system(size: 16, weight: .medium))
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 13)
            .foregroundStyle(DS.ColorToken.label)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(DS.ColorToken.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .stroke(DS.ColorToken.separator, lineWidth: 1)
            )
        }
        .accessibilityLabel("Canvas size \(panelCanvasWidth) by \(panelCanvasHeight)")
    }

    /// Nested sheets while Edit & Polish is open often fail to present — dismiss Edit first.
    private func presentToolSheetAfterDismissingEdit(_ present: @escaping () -> Void) {
        if showEditPolishSheet {
            showEditPolishSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                present()
            }
        } else {
            present()
        }
    }

    /// Filter / auto-enhance / tone tweaks only — does not re-run background removal (prevents fringe stains).
    private func scheduleFilterOnlyRender(quality: DraftPreviewQuality = .standard) {
        guard currentProduct != nil else { return }
        draftPreviewQuality = quality
        hasPendingChanges = true
        beforeAfterSplit = 0
        let debounce: UInt64 = quality == .interactive ? 16_000_000 : 40_000_000
        scheduleDraftRender(previewDebounceNanoseconds: debounce)
    }

    /// Rotation / fill / flip / shadow — reuse cached subject cutout and re-composite (no Vision).
    private func scheduleGeometryPreview(quality: DraftPreviewQuality = .standard) {
        guard currentProduct != nil, !draftIsRasterEdit else {
            markPendingAndRender(clearRasterEdit: true, reuseCutout: false, quality: quality)
            return
        }
        draftPreviewQuality = quality
        hasPendingChanges = true
        beforeAfterSplit = 0
        clearFilterPreviewBase()
        draftRenderedBackgroundToken = nil
        let debounce: UInt64 = quality == .interactive ? 16_000_000 : 40_000_000
        scheduleFastBackgroundPreview(debounceNanoseconds: debounce)
    }

    private func currentEditSnapshot() -> PreviewEditSnapshot {
        PreviewEditSnapshot(
            panelPolishEnabled: panelPolishEnabled,
            panelMode: panelMode,
            panelStrength: panelStrength,
            panelFillRatio: panelFillRatio,
            panelCanvasWidth: panelCanvasWidth,
            panelCanvasHeight: panelCanvasHeight,
            panelBackgroundColor: panelBackgroundColor,
            panelSecondaryBackgroundColor: panelSecondaryBackgroundColor,
            panelBackgroundStyle: panelBackgroundStyle,
            panelGradientHexes: panelGradientHexes,
            panelBackgroundFillSpec: panelBackgroundFillSpec,
            panelSelectedPresetID: panelSelectedPresetID,
            panelRotationDegrees: panelRotationDegrees,
            panelFlipHorizontal: panelFlipHorizontal,
            panelFlipVertical: panelFlipVertical,
            panelPhotoFilter: panelPhotoFilter,
            panelPhotoFilterIntensity: panelPhotoFilterIntensity,
            panelAdjustAutoEnhance: panelAdjustAutoEnhance,
            panelToneAdjustments: panelToneAdjustments,
            panelCutoutFeather: panelCutoutFeather,
            panelCutoutBrushMaskData: panelCutoutBrushMaskData,
            panelStudioShadow: panelStudioShadow,
            panelSuppressBrandMark: panelSuppressBrandMark,
            draftJPEG: draftPreviewImage.flatMap { $0.jpegData(compressionQuality: 0.92) },
            draftRasterBaseJPEG: draftRasterBaseImage.flatMap { $0.jpegData(compressionQuality: 0.92) },
            draftIsRasterEdit: draftIsRasterEdit,
            draftSourceProductID: draftSourceProductID
        )
    }

    private func applyEditSnapshot(_ snap: PreviewEditSnapshot) {
        panelPolishEnabled = snap.panelPolishEnabled
        panelMode = snap.panelMode
        panelStrength = snap.panelStrength
        panelFillRatio = snap.panelFillRatio
        panelCanvasWidth = snap.panelCanvasWidth
        panelCanvasHeight = snap.panelCanvasHeight
        panelBackgroundColor = snap.panelBackgroundColor
        panelSecondaryBackgroundColor = snap.panelSecondaryBackgroundColor
        panelBackgroundStyle = snap.panelBackgroundStyle
        panelGradientHexes = snap.panelGradientHexes
        applyPanelFillSpec(snap.panelBackgroundFillSpec, presetID: snap.panelSelectedPresetID)
        panelRotationDegrees = snap.panelRotationDegrees
        panelFlipHorizontal = snap.panelFlipHorizontal
        panelFlipVertical = snap.panelFlipVertical
        panelPhotoFilter = snap.panelPhotoFilter
        panelPhotoFilterIntensity = snap.panelPhotoFilterIntensity
        panelAdjustAutoEnhance = snap.panelAdjustAutoEnhance
        panelToneAdjustments = snap.panelToneAdjustments
        panelCutoutFeather = snap.panelCutoutFeather
        panelCutoutBrushMaskData = snap.panelCutoutBrushMaskData
        panelStudioShadow = snap.panelStudioShadow
        panelSuppressBrandMark = snap.panelSuppressBrandMark

        renderTask?.cancel()
        draftFilterBaseImage = nil
        if snap.draftIsRasterEdit,
           let baseData = snap.draftRasterBaseJPEG,
           let baseImage = UIImage(data: baseData) {
            draftRasterBaseImage = baseImage
            draftIsRasterEdit = true
            draftSourceProductID = snap.draftSourceProductID ?? currentProduct?.id
            hasPendingChanges = true
            beforeAfterSplit = 0
            isRenderingDraft = false
            scheduleDraftRender()
        } else if snap.draftIsRasterEdit,
                  let data = snap.draftJPEG,
                  let image = UIImage(data: data) {
            draftPreviewImage = image
            draftRasterBaseImage = nil
            draftIsRasterEdit = true
            draftSourceProductID = snap.draftSourceProductID ?? currentProduct?.id
            hasPendingChanges = true
            beforeAfterSplit = 0
            isRenderingDraft = false
        } else if let data = snap.draftJPEG, let image = UIImage(data: data) {
            draftPreviewImage = image
            draftRasterBaseImage = nil
            draftIsRasterEdit = snap.draftIsRasterEdit
            draftSourceProductID = snap.draftSourceProductID ?? currentProduct?.id
            hasPendingChanges = true
            beforeAfterSplit = 0
            isRenderingDraft = false
        } else {
            draftPreviewImage = nil
            draftRasterBaseImage = nil
            draftIsRasterEdit = false
            markPendingAndRender(clearRasterEdit: false)
        }
    }

    private func captureUndoSnapshot() {
        if undoSnapshots.count >= 25 { undoSnapshots.removeFirst() }
        undoSnapshots.append(currentEditSnapshot())
        redoSnapshots.removeAll()
    }

    private func undoLastEditSnapshot() {
        guard let previous = undoSnapshots.popLast() else { return }
        redoSnapshots.append(currentEditSnapshot())
        applyEditSnapshot(previous)
    }

    private func redoLastEditSnapshot() {
        guard let next = redoSnapshots.popLast() else { return }
        undoSnapshots.append(currentEditSnapshot())
        applyEditSnapshot(next)
    }

    private func applyOriginalAspectCanvasPreset() {
        guard let p = currentProduct else { return }
        captureUndoSnapshot()
        let oldW = panelCanvasWidth
        let oldH = panelCanvasHeight
        guardedFullReprocess(
            revert: {
                panelCanvasWidth = oldW
                panelCanvasHeight = oldH
            },
            apply: {
                let sz = QueueImageResolver.sourcePixelSize(for: p)
                let sc: CGFloat = 1
                var w = Int(sz.width * sc)
                var h = Int(sz.height * sc)
                guard w > 0, h > 0 else { return }
                let maxEdge = CanvasPresetCatalog.dimensionBounds.upperBound
                let m = max(w, h)
                if m > maxEdge {
                    let f = Double(maxEdge) / Double(m)
                    w = max(300, Int(Double(w) * f))
                    h = max(300, Int(Double(h) * f))
                }
                panelCanvasWidth = min(maxEdge, max(300, w))
                panelCanvasHeight = min(maxEdge, max(300, h))
                markPendingAndRender(clearRasterEdit: true, reuseCutout: true)
            }
        )
    }

    private func applyExportCanvasPreset(width: Int, height: Int) {
        captureUndoSnapshot()
        let oldW = panelCanvasWidth
        let oldH = panelCanvasHeight
        let clamped = CanvasPresetCatalog.clampDimensions(width: width, height: height)
        guardedFullReprocess(
            revert: {
                panelCanvasWidth = oldW
                panelCanvasHeight = oldH
            },
            apply: {
                panelCanvasWidth = clamped.width
                panelCanvasHeight = clamped.height
                markPendingAndRender(clearRasterEdit: true, reuseCutout: true)
            }
        )
    }

    private func bumpPreviewRotation(degrees: Double) {
        captureUndoSnapshot()
        let old = panelRotationDegrees
        guardedFullReprocess(
            revert: { panelRotationDegrees = old },
            apply: {
                InteractionHaptics.tap(vibrate: session.vibrateEnabled)
                panelRotationDegrees = (panelRotationDegrees + degrees).truncatingRemainder(dividingBy: 360)
                scheduleGeometryPreview(quality: .standard)
            }
        )
    }

    private func toggleFlipHorizontal() {
        captureUndoSnapshot()
        let old = panelFlipHorizontal
        guardedFullReprocess(
            revert: { panelFlipHorizontal = old },
            apply: {
                InteractionHaptics.tap(vibrate: session.vibrateEnabled)
                panelFlipHorizontal.toggle()
                scheduleGeometryPreview(quality: .standard)
            }
        )
    }

    private func toggleFlipVertical() {
        captureUndoSnapshot()
        let old = panelFlipVertical
        guardedFullReprocess(
            revert: { panelFlipVertical = old },
            apply: {
                InteractionHaptics.tap(vibrate: session.vibrateEnabled)
                panelFlipVertical.toggle()
                scheduleGeometryPreview(quality: .standard)
            }
        )
    }

    private func toggleFlipBoth() {
        captureUndoSnapshot()
        let oldH = panelFlipHorizontal
        let oldV = panelFlipVertical
        guardedFullReprocess(
            revert: {
                panelFlipHorizontal = oldH
                panelFlipVertical = oldV
            },
            apply: {
                InteractionHaptics.success(vibrate: session.vibrateEnabled)
                panelFlipHorizontal.toggle()
                panelFlipVertical.toggle()
                scheduleGeometryPreview(quality: .standard)
            }
        )
    }

    private func markupEditorBaseImage() -> UIImage? {
        if let d = draftPreviewImage, draftSourceProductID == currentProduct?.id { return d }
        return currentProduct?.image
    }

    private func sharePreviewOriginalUnprocessed() {
        guard let product = currentProduct else { return }
        guard let original = QueueImageResolver.uncompressedOriginal(for: product) else { return }
        let q = session.compressBeforeShare ? session.jpegQuality : 1.0
        let name = product.filename(for: session.imageNamingMode)
        guard let u = ExportManager.jpegURL(for: original, filename: name, quality: q) else { return }
        sharePayload = SharePayload(items: [u], productIDsForRemovalPrompt: [product.id])
    }

    /// Current instruction set for the non-destructive pipeline. Recomputed from the live panel
    /// bindings so any structural change drives a fresh render off the pristine source.
    private var editingAdjustmentState: EditingAdjustmentState {
        EditingAdjustmentState(
            selectedStyle: panelMode,
            studioStrength: panelStrength,
            polishEnabled: panelPolishEnabled,
            backgroundFillType: panelBackgroundFillSpec.fillKind,
            backgroundAngle: panelBackgroundFillSpec.gradientAngleDegrees,
            backgroundFillSpec: panelBackgroundFillSpec,
            primaryBackgroundHex: UIColor(panelBackgroundColor).hexString,
            secondaryBackgroundHex: UIColor(panelSecondaryBackgroundColor).hexString,
            fillRatio: panelFillRatio,
            canvasWidth: panelCanvasWidth,
            canvasHeight: panelCanvasHeight,
            flipHorizontal: panelFlipHorizontal,
            flipVertical: panelFlipVertical
        )
    }

    /// Re-render the canvas from scratch (pristine source -> active style -> background) whenever the
    /// instruction set changes during an active edit. A raster Markup draft is left untouched.
    private func handleAdjustmentStateChange() {
        guard hasPendingChanges, !draftIsRasterEdit else { return }
        // Format Background sheet owns preview updates via the fast composite path.
        if showGradientEditorSheet || showImageBackgroundSheet { return }
        invalidateDraftBackgroundCutout()
        clearFilterPreviewBase()
        scheduleDraftRender()
    }

    private func resetPanelFromCurrentProduct() {
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
        aiPolishEnhanceApplied = false
        invalidateDraftBackgroundCutout()
        guard let product = currentProduct else {
            panelPolishEnabled = session.productPolishEnabled
            panelMode = .standardClean
            panelStrength = CatalogProcessingBaseline.strength
            panelFillRatio = session.outputFillRatio
            panelCanvasWidth = session.outputCanvasWidth
            panelCanvasHeight = session.outputCanvasHeight
            panelRotationDegrees = 0
            draftBakedRotationDegrees = 0
            panelFlipHorizontal = false
            panelFlipVertical = false
            panelPhotoFilter = .none
            panelPhotoFilterIntensity = 1.0
            panelAdjustAutoEnhance = false
            panelToneAdjustments = .neutral
            panelCutoutFeather = 0.35
            panelCutoutBrushMaskData = nil
            panelStudioShadow = .off
            panelHistogram = nil
            panelSuppressBrandMark = false
            panelBackgroundColor = Color(uiColor: session.backgroundColor)
            panelSecondaryBackgroundColor = Color(uiColor: session.secondaryBackgroundColor)
            applyPanelFillSpec(BackgroundFillSpec.fromLegacy(style: session.backgroundCanvasStyle, hexes: session.gradientColorHexes))
            hasPendingChanges = false
            draftPreviewImage = nil
            draftSourceProductID = nil
            draftIsRasterEdit = false
            beforeAfterSplit = 0
            clearBeforeCompareCache()
            showEditPolishSheet = false
            return
        }
        panelPolishEnabled = product.polishEnabled
        panelMode = .standardClean
        panelStrength = CatalogProcessingBaseline.strength
        panelFillRatio = product.fillRatio
        panelCanvasWidth = product.canvasWidth
        panelCanvasHeight = product.canvasHeight
        panelRotationDegrees = product.rotationDegrees
        panelFlipHorizontal = product.flipHorizontal
        panelFlipVertical = product.flipVertical
        panelPhotoFilter = ExportPhotoFilter.resolved(from: product.photoFilter.rawValue)
        panelPhotoFilterIntensity = product.photoFilterIntensity
        panelAdjustAutoEnhance = product.adjustAutoEnhance
        panelToneAdjustments = product.toneAdjustments
        panelCutoutFeather = product.cutoutFeather
        panelCutoutBrushMaskData = product.cutoutBrushMaskData
        panelStudioShadow = product.polishEnabled ? .off : product.studioShadow
        panelHistogram = ExposureHistogramAnalyzer.analyze(product.image)
        panelSuppressBrandMark = product.suppressBrandMark
        panelBackgroundColor = Color(uiColor: product.backgroundColor)
        panelSecondaryBackgroundColor = Color(uiColor: product.secondaryBackgroundColor)
        applyPanelFillSpec(product.resolvedBackgroundFillSpec)
        if let presetID = panelSelectedPresetID,
           let group = GradientPresetGroupLibrary.groupContainingPreset(id: presetID) {
            panelGradientGroupID = group.id
        }
        if panelBackgroundFillSpec.fillKind == .image,
           let bgID = panelBackgroundFillSpec.imageSelection?.backgroundID {
            panelImageCategory = ImageBackgroundFolderCatalog.category(forBackgroundID: bgID)
        }
        beforeAfterSplit = 0
        hasPendingChanges = false
        draftPreviewImage = nil
        draftSourceProductID = nil
        draftRasterBaseImage = nil
        draftFilterBaseImage = nil
        draftIsRasterEdit = false
        draftBakedRotationDegrees = panelRotationDegrees
        clearBeforeCompareCache()
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
        cancelDraftRender()
        showEditPolishSheet = false
        panelSelectedPresetID = nil
    }

    private func markPendingAndRender(
        clearRasterEdit: Bool = false,
        invalidateStyleCache: Bool = true,
        reuseCutout: Bool = false,
        quality: DraftPreviewQuality = .standard
    ) {
        guard let product = currentProduct else { return }
        draftPreviewQuality = quality
        if invalidateStyleCache {
            StylePreviewCacheRevisionStore.shared.invalidate(productID: product.id, reason: "preview edit")
        }
        if clearRasterEdit {
            clearRasterMarkupDraft()
            if reuseCutout {
                // Rotation / fill / canvas size: keep Vision cutout; re-composite only.
                clearFilterPreviewBase()
                draftRenderedBackgroundToken = nil
                hasPendingChanges = true
                beforeAfterSplit = 0
                alignedBeforeCompareImage = nil
                alignedBeforeCompareToken = nil
                scheduleFastBackgroundPreview(
                    debounceNanoseconds: quality == .interactive ? 16_000_000 : 40_000_000
                )
                return
            }
            invalidateDraftBackgroundCutout()
        } else {
            clearFilterPreviewBase()
        }
        hasPendingChanges = true
        beforeAfterSplit = 0
        // Drop stale aligned Before so compare rebuilds against the new canvas/cutout.
        alignedBeforeCompareImage = nil
        alignedBeforeCompareToken = nil
        let debounce: UInt64 = quality == .interactive ? 16_000_000 : 50_000_000
        scheduleDraftRender(previewDebounceNanoseconds: debounce)
    }

    private func cancelDraftRender() {
        renderTask?.cancel()
        renderTask = nil
        isRenderingDraft = false
        syncMagicPreviewOverlay()
    }

    private func resetDraftPreviewCaches() {
        invalidateDraftBackgroundCutout()
        draftPreviewImage = nil
        draftSourceProductID = nil
        draftRasterBaseImage = nil
        draftFilterBaseImage = nil
    }

    @MainActor
    private func finishDraftRenderIfCurrent(generation: UInt) {
        guard generation == draftRenderGeneration else { return }
        isRenderingDraft = false
        syncMagicPreviewOverlay()
    }

    /// Draft preview resolution by quality tier (Apply still uses full export pipeline).
    private func draftPreviewCanvasSize(for fillSpec: BackgroundFillSpec) -> (width: Int, height: Int) {
        let fullW = panelCanvasWidth
        let fullH = panelCanvasHeight
        let longest = max(fullW, fullH)
        let isImageBG = fillSpec.fillKind == .image
        let fraction: Double = {
            switch draftPreviewQuality {
            case .interactive:
                return isImageBG ? 0.40 : 0.45
            case .standard:
                if showGradientEditorSheet || showImageBackgroundSheet {
                    return isImageBG ? 0.52 : 0.58
                }
                return isImageBG ? 0.55 : 0.62
            case .final:
                return isImageBG ? 0.80 : 0.85
            }
        }()
        let minCap = draftPreviewQuality == .interactive ? 480 : 560
        let maxEdge = min(longest, max(minCap, Int((Double(longest) * fraction).rounded())))
        guard longest > maxEdge else { return (fullW, fullH) }
        let scale = Double(maxEdge) / Double(longest)
        return (
            max(280, Int((Double(fullW) * scale).rounded())),
            max(280, Int((Double(fullH) * scale).rounded()))
        )
    }

    private func scheduleDraftRender(previewDebounceNanoseconds: UInt64 = 50_000_000) {
        guard !isApplying else { return }
        draftRenderGeneration &+= 1
        let generation = draftRenderGeneration
        // Clear busy flag immediately when superseding — otherwise cancelled tasks never clear it.
        if isRenderingDraft {
            isRenderingDraft = false
            syncMagicPreviewOverlay()
        }
        performFullPipelineDraftRender(
            previewDebounceNanoseconds: previewDebounceNanoseconds,
            generation: generation
        )
    }

    private func performFullPipelineDraftRender(
        previewDebounceNanoseconds: UInt64,
        generation: UInt
    ) {
        guard let product = currentProduct else {
            cancelDraftRender()
            return
        }
        let productID = product.id
        renderTask?.cancel()

        let renderWatchdog = generation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard renderWatchdog == draftRenderGeneration, isRenderingDraft else { return }
            renderTask?.cancel()
            renderTask = nil
            isRenderingDraft = false
            syncMagicPreviewOverlay()
        }

        if draftIsRasterEdit,
           let base = draftRasterBaseImage,
           draftSourceProductID == productID {
            renderTask = Task {
                defer {
                    Task { @MainActor in
                        finishDraftRenderIfCurrent(generation: generation)
                    }
                }
                try? await Task.sleep(nanoseconds: 40_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard generation == draftRenderGeneration else { return }
                    isRenderingDraft = true
                    syncMagicPreviewOverlay()
                }
                let tuned = await applyPreviewTuningAsync(to: base)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard generation == draftRenderGeneration, currentProduct?.id == productID else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        draftPreviewImage = tuned
                        draftSourceProductID = productID
                    }
                }
            }
            return
        }

        if !draftIsRasterEdit,
           let base = draftFilterBaseImage,
           draftSourceProductID == productID {
            renderTask = Task {
                defer {
                    Task { @MainActor in
                        finishDraftRenderIfCurrent(generation: generation)
                    }
                }
                try? await Task.sleep(nanoseconds: 40_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard generation == draftRenderGeneration else { return }
                    isRenderingDraft = true
                    syncMagicPreviewOverlay()
                }
                let tuned = await applyPreviewTuningAsync(to: base)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard generation == draftRenderGeneration, currentProduct?.id == productID else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        draftPreviewImage = tuned
                        draftSourceProductID = productID
                    }
                }
            }
            return
        }

        let mode = panelMode
        let strength = panelStrength
        let fill = panelFillRatio
        let polish = panelPolishEnabled
        let bgColor = UIColor(panelBackgroundColor)
        let bg2Color = UIColor(panelSecondaryBackgroundColor)
        let bgStyle = panelBackgroundStyle
        let gradientHexes = panelGradientHexes
        var fillSpec = panelBackgroundFillSpec
        fillSpec.normalizeStops()

        let previewCanvas = draftPreviewCanvasSize(for: fillSpec)
        let targetW = previewCanvas.width
        let targetH = previewCanvas.height

        let colorAccuracy = session.smartColorAccuracyEnabled
        let upscale = false // Smart Upscale removed.
        let rot = panelRotationDegrees
        let flipH = panelFlipHorizontal
        let flipV = panelFlipVertical
        let removeBG = removeBackgroundWhenPreviewing(product: product)
        let feather = panelCutoutFeather
        let brushMask = panelCutoutBrushMaskData
        let shadow = effectiveStudioShadow
        let preferInteractive = draftPreviewQuality == .interactive
        let previewSourceCap = ImageProcessor.previewSourceLongEdgeCap(
            canvasWidth: targetW,
            canvasHeight: targetH,
            preferInteractive: preferInteractive
        )
        let memorySourceCap = MemoryPressureMonitor.shared.recommendedProcessingLongEdge
        let maxSourceLongEdge = min(previewSourceCap, memorySourceCap)
        renderTask = Task {
            defer {
                Task { @MainActor in
                    finishDraftRenderIfCurrent(generation: generation)
                }
            }
            try? await Task.sleep(nanoseconds: previewDebounceNanoseconds)
            if Task.isCancelled { return }

            await MainActor.run {
                guard generation == draftRenderGeneration else { return }
                isRenderingDraft = true
                syncMagicPreviewOverlay()
            }

            let pipelineResult = await HeavyProcessingGate.shared.withExclusiveAccess {
                let sourceImage = await Task.detached(priority: .utility) {
                    autoreleasepool { QueueImageResolver.reliableOriginalForReprocess(product) }
                }.value
                guard let sourceImage else { return PipelineRenderResult.missingSource }

                let exportResult = await ImageProcessor.processForExportAsync(
                    sourceImage,
                    removeBackground: removeBG,
                    canvasWidth: targetW,
                    canvasHeight: targetH,
                    rotationDegrees: rot,
                    fillRatio: fill,
                    polishEnabled: polish,
                    enhancementMode: mode,
                    studioAIStrength: strength,
                    backgroundColor: bgColor,
                    secondaryBackgroundColor: bg2Color,
                    backgroundStyle: bgStyle,
                    gradientColorHexes: gradientHexes,
                    backgroundFillSpec: fillSpec,
                    smartColorAccuracy: colorAccuracy,
                    smartUpscale: upscale,
                    flipHorizontal: flipH,
                    flipVertical: flipV,
                    photoFilter: .none,
                    photoFilterIntensity: 1.0,
                    adjustAutoEnhance: false,
                    toneAdjustments: .neutral,
                    cutoutFeather: feather,
                    cutoutBrushMaskData: brushMask,
                    studioShadow: shadow,
                    applyBrandMark: false,
                    qos: preferInteractive ? .utility : .userInitiated,
                    maxSourceLongEdge: maxSourceLongEdge
                )
                guard ImageProcessor.isValidExportBitmap(exportResult.image) else {
                    return PipelineRenderResult.invalidBitmap
                }
                let tuned = await applyPreviewTuningAsync(to: exportResult.image)
                return .success(filterBase: exportResult.image, preview: tuned)
            }

            if Task.isCancelled { return }
            switch pipelineResult {
            case .missingSource, .invalidBitmap:
                await MainActor.run {
                    guard generation == draftRenderGeneration else { return }
                    isRenderingDraft = false
                    syncMagicPreviewOverlay()
                }
                return
            case .success(let filterBase, let preview):
                await MainActor.run {
                    guard generation == draftRenderGeneration, currentProduct?.id == productID else { return }
                    draftFilterBaseImage = filterBase
                    draftBakedRotationDegrees = rot
                    withAnimation(.easeInOut(duration: 0.18)) {
                        draftPreviewImage = preview
                        draftSourceProductID = productID
                        draftBakedRotationDegrees = rot
                    }
                }
            }
        }
    }

    private enum PipelineRenderResult {
        case missingSource
        case invalidBitmap
        case success(filterBase: UIImage, preview: UIImage)
    }

    private func applyCurrentPanelSettings(navigateAfterApply: Int? = nil, openSharePickerOnComplete: Bool = false) {
        guard let product = currentProduct, !isApplying else { return }
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)
        cancelDraftRender()
        liveRenderTask?.cancel()
        liveRenderTask = nil
        invalidateDraftBackgroundCutout()
        draftPreviewImage = nil
        draftFilterBaseImage = nil
        draftRasterBaseImage = nil
        ImageBackgroundAssetLoader.clearMemoryCaches()
        isApplying = true
        syncMagicPreviewOverlay()
        beforeAfterSplit = 0

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 32_000_000)
            syncMagicPreviewOverlay()
            applyCurrentPanelSettingsAfterOverlayPainted(
                product: product,
                navigateAfterApply: navigateAfterApply,
                openSharePickerOnComplete: openSharePickerOnComplete
            )
        }
    }

    private func applyCurrentPanelSettingsAfterOverlayPainted(
        product: CapturedProduct,
        navigateAfterApply: Int? = nil,
        openSharePickerOnComplete: Bool = false
    ) {
        let bgColor = UIColor(panelBackgroundColor)
        let bg2Color = UIColor(panelSecondaryBackgroundColor)
        let bgStyle = panelBackgroundStyle
        let fillSpec = panelBackgroundFillSpec
        let navTarget = navigateAfterApply
        let finishApply: () -> Void = {
            StylePreviewCacheRevisionStore.shared.invalidate(productID: product.id, reason: "applied")
            undoSnapshots.removeAll()
            redoSnapshots.removeAll()
            hasPendingChanges = false
            draftPreviewImage = nil
            draftSourceProductID = nil
            draftRasterBaseImage = nil
            draftFilterBaseImage = nil
            draftIsRasterEdit = false
            isRenderingDraft = false
            isApplying = false
            syncMagicPreviewOverlay()
            showGradientEditorSheet = false
            resetPreviewZoom()
            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) { showAppliedToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                withAnimation(.easeInOut(duration: 0.18)) { showAppliedToast = false }
            }
            if let target = navTarget {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { moveToIndex(target) }
            } else {
                resetPanelFromCurrentProduct()
            }
            if openSharePickerOnComplete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showPreviewShareDialog = true
                }
            }
        }

        if draftIsRasterEdit, let raster = draftPreviewImage, draftSourceProductID == product.id {
            let filter = panelPhotoFilter
            let intensity = panelPhotoFilterIntensity
            let autoEnhance = panelAdjustAutoEnhance
            let tones = panelToneAdjustments
            let feather = panelCutoutFeather
            let brush = panelCutoutBrushMaskData
            let shadow = effectiveStudioShadow
            Task.detached(priority: .userInitiated) {
                let tuned = ImageProcessor.applyExportTuning(
                    to: raster,
                    photoFilter: filter,
                    photoFilterIntensity: intensity,
                    adjustAutoEnhance: autoEnhance,
                    toneAdjustments: tones,
                    applyBrandMark: false
                )
                await MainActor.run {
                    session.commitRasterPreview(
                        for: product,
                        image: tuned,
                        polishEnabled: panelPolishEnabled,
                        enhancementMode: panelMode,
                        studioAIStrength: panelStrength,
                        canvasWidth: panelCanvasWidth,
                        canvasHeight: panelCanvasHeight,
                        rotationDegrees: panelRotationDegrees,
                        fillRatio: panelFillRatio,
                        backgroundColor: bgColor,
                        secondaryBackgroundColor: bg2Color,
                        backgroundStyle: bgStyle,
                        gradientColorHexes: panelGradientHexes,
                        backgroundFillSpec: fillSpec,
                        flipHorizontal: panelFlipHorizontal,
                        flipVertical: panelFlipVertical,
                        photoFilter: filter,
                        photoFilterIntensity: intensity,
                        adjustAutoEnhance: autoEnhance,
                        toneAdjustments: tones,
                        cutoutFeather: feather,
                        cutoutBrushMaskData: brush,
                        studioShadow: shadow,
                        suppressBrandMark: panelSuppressBrandMark,
                        completion: finishApply
                    )
                }
            }
            return
        }

        session.reprocessProduct(
            product,
            removeBackground: removeBackgroundWhenPreviewing(product: product),
            polishEnabled: panelPolishEnabled,
            enhancementMode: panelMode,
            studioAIStrength: panelStrength,
            canvasWidth: panelCanvasWidth,
            canvasHeight: panelCanvasHeight,
            rotationDegrees: panelRotationDegrees,
            fillRatio: panelFillRatio,
            backgroundColor: bgColor,
            secondaryBackgroundColor: bg2Color,
            backgroundStyle: bgStyle,
            gradientColorHexes: panelGradientHexes,
            backgroundFillSpec: fillSpec,
            flipHorizontal: panelFlipHorizontal,
            flipVertical: panelFlipVertical,
            photoFilter: panelPhotoFilter,
            photoFilterIntensity: panelPhotoFilterIntensity,
            adjustAutoEnhance: panelAdjustAutoEnhance,
            toneAdjustments: panelToneAdjustments,
            cutoutFeather: panelCutoutFeather,
            cutoutBrushMaskData: .some(panelCutoutBrushMaskData),
            studioShadow: effectiveStudioShadow,
            suppressBrandMark: panelSuppressBrandMark,
            completion: finishApply
        )
    }

    private func requestNavigation(to target: Int) {
        let safeTarget = min(max(0, target), max(0, session.products.count - 1))
        guard safeTarget != selectedIndex else { return }
        if hasPendingChanges {
            pendingNavigationIndex = safeTarget
            showPendingNavigationAlert = true
        } else {
            moveToIndex(safeTarget)
        }
    }

    private func moveToIndex(_ target: Int) {
        straightenRenderTask?.cancel()
        cancelDraftRender()
        pendingNavigationIndex = nil
        showPendingNavigationAlert = false
        selectedIndex = target
        if !session.products.isEmpty {
            let idx = min(max(0, target), session.products.count - 1)
            session.ensureProcessedImageInMemory(productID: session.products[idx].id)
        }
        resetPreviewZoom()
        showEditPolishSheet = false
        showGradientEditorSheet = false
        resetPanelFromCurrentProduct()
    }

    /// Photos-style duplicate: always saves a full-resolution render (never the draft preview bitmap).
    private func saveAsDuplicateFromEditPanel() {
        guard let product = currentProduct else { return }
        isApplying = true

        let finishDuplicate: (UIImage) -> Void = { image in
            let bgColor = UIColor(panelBackgroundColor)
            let bg2Color = UIColor(panelSecondaryBackgroundColor)
            let fillSpec = panelBackgroundFillSpec
            let duplicate = session.insertDuplicateOfProduct(
                product,
                image: image,
                polishEnabled: panelPolishEnabled,
                enhancementMode: panelMode,
                studioAIStrength: panelStrength,
                canvasWidth: panelCanvasWidth,
                canvasHeight: panelCanvasHeight,
                rotationDegrees: panelRotationDegrees,
                fillRatio: panelFillRatio,
                backgroundColor: bgColor,
                secondaryBackgroundColor: bg2Color,
                backgroundStyle: panelBackgroundStyle,
                gradientColorHexes: panelGradientHexes,
                backgroundFillSpec: fillSpec,
                flipHorizontal: panelFlipHorizontal,
                flipVertical: panelFlipVertical,
                photoFilter: panelPhotoFilter,
                photoFilterIntensity: panelPhotoFilterIntensity,
                adjustAutoEnhance: panelAdjustAutoEnhance,
                toneAdjustments: panelToneAdjustments,
                cutoutFeather: panelCutoutFeather,
                cutoutBrushMaskData: panelCutoutBrushMaskData,
                studioShadow: effectiveStudioShadow,
                suppressBrandMark: panelSuppressBrandMark
            )
            isApplying = false
            if let idx = session.products.firstIndex(where: { $0.id == duplicate.id }) {
                moveToIndex(idx)
            }
            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) { showAppliedToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                withAnimation(.easeInOut(duration: 0.18)) { showAppliedToast = false }
            }
        }

        Task {
            guard let image = await renderFullResolutionExportImage(for: product) else {
                await MainActor.run { isApplying = false }
                return
            }
            await MainActor.run { finishDuplicate(image) }
        }
    }

    /// Full-canvas process + panel tuning — used for share/duplicate so draft previews never leave the app.
    private func renderFullResolutionExportImage(for product: CapturedProduct) async -> UIImage? {
        var fillSpec = panelBackgroundFillSpec
        fillSpec.normalizeStops()
        guard let source = await QueueImageResolver.uncompressedOriginal(for: product) else { return nil }
        ImageProcessor.invalidateCutoutCache(productID: product.id)
        let result = await ImageProcessor.processForExportAsync(
            source,
            removeBackground: removeBackgroundWhenPreviewing(product: product),
            canvasWidth: panelCanvasWidth,
            canvasHeight: panelCanvasHeight,
            rotationDegrees: panelRotationDegrees,
            fillRatio: panelFillRatio,
            polishEnabled: panelPolishEnabled,
            enhancementMode: panelMode,
            studioAIStrength: panelStrength,
            backgroundColor: UIColor(panelBackgroundColor),
            secondaryBackgroundColor: UIColor(panelSecondaryBackgroundColor),
            backgroundStyle: panelBackgroundStyle,
            gradientColorHexes: panelGradientHexes,
            backgroundFillSpec: fillSpec,
            smartColorAccuracy: session.smartColorAccuracyEnabled,
            smartUpscale: false,
            flipHorizontal: panelFlipHorizontal,
            flipVertical: panelFlipVertical,
            photoFilter: .none,
            photoFilterIntensity: 1.0,
            adjustAutoEnhance: false,
            toneAdjustments: .neutral,
            cutoutFeather: panelCutoutFeather,
            cutoutBrushMaskData: panelCutoutBrushMaskData,
            studioShadow: effectiveStudioShadow,
            applyBrandMark: false
        )
        return await MainActor.run { applyPreviewTuning(to: result.image) }
    }

    private func resetPanelToWhite() {
        captureUndoSnapshot()
        let oldSpec = panelBackgroundFillSpec
        let oldPresetID = panelSelectedPresetID
        guardedBackgroundRebuild(
            revert: { applyPanelFillSpec(oldSpec, presetID: oldPresetID) },
            apply: { applyPanelFillSpec(.catalogWhite, presetID: nil); markBackgroundPendingAndRender() }
        )
    }

    private func startPreviewRename() {
        guard let product = currentProduct else { return }
        previewRenameText = product.upc
        showRenameAlert = true
    }

    private func previewStartReplace() {
        showReplaceCamera = true
    }

    /// Same mutation path as `QueueView.quickApply` for the active queue row.
    private func previewQueueQuickApply(mode: PhotoEnhancementMode, strength: StudioAIStrength) {
        guard let product = currentProduct else { return }
        cancelDraftRender()
        beforeAfterSplit = 0
        hasPendingChanges = false
        session.reprocessProduct(
            product,
            removeBackground: product.backgroundRemoved || session.autoBackgroundRemoval,
            polishEnabled: true,
            enhancementMode: mode,
            studioAIStrength: strength,
            canvasWidth: product.canvasWidth,
            canvasHeight: product.canvasHeight,
            fillRatio: product.fillRatio,
            backgroundColor: product.backgroundColor,
            secondaryBackgroundColor: product.secondaryBackgroundColor,
            backgroundStyle: product.backgroundStyle,
            gradientColorHexes: product.gradientColorHexes,
            completion: { resetPanelFromCurrentProduct() }
        )
    }

    private func previewApplyDefringeSharpen(to product: CapturedProduct) {
        session.applyDefringeSharpen(to: product)
        if product.id == currentProduct?.id {
            resetPanelFromCurrentProduct()
        }
    }

    private func deleteCurrentAndDismissIfNeeded() {
        guard let product = currentProduct else { return }
        session.remove(product)
        if session.products.isEmpty { dismiss() }
        else { selectedIndex = min(selectedIndex, session.products.count - 1); resetPreviewZoom(); resetPanelFromCurrentProduct() }
    }

    private func shareCurrentImage() {
        guard let product = currentProduct,
              let url = ExportManager.imageURL(
                for: product,
                namingMode: session.imageNamingMode,
                quality: session.compressBeforeShare ? session.jpegQuality : 1.0,
                cleanFolder: true
              ) else { return }
        sharePayload = SharePayload(items: [url], productIDsForRemovalPrompt: [product.id])
    }

    private func previewShareImage() -> UIImage? {
        guard let product = currentProduct else { return nil }
        // Never share a reduced draft preview — callers that need pending edits must render full-res first.
        return product.image
    }

    private var previewCSVAskPresented: Binding<Bool> {
        Binding(
            get: { pendingPreviewCSVAsk != nil },
            set: { if !$0 { pendingPreviewCSVAsk = nil } }
        )
    }

    private func runPreviewShare(
        includeImages: Bool,
        includeCSV: Bool,
        format: ExportImageFormat = .jpg,
        asZip: Bool = false
    ) {
        guard let product = currentProduct else { return }
        let q = session.compressBeforeShare ? session.jpegQuality : 1.0
        let namingMode = session.imageNamingMode

        loadingState?.runAction(
            key: "preview-export-\(product.id)-\(format.rawValue)-\(asZip)",
            message: "Exporting…",
            global: true,
            vibrate: session.vibrateEnabled
        ) {
            let resolvedImage: UIImage?
            if includeImages {
                if self.hasPendingChanges, self.draftSourceProductID == product.id {
                    resolvedImage = await self.renderFullResolutionExportImage(for: product)
                } else {
                    resolvedImage = product.image
                }
            } else {
                resolvedImage = nil
            }
            if includeImages, resolvedImage == nil { return }

            if asZip, let image = resolvedImage {
                let exportProduct = product.replacingProcessedImage(image)
                var context = ExportPackageContext(
                    projectName: session.activeCatalogSessionName,
                    marketplaceProfile: MarketplaceExportProfileID.from(exportChannel: session.exportChannelProfile),
                    brandName: session.brandMarkText,
                    namingMode: namingMode,
                    jpegQuality: q
                )
                context.imageProvider = { candidate in
                    candidate.id == exportProduct.id ? image : candidate.image
                }
                let url = await Task.detached(priority: .userInitiated) {
                    ExportManager.zipExportURL(for: [exportProduct], context: context)
                }.value
                guard let url else { return }
                await MainActor.run {
                    sharePayload = SharePayload(items: [url], productIDsForRemovalPrompt: [product.id])
                }
                return
            }

            let urls = await Task.detached(priority: .userInitiated) {
                var urls: [URL] = []
                var exportFolder: URL?
                if includeImages, let image = resolvedImage {
                    let file = product.filename(for: namingMode, format: format)
                    let url: URL?
                    switch format {
                    case .jpg:
                        url = ExportManager.jpegURL(for: image, filename: file, quality: q)
                    case .png:
                        let pngSource = ExportManager.transparentCutoutImage(for: product) ?? image
                        url = ExportManager.pngURL(for: pngSource, filename: file)
                    }
                    guard let u = url else { return [] }
                    urls.append(u)
                    exportFolder = u.deletingLastPathComponent()
                }
                if includeCSV, let c = ExportManager.csvURL(
                    for: [product],
                    namingMode: namingMode,
                    folder: exportFolder,
                    formats: includeImages ? [format] : [.jpg]
                ) {
                    urls.append(c)
                }
                return urls
            }.value
            guard !urls.isEmpty else { return }
            await MainActor.run {
                sharePayload = SharePayload(items: urls, productIDsForRemovalPrompt: [product.id])
            }
        }
    }

    private func runPreviewShareAllFormats() {
        guard let product = currentProduct else { return }
        let q = session.compressBeforeShare ? session.jpegQuality : 1.0
        let namingMode = session.imageNamingMode

        loadingState?.runAction(
            key: "preview-export-all-\(product.id)",
            message: "Exporting…",
            global: true,
            vibrate: session.vibrateEnabled
        ) {
            let image: UIImage?
            if self.hasPendingChanges, self.draftSourceProductID == product.id {
                image = await self.renderFullResolutionExportImage(for: product)
            } else {
                image = product.image
            }
            guard let image else { return }

            let urls = await Task.detached(priority: .userInitiated) {
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ProductStudioSingleShare", isDirectory: true)
                try? FileManager.default.removeItem(at: folder)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var urls: [URL] = []
                for format in ExportImageFormat.allCases {
                    let file = product.filename(for: namingMode, format: format)
                    let url: URL?
                    switch format {
                    case .jpg:
                        url = ExportManager.jpegURL(for: image, filename: file, quality: q)
                    case .png:
                        let pngSource = ExportManager.transparentCutoutImage(for: product) ?? image
                        url = ExportManager.pngURL(for: pngSource, filename: file)
                    }
                    if let u = url { urls.append(u) }
                }
                if let c = ExportManager.csvURL(
                    for: [product],
                    namingMode: namingMode,
                    folder: folder,
                    formats: ExportImageFormat.allCases
                ) {
                    urls.append(c)
                }
                return urls
            }.value
            guard !urls.isEmpty else { return }
            await MainActor.run {
                sharePayload = SharePayload(items: urls, productIDsForRemovalPrompt: [product.id])
            }
        }
    }

}
