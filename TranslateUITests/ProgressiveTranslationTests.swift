//
//  ProgressiveTranslationTests.swift
//  TranslateUITests
//

import Foundation
import Testing
import Translation

@testable import TranslateUI

/// The streaming path must update blocks one at a time and only fail the ones
/// that never arrived.
@MainActor
@Suite("Progressive translation")
struct ProgressiveTranslationTests {

    @Test("A streamed result marks just that block as translated")
    func streamedResultUpdatesOneBlock() {
        let store = TestFixtures.store()
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Einstellungen", state: .translating),
            TestFixtures.block("Abmelden", state: .translating)
        ])
        store.screenshots = [screenshot]

        store.applyTranslation("Settings", to: screenshot.blocks[0].id, in: screenshot)

        #expect(screenshot.blocks[0].translatedText == "Settings")
        #expect(screenshot.blocks[0].state == .translated)
        #expect(screenshot.blocks[1].state == .translating, "the other block is still in flight")
    }

    @Test("Applying to a missing screenshot is harmless")
    func applyingWithoutOwnerIsSafe() {
        let store = TestFixtures.store()

        store.applyTranslation("Settings", to: UUID(), in: nil)

        #expect(store.screenshots.isEmpty)
    }

    @Test("A glossary term still wins over a streamed machine translation")
    func glossaryStillWinsAfterStreaming() {
        let store = TestFixtures.store()
        store.glossary.learn(sourceText: "Abmelden", language: .german, translation: "Sign Out")
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Abmelden", state: .translating)
        ])
        store.screenshots = [screenshot]

        store.applyTranslation("Log off", to: screenshot.blocks[0].id, in: screenshot)
        store.applyGlossary(to: screenshot)

        #expect(screenshot.blocks[0].displayText == "Sign Out")
        #expect(screenshot.blocks[0].translatedText == "Log off")
    }

    @Test("Both strategies map onto the framework")
    func strategyMapping() {
        #expect(TranslationStrategy.highFidelity.sessionStrategy == .highFidelity)
        #expect(TranslationStrategy.lowLatency.sessionStrategy == .lowLatency)
    }

    @Test("Performance preferences round-trip through UserDefaults")
    func performancePreferencesPersist() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!

        let first = AppSettings(defaults: defaults)
        #expect(first.translationStrategy == .highFidelity, "quality by default")
        #expect(first.prewarmModel)

        first.translationStrategy = .lowLatency
        first.prewarmModel = false

        let second = AppSettings(defaults: defaults)
        #expect(second.translationStrategy == .lowLatency)
        #expect(second.prewarmModel == false)
    }

    @Test("Prewarming is safe to call regardless of model availability")
    func prewarmIsSafe() async {
        let store = TestFixtures.store()

        await store.prewarm()

        #expect(store.languageStatuses[.german] != nil)
    }
}
