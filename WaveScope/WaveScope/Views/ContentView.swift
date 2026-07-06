import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            mainArea
            Divider()
            TransportBar()
        }
        // トランスポートバーの固定幅要素(音量・レベルメーター・ズーム・表示切替など)が
        // 収まる幅を下限にする。これより狭いとテキストが縦折り返しになりバーが崩れる
        .frame(minWidth: 950, minHeight: 320)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url: url)
            return true
        }
        .navigationTitle(model.fileURL?.lastPathComponent ?? "WaveScope")
    }

    @ViewBuilder
    private var mainArea: some View {
        switch model.loadState {
        case .empty:
            EmptyStateView()
        case .loading(let progress):
            VStack(spacing: 12) {
                ProgressView(value: progress)
                    .frame(maxWidth: 280)
                Text("Loading… \(Int(progress * 100))%")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let peaks):
            WaveformView(peaks: peaks)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Couldn't load the file")
                Text("The file may be in an unsupported format or corrupted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                // 生のOSエラーは調査の手がかりとして小さく残す
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("Open Another File…") {
                    model.openPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
