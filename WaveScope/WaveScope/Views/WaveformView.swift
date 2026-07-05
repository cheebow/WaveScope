import SwiftUI
import AVFoundation

/// 波形表示 + クリックシーク + ドラッグ範囲選択 + ズーム/スクロール + 再生ヘッド + dBグリッド。
struct WaveformView: View {
    @Environment(AppModel.self) private var model
    let peaks: WaveformPeaks

    @State private var hoverPoint: CGPoint?

    private static let rulerHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            VStack(spacing: 0) {
                timeRuler(width: width)
                waveformArea(width: width)
            }
            .overlay(alignment: .topTrailing) {
                // hoverPoint はルーラーを除いた波形領域の座標なので、高さもルーラー分を引いて渡す
                cursorReadout(width: width, height: geo.size.height - Self.rulerHeight)
            }
            .clipped()
            .onChange(of: width, initial: true) { _, newWidth in model.viewWidth = newWidth }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: model.player.state) {
            // ズーム中の再生追従(ページ送り)
            guard model.player.state == .playing else { return }
            while !Task.isCancelled && model.player.state == .playing {
                model.followPlayheadIfNeeded()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func waveformArea(width: CGFloat) -> some View {
            ZStack(alignment: .leading) {
                waveformLayer
                selectionOverlay(width: width)
                playheadOverlay(width: width)
                WaveformInteractionView(
                    onClick: { x in
                        model.selection = nil
                        model.player.play(from: frame(at: x, width: width), to: peaks.frameCount)
                    },
                    onDragSelect: { x0, x1 in
                        let a = frame(at: x0, width: width)
                        let b = frame(at: x1, width: width)
                        model.selection = a...max(b, a)
                    },
                    onDragEnd: {
                        model.selectionDragEnded()
                    },
                    onScroll: { dx in
                        model.scroll(byPixels: dx, width: width)
                    },
                    onZoom: { factor, anchorX in
                        model.zoom(by: factor, anchorFraction: min(max(anchorX / width, 0), 1))
                    },
                    onHover: { point in
                        hoverPoint = point
                    }
                )
            }
    }

    // MARK: - 時間ルーラー

    private func timeRuler(width: CGFloat) -> some View {
        let visibleStart = model.visibleStart
        let visibleLength = model.visibleLength
        let sampleRate = peaks.sampleRate
        return Canvas { context, size in
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
        .frame(height: Self.rulerHeight)
    }

    private nonisolated static let rulerIntervals: [Double] = [
        0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5,
        1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200, 1800, 3600,
    ]

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

    // MARK: - 波形(再生ヘッドの更新で再描画されないよう TimelineView の外に置く)

    @ViewBuilder
    private var waveformLayer: some View {
        if model.displayMode == .stereo && peaks.channelCount >= 2 {
            VStack(spacing: 0) {
                channelCanvas(channel: 0)
                Divider()
                channelCanvas(channel: 1)
            }
        } else {
            channelCanvas(channel: nil)
        }
    }

    private func channelCanvas(channel: Int?) -> some View {
        // Observable の変更で再描画されるよう、依存値は body 側で読む
        let visibleStart = model.visibleStart
        let visibleEnd = model.visibleEnd
        let hiRes = model.hiResPeaks
        let peaks = peaks
        return Canvas { context, size in
            let width = Int(size.width)
            // 0dB が上下端に張り付かないよう余白を取る
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0, dy: 10)
            guard rect.height > 20 else { return }
            drawDBGridLines(in: &context, rect: rect)
            let (mins, maxs): ([Float], [Float])
            if let hiRes, hiRes.matches(startFrame: visibleStart, endFrame: visibleEnd, width: width) {
                (mins, maxs) = hiRes.pixelPeaks(channel: channel)
            } else {
                (mins, maxs) = peaks.pixelPeaks(width: width, channel: channel,
                                                startFrame: visibleStart, endFrame: visibleEnd)
            }
            let color = NSColor.controlAccentColor.cgColor
            context.withCGContext { ctx in
                WaveformRenderer.draw(mins: mins, maxs: maxs, in: ctx, rect: rect, color: color)
            }
            // ラベルは波形に重なっても読めるよう、波形の上に袋文字で描く
            drawDBLabels(in: &context, rect: rect)
        }
    }

    // MARK: - dBグリッド

    /// 3dB刻みの目盛り。ラベルを描く位置(間隔が十分な線)だけ dB 値を返す。
    private func dbGridEntries(halfHeight: CGFloat) -> [(dB: Double, offset: CGFloat, labeled: Bool)] {
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

    private func drawDBGridLines(in context: inout GraphicsContext, rect: CGRect) {
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
        for entry in dbGridEntries(halfHeight: halfHeight) {
            horizontalLine(at: midY - entry.offset)
            horizontalLine(at: midY + entry.offset)
        }
    }

    private func drawDBLabels(in context: inout GraphicsContext, rect: CGRect) {
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
        for entry in dbGridEntries(halfHeight: halfHeight) where entry.labeled {
            drawLabel("\(Int(entry.dB))", at: CGPoint(x: 4, y: midY - entry.offset))
            drawLabel("\(Int(entry.dB))", at: CGPoint(x: 4, y: midY + entry.offset))
        }
    }

    // MARK: - オーバーレイ

    @ViewBuilder
    private func selectionOverlay(width: CGFloat) -> some View {
        if let selection = model.selection {
            let x0 = xPosition(of: selection.lowerBound, width: width)
            let x1 = xPosition(of: selection.upperBound, width: width)
            if x1 > 0 && x0 < width {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.2))
                    .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor).frame(width: 1) }
                    .overlay(alignment: .trailing) { Rectangle().fill(Color.accentColor).frame(width: 1) }
                    .frame(width: max(x1 - x0, 2))
                    .offset(x: x0)
                    .allowsHitTesting(false)
            }
        }
    }

    private func playheadOverlay(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: model.player.state != .playing)) { _ in
            let x = xPosition(of: model.player.currentFrame, width: width)
            if x >= 0 && x <= width {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 1)
                    .offset(x: x)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - カーソル位置の時刻・dB表示

    @ViewBuilder
    private func cursorReadout(width: CGFloat, height: CGFloat) -> some View {
        if let point = hoverPoint, width > 0 {
            let time = Double(frame(at: point.x, width: width)) / peaks.sampleRate
            let isStereo = model.displayMode == .stereo && peaks.channelCount >= 2
            let channel: Int? = isStereo ? (point.y < height / 2 ? 0 : 1) : nil
            let channelName = isStereo ? (channel == 0 ? "L " : "R ") : ""
            let dB = model.peakDB(atColumn: Int(point.x), channel: channel, width: Int(width))
            let dBText = dB.map { String(format: "%.1f dB", $0) } ?? "-∞ dB"
            Text("\(formatTime(time))　\(channelName)\(dBText)")
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(6)
                .allowsHitTesting(false)
        }
    }

    // MARK: - 座標変換(表示範囲基準)

    private func frame(at x: CGFloat, width: CGFloat) -> AVAudioFramePosition {
        guard width > 0 else { return 0 }
        let ratio = min(max(x / width, 0), 1)
        return model.visibleStart + AVAudioFramePosition(ratio * CGFloat(model.visibleLength))
    }

    private func xPosition(of frame: AVAudioFramePosition, width: CGFloat) -> CGFloat {
        guard model.visibleLength > 0 else { return 0 }
        return CGFloat(frame - model.visibleStart) / CGFloat(model.visibleLength) * width
    }
}
