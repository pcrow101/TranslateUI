//
//  TranslationEditor.swift
//  TranslateUI
//

import SwiftUI

/// Popover for correcting a single translation, with the option to remember the
/// correction for every future screenshot.
struct TranslationEditor: View {
    @Environment(ScreenshotStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let screenshot: Screenshot
    let block: TextBlock

    @State private var text: String = ""
    @State private var remember: Bool = true
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(block.sourceLanguage.flagSymbol) \(block.sourceText)")
                    .font(.headline)
                    .textSelection(.enabled)
                if let machine = block.machineText, machine != text {
                    Text("Machine translation: \(machine)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("English", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($isFieldFocused)
                .onSubmit(save)

            if block.sourceLanguage.isTranslatable {
                Toggle(isOn: $remember) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Remember this term")
                        Text("Apply to “\(block.sourceText)” on every screenshot")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                if block.userText != nil {
                    Button("Use Machine Translation") {
                        store.resetTranslation(for: block.id, in: screenshot)
                        dismiss()
                    }
                }

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            text = block.displayText
            remember = block.sourceLanguage.isTranslatable
            isFieldFocused = true
        }
    }

    private func save() {
        store.setTranslation(text, for: block.id, in: screenshot, rememberInGlossary: remember)
        dismiss()
    }
}
