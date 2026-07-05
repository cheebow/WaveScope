import SwiftUI

/// 再生レベルメーター。-60〜0dB をチャンネルごとの横バーで表示する。
/// 立ち上がりは即時、下降は一定速度で減衰させて滑らかに見せる。
struct LevelMeterView: View {
    /// チャンネル別ピーク(dB)。空 = 無音。
    let levels: [Float]

    private static let floorDB: Float = -60
    /// 下降の減衰速度(dB/秒)
    private static let releaseRate: Float = 60
    private static let peakHoldDuration: TimeInterval = 1.5

    /// 直近の levels 更新時点の表示値・目標値(減衰アニメーションの基準)
    @State private var baseValues: [Float] = []
    @State private var targetValues: [Float] = []
    @State private var changeDate = Date.distantPast
    @State private var peakHolds: [(value: Float, date: Date)] = []
    @State private var isIdle = true
    @State private var idleTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isIdle)) { timeline in
            let displayed = displayedValues(at: timeline.date)
            Canvas { context, size in
                let rows = max(displayed.count, 2)
                let rowHeight = (size.height - CGFloat(rows - 1) * 2) / CGFloat(rows)
                for row in 0..<rows {
                    let y = CGFloat(row) * (rowHeight + 2)
                    let track = CGRect(x: 0, y: y, width: size.width, height: rowHeight)
                    context.fill(Path(roundedRect: track, cornerRadius: 2),
                                 with: .color(Color(nsColor: .quaternaryLabelColor)))

                    let dB = row < displayed.count ? displayed[row] : Self.floorDB
                    let fraction = normalized(dB)
                    if fraction > 0 {
                        // -12dB までは緑、-6dB までは黄、それ以上は赤
                        let zones: [(from: Float, to: Float, color: Color)] = [
                            (Self.floorDB, -12, .green),
                            (-12, -6, .yellow),
                            (-6, 0, .red),
                        ]
                        for zone in zones {
                            let zoneStart = normalized(zone.from)
                            let zoneEnd = min(normalized(zone.to), fraction)
                            guard zoneEnd > zoneStart else { continue }
                            let rect = CGRect(x: size.width * CGFloat(zoneStart), y: y,
                                              width: size.width * CGFloat(zoneEnd - zoneStart),
                                              height: rowHeight)
                            context.fill(Path(rect), with: .color(zone.color.opacity(0.85)))
                        }
                    }

                    // ピークホールド
                    if row < peakHolds.count, peakHolds[row].value > Self.floorDB,
                       timeline.date.timeIntervalSince(peakHolds[row].date) < Self.peakHoldDuration {
                        let x = size.width * CGFloat(normalized(peakHolds[row].value))
                        context.fill(Path(CGRect(x: x - 1, y: y, width: 1.5, height: rowHeight)),
                                     with: .color(.primary.opacity(0.6)))
                    }
                }
                // -12 / -6 dB の目盛り
                for tick in [-12.0 as Float, -6.0] {
                    let x = size.width * CGFloat(normalized(tick))
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                                 with: .color(Color(nsColor: .separatorColor)))
                }
            }
        }
        .frame(width: 120, height: 14)
        .onChange(of: levels) { _, newLevels in
            applyNewLevels(newLevels)
        }
        .help("再生レベル(ピーク)")
    }

    private func normalized(_ dB: Float) -> Float {
        min(max((dB - Self.floorDB) / -Self.floorDB, 0), 1)
    }

    /// 減衰を織り込んだ現在の表示値(純関数: TimelineView の日時から計算する)
    private func displayedValues(at date: Date) -> [Float] {
        let dt = Float(max(date.timeIntervalSince(changeDate), 0))
        return (0..<targetValues.count).map { i in
            max(targetValues[i], baseValues[i] - Self.releaseRate * dt)
        }
    }

    private func applyNewLevels(_ newLevels: [Float]) {
        let now = Date()
        let current = displayedValues(at: now)
        // 停止(空)のときは行数を保ったまま床値へ減衰させる
        let count = newLevels.isEmpty ? current.count : newLevels.count
        var base: [Float] = []
        var target: [Float] = []
        for i in 0..<count {
            let newValue = i < newLevels.count ? newLevels[i] : Self.floorDB
            let currentValue = i < current.count ? current[i] : Self.floorDB
            target.append(newValue)
            base.append(max(newValue, currentValue))   // 上昇は即時、下降は減衰
        }
        baseValues = base
        targetValues = target
        changeDate = now
        updatePeakHolds(with: target, at: now)

        isIdle = false
        idleTask?.cancel()
        if newLevels.isEmpty {
            // 減衰しきってから描画を止める
            idleTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                isIdle = true
                baseValues = []
                targetValues = []
                peakHolds = []
            }
        }
    }

    private func updatePeakHolds(with newLevels: [Float], at now: Date) {
        var holds = peakHolds
        if holds.count != newLevels.count {
            holds = newLevels.map { ($0, now) }
        } else {
            for i in 0..<holds.count {
                if newLevels[i] >= holds[i].value
                    || now.timeIntervalSince(holds[i].date) > Self.peakHoldDuration {
                    holds[i] = (newLevels[i], now)
                }
            }
        }
        peakHolds = holds
    }
}
