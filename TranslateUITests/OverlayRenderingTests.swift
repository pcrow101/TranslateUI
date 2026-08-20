//
//  OverlayRenderingTests.swift
//  TranslateUITests
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import TranslateUI

/// Regression tests for the overlay chips.
///
/// The canvas is rendered to a bitmap and read back with Vision, which proves
/// the translated text is actually visible rather than clipped to the height of
/// the recognised line (the "blank highlighted lines" bug).
@MainActor
@Suite("Overlay rendering")
struct OverlayRenderingTests {

    private func makeScreenshot(lines: [String], fontSize: CGFloat) async throws -> Screenshot {
        let image = try #require(TestImageFactory.screen(lines: lines, fontSize: fontSize))
        let screenshot = Screenshot(
            loaded: LoadedImage(
                name: "fixture",
                sourceURL: nil,
                contentHash: UUID().uuidString,
                image: SendableImage(cgImage: image)
            )
        )
        let blocks = try await TextRecognitionService().recognizeText(in: screenshot.image)
        screenshot.blocks = blocks.map { block in
            var block = block
            block.sourceLanguage = .german
            block.translatedText = "Continue Watching"
            block.state = .translated
            return block
        }
        return screenshot
    }

    private func renderedText(for screenshot: Screenshot, showsOriginal: Bool) async throws -> String {
        let canvas = ScreenshotCanvas(
            screenshot: screenshot,
            selectedBlockID: .constant(nil),
            showsOriginal: showsOriginal,
            isInteractive: false
        )
        .frame(width: screenshot.pixelSize.width, height: screenshot.pixelSize.height)

        let data = try #require(ScreenshotExporter.pngData(for: canvas))
        let rendered = try await ImageLoader.load(data: data, name: "rendered")
        let blocks = try await TextRecognitionService().recognizeText(in: rendered.image)
        return blocks.map(\.sourceText).joined(separator: " ")
    }

    @Test("Chips draw the translated text over the screenshot")
    func chipsDrawTranslations() async throws {
        let screenshot = try await makeScreenshot(lines: ["Wiedergabe fortsetzen"], fontSize: 46)
        #expect(!screenshot.blocks.isEmpty)

        let text = try await renderedText(for: screenshot, showsOriginal: false)

        #expect(text.contains("Continue"))
    }

    @Test("Show Original draws the source text as well as the translation")
    func showOriginalDrawsBothLines() async throws {
        let screenshot = try await makeScreenshot(lines: ["Wiedergabe fortsetzen"], fontSize: 46)

        let text = try await renderedText(for: screenshot, showsOriginal: true)

        #expect(text.contains("Continue"))
        #expect(text.contains("Wiedergabe"))
    }

    @Test("Small interface labels still render legible chips")
    func smallLabelsStayLegible() async throws {
        let screenshot = try await makeScreenshot(lines: ["Einstellungen"], fontSize: 18)

        let text = try await renderedText(for: screenshot, showsOriginal: false)

        #expect(text.contains("Continue"))
    }

    @Test("A remembered glossary term is what actually gets drawn")
    func glossaryTermIsRendered() async throws {
        let store = TestFixtures.store()
        store.glossary.learn(
            sourceText: "Wiedergabe fortsetzen", language: .german, translation: "Keep Watching")

        let screenshot = try await makeScreenshot(lines: ["Wiedergabe fortsetzen"], fontSize: 46)
        store.screenshots = [screenshot]
        store.applyGlossary(to: screenshot)

        let text = try await renderedText(for: screenshot, showsOriginal: false)

        let allMatched = screenshot.blocks.allSatisfy(\.isGlossaryMatch)
        #expect(text.contains("Keep Watching"))
        #expect(allMatched)
    }

    @Test("Chip type size follows the recognised line height")
    func fontSizeTracksLineHeight() {
        #expect(ScreenshotCanvas.fontSize(forLineHeight: 40) > ScreenshotCanvas.fontSize(forLineHeight: 16))
        // Never so small that it disappears, never larger than a heading.
        #expect(ScreenshotCanvas.fontSize(forLineHeight: 2) >= 9)
        #expect(ScreenshotCanvas.fontSize(forLineHeight: 400) <= 48)
    }
}
