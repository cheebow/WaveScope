#!/bin/bash
# WaveScope 用テスト音源を生成する。
#   ./make-test-audio.sh          # 10秒のステレオWAV + 各フォーマット変換 + 音声サンプル
#   ./make-test-audio.sh --long   # 1時間のWAVも追加生成(チャンク読み・進捗UIの確認用)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../TestAudio"
mkdir -p "$OUT_DIR"

gen_wav() { # $1=出力パス $2=秒数
  swift - "$1" "$2" <<'EOF'
import AVFoundation

let path = CommandLine.arguments[1]
let seconds = Double(CommandLine.arguments[2])!
let sampleRate = 44100.0
let url = URL(fileURLWithPath: path)

let settings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: 2,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false,
]
// AVAudioFile はオブジェクト解放時にヘッダ(フレーム数)を確定するため、
// 書き込みは関数スコープに閉じ込めて確実に解放させる
func writeTone() throws {
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: 2, interleaved: false)!
    let chunkFrames: AVAudioFrameCount = 44100
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)!

    let totalFrames = Int(seconds * sampleRate)
    // 中央に1秒の無音ギャップ(範囲再生・シークの聴覚/視覚ランドマーク)
    let gapStart = totalFrames / 2 - Int(sampleRate) / 2
    let gapEnd = gapStart + Int(sampleRate)

    var frame = 0
    while frame < totalFrames {
        let n = min(Int(chunkFrames), totalFrames - frame)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for i in 0..<n {
            let t = Double(frame + i) / sampleRate
            let silent = (frame + i) >= gapStart && (frame + i) < gapEnd
            left[i] = silent ? 0 : Float(0.5 * sin(2 * .pi * 440 * t))   // L: 440 Hz
            right[i] = silent ? 0 : Float(0.5 * sin(2 * .pi * 880 * t))  // R: 880 Hz
        }
        buffer.frameLength = AVAudioFrameCount(n)
        try file.write(from: buffer)
        frame += n
    }
}
try writeTone()
print("wrote \(path) (\(seconds)s, stereo L=440Hz R=880Hz, 1s gap in middle)")
EOF
}

gen_wav "$OUT_DIR/test.wav" 10

afconvert -f AIFF -d BEI16 "$OUT_DIR/test.wav" "$OUT_DIR/test.aiff"
afconvert -f m4af -d aac   "$OUT_DIR/test.wav" "$OUT_DIR/test.m4a"
afconvert -f caff -d LEI16 "$OUT_DIR/test.wav" "$OUT_DIR/test.caf"
afconvert -f flac -d flac  "$OUT_DIR/test.wav" "$OUT_DIR/test.flac"

say -o "$OUT_DIR/voice.aiff" "This is a WaveScope test file."

if [[ "${1:-}" == "--long" ]]; then
  gen_wav "$OUT_DIR/long.wav" 3600
fi

ls -lh "$OUT_DIR"
