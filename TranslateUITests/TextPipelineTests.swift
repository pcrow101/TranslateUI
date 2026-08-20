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
}
