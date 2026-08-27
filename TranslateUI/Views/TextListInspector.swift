//
//  TextListInspector.swift
//  TranslateUI
//

import AppKit
import SwiftUI

/// Trailing inspector listing every recognised line and its translation.
struct TextListInspector: View {
    @Environment(ScreenshotStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Binding var selectedBlockID: TextBlock.ID?

    @State private var editingBlock: TextBlock?

    var body: some View {
        Group {
            if let screenshot = store.selectedScreenshot, !screenshot.blocks.isEmpty {
                List(selection: $selectedBlockID) {
                    ForEach(screenshot.blocks.inReadingOrder) { block in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.displayText)
                                .font(.body)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("inspector.translation")

                            HStack(spacing: 6) {
                                Text(block.sourceLanguage.flagSymbol)
                                Text(block.sourceText)
                                    .lineLimit(2)
                                if block.isManuallyEdited {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(.tint)
                                        .help("Edited by you")
                                } else if block.isGlossaryMatch {
                                    Image(systemName: "bookmark.fill")
                                        .foregroundStyle(.tint)
                                        .help("Remembered term from your glossary")
                                } else if block.refinedText != nil {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.tint)
                                        .help("Polished by the on-device model")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if case .failed(let message) = block.state {
                                Label(message, systemImage: "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(block.id)
                        // Drag out the translated text — mirrors the
                        // draggable overlay chips on the canvas.
                        .draggable(block.displayText)
                        .swipeActions(edge: .trailing) {
                            Button("Edit") { editingBlock = block }
                        }
                        .contextMenu {
                            Button("Edit Translation…") { editingBlock = block }
                            if block.userText != nil {
                                Button("Use Machine Translation") {
                                    store.resetTranslation(for: block.id, in: screenshot)
                                }
                            }
                            if block.canRetry {
                                Button("Retry Translation") {
                                    Task { await store.retryTranslation(for: block.id, in: screenshot) }
                                }
                            }
                            Divider()
                            Button("Copy Translation") { copy(block.displayText) }
                            Button("Copy Original") { copy(block.sourceText) }
                        }
                    }
                }
                .listStyle(.inset)
            } else {
                ContentUnavailableView(
                    "No Text Yet",
                    systemImage: "text.viewfinder",
                    description: Text("Recognised lines appear here once a screenshot is analysed.")
                )
            }
        }
        .sheet(item: $editingBlock) { block in
            if let screenshot = store.selectedScreenshot {
                TranslationEditor(screenshot: screenshot, block: block)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.selectedScreenshot != nil {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Toggle(
                            "Show Original",
                            isOn: Binding(
                                get: { settings.showOriginalText },
                                set: { settings.showOriginalText = $0 }
                            )
                        )
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Spacer()

                        Button {
                            Task { await store.refineSelection() }
                        } label: {
                            Label("Polish", systemImage: "sparkles")
                        }
                        .buttonStyle(.glass)
                        .disabled(!UIStringRefiner.isAvailable)
                        .help(UIStringRefiner.unavailableReason ?? "Rewrite labels with the on-device model")
                    }
                    .padding(12)
                }
                .background(.bar)
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
