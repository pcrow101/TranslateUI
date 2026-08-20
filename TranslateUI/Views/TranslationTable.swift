//
//  TranslationTable.swift
//  TranslateUI
//

import SwiftUI

/// Full-width table used by the "Text List" display mode.
struct TranslationTable: View {
    let screenshot: Screenshot
    @Binding var selectedBlockID: TextBlock.ID?

    var body: some View {
        Table(rows, selection: selectionBinding) {
            TableColumn("Language") { row in
                Text("\(row.sourceLanguage.flagSymbol) \(row.sourceLanguage.displayName)")
            }
            .width(min: 90, ideal: 110, max: 140)

            TableColumn("Original", value: \.sourceText)

            TableColumn("English") { row in
                HStack(spacing: 4) {
                    Text(row.displayText)
                    if row.refinedText != nil {
                        Image(systemName: "sparkles").foregroundStyle(.tint)
                    }
                }
            }

            TableColumn("Status") { row in
                Text(statusText(for: row))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120, max: 180)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds()
    }

    private var rows: [TextBlock] {
        screenshot.blocks.inReadingOrder
    }

    private var selectionBinding: Binding<TextBlock.ID?> {
        Binding(get: { selectedBlockID }, set: { selectedBlockID = $0 })
    }

    private func statusText(for block: TextBlock) -> String {
        switch block.state {
        case .pending: String(localized: "Waiting")
        case .translating: String(localized: "Translating…")
        case .translated: String(localized: "Translated")
        case .skipped(let reason): reason
        case .failed(let message): message
        }
    }
}
