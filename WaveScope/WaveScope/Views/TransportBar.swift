import SwiftUI

struct TransportBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            Button {
                model.player.togglePlayPause()
            } label: {
                Image(systemName: model.player.state == .playing ? "pause.fill" : "play.fill")
                    .frame(width: 20)
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!model.player.isLoaded)
            .help(model.player.state == .playing ? "一時停止" : "再生")

            Button {
                model.player.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(!model.player.isLoaded)
            .help("停止")

            Button("選択範囲を再生") {
                model.playSelection()
            }
            .disabled(model.selection == nil)

            TimelineView(.animation(minimumInterval: 0.05, paused: model.player.state != .playing)) { _ in
                Text("\(formatTime(model.player.currentTime)) / \(formatTime(model.player.duration))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // 幅が足りないときは BPM ラベル側を先に詰めて、時刻表示を守る
            .layoutPriority(1)

            bpmLabel

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: volumeIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Slider(value: Binding(
                    get: { model.player.volume },
                    set: { model.player.volume = $0 }
                ), in: 0...1)
                .frame(width: 80)
                .controlSize(.small)
            }
            .help("音量")

            LevelMeterView(levels: model.player.meterLevels)

            HStack(spacing: 4) {
                Button {
                    model.zoom(by: 2)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(!model.isZoomed)
                .help("ズームアウト (⌘−)")

                Button {
                    model.zoom(by: 0.5)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(!model.canZoomIn)
                .help("ズームイン (⌘+)")

                Button {
                    model.zoomToFit()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .disabled(!model.isZoomed)
                .help("全体を表示 (⌘0)")
            }

            Picker("表示", selection: $model.displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled((model.loadedPeaks?.channelCount ?? 0) < 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var bpmLabel: some View {
        switch model.bpmState {
        case .none:
            EmptyView()
        case .analyzing:
            Text("BPM 解析中…")
                .font(.body.monospacedDigit())
                .foregroundStyle(.tertiary)
        case .detected(let bpm, let fromMetadata):
            // 解析による推定は ±1 程度の精度なので整数に丸める(タグの値はそのまま)
            Text("BPM \((fromMetadata ? bpm : bpm.rounded()).formatted(.number.precision(.fractionLength(0...1))))")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .help(fromMetadata
                      ? "ファイルの BPM タグの値"
                      : "音声解析による推定値(倍/半分に取り違える場合があります)")
        }
    }

    private var volumeIcon: String {
        switch model.player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
