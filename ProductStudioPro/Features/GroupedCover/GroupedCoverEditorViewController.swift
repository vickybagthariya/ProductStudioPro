import SwiftUI
import UIKit

// MARK: - SwiftUI bridge

struct GroupedCoverEditorSheet: View {
    let sourceProducts: [CapturedProduct]
    let canvasWidth: Int
    let canvasHeight: Int
    let fillRatio: Double
    let backgroundFillSpec: BackgroundFillSpec
    let primaryColor: UIColor
    let secondaryColor: UIColor
    var coverName: String = ""
    var existingLayout: CompositeBundleLayout?
    var editingProductID: UUID?
    let onSave: (UIImage, CompositeBundleLayout) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var processingMessage: String?

    var body: some View {
        ZStack {
            GroupedCoverEditorBridge(
                sourceProducts: sourceProducts,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
                fillRatio: fillRatio,
                backgroundFillSpec: backgroundFillSpec,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                coverName: coverName,
                existingLayout: existingLayout,
                editingProductID: editingProductID,
                processingMessage: $processingMessage,
                onSave: { image, layout in
                    onSave(image, layout)
                    dismiss()
                },
                onCancel: {
                    onCancel()
                    dismiss()
                }
            )
            .ignoresSafeArea()

            if let processingMessage {
                MagicPreviewOverlayHost(isApplying: true, message: processingMessage)
            }
        }
    }
}

struct GroupedCoverEditorBridge: UIViewControllerRepresentable {
    let sourceProducts: [CapturedProduct]
    let canvasWidth: Int
    let canvasHeight: Int
    let fillRatio: Double
    let backgroundFillSpec: BackgroundFillSpec
    let primaryColor: UIColor
    let secondaryColor: UIColor
    var coverName: String = ""
    var existingLayout: CompositeBundleLayout?
    var editingProductID: UUID?
    @Binding var processingMessage: String?
    let onSave: (UIImage, CompositeBundleLayout) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSave: onSave, onCancel: onCancel, processingMessage: $processingMessage)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let root = GroupedCoverEditorViewController()
        root.coordinator = context.coordinator
        root.sourceProducts = sourceProducts
        root.canvasWidth = canvasWidth
        root.canvasHeight = canvasHeight
        root.fillRatio = fillRatio
        root.backgroundFillSpec = backgroundFillSpec
        root.primaryColor = primaryColor
        root.secondaryColor = secondaryColor
        root.coverName = coverName
        root.existingLayout = existingLayout
        root.editingProductID = editingProductID
        let nav = UINavigationController(rootViewController: root)
        nav.modalPresentationStyle = .fullScreen
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator {
        let onSave: (UIImage, CompositeBundleLayout) -> Void
        let onCancel: () -> Void
        var processingMessage: Binding<String?>

        init(
            onSave: @escaping (UIImage, CompositeBundleLayout) -> Void,
            onCancel: @escaping () -> Void,
            processingMessage: Binding<String?>
        ) {
            self.onSave = onSave
            self.onCancel = onCancel
            self.processingMessage = processingMessage
        }

        func setProcessingMessage(_ message: String?) {
            // UIKit can call this during appearance/layout; defer so SwiftUI
            // is not mutated mid view-update.
            DispatchQueue.main.async { [processingMessage] in
                processingMessage.wrappedValue = message
            }
        }
    }
}

// MARK: - Canvas background

private final class GroupedCoverCanvasBackgroundView: UIView {
    var primaryColor: UIColor = .white
    var secondaryColor: UIColor = UIColor(white: 0.94, alpha: 1)
    var fillSpec: BackgroundFillSpec = BackgroundFillSpec()

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        BackgroundFillRenderer.draw(
            in: rect,
            context: ctx,
            primary: primaryColor,
            secondary: secondaryColor,
            spec: fillSpec
        )
    }
}

// MARK: - Preset cell

private final class GridPresetCell: UICollectionViewCell {
    static let reuseID = "GridPresetCell"

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor.secondarySystemBackground
        contentView.layer.cornerRadius = 10
        contentView.layer.cornerCurve = .continuous
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(matrix: CompositeLayoutMatrix, selected: Bool) {
        titleLabel.text = matrix.label
        contentView.backgroundColor = selected ? UIColor.systemBlue.withAlphaComponent(0.18) : UIColor.secondarySystemBackground
        contentView.layer.borderWidth = selected ? 2 : 0
        contentView.layer.borderColor = selected ? UIColor.systemBlue.cgColor : nil
    }
}

