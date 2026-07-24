import CoreImage
import SwiftUI
import UIKit

// MARK: - SwiftUI bridge

struct ImageBackgroundVisualEditorSheet: View {
    let initialSelection: ImageBackgroundSelection
    let cutoutImage: UIImage
    let cutoutSize: CGSize
    let canvasWidth: Int
    let canvasHeight: Int
    let fillRatio: Double
    let onSave: (ImageBackgroundSelection) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ImageBackgroundEditorBridge(
            initialSelection: initialSelection,
            cutoutImage: cutoutImage,
            cutoutSize: cutoutSize,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            fillRatio: fillRatio,
            onSave: { selection in
                onSave(selection)
                dismiss()
            },
            onCancel: {
                onCancel()
                dismiss()
            }
        )
        .ignoresSafeArea()
        .interactiveDismissDisabled(true)
    }
}

struct ImageBackgroundEditorBridge: UIViewControllerRepresentable {
    let initialSelection: ImageBackgroundSelection
    let cutoutImage: UIImage
    let cutoutSize: CGSize
    let canvasWidth: Int
    let canvasHeight: Int
    let fillRatio: Double
    let onSave: (ImageBackgroundSelection) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let root = ImageBackgroundEditorViewController()
        root.initialSelection = initialSelection
        root.cutoutImage = cutoutImage
        root.cutoutSize = cutoutSize
        root.canvasWidth = canvasWidth
        root.canvasHeight = canvasHeight
        root.fillRatio = fillRatio
        root.onSave = { selection in onSave(selection) }
        root.onCancel = onCancel
        let nav = UINavigationController(rootViewController: root)
        nav.modalPresentationStyle = .fullScreen
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

// MARK: - Transform overlay

private final class LayerTransformOverlay: UIView {
    enum HandleKind: Int, CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, rotate

        var isCorner: Bool {
            switch self {
            case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
            default: return false
            }
        }

        var isEdge: Bool {
            switch self {
            case .top, .right, .bottom, .left: return true
            default: return false
            }
        }
    }

    var onHandleDrag: ((HandleKind, UIPanGestureRecognizer) -> Void)?

    private var handleViews: [HandleKind: UIView] = [:]
    private let borderLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        borderLayer.strokeColor = UIColor.systemBlue.cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 2
        layer.addSublayer(borderLayer)

        for kind in HandleKind.allCases {
            let size: CGFloat = kind == .rotate ? 28 : (kind.isEdge ? 18 : 24)
            let dot = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            dot.backgroundColor = .white
            dot.layer.cornerRadius = kind.isCorner ? 4 : (kind == .rotate ? 14 : 3)
            dot.layer.borderWidth = 2
            dot.layer.borderColor = UIColor.systemBlue.cgColor
            dot.layer.shadowColor = UIColor.black.cgColor
            dot.layer.shadowOpacity = 0.25
            dot.layer.shadowRadius = 3
            dot.layer.shadowOffset = .zero
            if kind == .rotate {
                let icon = UIImageView(image: UIImage(systemName: "arrow.triangle.2.circlepath"))
                icon.tintColor = UIColor.systemBlue
                icon.frame = dot.bounds.insetBy(dx: 5, dy: 5)
                icon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                dot.addSubview(icon)
            }
            addSubview(dot)
            handleViews[kind] = dot
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanned(_:)))
            dot.addGestureRecognizer(pan)
            dot.tag = kind.rawValue
        }
    }

    required init?(coder: NSCoder) { nil }

    /// Match the tracked image view in `container` (handles sit in container space so they aren't clipped).
    func align(to imageView: UIImageView, in container: UIView) {
        frame = container.bounds
        transform = .identity

        let tl = imageView.convert(CGPoint(x: imageView.bounds.minX, y: imageView.bounds.minY), to: container)
        let tr = imageView.convert(CGPoint(x: imageView.bounds.maxX, y: imageView.bounds.minY), to: container)
        let br = imageView.convert(CGPoint(x: imageView.bounds.maxX, y: imageView.bounds.maxY), to: container)
        let bl = imageView.convert(CGPoint(x: imageView.bounds.minX, y: imageView.bounds.maxY), to: container)
        let topMid = midpoint(tl, tr)
        let rightMid = midpoint(tr, br)
        let bottomMid = midpoint(bl, br)
        let leftMid = midpoint(tl, bl)

        let path = UIBezierPath()
        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: br)
        path.addLine(to: bl)
        path.close()
        borderLayer.frame = bounds
        borderLayer.path = path.cgPath

        let positions: [HandleKind: CGPoint] = [
            .topLeft: tl,
            .top: topMid,
            .topRight: tr,
            .right: rightMid,
            .bottomRight: br,
            .bottom: bottomMid,
            .bottomLeft: bl,
            .left: leftMid,
            .rotate: CGPoint(x: topMid.x, y: topMid.y - 28),
        ]
        for (kind, point) in positions {
            handleViews[kind]?.center = point
        }
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    @objc private func handlePanned(_ gesture: UIPanGestureRecognizer) {
        guard let kind = HandleKind(rawValue: gesture.view?.tag ?? -1) else { return }
        onHandleDrag?(kind, gesture)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, bounds.contains(point) else { return nil }
        for (_, handle) in handleViews {
            let local = convert(point, to: handle)
            if handle.bounds.insetBy(dx: -14, dy: -14).contains(local) { return handle }
        }
        return nil
    }
}

// MARK: - Photos-style crop overlay

private final class PhotosCropOverlayView: UIView {
    enum Handle: Int, CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    var cropRect: CGRect = .zero {
        didSet { setNeedsLayout() }
    }

    var aspectRatioLocked = true {
        didSet { setNeedsLayout() }
    }

    var lockedAspectRatio: CGFloat = 1
    var onCropRectChanged: ((CGRect) -> Void)?

    private let dimmingLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    private let bracketLayers: [CAShapeLayer] = (0..<4).map { _ in CAShapeLayer() }
    private var handleViews: [Handle: UIView] = [:]
    private var activeHandle: Handle?
    private var dragStartRect: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        dimmingLayer.fillRule = .evenOdd
        dimmingLayer.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 1.5
        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        gridLayer.lineWidth = 0.5
        layer.addSublayer(dimmingLayer)
        layer.addSublayer(gridLayer)
        layer.addSublayer(borderLayer)
        bracketLayers.forEach { layer.addSublayer($0) }

