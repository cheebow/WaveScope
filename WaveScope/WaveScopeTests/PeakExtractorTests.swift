import Testing
import AVFoundation
@testable import WaveScope

struct PeakExtractorTests {
    /// 既知のサンプル値を持つステレオWAVを一時ディレクトリに作る。
    /// 1000フレーム(256の倍数でない → 最終binが端数になる):
    ///   L: 先頭512フレームが +0.5、残りは 0
    ///   R: 全フレーム -0.25
    private func makeTestWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wavescope-test-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        // AVAudioFile はスコープを抜けるときにヘッダを確定する
        func write() throws {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100,
                                       channels: 2, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1000)!
            for i in 0..<1000 {
                buffer.floatChannelData![0][i] = i < 512 ? 0.5 : 0
                buffer.floatChannelData![1][i] = -0.25
            }
            buffer.frameLength = 1000
            try file.write(from: buffer)
        }
        try write()
        return url
    }

    @Test func extractPeaksがbin単位のminmaxを正しく計算する() throws {
        let url = try makeTestWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        let peaks = try PeakExtractor.extractPeaks(from: url, samplesPerBin: 256)
        #expect(peaks.channelCount == 2)
        #expect(peaks.frameCount == 1000)
        #expect(peaks.sampleRate == 44100)
        #expect(peaks.channelMins[0].count == 4)   // ceil(1000/256)

        let tolerance: Float = 0.001
        // L: bin0,1 = +0.5 一定 / bin2(512...767) = 0 / bin3(端数232フレーム) = 0
        #expect(abs(peaks.channelMins[0][0] - 0.5) < tolerance)
        #expect(abs(peaks.channelMaxs[0][1] - 0.5) < tolerance)
        #expect(abs(peaks.channelMins[0][2]) < tolerance)
        #expect(abs(peaks.channelMaxs[0][3]) < tolerance)
        // R: 全bin -0.25 一定
        for b in 0..<4 {
            #expect(abs(peaks.channelMins[1][b] + 0.25) < tolerance)
            #expect(abs(peaks.channelMaxs[1][b] + 0.25) < tolerance)
        }
    }

    @Test func extractPeaksは進捗を単調増加で報告する() throws {
        let url = try makeTestWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        let reported = Mutex<[Double]>([])
        _ = try PeakExtractor.extractPeaks(from: url, samplesPerBin: 256) { p in
            reported.withLock { $0.append(p) }
        }
        let values = reported.withLock { $0 }
        #expect(!values.isEmpty)
        #expect(values == values.sorted())
        #expect(abs(values.last! - 1.0) < 0.0001)
    }

    @Test func extractPixelPeaksが範囲をピクセル列に割り当てる() throws {
        let url = try makeTestWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        // 全1000フレームを4列に: 列0,1 = L 0.5 / 列2 = 境界(0.5と0が混在) / 列3 = 0
        let hiRes = try PeakExtractor.extractPixelPeaks(from: url, startFrame: 0, endFrame: 1000, width: 4)
        #expect(hiRes.matches(startFrame: 0, endFrame: 1000, width: 4))
        #expect(hiRes.channelMins.count == 2)

        let tolerance: Float = 0.001
        #expect(abs(hiRes.channelMaxs[0][0] - 0.5) < tolerance)
        #expect(abs(hiRes.channelMins[0][1] - 0.5) < tolerance)
        #expect(abs(hiRes.channelMins[0][2]) < tolerance)          // min は 0(後半)
        #expect(abs(hiRes.channelMaxs[0][2] - 0.5) < tolerance)    // max は 0.5(前半)
        #expect(abs(hiRes.channelMaxs[0][3]) < tolerance)
        #expect(abs(hiRes.channelMins[1][0] + 0.25) < tolerance)   // R 全域 -0.25
    }

    @Test func extractPixelPeaksは範囲外指定をクランプする() throws {
        let url = try makeTestWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        let hiRes = try PeakExtractor.extractPixelPeaks(from: url, startFrame: 500, endFrame: 99999, width: 2)
        #expect(hiRes.startFrame == 500)
        #expect(hiRes.endFrame == 1000)
    }

    @Test func 空ファイル相当はエラーになる() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wavescope-missing-\(UUID().uuidString).wav")
        #expect(throws: (any Error).self) {
            _ = try PeakExtractor.extractPeaks(from: url)
        }
    }
}

/// テスト用の簡易ロック(進捗コールバックが同期的に呼ばれることの確認用)
final class Mutex<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
