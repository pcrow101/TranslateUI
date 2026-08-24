//
//  TestFixtures.swift
//  TranslateUITests
//

import CoreGraphics
import Foundation

@testable import TranslateUI

enum TestFixtures {
    /// A screenshot backed by a tiny rendered image, with hand-made blocks.
    @MainActor
    static func screenshot(
        name: String = "fixture",
        blocks: [TextBlock] = [],
        image: CGImage? = nil
    ) -> Screenshot {
        let cgImage =
            image ?? TestImageFactory.screen(
                lines: ["Fixture"],
                size: CGSize(width: 200, height: 80),
                fontSize: 20
            )!
        let screenshot = Screenshot(
            loaded: LoadedImage(
                name: name,
                sourceURL: nil,
                contentHash: UUID().uuidString,
                image: SendableImage(cgImage: cgImage)
            )
        )
        screenshot.blocks = blocks
        return screenshot
    }

    static func block(
        _ text: String,
        language: SourceLanguage = .german,
        translated: String? = nil,
        refined: String? = nil,
        user: String? = nil,
        isGlossaryMatch: Bool = false,
        state: TextBlock.TranslationState = .pending,
        y: CGFloat = 0
    ) -> TextBlock {
        TextBlock(
            sourceText: text,
            frame: CGRect(x: 0, y: y, width: 120, height: 24),
            confidence: 0.95,
            backgroundLuminance: 0.05,
            sourceLanguage: language,
            translatedText: translated,
            refinedText: refined,
            userText: user,
            isGlossaryMatch: isGlossaryMatch,
            state: state
        )
    }

    /// A store wired to throwaway storage so tests never touch real user data.
    @MainActor
    static func store(
        settings: AppSettings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
        glossary: Glossary = Glossary(fileURL: nil),
        screenCapture: (any ScreenCapturing)? = nil
    ) -> ScreenshotStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TranslateUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return ScreenshotStore(
            settings: settings,
            glossary: glossary,
            cache: ResultCache(directory: directory),
            screenCapture: screenCapture
        )
    }

    static func temporaryFileURL(_ name: String = "glossary.json") -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "TranslateUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: name)
    }
}
