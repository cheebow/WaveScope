import SwiftUI

/// ファイル情報シート(⌘I)。タグのメタデータとファイルの技術情報を表示する。
struct InfoSheetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Metadata") {
                    if let metadata = model.metadata, !metadata.isEmpty {
                        if let title = metadata.title { row("Title", title) }
                        if let artist = metadata.artist { row("Artist", artist) }
                        if let album = metadata.album { row("Album", album) }
                        if let genre = metadata.genre { row("Genre", genre) }
                        if let year = metadata.year { row("Year", year) }
                        if let bpm = metadata.bpm {
                            row("BPM Tag", bpm.formatted(.number.precision(.fractionLength(0...1))))
                        }
                    } else {
                        Text("No metadata")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("File") {
                    if let url = model.fileURL {
                        row("Name", url.lastPathComponent)
                        row("Format", url.pathExtension.uppercased())
                        if let size = fileSize(of: url) {
                            row("File Size", size)
                        }
                    }
                    if let peaks = model.loadedPeaks {
                        row("Duration", formatTime(Double(peaks.frameCount) / peaks.sampleRate))
                        row("Sample Rate", "\(Int(peaks.sampleRate)) Hz")
                        row("Channels", String(peaks.channelCount))
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 440, height: 640)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(label) {
            Text(verbatim: value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }

    private func fileSize(of url: URL) -> String? {
        guard let bytes = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64 else { return nil }
        return bytes.formatted(.byteCount(style: .file))
    }
}
