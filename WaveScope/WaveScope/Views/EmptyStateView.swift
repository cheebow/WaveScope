import SwiftUI

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop an audio file here, or open one")
                .foregroundStyle(.secondary)
            Button("Open…") {
                model.openPanel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
