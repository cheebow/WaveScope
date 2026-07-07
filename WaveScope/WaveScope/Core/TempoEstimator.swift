import Foundation
import AVFoundation
import Accelerate

/// 曲のテンポ(BPM)を音声解析(スペクトラルフラックス → 自己相関)で推定する。
/// タグ由来の BPM は AudioMetadata.bpm を先に確認し、無い場合だけこちらを使うこと。
/// estimateTempo は同期・ブロッキング実装なので、呼び出し側で Task.detached 等に載せること。
nonisolated enum TempoEstimator {
    /// 推定対象のテンポ範囲
    private static let minBPM = 40.0
    private static let maxBPM = 240.0

    private static let frameSize = 1024
    private static let hopSize = 256
    /// 自己相関ピークがこの値(正規化 -1〜1)未満なら「ビートなし」として nil を返す
    private static let confidenceThreshold: Float = 0.1

    // MARK: - 音声解析によるテンポ推定

    /// ファイル中央の最大 maxAnalysisSeconds 秒をモノラル化して解析する。
    /// ビートが検出できない(無音・持続音など)場合は nil。
    static func estimateTempo(from url: URL, maxAnalysisSeconds: Double = 60) throws -> Double? {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        let totalFrames = file.length
        guard channelCount > 0, totalFrames > 0 else { throw AudioReadError.emptyFile }

        let analysisFrames = min(totalFrames, AVAudioFramePosition(maxAnalysisSeconds * format.sampleRate))
        var mono = [Float](repeating: 0, count: Int(analysisFrames))
        let scale = 1.0 / Float(channelCount)
        try PeakExtractor.readChunks(of: file, from: (totalFrames - analysisFrames) / 2,
                                     frames: analysisFrames) { data, n, offset in
            mono.withUnsafeMutableBufferPointer { out in
                for ch in 0..<channelCount {
                    let samples = data[ch]
                    for i in 0..<n {
                        out[offset + i] += samples[i] * scale
                    }
                }
            }
        }

        return estimateTempo(monoSamples: mono, sampleRate: format.sampleRate)
    }

    /// モノラルサンプル列からテンポを推定する(テスト用に分離)。
    /// 4秒未満、またはビートの周期性が弱い場合は nil。
    static func estimateTempo(monoSamples: [Float], sampleRate: Double) -> Double? {
        guard sampleRate > 0, monoSamples.count >= Int(sampleRate * 4) else { return nil }
        guard var envelope = onsetEnvelope(of: monoSamples) else { return nil }
        let envelopeRate = sampleRate / Double(hopSize)

        // 移動平均窓は推定範囲の外(minBPM の周期 60/minBPM 秒の 5/3 倍)に置く。
        // 窓幅と同じ周期の人工的な相関が整流で生まれるため、範囲内だと誤検出になる
        detrend(&envelope, windowLength: Int(envelopeRate * 60 / minBPM * 5 / 3))

        // 平均を引いてから自己相関(オンセット列は非負なのでベースラインを除く)
        let mean = vDSP.mean(envelope)
        vDSP.add(-mean, envelope, result: &envelope)
        let energy = vDSP.sumOfSquares(envelope)
        guard energy > .ulpOfOne else { return nil }

        let minLag = max(2, Int(envelopeRate * 60 / maxBPM))
        let maxLag = Int(envelopeRate * 60 / minBPM)
        // 倍周期の支持を見るため 2*maxLag+2 まで計算する(重なりが最低約1秒残る範囲まで)
        let maxCorrLag = min(2 * maxLag + 2, envelope.count - Int(envelopeRate))
        guard maxLag < maxCorrLag, minLag < maxLag else { return nil }

        var correlation = [Float](repeating: 0, count: maxCorrLag + 1)
        envelope.withUnsafeBufferPointer { env in
            for lag in minLag...maxCorrLag {
                var dot: Float = 0
                vDSP_dotpr(env.baseAddress!, 1, env.baseAddress! + lag, 1, &dot,
                           vDSP_Length(env.count - lag))
                correlation[lag] = dot / energy
            }
        }

        // スコア = 自己相関 + 倍周期の支持(基本周期を優先)× 120BPM 中心の緩い事前分布
        var bestLag = 0
        var bestScore = -Float.greatestFiniteMagnitude
        for lag in minLag...maxLag {
            let harmonic = 2 * lag <= maxCorrLag ? 0.4 * correlation[2 * lag] : 0
            let bpm = 60 * envelopeRate / Double(lag)
            let octaves = Float(log2(bpm / 120))
            let prior = exp(-0.5 * (octaves / 0.9) * (octaves / 0.9))
            let score = (correlation[lag] + harmonic) * prior
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestLag > 0, correlation[bestLag] >= confidenceThreshold else { return nil }

        // 本物のビート列なら周期の倍数すべてに自己相関ピークが立つ。倍周期に支持が
        // 無いのは孤立イベントの偶然の一致(無音ギャップの両端など)なので棄却する。
        // 倍周期を検証できないほど入力が短い場合も、検証なしで値を返さず棄却する
        let doubled = 2 * bestLag
        guard doubled + 2 <= maxCorrLag else { return nil }
        var peak = doubled
        for lag in (doubled - 2)...(doubled + 2) where correlation[lag] > correlation[peak] {
            peak = lag
        }
        guard correlation[peak] >= max(0.05, 0.25 * correlation[bestLag]) else { return nil }

        // 倍周期のピークから周期を出すとラグ量子化誤差が半分になる
        let refinedLag = interpolatePeak(correlation, at: peak, min: minLag, max: maxCorrLag) / 2
        return min(max(60 * envelopeRate / refinedLag, minBPM), maxBPM)
    }

    /// 放物線補間でピーク位置をサブサンプル精度にする
    private static func interpolatePeak(_ correlation: [Float], at lag: Int, min minLag: Int, max maxLag: Int) -> Double {
        guard lag > minLag, lag < maxLag else { return Double(lag) }
        let a = Double(correlation[lag - 1])
        let b = Double(correlation[lag])
        let c = Double(correlation[lag + 1])
        let denominator = a - 2 * b + c
        guard abs(denominator) > .ulpOfOne else { return Double(lag) }
        return Double(lag) + min(max(0.5 * (a - c) / denominator, -0.5), 0.5)
    }

    /// スペクトラルフラックス(振幅スペクトルの正の増分の総和)のオンセット強度列を返す。
    /// 持続音や無音でフラックスが実質ゼロの場合は nil。
    private static func onsetEnvelope(of samples: [Float]) -> [Float]? {
        let frameCount = (samples.count - frameSize) / hopSize + 1
        guard frameCount > 8 else { return nil }
        let log2n = vDSP_Length(log2(Double(frameSize)))
        guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            return nil
        }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                 count: frameSize, isHalfWindow: false)
        let halfSize = frameSize / 2

        var windowed = [Float](repeating: 0, count: frameSize)
        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        var outReal = [Float](repeating: 0, count: halfSize)
        var outImag = [Float](repeating: 0, count: halfSize)
        var magnitude = [Float](repeating: 0, count: halfSize)
        var previousMagnitude = [Float](repeating: 0, count: halfSize)
        var difference = [Float](repeating: 0, count: halfSize)
        var envelope = [Float](repeating: 0, count: frameCount)
        var spectralSum: Float = 0

        for frame in 0..<frameCount {
            let start = frame * hopSize
            samples.withUnsafeBufferPointer { buf in
                vDSP.multiply(UnsafeBufferPointer(rebasing: buf[start..<start + frameSize]),
                              window, result: &windowed)
            }
            real.withUnsafeMutableBufferPointer { realBuf in
                imag.withUnsafeMutableBufferPointer { imagBuf in
                    outReal.withUnsafeMutableBufferPointer { outRealBuf in
                        outImag.withUnsafeMutableBufferPointer { outImagBuf in
                            var input = DSPSplitComplex(realp: realBuf.baseAddress!,
                                                        imagp: imagBuf.baseAddress!)
                            var output = DSPSplitComplex(realp: outRealBuf.baseAddress!,
                                                         imagp: outImagBuf.baseAddress!)
                            windowed.withUnsafeBufferPointer { w in
                                w.baseAddress!.withMemoryRebound(to: DSPComplex.self,
                                                                 capacity: halfSize) { complex in
                                    vDSP_ctoz(complex, 2, &input, 1, vDSP_Length(halfSize))
                                }
                            }
                            fft.forward(input: input, output: &output)
                            vDSP.squareMagnitudes(output, result: &magnitude)
                        }
                    }
                }
            }
            // 振幅スペクトルに変換し、DC(bin0 の実部にパックされている)は音量ドリフト対策で除外
            vForce.sqrt(magnitude, result: &magnitude)
            magnitude[0] = 0
            spectralSum += vDSP.sum(magnitude)
            vDSP.subtract(magnitude, previousMagnitude, result: &difference)
            vDSP.threshold(difference, to: 0, with: .zeroFill, result: &difference)
            envelope[frame] = vDSP.sum(difference)
            swap(&magnitude, &previousMagnitude)
        }

        // 持続音(サイン波など)はスペクトルが変化せずフラックスがほぼゼロになる。
        // 数値誤差由来の擬似フラックスを弾くため、総スペクトル量に対する相対値で判定する
        guard vDSP.sum(envelope) > max(spectralSum * 1e-3, 1e-9) else { return nil }
        return envelope
    }

    /// 移動平均を引いて半波整流し、緩やかな音量変化の影響を除く。
    /// 窓幅と同じ周期に整流由来の人工相関が立つため、呼び出し側は
    /// windowLength をテンポ推定範囲(minBPM の周期)より十分長く取ること。
    private static func detrend(_ envelope: inout [Float], windowLength: Int) {
        let window = max(3, min(windowLength, envelope.count))
        var prefix = [Double](repeating: 0, count: envelope.count + 1)
        for i in 0..<envelope.count {
            prefix[i + 1] = prefix[i] + Double(envelope[i])
        }
        let half = window / 2
        for i in 0..<envelope.count {
            let lo = max(0, i - half)
            let hi = min(envelope.count, i + half + 1)
            let localMean = Float((prefix[hi] - prefix[lo]) / Double(hi - lo))
            envelope[i] = max(0, envelope[i] - localMean)
        }
    }
}
