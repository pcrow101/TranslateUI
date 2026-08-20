//
//  Glossary.swift
//  TranslateUI
//

import Foundation
import OSLog
import Observation

/// Remembers house translations for interface labels and replays them on every
/// screenshot, so terminology stays consistent across a whole device.
@MainActor
@Observable
final class Glossary {
    private nonisolated static let logger = Logger(subsystem: "com.icloud.TranslateUI", category: "Glossary")

    private(set) var entries: [GlossaryEntry] = []
    private var index: [String: GlossaryEntry.ID] = [:]
    private let fileURL: URL?
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = Glossary.defaultFileURL()) {
        self.fileURL = fileURL
        load()
    }

    static func defaultFileURL() -> URL? {
        guard
            let base = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        else { return nil }
        let folder = base.appending(path: "TranslateUI", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "glossary.json")
    }

    // MARK: - Lookup

    var isEmpty: Bool { entries.isEmpty }

    func translation(for sourceText: String, language: SourceLanguage) -> String? {
        entry(for: sourceText, language: language)?.translation
    }

    func entry(for sourceText: String, language: SourceLanguage) -> GlossaryEntry? {
        guard let id = index[GlossaryEntry.key(for: sourceText, language: language)] else { return nil }
        return entries.first { $0.id == id }
    }

    /// Entries relevant to a set of labels, used to prime the refiner prompt.
    func entries(matching sourceTexts: [String], language: SourceLanguage) -> [GlossaryEntry] {
        sourceTexts.compactMap { entry(for: $0, language: language) }
    }

    // MARK: - Mutation

    @discardableResult
    func learn(sourceText: String, language: SourceLanguage, translation: String) -> GlossaryEntry? {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !target.isEmpty, language.isTranslatable else { return nil }

        if var existing = entry(for: source, language: language) {
            existing.translation = target
            existing.lastUsedAt = .now
            replace(existing)
            scheduleSave()
            return existing
        }

        let entry = GlossaryEntry(sourceText: source, language: language, translation: target)
        entries.append(entry)
        index[entry.key] = entry.id
        scheduleSave()
        return entry
    }

    func recordUse(of entry: GlossaryEntry) {
        var updated = entry
        updated.useCount += 1
        updated.lastUsedAt = .now
        replace(updated)
        scheduleSave()
    }

    func remove(_ entry: GlossaryEntry) {
        entries.removeAll { $0.id == entry.id }
        index.removeValue(forKey: entry.key)
        scheduleSave()
    }

    func remove(atOffsets offsets: IndexSet, in list: [GlossaryEntry]) {
        for index in offsets {
            guard list.indices.contains(index) else { continue }
            remove(list[index])
        }
    }

    func removeAll() {
        entries.removeAll()
        index.removeAll()
        scheduleSave()
    }

    private func replace(_ entry: GlossaryEntry) {
        guard let position = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[position] = entry
        index[entry.key] = entry.id
    }

    // MARK: - Persistence

    private func load() {
        guard
            let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([GlossaryEntry].self, from: data)
        else { return }
        entries = stored
        index = Dictionary(stored.map { ($0.key, $0.id) }, uniquingKeysWith: { _, last in last })
    }

    /// Coalesces rapid edits into a single write.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = entries
        let fileURL = self.fileURL
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let fileURL else { return }
            await Self.write(snapshot, to: fileURL)
        }
    }

    @concurrent
    private nonisolated static func write(_ entries: [GlossaryEntry], to url: URL) async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: url, options: .atomic)
        } catch {
            logger.warning("Failed to save glossary: \(error.localizedDescription, privacy: .public)")
        }
    }
}
