import Testing
import AVFoundation
@testable import WaveScope

struct WaveformPeaksTests {
    /// 4 bin × 2ch のテストデータ(samplesPerBin: 256、総フレーム 1024)
    private func makePeaks() -> WaveformPeaks {
        WaveformPeaks(
            sampleRate: 44100,
            frameCount: 1024,
            samplesPerBin: 256,
            channelMins: [
                [-0.5, -0.1, 0.0, -1.0],   // ch0
                [-0.2, -0.8, 0.0, -0.3],   // ch1
            ],
            channelMaxs: [
                [0.5, 0.1, 0.0, 1.0],
                [0.2, 0.8, 0.0, 0.3],
            ]
        )
    }

    @Test func 全範囲を等幅で再ビニングするとbinがそのまま返る() {
        let peaks = makePeaks()
        let (mins, maxs) = peaks.pixelPeaks(width: 4, channel: 0, startFrame: 0, endFrame: 1024)
        #expect(mins == [-0.5, -0.1, 0.0, -1.0])
        #expect(maxs == [0.5, 0.1, 0.0, 1.0])
    }

    @Test func 幅を半分にすると隣接binが統合される() {
        let peaks = makePeaks()
        let (mins, maxs) = peaks.pixelPeaks(width: 2, channel: 0, startFrame: 0, endFrame: 1024)
        #expect(mins == [-0.5, -1.0])
        #expect(maxs == [0.5, 1.0])
    }

    @Test func channelがnilなら全チャンネル合成になる() {
        let peaks = makePeaks()
        let (mins, maxs) = peaks.pixelPeaks(width: 4, channel: nil, startFrame: 0, endFrame: 1024)
        #expect(mins == [-0.5, -0.8, 0.0, -1.0])
        #expect(maxs == [0.5, 0.8, 0.0, 1.0])
    }

    @Test func フレーム範囲を指定すると該当binだけが使われる() {
        let peaks = makePeaks()
        let (mins, maxs) = peaks.pixelPeaks(width: 2, channel: 0, startFrame: 512, endFrame: 1024)
        #expect(mins == [0.0, -1.0])
        #expect(maxs == [0.0, 1.0])
    }

    @Test func binより広い幅では同じbinが繰り返される() {
        let peaks = makePeaks()
        let (mins, maxs) = peaks.pixelPeaks(width: 8, channel: 0, startFrame: 0, endFrame: 1024)
        #expect(mins.count == 8)
        #expect(mins[0] == -0.5 && mins[1] == -0.5)
        #expect(maxs[6] == 1.0 && maxs[7] == 1.0)
    }

    @Test func 不正な引数では空を返す() {
        let peaks = makePeaks()
        #expect(peaks.pixelPeaks(width: 0, channel: nil, startFrame: 0, endFrame: 1024).mins.isEmpty)
        #expect(peaks.pixelPeaks(width: 4, channel: nil, startFrame: 500, endFrame: 500).mins.isEmpty)
    }

    @Test func columnPeakは1列ぶんのピークを返す() {
        let peaks = makePeaks()
        let column = peaks.columnPeak(x: 3, width: 4, channel: 0, startFrame: 0, endFrame: 1024)
        #expect(column?.min == -1.0)
        #expect(column?.max == 1.0)
        #expect(peaks.columnPeak(x: 4, width: 4, channel: 0, startFrame: 0, endFrame: 1024) == nil)
    }

    @Test func 存在しないチャンネル指定は合成にフォールバックする() {
        let peaks = makePeaks()
        let (mins, _) = peaks.pixelPeaks(width: 4, channel: 5, startFrame: 0, endFrame: 1024)
        #expect(mins == [-0.5, -0.8, 0.0, -1.0])
    }
}

struct HighResPixelPeaksTests {
    private func makeHiRes() -> HighResPixelPeaks {
        HighResPixelPeaks(
            startFrame: 100,
            endFrame: 500,
            width: 2,
            channelMins: [[-0.5, -0.1], [-0.2, -0.9]],
            channelMaxs: [[0.5, 0.1], [0.2, 0.9]]
        )
    }

    @Test func coversは範囲内包を判定する() {
        let hiRes = makeHiRes()
        #expect(hiRes.covers(startFrame: 100, endFrame: 500))
        #expect(hiRes.covers(startFrame: 200, endFrame: 300))
        #expect(!hiRes.covers(startFrame: 99, endFrame: 500))
        #expect(!hiRes.covers(startFrame: 100, endFrame: 501))
        #expect(!hiRes.covers(startFrame: 300, endFrame: 300))
    }

    @Test func 同一範囲の再ビニングは元の列をそのまま返す() throws {
        let hiRes = makeHiRes()
        let rebinned = try #require(hiRes.rebinnedPeaks(startFrame: 100, endFrame: 500,
                                                        width: 2, channel: 1))
        #expect(rebinned.mins == [-0.2, -0.9])
        #expect(rebinned.maxs == [0.2, 0.9])
        let merged = try #require(hiRes.rebinnedPeaks(startFrame: 100, endFrame: 500,
                                                      width: 2, channel: nil))
        #expect(merged.mins == [-0.5, -0.9])
        #expect(merged.maxs == [0.5, 0.9])
    }

    @Test func 部分範囲への再ビニングは該当列だけを使う() throws {
        // 列0 = フレーム100..<300、列1 = 300..<500
        let hiRes = makeHiRes()
        let front = try #require(hiRes.rebinnedPeaks(startFrame: 100, endFrame: 300,
                                                     width: 2, channel: 0))
        #expect(front.mins == [-0.5, -0.5])   // ズームインでは同じ列が引き伸ばされる
        let back = try #require(hiRes.rebinnedPeaks(startFrame: 300, endFrame: 500,
                                                    width: 1, channel: 0))
        #expect(back.mins == [-0.1])
        #expect(back.maxs == [0.1])
    }

    @Test func カバー外の再ビニングはnilを返す() {
        let hiRes = makeHiRes()
        #expect(hiRes.rebinnedPeaks(startFrame: 0, endFrame: 500, width: 2, channel: nil) == nil)
        #expect(hiRes.rebinnedPeaks(startFrame: 400, endFrame: 600, width: 2, channel: nil) == nil)
    }

    @Test func columnPeakはカバー範囲内の1列を返す() {
        let hiRes = makeHiRes()
        // 表示範囲 300..<500(列1相当)を4列で見たときの先頭列
        let column = hiRes.columnPeak(x: 0, width: 4, channel: 1, startFrame: 300, endFrame: 500)
        #expect(column?.min == -0.9)
        #expect(column?.max == 0.9)
        #expect(hiRes.columnPeak(x: 0, width: 4, channel: 1, startFrame: 0, endFrame: 200) == nil)
    }
}
