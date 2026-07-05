import Foundation

/// 再生時間を "m:ss.SSS" 形式で整形する
nonisolated func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00.000" }
    let totalMillis = Int((seconds * 1000).rounded())
    let m = totalMillis / 60000
    let s = (totalMillis / 1000) % 60
    let ms = totalMillis % 1000
    return String(format: "%d:%02d.%03d", m, s, ms)
}
