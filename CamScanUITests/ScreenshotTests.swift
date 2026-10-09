import XCTest

/// Walks through the main screens with sample documents and attaches a screenshot of each.
/// CI exports the attachments, so the screens can be reviewed without a device.
final class ScreenshotTests: XCTestCase {
    private let languages: [(code: String, locale: String)] = [("ru", "ru_RU"), ("en", "en_US")]

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testOnboarding() {
        for language in languages {
            let app = launch(language, seenOnboarding: false)
            XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 10))
            snapshot("\(language.code)-01-onboarding")
            app.terminate()
        }
    }

    @MainActor
    func testMainScreens() {
        for language in languages {
            let app = launch(language, seenOnboarding: true)

            // Seeding runs the real import pipeline, so give it time.
            let firstDocument = app.buttons.matching(identifier: "documentCard").firstMatch
            XCTAssertTrue(firstDocument.waitForExistence(timeout: 60), "No documents in the list")
            snapshot("\(language.code)-02-documents")

            firstDocument.tap()
            XCTAssertTrue(app.buttons["editPage"].waitForExistence(timeout: 10))
            snapshot("\(language.code)-03-document")

            if tapIfExists(app.buttons["shareMenu"]) {
                sleep(1)
                snapshot("\(language.code)-04-share")
                dismissMenu(in: app)
            }

            if tapIfExists(app.buttons["documentMenu"]) {
                sleep(1)
                snapshot("\(language.code)-04b-more")
                dismissMenu(in: app)
            }

            if tapIfExists(app.buttons["editPage"]) {
                XCTAssertTrue(app.buttons["cropTool"].waitForExistence(timeout: 10))
                sleep(3) // preview and filter thumbnails render
                snapshot("\(language.code)-05-editor")

                if tapIfExists(app.buttons["filter-B&W"]) {
                    sleep(2)
                    snapshot("\(language.code)-06-editor-bw")
                }

                if tapIfExists(app.buttons["cropTool"]) {
                    sleep(1)
                    snapshot("\(language.code)-07-crop")
                    app.navigationBars.buttons.firstMatch.tap() // Cancel
                }
                app.navigationBars.buttons.firstMatch.tap() // Cancel editor
            }

            app.navigationBars.buttons.firstMatch.tap() // Back to the list
            if tapIfExists(app.buttons["settingsButton"]) {
                sleep(1)
                snapshot("\(language.code)-08-settings")
                app.navigationBars.buttons.element(boundBy: app.navigationBars.buttons.count - 1).tap()
            }

            if tapIfExists(app.buttons["proButton"]) {
                sleep(1)
                snapshot("\(language.code)-09-paywall")
            }
            app.terminate()
        }
    }

    // MARK: - Helpers

    @MainActor
    private func launch(_ language: (code: String, locale: String), seenOnboarding: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestSeed",
            "-AppleLanguages", "(\(language.code))",
            "-AppleLocale", language.locale,
            "-hasSeenOnboarding", seenOnboarding ? "YES" : "NO",
            "-pdfPageSize", "a4",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func tapIfExists(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 5) else { return false }
        element.tap()
        return true
    }

    /// Taps empty space near the top so the open menu closes without choosing an item.
    @MainActor
    private func dismissMenu(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        sleep(1)
    }

    @MainActor
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
