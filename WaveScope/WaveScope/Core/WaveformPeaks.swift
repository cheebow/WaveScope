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
/// 対象範囲・幅が一致するときだけ描画に使う。
nonisolated struct HighResPixelPeaks: Sendable {
    let startFrame: AVAudioFramePosition
    let endFrame: AVAudioFramePosition
    let width: Int
    /// [channel][pixel]
    let channelMins: [[Float]]
    let channelMaxs: [[Float]]

    func matches(startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition, width: Int) -> Bool {
        self.startFrame == startFrame && self.endFrame == endFrame && self.width == width
    }

    /// channel が nil ならば全チャンネル合成
    func pixelPeaks(channel: Int?) -> (mins: [Float], maxs: [Float]) {
        if let channel, channel < channelMins.count {
            return (channelMins[channel], channelMaxs[channel])
        }
        guard let first = channelMins.first else { return ([], []) }
        var mins = first
        var maxs = channelMaxs[0]
        for ch in 1..<channelMins.count {
            for i in 0..<mins.count {
                mins[i] = min(mins[i], channelMins[ch][i])
                maxs[i] = max(maxs[i], channelMaxs[ch][i])
            }
        }
        return (mins, maxs)
    }
}
