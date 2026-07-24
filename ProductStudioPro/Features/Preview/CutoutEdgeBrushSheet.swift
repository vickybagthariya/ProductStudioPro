import SwiftUI
import UIKit

/// Edge feather + paint keep/remove brush for cutout masks.
struct CutoutEdgeBrushSheet: View {
    @Environment(\.dismiss) private var dismiss

    let previewImage: UIImage
    @Binding var feather: Double
    @Binding var brushMaskData: Data?
    var onApply: () -> Void
    var onFeatherCommit: (() -> Void)? = nil

    @State private var mode: CutoutBrushMode = .erase
    @State private var brushSize: CGFloat = 28
    @State private var maskResetToken = 0
    @State private var draftFeather: Double = 0.35

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Paint to trim or restore the cutout edge. Red = remove, green = keep. Release feather to refresh softness.")
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.screenHorizontal)

                ZStack {
                    CheckerboardBackground()
                    CutoutBrushCanvas(
                        baseImage: previewImage,
                        mode: mode,
                        brushSize: brushSize,
                        initialMaskData: brushMaskData,
                        resetToken: maskResetToken,
                        onMaskChanged: { data, _ in
                            brushMaskData = data
                        }
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(DS.ColorToken.separator, lineWidth: 1)
                )
                .padding(.horizontal, DS.Space.screenHorizontal)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Edge feather")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(Int(draftFeather * 100))%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                    }
                    Slider(value: $draftFeather, in: 0...1) { editing in
                        if !editing {
                            feather = draftFeather
                            onFeatherCommit?()
                        }
                    }
                    .tint(DS.ColorToken.accent)

                    Picker("Brush", selection: $mode) {
                        ForEach(CutoutBrushMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Brush size")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(Int(brushSize))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                    }
                    Slider(value: $brushSize, in: 12...64)
                        .tint(DS.ColorToken.accent)

                    Button("Clear brush strokes") {
                        brushMaskData = nil
                        maskResetToken += 1
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.accent)
                }
                .padding(.horizontal, DS.Space.screenHorizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .background(DS.ColorToken.backgroundSecondary)
            .navigationTitle("Edge brush")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        feather = draftFeather
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { draftFeather = feather }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    let dark = (row + col) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: cell, height: cell)),
                        with: .color(dark ? Color(white: 0.82) : Color(white: 0.92))
                    )
                    x += cell
                    col += 1
                }
                y += cell
                row += 1
            }
        }
    }
}

enum CutoutBrushMode: String, CaseIterable, Identifiable {
    case erase = "Remove"
    case restore = "Keep"
    var id: String { rawValue }
}

private struct CutoutBrushCanvas: UIViewRepresentable {
    let baseImage: UIImage
    var mode: CutoutBrushMode
    var brushSize: CGFloat
    var initialMaskData: Data?
    var resetToken: Int
    var onMaskChanged: (Data?, UIImage?) -> Void

    func makeUIView(context: Context) -> BrushMaskView {
        let view = BrushMaskView()
        view.baseImage = baseImage
        view.baseSize = baseImage.size
        view.brushSize = brushSize
        view.isErase = mode == .erase
        view.onMaskChanged = onMaskChanged
        if let initialMaskData, let img = UIImage(data: initialMaskData) {
            view.loadMask(img)
        } else {
            view.resetToFullKeep()
        }
        return view
    }

    func updateUIView(_ uiView: BrushMaskView, context: Context) {
        uiView.baseImage = baseImage
        uiView.brushSize = brushSize
        uiView.isErase = mode == .erase
        uiView.onMaskChanged = onMaskChanged
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            uiView.resetToFullKeep()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastResetToken = 0
    }
}

private final class BrushMaskView: UIView {
    var baseImage: UIImage?
    var baseSize: CGSize = CGSize(width: 512, height: 512)
    var brushSize: CGFloat = 28
    var isErase = true
    var onMaskChanged: ((Data?, UIImage?) -> Void)?

