//
//  AppCommands.swift
//  TranslateUI
//

import SwiftUI

/// Menu-bar commands for the document actions.
///
/// These read whatever the focused scene published, so they stay enabled only
/// while a screenshot is selected.
struct DocumentCommands: Commands {
    @FocusedValue(\.copyTranslations) private var copyTranslations
    @FocusedValue(\.exportAnnotatedImage) private var exportAnnotatedImage

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Export Annotated Image…") {
                exportAnnotatedImage?()
            }
            .keyboardShortcut("e")
            .disabled(exportAnnotatedImage == nil)
        }

        CommandGroup(after: .pasteboard) {
            Button("Copy All Translations") {
                copyTranslations?()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(copyTranslations == nil)
        }
    }
}
