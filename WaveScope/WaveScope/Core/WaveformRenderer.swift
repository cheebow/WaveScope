import Foundation
import CoreGraphics

/// ピクセル列ごとの min/max を縦線で描く。SwiftUI 非依存(将来の QuickLook 拡張と共有可能)。
nonisolated enum WaveformRenderer {
    static func draw(mins: [Float], maxs: [Float], in ctx: CGContext, rect: CGRect, color: CGColor) {
        guard !mins.isEmpty, mins.count == maxs.count else { return }
        let midY = rect.midY
        let halfHeight = rect.height / 2

        var segments: [CGPoint] = []
        segments.reserveCapacity(mins.count * 2)
        for x in 0..<mins.count {
            let px = rect.minX + CGFloat(x) + 0.5
            var yTop = midY - CGFloat(min(max(maxs[x], -1), 1)) * halfHeight
            var yBottom = midY - CGFloat(min(max(mins[x], -1), 1)) * halfHeight
            if yBottom - yTop < 1 {
                // 無音でもヘアラインを描く
                yTop = midY - 0.5
                yBottom = midY + 0.5
            }
            segments.append(CGPoint(x: px, y: yTop))
            segments.append(CGPoint(x: px, y: yBottom))
        }
        ctx.setStrokeColor(color)
        ctx.setLineWidth(1)
        ctx.strokeLineSegments(between: segments)
    }
}
