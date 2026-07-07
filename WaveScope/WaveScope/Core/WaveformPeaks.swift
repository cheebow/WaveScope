import Foundation
import AVFoundation

/// デコード済み音声のチャンネル別 min/max ピークキャッシュ。
/// 固定解像度(samplesPerBin)で保持し、表示幅へは pixelPeaks で再ビニングする。
nonisolated struct WaveformPeaks: Sendable {
    let sampleRate: Double
    let frameCount: AVAudioFramePosition
    let samplesPerBin: Int
    /// [channel][bin]
    let channelMins: [[Float]]
    let channelMaxs: [[Float]]

    var channelCount: Int { channelMins.count }
    var duration: TimeInterval { Double(frameCount) / sampleRate }

    /// 全体を表示幅へ再ビニング(後方互換)
    func pixelPeaks(width: Int, channel: Int?) -> (mins: [Float], maxs: [Float]) {
        pixelPeaks(width: width, channel: channel, startFrame: 0, endFrame: frameCount)
    }

    /// フレーム範囲 [startFrame, endFrame) を表示幅(ピクセル数)ぶんの min/max に再ビニングする。
    /// channel が nil ならば全チャンネル合成(モノ表示)。
    func pixelPeaks(width: Int, channel: Int?,
                    startFrame: AVAudioFramePosition,
                    endFrame: AVAudioFramePosition) -> (mins: [Float], maxs: [Float]) {
        let binCount = channelMins.first?.count ?? 0
        guard width > 0, binCount > 0, endFrame > startFrame else { return ([], []) }

        var outMins = [Float](repeating: 0, count: width)
        var outMaxs = [Float](repeating: 0, count: width)
        let framesPerPixel = Double(endFrame - startFrame) / Double(width)
        for x in 0..<width {
            let f0 = Double(startFrame) + Double(x) * framesPerPixel
            let f1 = f0 + framesPerPixel
            let (lo, hi) = binRangePeak(f0: f0, f1: f1, channel: channel, binCount: binCount)
            outMins[x] = lo
            outMaxs[x] = hi
        }
        return (outMins, outMaxs)
    }

    /// 1ピクセル列ぶんのピーク(カーソル位置のdB表示用)
    func columnPeak(x: Int, width: Int, channel: Int?,
                    startFrame: AVAudioFramePosition,
                    endFrame: AVAudioFramePosition) -> (min: Float, max: Float)? {
        let binCount = channelMins.first?.count ?? 0
        guard width > 0, binCount > 0, endFrame > startFrame, (0..<width).contains(x) else { return nil }
        let framesPerPixel = Double(endFrame - startFrame) / Double(width)
        let f0 = Double(startFrame) + Double(x) * framesPerPixel
        return binRangePeak(f0: f0, f1: f0 + framesPerPixel, channel: channel, binCount: binCount)
    }

    private func binRangePeak(f0: Double, f1: Double, channel: Int?, binCount: Int) -> (Float, Float) {
        let b0 = min(max(Int(f0) / samplesPerBin, 0), binCount - 1)
        let b1 = min(max(Int(f1) / samplesPerBin, b0 + 1), binCount)
        let channels: Range<Int>
        if let channel, channel < channelCount {
            channels = channel ..< channel + 1
        } else {
            channels = 0 ..< channelCount
        }
        var lo = Float.greatestFiniteMagnitude
        var hi = -Float.greatestFiniteMagnitude
        for ch in channels {
            for b in b0..<b1 {
                lo = min(lo, channelMins[ch][b])
                hi = max(hi, channelMaxs[ch][b])
            }
        }
        return lo <= hi ? (lo, hi) : (0, 0)
    }
}

/// ズーム時にファイルから直接抽出した高解像度ピクセルピーク。
/// 表示範囲より広いマージン付きで抽出しておき、カバーしている範囲は
/// rebinnedPeaks で任意の表示範囲・幅へ再ビニングして描画する
/// (完全一致を要求すると、ズーム/パン/再生ページ送りのたびに
/// 粗いキャッシュへ先祖返りして表示がチラつく)。
nonisolated struct HighResPixelPeaks: Sendable {
    let startFrame: AVAudioFramePosition
    let endFrame: AVAudioFramePosition
    let width: Int
    /// [channel][pixel]
    let channelMins: [[Float]]
    let channelMaxs: [[Float]]

    /// 指定範囲がこのデータの範囲内に収まっているか(解像度は問わない)
    func covers(startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition) -> Bool {
        width > 0 && endFrame > startFrame
            && self.startFrame <= startFrame && endFrame <= self.endFrame
    }

    /// カバーしている範囲 [startFrame, endFrame) を出力幅へ再ビニングする。
    /// カバーしていなければ nil。channel が nil ならば全チャンネル合成。
    func rebinnedPeaks(startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition,
                       width outWidth: Int, channel: Int?) -> (mins: [Float], maxs: [Float])? {
        guard covers(startFrame: startFrame, endFrame: endFrame), outWidth > 0 else { return nil }
        var outMins = [Float](repeating: 0, count: outWidth)
        var outMaxs = [Float](repeating: 0, count: outWidth)
        let framesPerPixel = Double(endFrame - startFrame) / Double(outWidth)
        for x in 0..<outWidth {
            let f0 = Double(startFrame - self.startFrame) + Double(x) * framesPerPixel
            if let (lo, hi) = columnRangePeak(f0: f0, f1: f0 + framesPerPixel, channel: channel) {
                outMins[x] = lo
                outMaxs[x] = hi
            }
        }
        return (outMins, outMaxs)
    }

    /// 1ピクセル列ぶんのピーク(カーソル位置のdB表示用)。カバー外は nil。
    func columnPeak(x: Int, width outWidth: Int, channel: Int?,
                    startFrame: AVAudioFramePosition,
                    endFrame: AVAudioFramePosition) -> (min: Float, max: Float)? {
        guard covers(startFrame: startFrame, endFrame: endFrame), outWidth > 0,
              (0..<outWidth).contains(x) else { return nil }
        let framesPerPixel = Double(endFrame - startFrame) / Double(outWidth)
        let f0 = Double(startFrame - self.startFrame) + Double(x) * framesPerPixel
        return columnRangePeak(f0: f0, f1: f0 + framesPerPixel, channel: channel)
    }

    /// データ先頭からのフレームオフセット範囲 [f0, f1) に重なる列の min/max
    private func columnRangePeak(f0: Double, f1: Double, channel: Int?) -> (Float, Float)? {
        let framesPerColumn = Double(endFrame - startFrame) / Double(width)
        let c0 = min(max(Int(f0 / framesPerColumn), 0), width - 1)
        let c1 = min(max(Int(ceil(f1 / framesPerColumn)), c0 + 1), width)
        let channels: Range<Int>
        if let channel, channel < channelMins.count {
            channels = channel ..< channel + 1
        } else {
            channels = 0 ..< channelMins.count
        }
        var lo = Float.greatestFiniteMagnitude
        var hi = -Float.greatestFiniteMagnitude
        for ch in channels {
            for c in c0..<c1 {
                lo = min(lo, channelMins[ch][c])
                hi = max(hi, channelMaxs[ch][c])
            }
        }
        return lo <= hi ? (lo, hi) : nil
    }
}
