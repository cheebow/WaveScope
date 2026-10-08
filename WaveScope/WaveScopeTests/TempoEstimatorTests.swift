import Testing
import AVFoundation
@testable import WaveScope

struct TempoEstimatorTests {
    /// 短い減衰トーンバースト(クリック音)を samples の start 位置へ書き込む。
    /// クリックトラックと孤立過渡音の両テストで同じ波形を使う(回帰テストの前提)
    private func writeClick(into samples: inout [Float], at start: Int, sampleRate: Double) {
        let clickLength = Int(0.02 * sampleRate)
        for i in 0..<min(clickLength, samples.count - start) {
            let t = Double(i) / sampleRate
            samples[start + i] = Float(0.9 * exp(-t * 200) * sin(2 * .pi * 2000 * t))
        }
    }

    /// 指定 BPM のクリックトラックを合成する
    private func makeClickTrack(bpm: Double, seconds: Double, sampleRate: Double = 44100) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * sampleRate))
        let interval = 60.0 / bpm * sampleRate
        var position = 0.0
        while Int(position) < samples.count {
            writeClick(into: &samples, at: Int(position), sampleRate: sampleRate)
            position += interval
        }
        return samples
    }

    // MARK: - ジャンル別パターン(クリックより現実に近い合成。倍/半テンポ誤りの回帰用)

    /// 再現性のための固定シード疑似乱数(タイミングジッタ・音量ゆらぎ用)
    private struct SeededRandom {
        var state: UInt64 = 42
        mutating func next(in range: ClosedRange<Double>) -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double((state >> 11) & 0xFFFFFFFF) / Double(0xFFFFFFFF)
            return range.lowerBound + (range.upperBound - range.lowerBound) * unit
        }
    }

    /// 1小節を16分グリッドで表したヒット(kind: kick/snare/hat/tone)を繰り返して曲を合成する。
    /// ±4ms のジッタと音量ゆらぎ、小節ごとに変わる持続コード(パッド)を含む
    private func renderSong(bpm: Double, seconds: Double,
                            hits: [(position: Double, kind: String, amp: Double)],
                            sampleRate: Double = 44100) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * sampleRate))
        var random = SeededRandom()

        // パッド: 小節ごとにコードを差し替える持続音(持続成分があってもビートを見失わない確認)
        let barLength = Int(4 * 60 / bpm * sampleRate)
        let chords: [[Double]] = [[220, 277.2, 329.6], [174.6, 220, 261.6], [196, 246.9, 293.7]]
        var position = 0
        var barIndex = 0
        while position < samples.count {
            let chord = chords[barIndex % chords.count]
            for i in 0..<min(barLength, samples.count - position) {
                let t = Double(i) / sampleRate
                let envelope = min(t / 0.15, 1)
                var value = 0.0
                for frequency in chord { value += sin(2 * .pi * frequency * t) }
                samples[position + i] += Float(0.18 * envelope * value / Double(chord.count))
            }
            barIndex += 1
            position += barLength
        }

        let sixteenth = 60 / bpm / 4 * sampleRate
        var bar = 0
        while Double(bar) * Double(barLength) < Double(samples.count) {
            for hit in hits {
                let jitter = random.next(in: -0.004...0.004) * sampleRate
                let start = Int(Double(bar * barLength) + hit.position * sixteenth + jitter)
                guard start >= 0, start < samples.count else { continue }
                let amp = hit.amp * random.next(in: 0.75...1.0)
                switch hit.kind {
                case "kick":
                    for i in 0..<min(Int(0.18 * sampleRate), samples.count - start) {
                        let t = Double(i) / sampleRate
                        let frequency = 55 + 60 * exp(-t * 40)
                        samples[start + i] += Float(amp * min(t / 0.004, 1) * exp(-t * 18)
                                                    * sin(2 * .pi * frequency * t))
                    }
                case "snare":
                    for i in 0..<min(Int(0.14 * sampleRate), samples.count - start) {
                        let t = Double(i) / sampleRate
                        let noise = random.next(in: -1...1)
                        samples[start + i] += Float(amp * min(t / 0.002, 1) * exp(-t * 25)
                                                    * (0.7 * noise + 0.5 * sin(2 * .pi * 190 * t)))
                    }
                case "hat":
                    for i in 0..<min(Int(0.05 * sampleRate), samples.count - start) {
                        let t = Double(i) / sampleRate
                        let noise = random.next(in: -1...1)
                        samples[start + i] += Float(amp * min(t / 0.001, 1) * exp(-t * 60) * noise)
                    }
                case "tone":
                    // ピアノ的なソフトアタックの減衰トーン
                    for i in 0..<min(Int(1.2 * sampleRate), samples.count - start) {
                        let t = Double(i) / sampleRate
                        let envelope = min(t / 0.012, 1) * exp(-t * 3)
                        var value = 0.0
                        for (harmonic, weight) in [(1.0, 1.0), (2.0, 0.5), (3.0, 0.25)] {
                            value += weight * sin(2 * .pi * 261.6 * harmonic * t)
                        }
                        samples[start + i] += Float(amp * envelope * value / 1.75)
                    }
                default:
                    break
                }
            }
            bar += 1
        }
        return samples
    }

    /// バックビート(スネア2・4拍、キックはシンコペート)+8分ハット
    @Test func ロックのバックビートを推定できる() throws {
        let samples = renderSong(bpm: 104, seconds: 30, hits: [
            (0, "kick", 0.9), (6, "kick", 0.8), (10, "kick", 0.85),
            (4, "snare", 0.8), (12, "snare", 0.8),
            (0, "hat", 0.25), (2, "hat", 0.18), (4, "hat", 0.25), (6, "hat", 0.18),
            (8, "hat", 0.25), (10, "hat", 0.18), (12, "hat", 0.25), (14, "hat", 0.18),
        ])
        let bpm = try #require(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: 44100))
        #expect(abs(bpm - 104) < 2, "推定: \(bpm)")
    }

    /// ドラムなしのソフトなピアノ+パッド。オンセットが疎な曲は8分音符レベルの
    /// 倍テンポ(144)に化けやすい(事前分布を 102 BPM 中心に較正した理由の回帰)
    @Test func ピアノバラードが倍テンポにならない() throws {
        let samples = renderSong(bpm: 72, seconds: 30, hits: [
            (0, "tone", 0.35), (4, "tone", 0.35), (6, "tone", 0.3), (8, "tone", 0.35),
            (11, "tone", 0.28), (12, "tone", 0.35), (14, "tone", 0.3),
        ])
        let bpm = try #require(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: 44100))
        #expect(abs(bpm - 72) < 2, "推定: \(bpm)")
    }

    /// レゲエ・ワンドロップ: 1拍目に何もなく、静かなハットがオフビートを刻む。
    /// 線形フラックスではハットが埋もれて倍テンポ(152)になった回帰(対数圧縮で解消)
    @Test func レゲエのオフビートを推定できる() throws {
        let samples = renderSong(bpm: 76, seconds: 30, hits: [
            (8, "kick", 0.9), (8, "snare", 0.7),
            (2, "hat", 0.3), (6, "hat", 0.3), (10, "hat", 0.3), (14, "hat", 0.3),
            (4, "tone", 0.3), (12, "tone", 0.3),
        ])
        let bpm = try #require(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: 44100))
        #expect(abs(bpm - 76) < 2, "推定: \(bpm)")
    }

    @Test func クリックトラック120BPMを推定できる() throws {
        let samples = makeClickTrack(bpm: 120, seconds: 30)
        let bpm = try #require(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: 44100))
        #expect(abs(bpm - 120) < 1.5, "推定: \(bpm)")
    }

    @Test func クリックトラック90BPMを推定できる() throws {
        let samples = makeClickTrack(bpm: 90, seconds: 30)
        let bpm = try #require(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: 44100))
        #expect(abs(bpm - 90) < 1.5, "推定: \(bpm)")
    }

    /// 128 はエンベロープのラグ境界に乗らない値(量子化誤差が出やすい)
    @Test func クリックトラック128BPMを整数表示精度で推定できる() throws {
        let samples = makeClickTrack(bpm: 128, seconds: 30)
        let bpm = try #require(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: 44100))
        #expect(abs(bpm - 128) < 0.5, "推定: \(bpm)")
    }

    @Test func 持続するサイン波はビートなしとしてnilを返す() {
        let sampleRate = 44100.0
        let samples = (0..<Int(sampleRate * 10)).map { i in
            Float(0.5 * sin(2 * .pi * 440 * Double(i) / sampleRate))
        }
        #expect(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: sampleRate) == nil)
    }

    /// 短いクリップ×遅いテンポでも倍周期の支持チェックが働くこと
    /// (過去に4.5秒クリップの孤立ペアで支持チェックがスキップされ約50 BPMと誤検出された回帰)
    @Test func 短いクリップの孤立した過渡音ペアはnilを返す() {
        let sampleRate = 44100.0
        var samples = [Float](repeating: 0, count: Int(sampleRate * 4.5))
        for start in [Int(sampleRate * 1.0), Int(sampleRate * 2.2)] {
            writeClick(into: &samples, at: start, sampleRate: sampleRate)
        }
        #expect(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: sampleRate) == nil)
    }

    /// test.wav と同じ構成(サイン波+中央に1秒の無音ギャップ)。
    /// ギャップ境界の孤立したオンセットやサイン波の数値ノイズを
    /// ビートと誤検出しないこと(過去に BPM 60 と誤検出した回帰)
    @Test func 無音ギャップ入りサイン波はnilを返す() {
        let sampleRate = 44100.0
        let count = Int(sampleRate * 10)
        let gap = Int(sampleRate * 4.5)..<Int(sampleRate * 5.5)
        let samples = (0..<count).map { i in
            gap.contains(i) ? Float(0)
                : Float(0.5 * sin(2 * .pi * 440 * Double(i) / sampleRate))
        }
        #expect(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: sampleRate) == nil)
    }

    @Test func 無音はnilを返す() {
        let samples = [Float](repeating: 0, count: 44100 * 10)
        #expect(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: 44100) == nil)
    }

    @Test func 短すぎる入力はnilを返す() {
        let samples = makeClickTrack(bpm: 120, seconds: 2)
        #expect(TempoEstimator.estimateTempo(monoSamples: samples, sampleRate: 44100) == nil)
    }

    @Test func ファイルからステレオをモノラル化して推定できる() throws {
        let samples = makeClickTrack(bpm: 120, seconds: 20)
        let url = try writeTestWAV(channels: 2, frameCount: AVAudioFrameCount(samples.count)) { data in
            for i in 0..<samples.count {
                data[0][i] = samples[i]
                data[1][i] = samples[i] * 0.5
            }
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let bpm = try #require(try TempoEstimator.estimateTempo(from: url))
        #expect(abs(bpm - 120) < 1.5, "推定: \(bpm)")
    }

    @Test func タグの無いWAVのメタデータは空になる() async throws {
        let url = try writeTestWAV(channels: 1, frameCount: 44100)
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await AudioMetadata.load(from: url)
        #expect(metadata.isEmpty)
        #expect(metadata.bpm == nil)
        #expect(metadata.title == nil)
    }
}
