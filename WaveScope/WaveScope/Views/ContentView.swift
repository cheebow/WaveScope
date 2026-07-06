import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            mainArea
            Divider()
            TransportBar()
        }
        .frame(minWidth: 600, minHeight: 320)
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
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Another File…") {
                    model.openPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
