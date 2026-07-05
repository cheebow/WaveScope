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

    private var volumeIcon: String {
        switch model.player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
