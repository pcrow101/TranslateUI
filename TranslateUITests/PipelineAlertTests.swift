//
//  PipelineAlertTests.swift
//  TranslateUITests
//

import Foundation
import Testing
import Translation

@testable import TranslateUI

@MainActor
@Suite("Alerts and retry")
struct PipelineAlertTests {

    @Test("Posting the same alert twice keeps a single banner")
    func alertsAreDeduplicated() {
        let store = TestFixtures.store()

        store.post(.languageNeedsDownload(.german))
        store.post(.languageNeedsDownload(.german))
        store.post(.languageNeedsDownload(.italian))

        #expect(store.alerts.count == 2)
    }

    @Test("Dismissing removes only that banner")
    func dismissRemovesOne() {
        let store = TestFixtures.store()
        store.post(.languageNeedsDownload(.german))
        store.post(.translationsFailed(count: 3))

        store.dismiss(.languageNeedsDownload(.german))

        #expect(store.alerts.map(\.id) == [PipelineAlert.translationsFailed(count: 3).id])
    }

    @Test("A failed-translation banner is independent of the count")
    func failureBannerIsStable() {
        let store = TestFixtures.store()

        store.post(.translationsFailed(count: 2))
        store.post(.translationsFailed(count: 7))

        #expect(store.alerts.count == 1)
        #expect(store.alerts[0].title.contains("7"))
    }

    @Test("An unsupported pair reads as an error with a settings shortcut")
    func unsupportedAlertShape() {
        let alert = PipelineAlert.languageUnsupported(.italian)

        #expect(alert.severity == .error)
        #expect(alert.actions.contains(.openLanguageSettings))
        #expect(alert.title.contains("Italian"))
    }

    @Test("A download banner offers to trigger the download")
    func downloadAlertShape() {
        let alert = PipelineAlert.languageNeedsDownload(.german)

        #expect(alert.severity == .info)
        #expect(alert.actions.first == .downloadLanguage(.german))
    }

    @Test("Retrying resets failed blocks so they translate again")
    func retryResetsFailedBlocks() async {
        let store = TestFixtures.store()
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Abmelden", state: .failed(message: "Session ended")),
            TestFixtures.block("Suchen", translated: "Search", state: .translated)
        ])
        store.screenshots = [screenshot]
        store.post(.translationsFailed(count: 1))

        #expect(screenshot.blocks[0].canRetry)

        await store.retryFailedTranslations()

        #expect(screenshot.blocks[0].state == .pending)
        #expect(screenshot.blocks[0].needsTranslation)
        // The successful block is untouched.
        #expect(screenshot.blocks[1].translatedText == "Search")
        #expect(!store.alerts.contains { $0.id == PipelineAlert.translationsFailed(count: 0).id })
    }

    @Test("Retrying a single block only resets that one")
    func retrySingleBlock() async {
        let store = TestFixtures.store()
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Abmelden", state: .failed(message: "boom")),
            TestFixtures.block("Beenden", state: .failed(message: "boom"))
        ])
        store.screenshots = [screenshot]

        await store.retryTranslation(for: screenshot.blocks[0].id, in: screenshot)

        #expect(screenshot.blocks[0].state == .pending)
        #expect(screenshot.blocks[1].canRetry)
    }

    @Test("Language availability is recorded for both source languages")
    func availabilityIsRecorded() async {
        let store = TestFixtures.store()

        await store.refreshLanguageAvailability()

        #expect(store.languageStatuses[.german] != nil)
        #expect(store.languageStatuses[.italian] != nil)
    }
}
