import Foundation
import AVFoundation

/// テスト用 WAV(16bit LinearPCM)を一時ディレクトリに書いて URL を返す。
/// fill にはゼロ初期化済みのチャンネル別サンプルバッファが渡る。
/// 呼び出し側で削除すること: `defer { try? FileManager.default.removeItem(at: url) }`
func writeTestWAV(
    channels: AVAudioChannelCount,
    sampleRate: Double = 44100,
    frameCount: AVAudioFrameCount,
    fill: (UnsafePointer<UnsafeMutablePointer<Float>>) -> Void = { _ in }
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wavescope-test-\(UUID().uuidString).wav")
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]
    // AVAudioFile はスコープを抜けるときにヘッダを確定する(CLAUDE.md の既知の落とし穴)
    func write() throws {
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: channels, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        for ch in 0..<Int(channels) {
            buffer.floatChannelData![ch].update(repeating: 0, count: Int(frameCount))
        }
        fill(buffer.floatChannelData!)
        buffer.frameLength = frameCount
        try file.write(from: buffer)
    }
    try write()
    return url
}
