//
//  TextPipelineTests.swift
//  TranslateUITests
//

import CoreGraphics
import Foundation
import Testing

@testable import TranslateUI

@Suite("Text pipeline")
struct TextPipelineTests {

    private func block(
        _ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 60, height: CGFloat = 20
    ) -> TextBlock {
        TextBlock(
            sourceText: text,
            frame: CGRect(x: x, y: y, width: width, height: height),
            confidence: 0.9
        )
    }

    @Test("Fragments on the same baseline are merged into one phrase")
    func mergesFragmentsOnSameLine() {
        let fragments = [
            block("Audio &", x: 100, y: 200, width: 60),
            block("Untertitel", x: 168, y: 201, width: 80)
        ]

        let merged = TextRecognitionService.mergeFragmentsOnSameLine(fragments)

        #expect(merged.count == 1)
        #expect(merged[0].sourceText == "Audio & Untertitel")
        #expect(merged[0].frame.width == 148)
    }

    @Test("Fragments on different lines stay separate")
    func keepsSeparateLinesApart() {
        let lines = [
            block("Einstellungen", x: 100, y: 200),
            block("Abmelden", x: 100, y: 260)
        ]

        let merged = TextRecognitionService.mergeFragmentsOnSameLine(lines)

        #expect(merged.count == 2)
    }

    @Test("Distant fragments on the same line are not merged")
    func keepsDistantFragmentsApart() {
        let lines = [
            block("Startseite", x: 100, y: 200, width: 60),
            block("Suchen", x: 600, y: 200, width: 60)
        ]

        let merged = TextRecognitionService.mergeFragmentsOnSameLine(lines)

        #expect(merged.count == 2)
    }

    @Test("Short labels inherit the language of the screen")
    func shortLabelsInheritDocumentLanguage() async {
        let detector = LanguageDetector()
        let blocks = [
            block("Einstellungen und Datenschutz verwalten", x: 0, y: 0),
            block("OK", x: 0, y: 40)
        ]

        let documentLanguage = await detector.dominantLanguage(for: blocks)
        let classified = await detector.classify(blocks, documentLanguage: documentLanguage)
        let languages = Set(classified.map(\.sourceLanguage))
        let allNeedTranslation = classified.allSatisfy(\.needsTranslation)

        #expect(documentLanguage == .german)
        #expect(languages == [.german])
        #expect(allNeedTranslation)
    }

    @Test("Blocks prefer refined text, then translation, then source")
    func displayTextPrecedence() {
        var block = block("Zurück", x: 0, y: 0)
        #expect(block.displayText == "Zurück")

        block.translatedText = "Backwards"
        #expect(block.displayText == "Backwards")

        block.refinedText = "Back"
        #expect(block.displayText == "Back")
    }

    @Test("English blocks are skipped rather than translated")
    func englishBlocksAreSkipped() async {
        let detector = LanguageDetector()
        let blocks = [block("Continue watching the next episode", x: 0, y: 0)]

        let classified = await detector.classify(blocks, documentLanguage: .english)

        #expect(classified[0].sourceLanguage == .english)
        #expect(classified[0].needsTranslation == false)
        #expect(classified[0].translatedText == "Continue watching the next episode")
    }

    @Test("Spanish text misclassifies as Italian when the Spanish opt-in is off")
    func spanishClassifiesAsItalianByDefault() async {
        // Same corpus, two detectors. With the default candidate set (no
        // Spanish) NL falls back to Italian because it's the closest romance
        // language in the constraint list — this is exactly the bug the
        // Settings opt-in fixes.
        let detector = LanguageDetector()
        let blocks = [
            block("Buscar en la biblioteca de películas", x: 0, y: 0),
            block("Configuración de la cuenta", x: 0, y: 40)
        ]

        let dominant = await detector.dominantLanguage(for: blocks)
        #expect(dominant == .italian)
    }

    @Test("Enabling Spanish routes Spanish text through the Spanish pipeline")
    func spanishOptInClassifiesSpanish() async {
        var detector = LanguageDetector()
        detector.enabledOptional = [.spanish]
        let blocks = [
            block("Buscar en la biblioteca de películas", x: 0, y: 0),
            block("Configuración de la cuenta", x: 0, y: 40)
        ]

        let dominant = await detector.dominantLanguage(for: blocks)
        let classified = await detector.classify(blocks, documentLanguage: dominant)
        let languages = Set(classified.map(\.sourceLanguage))
        let allNeedTranslation = classified.allSatisfy(\.needsTranslation)

        #expect(dominant == .spanish)
        #expect(languages == [.spanish])
        #expect(allNeedTranslation)
    }

    @Test("Spanish is translatable and carries the Spanish flag")
    func spanishMetadata() {
        #expect(SourceLanguage.spanish.isTranslatable)
        #expect(SourceLanguage.spanish.flagSymbol == "🇪🇸")
        #expect(SourceLanguage.spanish.localeLanguage?.languageCode?.identifier == "es")
    }

    @Test("Vision recognition identifiers include Spanish only when opted in")
    func recognitionIdentifiersHonourOptIn() {
        // Locale.Language normalises "de-DE" to a language code of "de" and a
        // region of "DE", so compare on the pieces rather than round-tripping
        // the string.
        func codes(_ ids: [Locale.Language]) -> Set<String> {
            Set(ids.compactMap { $0.languageCode?.identifier })
        }

        let base = codes(SourceLanguage.recognitionIdentifiers())
        #expect(base == ["de", "it", "en"])

        let extended = codes(SourceLanguage.recognitionIdentifiers(additional: [.spanish]))
        #expect(extended == ["de", "it", "en", "es"])
    }

    @Test("Translation coordinator language list respects the Spanish opt-in")
    func coordinatorLanguageListRespectsOptIn() {
        #expect(TranslationCoordinator.languages(includingSpanish: false) == [.german, .italian])
        #expect(
            TranslationCoordinator.languages(includingSpanish: true) == [.german, .italian, .spanish]
        )
    }
}
