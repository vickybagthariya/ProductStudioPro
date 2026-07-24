import CoreGraphics
import Foundation

struct LayoutFrame: Equatable {
    let gridIndex: Int
    let frame: CGRect
}

enum CompositeLayoutEngine {
    /// Default spacing between grid cells on the export canvas (points at scale 1).
    static let defaultGridGapPoints: CGFloat = 24
    /// Grid occupies this fraction of the full canvas; remaining edge area is background margin.
    static let canvasFillRatio: Double = 0.95
    static let gridGapStepPoints: CGFloat = 4
    static let minGridGapPoints: CGFloat = 0
    static let maxGridGapPoints: CGFloat = 160

    static func computeGridFrames(
        matrix: CompositeLayoutMatrix,
        canvasSize: CGSize,
        gridGapPoints: CGFloat = defaultGridGapPoints,
        fillRatio: Double = canvasFillRatio,
        activeCellCount: Int? = nil
    ) -> [LayoutFrame] {
        guard matrix.rows > 0, matrix.columns > 0,
              canvasSize.width > 0, canvasSize.height > 0 else { return [] }

        let cellCount = activeCellCount.map { min(max(0, $0), matrix.cellCount) } ?? matrix.cellCount
        guard cellCount > 0 else { return [] }

        let outerRect = outerFillRect(in: canvasSize, fillRatio: fillRatio)
        let gap = clampGap(gridGapPoints)
        let cellWidth = (outerRect.width - gap * CGFloat(max(0, matrix.columns - 1))) / CGFloat(matrix.columns)
        let cellHeight = (outerRect.height - gap * CGFloat(max(0, matrix.rows - 1))) / CGFloat(matrix.rows)
        guard cellWidth > 0, cellHeight > 0 else { return [] }

        let usedRows = min(matrix.rows, (cellCount + matrix.columns - 1) / matrix.columns)
        let fullGridHeight = CGFloat(matrix.rows) * cellHeight + gap * CGFloat(max(0, matrix.rows - 1))
        let usedGridHeight = CGFloat(usedRows) * cellHeight + gap * CGFloat(max(0, usedRows - 1))
        let yOrigin = outerRect.minY + (fullGridHeight - usedGridHeight) / 2
        let fullRowWidth = CGFloat(matrix.columns) * cellWidth + gap * CGFloat(max(0, matrix.columns - 1))

        var frames: [LayoutFrame] = []
        for row in 0..<usedRows {
            let rowStart = row * matrix.columns
            let rowEnd = min(rowStart + matrix.columns, cellCount)
            let countInRow = rowEnd - rowStart
            guard countInRow > 0 else { continue }

            let rowWidth = CGFloat(countInRow) * cellWidth + gap * CGFloat(max(0, countInRow - 1))
            let xOffset = outerRect.minX + (fullRowWidth - rowWidth) / 2

            for col in 0..<countInRow {
                let index = rowStart + col
                let frame = CGRect(
                    x: xOffset + CGFloat(col) * (cellWidth + gap),
                    y: yOrigin + CGFloat(row) * (cellHeight + gap),
                    width: cellWidth,
                    height: cellHeight
                )
                frames.append(LayoutFrame(gridIndex: index, frame: frame))
            }
        }
        return frames
    }

    static func frame(
        forGridIndex gridIndex: Int,
        in matrix: CompositeLayoutMatrix,
        canvasSize: CGSize,
        gridGapPoints: CGFloat = defaultGridGapPoints,
        fillRatio: Double = canvasFillRatio,
        activeCellCount: Int? = nil
    ) -> CGRect? {
        computeGridFrames(
            matrix: matrix,
            canvasSize: canvasSize,
            gridGapPoints: gridGapPoints,
            fillRatio: fillRatio,
            activeCellCount: activeCellCount
        ).first { $0.gridIndex == gridIndex }?.frame
    }

    static func fitTransform(
        cutoutSize: CGSize,
        targetFrame: CGRect,
        canvasSize: CGSize,
        fillRatio: Double = 1.0
    ) -> CompositeLayerTransform {
        let fitted = aspectFitRect(imageSize: cutoutSize, in: targetFrame, fillRatio: fillRatio)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return .identity
        }
        return CompositeLayerTransform(
            centerX: Double(fitted.midX / canvasSize.width),
            centerY: Double(fitted.midY / canvasSize.height),
            scale: Double(fitted.width / canvasSize.width),
            rotationRadians: 0
        )
    }

    static func absoluteDrawRect(
        transform: CompositeLayerTransform,
        cutoutSize: CGSize,
        canvasSize: CGSize
    ) -> CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0,
              cutoutSize.width > 0, cutoutSize.height > 0 else { return .zero }

        let drawW = CGFloat(transform.scale) * canvasSize.width
        let drawH = drawW * (cutoutSize.height / cutoutSize.width)
        let center = CGPoint(
            x: CGFloat(transform.centerX) * canvasSize.width,
            y: CGFloat(transform.centerY) * canvasSize.height
        )
        return CGRect(
            x: center.x - drawW / 2,
            y: center.y - drawH / 2,
            width: drawW,
            height: drawH
        )
    }

    /// Aspect-fits `imageSize` inside `rect` without distortion.
    static func aspectFitDrawRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
        aspectFitRect(imageSize: imageSize, in: rect, fillRatio: 1.0)
    }

    static func gridIndex(
        at point: CGPoint,
        matrix: CompositeLayoutMatrix,
        canvasSize: CGSize,
        gridGapPoints: CGFloat = defaultGridGapPoints,
        fillRatio: Double = canvasFillRatio,
        activeCellCount: Int? = nil
    ) -> Int? {
        let frames = computeGridFrames(
            matrix: matrix,
            canvasSize: canvasSize,
            gridGapPoints: gridGapPoints,
            fillRatio: fillRatio,
            activeCellCount: activeCellCount
        )
        if let hit = frames.first(where: { $0.frame.contains(point) }) {
            return hit.gridIndex
        }
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for frame in frames {
            let d = hypot(point.x - frame.frame.midX, point.y - frame.frame.midY)
            if d < bestDistance {
                bestDistance = d
                bestIndex = frame.gridIndex
            }
        }
        return bestIndex
    }

    static func clampGap(_ gap: CGFloat) -> CGFloat {
        min(maxGridGapPoints, max(minGridGapPoints, gap))
    }

    // MARK: - Private

    private static func outerFillRect(in canvasSize: CGSize, fillRatio: Double) -> CGRect {
        let safeFill = CGFloat(max(0.30, min(fillRatio, 1.0)))
        let fitW = canvasSize.width * safeFill
        let fitH = canvasSize.height * safeFill
        return CGRect(
            x: (canvasSize.width - fitW) / 2,
            y: (canvasSize.height - fitH) / 2,
            width: fitW,
            height: fitH
        )
    }

    private static func aspectFitRect(imageSize: CGSize, in rect: CGRect, fillRatio: Double) -> CGRect {
        let safeFill = CGFloat(max(0.30, min(fillRatio, 1.0)))
        let fitW = rect.width * safeFill
        let fitH = rect.height * safeFill
        let inner = CGRect(
            x: rect.midX - fitW / 2,
            y: rect.midY - fitH / 2,
            width: fitW,
            height: fitH
        )
        guard imageSize.width > 1, imageSize.height > 1 else { return inner }

        let ws = inner.width / imageSize.width
        let hs = inner.height / imageSize.height
        let s = min(ws, hs)
        let w = imageSize.width * s
        let h = imageSize.height * s
        return CGRect(x: inner.midX - w / 2, y: inner.midY - h / 2, width: w, height: h)
    }
}
