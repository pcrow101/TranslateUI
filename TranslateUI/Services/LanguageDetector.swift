//
//  LanguageDetector.swift
//  TranslateUI
//

import Foundation
import NaturalLanguage

/// Decides whether each recognised block is German, Italian, English (or,
/// when enabled, Spanish).
///
/// UI labels are short ("Einstellungen", "Esci"), so per-block detection alone
/// is unreliable. The detector first establishes a dominant language for the
/// whole screen and only overrides it when a block is confidently different.
nonisolated struct LanguageDetector: Sendable {
    private static let baseCandidates: [NLLanguage: SourceLanguage] = [
        .german: .german,
        .italian: .italian,
        .english: .english
    ]

    private static let optionalCandidates: [SourceLanguage: NLLanguage] = [
        .spanish: .spanish
    ]

    /// Minimum probability required before a single block may disagree with
    /// the dominant language of the screen.
    var perBlockConfidenceThreshold: Double = 0.75

    /// Opt-in languages the user has enabled in Settings.
    var enabledOptional: Set<SourceLanguage> = []

    /// Every language the recognizer is allowed to consider.
    private var candidates: [NLLanguage: SourceLanguage] {
        var map = Self.baseCandidates
        for language in enabledOptional {
            if let key = Self.optionalCandidates[language] {
                map[key] = language
            }
        }
        return map
    }

    @concurrent
    nonisolated func dominantLanguage(for blocks: [TextBlock]) async -> SourceLanguage {
        let corpus =
            blocks
            .map(\.sourceText)
            .filter { $0.count > 2 }
            .joined(separator: ". ")
        guard !corpus.isEmpty else { return .unknown }
        return language(of: corpus).language
    }

    @concurrent
    nonisolated func classify(_ blocks: [TextBlock], documentLanguage: SourceLanguage) async -> [TextBlock] {
        blocks.map { block in
            var block = block
            let result = language(of: block.sourceText)
            if result.language != .unknown, result.confidence >= perBlockConfidenceThreshold {
                block.sourceLanguage = result.language
            } else if documentLanguage != .unknown {
                block.sourceLanguage = documentLanguage
            } else {
                block.sourceLanguage = result.language
            }

            if !block.sourceLanguage.isTranslatable, block.sourceLanguage == .english {
                block.state = .skipped(reason: String(localized: "Already English"))
                block.translatedText = block.sourceText
            }
            return block
        }
    }

    // MARK: - Private

    private nonisolated func language(of text: String) -> (language: SourceLanguage, confidence: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1 else { return (.unknown, 0) }

        let map = candidates
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Array(map.keys)
        recognizer.processString(trimmed)

        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard
            let best = hypotheses.max(by: { $0.value < $1.value }),
            let mapped = map[best.key]
        else {
            return (.unknown, 0)
        }
        return (mapped, best.value)
    }
}
