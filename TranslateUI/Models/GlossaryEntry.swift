//
//  GlossaryEntry.swift
//  TranslateUI
//

import Foundation

/// A remembered translation for a specific interface label.
///
/// Correcting "Abmelden" → "Sign Out" once teaches the app the house term, and
/// every future screenshot from the same device reuses it.
nonisolated struct GlossaryEntry: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    /// The original label, stored with its original casing for display.
    var sourceText: String
    var language: SourceLanguage
    var translation: String
    var createdAt: Date
    var lastUsedAt: Date
    /// How many blocks this entry has been applied to.
    var useCount: Int

    init(
        id: UUID = UUID(),
        sourceText: String,
        language: SourceLanguage,
        translation: String,
        createdAt: Date = .now,
        lastUsedAt: Date = .now,
        useCount: Int = 0
    ) {
        self.id = id
        self.sourceText = sourceText
        self.language = language
        self.translation = translation
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }

    /// Lookup key: case- and whitespace-insensitive, scoped by language.
    var key: String {
        Self.key(for: sourceText, language: language)
    }

    static func key(for sourceText: String, language: SourceLanguage) -> String {
        let normalized =
            sourceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(language.rawValue)|\(normalized)"
    }
}
