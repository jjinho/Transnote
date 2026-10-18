import XCTest

final class LocalTranscriberUITests: XCTestCase {
    /// Launches the app in US English so element lookups by label do not depend on the Mac's language.
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    func testMainWindowLaunchesAndShowsEmptyState() {
        let app = launchApp()

        // The main window launches and shows the empty-state message
        XCTAssertTrue(app.staticTexts["Drop or select an audio file to start transcribing"].waitForExistence(timeout: 10))
    }

    func testExportMenuAvailableAfterEmptyState() {
        let app = launchApp()

        // The export menu exists (it exists even while disabled, since there is no text)
        XCTAssertTrue(app.menuButtons["Export transcription result"].waitForExistence(timeout: 10))
    }

    func testSettingsSheetOpensAndCloses() {
        let app = launchApp()

        // Given: the main screen is running (the settings button is always shown)
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 30))

        // If a crash-recovery alert is shown, discard and close it (caused by leftover data in the environment)
        let discardButton = app.sheets.buttons["action-button-2"]
        if discardButton.waitForExistence(timeout: 2) {
            discardButton.tap()
        }

        // When: the settings sheet is opened
        app.buttons["Settings"].firstMatch.tap()
        let closeButton = app.buttons["Close Settings"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10))
        XCTAssertTrue(closeButton.isHittable)

        // Then: the close button closes the settings sheet
        app.buttons["Close Settings"].tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 3))

        // The bottom close button is also operable without scrolling
        app.buttons["Settings"].firstMatch.tap()
        let footerCloseButton = app.sheets.buttons["Close"]
        XCTAssertTrue(footerCloseButton.waitForExistence(timeout: 10))
        XCTAssertTrue(footerCloseButton.isHittable)
        footerCloseButton.tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 3))

        // The sheet can also be closed with the Escape key
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 3))
    }
}
