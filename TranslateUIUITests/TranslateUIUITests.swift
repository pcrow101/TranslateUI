//
//  TranslateUIUITests.swift
//  TranslateUIUITests
//

import AppKit
import XCTest

/// End-to-end smoke test for the import → recognise → display → copy → export
/// flow.
///
/// The app is launched with `-uiTestFixture`, which imports a synthetic German
/// TV screen through the real import path. Translation itself is deliberately
/// *not* asserted: it depends on the German language pack being downloaded on
/// the host, which isn't guaranteed on a clean machine or in CI. Everything up
/// to and including the on-screen result and the export render is covered.
final class TranslateUIUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchWithFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            // Every one of these must be a key/value *pair*: a bare flag breaks
            // NSUserDefaults' argument pairing for everything after it.
            "-uiTestFixture", "YES",
            // Without this, macOS restores the "no windows" state saved when a
            // previous test run terminated the app, and nothing is ever shown.
            "-ApplePersistenceIgnoreState", "YES",
            // UserDefaults reads these, keeping the run fast and deterministic.
            "-settings.useModelRefinement", "0",
            "-settings.prewarmModel", "0"
        ]
        app.launch()
        return app
    }

    @MainActor
    func testShowsDropZoneWhenEmpty() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["dropZone.title"].waitForExistence(timeout: 15),
            "an empty window should invite the user to drop a screenshot"
        )
    }

    @MainActor
    func testImportedScreenshotIsRecognisedAndCopyable() throws {
        let app = launchWithFixture()

        // Vision should read the fixture's labels into the inspector.
        let recognised = app.staticTexts.matching(identifier: "inspector.translation")
        XCTAssertTrue(
            waitForCount(of: recognised, toBeAtLeast: 1, timeout: 45),
            "recognition should produce at least one line of text"
        )

        // Copying should put the recognised text on the pasteboard. Driven from
        // the menu rather than the toolbar, which collapses into an overflow
        // popup when the window is narrow.
        NSPasteboard.general.clearContents()
        XCTAssertTrue(clickMenuItem(named: "Copy All Translations", in: app))

        let copied = waitForPasteboardText(timeout: 10)
        XCTAssertFalse(copied.isEmpty, "Copy Text should place the translations on the pasteboard")
        XCTAssertTrue(
            copied.localizedCaseInsensitiveContains("Einstellungen")
                || copied.localizedCaseInsensitiveContains("settings"),
            "expected the fixture's first label, got: \(copied)"
        )
    }

    @MainActor
    func testExportProducesASavePanel() throws {
        let app = launchWithFixture()

        let recognised = app.staticTexts.matching(identifier: "inspector.translation")
        XCTAssertTrue(
            waitForCount(of: recognised, toBeAtLeast: 1, timeout: 45),
            "the screenshot must be analysed before it can be exported"
        )

        XCTAssertTrue(clickMenuItem(named: "Export Annotated Image…", in: app))

        // The panel only appears once the annotated image rendered successfully,
        // so this also covers the overlay render path.
        let savePanel = app.sheets.firstMatch
        XCTAssertTrue(
            savePanel.waitForExistence(timeout: 20),
            "exporting should present a save panel once the PNG has rendered"
        )

        // Leave the app in a clean state.
        let cancel = savePanel.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.click() }
    }

    // MARK: - Helpers

    /// Clicks a main-menu item by title, returning whether it was found.
    private func clickMenuItem(named title: String, in app: XCUIApplication) -> Bool {
        let item = app.menuBars.menuItems[title]
        guard item.waitForExistence(timeout: 10), item.isEnabled else { return false }
        item.click()
        return true
    }

    private func waitForCount(
        of query: XCUIElementQuery,
        toBeAtLeast minimum: Int,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count >= minimum { return true }
            usleep(200_000)
        }
        return false
    }

    private func waitForPasteboardText(timeout: TimeInterval) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                return text
            }
            usleep(200_000)
        }
        return ""
    }
}
