import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

enum DisplayMode: String, CaseIterable, Identifiable {
    case mono
    case stereo

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mono: String(localized: "Mono")
        case .stereo: String(localized: "Stereo")
        }
    }
}

@Observable
final class AppModel {
    static let shared = AppModel()

    enum LoadState {
        case empty
        case loading(Double)
        case loaded(WaveformPeaks)
        case failed(String)
    }

    enum BPMState: Equatable {
        case none
        case analyzing
        /// fromMetadata: true = ファイルの BPM タグの値 / false = 音声解析による推定値
        case detected(bpm: Double, fromMetadata: Bool)
    }

    var loadState: LoadState = .empty
    var fileURL: URL?
    var displayMode: DisplayMode = .mono
    var selection: ClosedRange<AVAudioFramePosition>?
    var bpmState: BPMState = .none
    private var bpmTask: Task<Void, Never>?
    let player = PlayerController()

    // 表示範囲(ズーム/スクロール)
    var visibleStart: AVAudioFramePosition = 0
    var visibleLength: AVAudioFramePosition = 0
    /// WaveformView が現在の描画幅を報告する(ズーム下限と高解像度抽出に使う)
    var viewWidth: CGFloat = 0 {
        didSet { if viewWidth != oldValue { visibleRangeChanged() } }
    }
    var hiResPeaks: HighResPixelPeaks?
    private var hiResTask: Task<Void, Never>?

    private var loadTask: Task<Void, Never>?
    /// open() ごとに増える世代。キャンセルを観測する前に発行済みの古いコールバックを弾く
    private var loadGeneration = 0
    private var securityScopedURL: URL?
    private var hasSecurityScope = false

    /// これ以上ズームインしない下限(1ピクセルあたりのサンプル数)
    private static let minSamplesPerPixel = 2.0

    var loadedPeaks: WaveformPeaks? {
        if case .loaded(let peaks) = loadState { return peaks }
        return nil
    }

    var visibleEnd: AVAudioFramePosition { visibleStart + visibleLength }
    var isZoomed: Bool {
        guard let peaks = loadedPeaks else { return false }
        return visibleLength < peaks.frameCount
    }
    var canZoomIn: Bool {
        viewWidth > 0 && Double(visibleLength) / Double(viewWidth) > Self.minSamplesPerPixel
    }

    // MARK: - ズーム/スクロール

    func zoomToFit() {
        guard let peaks = loadedPeaks else { return }
        visibleStart = 0
        visibleLength = peaks.frameCount
        visibleRangeChanged()
    }

    /// factor < 1 でズームイン、> 1 でズームアウト。anchorFraction は表示範囲内の固定点(0〜1)。
    func zoom(by factor: Double, anchorFraction: Double = 0.5) {
        guard let peaks = loadedPeaks, visibleLength > 0 else { return }
        let anchorFrame = Double(visibleStart) + anchorFraction * Double(visibleLength)
        var newLength = Double(visibleLength) * factor
        let minLength = max(Self.minSamplesPerPixel * Double(max(viewWidth, 1)), 16)
        newLength = min(max(newLength, minLength), Double(peaks.frameCount))
        visibleStart = AVAudioFramePosition(anchorFrame - anchorFraction * newLength)
        visibleLength = AVAudioFramePosition(newLength)
        clampVisible()
        visibleRangeChanged()
    }

    /// width は呼び出し側の実際の描画幅(キャッシュの viewWidth はリサイズ中に古くなり得る)
    func scroll(byPixels dx: CGFloat, width: CGFloat) {
        guard loadedPeaks != nil, width > 0, isZoomed else { return }
        let framesPerPixel = Double(visibleLength) / Double(width)
        visibleStart -= AVAudioFramePosition(Double(dx) * framesPerPixel)
        clampVisible()
        visibleRangeChanged()
    }

    /// 再生ヘッドが表示範囲外に出たらページ送りする(再生中の追従)
    func followPlayheadIfNeeded() {
        guard isZoomed, player.state == .playing else { return }
        let frame = player.currentFrame
        if frame > visibleEnd || frame < visibleStart {
            visibleStart = frame
            clampVisible()
            visibleRangeChanged()
        }
    }

    private func clampVisible() {
        guard let peaks = loadedPeaks else { return }
        visibleLength = min(max(visibleLength, 16), peaks.frameCount)
        visibleStart = min(max(visibleStart, 0), peaks.frameCount - visibleLength)
    }

    // MARK: - バックグラウンドジョブ共通

    /// ブロッキング処理を Task.detached に載せ、待機側タスクのキャンセルを detached へ転送する。
    /// 転送を忘れると打ち切ったはずの処理が最後まで走るため、loadTask / hiResTask / bpmTask は
    /// 必ずこれを使うこと。
    private func runDetachedCancellable<T: Sendable>(
        priority: TaskPriority,
        _ work: @escaping @Sendable () throws -> T
    ) async -> Result<T, any Error> {
        let detached = Task.detached(priority: priority) { try work() }
        return await withTaskCancellationHandler {
            await detached.result
        } onCancel: {
            detached.cancel()
        }
    }

    // MARK: - 高解像度ピーク(キャッシュ解像度を超えるズーム時)

