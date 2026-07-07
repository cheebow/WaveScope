import SwiftUI
import AVFoundation

/// 波形上部の時間ルーラー。表示範囲に応じて目盛り間隔ときざみラベルの精度が変わる。
struct TimeRulerView: View {
    let visibleStart: AVAudioFramePosition
    let visibleLength: AVAudioFramePosition
    let sampleRate: Double

    static let height: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(nsColor: .windowBackgroundColor)))
            var bottom = Path()
            bottom.move(to: CGPoint(x: 0, y: size.height - 0.5))
            bottom.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(bottom, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1)

            guard visibleLength > 0, sampleRate > 0, size.width > 0 else { return }
            let startSec = Double(visibleStart) / sampleRate
            let visibleSec = Double(visibleLength) / sampleRate
            let endSec = startSec + visibleSec
            let interval = Self.rulerInterval(forDesired: visibleSec * 90.0 / Double(size.width))
            let tickColor = Color(nsColor: .tertiaryLabelColor)

            func x(of t: Double) -> CGFloat { CGFloat((t - startSec) / visibleSec) * size.width }

            // 小目盛り(1/5間隔、詰まりすぎるときは省略)
            let minor = interval / 5
            if CGFloat(minor / visibleSec) * size.width >= 6 {
                var ticks = Path()
                var i = Int(ceil(startSec / minor))
                while Double(i) * minor <= endSec {
                    let px = x(of: Double(i) * minor)
                    ticks.move(to: CGPoint(x: px, y: size.height - 4))
                    ticks.addLine(to: CGPoint(x: px, y: size.height))
                    i += 1
                }
                context.stroke(ticks, with: .color(tickColor), lineWidth: 1)
            }

            // 大目盛りとラベル
            var majors = Path()
            var i = Int(ceil(startSec / interval - 1e-9))
            while Double(i) * interval <= endSec {
                let t = Double(i) * interval
                let px = x(of: t)
                majors.move(to: CGPoint(x: px, y: size.height - 9))
                majors.addLine(to: CGPoint(x: px, y: size.height))
                let label = Text(Self.rulerLabel(seconds: t, interval: interval))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                context.draw(label, at: CGPoint(x: px + 3, y: size.height / 2 - 3), anchor: .leading)
                i += 1
            }
            context.stroke(majors, with: .color(Color(nsColor: .secondaryLabelColor)), lineWidth: 1)
        }
        .frame(height: Self.height)
    }

    private nonisolated static let rulerIntervals: [Double] = [
        0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5,
        1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200, 1800, 3600,
    ]

    // rulerInterval / rulerLabel はテスト用に internal にしてある
    nonisolated static func rulerInterval(forDesired desired: Double) -> Double {
        rulerIntervals.first { $0 >= desired } ?? 3600
    }

    nonisolated static func rulerLabel(seconds: Double, interval: Double) -> String {
        let minutes = Int(seconds) / 60
        let secPart = seconds - Double(minutes * 60)
        if interval >= 1 {
            return String(format: "%d:%02d", minutes, Int(secPart.rounded()))
        }
        let digits = min(3, max(1, Int(ceil(-log10(interval)))))
        return String(format: "%d:%0\(digits + 3).\(digits)f", minutes, secPart)
    }
}
