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
            .help(model.player.state == .playing ? "Pause" : "Play")

            Button {
                model.player.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(!model.player.isLoaded)
            .help("Stop")

            Button("Play Selection") {
                model.playSelection()
            }
            .disabled(model.selection == nil)

            TimelineView(.animation(minimumInterval: 0.05, paused: model.player.state != .playing)) { _ in
                Text(verbatim: "\(formatTime(model.player.currentTime)) / \(formatTime(model.player.duration))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)   // 幅不足時に縦折り返しでバーの高さが膨らむのを防ぐ
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
            .help("Volume")

            LevelMeterView(levels: model.player.meterLevels)

            HStack(spacing: 4) {
                Button {
                    model.zoom(by: 2)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(!model.isZoomed)
                .help("Zoom Out (⌘−)")

                Button {
                    model.zoom(by: 0.5)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(!model.canZoomIn)
                .help("Zoom In (⌘+)")

                Button {
                    model.zoomToFit()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .disabled(!model.isZoomed)
                .help("Zoom to Fit (⌘0)")
            }

            Picker("Display", selection: $model.displayMode) {
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
            Text("Analyzing BPM…")
                .font(.body.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        case .detected(let bpm, let fromMetadata):
            // 解析による推定は ±1 程度の精度なので整数に丸める(タグの値はそのまま)
            Text(verbatim: "BPM \((fromMetadata ? bpm : bpm.rounded()).formatted(.number.precision(.fractionLength(0...1))))")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)   // 幅不足時に縦折り返しでバーの高さが膨らむのを防ぐ
                .help(fromMetadata
                      ? "Value from the file's BPM tag"
                      : "Estimated by audio analysis (may be double or half the actual tempo)")
                .contextMenu {
                    Button("Copy BPM") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(Self.bpmCopyText(bpm: bpm, fromMetadata: fromMetadata),
                                             forType: .string)
                    }
                }
        }
    }

    /// コピー用の BPM 文字列。表示と同じ丸めで、スペースなしの「BPM124」形式
    static func bpmCopyText(bpm: Double, fromMetadata: Bool) -> String {
        "BPM" + (fromMetadata ? bpm : bpm.rounded()).formatted(.number.precision(.fractionLength(0...1)))
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