    private func visibleRangeChanged() {
        guard let peaks = loadedPeaks, let url = fileURL, viewWidth > 0 else { return }
        let width = Int(viewWidth)
        let samplesPerPixel = Double(visibleLength) / Double(viewWidth)
        hiResTask?.cancel()
        if samplesPerPixel >= Double(peaks.samplesPerBin) {
            hiResPeaks = nil
            return
        }
        let start = visibleStart
        let end = visibleEnd
        hiResTask = Task { [weak self] in
            // スクロール/ズーム操作の連打をまとめる
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, !Task.isCancelled else { return }
            let result = try? await self.runDetachedCancellable(priority: .userInitiated) {
                try PeakExtractor.extractPixelPeaks(from: url, startFrame: start, endFrame: end, width: width)
            }.get()
            guard let result, !Task.isCancelled else { return }
            // 抽出中にさらに動いていたら破棄(matches で描画側も守られるが無駄な更新を避ける)
            guard result.matches(startFrame: self.visibleStart, endFrame: self.visibleEnd, width: Int(self.viewWidth)) else { return }
            self.hiResPeaks = result
        }
    }

    // MARK: - カーソル位置のピーク

    /// 表示中データ(高解像度があればそれ)から1ピクセル列のピークdBを返す。無音は nil。
    /// width はビューの実際の描画幅(キャッシュではなく呼び出し側の GeometryReader の値)を渡す。
    func peakDB(atColumn x: Int, channel: Int?, width: Int) -> Float? {
        guard let peaks = loadedPeaks, width > 0 else { return nil }
        let peak: Float
        if let hiRes = hiResPeaks, hiRes.matches(startFrame: visibleStart, endFrame: visibleEnd, width: width),
           (0..<width).contains(x) {
            let (mins, maxs) = hiRes.pixelPeaks(channel: channel)
            peak = max(abs(mins[x]), abs(maxs[x]))
        } else if let column = peaks.columnPeak(x: x, width: width, channel: channel,
                                                startFrame: visibleStart, endFrame: visibleEnd) {
            peak = max(abs(column.min), abs(column.max))
        } else {
            return nil
        }
        guard peak > 0 else { return nil }
        return 20 * log10(peak)
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        loadTask?.cancel()
        // 前のファイルの高解像度抽出が遅れて完了し、フレーム数が同じ新ファイルの
        // matches() を通過して古い波形を表示してしまうのを防ぐ
        hiResTask?.cancel()
        hiResPeaks = nil
        bpmTask?.cancel()
        player.unload()
        selection = nil
        loadGeneration += 1
        let generation = loadGeneration

        // 前のファイルのセキュリティスコープを解放し、新しいファイルのスコープを保持する
        if hasSecurityScope {
            securityScopedURL?.stopAccessingSecurityScopedResource()
        }
        hasSecurityScope = url.startAccessingSecurityScopedResource()
        securityScopedURL = url

        fileURL = url
        loadState = .loading(0)
        bpmState = .analyzing
        startBPMAnalysis(url: url, generation: generation)

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 再生はピーク抽出と独立なので、スキャン完了を待たずに再生可能にする
                try self.player.load(url: url)
                let peaks = try await self.runDetachedCancellable(priority: .userInitiated) {
                    try PeakExtractor.extractPeaks(from: url) { p in
                        Task { @MainActor in
                            // 世代チェック: キャンセル済みの前ロードから遅れて届いた進捗を捨てる
                            guard self.loadGeneration == generation,
                                  case .loading = self.loadState else { return }
                            self.loadState = .loading(p)
                        }
                    }
                }.get()
                guard !Task.isCancelled, self.loadGeneration == generation else { return }
                if peaks.channelCount < 2 {
                    self.displayMode = .mono
                }
                self.loadState = .loaded(peaks)
                self.hiResPeaks = nil
                self.visibleStart = 0
                self.visibleLength = peaks.frameCount
                // 初期表示が高解像度対象のズーム率でも発火するように明示的に通知する
                // (viewWidth の didSet は同値の再代入では発火しない)
                self.visibleRangeChanged()
            } catch is CancellationError {
                // 別ファイルを開いた等。何もしない
            } catch {
                guard !Task.isCancelled, self.loadGeneration == generation else { return }
                self.player.unload()
                // 読み込めなかったファイルの BPM をエラー表示の横に出さない
                self.bpmTask?.cancel()
                self.bpmState = .none
                self.loadState = .failed(error.localizedDescription)
            }
        }
    }

    /// BPM の取得。メタデータのタグを優先し、無ければ音声解析で推定する。
    /// ピーク抽出とは独立に走り、失敗しても loadState には影響しない。
    private func startBPMAnalysis(url: URL, generation: Int) {
        bpmTask = Task { [weak self] in
            let tagged = try? await TempoEstimator.metadataBPM(from: url)
            guard let self, !Task.isCancelled, self.loadGeneration == generation else { return }
            if let tagged {
                self.bpmState = .detected(bpm: tagged, fromMetadata: true)
                return
            }
            let estimated = await self.runDetachedCancellable(priority: .utility) {
                try TempoEstimator.estimateTempo(from: url)
            }
            guard !Task.isCancelled, self.loadGeneration == generation else { return }
            // success(nil) は「解析できたがビートなし」、failure は読み込みエラー。どちらも非表示
            if case .success(let bpm?) = estimated {
                self.bpmState = .detected(bpm: bpm, fromMetadata: false)
            } else {
                self.bpmState = .none
            }
        }
    }

    func playSelection() {
        guard let selection else { return }
        player.play(from: selection.lowerBound, to: selection.upperBound, asSelection: true)
    }

    /// 選択範囲のドラッグ確定。選択範囲を再生中なら新しい範囲へライブ追従する。
    func selectionDragEnded() {
        guard player.isSelectionSegment, player.state == .playing, let selection else { return }
        let current = player.currentFrame
        if selection.contains(current) {
            // 再生位置が新しい範囲内: 現在位置から新しい終点まで続行
            player.play(from: current, to: selection.upperBound, asSelection: true)
        } else {
            // 範囲外に出た: 新しい範囲の先頭から再生し直す
            player.play(from: selection.lowerBound, to: selection.upperBound, asSelection: true)
        }
    }
}
