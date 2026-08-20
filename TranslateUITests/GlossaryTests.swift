//
//  GlossaryTests.swift
//  TranslateUITests
//

import Foundation
import Testing

@testable import TranslateUI

@MainActor
@Suite("Glossary")
struct GlossaryTests {

    @Test("Lookup ignores case and surrounding whitespace")
    func lookupIsNormalised() {
        let glossary = Glossary(fileURL: nil)
        glossary.learn(sourceText: "Abmelden", language: .german, translation: "Sign Out")

        #expect(glossary.translation(for: "abmelden", language: .german) == "Sign Out")
        #expect(glossary.translation(for: "  ABMELDEN  ", language: .german) == "Sign Out")
        // Same word, different language is a different term.
        #expect(glossary.translation(for: "Abmelden", language: .italian) == nil)
    }

    @Test("Learning the same term twice updates it instead of duplicating")
    func learningTwiceUpdates() {
        let glossary = Glossary(fileURL: nil)
        glossary.learn(sourceText: "Zurück", language: .german, translation: "Backwards")
        glossary.learn(sourceText: "zurück", language: .german, translation: "Back")

        #expect(glossary.entries.count == 1)
        #expect(glossary.translation(for: "Zurück", language: .german) == "Back")
    }

    @Test("Empty or untranslatable input is rejected")
    func rejectsInvalidInput() {
        let glossary = Glossary(fileURL: nil)

        #expect(glossary.learn(sourceText: "  ", language: .german, translation: "Nope") == nil)
        #expect(glossary.learn(sourceText: "Exit", language: .german, translation: " ") == nil)
        #expect(glossary.learn(sourceText: "Exit", language: .english, translation: "Exit") == nil)
        #expect(glossary.isEmpty)
    }

    @Test("Terms survive a relaunch")
    func persistsToDisk() async throws {
        let url = TestFixtures.temporaryFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let first = Glossary(fileURL: url)
        first.learn(sourceText: "Einstellungen", language: .german, translation: "Settings")
        // Saving is debounced.
        try await Task.sleep(for: .milliseconds(600))

        let second = Glossary(fileURL: url)
        #expect(second.translation(for: "Einstellungen", language: .german) == "Settings")
    }

    @Test("Removing a term forgets it")
    func removalForgets() {
        let glossary = Glossary(fileURL: nil)
        glossary.learn(sourceText: "Suchen", language: .german, translation: "Search")
        let entry = try! #require(glossary.entry(for: "Suchen", language: .german))

        glossary.remove(entry)

        #expect(glossary.translation(for: "Suchen", language: .german) == nil)
        #expect(glossary.isEmpty)
    }
}

@MainActor
@Suite("Glossary applied to screenshots")
struct GlossaryApplicationTests {

    @Test("Remembered terms replace the machine translation")
    func glossaryOverridesMachineTranslation() {
        let store = TestFixtures.store()
        store.glossary.learn(sourceText: "Abmelden", language: .german, translation: "Sign Out")

        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Abmelden", translated: "Log off", state: .translated)
        ])
        store.applyGlossary(to: screenshot)

        let block = screenshot.blocks[0]
        #expect(block.displayText == "Sign Out")
        #expect(block.isGlossaryMatch)
        #expect(block.translatedText == "Log off", "the machine output is kept for reference")
    }

    @Test("Editing a translation teaches it to every screenshot")
    func editingTeachesGlossary() {
        let store = TestFixtures.store()
        let edited = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Abmelden", translated: "Log off", state: .translated)
        ])
        let other = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Abmelden", translated: "Log off", state: .translated)
        ])
        store.screenshots = [edited, other]

        store.setTranslation(
            "Sign Out",
            for: edited.blocks[0].id,
            in: edited,
            rememberInGlossary: true
        )

        #expect(edited.blocks[0].displayText == "Sign Out")
        #expect(edited.blocks[0].isManuallyEdited)
        #expect(other.blocks[0].displayText == "Sign Out", "the term propagates to other screenshots")
        #expect(other.blocks[0].isGlossaryMatch)
        #expect(store.glossary.entries.count == 1)
    }

    @Test("Editing without remembering is local to that screenshot")
    func editingWithoutRememberStaysLocal() {
        let store = TestFixtures.store()
        let edited = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Beenden", translated: "Finish", state: .translated)
        ])
        let other = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Beenden", translated: "Finish", state: .translated)
        ])
        store.screenshots = [edited, other]

        store.setTranslation("Quit", for: edited.blocks[0].id, in: edited, rememberInGlossary: false)

        #expect(edited.blocks[0].displayText == "Quit")
        #expect(other.blocks[0].displayText == "Finish")
        #expect(store.glossary.isEmpty)
    }

    @Test("A manual edit is never overwritten by the glossary")
    func manualEditWinsOverGlossary() {
        let store = TestFixtures.store()
        store.glossary.learn(sourceText: "Zurück", language: .german, translation: "Back")

        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Zurück", translated: "Backwards", state: .translated)
        ])
        store.screenshots = [screenshot]
        store.setTranslation(
            "Previous", for: screenshot.blocks[0].id, in: screenshot, rememberInGlossary: false)

        store.applyGlossary(to: screenshot)

        #expect(screenshot.blocks[0].displayText == "Previous")
    }

    @Test("Resetting falls back to the machine translation")
    func resetRestoresMachineTranslation() {
        let store = TestFixtures.store()
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block(
                "Untertitel", translated: "Subtitles", refined: "Subtitles & Captions", state: .translated)
        ])
        store.screenshots = [screenshot]
        store.setTranslation("Subs", for: screenshot.blocks[0].id, in: screenshot, rememberInGlossary: false)
        #expect(screenshot.blocks[0].displayText == "Subs")

        store.resetTranslation(for: screenshot.blocks[0].id, in: screenshot)

        #expect(screenshot.blocks[0].displayText == "Subtitles & Captions")
        #expect(screenshot.blocks[0].userText == nil)
    }

    @Test("Removing a term reverts screenshots that used it")
    func removingTermReverts() {
        let store = TestFixtures.store()
        store.glossary.learn(sourceText: "Startseite", language: .german, translation: "Home Screen")
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Startseite", translated: "Home page", state: .translated)
        ])
        store.screenshots = [screenshot]
        store.applyGlossary(to: screenshot)
        #expect(screenshot.blocks[0].displayText == "Home Screen")

        let entry = try! #require(store.glossary.entry(for: "Startseite", language: .german))
        store.removeGlossaryEntry(entry)

        #expect(screenshot.blocks[0].displayText == "Home page")
        #expect(screenshot.blocks[0].isGlossaryMatch == false)
    }

    @Test("Display precedence: user, then refined, then translated, then source")
    func displayPrecedence() {
        var block = TestFixtures.block("Fortsetzen")
        #expect(block.displayText == "Fortsetzen")

        block.translatedText = "Continue"
        #expect(block.displayText == "Continue")

        block.refinedText = "Resume"
        #expect(block.displayText == "Resume")

        block.userText = "Keep Watching"
        #expect(block.displayText == "Keep Watching")
        #expect(block.machineText == "Resume")
    }
}