// MARK: - Editor view controller

final class GroupedCoverEditorViewController: UIViewController {
    var coordinator: GroupedCoverEditorBridge.Coordinator?
    var sourceProducts: [CapturedProduct] = []
    var canvasWidth: Int = 1200
    var canvasHeight: Int = 1200
    var fillRatio: Double = 0.95
    var backgroundFillSpec: BackgroundFillSpec = BackgroundFillSpec()
    var primaryColor: UIColor = .white
    var secondaryColor: UIColor = UIColor(white: 0.94, alpha: 1)
    var coverName: String = ""
    var existingLayout: CompositeBundleLayout?
    var editingProductID: UUID?

    private struct LayerState {
        var item: CompositeLayerItem
        let product: CapturedProduct
        let imageView: UIImageView
        var cutoutSize: CGSize
    }

    private var layers: [LayerState] = []
    private var currentMatrix = CompositeLayoutMatrix.defaultMatrix(forProductCount: 2)
    private var gridGapPoints = CompositeLayoutEngine.defaultGridGapPoints
    private var isFreeformMode = false
    private var selectedLayerIndex = 0
    private var isSaving = false

    private var draggingLayerIndex: Int?
    private var dragOffset: CGPoint = .zero
    private var preloadGeneration: Int = 0
    private var baselineLayout: CompositeBundleLayout?

    private let workspaceView = UIView()
    private let canvasContainer = UIView()
    private let canvasView = GroupedCoverCanvasBackgroundView()
    private let controlsBar = UIStackView()
    private let gapLabel = UILabel()
    private let presetCollectionView: UICollectionView
    private let freeformSwitch = UISwitch()
    private var canvasAspectConstraint: NSLayoutConstraint?

    private var canvasPixelSize: CGSize {
        CGSize(width: CGFloat(max(1, canvasWidth)), height: CGFloat(max(1, canvasHeight)))
    }

    private var eligiblePresets: [CompositeLayoutMatrix] {
        CompositeLayoutMatrix.presets(forProductCount: sourceProducts.count)
    }

