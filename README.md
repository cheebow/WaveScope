# WaveScope

音声ファイルの波形表示・再生を行う macOS アプリです(編集・保存機能なしのビューア)。

![アプリアイコン](Design/AppIcon/preview.png)

## 対応フォーマット

WAV / MP3 / AIFF / M4A / CAF / FLAC

## 主な機能

- **波形表示** — チャンネル別(ステレオ対応)の min/max ピーク波形。ズームインすると可視範囲だけをファイルから再デコードする二段構えの高解像度描画。
- **再生** — 全体再生・クリック位置からの再生・選択範囲のループしないサンプル精度の範囲再生。
- **範囲選択** — ドラッグで範囲選択し、その区間だけを再生。
- **ズーム / パン** — ⌥/⌘+スクロールやピンチでズーム、横スクロールでパン。
- **レベルメーター** — 再生中のチャンネル別ピークレベル(dB)を 60fps で表示。
- **カーソルチップ** — マウス位置の時刻とピーク dB を表示。
- **時間ルーラー** — ズームに応じて目盛り間隔が変化。

## 動作環境

- macOS 14 以降
- ビルドには Xcode 26 以降(Swift Testing / Icon Composer ドキュメントを使用)

## ビルドと実行

```sh
cd WaveScope

# ビルド
xcodebuild -project WaveScope.xcodeproj -scheme WaveScope -configuration Debug -derivedDataPath build build

# 起動(ファイルを渡すと「このアプリで開く」経路で開く)
open -a "$(pwd)/build/Build/Products/Debug/WaveScope.app" ../TestAudio/test.wav
```

## テスト

```sh
cd WaveScope
xcodebuild test -project WaveScope.xcodeproj -scheme WaveScope -destination 'platform=macOS' -only-testing:WaveScopeTests
```

テスト音源はリポジトリに含まれません。リポジトリルートで以下を実行すると `TestAudio/` に各フォーマットのファイルが生成されます:

```sh
./Scripts/make-test-audio.sh        # 通常のテスト音源
./Scripts/make-test-audio.sh --long # 1時間の長尺ファイルも生成
```

## プロジェクト構成

```
WaveScope/WaveScope/
├── Core/        # SwiftUI 非依存の純粋レイヤー(ピーク抽出・波形描画)
│   ├── PeakExtractor.swift
│   ├── WaveformPeaks.swift
│   └── WaveformRenderer.swift
├── Views/       # SwiftUI ビュー(波形・トランスポート・レベルメーターなど)
├── AppModel.swift        # アプリ状態(ロード・選択・表示範囲)
├── PlayerController.swift # AVAudioEngine による再生制御
└── WaveScopeApp.swift
```

## ライセンス

未定
