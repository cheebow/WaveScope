import Foundation
import AVFoundation

nonisolated enum AudioReadError: LocalizedError {
    case emptyFile
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .emptyFile: "音声データが空です"
        case .bufferAllocationFailed: "バッファの確保に失敗しました"
        }
    }
}

/// AVAudioFile をチャンク読みして固定解像度の min/max ピークを抽出する。
/// 同期・ブロッキング実装なので、呼び出し側で Task.detached 等に載せること。
nonisolated enum PeakExtractor {
    /// [start, start+frames) を 65536 フレームずつ読み、チャンクごとに body を呼ぶ共通ループ。
    /// body には (チャンネル別サンプル, 有効フレーム数 n, 範囲先頭からのオフセット) が渡る。
    /// 圧縮フォーマットでは要求より多くデコードされ得るため、範囲を超えるフレームは
    /// ここで捨てる(呼び出し側の配列サイズの根拠を超えると境界外書き込みになる)。
    static func readChunks(
        of file: AVAudioFile,
        from start: AVAudioFramePosition,
        frames total: AVAudioFramePosition,
        _ body: (_ channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
                 _ frameCount: Int, _ offset: Int) throws -> Void
    ) throws {
        let chunkFrames: AVAudioFrameCount = 65536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: chunkFrames) else {
            throw AudioReadError.bufferAllocationFailed
        }
        file.framePosition = start
        var offset = 0
        while offset < Int(total) {
            try Task.checkCancellation()
            try file.read(into: buffer)
            let n = min(Int(buffer.frameLength), Int(total) - offset)
            guard n > 0, let data = buffer.floatChannelData else { break }
            try body(data, n, offset)
            offset += n
        }
    }

    static func extractPeaks(
        from url: URL,
        samplesPerBin: Int = 256,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> WaveformPeaks {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        let totalFrames = file.length
        guard channelCount > 0, totalFrames > 0 else { throw AudioReadError.emptyFile }

        let binCount = Int((totalFrames + AVAudioFramePosition(samplesPerBin) - 1)
                           / AVAudioFramePosition(samplesPerBin))
        var mins = [[Float]](repeating: [Float](repeating: .greatestFiniteMagnitude, count: binCount),
                             count: channelCount)
        var maxs = [[Float]](repeating: [Float](repeating: -.greatestFiniteMagnitude, count: binCount),
                             count: channelCount)
        var lastReported = 0.0

        try readChunks(of: file, from: 0, frames: totalFrames) { data, n, offset in
            for ch in 0..<channelCount {
                let samples = data[ch]
                mins[ch].withUnsafeMutableBufferPointer { minBuf in
                    maxs[ch].withUnsafeMutableBufferPointer { maxBuf in
                        var i = 0
                        while i < n {
                            let globalFrame = offset + i
                            let binIndex = globalFrame / samplesPerBin
                            let remainingInBin = samplesPerBin - globalFrame % samplesPerBin
                            let end = min(n, i + remainingInBin)
                            var lo = minBuf[binIndex]
                            var hi = maxBuf[binIndex]
                            while i < end {
                                let s = samples[i]
                                if s < lo { lo = s }
                                if s > hi { hi = s }
                                i += 1
                            }
                            minBuf[binIndex] = lo
                            maxBuf[binIndex] = hi
                        }
                    }
                }
            }
            if let progress {
                let p = Double(offset + n) / Double(totalFrames)
                if p - lastReported >= 0.01 || p >= 1.0 {
                    lastReported = p
                    progress(p)
                }
            }
        }

        // サンプルが入らなかった bin(末尾など)は無音扱いにする
        for ch in 0..<channelCount {
            for b in 0..<binCount where mins[ch][b] > maxs[ch][b] {
                mins[ch][b] = 0
                maxs[ch][b] = 0
            }
        }

        return WaveformPeaks(
            sampleRate: format.sampleRate,
            frameCount: totalFrames,
            samplesPerBin: samplesPerBin,
            channelMins: mins,
            channelMaxs: maxs
        )
    }

    /// ズーム表示用: フレーム範囲 [startFrame, endFrame) をファイルから直接読み、
    /// ピクセル列ごとの min/max を全チャンネルぶん抽出する。
    static func extractPixelPeaks(
        from url: URL,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        width: Int
    ) throws -> HighResPixelPeaks {
        let file = try AVAudioFile(forReading: url)
        let channelCount = Int(file.processingFormat.channelCount)
        let start = max(0, min(startFrame, file.length))
        let end = max(start, min(endFrame, file.length))
        let totalFrames = Int(end - start)
        guard channelCount > 0, totalFrames > 0, width > 0 else { throw AudioReadError.emptyFile }

        var mins = [[Float]](repeating: [Float](repeating: .greatestFiniteMagnitude, count: width),
                             count: channelCount)
        var maxs = [[Float]](repeating: [Float](repeating: -.greatestFiniteMagnitude, count: width),
                             count: channelCount)
        let framesPerPixel = Double(totalFrames) / Double(width)

        try readChunks(of: file, from: start, frames: AVAudioFramePosition(totalFrames)) { data, n, offset in
            for ch in 0..<channelCount {
                let samples = data[ch]
                mins[ch].withUnsafeMutableBufferPointer { minBuf in
                    maxs[ch].withUnsafeMutableBufferPointer { maxBuf in
                        for i in 0..<n {
                            let column = min(Int(Double(offset + i) / framesPerPixel), width - 1)
                            let s = samples[i]
                            if s < minBuf[column] { minBuf[column] = s }
                            if s > maxBuf[column] { maxBuf[column] = s }
                        }
                    }
                }
            }
        }

        // サンプルが入らなかった列は近傍と同じ扱いで無音にする
        for ch in 0..<channelCount {
            for x in 0..<width where mins[ch][x] > maxs[ch][x] {
                mins[ch][x] = 0
                maxs[ch][x] = 0
            }
        }

        return HighResPixelPeaks(
            startFrame: start,
            endFrame: end,
            width: width,
            channelMins: mins,
            channelMaxs: maxs
        )
    }
}
