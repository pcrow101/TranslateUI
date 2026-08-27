//
//  UIStringRefiner.swift
//  TranslateUI
//

import Foundation
import FoundationModels
import OSLog

/// Optional post-processing pass that rewrites machine-translated strings with
/// the on-device foundation model so they read like real streaming-device UI
/// labels ("Zurück" → "Back" rather than "Backwards").
struct UIStringRefiner {
    private static let logger = Logger(subsystem: "com.icloud.TranslateUI", category: "Refiner")

    /// Keeps prompts small and responses fast.
    private static let chunkSize = 12

    struct Item: Sendable {
        let id: UUID
        let source: String
        let translation: String
        /// Language of `source`. Used to skip items in a language the on-device
        /// model doesn't understand — passing them anyway produced an
        /// "Unsupported language id detected" log entry per chunk and left
        /// their raw translation untouched.
        let sourceLanguage: SourceLanguage
    }

    @Generable
    struct RefinedLabel {
        @Guide(description: "The numeric id copied verbatim from the matching input line.")
        var id: Int
        @Guide(description: "The final English label. Keep it as short as the original.")
        var text: String
    }

    @Generable
    struct RefinedLabelSet {
        @Guide(description: "One entry for every input line, in the same order.")
        var labels: [RefinedLabel]
    }

    /// Loads the model into memory ahead of the first request. Cheap to call
    /// and a no-op when Apple Intelligence isn't available.
    func prewarm() {
        guard Self.isAvailable else { return }
        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Which of our source languages the on-device model actually understands.
    ///
    /// Foundation Models silently logs *"Unsupported language id detected"*
    /// (and returns the draft unchanged) whenever a chunk contains a language
    /// its dictionary hasn't been trained on. We filter unsupported source
    /// languages *before* the call so the log stays clean and we don't waste
    /// a round-trip that can't improve the label.
    static var supportedSourceLanguages: Set<SourceLanguage> {
        let modelLanguages = SystemLanguageModel.default.supportedLanguages
        // Match on the language subtag ("de", "it", …). The model reports
        // Locale.Language values which include region info we don't care about
        // for the "is this language covered at all?" question.
        let codes = Set(modelLanguages.compactMap { $0.languageCode?.identifier })
        var result: Set<SourceLanguage> = [.english]
        for language in SourceLanguage.allCases {
            guard let code = language.localeLanguage?.languageCode?.identifier else { continue }
            if codes.contains(code) { result.insert(language) }
        }
        return result
    }

    static var unavailableReason: String? {
        guard case .unavailable(let reason) = SystemLanguageModel.default.availability else {
            return nil
        }
        switch reason {
        case .deviceNotEligible:
            return String(localized: "This Mac doesn’t support Apple Intelligence.")
        case .appleIntelligenceNotEnabled:
            return String(localized: "Turn on Apple Intelligence in System Settings to refine labels.")
        case .modelNotReady:
            return String(localized: "The on-device model is still downloading.")
        @unknown default:
            return String(localized: "The on-device model isn’t available right now.")
        }
    }

    private static let instructions = """
        You polish machine translations of streaming-device user-interface labels \
        (Apple TV, Fire TV, smart-TV menus) into natural English.

        Rules:
        - Use the standard English term a TV interface would use (Settings, Back, \
        Sign Out, Continue Watching, Subtitles, Audio & Language).
        - Keep the label as short as the original; never add explanations.
        - Preserve numbers, times, episode markers, brand and app names exactly.
        - If the supplied English is already correct, return it unchanged.
        - Return exactly one entry per input line, reusing its id.
        """

    /// Polishes machine translations into idiomatic interface English.
    ///
    /// - Parameters:
    ///   - items: the translated labels to refine.
    ///   - glossary: agreed source → English terms, injected into the prompt so
    ///     the model reuses house terminology instead of inventing its own.
    ///   - handler: called once per chunk so the UI can update while later
    ///     chunks are still being generated.
    /// - Returns: refined text keyed by block id. Any failure yields an empty
    ///   dictionary so the raw translation is used instead.
    func refine(
        _ items: [Item],
        glossary: [String: String] = [:],
        onChunk handler: (@MainActor ([UUID: String]) -> Void)? = nil
    ) async -> [UUID: String] {
        guard Self.isAvailable, !items.isEmpty else { return [:] }

        // Drop items in languages the on-device model doesn't recognise before
        // they get near a prompt — otherwise Foundation Models logs
        // "Unsupported language id detected" for the whole chunk.
        let supported = Self.supportedSourceLanguages
        let refinable = items.filter { supported.contains($0.sourceLanguage) }
        guard !refinable.isEmpty else { return [:] }

        var refinements: [UUID: String] = [:]
        for chunk in refinable.chunked(into: Self.chunkSize) {
            let session = LanguageModelSession(instructions: Self.instructions)
            let numbered = chunk.enumerated().map { index, item in
                "\(index). original: \"\(item.source)\" | draft: \"\(item.translation)\""
            }.joined(separator: "\n")

            var prompt = """
                Polish these labels from one screen of a TV interface:
                \(numbered)
                """

            // Established house terms win over the model's own preference.
            if !glossary.isEmpty {
                let examples =
                    glossary
                    .sorted { $0.key < $1.key }
                    .map { "\"\($0.key)\" is always \"\($0.value)\"" }
                    .joined(separator: "\n")
                prompt = """
                    These translations have already been agreed for this device and \
                    must be reused exactly when the same original appears:
                    \(examples)

                    \(prompt)
                    """
            }

            do {
                let response = try await session.respond(to: prompt, generating: RefinedLabelSet.self)
                var chunkResults: [UUID: String] = [:]
                for label in response.content.labels {
                    guard chunk.indices.contains(label.id) else { continue }
                    let text = label.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    chunkResults[chunk[label.id].id] = text
                }
                refinements.merge(chunkResults) { _, new in new }
                if !chunkResults.isEmpty {
                    await MainActor.run { handler?(chunkResults) }
                }
            } catch {
                Self.logger.warning(
                    "Refinement chunk failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return refinements
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
