//
//  HelpUITests.swift
//  TranslateUIUITests
//

import XCTest

/// Covers the Help menu and the help book window.
@MainActor
final class HelpUITests: XCTestCase {

    /// Kept in step with `HelpContent.topics` by `HelpContentTests`.
    private static let topicCount = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-settings.prewarmModel", "0"
        ]
        app.launch()
        app.activate()
        // Menu clicks are rejected unless the app is genuinely frontmost.
        _ = app.wait(for: .runningForeground, timeout: 15)
        return app
    }

    /// Clicks a Help menu item, making sure the app is frontmost first.
    @discardableResult
    private func clickHelpItem(_ title: String, in app: XCUIApplication) -> Bool {
        app.activate()
        let item = app.menuBars.menuItems[title].firstMatch
        guard item.waitForExistence(timeout: 15) else { return false }
        guard waitFor(timeout: 10, { app.state == .runningForeground }) else { return false }
        item.click()
        return true
    }

    private func helpWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows["Translate UI Help"]
    }

    @MainActor
    func testHelpMenuOpensTheHelpBook() throws {
        let app = launch()

        XCTAssertTrue(
            clickHelpItem("Translate UI Help", in: app), "the Help menu should offer app help")

        let window = helpWindow(app)
        XCTAssertTrue(window.waitForExistence(timeout: 15), "the help window should open")

        // Every topic is listed…
        let rows = window.outlines["help.topicList"].outlineRows
        XCTAssertTrue(
            waitFor(timeout: 10) { rows.count == HelpUITests.topicCount },
            "expected \(HelpUITests.topicCount) topics, saw \(rows.count)"
        )

        // …and the book opens on the first one.
        XCTAssertEqual(
            window.staticTexts["help.title"].firstMatch.value as? String,
            "Getting Started"
        )
    }

    @MainActor
    func testHelpMenuJumpsStraightToATopic() throws {
        let app = launch()

        XCTAssertTrue(clickHelpItem("Keyboard Shortcuts", in: app))

        let window = helpWindow(app)
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        let title = window.staticTexts["help.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitFor(timeout: 10) { title.value as? String == "Keyboard Shortcuts" },
            "help should open on the topic the menu asked for, saw \(String(describing: title.value))"
        )

        // The page really is the shortcut reference.
        XCTAssertTrue(window.staticTexts["⇧⌘C"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testSearchingFiltersTopics() throws {
        let app = launch()

        XCTAssertTrue(clickHelpItem("Translate UI Help", in: app))
        let window = helpWindow(app)
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        let rows = window.outlines["help.topicList"].outlineRows
        XCTAssertTrue(waitFor(timeout: 10) { rows.count == HelpUITests.topicCount })

        let field = window.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "help should be searchable")
        field.click()
        field.typeText("shortcut")

        // Only the shortcuts topic mentions the word.
        XCTAssertTrue(
            waitFor(timeout: 10) { rows.count == 1 },
            "searching should narrow the list, saw \(rows.count) topics"
        )

        rows.element(boundBy: 0).click()
        XCTAssertTrue(
            waitFor(timeout: 10) {
                window.staticTexts["help.title"].firstMatch.value as? String == "Keyboard Shortcuts"
            },
            "the remaining result should be the shortcuts topic"
        )
    }

    @MainActor
    func testEmptyStateOffersHelp() throws {
        let app = launch()

        let link = app.descendants(matching: .any).matching(identifier: "dropZone.help").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 15), "the empty state should offer help")
        link.click()

        XCTAssertTrue(
            helpWindow(app).waitForExistence(timeout: 15),
            "the empty state help link should open the help book"
        )
    }

    // MARK: - Helpers

    private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }
}
