import SwiftUI

/// 波形背景の dB グリッド(3dB刻みの水平線と袋文字ラベル)の描画。
/// 0dB を上下端・中央線を挟んで対称に、対数スケールでオフセットを計算する。
enum DBGrid {
    /// 3dB刻みの目盛り。ラベルを描く位置(間隔が十分な線)だけ labeled が真になる。
    static func entries(halfHeight: CGFloat) -> [(dB: Double, offset: CGFloat, labeled: Bool)] {
        // 線: 3dB刻み、詰まりすぎる線は間引く
        var lines: [(dB: Double, offset: CGFloat)] = []
        var lastLineOffset = halfHeight   // 0dB(端)から開始
        for dB in stride(from: -3.0, through: -24.0, by: -3.0) {
            let offset = CGFloat(pow(10, dB / 20)) * halfHeight
            guard lastLineOffset - offset >= 4 else { continue }
            lines.append((dB, offset))
            lastLineOffset = offset
        }
        // ラベル: -6/-12/-18/-24 を優先し、空きがあれば -3/-9/-15/-21 も付ける
        var labeledOffsets: [CGFloat] = [halfHeight]   // 0dB ラベルぶん
        var labeled = Set<Double>()
        for dB in [-6.0, -12, -18, -24, -3, -9, -15, -21] {
            guard let line = lines.first(where: { $0.dB == dB }) else { continue }
            if labeledOffsets.allSatisfy({ abs($0 - line.offset) >= 12 }) {
                labeled.insert(dB)
                labeledOffsets.append(line.offset)
            }
        }
        return lines.map { ($0.dB, $0.offset, labeled.contains($0.dB)) }
    }

    static func drawGridLines(in context: inout GraphicsContext, rect: CGRect) {
        let midY = rect.midY
        let halfHeight = rect.height / 2
        let lineColor = Color(nsColor: .separatorColor)

        func horizontalLine(at y: CGFloat) {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(path, with: .color(lineColor), lineWidth: 1)
        }

        horizontalLine(at: rect.minY)   // 0dB
        horizontalLine(at: rect.maxY)   // 0dB
        horizontalLine(at: midY)
        for entry in entries(halfHeight: halfHeight) {
            horizontalLine(at: midY - entry.offset)
            horizontalLine(at: midY + entry.offset)
        }
    }

    static func drawLabels(in context: inout GraphicsContext, rect: CGRect) {
        let midY = rect.midY
        let halfHeight = rect.height / 2

        func drawLabel(_ text: String, at point: CGPoint) {
            // 袋文字: 周囲8方向に背景色で描いてから本体を重ねる
            let halo = context.resolve(
                Text(text).font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(nsColor: .textBackgroundColor))
            )
            let body = context.resolve(
                Text(text).font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            )
            for dx in [-1.0, 0, 1] {
                for dy in [-1.0, 0, 1] where !(dx == 0 && dy == 0) {
                    context.draw(halo, at: CGPoint(x: point.x + dx, y: point.y + dy), anchor: .leading)
                }
            }
            context.draw(body, at: point, anchor: .leading)
        }

        drawLabel("0dB", at: CGPoint(x: 4, y: rect.minY))
        for entry in entries(halfHeight: halfHeight) where entry.labeled {
            drawLabel("\(Int(entry.dB))", at: CGPoint(x: 4, y: midY - entry.offset))
            drawLabel("\(Int(entry.dB))", at: CGPoint(x: 4, y: midY + entry.offset))
        }
    }
}
