import SwiftUI
import AVFoundation

/// 波形表示 + クリックシーク + ドラッグ範囲選択 + ズーム/スクロール + 再生ヘッド + dBグリッド。
struct WaveformView: View {
    @Environment(AppModel.self) private var model
    let peaks: WaveformPeaks

    @State private var hoverPoint: CGPoint?

    /// ステレオ2段表示かどうか。波形レイアウトとカーソルチップのチャンネル判定で共用する
    private var isStereoDisplay: Bool {
        model.displayMode == .stereo && peaks.channelCount >= 2
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            VStack(spacing: 0) {
                TimeRulerView(visibleStart: model.visibleStart,
                              visibleLength: model.visibleLength,
                              sampleRate: peaks.sampleRate)
                waveformArea(width: width)
            }
            .overlay(alignment: .topTrailing) {
                // hoverPoint はルーラーを除いた波形領域の座標なので、高さもルーラー分を引いて渡す
                cursorReadout(width: width, height: geo.size.height - TimeRulerView.height)
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

    // MARK: - 波形(再生ヘッドの更新で再描画されないよう TimelineView の外に置く)

    @ViewBuilder
    private var waveformLayer: some View {
        if isStereoDisplay {
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
            DBGrid.drawGridLines(in: &context, rect: rect)
            let (mins, maxs): ([Float], [Float])
            if let rebinned = hiRes?.rebinnedPeaks(startFrame: visibleStart, endFrame: visibleEnd,
                                                   width: width, channel: channel) {
                // 手元の高解像度データがカバーしている限りそこから再ビニングして描く。
                // 完全一致を要求すると操作や再生ページ送りのたびに粗い表示が挟まってチラつく
                (mins, maxs) = rebinned
            } else {
                (mins, maxs) = peaks.pixelPeaks(width: width, channel: channel,
                                                startFrame: visibleStart, endFrame: visibleEnd)
            }
            let color = NSColor.controlAccentColor.cgColor
            context.withCGContext { ctx in
                WaveformRenderer.draw(mins: mins, maxs: maxs, in: ctx, rect: rect, color: color)
            }
            // ラベルは波形に重なっても読めるよう、波形の上に袋文字で描く
            DBGrid.drawLabels(in: &context, rect: rect)
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
            let channel: Int? = isStereoDisplay ? (point.y < height / 2 ? 0 : 1) : nil
            let channelName = isStereoDisplay ? (channel == 0 ? "L " : "R ") : ""
            let dB = model.peakDB(atColumn: Int(point.x), channel: channel, width: Int(width))
            let dBText = dB.map { String(format: "%.1f dB", $0) } ?? "-∞ dB"
            Text(verbatim: "\(formatTime(time))　\(channelName)\(dBText)")
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
