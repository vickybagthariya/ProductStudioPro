import SwiftUI
import UIKit

/// UIKit double-tap bridge — reliable inside `TabView` page swipers where SwiftUI `TapGesture` often loses.
struct PreviewDoubleTapZoomBridge: UIViewRepresentable {
    var onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleTap: onDoubleTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        recognizer.numberOfTapsRequired = 2
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDoubleTap = onDoubleTap
    }

    final class Coordinator: NSObject {
        var onDoubleTap: () -> Void

        init(onDoubleTap: @escaping () -> Void) {
            self.onDoubleTap = onDoubleTap
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onDoubleTap()
        }
    }
}

/// UIKit swipe-up bridge — opens info/metadata sheet (Photos-style). Works inside TabView + zoom hosts.
struct PreviewInfoSwipeUpBridge: UIViewRepresentable {
    var isEnabled: Bool
    var onSwipeUp: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeUp: onSwipeUp)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let swipe = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipeUp(_:))
        )
        swipe.direction = .up
        swipe.cancelsTouchesInView = false
        swipe.delaysTouchesBegan = false
        swipe.delaysTouchesEnded = false
        swipe.delegate = context.coordinator
        view.addGestureRecognizer(swipe)
        context.coordinator.swipeRecognizer = swipe
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onSwipeUp = onSwipeUp
        context.coordinator.isEnabled = isEnabled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSwipeUp: () -> Void
        var isEnabled: Bool = true
        weak var swipeRecognizer: UISwipeGestureRecognizer?

        init(onSwipeUp: @escaping () -> Void) {
            self.onSwipeUp = onSwipeUp
        }

        @objc func handleSwipeUp(_ gesture: UISwipeGestureRecognizer) {
            guard isEnabled, gesture.state == .ended else { return }
            onSwipeUp()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension View {
    /// Pinch, pan (when zoomed), and UIKit-backed double-tap for canvas preview.
    func previewCanvasZoomGestures(
        zoomScale: Binding<CGFloat>,
        pinchAnchor: Binding<CGFloat>,
        panBase: Binding<CGSize>,
        panGesture: Binding<CGSize>,
        onReset: @escaping () -> Void
    ) -> some View {
        modifier(PreviewCanvasZoomModifier(
            zoomScale: zoomScale,
            pinchAnchor: pinchAnchor,
            panBase: panBase,
            panGesture: panGesture,
            onReset: onReset
        ))
    }
}

private struct PreviewCanvasZoomModifier: ViewModifier {
    @Binding var zoomScale: CGFloat
    @Binding var pinchAnchor: CGFloat
    @Binding var panBase: CGSize
    @Binding var panGesture: CGSize
    var onReset: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                PreviewDoubleTapZoomBridge {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        if zoomScale > 1.02 {
                            onReset()
                        } else {
                            zoomScale = 2
                            pinchAnchor = 2
                        }
                    }
                }
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { magnification in
                        let newScale = pinchAnchor * magnification
                        zoomScale = min(5, max(1, newScale))
                    }
                    .onEnded { _ in
                        pinchAnchor = zoomScale
                        if zoomScale <= 1.02 { onReset() }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 22)
                    .onChanged { value in
                        if zoomScale > 1.02 { panGesture = value.translation }
                    }
                    .onEnded { value in
                        if zoomScale > 1.02 {
                            panBase.width += value.translation.width
                            panBase.height += value.translation.height
                            panGesture = .zero
                        }
                    }
            )
    }
}

// MARK: - Combined preview canvas (subject lift + zoom, UIKit gesture coexistence)

