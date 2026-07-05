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
        WindowGroup {
            ContentView()
                .environment(AppModel.shared)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("開く…") {
                    AppModel.shared.openPanel()
                }
                .keyboardShortcut("o")
            }
            CommandGroup(after: .sidebar) {
                Button("ズームイン") {
                    AppModel.shared.zoom(by: 0.5)
                }
                .keyboardShortcut("+")

                Button("ズームアウト") {
                    AppModel.shared.zoom(by: 2)
                }
                .keyboardShortcut("-")

                Button("全体を表示") {
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
}
