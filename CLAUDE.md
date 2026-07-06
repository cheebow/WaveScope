# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

WaveScope — 音声ファイル(WAV/MP3/AIFF/M4A/CAF/FLAC)の波形表示・再生を行う macOS アプリ(SwiftUI、macOS 14+、編集・保存機能なしのビューア)。UI は日英ローカライズ済み: **コード内の文字列は英語キー**で書き、`Localizable.xcstrings` に日本語訳を追加する(開発言語 en、日英以外は英語にフォールバック)。時刻・dB などのデータ表示は `Text(verbatim:)` でカタログに載せない。動作確認で言語を切り替えるには `open <app> --args -AppleLanguages '(en)'`。

## コマンド

すべて `WaveScope/` ディレクトリで実行する(`.xcodeproj` がそこにあるため):

```sh
cd WaveScope

# ビルド
xcodebuild -project WaveScope.xcodeproj -scheme WaveScope -configuration Debug -derivedDataPath build build

# 起動(ファイルを渡すと「このアプリで開く」経路 = AppDelegate.application(_:open:) を通る)
open -a "$(pwd)/build/Build/Products/Debug/WaveScope.app" ../TestAudio/test.wav

# ユニットテスト(Swift Testing。UIテストは遅いので -only-testing 推奨)
xcodebuild test -project WaveScope.xcodeproj -scheme WaveScope -destination 'platform=macOS' -only-testing:WaveScopeTests

# 単一テストの実行
xcodebuild test ... -only-testing:'WaveScopeTests/AppModelZoomTests/中央アンカーのズームイン()'
```

テスト音源の生成(リポジトリルートから): `./Scripts/make-test-audio.sh` → `TestAudio/` に各フォーマットを生成。`test.wav` は左440Hz/右880Hz・中央に1秒の無音ギャップ(ステレオ確認・範囲再生の境界確認用ランドマーク)。`--long` で1時間ファイルも生成。afconvert は MP3 をエンコードできないため MP3 フィクスチャは無い。

## ブランチ運用とリリース

- 日常の開発は **develop ブランチ**で行う(GitHub のデフォルトブランチも develop)。main へ直接コミットしない。
- リリース手順: `git switch main && git merge --ff-only develop` → `./Scripts/release.sh`(リポジトリルートから実行)。
- `release.sh` が MARKETING_VERSION からバージョンを取り、ビルド → Developer ID 署名 → 公証 → **main 上に `vX.Y.Z` タグを作成して push** → GitHub Release 作成(zip 添付)まで行う。main ブランチ・クリーンな作業ツリー・タグ未存在をスクリプトが検証する。
- バージョンを上げるときは pbxproj の `MARKETING_VERSION`(全 configuration)を更新してから develop にコミットする。

## プロジェクト構成の重要な制約

- **XcodeGen/Tuist 等のプロジェクト生成ツールは使わない**(ユーザーの明示方針)。プロジェクトは Xcode テンプレート製。
- ソースは **File System Synchronized Group**(同期フォルダ)なので、`WaveScope/WaveScope/` 以下にファイルを追加/削除するだけでターゲットに反映される。**pbxproj の編集は不要**。
- ビルド設定で `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`(Xcode 26 テンプレート既定)。**全宣言がデフォルトで MainActor になる**ため、バックグラウンドで動く Core 層の型は明示的に `nonisolated` を付けている。新しい Core 型にも必須。
- `Info.plist`(`WaveScope/Info.plist`)は `CFBundleDocumentTypes`(「このアプリで開く」対応)と `LSApplicationCategoryType` だけを持ち、`GENERATE_INFOPLIST_FILE = YES` と併用で自動生成分とマージされる。
- テスト用に `WaveformView.rulerInterval` / `rulerLabel` は internal にしてある。

## アプリアイコン

- `WaveScope/WaveScope/AppIcon.icon` は Icon Composer ドキュメント(パッケージ: `icon.json` + `Assets/*.svg`)。ビルド時に actool がコンパイルし、macOS 14/15 向けの平坦化 `.icns` も自動生成される。名前はビルド設定 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` と一致させること。
- `Assets.xcassets` に AppIcon.appiconset は**無い**(`.icon` と競合するため削除済み。復活させないこと)。
- デザイン原本は `Design/AppIcon/`。SVG レイヤー(波形バー・再生ヘッド)は `gen_icon.py` で生成しており、バー本数/エンベロープ/再生ヘッド位置はスクリプト内の定数。手直しは Icon Composer で `.icon` を直接開いてもよいが、その場合は `Design/AppIcon/AppIcon.icon`(原本)と乖離することに注意。

## アーキテクチャ

### データフロー(表示)

```
open(url) [AppModel]
  → PeakExtractor.extractPeaks (Task.detached、チャンク読み、進捗、キャンセル対応)
  → WaveformPeaks: チャンネル別 min/max を 256サンプル/bin の固定解像度でメモリキャッシュ(1時間ステレオ≈10MB)
  → 表示時に pixelPeaks(width:channel:startFrame:endFrame:) で可視範囲を表示幅へ再ビニング
  → WaveformView の Canvas → WaveformRenderer.draw(CGContext への純描画)