/// Photos-style subject lift (`ImageAnalysisInteraction`) with pinch/pan/double-tap on the same host.
@available(iOS 17.0, *)
struct PreviewZoomSubjectLiftHost: UIViewRepresentable {
    let image: UIImage
    var allowsSubjectLift: Bool
    @Binding var zoomScale: CGFloat
    @Binding var pinchAnchor: CGFloat
    @Binding var panBase: CGSize
    @Binding var panGesture: CGSize
    var onReset: () -> Void
    var onSwipeUp: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            zoomScale: $zoomScale,
            pinchAnchor: $pinchAnchor,
            panBase: $panBase,
            panGesture: $panGesture,
            onReset: onReset,
            onSwipeUp: onSwipeUp
        )
    }

    func makeUIView(context: Context) -> SubjectLiftHostView {
        let host = SubjectLiftHostView()
        context.coordinator.install(on: host, image: image, allowsSubjectLift: allowsSubjectLift)
        return host
    }

    func updateUIView(_ host: SubjectLiftHostView, context: Context) {
        context.coordinator.allowsSubjectLift = allowsSubjectLift
        context.coordinator.onSwipeUp = onSwipeUp
        context.coordinator.subjectLift.setLiftEnabled(allowsSubjectLift)
        if host.imageView.image !== image {
            host.imageView.image = image
            context.coordinator.subjectLift.updateImage(image, analyzeForLift: allowsSubjectLift)
        }
        context.coordinator.syncPinchAnchor(from: pinchAnchor)
        host.transform = .identity
    }

    static func dismantleUIView(_ uiView: SubjectLiftHostView, coordinator: Coordinator) {
        coordinator.subjectLift.cancel()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @Binding var zoomScale: CGFloat
        @Binding var pinchAnchor: CGFloat
        @Binding var panBase: CGSize
        @Binding var panGesture: CGSize
        var onReset: () -> Void
        var onSwipeUp: (() -> Void)?
        var allowsSubjectLift: Bool

        let subjectLift = SubjectLiftAnalysisController()
        private weak var host: SubjectLiftHostView?
        private var pinchStartScale: CGFloat = 1
        private var didInstallGestures = false

        init(
            zoomScale: Binding<CGFloat>,
            pinchAnchor: Binding<CGFloat>,
            panBase: Binding<CGSize>,
            panGesture: Binding<CGSize>,
            onReset: @escaping () -> Void,
            onSwipeUp: (() -> Void)?
        ) {
            _zoomScale = zoomScale
            _pinchAnchor = pinchAnchor
            _panBase = panBase
            _panGesture = panGesture
            self.onReset = onReset
            self.onSwipeUp = onSwipeUp
            allowsSubjectLift = true
        }

        func install(on host: SubjectLiftHostView, image: UIImage, allowsSubjectLift: Bool) {
            self.host = host
            self.allowsSubjectLift = allowsSubjectLift
            host.isUserInteractionEnabled = true
            host.imageView.image = image
            subjectLift.attach(to: host.imageView)
            subjectLift.setLiftEnabled(allowsSubjectLift)
            subjectLift.updateImage(image, analyzeForLift: allowsSubjectLift)
            pinchStartScale = pinchAnchor
            host.transform = .identity

            guard !didInstallGestures else { return }
            didInstallGestures = true

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            pinch.cancelsTouchesInView = false
            host.addGestureRecognizer(pinch)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.minimumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            host.addGestureRecognizer(pan)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = self
            doubleTap.cancelsTouchesInView = false
            host.addGestureRecognizer(doubleTap)

            let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp(_:)))
            swipeUp.direction = .up
            swipeUp.cancelsTouchesInView = false
            swipeUp.delegate = self
            host.addGestureRecognizer(swipeUp)
        }

        @objc private func handleSwipeUp(_ gesture: UISwipeGestureRecognizer) {
            guard gesture.state == .ended else { return }
            guard zoomScale <= 1.08 else { return }
            onSwipeUp?()
        }

        func syncPinchAnchor(from anchor: CGFloat) {
            if pinchStartScale != anchor, zoomScale <= 1.02 {
                pinchStartScale = anchor
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer is UIPanGestureRecognizer {
                return zoomScale > 1.02
            }
            return true
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchStartScale = pinchAnchor
            case .changed:
                zoomScale = min(5, max(1, pinchStartScale * gesture.scale))
            case .ended, .cancelled:
                pinchAnchor = zoomScale
                if zoomScale <= 1.02 { onReset() }
            default:
                break
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard zoomScale > 1.02 else { return }
            let translation = gesture.translation(in: gesture.view)
            if gesture.state == .ended || gesture.state == .cancelled {
                panBase.width += translation.x
                panBase.height += translation.y
                panGesture = .zero
                gesture.setTranslation(.zero, in: gesture.view)
            } else if gesture.state == .changed {
                panGesture = CGSize(width: translation.x, height: translation.y)
            }
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            if zoomScale > 1.02 {
                onReset()
            } else {
                zoomScale = 2
                pinchAnchor = 2
                pinchStartScale = 2
            }
        }
    }
}

// MARK: - UIScrollView zoom (fullscreen)

enum PhotoZoomScrollLayout {
    static func pixelSize(of image: UIImage) -> CGSize {
        CGSize(width: max(1, image.size.width * image.scale), height: max(1, image.size.height * image.scale))
    }

    static func centerImageView(in scrollView: UIScrollView, imageView: UIView) {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        imageView.center = CGPoint(
            x: scrollView.contentSize.width * 0.5 + offsetX,
            y: scrollView.contentSize.height * 0.5 + offsetY
        )
    }
}

/// Stable pinch-zoom scroll surface for full-screen photo viewing.
struct PhotoZoomScrollView: UIViewRepresentable {
    let image: UIImage
    var backgroundColor: UIColor = .black
    /// Change to force fit-zoom reset (e.g. new image).
    var resetToken: String = ""
    var allowsSubjectLift: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PhotoZoomScrollContainer {
        let container = PhotoZoomScrollContainer()
        container.coordinator = context.coordinator
        container.delegate = context.coordinator
        container.backgroundColor = backgroundColor
        container.showsVerticalScrollIndicator = false
        container.showsHorizontalScrollIndicator = false
        container.bouncesZoom = true
        container.decelerationRate = .fast
        container.contentInsetAdjustmentBehavior = .never
        container.minimumZoomScale = 1
        container.maximumZoomScale = 5

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.backgroundColor = backgroundColor
        container.addSubview(imageView)

        context.coordinator.scrollView = container
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        container.addGestureRecognizer(doubleTap)

        return container
    }

