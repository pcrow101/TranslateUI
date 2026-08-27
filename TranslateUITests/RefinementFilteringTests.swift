//
//  RefinementFilteringTests.swift
//  TranslateUITests
//

import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import TranslateUI

@Suite("Refinement filtering and clipboard")
@MainActor
struct RefinementFilteringTests {

    @Test("Supported source languages always include English")
    func supportedIncludesEnglish() {
        let supported = UIStringRefiner.supportedSourceLanguages
        // English is baked in because the refiner's own instructions are
        // English — it's always safe to hand it English source text.
        #expect(supported.contains(.english))
    }

    @Test("Refiner short-circuits when every item is in an unsupported language")
    func skipsWhenNothingIsSupported() async {
        // Craft a language that's guaranteed not to be in the supported set
        // by comparing against what the model actually reports. If, on the
        // running host, *every* SourceLanguage is supported, there's nothing
        // to test — skip cleanly.
        let supported = UIStringRefiner.supportedSourceLanguages
        let candidate = SourceLanguage.allCases.first {
            $0.isTranslatable && !supported.contains($0)
        }
        guard let unsupported = candidate else {
            // Every translatable language is supported on this host; the
            // filter has nothing to reject.
            return
        }

        let refiner = UIStringRefiner()
        let items = [
            UIStringRefiner.Item(
                id: UUID(),
                source: "Ejemplo",
                translation: "Example",
                sourceLanguage: unsupported
            )
        ]

        // If refinement is available it would normally hit Foundation Models;
        // filtering happens before that call, so an unsupported-only batch
        // returns an empty dictionary immediately.
        let result = await refiner.refine(items)
        #expect(result.isEmpty)
    }

    @Test("Clipboard copy writes to the given pasteboard")
    @MainActor
    func clipboardWriteBumpsChangeCount() throws {
        // Use a uniquely-named pasteboard so the user's real clipboard is
        // untouched.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("TranslateUITests-\(UUID().uuidString)"))
        let image = try #require(
            TestImageFactory.screen(
                lines: ["Copy me"], size: CGSize(width: 200, height: 80), fontSize: 20
            )
        )
        let before = pasteboard.changeCount
        let after = Pasteboard.write(image, to: pasteboard)
        #expect(after > before)

        // The pasteboard should now vend an image.
        let items = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)
        #expect(items?.first is NSImage)
    }
}