    private var activeCellCount: Int {
        max(1, layers.isEmpty ? sourceProducts.count : layers.count)
    }

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        presetCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        releasePreviewBitmaps()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        if let layout = existingLayout {
            currentMatrix = layout.matrix
            gridGapPoints = CGFloat(layout.gridGapPoints)
            isFreeformMode = layout.isFreeformMode
            canvasWidth = layout.resolvedCanvasWidth
            canvasHeight = layout.resolvedCanvasHeight
        } else {
            currentMatrix = CompositeLayoutMatrix.defaultMatrix(forProductCount: max(2, sourceProducts.count))
        }
        configureNavigation()
        configureLayout()
        showBlockingOverlay(message: "Preparing cutouts…")
        preloadCutouts()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !layers.isEmpty, coordinator?.processingMessage.wrappedValue == nil else { return }
        applyAllLayerTransforms(animated: false)
    }

    private func configureNavigation() {
        title = editingProductID == nil ? "Grouped Cover" : "Edit Grouped Cover"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )

        freeformSwitch.isOn = isFreeformMode
        freeformSwitch.addTarget(self, action: #selector(freeformToggled), for: .valueChanged)
        let freeformItem = UIBarButtonItem(customView: makeFreeformControl())
        let aspectItem = UIBarButtonItem(
            image: UIImage(systemName: "rectangle.ratio.3.to.4"),
            menu: makeCanvasAspectMenu()
        )
        aspectItem.accessibilityLabel = "Canvas aspect"
        let forwardItem = UIBarButtonItem(
            image: UIImage(systemName: "square.3.layers.3d.top.filled"),
            style: .plain,
            target: self,
            action: #selector(bringForwardTapped)
        )
        let backwardItem = UIBarButtonItem(
            image: UIImage(systemName: "square.3.layers.3d.bottom.filled"),
            style: .plain,
            target: self,
            action: #selector(sendBackwardTapped)
        )
        toolbarItems = [aspectItem, .flexibleSpace(), freeformItem, .flexibleSpace(), backwardItem, forwardItem]
        navigationController?.isToolbarHidden = false
    }

    private func makeFreeformControl() -> UIView {
        let stack = UIStackView(arrangedSubviews: [
            { let l = UILabel(); l.text = "Freeform"; l.font = .systemFont(ofSize: 13, weight: .medium); return l }(),
            freeformSwitch,
        ])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }

    private func configureLayout() {
        workspaceView.translatesAutoresizingMaskIntoConstraints = false
        canvasContainer.translatesAutoresizingMaskIntoConstraints = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        controlsBar.translatesAutoresizingMaskIntoConstraints = false
        presetCollectionView.translatesAutoresizingMaskIntoConstraints = false

        canvasView.primaryColor = primaryColor
        canvasView.secondaryColor = secondaryColor
        canvasView.fillSpec = backgroundFillSpec
        canvasView.clipsToBounds = true
        canvasView.layer.cornerRadius = 8
        canvasView.layer.cornerCurve = .continuous

        controlsBar.axis = .horizontal
        controlsBar.alignment = .center
        controlsBar.spacing = 12
        controlsBar.distribution = .fill

        gapLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        gapLabel.textColor = .label
        gapLabel.textAlignment = .center
        gapLabel.setContentHuggingPriority(.required, for: .horizontal)
        updateGapLabel()

        let decreaseGap = makeGapButton(systemName: "minus.circle.fill", action: #selector(decreaseGapTapped))
        let increaseGap = makeGapButton(systemName: "plus.circle.fill", action: #selector(increaseGapTapped))
        controlsBar.addArrangedSubview(decreaseGap)
        controlsBar.addArrangedSubview(gapLabel)
        controlsBar.addArrangedSubview(increaseGap)

        canvasContainer.addSubview(canvasView)
        workspaceView.addSubview(canvasContainer)
        view.addSubview(workspaceView)
        view.addSubview(controlsBar)
        view.addSubview(presetCollectionView)

        presetCollectionView.backgroundColor = .clear
        presetCollectionView.showsHorizontalScrollIndicator = false
        presetCollectionView.dataSource = self
        presetCollectionView.delegate = self
        presetCollectionView.register(GridPresetCell.self, forCellWithReuseIdentifier: GridPresetCell.reuseID)

        let aspect = CGFloat(canvasWidth) / CGFloat(max(1, canvasHeight))
        let aspectConstraint = canvasContainer.widthAnchor.constraint(equalTo: canvasContainer.heightAnchor, multiplier: aspect)
        canvasAspectConstraint = aspectConstraint
        NSLayoutConstraint.activate([
            workspaceView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            workspaceView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            workspaceView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            workspaceView.bottomAnchor.constraint(equalTo: controlsBar.topAnchor, constant: -10),

            canvasContainer.centerXAnchor.constraint(equalTo: workspaceView.centerXAnchor),
            canvasContainer.centerYAnchor.constraint(equalTo: workspaceView.centerYAnchor),
            canvasContainer.widthAnchor.constraint(lessThanOrEqualTo: workspaceView.widthAnchor),
            canvasContainer.heightAnchor.constraint(lessThanOrEqualTo: workspaceView.heightAnchor),
            aspectConstraint,
            canvasContainer.widthAnchor.constraint(equalTo: workspaceView.widthAnchor).withPriority(.defaultHigh),

            canvasView.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),

            controlsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            controlsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            controlsBar.bottomAnchor.constraint(equalTo: presetCollectionView.topAnchor, constant: -8),
            controlsBar.heightAnchor.constraint(equalToConstant: 36),

            presetCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            presetCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            presetCollectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            presetCollectionView.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    private func makeGapButton(systemName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = DSUIKit.accent(traitCollection)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.accessibilityLabel = systemName.contains("minus") ? "Decrease gap" : "Increase gap"
        DSUIKit.installPressFeedback(on: button, scale: DS.Motion.pressScaleIcon)
        return button
    }

    private func updateGapLabel() {
        gapLabel.text = "Gap: \(Int(gridGapPoints.rounded())) pt"
    }

    private func makeCanvasAspectMenu() -> UIMenu {
        var actions: [UIAction] = CanvasPresetCatalog.all.map { preset in
            UIAction(title: preset.menuTitle, subtitle: preset.menuSubtitle) { [weak self] _ in
                self?.applyCanvasPreset(width: preset.width, height: preset.height)
            }
        }
        actions.append(
            UIAction(title: "Custom Size…", image: UIImage(systemName: "slider.horizontal.below.rectangle")) { [weak self] _ in
                self?.presentCustomCanvasSizePrompt()
            }
        )
        return UIMenu(title: "Canvas Size", children: actions)
    }

    private func applyCanvasPreset(width: Int, height: Int) {
        let clamped = CanvasPresetCatalog.clampDimensions(width: width, height: height)
        canvasWidth = clamped.width
        canvasHeight = clamped.height
        updateCanvasAspectConstraint()
        reflowCutoutsForCurrentCanvas(animated: true)
        canvasView.setNeedsDisplay()
    }

    private func updateCanvasAspectConstraint() {
        let aspect = CGFloat(canvasWidth) / CGFloat(max(1, canvasHeight))
        canvasAspectConstraint?.isActive = false
        let constraint = canvasContainer.widthAnchor.constraint(equalTo: canvasContainer.heightAnchor, multiplier: aspect)
        constraint.isActive = true
        canvasAspectConstraint = constraint
        view.setNeedsLayout()
    }

    private func presentCustomCanvasSizePrompt() {
        let alert = UIAlertController(title: "Custom Canvas Size", message: "Enter output dimensions in pixels.", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "Width"
            field.text = "\(self.canvasWidth)"
        }
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "Height"
            field.text = "\(self.canvasHeight)"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            guard let self else { return }
            let widthText = alert.textFields?[0].text ?? ""
            let heightText = alert.textFields?[1].text ?? ""
            guard
                let width = Int(widthText.trimmingCharacters(in: .whitespaces)),
                let height = Int(heightText.trimmingCharacters(in: .whitespaces))
            else { return }
            self.applyCanvasPreset(width: width, height: height)
        })
        present(alert, animated: true)
    }

    private func reflowCutoutsForCurrentCanvas(animated: Bool) {
        guard !layers.isEmpty else { return }
        for index in layers.indices {
            layers[index].item.gridIndex = min(index, currentMatrix.cellCount - 1)
        }
        layoutLayersOnGrid(animated: animated)
    }

    private func preloadCutouts() {
        let products = sourceProducts
        let generation = preloadGeneration + 1
        preloadGeneration = generation
        let width = canvasWidth
        let height = canvasHeight

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var cutouts: [(CapturedProduct, UIImage, CGSize)] = []
            cutouts.reserveCapacity(products.count)
            for product in products {
                autoreleasepool {
                    if let loaded = CompositeBundleCutoutLoader.previewCutout(
                        for: product,
                        canvasWidth: width,
                        canvasHeight: height
                    ) {
                        cutouts.append((product, loaded.image, loaded.pixelSize))
                    } else {
                        let fallback = ImageProcessor.downsampleIfNeededForImportPipeline(
                            product.image,
                            maxLongEdgePixels: CompositeBundleCutoutLoader.previewMaxLongEdge(
                                canvasWidth: width,
                                canvasHeight: height
                            )
                        )
                        cutouts.append((product, fallback, fallback.size))
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self, self.preloadGeneration == generation else { return }
                self.finishLoading(cutouts: cutouts)
            }
        }
    }

    private func releasePreviewBitmaps() {
        for layer in layers {
            layer.imageView.image = nil
        }
    }

    private func finishLoading(cutouts: [(CapturedProduct, UIImage, CGSize)]) {
        canvasView.subviews.forEach { $0.removeFromSuperview() }
        layers.removeAll()

        let layout: CompositeBundleLayout
        if let existingLayout {
            layout = existingLayout
            currentMatrix = existingLayout.matrix
            gridGapPoints = CGFloat(existingLayout.gridGapPoints)
            isFreeformMode = existingLayout.isFreeformMode
            freeformSwitch.isOn = isFreeformMode
            updateGapLabel()
        } else {
            let sizes = Dictionary(uniqueKeysWithValues: cutouts.map { ($0.0.id, $0.2) })
            layout = CompositeBundleLayout.initial(
                products: sourceProducts,
                matrix: currentMatrix,
                canvasSize: canvasPixelSize,
                gridGapPoints: gridGapPoints,
                cutoutSizes: sizes
            )
        }

        for item in layout.layers {
            guard let product = sourceProducts.first(where: { $0.id == item.sourceProductID }),
                  let cutout = cutouts.first(where: { $0.0.id == item.sourceProductID }) else { continue }
            var layerItem = item
            if layerItem.cutoutAspectWidth <= 0 || layerItem.cutoutAspectHeight <= 0 {
                let aspect = CompositeLayerItem.aspect(from: cutout.2)
                layerItem.cutoutAspectWidth = aspect.width
                layerItem.cutoutAspectHeight = aspect.height
            }
            let imageView = UIImageView(image: cutout.1)
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = true
            attachGestures(to: imageView)
            canvasView.addSubview(imageView)
            layers.append(LayerState(item: layerItem, product: product, imageView: imageView, cutoutSize: cutout.2))
        }

        if !isFreeformMode, existingLayout == nil {
            applyGridLayout(animated: false)
        } else {
            view.layoutIfNeeded()
            applyAllLayerTransforms(animated: false)
        }

        sortLayerSubviews()
        selectedLayerIndex = min(selectedLayerIndex, max(0, layers.count - 1))
        updateSelectionHighlight()
        baselineLayout = buildLayout()
        hideBlockingOverlay()
    }

    private var hasUnsavedLayoutChanges: Bool {
        guard let baselineLayout else { return false }
        return buildLayout() != baselineLayout
    }

    private func attachGestures(to imageView: UIImageView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        imageView.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        imageView.addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        imageView.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        imageView.addGestureRecognizer(pinch)

        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotation.delegate = self
        imageView.addGestureRecognizer(rotation)
    }

    private func layerIndex(for view: UIView) -> Int? {
        layers.firstIndex { $0.imageView === view }
    }

    private func layoutToViewScale() -> CGFloat {
        guard canvasPixelSize.width > 0, canvasView.bounds.width > 0 else { return 1 }
        return canvasView.bounds.width / canvasPixelSize.width
    }

    private func viewPointToLayoutPoint(_ point: CGPoint) -> CGPoint {
        let scale = layoutToViewScale()
        guard scale > 0 else { return point }
        return CGPoint(x: point.x / scale, y: point.y / scale)
    }

    private func applyAllLayerTransforms(animated: Bool) {
        for index in layers.indices {
            applyLayerTransform(at: index, animated: animated)
        }
    }

    private func applyLayerTransform(at index: Int, animated: Bool) {
        guard layers.indices.contains(index) else { return }
        guard canvasPixelSize.width > 0, canvasPixelSize.height > 0 else { return }

        let pixelRect = CompositeLayoutEngine.absoluteDrawRect(
            transform: layers[index].item.transform,
            cutoutSize: layers[index].cutoutSize,
            canvasSize: canvasPixelSize
        )
        let scale = layoutToViewScale()
        let viewRect = CGRect(
            x: pixelRect.origin.x * scale,
            y: pixelRect.origin.y * scale,
            width: pixelRect.width * scale,
            height: pixelRect.height * scale
        )

        let apply = {
            self.layers[index].imageView.bounds = CGRect(origin: .zero, size: viewRect.size)
            self.layers[index].imageView.center = CGPoint(x: viewRect.midX, y: viewRect.midY)
            self.layers[index].imageView.transform = CGAffineTransform(rotationAngle: CGFloat(self.layers[index].item.transform.rotationRadians))
        }

        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.35, options: [.allowUserInteraction], animations: apply)
        } else {
            apply()
        }
    }

    private func layoutLayersOnGrid(animated: Bool) {
        let frames = CompositeLayoutEngine.computeGridFrames(
            matrix: currentMatrix,
            canvasSize: canvasPixelSize,
            gridGapPoints: gridGapPoints,
            activeCellCount: activeCellCount
        )
        for index in layers.indices {
            let gridIndex = layers[index].item.gridIndex
            guard let frame = frames.first(where: { $0.gridIndex == gridIndex })?.frame else { continue }
            layers[index].item.transform = CompositeLayoutEngine.fitTransform(
                cutoutSize: layers[index].cutoutSize,
                targetFrame: frame,
                canvasSize: canvasPixelSize,
                fillRatio: 1.0
            )
            let aspect = CompositeLayerItem.aspect(from: layers[index].cutoutSize)
            layers[index].item.cutoutAspectWidth = aspect.width
            layers[index].item.cutoutAspectHeight = aspect.height
        }
        applyAllLayerTransforms(animated: animated)
    }

    private func applyGridLayout(animated: Bool) {
        guard !isFreeformMode else { return }
        layoutLayersOnGrid(animated: animated)
    }

    private func applyFreeformGapAdjustment(from oldGap: CGFloat, animated: Bool) {
        for index in layers.indices {
            syncTransformFromView(at: index)
        }

        let oldFrames = CompositeLayoutEngine.computeGridFrames(
            matrix: currentMatrix,
            canvasSize: canvasPixelSize,
            gridGapPoints: oldGap,
            activeCellCount: activeCellCount
        )
        let newFrames = CompositeLayoutEngine.computeGridFrames(
            matrix: currentMatrix,
            canvasSize: canvasPixelSize,
            gridGapPoints: gridGapPoints,
            activeCellCount: activeCellCount
        )

        for index in layers.indices {
            let gridIndex = layers[index].item.gridIndex
            guard
                let oldFrame = oldFrames.first(where: { $0.gridIndex == gridIndex })?.frame,
                let newFrame = newFrames.first(where: { $0.gridIndex == gridIndex })?.frame,
                oldFrame.width > 0
            else { continue }

            var transform = layers[index].item.transform
            let oldCenter = CGPoint(x: oldFrame.midX, y: oldFrame.midY)
            let newCenter = CGPoint(x: newFrame.midX, y: newFrame.midY)
            transform.centerX += Double((newCenter.x - oldCenter.x) / canvasPixelSize.width)
            transform.centerY += Double((newCenter.y - oldCenter.y) / canvasPixelSize.height)
            transform.scale *= Double(newFrame.width / oldFrame.width)
            layers[index].item.transform = transform
        }

        applyAllLayerTransforms(animated: animated)
    }

    private func syncTransformFromView(at index: Int) {
        guard layers.indices.contains(index) else { return }
        guard canvasPixelSize.width > 0, canvasPixelSize.height > 0 else { return }

        let scale = layoutToViewScale()
        guard scale > 0 else { return }

        let view = layers[index].imageView
        let angle = atan2(view.transform.b, view.transform.a)
        let pixelCenter = CGPoint(x: view.center.x / scale, y: view.center.y / scale)
        let pixelWidth = view.bounds.width / scale
        layers[index].item.transform = CompositeLayerTransform(
            centerX: Double(pixelCenter.x / canvasPixelSize.width),
            centerY: Double(pixelCenter.y / canvasPixelSize.height),
            scale: Double(pixelWidth / canvasPixelSize.width),
            rotationRadians: Double(angle)
        )
        let aspect = CompositeLayerItem.aspect(from: layers[index].cutoutSize)
        layers[index].item.cutoutAspectWidth = aspect.width
        layers[index].item.cutoutAspectHeight = aspect.height
    }

    private func sortLayerSubviews() {
        let sorted = layers.enumerated().sorted { $0.element.item.zIndex < $1.element.item.zIndex }
        for pair in sorted {
            canvasView.bringSubviewToFront(pair.element.imageView)
        }
    }

    private func normalizedZIndices() {
        let order = layers.indices.sorted { layers[$0].item.zIndex < layers[$1].item.zIndex }
        for (rank, index) in order.enumerated() {
            layers[index].item.zIndex = rank
        }
    }

    private func updateSelectionHighlight() {
        for (index, layer) in layers.enumerated() {
            layer.imageView.layer.borderWidth = index == selectedLayerIndex ? 2.5 : 0
            layer.imageView.layer.borderColor = index == selectedLayerIndex ? DSUIKit.accent(traitCollection).cgColor : nil
            layer.imageView.layer.shadowOpacity = index == selectedLayerIndex ? 0.18 : 0
            layer.imageView.layer.shadowRadius = index == selectedLayerIndex ? 8 : 0
            layer.imageView.layer.shadowOffset = .zero
        }
    }

    private func showBlockingOverlay(message: String) {
        coordinator?.setProcessingMessage(message)
        navigationItem.rightBarButtonItem?.isEnabled = false
        presetCollectionView.isUserInteractionEnabled = false
        controlsBar.isUserInteractionEnabled = false
    }

    private func hideBlockingOverlay() {
        coordinator?.setProcessingMessage(nil)
        navigationItem.rightBarButtonItem?.isEnabled = true
        presetCollectionView.isUserInteractionEnabled = true
        controlsBar.isUserInteractionEnabled = true
    }

    private func buildLayout() -> CompositeBundleLayout {
        if isFreeformMode {
            for index in layers.indices {
                syncTransformFromView(at: index)
            }
        } else {
            for index in layers.indices {
                let aspect = CompositeLayerItem.aspect(from: layers[index].cutoutSize)
                layers[index].item.cutoutAspectWidth = aspect.width
                layers[index].item.cutoutAspectHeight = aspect.height
            }
        }
        normalizedZIndices()
        return CompositeBundleLayout(
            matrix: currentMatrix,
            layers: layers.map(\.item),
            isFreeformMode: isFreeformMode,
            sourceProductIDs: sourceProducts.map(\.id),
            gridGapPoints: Double(gridGapPoints),
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )
    }

    @objc private func cancelTapped() {
        guard hasUnsavedLayoutChanges else {
            dismissEditor()
            return
        }
        let alert = UIAlertController(
            title: "Unsaved changes",
            message: "Save your grouped cover layout, discard your edits, or keep editing.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            self?.dismissEditor()
        })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            self?.saveTapped()
        })
        present(alert, animated: true)
    }

    private func dismissEditor() {
        preloadGeneration += 1
        releasePreviewBitmaps()
        coordinator?.onCancel()
    }

    @objc private func saveTapped() {
        guard !isSaving else { return }
        isSaving = true
        releasePreviewBitmaps()
        showBlockingOverlay(message: "Saving…")

        let layout = buildLayout()
        let productsByID = Dictionary(uniqueKeysWithValues: sourceProducts.map { ($0.id, $0) })

        CompositeBundleRenderer.render(
            layout: layout,
            productsByID: productsByID,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            fillRatio: fillRatio,
            backgroundFillSpec: backgroundFillSpec,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor
        ) { [weak self] result in
            guard let self else { return }
            self.isSaving = false
            self.hideBlockingOverlay()
            switch result {
            case .success(let image):
                self.coordinator?.onSave(image, layout)
            case .failure:
                let alert = UIAlertController(title: "Could Not Save", message: "The grouped cover could not be rendered. Try again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    @objc private func freeformToggled() {
        isFreeformMode = freeformSwitch.isOn
        if !isFreeformMode {
            applyGridLayout(animated: true)
        } else {
            for index in layers.indices {
                syncTransformFromView(at: index)
            }
        }
    }

    @objc private func decreaseGapTapped() {
        let oldGap = gridGapPoints
        gridGapPoints = CompositeLayoutEngine.clampGap(gridGapPoints - CompositeLayoutEngine.gridGapStepPoints)
        updateGapLabel()
        if isFreeformMode {
            applyFreeformGapAdjustment(from: oldGap, animated: true)
        } else {
            applyGridLayout(animated: true)
        }
    }

    @objc private func increaseGapTapped() {
        let oldGap = gridGapPoints
        gridGapPoints = CompositeLayoutEngine.clampGap(gridGapPoints + CompositeLayoutEngine.gridGapStepPoints)
        updateGapLabel()
        if isFreeformMode {
            applyFreeformGapAdjustment(from: oldGap, animated: true)
        } else {
            applyGridLayout(animated: true)
        }
    }

    @objc private func bringForwardTapped() {
        guard layers.indices.contains(selectedLayerIndex) else { return }
        let order = layers.indices.sorted { layers[$0].item.zIndex < layers[$1].item.zIndex }
        guard let position = order.firstIndex(of: selectedLayerIndex), position < order.count - 1 else { return }
        let nextIndex = order[position + 1]
        let currentZ = layers[selectedLayerIndex].item.zIndex
        layers[selectedLayerIndex].item.zIndex = layers[nextIndex].item.zIndex
        layers[nextIndex].item.zIndex = currentZ
        sortLayerSubviews()
        updateSelectionHighlight()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func sendBackwardTapped() {
        guard layers.indices.contains(selectedLayerIndex) else { return }
        let order = layers.indices.sorted { layers[$0].item.zIndex < layers[$1].item.zIndex }
        guard let position = order.firstIndex(of: selectedLayerIndex), position > 0 else { return }
        let previousIndex = order[position - 1]
        let currentZ = layers[selectedLayerIndex].item.zIndex
        layers[selectedLayerIndex].item.zIndex = layers[previousIndex].item.zIndex
        layers[previousIndex].item.zIndex = currentZ
        sortLayerSubviews()
        updateSelectionHighlight()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view, let index = layerIndex(for: view) else { return }
        selectedLayerIndex = index
        updateSelectionHighlight()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard !isFreeformMode, let view = gesture.view as? UIImageView,
              let index = layerIndex(for: view) else { return }

        switch gesture.state {
        case .began:
            selectedLayerIndex = index
            updateSelectionHighlight()
            draggingLayerIndex = index
            dragOffset = gesture.location(in: canvasView)
            dragOffset.x -= view.center.x
            dragOffset.y -= view.center.y
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .changed:
            guard draggingLayerIndex == index else { return }
            let location = gesture.location(in: canvasView)
            view.center = CGPoint(x: location.x - dragOffset.x, y: location.y - dragOffset.y)
        case .ended, .cancelled:
            guard draggingLayerIndex == index else { return }
            let dropPoint = viewPointToLayoutPoint(view.center)
            if let targetGrid = CompositeLayoutEngine.gridIndex(
                at: dropPoint,
                matrix: currentMatrix,
                canvasSize: canvasPixelSize,
                gridGapPoints: gridGapPoints,
                activeCellCount: activeCellCount
            ) {
                swapOrMoveLayer(at: index, toGridIndex: targetGrid)
            } else {
                applyLayerTransform(at: index, animated: true)
            }
            draggingLayerIndex = nil
        default:
            break
        }
    }

    private func swapOrMoveLayer(at index: Int, toGridIndex targetGrid: Int) {
        let sourceGrid = layers[index].item.gridIndex
        guard sourceGrid != targetGrid else {
            applyLayerTransform(at: index, animated: true)
            return
        }

        if let otherIndex = layers.firstIndex(where: { $0.item.gridIndex == targetGrid && $0.item.sourceProductID != layers[index].item.sourceProductID }) {
            layers[otherIndex].item.gridIndex = sourceGrid
            if let frame = cellFrame(forGridIndex: sourceGrid) {
                layers[otherIndex].item.transform = CompositeLayoutEngine.fitTransform(
                    cutoutSize: layers[otherIndex].cutoutSize,
                    targetFrame: frame,
                    canvasSize: canvasPixelSize,
                    fillRatio: 1.0
                )
            }
            applyLayerTransform(at: otherIndex, animated: true)
        }
        layers[index].item.gridIndex = targetGrid
        if let frame = cellFrame(forGridIndex: targetGrid) {
            layers[index].item.transform = CompositeLayoutEngine.fitTransform(
                cutoutSize: layers[index].cutoutSize,
                targetFrame: frame,
                canvasSize: canvasPixelSize,
                fillRatio: 1.0
            )
        }
        applyLayerTransform(at: index, animated: true)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func cellFrame(forGridIndex gridIndex: Int) -> CGRect? {
        CompositeLayoutEngine.frame(
            forGridIndex: gridIndex,
            in: currentMatrix,
            canvasSize: canvasPixelSize,
            gridGapPoints: gridGapPoints,
            activeCellCount: activeCellCount
        )
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isFreeformMode, let view = gesture.view as? UIImageView,
              let index = layerIndex(for: view) else { return }

        selectedLayerIndex = index
        updateSelectionHighlight()

        let translation = gesture.translation(in: canvasView)
        switch gesture.state {
        case .began, .changed:
            view.center = CGPoint(x: view.center.x + translation.x, y: view.center.y + translation.y)
            gesture.setTranslation(.zero, in: canvasView)
            syncTransformFromView(at: index)
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isFreeformMode, let view = gesture.view as? UIImageView,
              let index = layerIndex(for: view) else { return }

        selectedLayerIndex = index
        updateSelectionHighlight()

        if gesture.state == .began || gesture.state == .changed {
            view.bounds.size = CGSize(
                width: max(24, view.bounds.width * gesture.scale),
                height: max(24, view.bounds.height * gesture.scale)
            )
            gesture.scale = 1
            syncTransformFromView(at: index)
        }
    }

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard isFreeformMode, let view = gesture.view as? UIImageView,
              let index = layerIndex(for: view) else { return }

        selectedLayerIndex = index
        updateSelectionHighlight()

        if gesture.state == .began || gesture.state == .changed {
            view.transform = view.transform.rotated(by: gesture.rotation)
            gesture.rotation = 0
            syncTransformFromView(at: index)
        }
    }

    private func selectMatrix(_ matrix: CompositeLayoutMatrix) {
        currentMatrix = matrix
        if !isFreeformMode {
            for index in layers.indices {
                layers[index].item.gridIndex = min(index, matrix.cellCount - 1)
            }
            applyGridLayout(animated: true)
        }
        presetCollectionView.reloadData()
    }
}

// MARK: - Collection view

extension GroupedCoverEditorViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        eligiblePresets.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GridPresetCell.reuseID, for: indexPath)
        guard let presetCell = cell as? GridPresetCell else { return cell }
        let matrix = eligiblePresets[indexPath.item]
        presetCell.configure(matrix: matrix, selected: matrix == currentMatrix)
        return presetCell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectMatrix(eligiblePresets[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let label = eligiblePresets[indexPath.item].label
        let width = max(64, label.size(withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]).width + 28)
        return CGSize(width: width, height: 44)
    }
}

// MARK: - Gesture delegate

extension GroupedCoverEditorViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        isFreeformMode
    }
}

// MARK: - Constraint priority helper

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