        for handle in Handle.allCases {
            let view = UIView()
            view.backgroundColor = handle.isCorner ? .clear : UIColor.white.withAlphaComponent(0.95)
            view.isUserInteractionEnabled = true
            view.layer.cornerRadius = handle.isCorner ? 0 : 2
            addSubview(view)
            handleViews[handle] = view
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)
            view.tag = handle.rawValue
        }
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, bounds.contains(point) else { return nil }
        for handle in Handle.allCases {
            guard let view = handleViews[handle] else { continue }
            let hitFrame = view.frame.insetBy(dx: handle.isCorner ? -8 : -18, dy: handle.isCorner ? -8 : -18)
            if hitFrame.contains(point) { return view }
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        redrawOverlay()
        layoutHandles()
    }

    private func redrawOverlay() {
        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(rect: cropRect))
        dimmingLayer.path = path.cgPath
        borderLayer.path = UIBezierPath(rect: cropRect).cgPath

        let grid = UIBezierPath()
        for i in 1..<3 {
            let x = cropRect.minX + cropRect.width * CGFloat(i) / 3
            grid.move(to: CGPoint(x: x, y: cropRect.minY))
            grid.addLine(to: CGPoint(x: x, y: cropRect.maxY))
            let y = cropRect.minY + cropRect.height * CGFloat(i) / 3
            grid.move(to: CGPoint(x: cropRect.minX, y: y))
            grid.addLine(to: CGPoint(x: cropRect.maxX, y: y))
        }
        gridLayer.path = grid.cgPath
        layoutCornerBrackets()
    }

    private func layoutCornerBrackets() {
        let r = cropRect
        let len: CGFloat = 22
        let thick: CGFloat = 3
        let corners: [(CGPoint, CGFloat)] = [
            (CGPoint(x: r.minX, y: r.minY), 0),
            (CGPoint(x: r.maxX, y: r.minY), .pi / 2),
            (CGPoint(x: r.maxX, y: r.maxY), .pi),
            (CGPoint(x: r.minX, y: r.maxY), -.pi / 2),
        ]
        for (index, corner) in corners.enumerated() {
            let bracket = UIBezierPath()
            bracket.move(to: corner.0)
            bracket.addLine(to: CGPoint(x: corner.0.x + len * cos(corner.1), y: corner.0.y + len * sin(corner.1)))
            bracket.move(to: corner.0)
            bracket.addLine(to: CGPoint(x: corner.0.x + len * cos(corner.1 + .pi / 2), y: corner.0.y + len * sin(corner.1 + .pi / 2)))
            let layer = bracketLayers[index]
            layer.strokeColor = UIColor.white.cgColor
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = thick
            layer.lineCap = .square
            layer.path = bracket.cgPath
        }
    }

    private func layoutHandles() {
        let r = cropRect
        let positions: [Handle: CGPoint] = [
            .topLeft: CGPoint(x: r.minX, y: r.minY),
            .top: CGPoint(x: r.midX, y: r.minY),
            .topRight: CGPoint(x: r.maxX, y: r.minY),
            .right: CGPoint(x: r.maxX, y: r.midY),
            .bottomRight: CGPoint(x: r.maxX, y: r.maxY),
            .bottom: CGPoint(x: r.midX, y: r.maxY),
            .bottomLeft: CGPoint(x: r.minX, y: r.maxY),
            .left: CGPoint(x: r.minX, y: r.midY),
        ]
        for (handle, center) in positions {
            guard let view = handleViews[handle] else { continue }
            let size = handle.isCorner ? CGSize(width: 44, height: 44) : (handle.isHorizontal ? CGSize(width: 32, height: 6) : CGSize(width: 6, height: 32))
            view.bounds = CGRect(origin: .zero, size: size)
            view.center = center
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let handle = Handle(rawValue: gesture.view?.tag ?? -1) else { return }
        let limit = clampLimits()
        if gesture.state == .began { dragStartRect = cropRect }
        var rect = dragStartRect
        let t = gesture.translation(in: self)

        switch handle {
        case .topLeft:
            rect.origin.x += t.x
            rect.origin.y += t.y
            rect.size.width -= t.x
            rect.size.height -= t.y
        case .top:
            rect.origin.y += t.y
            rect.size.height -= t.y
        case .topRight:
            rect.size.width += t.x
            rect.origin.y += t.y
            rect.size.height -= t.y
        case .right:
            rect.size.width += t.x
        case .bottomRight:
            rect.size.width += t.x
            rect.size.height += t.y
        case .bottom:
            rect.size.height += t.y
        case .bottomLeft:
            rect.origin.x += t.x
            rect.size.width -= t.x
            rect.size.height += t.y
        case .left:
            rect.origin.x += t.x
            rect.size.width -= t.x
        }

        if aspectRatioLocked {
            rect = enforceAspect(on: rect, anchor: handle, in: limit)
        }

        cropRect = clamp(rect: rect, in: limit)
        if gesture.state == .ended || gesture.state == .cancelled {
            dragStartRect = cropRect
        }
        onCropRectChanged?(cropRect)
    }

    private func enforceAspect(on rect: CGRect, anchor: Handle, in limit: CGRect) -> CGRect {
        let aspect = lockedAspectRatio
        var r = rect
        let minSide: CGFloat = 48

        switch anchor {
        case .topLeft:
            r.size.height = max(minSide, r.width / aspect)
            r.origin.y = rect.maxY - r.height
            r.origin.x = rect.maxX - r.width
        case .topRight:
            r.size.height = max(minSide, r.width / aspect)
            r.origin.y = rect.maxY - r.height
        case .bottomLeft:
            r.size.height = max(minSide, r.width / aspect)
            r.origin.x = rect.maxX - r.width
        case .bottomRight:
            r.size.height = max(minSide, r.width / aspect)
        case .top:
            r.size.width = max(minSide, r.height * aspect)
            r.origin.y = rect.maxY - r.height
        case .bottom:
            r.size.width = max(minSide, r.height * aspect)
        case .left:
            r.size.height = max(minSide, r.width / aspect)
            r.origin.x = rect.maxX - r.width
        case .right:
            r.size.height = max(minSide, r.width / aspect)
        }

        return r.intersection(limit).nullRectFallback(r)
    }

    private func clampLimits() -> CGRect {
        bounds.insetBy(dx: 8, dy: 8)
    }

    private func clamp(rect: CGRect, in limit: CGRect) -> CGRect {
        let minSide: CGFloat = 48
        var r = rect
        if aspectRatioLocked {
            r.size.height = max(minSide, r.width / lockedAspectRatio)
        } else {
            r.size.width = max(minSide, r.width)
            r.size.height = max(minSide, r.height)
        }
        r.size.width = min(r.width, limit.width)
        r.size.height = min(r.height, limit.height)
        r.origin.x = max(limit.minX, min(r.origin.x, limit.maxX - r.width))
        r.origin.y = max(limit.minY, min(r.origin.y, limit.maxY - r.height))
        return r
    }
}

private extension PhotosCropOverlayView.Handle {
    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }

    var isHorizontal: Bool { self == .top || self == .bottom }
}

// MARK: - Crop editor (Photos-style)

