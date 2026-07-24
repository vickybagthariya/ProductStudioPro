import SwiftUI
import UIKit
import VisionKit

// MARK: - Memory / power guard

enum SubjectLiftSafety {
    /// Skip VisionKit subject analysis under thermal/memory pressure.
    @MainActor
    static var allowsSubjectLift: Bool {
        MemoryPressureMonitor.shared.allowsSubjectLift()
    }
}

// MARK: - Shared VisionKit subject lift (Photos-style)

@available(iOS 17.0, *)
@MainActor
final class SubjectLiftAnalysisController: NSObject, ImageAnalysisInteractionDelegate {
    private weak var anchorView: UIView?
    private(set) var interaction: ImageAnalysisInteraction?
    private var imageToken: String?
    private var displayImage: UIImage?
    private var analysisTask: Task<Void, Never>?
    private var longPressRecognizer: UILongPressGestureRecognizer?
    private let analyzer = ImageAnalyzer()

    func attach(to imageView: UIImageView) {
        anchorView = imageView
        if interaction == nil {
            let lift = ImageAnalysisInteraction(self)
            lift.preferredInteractionTypes = [.imageSubject]
            lift.isSupplementaryInterfaceHidden = true
            imageView.addInteraction(lift)
            interaction = lift
        }
        if longPressRecognizer == nil {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.42
            longPress.cancelsTouchesInView = false
            longPress.delaysTouchesBegan = false
            imageView.addGestureRecognizer(longPress)
            longPressRecognizer = longPress
        }
    }

    func setLiftEnabled(_ enabled: Bool) {
        anchorView?.isUserInteractionEnabled = enabled
        longPressRecognizer?.isEnabled = enabled
        interaction?.preferredInteractionTypes = enabled ? [.imageSubject] : []
        if !enabled {
            cancelAnalysis()
        }
    }

    func updateImage(_ image: UIImage, analyzeForLift: Bool) {
        displayImage = image
        let token = analysisToken(for: image)
        guard token != imageToken else { return }
        imageToken = token
        cancelAnalysis()
    }

    func cancel() {
        imageToken = nil
        displayImage = nil
        cancelAnalysis()
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        interaction?.analysis = nil
        interaction?.highlightedSubjects = []
    }

    private func analysisToken(for image: UIImage) -> String {
        let ptr = image.cgImage.map { Unmanaged.passUnretained($0).toOpaque() }
            ?? Unmanaged.passUnretained(image).toOpaque()
        return "\(ptr)-\(Int(image.size.width))x\(Int(image.size.height))"
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard let image = displayImage else { return }
        guard interaction?.analysis == nil else { return }
        beginLazyAnalysis(for: image)
    }

    private func beginLazyAnalysis(for image: UIImage) {
        analysisTask?.cancel()
        let token = imageToken
        let proxy = Self.analysisProxy(for: image, maxLongEdge: 768)
        analysisTask = Task { @MainActor in
            let configuration = ImageAnalyzer.Configuration([.text, .visualLookUp, .machineReadableCode])
            do {
                let analysis = try await analyzer.analyze(proxy, configuration: configuration)
                guard !Task.isCancelled, token == imageToken else { return }
                interaction?.analysis = analysis
                InteractionHaptics.success()
            } catch {
                guard !Task.isCancelled else { return }
            }
        }
    }

    /// Downsample for VisionKit analysis — full-res originals can exceed app memory limits.
    private static func analysisProxy(for image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        guard let cg = ImageProcessor.normalizedCGImage(image) else { return image }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let longest = max(w, h, 1)
        guard longest > maxLongEdge else { return image }
        let scale = maxLongEdge / longest
        let tw = max(1, Int((w * scale).rounded()))
        let th = max(1, Int((h * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: tw,
            height: th,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let scaled = ctx.makeImage() else { return image }
        return UIImage(cgImage: scaled, scale: 1, orientation: .up)
    }

    func presentingViewController(for interaction: ImageAnalysisInteraction) -> UIViewController? {
        var responder: UIResponder? = anchorView
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }
}

/// Host view that pins a `UIImageView` to bounds so SwiftUI does not expand to image pixel size.
@available(iOS 17.0, *)
final class SubjectLiftHostView: UIView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

/// Preview image + system subject lift; host view pins aspect-fit layout to the SwiftUI frame.
@available(iOS 17.0, *)
struct NativeSubjectLiftImageView: UIViewRepresentable {
    let image: UIImage
    var allowsSubjectLift: Bool = true

    func makeCoordinator() -> SubjectLiftAnalysisController { SubjectLiftAnalysisController() }

    func makeUIView(context: Context) -> SubjectLiftHostView {
        let host = SubjectLiftHostView()
        context.coordinator.attach(to: host.imageView)
        host.imageView.image = image
        context.coordinator.updateImage(image, analyzeForLift: allowsSubjectLift)
        context.coordinator.setLiftEnabled(allowsSubjectLift)
        return host
    }

    func updateUIView(_ host: SubjectLiftHostView, context: Context) {
        context.coordinator.setLiftEnabled(allowsSubjectLift)
        if host.imageView.image !== image {
            host.imageView.image = image
            context.coordinator.updateImage(image, analyzeForLift: allowsSubjectLift)
        }
    }

    static func dismantleUIView(_ uiView: SubjectLiftHostView, coordinator: SubjectLiftAnalysisController) {
        coordinator.cancel()
    }
}

/// Invisible hit layer over a SwiftUI `Image` (same layout, lift handled in UIKit).
@available(iOS 17.0, *)
struct NativeSubjectLiftOverlay: UIViewRepresentable {
    let image: UIImage
    var allowsSubjectLift: Bool = true

    func makeCoordinator() -> SubjectLiftAnalysisController { SubjectLiftAnalysisController() }

    func makeUIView(context: Context) -> SubjectLiftHostView {
        let host = SubjectLiftHostView()
        context.coordinator.attach(to: host.imageView)
        host.imageView.alpha = 0.015
        host.imageView.image = image
        context.coordinator.updateImage(image, analyzeForLift: allowsSubjectLift)
        context.coordinator.setLiftEnabled(allowsSubjectLift)
        return host
    }

    func updateUIView(_ host: SubjectLiftHostView, context: Context) {
        context.coordinator.setLiftEnabled(allowsSubjectLift)
        host.isUserInteractionEnabled = allowsSubjectLift
        if host.imageView.image !== image {
            host.imageView.image = image
            context.coordinator.updateImage(image, analyzeForLift: allowsSubjectLift)
        }
    }

    static func dismantleUIView(_ uiView: SubjectLiftHostView, coordinator: SubjectLiftAnalysisController) {
        coordinator.cancel()
    }
}

@available(iOS 17.0, *)
typealias SubjectLiftMenuOverlay = NativeSubjectLiftOverlay
