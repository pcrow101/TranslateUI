//
//  ComponentTests.swift
//  TranslateUITests
//

import CoreGraphics
import Foundation
import Testing

@testable import TranslateUI

/// Covers the pieces that were split out of `ScreenshotStore`, each of which
/// can now be exercised without going through the view model.
@Suite("Extracted components")
struct ComponentTests {

    // MARK: - ScreenshotImporter

    @Test("Only decodable image types are imported")
    func filtersUnsupportedFiles() {
        let urls = [
            URL(fileURLWithPath: "/tmp/shot.png"),
            URL(fileURLWithPath: "/tmp/notes.txt"),
            URL(fileURLWithPath: "/tmp/clip.mov"),
            URL(fileURLWithPath: "/tmp/photo.jpeg")
        ]

        let supported = ScreenshotImporter.supportedURLs(in: urls).map(\.lastPathComponent)

        #expect(supported == ["shot.png", "photo.jpeg"])
    }

    @Test("One bad file doesn't abandon the rest of the batch")
    func reportsFailuresPerFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ImporterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let good = directory.appending(path: "good.png")
        let bad = directory.appending(path: "corrupt.png")
        let image = try #require(
            TestImageFactory.screen(
                lines: ["Einstellungen"], size: CGSize(width: 240, height: 80), fontSize: 24)
        )
        try #require(TestImageFactory.pngData(from: image)).write(to: good)
        try Data("this is not a png".utf8).write(to: bad)

        let outcome = await ScreenshotImporter().load(contentsOf: [bad, good])

        #expect(outcome.images.count == 1, "the readable file should still import")
        #expect(outcome.images.first?.name == "good")
        #expect(outcome.failures.count == 1)
        #expect(outcome.failures.first?.name == "corrupt.png")
    }

    @Test("Importing raw data yields a hashed image")
    func importsData() async throws {
        let image = try #require(
            TestImageFactory.screen(lines: ["Ton"], size: CGSize(width: 200, height: 80), fontSize: 24)
        )
        let data = try #require(TestImageFactory.pngData(from: image))

        let outcome = await ScreenshotImporter().load(data: data, name: "pasted")

        #expect(outcome.failures.isEmpty)
        #expect(outcome.images.first?.name == "pasted")
        #expect(outcome.images.first?.contentHash.isEmpty == false)
    }

    // MARK: - AlertCenter

    @Test("Re-posting the same alert updates it instead of stacking")
    @MainActor
    func alertsAreKeyedByIdentity() {
        let center = AlertCenter()

        center.post(.translationsFailed(count: 2))
        center.post(.translationsFailed(count: 9))
        center.post(.languageNeedsDownload(.german))

        #expect(center.alerts.count == 2)
        #expect(center.alerts.first?.title.contains("9") == true)
    }

    @Test("Dismissing removes only the matching alert")
    @MainActor
    func dismissesByIdentity() {
        let center = AlertCenter()
        center.post(.languageNeedsDownload(.german))
        center.post(.languageNeedsDownload(.italian))

        center.dismiss(.languageNeedsDownload(.german))

        #expect(center.alerts.count == 1)
        #expect(!center.contains(id: PipelineAlert.languageNeedsDownload(.german).id))
        #expect(center.contains(id: PipelineAlert.languageNeedsDownload(.italian).id))
    }

    // MARK: - TranslationCoordinator

    @Test("Nothing is armed when no block needs that language")
    @MainActor
    func reportsNoWork() async {
        let coordinator = TranslationCoordinator()
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Settings", language: .english)
        ])

        let readiness = await coordinator.prepare(.german, screenshots: [screenshot], strategy: .highFidelity)

        #expect(readiness == .noWork)
        #expect(coordinator.germanConfiguration == nil, "no session should be armed for idle languages")
    }

    @Test("Retrying clears failed blocks so the next pass picks them up")
    @MainActor
    func resetsFailures() {
        let coordinator = TranslationCoordinator()
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Abmelden", translated: "x", state: .failed(message: "boom")),
            TestFixtures.block("Zurück", translated: "Back", state: .translated)
        ])

        coordinator.resetFailures(in: [screenshot])

        #expect(screenshot.blocks[0].state == .pending)
        #expect(screenshot.blocks[0].translatedText == nil)
        #expect(screenshot.blocks[1].state == .translated, "successful blocks are left alone")
    }

    // MARK: - RecognitionPipeline

    @Test("Recognition and language classification run as one step")
    func analyzesAnImage() async throws {
        let image = try #require(
            TestImageFactory.screen(
                lines: ["Einstellungen", "Untertitel", "Wiedergabe fortsetzen"],
                size: CGSize(width: 900, height: 420),
                fontSize: 56
            )
        )

        let analysis = try await RecognitionPipeline().analyze(SendableImage(cgImage: image))

        #expect(!analysis.blocks.isEmpty, "the pipeline should find the rendered labels")
        #expect(analysis.documentLanguage == .german)
        #expect(analysis.blocks.allSatisfy { !$0.sourceText.isEmpty })
    }

    // MARK: - GlossaryCoordinator

    @Test("Remembered terms are replayed, manual edits are not overwritten")
    @MainActor
    func appliesGlossaryWithoutClobberingEdits() {
        let glossary = Glossary(fileURL: nil)
        glossary.learn(sourceText: "Abmelden", language: .german, translation: "Sign Out")
        glossary.learn(sourceText: "Zurück", language: .german, translation: "Back")

        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Abmelden", translated: "Log off"),
            TestFixtures.block("Zurück", translated: "Backwards", user: "Previous")
        ])

        GlossaryCoordinator(glossary: glossary).apply(to: screenshot)

        #expect(screenshot.blocks[0].displayText == "Sign Out")
        #expect(screenshot.blocks[0].isGlossaryMatch)
        #expect(screenshot.blocks[1].displayText == "Previous", "a hand-typed edit outranks the glossary")
    }

    @Test("Glossary examples are scoped to the screenshot")
    @MainActor
    func collectsRelevantExamples() {
        let glossary = Glossary(fileURL: nil)
        glossary.learn(sourceText: "Abmelden", language: .german, translation: "Sign Out")
        glossary.learn(sourceText: "Impostazioni", language: .italian, translation: "Settings")

        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Abmelden", translated: "Log off")
        ])

        let examples = GlossaryCoordinator(glossary: glossary).examples(for: screenshot)

        #expect(examples == ["Abmelden": "Sign Out"], "unrelated terms shouldn't be sent to the model")
    }

    // MARK: - Store removal

    @Test("Removing one screenshot keeps the others and moves the selection")
    @MainActor
    func removingOneKeepsOthers() async {
        // Guards the sidebar's trash button: the primary action must delete
        // only the selected screenshot, not the whole batch.
        let store = TestFixtures.store()
        let first = TestFixtures.screenshot(name: "First")
        let second = TestFixtures.screenshot(name: "Second")
        let third = TestFixtures.screenshot(name: "Third")
        store.screenshots = [first, second, third]
        store.selectionID = second.id

        store.remove(second)

        #expect(store.screenshots.map(\.name) == ["First", "Third"])
        // Something must stay selected so the detail pane doesn't blank out.
        #expect(store.selectionID != nil)
        #expect(store.selectionID != second.id)
    }

    @Test("Remove All wipes the sidebar")
    @MainActor
    func removeAllWipesEverything() {
        let store = TestFixtures.store()
        store.screenshots = [
            TestFixtures.screenshot(name: "One"),
            TestFixtures.screenshot(name: "Two")
        ]
        store.selectionID = store.screenshots.first?.id

        store.removeAll()

        #expect(store.screenshots.isEmpty)
        #expect(store.selectionID == nil)
    }
}
