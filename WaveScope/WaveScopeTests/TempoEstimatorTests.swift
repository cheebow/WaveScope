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
