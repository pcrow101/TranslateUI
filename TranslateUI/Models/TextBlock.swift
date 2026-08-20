//
//  TextBlock.swift
//  TranslateUI
//

import CoreGraphics
import Foundation

/// A single logical run of text found on a screenshot, together with its
/// detected language and translation state.
nonisolated struct TextBlock: Identifiable, Hashable, Sendable, Codable {
    enum TranslationState: Hashable, Sendable, Codable {
        case pending
        case translating
        case translated
        case skipped(reason: String)
        case failed(message: String)
    }

    let id: UUID
    /// Text exactly as recognised by Vision.
    var sourceText: String
    /// Bounding box in *image pixel* coordinates with a top-left origin.
    var frame: CGRect
    /// Vision's confidence for the winning candidate (0...1).
    var confidence: Float
    /// Average brightness (0...1) of the screenshot behind this block, used to
    /// pick a legible chip text colour.
    var backgroundLuminance: Double
    /// Language detected for this block (falls back to the document language).
    var sourceLanguage: SourceLanguage
    /// English text produced by the Translation framework.
    var translatedText: String?
    /// Optional Foundation Models rewrite tuned for UI terminology.
    var refinedText: String?
    /// A translation supplied by the user (inline edit) or replayed from the
    /// glossary. Always wins over the machine output.
    var userText: String?
    /// True when `userText` was applied from the glossary rather than typed
    /// on this screenshot.
    var isGlossaryMatch: Bool
    var state: TranslationState

    init(
        id: UUID = UUID(),
        sourceText: String,
        frame: CGRect,
        confidence: Float,
        backgroundLuminance: Double = 0,
        sourceLanguage: SourceLanguage = .unknown,
        translatedText: String? = nil,
        refinedText: String? = nil,
        userText: String? = nil,
        isGlossaryMatch: Bool = false,
        state: TranslationState = .pending
    ) {
        self.id = id
        self.sourceText = sourceText
        self.frame = frame
        self.confidence = confidence
        self.backgroundLuminance = backgroundLuminance
        self.sourceLanguage = sourceLanguage
        self.translatedText = translatedText
        self.refinedText = refinedText
        self.userText = userText
        self.isGlossaryMatch = isGlossaryMatch
        self.state = state
    }

    /// True when the screenshot behind this label is dark.
    var prefersLightText: Bool { backgroundLuminance < 0.5 }

    /// Best available English rendering of this block.
    var displayText: String {
        userText ?? refinedText ?? translatedText ?? sourceText
    }

    /// The machine translation, ignoring any manual or glossary override.
    var machineText: String? {
        refinedText ?? translatedText
    }

    /// Typed by hand on this screenshot (as opposed to replayed from glossary).
    var isManuallyEdited: Bool {
        userText != nil && !isGlossaryMatch
    }

    var needsTranslation: Bool {
        translatedText == nil && sourceLanguage.isTranslatable && state == .pending
    }

    /// Whether a translation attempt ended in failure and can be retried.
    var canRetry: Bool {
        if case .failed = state { return true }
        return false
    }

    /// Whether this block's result is final, and therefore safe to cache.
    ///
    /// Failed and in-flight labels must never be persisted: `needsTranslation`
    /// ignores them, so a cached failure would be replayed on every future
    /// import and the screenshot could never recover on its own.
    var isSettled: Bool {
        switch state {
        case .translated, .skipped:
            true
        case .failed, .translating:
            false
        case .pending:
            // Nothing to wait for when the language isn't translated at all.
            !sourceLanguage.isTranslatable
        }
    }

    /// A copy that a later pass will pick up again, used when reading results
    /// cached by an older (or interrupted) run.
    func revivedForRetry() -> TextBlock {
        guard !isSettled else { return self }
        var revived = self
        revived.state = .pending
        revived.translatedText = nil
        return revived
    }
}

// MARK: - Reading order

// `nonisolated` is required: the target defaults to main-actor isolation, so an
// unmarked extension would make the comparator `@MainActor` and trap whenever
// blocks are sorted off the main actor (recognition, export, tests).
nonisolated extension TextBlock {
    /// Orders blocks the way a person reads a screen: top to bottom, then left
    /// to right within the same visual line.
    ///
    /// Two blocks count as sharing a line when their vertical offset is under
    /// 60% of their *average* height. Averaging matters: keying the tolerance
    /// off only one side's height makes the comparison asymmetric, so
    /// `isOrderedBefore(a, b)` and `isOrderedBefore(b, a)` can both be true
    /// when a large heading sits beside small body text. That breaks the strict
    /// weak ordering `sorted(by:)` requires and produces unstable output.
    static func isOrderedBefore(_ lhs: TextBlock, _ rhs: TextBlock) -> Bool {
        let tolerance = ((lhs.frame.height + rhs.frame.height) / 2) * 0.6
        if abs(lhs.frame.minY - rhs.frame.minY) > tolerance {
            return lhs.frame.minY < rhs.frame.minY
        }
        if lhs.frame.minX != rhs.frame.minX {
            return lhs.frame.minX < rhs.frame.minX
        }
        // Deterministic tiebreak so identical geometry doesn't reorder between runs.
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

nonisolated extension Sequence<TextBlock> {
    /// The blocks sorted top-to-bottom, then left-to-right.
    var inReadingOrder: [TextBlock] {
        sorted(by: TextBlock.isOrderedBefore)
    }
}

/// The languages this app knows how to handle on a streaming-device UI.
nonisolated enum SourceLanguage: String, CaseIterable, Hashable, Sendable, Codable {
    case german
    case italian
    case english
    case unknown

    var localeLanguage: Locale.Language? {
        switch self {
        case .german: Locale.Language(identifier: "de")
        case .italian: Locale.Language(identifier: "it")
        case .english: Locale.Language(identifier: "en")
        case .unknown: nil
        }
    }

    /// Language identifiers handed to Vision for text recognition.
    static var recognitionIdentifiers: [Locale.Language] {
        [
            Locale.Language(identifier: "de-DE"),
            Locale.Language(identifier: "it-IT"),
            Locale.Language(identifier: "en-US")
        ]
    }

    /// Only German and Italian are translated; English is passed through.
    var isTranslatable: Bool {
        self == .german || self == .italian
    }

    var displayName: String {
        switch self {
        case .german: String(localized: "German")
        case .italian: String(localized: "Italian")
        case .english: String(localized: "English")
        case .unknown: String(localized: "Unknown")
        }
    }

    var flagSymbol: String {
        switch self {
        case .german: "🇩🇪"
        case .italian: "🇮🇹"
        case .english: "🇬🇧"
        case .unknown: "🏳️"
        }
    }
}