```

**二段構えのズーム描画**: 1ピクセルあたりのサンプル数が 256(samplesPerBin)を下回るズームでは、`PeakExtractor.extractPixelPeaks` が可視範囲だけをファイルから再デコードして `HighResPixelPeaks` を作る(60ms デバウンス、AppModel.visibleRangeChanged)。描画側は `matches(startFrame:endFrame:width:)` が**完全一致するときだけ**高解像度を使い、それ以外は粗いキャッシュで即描画→非同期差し替え。

### レイヤー分離

- `Core/`(WaveformPeaks / PeakExtractor / WaveformRenderer)は **SwiftUI 非依存・nonisolated・Sendable**。将来 QuickLook 拡張ターゲット(v1では見送り)とコード共有するための純度を保つこと。
- `AppModel`(@MainActor @Observable、シングルトン `.shared`)がロード状態・選択範囲・表示範囲(ズーム/スクロール)・高解像度ピークを持つ。AppDelegate と menu commands からも `.shared` 経由で触る。
- `PlayerController` が AVAudioEngine + AVAudioPlayerNode を包む。UI は `TimelineView` で再生位置をポーリングする(@Observable の再生位置プロパティ変更で波形を再描画させないため、波形 Canvas は TimelineView の外)。

### 再生(PlayerController)

- 単一プリミティブ `play(from:to:asSelection:)` が全再生モード(全体/クリック位置から/選択範囲)を実現。`scheduleSegment` によるサンプル精度の範囲再生。
- **世代カウンタが必須**: `stop()`/再スケジュールでも完了コールバックが発火するため、世代一致時のみ `.stopped` へ遷移する。
- ファイルを開くたびに `processingFormat` で mixer へ**再接続**する(サンプルレートが違うと `playerTime.sampleTime` とファイルフレームの対応が崩れる)。
- 再生位置 = `segmentStartFrame + playerTime(forNodeTime: lastRenderTime).sampleTime`。`lastRenderTime` はエンジン描画前 nil。
- `asSelection: true` のセグメント再生中に選択をドラッグし直すと、マウスアップ時に `AppModel.selectionDragEnded()` がライブ追従(位置が新範囲内なら継続、範囲外なら新範囲の先頭から)。
- レベルメーターは playerNode の tap(512サンプル)→ `meterLevels`(dB)。表示側(LevelMeterView)が 60fps で補間(立ち上がり即時・下降 60dB/s)。

### 入力処理

SwiftUI ジェスチャではスクロールホイール/ピンチ/ホバーを扱えないため、`WaveformInteractionView`(NSViewRepresentable)が**マウス操作を一元的に**受けてコールバックで返す: クリック=シーク再生、3pt超ドラッグ=範囲選択、横スクロール=パン、⌥/⌘スクロールとピンチ=ズーム、mouseMoved=カーソル位置チップ(時刻+ピークdB)。

### 既知の落とし穴

- `AVAudioFile(forWriting:)` は**オブジェクト解放時にヘッダを確定**する。書き込みを関数スコープに閉じないと 0 フレームのファイルができる(テスト音源スクリプト・テストフィクスチャの `func write()` パターンはこのため)。
- `AppModel.viewWidth` は GeometryReader からのキャッシュで、稀に古くなる。**座標→データの変換に使う幅は、可能なら呼び出し側の実際の幅を渡す**(過去に hover チップの dB が別位置の値になるバグの原因になった。`peakDB(atColumn:channel:width:)` が width を引数に取るのはこのため)。
- 波形 Canvas は依存値(visibleStart/hiResPeaks 等)を **body 側で読んでからクロージャに渡す**。Canvas クロージャ内で直接 Observable を読むと変更検知されない。

## 検証の慣習

UI 動作はスクリーンショットで確認する: アプリを起動し `screencapture -l <windowID>` でウィンドウをキャプチャ(windowID は CGWindowListCopyWindowInfo で取得。システム python3 に pyobjc は無いので `swift -e` でワンライナーを書く)。操作の合成は AppleScript(System Events のボタンクリック)と CGEvent(クリック/ドラッグ/スクロール。**ドラッグは mouseDown 後に 250ms 待たないと無視される**)。トランスポートの時刻表示は AX の static text から読める(カーソルチップが static text 1 になることがあるので注意)。
