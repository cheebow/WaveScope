import SwiftUI

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("音声ファイルをドロップするか、開いてください")
                .foregroundStyle(.secondary)
            Button("開く…") {
                model.openPanel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
