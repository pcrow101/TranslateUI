//
//  GlossaryCoordinator.swift
//  TranslateUI
//

import Foundation

/// Replays remembered terms onto screenshots.
///
/// Precedence is deliberate: a translation typed by hand on a screenshot is
/// never overwritten by the glossary, while a term that was *applied from* the
/// glossary reverts to the machine output once that term is forgotten.
@MainActor
struct GlossaryCoordinator {
    let glossary: Glossary

    /// Applies every matching remembered term to `screenshot`.
    func apply(to screenshot: Screenshot) {
        for block in screenshot.blocks {
            guard block.sourceLanguage.isTranslatable, !block.isManuallyEdited else { continue }

            guard let entry = glossary.entry(for: block.sourceText, language: block.sourceLanguage) else {
                // A term removed from the glossary should revert to the machine output.
                if block.isGlossaryMatch {
                    screenshot.update(blockID: block.id) {
                        $0.userText = nil
                        $0.isGlossaryMatch = false
                    }
                }
                continue
            }

            guard block.userText != entry.translation else { continue }
            screenshot.update(blockID: block.id) {
                $0.userText = entry.translation
                $0.isGlossaryMatch = true
            }
            glossary.recordUse(of: entry)
        }
    }

    /// Agreed terms relevant to this screenshot, used to prime the model so
    /// refinement follows the user's terminology instead of inventing its own.
    func examples(for screenshot: Screenshot) -> [String: String] {
        var examples: [String: String] = [:]
        for block in screenshot.blocks where block.sourceLanguage.isTranslatable {
            if let entry = glossary.entry(for: block.sourceText, language: block.sourceLanguage) {
                examples[entry.sourceText] = entry.translation
            }
        }
        return examples
    }
}