    func updateUIView(_ scrollView: PhotoZoomScrollContainer, context: Context) {
        scrollView.backgroundColor = backgroundColor
        context.coordinator.imageView?.backgroundColor = backgroundColor
        context.coordinator.imageView?.image = image
        context.coordinator.syncSubjectLift(image: image, enabled: allowsSubjectLift)

        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.userDidPinchZoom = false
            context.coordinator.needsFitZoom = true
        }
        context.coordinator.applyLayoutIfNeeded()
    }

    static func dismantleUIView(_ scrollView: PhotoZoomScrollContainer, coordinator: Coordinator) {
        coordinator.teardownSubjectLift()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: PhotoZoomScrollContainer?
        weak var imageView: UIImageView?
        var lastResetToken: String = ""
        var lastBoundsSize: CGSize = .zero
        var needsFitZoom = true
        var isZooming = false
        var userDidPinchZoom = false
        private var subjectLift: SubjectLiftAnalysisController?
        private var subjectLiftEnabled = false

        func teardownSubjectLift() {
            subjectLift?.cancel()
            subjectLift = nil
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isZooming = true
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            PhotoZoomScrollLayout.centerImageView(in: scrollView, imageView: imageView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isZooming = false
            userDidPinchZoom = scale > scrollView.minimumZoomScale * 1.04
        }

        /// Force the next layout pass to fit the image in bounds (e.g. after sheet open/close).
        func requestFitZoomReset() {
            userDidPinchZoom = false
            needsFitZoom = true
        }

        func syncSubjectLift(image: UIImage, enabled: Bool) {
            subjectLiftEnabled = enabled
            guard enabled else {
                if let subjectLift {
                    Task { @MainActor in subjectLift.setLiftEnabled(false) }
                }
                return
            }
            guard let imageView else { return }
            if #available(iOS 17.0, *) {
                Task { @MainActor in
                    if subjectLift == nil {
                        subjectLift = SubjectLiftAnalysisController()
                    }
                    subjectLift?.attach(to: imageView)
                    subjectLift?.setLiftEnabled(true)
                    subjectLift?.updateImage(image, analyzeForLift: true)
                }
            }
        }

        func applyLayoutIfNeeded() {
            guard let scrollView, let imageView, let image = imageView.image else { return }
            let bounds = scrollView.bounds.size
            guard bounds.width > 1, bounds.height > 1 else { return }

            let pixelSize = PhotoZoomScrollLayout.pixelSize(of: image)
            imageView.frame = CGRect(origin: .zero, size: pixelSize)

            let widthScale = bounds.width / pixelSize.width
            let heightScale = bounds.height / pixelSize.height
            let fitScale = min(widthScale, heightScale)

            let boundsChanged = abs(bounds.width - lastBoundsSize.width) > 1
                || abs(bounds.height - lastBoundsSize.height) > 1

            scrollView.minimumZoomScale = fitScale
            scrollView.maximumZoomScale = max(fitScale * 5, fitScale + 0.01)
            scrollView.contentSize = pixelSize

            let shouldFit = needsFitZoom
                || (!userDidPinchZoom && boundsChanged)
                || (!userDidPinchZoom && scrollView.zoomScale > fitScale * 1.04)
                || (!userDidPinchZoom && scrollView.zoomScale < fitScale * 0.96)

            if shouldFit {
                needsFitZoom = false
                scrollView.setZoomScale(fitScale, animated: false)
                scrollView.contentOffset = .zero
            }

            PhotoZoomScrollLayout.centerImageView(in: scrollView, imageView: imageView)
            lastBoundsSize = bounds
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scrollView, let imageView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale * 1.02 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let side: CGFloat = 120
                let zoomRect = CGRect(x: point.x - side * 0.5, y: point.y - side * 0.5, width: side, height: side)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
    }
}

/// Relayouts when bounds change, but never interrupts an active pinch-zoom.
final class PhotoZoomScrollContainer: UIScrollView {
    weak var coordinator: PhotoZoomScrollView.Coordinator?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let coordinator, !coordinator.isZooming else { return }
        let bounds = bounds.size
        guard bounds.width > 1, bounds.height > 1 else { return }
        let boundsChanged = abs(bounds.width - coordinator.lastBoundsSize.width) > 1
            || abs(bounds.height - coordinator.lastBoundsSize.height) > 1
        guard coordinator.needsFitZoom || boundsChanged else { return }
        coordinator.applyLayoutIfNeeded()
    }
}
