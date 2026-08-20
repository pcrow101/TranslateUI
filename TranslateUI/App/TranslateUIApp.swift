//
//  TranslateUIApp.swift
//  TranslateUI
//
//  Created by paucrow on 17/08/2026.
//

import SwiftUI

@main
struct TranslateUIApp: App {
    @State private var settings: AppSettings
    @State private var store: ScreenshotStore
    @State private var help = HelpCenter()

    @Environment(\.openWindow) private var openWindow

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _store = State(initialValue: ScreenshotStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(store)
                .environment(help)
                .environment(\.showHelp, showHelp)
        }
        .defaultSize(width: 1200, height: 760)
        .commands {
            DocumentCommands()
            HelpCommands(help: help)

            CommandGroup(replacing: .newItem) {
                Button("Open Screenshots…") {
                    store.showsFileImporter = true
                }
                .keyboardShortcut("o")
            }

            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Re-analyze Screenshot") {
                    Task { await store.reanalyzeSelection() }
                }
                .keyboardShortcut("r")
                .disabled(store.selectedScreenshot == nil)
            }
        }

        // A single Help window rather than a group: asking for help twice
        // brings the existing window forward instead of stacking copies.
        Window("Translate UI Help", id: HelpCenter.windowID) {
            HelpView()
                .environment(help)
                .environment(\.showHelp, showHelp)
        }
        .defaultSize(width: 900, height: 620)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(store)
                .environment(\.showHelp, showHelp)
        }
    }

    private func showHelp(_ topic: HelpTopic.ID) {
        help.prepare(topic: topic)
        openWindow(id: HelpCenter.windowID)
    }
}
