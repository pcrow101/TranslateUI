//
//  MultiImageTranslationTests.swift
//  TranslateUITests
//

import Foundation
import Testing

@testable import TranslateUI

/// Regression cover for translations being dropped when several screenshots
/// are imported at once.
///
/// Each import analyses on its own task, so every screenshot that finishes
/// recognition used to re-arm the session. Re-arming invalidates the
/// configuration, which cancels the in-flight `.translationTask` — and the
/// abandoned labels were marked `.failed`, a state no later pass picks up. The
/// language armed last in each pass (Italian) lost the race most often.
@Suite("Multi-image translation")
@MainActor
struct MultiImageTranslationTests {

    private func italianScreenshot(_ text: String = "Impostazioni") -> Screenshot {
        TestFixtures.screenshot(blocks: [TestFixtures.block(text, language: .italian)])
    }

    // MARK: - The state machine that caused the bug

    @Test("A failed block is never picked up by a later pass")
    func failedBlocksAreNotRetriedAutomatically() {
        let screenshot = italianScreenshot()
        screenshot.update(blockID: screenshot.blocks[0].id) {
            $0.state = .failed(message: "cancelled")
        }

        #expect(!screenshot.blocks[0].needsTranslation)
        #expect(screenshot.untranslatedBlocks(in: .italian).isEmpty)
        #expect(
            screenshot.blocks[0].canRetry,
            "only an explicit retry recovers it, which is why cancellation must not mark blocks failed"
        )
    }

    @Test("A pending block is eligible for the next pass")
    func pendingBlocksAreEligible() {
        let screenshot = italianScreenshot()

        #expect(screenshot.blocks[0].needsTranslation)
        #expect(screenshot.untranslatedBlocks(in: .italian).count == 1)
    }

    // MARK: - Cancellation returns work to the queue

    @Test("Cancelled work goes back to pending, not failed")
    func cancelledWorkReturnsToQueue() {
        let coordinator = TranslationCoordinator()
        let screenshot = italianScreenshot()
        screenshot.update(blockID: screenshot.blocks[0].id) { $0.state = .translating }

        let returned = coordinator.returnUnfinishedWork(for: .italian, in: [screenshot])

        #expect(returned == 1)
        #expect(screenshot.blocks[0].state == .pending)
        #expect(
            screenshot.blocks[0].needsTranslation,
            "the label must be eligible for the next session"
        )
    }

    @Test("Returning work leaves finished and failed labels alone")
    func returningWorkOnlyTouchesInFlightLabels() {
        let coordinator = TranslationCoordinator()
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Impostazioni", language: .italian, state: .translating),
            TestFixtures.block(
                "Sottotitoli", language: .italian, translated: "Subtitles", state: .translated),
            TestFixtures.block("Audio", language: .italian, state: .failed(message: "boom"))
        ])

        let returned = coordinator.returnUnfinishedWork(for: .italian, in: [screenshot])

        #expect(returned == 1)
        #expect(screenshot.blocks[0].state == .pending)
        #expect(screenshot.blocks[1].state == .translated)
        #expect(screenshot.blocks[2].state == .failed(message: "boom"))
    }

    @Test("Only the requested language is returned to the queue")
    func returningWorkIsScopedToOneLanguage() {
        let coordinator = TranslationCoordinator()
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Impostazioni", language: .italian, state: .translating),
            TestFixtures.block("Einstellungen", language: .german, state: .translating)
        ])

        coordinator.returnUnfinishedWork(for: .italian, in: [screenshot])

        #expect(screenshot.blocks[0].state == .pending)
        #expect(screenshot.blocks[1].state == .translating, "the German batch is still running")
    }

    // MARK: - A second import must not cancel a running batch

    @Test("Preparing a language mid-batch defers instead of re-arming")
    func prepareDefersWhileRunning() async {
        let coordinator = TranslationCoordinator()
        let first = italianScreenshot()
        let second = italianScreenshot("Sottotitoli")

        // First screenshot arms Italian and its batch starts running.
        coordinator.beginRun(.italian)

        // The second screenshot finishes recognition while that batch is live.
        let readiness = await coordinator.prepare(
            .italian,
            screenshots: [first, second],
            strategy: .highFidelity
        )

        #expect(readiness == .busy)
        #expect(
            coordinator.italianConfiguration == nil,
            "arming here would invalidate the configuration and cancel the running session"
        )
    }

    @Test("Preparing again during the download window defers instead of re-arming")
    func prepareDefersWhileArmedWaitingForSession() async {
        // Simulates the freeze the user reported: a language pack is
        // downloading (session was armed but `.translationTask` hasn't started
        // running yet), and a second screenshot's recognition finishes.
        // Re-arming here would invalidate the configuration and cancel the
        // in-flight `prepareTranslation()`, triggering an infinite loop.
        let coordinator = TranslationCoordinator()
        let first = italianScreenshot()
        let second = italianScreenshot("Sottotitoli")

        // Simulate arming without the run having started yet.
        coordinator.beginRun(.italian)
        coordinator.endRun(.italian)
        // The above balances `runningLanguages`; now mark armed by driving
        // through the public path: first arm produces `.ready` or
        // `.needsDownload` and sets the armed flag.
        _ = await coordinator.prepare(.italian, screenshots: [first], strategy: .highFidelity)
        #expect(coordinator.isArmed(.italian))

        // A second prepare while still armed must not re-arm.
        let readiness = await coordinator.prepare(
            .italian,
            screenshots: [first, second],
            strategy: .highFidelity
        )
        #expect(readiness == .busy)
        #expect(coordinator.takeDeferredRequest(for: .italian))
    }

    @Test("Starting a run clears the armed flag")
    func beginRunClearsArmed() async {
        let coordinator = TranslationCoordinator()
        let screenshot = italianScreenshot()
        _ = await coordinator.prepare(.italian, screenshots: [screenshot], strategy: .highFidelity)
        #expect(coordinator.isArmed(.italian))

        coordinator.beginRun(.italian)
        #expect(!coordinator.isArmed(.italian))
        #expect(coordinator.isRunning(.italian))

        coordinator.endRun(.italian)
        #expect(!coordinator.isRunning(.italian))
        #expect(!coordinator.isArmed(.italian))
    }

    @Test("The deferred request is remembered exactly once")
    func deferredRequestIsConsumedOnce() async {
        let coordinator = TranslationCoordinator()
        let screenshot = italianScreenshot()

        coordinator.beginRun(.italian)
        _ = await coordinator.prepare(.italian, screenshots: [screenshot], strategy: .highFidelity)
        coordinator.endRun(.italian)

        #expect(coordinator.takeDeferredRequest(for: .italian))
        #expect(!coordinator.takeDeferredRequest(for: .italian), "the flag is consumed")
        #expect(!coordinator.takeDeferredRequest(for: .german), "languages are tracked separately")
    }

    @Test("A language with no running batch is not deferred")
    func idleLanguageIsNotDeferred() async {
        let coordinator = TranslationCoordinator()
        let screenshot = italianScreenshot()
        coordinator.beginRun(.german)
        let readiness = await coordinator.prepare(
            .italian,
            screenshots: [screenshot],
            strategy: .highFidelity
        )

        #expect(readiness != .busy, "a German batch must not block Italian")
    }

    @Test("Work outstanding across several screenshots is detected")
    func hasWorkSpansEveryScreenshot() {
        let coordinator = TranslationCoordinator()
        let done = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Impostazioni", language: .italian, translated: "Settings", state: .translated)
        ])
        let waiting = italianScreenshot("Sottotitoli")

        #expect(!coordinator.hasWork(for: .italian, in: [done]))
        #expect(coordinator.hasWork(for: .italian, in: [done, waiting]))
        #expect(!coordinator.hasWork(for: .german, in: [done, waiting]))
    }

    // MARK: - Failures must never be cached

    @Test("A failed label is not settled, so it is never cached")
    func failedLabelsAreNotCacheable() {
        let failed = TestFixtures.block("Impostazioni", language: .italian, state: .failed(message: "x"))
        let inFlight = TestFixtures.block("Sottotitoli", language: .italian, state: .translating)
        let waiting = TestFixtures.block("Riproduzione", language: .italian, state: .pending)

        #expect(!failed.isSettled)
        #expect(!inFlight.isSettled)
        #expect(!waiting.isSettled, "a translatable label still waiting isn't a final result")
    }

    @Test("Finished labels are cacheable")
    func finishedLabelsAreCacheable() {
        let translated = TestFixtures.block(
            "Impostazioni", language: .italian, translated: "Settings", state: .translated)
        let skipped = TestFixtures.block(
            "Impostazioni", language: .italian, state: .skipped(reason: "unavailable"))
        let english = TestFixtures.block("Settings", language: .english)

        #expect(translated.isSettled)
        #expect(skipped.isSettled)
        #expect(english.isSettled, "English is passed through, so it needs nothing further")
    }

    @Test("Reviving a cached failure makes it eligible again")
    func revivingRestoresEligibility() {
        let failed = TestFixtures.block("Impostazioni", language: .italian, state: .failed(message: "x"))

        let revived = failed.revivedForRetry()

        #expect(revived.state == .pending)
        #expect(revived.needsTranslation, "the next pass must pick it up")
        #expect(revived.id == failed.id)
        #expect(revived.sourceText == failed.sourceText)
    }

    @Test("Reviving leaves a finished translation untouched")
    func revivingKeepsGoodResults() {
        let done = TestFixtures.block(
            "Impostazioni", language: .italian, translated: "Settings", state: .translated)

        let revived = done.revivedForRetry()

        #expect(revived.state == .translated)
        #expect(revived.translatedText == "Settings")
    }

    @Test("A cached failure is revived instead of replayed")
    func cachedFailureIsRevivedOnLoad() async {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MultiImageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cache = ResultCache(directory: directory)
        let store = ScreenshotStore(
            settings: AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            glossary: Glossary(fileURL: nil),
            cache: cache
        )
        let screenshot = TestFixtures.screenshot(blocks: [])

        // Simulate a cache written by an interrupted run.
        await cache.store(
            ResultCache.Entry(
                signature: store.pipelineSignature,
                documentLanguage: .italian,
                blocks: [
                    TestFixtures.block("Impostazioni", language: .italian, state: .failed(message: "boom"))
                ]
            ),
            for: screenshot.contentHash
        )

        await store.analyze(screenshot)

        #expect(screenshot.blocks.count == 1, "the cached entry should still be used")
        #expect(
            screenshot.blocks[0].state == .pending,
            "a cached failure must come back retryable, not permanently failed"
        )
        #expect(screenshot.blocks[0].needsTranslation)
    }

    @Test("Run state is tracked per language")
    func runStateIsPerLanguage() {
        let coordinator = TranslationCoordinator()

        coordinator.beginRun(.italian)
        #expect(coordinator.isRunning(.italian))
        #expect(!coordinator.isRunning(.german))

        coordinator.endRun(.italian)
        #expect(!coordinator.isRunning(.italian))
    }
}
