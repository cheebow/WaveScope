import Foundation
import AVFoundation
import Accelerate
import Observation

/// AVAudioEngine + AVAudioPlayerNode による再生制御。
/// play(from:to:) の単一プリミティブで全体再生・位置指定再生・範囲再生を実現する。
@Observable
final class PlayerController {
    enum PlaybackState {
        case stopped
        case playing
        case paused
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var file: AVAudioFile?

    private(set) var state: PlaybackState = .stopped
    /// 現在のセグメントが「選択範囲の再生」かどうか(選択変更のライブ追従に使う)
    private(set) var isSelectionSegment = false
    /// 再生中のチャンネル別ピークレベル(dB)。無音/停止中は空。
    private(set) var meterLevels: [Float] = []
    private var segmentStartFrame: AVAudioFramePosition = 0
    private var segmentEndFrame: AVAudioFramePosition = 0
    private var pausedFrame: AVAudioFramePosition = 0
    /// stop()/再スケジュールでも完了コールバックが発火するため、世代一致時のみ状態遷移する
    private var generation = 0
    private var tapInstalled = false

    /// 再生音量(0.0〜1.0)。起動間で保持する。
    /// レベルメーターのタップは playerNode 上にあるため、音量を下げてもメーターはファイル本来のレベルを示す。
    var volume: Float {
        didSet {
            playerNode.volume = volume
            UserDefaults.standard.set(volume, forKey: Self.volumeDefaultsKey)
        }
    }

    private static let volumeDefaultsKey = "playerVolume"

    init() {
        // @Observable の init 内代入は didSet を通らないため、playerNode へは明示的に反映する
        let stored = UserDefaults.standard.object(forKey: Self.volumeDefaultsKey) as? Float
        volume = min(max(stored ?? 1.0, 0), 1)
        engine.attach(playerNode)
        playerNode.volume = volume
        // 出力デバイスの変更(ヘッドホン抜き差し等)でエンジンが停止したとき、
        // state が .playing のまま固まらないように監視する
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(engineConfigurationDidChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    /// AVAudioEngineConfigurationChange はバックグラウンドスレッドから届くため、
    /// nonisolated で受けて MainActor へ移してから状態を触る
    @objc nonisolated private func engineConfigurationDidChange(_ notification: Notification) {
        Task { @MainActor in
            self.handleEngineConfigurationChange()
        }
    }

    /// デバイス変更等でエンジンが停止したら、現在位置を保持して一時停止扱いにする。
    /// スケジュール済みセグメントは失効しているので、再開は togglePlayPause の
    /// 再スケジュール経路(engine が止まっている場合)を通る。
    private func handleEngineConfigurationChange() {
        // この通知はエンジン起動時などにも発火する。デバイス変更で実際に
        // エンジンが停止した場合(再生中なのに動いていない)だけ処理する
        guard state == .playing, !engine.isRunning else { return }
        let position = currentFrame
        generation += 1   // playerNode.stop() の完了コールバックが .stopped に遷移させるのを防ぐ
        playerNode.stop()
        pausedFrame = position
        state = .paused
        meterLevels = []
    }

    var totalFrames: AVAudioFramePosition { file?.length ?? 0 }
    var sampleRate: Double { file?.processingFormat.sampleRate ?? 44100 }
    var duration: TimeInterval { Double(totalFrames) / sampleRate }
    var currentTime: TimeInterval { Double(currentFrame) / sampleRate }
    var isLoaded: Bool { file != nil }

    var currentFrame: AVAudioFramePosition {
        switch state {
        case .stopped:
            return segmentStartFrame
        case .paused:
            return pausedFrame
        case .playing:
            guard let nodeTime = playerNode.lastRenderTime,
                  let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
                return segmentStartFrame
            }
            return min(segmentStartFrame + playerTime.sampleTime, segmentEndFrame)
        }
    }

    func load(url: URL) throws {
        stop()
        let newFile = try AVAudioFile(forReading: url)
        file = newFile
        segmentStartFrame = 0
        segmentEndFrame = newFile.length
        // サンプルレートの異なるファイルに備え、毎回そのファイルのフォーマットで再接続する
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: newFile.processingFormat)
        engine.prepare()
        installMeterTap()
    }

    func unload() {
        stop()
        removeMeterTap()
        engine.stop()
        file = nil
        segmentStartFrame = 0
        segmentEndFrame = 0
    }

    // MARK: - レベルメーター

    private func installMeterTap() {
        removeMeterTap()
        playerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { return }
            var levels: [Float] = []
            for ch in 0..<Int(buffer.format.channelCount) {
                let peak = vDSP.maximumMagnitude(UnsafeBufferPointer(start: data[ch], count: n))
                levels.append(20 * log10(max(peak, 1e-5)))
            }
            Task { @MainActor [weak self] in
                guard let self, self.state == .playing else { return }
                self.meterLevels = levels
            }
        }
        tapInstalled = true
    }

    private func removeMeterTap() {
        if tapInstalled {
            playerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        meterLevels = []
    }

    func play(from start: AVAudioFramePosition, to end: AVAudioFramePosition,
              asSelection: Bool = false) {
        guard let file else { return }
        let clampedStart = max(0, min(start, file.length))
        let clampedEnd = max(clampedStart, min(end, file.length))
        let frameCount = AVAudioFrameCount(clampedEnd - clampedStart)
        guard frameCount > 0 else { return }

        playerNode.stop()
        generation += 1
        let gen = generation
        isSelectionSegment = asSelection
        segmentStartFrame = clampedStart
        segmentEndFrame = clampedEnd

        playerNode.scheduleSegment(
            file,
            startingFrame: clampedStart,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == gen else { return }
                self.state = .stopped
                self.meterLevels = []
            }
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                state = .stopped
                return
            }
        }
        playerNode.play()
        state = .playing
    }

    func togglePlayPause() {
        switch state {
        case .playing:
            pausedFrame = currentFrame
            playerNode.pause()
            state = .paused
            meterLevels = []
        case .paused:
            if engine.isRunning {
                playerNode.play()
                state = .playing
            } else {
                // エンジンが止まっている(デバイス変更等)場合、スケジュール済み
                // セグメントは失効しているので、保持した位置から再スケジュールする
                play(from: pausedFrame, to: segmentEndFrame, asSelection: isSelectionSegment)
            }
        case .stopped:
            play(from: 0, to: totalFrames)
        }
    }

    func stop() {
        generation += 1
        playerNode.stop()
        state = .stopped
        meterLevels = []
    }
}
