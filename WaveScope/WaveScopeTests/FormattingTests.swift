import Testing
@testable import WaveScope

struct TimeFormattingTests {
    @Test func 基本フォーマット() {
        #expect(formatTime(0) == "0:00.000")
        #expect(formatTime(1.5) == "0:01.500")
        #expect(formatTime(61.234) == "1:01.234")
        #expect(formatTime(600) == "10:00.000")
        #expect(formatTime(3661.5) == "61:01.500")
    }

    @Test func ミリ秒の丸め() {
        #expect(formatTime(0.9995) == "0:01.000")
        #expect(formatTime(0.0004) == "0:00.000")
    }

    @Test func 不正値は0扱い() {
        #expect(formatTime(-1) == "0:00.000")
        #expect(formatTime(.infinity) == "0:00.000")
        #expect(formatTime(.nan) == "0:00.000")
    }
}

struct RulerTests {
    @Test func 目盛り間隔はきりのいい値に切り上げる() {
        #expect(WaveformView.rulerInterval(forDesired: 0.0008) == 0.001)
        #expect(WaveformView.rulerInterval(forDesired: 0.008) == 0.01)
        #expect(WaveformView.rulerInterval(forDesired: 0.9) == 1)
        #expect(WaveformView.rulerInterval(forDesired: 1.0) == 1)
        #expect(WaveformView.rulerInterval(forDesired: 47) == 60)
        #expect(WaveformView.rulerInterval(forDesired: 400) == 600)
        #expect(WaveformView.rulerInterval(forDesired: 99999) == 3600)
    }

    @Test func 秒単位のラベル() {
        #expect(WaveformView.rulerLabel(seconds: 0, interval: 1) == "0:00")
        #expect(WaveformView.rulerLabel(seconds: 7, interval: 1) == "0:07")
        #expect(WaveformView.rulerLabel(seconds: 65, interval: 5) == "1:05")
        #expect(WaveformView.rulerLabel(seconds: 600, interval: 60) == "10:00")
    }

    @Test func 秒未満のラベルは間隔に応じた桁数になる() {
        #expect(WaveformView.rulerLabel(seconds: 4.97, interval: 0.01) == "0:04.97")
        #expect(WaveformView.rulerLabel(seconds: 0.5, interval: 0.1) == "0:00.5")
        #expect(WaveformView.rulerLabel(seconds: 0.123, interval: 0.001) == "0:00.123")
    }
}
