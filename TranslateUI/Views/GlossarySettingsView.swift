//
//  GlossarySettingsView.swift
//  TranslateUI
//

import SwiftUI

/// Manages the remembered terms that keep interface wording consistent.
struct GlossarySettingsView: View {
    @Environment(ScreenshotStore.self) private var store

    @State private var searchText = ""
    @State private var selection: GlossaryEntry.ID?
    @State private var showsRemoveAllConfirmation = false

    private var entries: [GlossaryEntry] {
        let all = store.glossary.entries.sorted { lhs, rhs in
            lhs.sourceText.localizedStandardCompare(rhs.sourceText) == .orderedAscending
        }
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.sourceText.localizedStandardContains(searchText)
                || $0.translation.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.glossary.isEmpty {
                ContentUnavailableView(
                    "No Remembered Terms",
                    systemImage: "bookmark",
                    description: Text(
                        "Correct a translation on a screenshot and choose “Remember this term” to add it here."
                    )
                )
            } else {
                Table(entries, selection: $selection) {
                    TableColumn("Original") { entry in
                        Text("\(entry.language.flagSymbol) \(entry.sourceText)")
                    }
                    TableColumn("English", value: \.translation)
                    TableColumn("Uses") { entry in
                        Text(entry.useCount, format: .number)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 44, ideal: 52, max: 70)
                }
                .tableStyle(.inset)
                .alternatingRowBackgrounds()
                .contextMenu(forSelectionType: GlossaryEntry.ID.self) { ids in
                    Button("Remove", role: .destructive) { remove(ids) }
                } primaryAction: { _ in
                }
                .onDeleteCommand { remove(selection.map { [$0] } ?? []) }
                .searchable(text: $searchText, placement: .automatic, prompt: "Search terms")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(store.glossary.entries.count) terms")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Remove Selected") {
                    remove(selection.map { [$0] } ?? [])
                }
                .disabled(selection == nil)

                Button("Remove All…", role: .destructive) {
                    showsRemoveAllConfirmation = true
                }
                .disabled(store.glossary.isEmpty)
            }
            .padding(12)
        }
        .confirmationDialog(
            "Remove every remembered term?",
            isPresented: $showsRemoveAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) {
                store.glossary.removeAll()
                store.applyGlossaryToAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Screenshots revert to the machine translation. This can’t be undone.")
        }
    }

    private func remove(_ ids: Set<GlossaryEntry.ID>) {
        for id in ids {
            guard let entry = store.glossary.entries.first(where: { $0.id == id }) else { continue }
            store.removeGlossaryEntry(entry)
        }
        selection = nil
    }

    private func remove(_ ids: [GlossaryEntry.ID]) {
        remove(Set(ids))
    }
}
