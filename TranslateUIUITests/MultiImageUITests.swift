//
//  MultiImageUITests.swift
//  TranslateUIUITests
//

import AppKit
import XCTest

/// End-to-end cover for the reported bug: with several screenshots imported at
/// once, Italian ones were sometimes left untranslated.
///
/// This drives the real pipeline — Vision, the Translation framework and the
/// live `.translationTask` sessions — so it only produces a meaningful result
/// on a machine where the German and Italian language packs are installed. If
/// they aren't, the test skips rather than reporting a false failure.
@MainActor
final class MultiImageUITests: XCTestCase {

    /// Words that must not survive to the translated column.
    private let untranslatedItalian = ["Impostazioni", "Sottotitoli", "Riproduzione", "Preferiti", "Esci"]
    private let untranslatedGerman = ["Einstellungen", "Untertitel", "Wiedergabe", "Favoriten", "Beenden"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryScreenshotIsTranslatedWhenImportedTogether() throws {
        let screenshotCount = 8

        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestFixture", "YES",
            "-uiTestFixtureCount", "\(screenshotCount)",
            "-ApplePersistenceIgnoreState", "YES",
            // Numeric values matter: NSUserDefaults parses "NO" as a *string*,
            // which `object(forKey:) as? Bool` rejects, so the setting would
            // silently keep its default. Keeping refinement off also stops the
            // polishing pass rewriting the very strings this test checks for.
            "-settings.useModelRefinement", "0",
            "-settings.prewarmModel", "0"
        ]
        app.launch()

        // Every screenshot should be imported and analysed.
        let phases = app.staticTexts.matching(identifier: "sidebar.phase")
        XCTAssertTrue(
            waitFor(timeout: 120) { phases.count == screenshotCount },
            "expected \(screenshotCount) screenshots, saw \(phases.count)"
        )

        // Wait for the pipeline to settle on every row.
        XCTAssertTrue(
            waitFor(timeout: 180) { allValues(of: phases).allSatisfy { $0 == "Ready" } },
            "screenshots never finished: \(allValues(of: phases))"
        )

        try skipIfTranslationUnavailable(app)

        // Walk each screenshot and confirm nothing was left in the source
        // language. This is what regressed: the abandoned labels fell back to
        // displaying their original text.
        let rows = app.staticTexts.matching(identifier: "sidebar.name")
        var checked = 0

        for index in 0..<rows.count {
            let row = rows.element(boundBy: index)
            guard row.exists else { continue }
            let name = row.value as? String ?? row.label
            row.click()

            let translations = app.staticTexts.matching(identifier: "inspector.translation")
            XCTAssertTrue(
                waitFor(timeout: 20) { translations.count > 0 },
                "\(name) produced no recognised text"
            )

            let shown = allValues(of: translations)
            let leftovers = shown.filter { value in
                untranslatedItalian.contains(value) || untranslatedGerman.contains(value)
            }

            XCTAssertTrue(
                leftovers.isEmpty,
                "\(name) still shows untranslated source text: \(leftovers) (all: \(shown))"
            )
            checked += 1
        }

        XCTAssertEqual(checked, screenshotCount, "every screenshot should have been inspected")
    }

    /// Imports a second batch while the first is still being translated.
    ///
    /// That forces a live translation session to be re-armed, which is what
    /// crashed the app: the framework raises an uncatchable `fatalError` if a
    /// session is used after the view that vended it has gone. A crash here
    /// shows up as the app no longer running.
    @MainActor
    func testImportingWhileTranslatingDoesNotCrash() throws {
        let screenshotCount = 8

        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestFixture", "YES",
            "-uiTestFixtureCount", "\(screenshotCount)",
            // Second half arrives mid-translation.
            "-uiTestFixtureWave", "4",
            "-ApplePersistenceIgnoreState", "YES",
            "-settings.useModelRefinement", "0",
            "-settings.prewarmModel", "0"
        ]
        app.launch()

        let phases = app.staticTexts.matching(identifier: "sidebar.phase")
        XCTAssertTrue(
            waitFor(timeout: 120) { phases.count == screenshotCount },
            "expected \(screenshotCount) screenshots, saw \(phases.count)"
        )

        XCTAssertTrue(
            waitFor(timeout: 180) { allValues(of: phases).allSatisfy { $0 == "Ready" } },
            "screenshots never finished: \(allValues(of: phases))"
        )

        XCTAssertEqual(
            app.state, .runningForeground,
            "the app must survive a session being re-armed mid-translation"
        )

        try skipIfTranslationUnavailable(app)

        // And the interrupted batch must still have been translated.
        let rows = app.staticTexts.matching(identifier: "sidebar.name")
        for index in 0..<rows.count {
            let row = rows.element(boundBy: index)
            guard row.exists else { continue }
            let name = row.value as? String ?? row.label
            row.click()

            let translations = app.staticTexts.matching(identifier: "inspector.translation")
            XCTAssertTrue(waitFor(timeout: 20) { translations.count > 0 }, "\(name) has no text")

            let shown = allValues(of: translations)
            let leftovers = shown.filter { value in
                untranslatedItalian.contains(value) || untranslatedGerman.contains(value)
            }
            XCTAssertTrue(leftovers.isEmpty, "\(name) still shows source text: \(leftovers)")
        }
    }

    // MARK: - Helpers

    /// Skips the test when the language packs aren't installed, which the app
    /// surfaces as a "needs download" or "unavailable" banner.
    private func skipIfTranslationUnavailable(_ app: XCUIApplication) throws {
        let banners = app.staticTexts.allElementsBoundByIndex.compactMap { $0.value as? String }
        let blocked = banners.contains {
            $0.localizedCaseInsensitiveContains("download")
                || $0.localizedCaseInsensitiveContains("isn’t available")
                || $0.localizedCaseInsensitiveContains("isn't available")
        }
        try XCTSkipIf(blocked, "German/Italian language packs are not installed on this machine")
    }

    private func allValues(of query: XCUIElementQuery) -> [String] {
        query.allElementsBoundByIndex.compactMap { element in
            (element.value as? String) ?? element.label
        }
    }

    private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(300_000)
        }
        return condition()
    }
}
