//
//  WaveScopeApp.swift
//  WaveScope
//
//  Created by CHEEBOW on 2026/07/05.
//

import SwiftUI

@main
struct WaveScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 単一ウィンドウのビューア。WindowGroup だと Finder からのファイルオープンごとに
        // ウィンドウが増える(状態は AppModel.shared 共有なので同じ表示が複数並ぶ)ため
        // Window シーンで常に1枚にする。ファイルオープン時に SwiftUI がウィンドウを
        // 作り直すことがあるが、表示上は1枚が維持される
        Window("WaveScope", id: "main") {
            ContentView()
                .environment(AppModel.shared)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    AppModel.shared.openPanel()
                }
                .keyboardShortcut("o")

                Button("Get Info") {
                    // ファイル未読み込み時は何も出すものがないので開かない
                    guard AppModel.shared.loadedPeaks != nil else { return }
                    AppModel.shared.showInfoSheet = true
                }
                .keyboardShortcut("i")
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy BPM") {
                    // BPM 未検出時は何もしない(コピー対象がない)
                    AppModel.shared.copyBPM()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Zoom In") {
                    AppModel.shared.zoom(by: 0.5)
                }
                .keyboardShortcut("+")

                Button("Zoom Out") {
                    AppModel.shared.zoom(by: 2)
                }
                .keyboardShortcut("-")

                Button("Zoom to Fit") {
                    AppModel.shared.zoomToFit()
                }
                .keyboardShortcut("0")

                Divider()
            }
        }
    }
}

/// Finder の「このアプリで開く」/ Dock アイコンへのドロップを受ける
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        AppModel.shared.open(url: url)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // メインウィンドウを閉じたらアプリを終了する(再生も確実に止まる)。
        // SwiftUI ライフサイクルでは applicationShouldTerminateAfterLastWindowClosed が
        // 呼ばれず、scenePhase は ⌘H で隠しただけでも .background になるため、
        // willClose 通知を直接監視する。canBecomeMain でオープンパネル等の補助ウィンドウを除外。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.canBecomeMain else { return }
        // この willClose が「ユーザーが×/⌘W で閉じた」のか「ファイルオープンで SwiftUI が
        // ウィンドウを作り直している最中」なのかはこの時点では区別できない。
        // 再生成なら新しいウィンドウがすぐ現れるので、少し待ってから
        // メインになれる可視ウィンドウが残っていなければユーザーの閉じ操作とみなして終了する
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let windowRemains = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
            if !windowRemains {
                NSApp.terminate(nil)
            }
        }
    }
}
