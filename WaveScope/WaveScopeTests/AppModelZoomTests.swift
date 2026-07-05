import Testing
import AVFoundation
@testable import WaveScope

@MainActor
struct AppModelZoomTests {
    /// 10秒 @44.1kHz 相当のピークを持つモデル(fileURL は nil なので高解像度抽出は走らない)
    private func makeModel() -> AppModel {
        let binCount = Int((441000 + 255) / 256)
        let peaks = WaveformPeaks(
            sampleRate: 44100,
            frameCount: 441000,
            samplesPerBin: 256,
            channelMins: [[Float](repeating: -0.5, count: binCount)],
            channelMaxs: [[Float](repeating: 0.5, count: binCount)]
        )
        let model = AppModel()
        model.loadState = .loaded(peaks)
        model.viewWidth = 100
        model.visibleStart = 0
        model.visibleLength = 441000
        return model
    }

    @Test func 中央アンカーのズームイン() {
        let model = makeModel()
        model.zoom(by: 0.5)
        #expect(model.visibleLength == 220500)
        #expect(model.visibleStart == 110250)
    }

    @Test func ズームインの下限は2サンプル毎ピクセル() {
        let model = makeModel()
        model.zoom(by: 0.000001)
        #expect(model.visibleLength == 200)   // 2 samples/px × 100px
        #expect(model.canZoomIn == false)
    }

    @Test func ズームアウトは全体でクランプされる() {
        let model = makeModel()
        model.zoom(by: 0.5)
        model.zoom(by: 100)
        #expect(model.visibleStart == 0)
        #expect(model.visibleLength == 441000)
        #expect(model.isZoomed == false)
    }

    @Test func 左端アンカーではズーム後も先頭が固定される() {
        let model = makeModel()
        model.zoom(by: 0.5, anchorFraction: 0)
        #expect(model.visibleStart == 0)
        #expect(model.visibleLength == 220500)
    }

    @Test func スクロールは端でクランプされる() {
        let model = makeModel()
        model.zoom(by: 0.5)   // 110250..330750
        model.scroll(byPixels: 100000)    // 左方向へ大きく
        #expect(model.visibleStart == 0)
        model.scroll(byPixels: -100000)   // 右方向へ大きく
        #expect(model.visibleStart == 441000 - model.visibleLength)
    }

    @Test func 全体表示ではスクロールしない() {
        let model = makeModel()
        model.scroll(byPixels: -50)
        #expect(model.visibleStart == 0)
    }

    @Test func zoomToFitで全体に戻る() {
        let model = makeModel()
        model.zoom(by: 0.25)
        model.scroll(byPixels: -50)
        model.zoomToFit()
        #expect(model.visibleStart == 0)
        #expect(model.visibleLength == 441000)
    }
}