final class ImageBackgroundCropViewController: UIViewController, UIScrollViewDelegate {
    var sourceImage: UIImage = UIImage()
    var existingCrop: ImageBackgroundCropSpec = .full
    var onApply: ((ImageBackgroundCropSpec) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let imageView = UIImageView()
    private let cropOverlay = PhotosCropOverlayView()
    private let straightenSlider = UISlider()
    private let aspectStack = UIStackView()
    private let lockButton = UIButton(type: .system)
    private let aspectLockLabel = UILabel()
    private var rotationRadians: CGFloat = 0
    private var selectedAspectMode: AspectMode = .original
    private var lastWorkspaceSize: CGSize = .zero
    private var didApplyInitialCropFrame = false
    private var didCaptureBaseline = false
    private var baselineSnapshot: CropEditorSnapshot?
    private var baseFitScale: CGFloat = 1
    private var imagePixelSize: CGSize = .zero

    private struct CropEditorSnapshot: Equatable {
        let cropRect: CGRect
        let rotation: CGFloat
        let aspectMode: AspectMode
        let aspectLocked: Bool
        let straighten: Float
    }

    private enum AspectMode: String, CaseIterable {
        case original = "Original"
        case freeform = "Freeform"
        case square = "Square"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sourceImage = Self.uprightImage(from: sourceImage)
        imagePixelSize = sourceImage.size
        view.backgroundColor = .black
        title = "Crop"

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(applyTapped))

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true

        imageView.image = sourceImage
        imageView.contentMode = .scaleToFill
        contentView.backgroundColor = .clear
        contentView.addSubview(imageView)
        scrollView.addSubview(contentView)

        cropOverlay.translatesAutoresizingMaskIntoConstraints = false
        cropOverlay.aspectRatioLocked = true
        cropOverlay.lockedAspectRatio = imagePixelSize.width / max(imagePixelSize.height, 1)

        aspectLockLabel.text = "Aspect Ratio"
        aspectLockLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        aspectLockLabel.textColor = .secondaryLabel

        straightenSlider.minimumValue = -45
        straightenSlider.maximumValue = 45
        straightenSlider.value = 0
        straightenSlider.tintColor = .systemBlue
        straightenSlider.addTarget(self, action: #selector(straightenChanged), for: .valueChanged)

        lockButton.setImage(UIImage(systemName: "lock.fill"), for: .normal)
        lockButton.tintColor = .white
        lockButton.addTarget(self, action: #selector(toggleLock), for: .touchUpInside)

        aspectStack.axis = .horizontal
        aspectStack.spacing = 10
        aspectStack.distribution = .fillEqually
        aspectStack.translatesAutoresizingMaskIntoConstraints = false
        for mode in AspectMode.allCases {
            let button = UIButton(type: .custom)
            button.tag = AspectMode.allCases.firstIndex(of: mode) ?? 0
            button.addTarget(self, action: #selector(aspectModeTapped(_:)), for: .touchUpInside)
            aspectStack.addArrangedSubview(button)
        }

        let resetButton = UIButton(type: .custom)
        var resetConfig = UIButton.Configuration.plain()
        resetConfig.title = "Reset"
        resetConfig.baseForegroundColor = .systemBlue
        resetConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 15, weight: .semibold)
            out.underlineStyle = []
            return out
        }
        resetButton.configuration = resetConfig
        resetButton.addTarget(self, action: #selector(resetCropTapped), for: .touchUpInside)

        let aspectHeader = UIStackView(arrangedSubviews: [aspectLockLabel, UIView(), lockButton])
        aspectHeader.axis = .horizontal
        aspectHeader.alignment = .center

        let bottomStack = UIStackView(arrangedSubviews: [aspectHeader, aspectStack, straightenSlider, resetButton])
        bottomStack.axis = .vertical
        bottomStack.spacing = 14
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        bottomStack.isLayoutMarginsRelativeArrangement = true

        view.addSubview(scrollView)
        view.addSubview(cropOverlay)
        view.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor),
            cropOverlay.topAnchor.constraint(equalTo: scrollView.topAnchor),
            cropOverlay.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            cropOverlay.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            cropOverlay.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bottomStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            aspectStack.heightAnchor.constraint(equalToConstant: 40),
        ])