    private var maskImage: UIImage?
    private var strokeOverlay: UIImage?
    private var lastPoint: CGPoint?
    private var hasUserStrokes = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func resetToFullKeep() {
        hasUserStrokes = false
        let size = workingSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        maskImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        strokeOverlay = renderer.image { _ in }
        onMaskChanged?(nil, nil)
        setNeedsDisplay()
    }

    func loadMask(_ image: UIImage) {
        hasUserStrokes = true
        maskImage = image
        let size = workingSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        strokeOverlay = UIGraphicsImageRenderer(size: size, format: format).image { _ in }
        emit()
        setNeedsDisplay()
    }

    private var workingSize: CGSize {
        let src = baseImage?.size ?? baseSize
        let maxEdge: CGFloat = 720
        let long = max(src.width, src.height)
        if long <= maxEdge { return CGSize(width: max(64, src.width), height: max(64, src.height)) }
        let scale = maxEdge / long
        return CGSize(width: max(64, src.width * scale), height: max(64, src.height * scale))
    }

    override func draw(_ rect: CGRect) {
        guard let baseImage else { return }
        let size = workingSize
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let drawW = size.width * scale
        let drawH = size.height * scale
        let origin = CGPoint(x: (bounds.width - drawW) / 2, y: (bounds.height - drawH) / 2)
        let drawRect = CGRect(origin: origin, size: CGSize(width: drawW, height: drawH))

        // Dimmed full image under masked result.
        baseImage.draw(in: drawRect, blendMode: .normal, alpha: 0.28)

        if let masked = maskedPreview(size: size) {
            masked.draw(in: drawRect)
        } else {
            baseImage.draw(in: drawRect)
        }
        strokeOverlay?.draw(in: drawRect, blendMode: .normal, alpha: 0.85)
    }

    private func maskedPreview(size: CGSize) -> UIImage? {
        guard let baseImage, let maskImage else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            baseImage.draw(in: CGRect(origin: .zero, size: size))
            maskImage.draw(in: CGRect(origin: .zero, size: size), blendMode: .destinationIn, alpha: 1)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastPoint = touches.first.map { convertPoint($0.location(in: self)) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = convertPoint(touch.location(in: self))
        stroke(from: lastPoint ?? point, to: point)
        lastPoint = point
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastPoint = nil
        emit()
    }

    private func convertPoint(_ p: CGPoint) -> CGPoint {
        let size = workingSize
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let drawW = size.width * scale
        let drawH = size.height * scale
        let origin = CGPoint(x: (bounds.width - drawW) / 2, y: (bounds.height - drawH) / 2)
        return CGPoint(
            x: (p.x - origin.x) / scale,
            y: (p.y - origin.y) / scale
        )
    }

    private func stroke(from: CGPoint, to: CGPoint) {
        hasUserStrokes = true
        let size = workingSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let priorMask = maskImage
        maskImage = renderer.image { ctx in
            if let priorMask {
                priorMask.draw(in: CGRect(origin: .zero, size: size))
            } else {
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            let path = UIBezierPath()
            path.move(to: from)
            path.addLine(to: to)
            path.lineWidth = brushSize
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            if isErase {
                ctx.cgContext.setBlendMode(.destinationOut)
                UIColor.black.setStroke()
            } else {
                ctx.cgContext.setBlendMode(.normal)
                UIColor.white.setStroke()
            }
            path.stroke()
        }

        strokeOverlay = renderer.image { ctx in
            strokeOverlay?.draw(in: CGRect(origin: .zero, size: size))
            let path = UIBezierPath()
            path.move(to: from)
            path.addLine(to: to)
            path.lineWidth = max(2, brushSize * 0.35)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            (isErase ? UIColor.systemRed.withAlphaComponent(0.55) : UIColor.systemGreen.withAlphaComponent(0.55)).setStroke()
            path.stroke()
        }

        setNeedsDisplay()
    }

    private func emit() {
        guard hasUserStrokes, let maskImage else {
            onMaskChanged?(nil, nil)
            return
        }
        onMaskChanged?(maskImage.pngData(), maskImage)
    }
}
