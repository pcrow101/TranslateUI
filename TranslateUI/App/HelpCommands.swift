//
//  HelpCommands.swift
//  TranslateUI
//

import SwiftUI

/// Replaces the standard Help menu with the in-app help book.
///
/// `⌘?` is the system-standard shortcut for application help, so it stays on
/// the main entry. The extra items jump straight to the topics people look for
/// most often rather than making them search.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let help: HelpCenter

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Translate UI Help") {
                open(HelpContent.ID.gettingStarted)
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button("Keyboard Shortcuts") {
                open(HelpContent.ID.shortcuts)
            }

            Button("Languages & Downloads") {
                open(HelpContent.ID.languages)
            }

            Button("If Something Looks Wrong") {
                open(HelpContent.ID.troubleshooting)
            }

            Divider()

            Link(
                "Translation Languages in System Settings",
                destination: URL(
                    string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
            )
        }
    }

    private func open(_ topic: HelpTopic.ID) {
        help.prepare(topic: topic)
        openWindow(id: HelpCenter.windowID)
    }
}

// MARK: - Opening help from a view

extension EnvironmentValues {
    /// Opens the help book at a given topic. Injected by the app so any view
    /// can offer contextual help without reaching for the window machinery.
    @Entry var showHelp: (HelpTopic.ID) -> Void = { _ in }
}

/// A small "?" button that opens the help book at `topic`.
struct HelpButton: View {
    @Environment(\.showHelp) private var showHelp

    let topic: HelpTopic.ID
    var title: LocalizedStringKey = "Help"

    var body: some View {
        Button {
            showHelp(topic)
        } label: {
            Label(title, systemImage: "questionmark.circle")
        }
        .help(title)
        .accessibilityIdentifier("help.button")
    }
}