        updateAspectButtonStyles()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshCropLayoutIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshCropLayoutIfNeeded()
    }

    private func refreshCropLayoutIfNeeded() {
        let size = scrollView.bounds.size
        guard size.width > 10, size.height > 10 else { return }
        guard size != lastWorkspaceSize else { return }
        lastWorkspaceSize = size
        rebuildScrollContent()
        if !didApplyInitialCropFrame {
            applyInitialCropFrame()
            didApplyInitialCropFrame = true
        }
        if !didCaptureBaseline {
            captureBaseline()
            didCaptureBaseline = true
        }
    }

    private func workspaceCropArea() -> CGRect {
        cropOverlay.bounds.insetBy(dx: 16, dy: 16)
    }

    private func applyInitialCropFrame() {
        let area = workspaceCropArea()
        guard area.width > 40, area.height > 40 else { return }
        syncLockedAspectRatio()
        cropOverlay.cropRect = fittedRect(aspect: cropOverlay.lockedAspectRatio, inside: area)
        applyCropAspectPreset(animated: false)
    }

    private func captureBaseline() {
        baselineSnapshot = currentSnapshot()
    }

    private func currentSnapshot() -> CropEditorSnapshot {
        CropEditorSnapshot(
            cropRect: cropOverlay.cropRect,
            rotation: rotationRadians,
            aspectMode: selectedAspectMode,
            aspectLocked: cropOverlay.aspectRatioLocked,
            straighten: straightenSlider.value
        )
    }

    private var hasUnsavedCropChanges: Bool {
        guard let baselineSnapshot else { return false }
        return !snapshotsEqual(baselineSnapshot, currentSnapshot())
    }

    private func snapshotsEqual(_ lhs: CropEditorSnapshot, _ rhs: CropEditorSnapshot) -> Bool {
        abs(lhs.straighten - rhs.straighten) < 0.05
            && abs(lhs.rotation - rhs.rotation) < 0.002
            && lhs.aspectMode == rhs.aspectMode
            && lhs.aspectLocked == rhs.aspectLocked
            && cropRectsSimilar(lhs.cropRect, rhs.cropRect)
    }

    private func cropRectsSimilar(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1.5
            && abs(a.minY - b.minY) < 1.5
            && abs(a.width - b.width) < 1.5
            && abs(a.height - b.height) < 1.5
    }

    private func rebuildScrollContent() {
        layoutRotatedContent()
        fitImageInScrollView()
    }

    private func layoutRotatedContent() {
        imageView.transform = .identity
        imageView.bounds = CGRect(origin: .zero, size: imagePixelSize)
        imageView.transform = CGAffineTransform(rotationAngle: rotationRadians)
        let box = Self.axisAlignedBounds(for: imagePixelSize, rotation: rotationRadians)
        contentView.bounds = CGRect(origin: .zero, size: box)
        contentView.frame = CGRect(origin: .zero, size: box)
        imageView.center = CGPoint(x: box.width / 2, y: box.height / 2)
        scrollView.contentSize = box
    }

    private func fitImageInScrollView() {
        let bounds = scrollView.bounds
        guard bounds.width > 0, scrollView.contentSize.width > 0 else { return }
        let fitScale = min(bounds.width / scrollView.contentSize.width, bounds.height / scrollView.contentSize.height)
        baseFitScale = fitScale
        scrollView.minimumZoomScale = fitScale
        scrollView.maximumZoomScale = max(fitScale * 5, fitScale + 0.01)
        scrollView.setZoomScale(fitScale, animated: false)
        scrollView.contentOffset = .zero
        recenterScrollView()
    }

    private func recenterScrollView() {
        let bounds = scrollView.bounds
        let zoom = scrollView.zoomScale
        let contentWidth = scrollView.contentSize.width * zoom
        let contentHeight = scrollView.contentSize.height * zoom
        let insetX = max(0, (bounds.width - contentWidth) / 2)
        let insetY = max(0, (bounds.height - contentHeight) / 2)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    private func visibleImageRect() -> CGRect {
        let zoom = scrollView.zoomScale
        let size = CGSize(
            width: scrollView.contentSize.width * zoom,
            height: scrollView.contentSize.height * zoom
        )
        return CGRect(
            x: scrollView.contentInset.left - scrollView.contentOffset.x,
            y: scrollView.contentInset.top - scrollView.contentOffset.y,
            width: size.width,
            height: size.height
        )
    }

    private func imageFrameInWorkspace() -> CGRect {
        visibleImageRect()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        recenterScrollView()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {}

    @objc private func straightenChanged() {
        rotationRadians = CGFloat(straightenSlider.value * .pi / 180)
        rebuildScrollContent()
    }

    @objc private func toggleLock() {
        cropOverlay.aspectRatioLocked.toggle()
        let icon = cropOverlay.aspectRatioLocked ? "lock.fill" : "lock.open.fill"
        lockButton.setImage(UIImage(systemName: icon), for: .normal)
        if cropOverlay.aspectRatioLocked {
            syncLockedAspectRatio()
            applyCropAspectPreset(animated: true)
        }
    }

    @objc private func aspectModeTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < AspectMode.allCases.count else { return }
        selectedAspectMode = AspectMode.allCases[sender.tag]
        updateAspectButtonStyles()
        switch selectedAspectMode {
        case .original:
            cropOverlay.aspectRatioLocked = true
            syncLockedAspectRatio()
        case .freeform:
            cropOverlay.aspectRatioLocked = false
        case .square:
            cropOverlay.aspectRatioLocked = true
            cropOverlay.lockedAspectRatio = 1
        }
        lockButton.setImage(UIImage(systemName: cropOverlay.aspectRatioLocked ? "lock.fill" : "lock.open.fill"), for: .normal)
        applyCropAspectPreset(animated: true)
    }

    private func syncLockedAspectRatio() {
        switch selectedAspectMode {
        case .original:
            cropOverlay.lockedAspectRatio = imagePixelSize.width / max(imagePixelSize.height, 1)
        case .square:
            cropOverlay.lockedAspectRatio = 1
        case .freeform:
            break
        }
    }

    private func applyCropAspectPreset(animated: Bool) {
        let area = workspaceCropArea()
        guard area.width > 40, area.height > 40 else { return }

        let newRect: CGRect
        switch selectedAspectMode {
        case .original:
            syncLockedAspectRatio()
            newRect = fittedRect(aspect: cropOverlay.lockedAspectRatio, inside: area)
        case .freeform:
            newRect = cropOverlay.cropRect.width > 40 ? cropOverlay.cropRect : area
        case .square:
            cropOverlay.lockedAspectRatio = 1
            newRect = fittedRect(aspect: 1, inside: area)
        }

        let apply = { self.cropOverlay.cropRect = newRect }
        if animated {
            UIView.animate(withDuration: 0.22, animations: apply)
        } else {
            apply()
        }
    }

    private func fittedRect(aspect: CGFloat, inside rect: CGRect) -> CGRect {
        guard aspect > 0 else { return rect }
        var width = rect.width
        var height = width / aspect
        if height > rect.height {
            height = rect.height
            width = height * aspect
        }
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func updateAspectButtonStyles() {
        for case let button as UIButton in aspectStack.arrangedSubviews {
            let mode = AspectMode.allCases[button.tag]
            let selected = mode == selectedAspectMode
            var config = UIButton.Configuration.plain()
            config.title = mode.rawValue.uppercased()
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
            config.baseForegroundColor = selected ? .black : .white
            config.background.backgroundColor = selected ? UIColor.white.withAlphaComponent(0.92) : UIColor.white.withAlphaComponent(0.14)
            config.background.cornerRadius = 8
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = .systemFont(ofSize: 12, weight: .semibold)
                out.underlineStyle = []
                return out
            }
            button.configuration = config
        }
    }

    @objc private func resetCropTapped() {
        straightenSlider.value = 0
        rotationRadians = 0
        selectedAspectMode = .original
        cropOverlay.aspectRatioLocked = true
        syncLockedAspectRatio()
        existingCrop = .full
        lastWorkspaceSize = .zero
        didApplyInitialCropFrame = false
        rebuildScrollContent()
        applyInitialCropFrame()
        didApplyInitialCropFrame = true
        applyCropAspectPreset(animated: false)
        updateAspectButtonStyles()
        lockButton.setImage(UIImage(systemName: "lock.fill"), for: .normal)
        captureBaseline()
    }

    @objc private func cancelTapped() {
        guard hasUnsavedCropChanges else {
            dismiss(animated: true)
            return
        }
        EditorUnsavedChangesAlert.present(
            on: self,
            message: "Save your crop, discard your edits, or keep editing.",
            onDiscard: { [weak self] in self?.dismiss(animated: true) },
            onSave: { [weak self] in self?.applyTapped() }
        )
    }

    @objc private func applyTapped() {
        let imageFrame = imageFrameInWorkspace()
        let cropRect = cropOverlay.cropRect
        let intersection = cropRect.intersection(imageFrame)
        guard intersection.width > 2, intersection.height > 2, imageFrame.width > 1, imageFrame.height > 1 else {
            let alert = UIAlertController(title: "Nothing to Crop", message: "Move or zoom the photo so it fills the crop area.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let normalizedX = (intersection.minX - imageFrame.minX) / imageFrame.width
        let normalizedY = (intersection.minY - imageFrame.minY) / imageFrame.height
        let normalizedW = intersection.width / imageFrame.width
        let normalizedH = intersection.height / imageFrame.height

        let crop = ImageBackgroundCropSpec(
            x: Double(max(0, min(1, normalizedX))),
            y: Double(max(0, min(1, normalizedY))),
            width: Double(max(0.05, min(1, normalizedW))),
            height: Double(max(0.05, min(1, normalizedH)))
        )
        onApply?(crop.clamped())
        dismiss(animated: true)
    }

    private static func uprightImage(from image: UIImage) -> UIImage {
        guard image.imageOrientation != .up, let cg = image.cgImage else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }

    private static func axisAlignedBounds(for size: CGSize, rotation: CGFloat) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(CGAffineTransform(rotationAngle: rotation))
        return CGSize(width: max(1, abs(rect.width)), height: max(1, abs(rect.height)))
    }
}

// MARK: - Editor view controller

final class ImageBackgroundEditorViewController: UIViewController, UIGestureRecognizerDelegate {
    var initialSelection: ImageBackgroundSelection = .defaultSelection()
    var cutoutImage: UIImage = UIImage()
    var cutoutSize: CGSize = .zero
    var canvasWidth: Int = 1200
    var canvasHeight: Int = 1200
    var fillRatio: Double = 0.88
    var onSave: ((ImageBackgroundSelection) -> Void)?
    var onCancel: (() -> Void)?

    private var workingSelection: ImageBackgroundSelection = .defaultSelection()
    private var baselineSelection: ImageBackgroundSelection = .defaultSelection()
    private var selectedLayer: ImageBackgroundEditorLayerKind?

    private let workspaceView = UIView()
    private let canvasContainer = UIView()
    private let canvasView = UIView()
    private let backgroundImageView = UIImageView()
    private let shadowPreviewView = UIView()
    private let reflectionImageView = UIImageView()
    private let productImageView = UIImageView()
    private let transformOverlay = LayerTransformOverlay()
    private let bottomChrome = UIStackView()
    private let layerMenuButton = UIButton(type: .system)
    private let resetLayerButton = UIButton(type: .system)
    private let lockLayerButton = UIButton(type: .system)
    private let cropButton = UIButton(type: .system)
    private let accessoryPanel = UIStackView()
    private let instructionLabel = UILabel()
    private let blurSlider = UISlider()
    private let productRotationSlider = UISlider()
    private let reflectionSlider = UISlider()
    private let shadowControlStack = UIStackView()
    private var canvasAspectConstraint: NSLayoutConstraint?
    private var fullResolutionBackground: UIImage = UIImage()
    private var didInitialCanvasLayout = false
    private var lastCanvasSize: CGSize = .zero
    private var blurApplyWorkItem: DispatchWorkItem?
    private var isGesturing = false
    private var resizeStartBounds: CGRect = .zero
    private var resizeStartCenter: CGPoint = .zero
    private var resizeStartAngle: CGFloat = 0

    private var canvasPixelSize: CGSize {
        CGSize(width: CGFloat(max(1, canvasWidth)), height: CGFloat(max(1, canvasHeight)))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        workingSelection = initialSelection
        baselineSelection = initialSelection
        selectedLayer = nil
        configureNavigation()
        configureLayout()
        reloadBackgroundImage(applyBlur: true)
        productImageView.image = cutoutImage
        productImageView.contentMode = .scaleAspectFit
        reflectionImageView.image = cutoutImage
        reflectionImageView.contentMode = .scaleAspectFit
        reflectionImageView.alpha = 0
        attachCanvasGestures(to: backgroundImageView)
        attachCanvasGestures(to: productImageView)
        ensureDefaultTransforms()
        updateChromeForSelectedLayer()
        wireTransformOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyAllLayerTransforms(animated: false)
        normalizeLayerZOrder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard canvasView.bounds.width > 0 else { return }
        let size = canvasView.bounds.size
        if size != lastCanvasSize {
            lastCanvasSize = size
            applyAllLayerTransforms(animated: false)
            normalizeLayerZOrder()
        }
        if !didInitialCanvasLayout {
            didInitialCanvasLayout = true
            applyAllLayerTransforms(animated: false)
            normalizeLayerZOrder()
        }
        if !isGesturing {
            updateAuxiliaryPreviews()
            updateTransformOverlay()
        }
    }

    private func configureNavigation() {
        title = "Background Editor"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneTapped))
        navigationController?.isToolbarHidden = true
    }

    private func configureLayout() {
        [workspaceView, canvasContainer, canvasView, bottomChrome, accessoryPanel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        canvasView.backgroundColor = UIColor.secondarySystemBackground
        canvasView.clipsToBounds = true
        canvasView.layer.cornerRadius = 8
        canvasView.layer.cornerCurve = .continuous
        canvasContainer.clipsToBounds = false

        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        productImageView.isUserInteractionEnabled = true
        backgroundImageView.isUserInteractionEnabled = true

        for sub in [backgroundImageView, shadowPreviewView, reflectionImageView, productImageView] {
            canvasView.addSubview(sub)
        }
        canvasContainer.addSubview(transformOverlay)
        transformOverlay.translatesAutoresizingMaskIntoConstraints = false

        bottomChrome.axis = .horizontal
        bottomChrome.spacing = 10
        bottomChrome.alignment = .fill
        bottomChrome.distribution = .fillEqually

        styleChromeButton(layerMenuButton, title: "Layer ▾")
        styleChromeButton(resetLayerButton, title: "Reset")
        styleChromeButton(lockLayerButton, title: "Lock")
        styleChromeButton(cropButton, title: "Crop")

        layerMenuButton.showsMenuAsPrimaryAction = true
        resetLayerButton.addTarget(self, action: #selector(resetSelectedLayerTapped), for: .touchUpInside)
        lockLayerButton.addTarget(self, action: #selector(toggleLockTapped), for: .touchUpInside)
        cropButton.addTarget(self, action: #selector(cropTapped), for: .touchUpInside)

        bottomChrome.addArrangedSubview(layerMenuButton)
        bottomChrome.addArrangedSubview(resetLayerButton)
        bottomChrome.addArrangedSubview(lockLayerButton)
        bottomChrome.addArrangedSubview(cropButton)

        accessoryPanel.axis = .vertical
        accessoryPanel.spacing = 8
        accessoryPanel.isLayoutMarginsRelativeArrangement = true
        accessoryPanel.layoutMargins = UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16)

        blurSlider.minimumValue = 0
        blurSlider.maximumValue = 30
        blurSlider.addTarget(self, action: #selector(blurChanged), for: .valueChanged)
        blurSlider.addTarget(self, action: #selector(blurFinished), for: [.touchUpInside, .touchUpOutside])

        productRotationSlider.minimumValue = -180
        productRotationSlider.maximumValue = 180
        productRotationSlider.addTarget(self, action: #selector(productRotationChanged), for: .valueChanged)

        reflectionSlider.minimumValue = 0
        reflectionSlider.maximumValue = 1
        reflectionSlider.addTarget(self, action: #selector(reflectionChanged), for: .valueChanged)

        shadowControlStack.axis = .horizontal
        shadowControlStack.spacing = 6
        shadowControlStack.distribution = .fillEqually
        for strength in ContactShadowStrength.allCases {
            let button = UIButton(type: .system)
            button.setTitle(strength.rawValue, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
            button.layer.cornerRadius = 8
            button.tag = ContactShadowStrength.allCases.firstIndex(of: strength) ?? 0
            button.addTarget(self, action: #selector(shadowChipTapped(_:)), for: .touchUpInside)
            shadowControlStack.addArrangedSubview(button)
        }

        instructionLabel.font = .systemFont(ofSize: 12, weight: .regular)
        instructionLabel.textColor = .secondaryLabel
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.isHidden = true

        canvasContainer.addSubview(canvasView)
        workspaceView.addSubview(canvasContainer)
        workspaceView.addSubview(instructionLabel)
        view.addSubview(workspaceView)
        view.addSubview(accessoryPanel)
        view.addSubview(bottomChrome)

        let aspect = CGFloat(canvasWidth) / CGFloat(max(1, canvasHeight))
        canvasAspectConstraint = canvasContainer.widthAnchor.constraint(equalTo: canvasContainer.heightAnchor, multiplier: aspect)

        NSLayoutConstraint.activate([
            workspaceView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            workspaceView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            workspaceView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            workspaceView.bottomAnchor.constraint(equalTo: accessoryPanel.topAnchor, constant: -8),

            canvasContainer.centerXAnchor.constraint(equalTo: workspaceView.centerXAnchor),
            canvasContainer.centerYAnchor.constraint(equalTo: workspaceView.centerYAnchor, constant: -12),
            canvasContainer.widthAnchor.constraint(lessThanOrEqualTo: workspaceView.widthAnchor),
            canvasContainer.heightAnchor.constraint(lessThanOrEqualTo: workspaceView.heightAnchor, constant: -52),
            canvasAspectConstraint!,
            canvasContainer.widthAnchor.constraint(equalTo: workspaceView.widthAnchor).withPriority(.defaultHigh),

            instructionLabel.topAnchor.constraint(equalTo: canvasContainer.bottomAnchor, constant: 10),
            instructionLabel.leadingAnchor.constraint(equalTo: workspaceView.leadingAnchor, constant: 4),
            instructionLabel.trailingAnchor.constraint(equalTo: workspaceView.trailingAnchor, constant: -4),
            instructionLabel.bottomAnchor.constraint(lessThanOrEqualTo: workspaceView.bottomAnchor),

            canvasView.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),

            transformOverlay.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            transformOverlay.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
            transformOverlay.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
            transformOverlay.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),

            accessoryPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            accessoryPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            accessoryPanel.bottomAnchor.constraint(equalTo: bottomChrome.topAnchor, constant: -8),

            bottomChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Space.screenHorizontal - 2),
            bottomChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -(DS.Space.screenHorizontal - 2)),
            bottomChrome.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomChrome.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func styleChromeButton(_ button: UIButton, title: String) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 6, bottom: 10, trailing: 6)
        config.background.cornerRadius = DS.Radius.chip
        config.background.strokeWidth = 1
        config.background.strokeColor = DSUIKit.separator
        config.background.backgroundColor = UIColor.secondarySystemFill
        config.baseForegroundColor = DSUIKit.label
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 14, weight: .semibold)
            out.underlineStyle = []
            return out
        }
        button.configuration = config
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        DSUIKit.installPressFeedback(on: button, scale: DS.Motion.pressScaleCompact)
    }

    private func updateChromeButtonTitle(_ button: UIButton, title: String) {
        styleChromeButton(button, title: title)
    }

    private func wireTransformOverlay() {
        transformOverlay.onHandleDrag = { [weak self] kind, gesture in
            self?.handleOverlayDrag(kind: kind, gesture: gesture)
        }
    }

    // MARK: - Background image

    private func backgroundLayerImageSize() -> CGSize {
        let cropped = ImageBackgroundRenderer.croppedBackgroundImage(
            fullResolutionBackground,
            crop: workingSelection.backgroundCrop
        )
        let size = cropped.size
        return size.width > 0 && size.height > 0 ? size : fullResolutionBackground.size
    }

    private func reloadBackgroundImage(applyBlur: Bool) {
        let def = ImageBackgroundRenderer.resolvedDefinition(for: workingSelection)
        fullResolutionBackground = ImageBackgroundAssetLoader.fullImage(for: def, customRef: workingSelection.customImageRef)
        var display = ImageBackgroundRenderer.croppedBackgroundImage(
            fullResolutionBackground,
            crop: workingSelection.backgroundCrop
        )
        if applyBlur, workingSelection.backgroundBlur > 0.5 {
            display = blurredPreviewImage(display, radius: CGFloat(workingSelection.backgroundBlur)) ?? display
        }
        backgroundImageView.image = display
        blurSlider.value = Float(workingSelection.backgroundBlur)
        reflectionSlider.value = Float(workingSelection.reflectionOpacity)
    }

    private func blurredPreviewImage(_ image: UIImage, radius: CGFloat) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(min(radius, 18), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: nil)
        let extent = ci.extent
        guard let cg = context.createCGImage(output.cropped(to: extent), from: extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    private func ensureDefaultTransforms() {
        let bgSize = backgroundLayerImageSize()
        if workingSelection.backgroundTransform == nil {
            workingSelection.backgroundTransform = ImageBackgroundRenderer.aspectFillTransform(imageSize: bgSize, canvasSize: canvasPixelSize)
        }
        if workingSelection.productTransform == nil {
            let def = ImageBackgroundRenderer.resolvedDefinition(for: workingSelection)
            let rect = ProductPlacementEngine.computeDrawRect(
                cutoutSize: cutoutSize,
                canvasSize: canvasPixelSize,
                fillRatio: fillRatio,
                background: def,
                placement: workingSelection.placement
            )
            workingSelection.productTransform = ImageBackgroundAutoPlacement.transform(from: rect, canvasSize: canvasPixelSize, aspect: cutoutSize)
        }
    }

    // MARK: - Transforms

    private func layoutToViewScale() -> CGFloat {
        guard canvasPixelSize.width > 0, canvasView.bounds.width > 0 else { return 1 }
        return canvasView.bounds.width / canvasPixelSize.width
    }

    private func applyAllLayerTransforms(animated: Bool) {
        applyBackgroundTransform(animated: animated)
        applyProductTransform(animated: animated)
        updateTransformOverlay()
    }

    private func applyBackgroundTransform(animated: Bool) {
        guard let transform = workingSelection.backgroundTransform else { return }
        applyTransform(transform, imageSize: backgroundLayerImageSize(), to: backgroundImageView, animated: animated)
    }

    private func applyProductTransform(animated: Bool) {
        guard let transform = workingSelection.productTransform else { return }
        applyTransform(transform, imageSize: cutoutSize, to: productImageView, animated: animated)
        applyTransform(transform, imageSize: cutoutSize, to: reflectionImageView, animated: animated)
    }

    private func applyTransform(_ transform: CompositeLayerTransform, imageSize: CGSize, to imageView: UIImageView, animated: Bool) {
        let pixelRect = CompositeLayoutEngine.absoluteDrawRect(
            transform: transform,
            cutoutSize: imageSize,
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
            imageView.bounds = CGRect(origin: .zero, size: viewRect.size)
            imageView.center = CGPoint(x: viewRect.midX, y: viewRect.midY)
            imageView.transform = CGAffineTransform(rotationAngle: CGFloat(transform.rotationRadians))
        }
        if animated { UIView.animate(withDuration: 0.2, animations: apply) } else { apply() }
    }

    private func syncTransformFromView(_ view: UIImageView, imageSize: CGSize, into transform: inout CompositeLayerTransform) {
        let scale = layoutToViewScale()
        guard scale > 0, canvasPixelSize.width > 0 else { return }
        let angle = atan2(view.transform.b, view.transform.a)
        let pixelCenter = CGPoint(x: view.center.x / scale, y: view.center.y / scale)
        let pixelWidth = view.bounds.width / scale
        transform = CompositeLayerTransform(
            centerX: Double(pixelCenter.x / canvasPixelSize.width),
            centerY: Double(pixelCenter.y / canvasPixelSize.height),
            scale: Double(pixelWidth / canvasPixelSize.width),
            rotationRadians: Double(angle)
        )
    }

    private func editableImageView(for layer: ImageBackgroundEditorLayerKind?) -> UIImageView? {
        guard let layer else { return nil }
        switch layer {
        case .product: return productImageView
        case .background: return backgroundImageView
        default: return nil
        }
    }

    private func isLayerLocked(_ layer: ImageBackgroundEditorLayerKind?) -> Bool {
        guard let layer else { return true }
        switch layer {
        case .product: return workingSelection.productLocked
        case .background: return workingSelection.backgroundLocked
        default: return true
        }
    }

    private func normalizeLayerZOrder() {
        canvasView.sendSubviewToBack(backgroundImageView)
        canvasView.insertSubview(shadowPreviewView, aboveSubview: backgroundImageView)
        canvasView.insertSubview(reflectionImageView, aboveSubview: shadowPreviewView)
        canvasView.bringSubviewToFront(productImageView)
        canvasContainer.bringSubviewToFront(transformOverlay)
    }

    private func selectLayer(_ layer: ImageBackgroundEditorLayerKind) {
        selectedLayer = layer
        normalizeLayerZOrder()
        updateChromeForSelectedLayer()
    }

    private func updateTransformOverlay() {
        guard let layer = selectedLayer, let view = editableImageView(for: layer), !isLayerLocked(layer) else {
            transformOverlay.isHidden = true
            return
        }
        transformOverlay.isHidden = false
        transformOverlay.align(to: view, in: canvasContainer)
        canvasContainer.bringSubviewToFront(transformOverlay)
    }

    // MARK: - Chrome

    private func updateChromeForSelectedLayer() {
        if let layer = selectedLayer {
            updateChromeButtonTitle(layerMenuButton, title: "\(layer.rawValue) ▾")
        } else {
            updateChromeButtonTitle(layerMenuButton, title: "Layer ▾")
        }

        let actions = ImageBackgroundEditorLayerKind.allCases.map { kind in
            UIAction(title: kind.rawValue, state: selectedLayer == kind ? .on : .off) { [weak self] _ in
                self?.selectLayer(kind)
            }
        }
        layerMenuButton.menu = UIMenu(title: "Select Layer", children: actions)

        let hasSelection = selectedLayer != nil
        lockLayerButton.isEnabled = selectedLayer == .product || selectedLayer == .background
        resetLayerButton.isEnabled = hasSelection
        cropButton.isEnabled = selectedLayer == .background
        cropButton.alpha = selectedLayer == .background ? 1 : 0.45

        if let layer = selectedLayer {
            updateChromeButtonTitle(lockLayerButton, title: isLayerLocked(layer) ? "Unlock" : "Lock")
        } else {
            updateChromeButtonTitle(lockLayerButton, title: "Lock")
        }

        accessoryPanel.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch selectedLayer {
        case .product:
            let label = UILabel()
            label.text = "Product Rotation"
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .label
            productRotationSlider.value = Float((workingSelection.productTransform?.rotationRadians ?? 0) * 180 / .pi)
            productRotationSlider.isEnabled = !isLayerLocked(.product)
            accessoryPanel.addArrangedSubview(label)
            accessoryPanel.addArrangedSubview(productRotationSlider)
        case .background:
            let label = UILabel()
            label.text = "Background Blur"
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .label
            accessoryPanel.addArrangedSubview(label)
            accessoryPanel.addArrangedSubview(blurSlider)
        case .reflection:
            let label = UILabel()
            label.text = "Reflection"
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .label
            accessoryPanel.addArrangedSubview(label)
            accessoryPanel.addArrangedSubview(reflectionSlider)
        case .shadow:
            let label = UILabel()
            label.text = "Shadow"
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .label
            accessoryPanel.addArrangedSubview(label)
            accessoryPanel.addArrangedSubview(shadowControlStack)
            updateShadowChipStyles()
        default:
            break
        }
        accessoryPanel.isHidden = selectedLayer == nil
        updateInstructionLabel()
        updateAuxiliaryPreviews()
        updateTransformOverlay()
    }

    private func updateInstructionLabel() {
        guard let layer = selectedLayer else {
            instructionLabel.text = "Choose a layer from the menu below to start editing."
            instructionLabel.isHidden = false
            return
        }
        instructionLabel.text = instructionText(for: layer)
        instructionLabel.isHidden = instructionLabel.text?.isEmpty ?? true
    }

    private func instructionText(for layer: ImageBackgroundEditorLayerKind) -> String {
        switch layer {
        case .product:
            return "Drag to move. Pinch to scale. Use the rotation slider or handles to rotate and resize."
        case .background:
            return "Drag to reposition. Pinch to scale. Use handles to resize or rotate. Tap Crop to trim the background image."
        case .shadow:
            return "Pick a shadow strength below."
        case .reflection:
            return "Adjust reflection intensity with the slider below."
        }
    }

    private func updateShadowChipStyles() {
        for case let button as UIButton in shadowControlStack.arrangedSubviews {
            let strength = ContactShadowStrength.allCases[button.tag]
            let selected = workingSelection.shadow == strength
            button.backgroundColor = selected ? DSUIKit.accent(traitCollection).withAlphaComponent(0.18) : UIColor.secondarySystemBackground
            button.setTitleColor(selected ? DSUIKit.accent(traitCollection) : .label, for: .normal)
        }
    }

    private func updateAuxiliaryPreviews() {
        shadowPreviewView.isHidden = workingSelection.shadow == .off
        if workingSelection.shadow != .off, let transform = workingSelection.productTransform {
            let scale = layoutToViewScale()
            let productRect = CompositeLayoutEngine.absoluteDrawRect(transform: transform, cutoutSize: cutoutSize, canvasSize: canvasPixelSize)
            let viewRect = CGRect(x: productRect.origin.x * scale, y: productRect.origin.y * scale, width: productRect.width * scale, height: productRect.height * scale)
            let shadowWidth = viewRect.width * 0.78
            let shadowHeight = max(6, viewRect.height * 0.12)
            shadowPreviewView.frame = CGRect(x: viewRect.midX - shadowWidth / 2, y: viewRect.maxY - shadowHeight * 0.35 + 6, width: shadowWidth, height: shadowHeight)
            shadowPreviewView.backgroundColor = UIColor.black.withAlphaComponent(0.25)
            shadowPreviewView.layer.cornerRadius = shadowHeight / 2
        }

        if workingSelection.reflectionOpacity > 0.01, let transform = workingSelection.productTransform {
            reflectionImageView.alpha = CGFloat(workingSelection.reflectionOpacity * 0.45)
            var reflected = transform
            reflected.centerY = min(0.98, transform.centerY + Double(transform.scale * cutoutSize.height / canvasPixelSize.height) * 0.85)
            applyTransform(reflected, imageSize: cutoutSize, to: reflectionImageView, animated: false)
            reflectionImageView.transform = reflectionImageView.transform.scaledBy(x: 1, y: -1)
        } else {
            reflectionImageView.alpha = 0
        }
    }

    // MARK: - Gestures

    private func attachCanvasGestures(to imageView: UIImageView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        imageView.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        imageView.addGestureRecognizer(pinch)
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotation.delegate = self
        imageView.addGestureRecognizer(rotation)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        imageView.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view as? UIImageView else { return }
        selectLayer(view === productImageView ? .product : .background)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view as? UIImageView else { return }
        let layer: ImageBackgroundEditorLayerKind = view === productImageView ? .product : .background
        if gesture.state == .began {
            selectLayer(layer)
        }
        guard selectedLayer == layer, !isLayerLocked(layer) else { return }
        isGesturing = gesture.state != .ended && gesture.state != .cancelled
        if gesture.state == .began || gesture.state == .changed {
            view.center = CGPoint(x: view.center.x + gesture.translation(in: canvasView).x, y: view.center.y + gesture.translation(in: canvasView).y)
            gesture.setTranslation(.zero, in: canvasView)
            transformOverlay.align(to: view, in: canvasContainer)
            updateAuxiliaryPreviews()
        }
        if gesture.state == .ended || gesture.state == .cancelled {
            persistTransform(from: view)
            isGesturing = false
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let view = gesture.view as? UIImageView else { return }
        let layer: ImageBackgroundEditorLayerKind = view === productImageView ? .product : .background
        if gesture.state == .began { selectLayer(layer) }
        guard selectedLayer == layer, !isLayerLocked(layer) else { return }
        isGesturing = gesture.state != .ended && gesture.state != .cancelled
        if gesture.state == .began || gesture.state == .changed {
            view.bounds.size = CGSize(width: max(24, view.bounds.width * gesture.scale), height: max(24, view.bounds.height * gesture.scale))
            gesture.scale = 1
            transformOverlay.align(to: view, in: canvasContainer)
            updateAuxiliaryPreviews()
        }
        if gesture.state == .ended || gesture.state == .cancelled {
            persistTransform(from: view)
            isGesturing = false
        }
    }

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let view = gesture.view as? UIImageView else { return }
        let layer: ImageBackgroundEditorLayerKind = view === productImageView ? .product : .background
        if gesture.state == .began { selectLayer(layer) }
        guard selectedLayer == layer, !isLayerLocked(layer) else { return }
        isGesturing = gesture.state != .ended && gesture.state != .cancelled
        if gesture.state == .began || gesture.state == .changed {
            view.transform = view.transform.rotated(by: gesture.rotation)
            gesture.rotation = 0
            transformOverlay.align(to: view, in: canvasContainer)
        }
        if gesture.state == .ended || gesture.state == .cancelled {
            persistTransform(from: view)
            isGesturing = false
        }
    }

    private func layerMatchesView(_ view: UIImageView, layer: ImageBackgroundEditorLayerKind) -> Bool {
        (view === productImageView && layer == .product) || (view === backgroundImageView && layer == .background)
    }

    private func persistTransform(from view: UIImageView) {
        if view === productImageView, var transform = workingSelection.productTransform {
            syncTransformFromView(view, imageSize: cutoutSize, into: &transform)
            workingSelection.productTransform = transform
            syncProductRotationSliderFromTransform()
        } else if view === backgroundImageView, var transform = workingSelection.backgroundTransform {
            syncTransformFromView(view, imageSize: backgroundLayerImageSize(), into: &transform)
            workingSelection.backgroundTransform = transform
        }
    }

    private func syncProductRotationSliderFromTransform() {
        guard selectedLayer == .product else { return }
        let degrees = Float((workingSelection.productTransform?.rotationRadians ?? 0) * 180 / .pi)
        productRotationSlider.value = degrees
    }

    @objc private func productRotationChanged() {
        guard selectedLayer == .product, !isLayerLocked(.product) else { return }
        guard var transform = workingSelection.productTransform else { return }
        transform.rotationRadians = Double(productRotationSlider.value * .pi / 180)
        workingSelection.productTransform = transform
        applyProductTransform(animated: false)
        updateTransformOverlay()
        updateAuxiliaryPreviews()
    }

    private func handleOverlayDrag(kind: LayerTransformOverlay.HandleKind, gesture: UIPanGestureRecognizer) {
        guard let layer = selectedLayer, let view = editableImageView(for: layer), !isLayerLocked(layer) else { return }
        isGesturing = gesture.state != .ended && gesture.state != .cancelled

        if gesture.state == .began {
            resizeStartBounds = view.bounds
            resizeStartCenter = view.center
            resizeStartAngle = atan2(view.transform.b, view.transform.a)
        }

        let translation = gesture.translation(in: canvasContainer)
        let cosA = cos(-resizeStartAngle)
        let sinA = sin(-resizeStartAngle)
        let local = CGPoint(x: translation.x * cosA - translation.y * sinA, y: translation.x * sinA + translation.y * cosA)

        if kind == .rotate {
            if gesture.state == .changed || gesture.state == .began {
                let center = view.center
                let touch = gesture.location(in: canvasContainer)
                let angle = atan2(touch.y - center.y, touch.x - center.x) + .pi / 2
                view.transform = CGAffineTransform(rotationAngle: angle)
            }
        } else if kind.isCorner || kind.isEdge {
            if gesture.state == .changed || gesture.state == .began {
                var newWidth = resizeStartBounds.width
                var newHeight = resizeStartBounds.height
                var centerOffsetLocal = CGPoint.zero

                switch kind {
                case .topLeft:
                    newWidth = max(24, resizeStartBounds.width - local.x)
                    newHeight = max(24, resizeStartBounds.height - local.y)
                    centerOffsetLocal = CGPoint(x: local.x / 2, y: local.y / 2)
                case .top:
                    newHeight = max(24, resizeStartBounds.height - local.y)
                    centerOffsetLocal = CGPoint(x: 0, y: local.y / 2)
                case .topRight:
                    newWidth = max(24, resizeStartBounds.width + local.x)
                    newHeight = max(24, resizeStartBounds.height - local.y)
                    centerOffsetLocal = CGPoint(x: local.x / 2, y: local.y / 2)
                case .right:
                    newWidth = max(24, resizeStartBounds.width + local.x)
                    centerOffsetLocal = CGPoint(x: local.x / 2, y: 0)
                case .bottomRight:
                    newWidth = max(24, resizeStartBounds.width + local.x)
                    newHeight = max(24, resizeStartBounds.height + local.y)
                    centerOffsetLocal = CGPoint(x: local.x / 2, y: local.y / 2)
                case .bottom:
                    newHeight = max(24, resizeStartBounds.height + local.y)
                    centerOffsetLocal = CGPoint(x: 0, y: local.y / 2)
                case .bottomLeft:
                    newWidth = max(24, resizeStartBounds.width - local.x)
                    newHeight = max(24, resizeStartBounds.height + local.y)
                    centerOffsetLocal = CGPoint(x: local.x / 2, y: local.y / 2)
                case .left:
                    newWidth = max(24, resizeStartBounds.width - local.x)
                    centerOffsetLocal = CGPoint(x: local.x / 2, y: 0)
                default:
                    break
                }

                if kind.isCorner {
                    let aspect = resizeStartBounds.height / max(resizeStartBounds.width, 1)
                    newHeight = newWidth * aspect
                }

                view.bounds.size = CGSize(width: newWidth, height: newHeight)
                let worldOffset = CGPoint(
                    x: centerOffsetLocal.x * cos(resizeStartAngle) - centerOffsetLocal.y * sin(resizeStartAngle),
                    y: centerOffsetLocal.x * sin(resizeStartAngle) + centerOffsetLocal.y * cos(resizeStartAngle)
                )
                view.center = CGPoint(x: resizeStartCenter.x + worldOffset.x, y: resizeStartCenter.y + worldOffset.y)
            }
        }

        if gesture.state == .ended || gesture.state == .cancelled {
            persistTransform(from: view)
            isGesturing = false
        }
        transformOverlay.align(to: view, in: canvasContainer)
        updateAuxiliaryPreviews()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: - Actions

    @objc private func resetSelectedLayerTapped() {
        guard let layer = selectedLayer else { return }
        resetLayer(layer)
    }

    @objc private func toggleLockTapped() {
        guard let layer = selectedLayer else { return }
        switch layer {
        case .product: workingSelection.productLocked.toggle()
        case .background: workingSelection.backgroundLocked.toggle()
        default: return
        }
        updateChromeForSelectedLayer()
    }

    private func resetLayer(_ kind: ImageBackgroundEditorLayerKind) {
        let def = ImageBackgroundRenderer.resolvedDefinition(for: workingSelection)
        switch kind {
        case .product:
            let rect = ProductPlacementEngine.computeDrawRect(cutoutSize: cutoutSize, canvasSize: canvasPixelSize, fillRatio: fillRatio, background: def, placement: .default)
            workingSelection.productTransform = ImageBackgroundAutoPlacement.transform(from: rect, canvasSize: canvasPixelSize, aspect: cutoutSize)
            workingSelection.placement = .default
        case .background:
            workingSelection.backgroundCrop = .full
            workingSelection.backgroundBlur = 0
            reloadBackgroundImage(applyBlur: true)
            workingSelection.backgroundTransform = ImageBackgroundRenderer.aspectFillTransform(
                imageSize: backgroundLayerImageSize(),
                canvasSize: canvasPixelSize
            )
        case .shadow:
            workingSelection.shadow = .off
        case .reflection:
            workingSelection.reflectionOpacity = 0
        }
        applyAllLayerTransforms(animated: true)
        normalizeLayerZOrder()
        updateChromeForSelectedLayer()
    }

    @objc private func blurChanged() {
        workingSelection.backgroundBlur = Double(blurSlider.value)
        blurApplyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadBackgroundImage(applyBlur: true)
            self?.applyBackgroundTransform(animated: false)
        }
        blurApplyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    @objc private func blurFinished() { reloadBackgroundImage(applyBlur: true) }

    @objc private func reflectionChanged() {
        workingSelection.reflectionOpacity = Double(reflectionSlider.value)
        updateAuxiliaryPreviews()
    }

    @objc private func shadowChipTapped(_ sender: UIButton) {
        workingSelection.shadow = ContactShadowStrength.allCases[sender.tag]
        updateShadowChipStyles()
        updateAuxiliaryPreviews()
    }

    @objc private func cropTapped() {
        selectLayer(.background)
        let cropVC = ImageBackgroundCropViewController()
        cropVC.sourceImage = fullResolutionBackground
        cropVC.existingCrop = workingSelection.backgroundCrop ?? .full
        cropVC.onApply = { [weak self] crop in
            guard let self else { return }
            self.workingSelection.backgroundCrop = crop
            self.reloadBackgroundImage(applyBlur: true)
            let croppedSize = self.backgroundLayerImageSize()
            self.workingSelection.backgroundTransform = ImageBackgroundRenderer.aspectFillTransform(
                imageSize: croppedSize,
                canvasSize: self.canvasPixelSize
            )
            self.applyAllLayerTransforms(animated: true)
            self.updateChromeForSelectedLayer()
        }
        present(UINavigationController(rootViewController: cropVC), animated: true)
    }

    @objc private func cancelTapped() {
        guard workingSelection != baselineSelection else {
            onCancel?()
            return
        }
        EditorUnsavedChangesAlert.present(
            on: self,
            message: "Save your background edits, discard them, or keep editing.",
            onDiscard: { [weak self] in self?.onCancel?() },
            onSave: { [weak self] in self?.doneTapped() }
        )
    }

    @objc private func doneTapped() {
        if let layer = selectedLayer, let view = editableImageView(for: layer) {
            persistTransform(from: view)
        }
        onSave?(workingSelection)
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

private extension CGRect {
    func nullRectFallback(_ fallback: CGRect) -> CGRect {
        width > 0 && height > 0 ? self : fallback
    }
}
