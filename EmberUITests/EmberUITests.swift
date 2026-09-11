import XCTest

@MainActor final class EmberUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let appearance = extra.contains("dark") ? "dark" : "light"
        app.launchArguments = ["--ui-testing", "-appearance", appearance, "-selectedFeed", "top", "-hideReadStories", "NO", "-compactRows", "NO"] + extra.filter { !["-appearance", "dark", "light"].contains($0) }
        app.launch()
        return app
    }

    func testReadSaveAndRestoreBookmark() {
        let app = launch()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        app.buttons["story-1001"].tap()
        XCTAssertTrue(app.buttons["bookmark-story"].waitForExistence(timeout: 5))
        app.buttons["bookmark-story"].tap()
        XCTAssertEqual(app.buttons["bookmark-story"].label, "Remove bookmark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 5))
        app.terminate()
        let restored = launch(["--preserve-state"])
        restored.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(restored.buttons["story-1001"].waitForExistence(timeout: 5))
    }

    func testSearchAndEmptyResults() {
        let app = launch()
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("synthesizer")
        XCTAssertTrue(app.buttons["story-1003"].waitForExistence(timeout: 5))
        field.buttons["Clear text"].tap(); field.typeText("zzzznomatch")
        XCTAssertTrue(app.staticTexts["No results"].waitForExistence(timeout: 5))
    }

    func testThreadCollapseAndReplyExpansion() {
        let app = launch()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        app.buttons["story-1001"].tap()
        XCTAssertTrue(app.buttons["collapse-2001"].waitForExistence(timeout: 5))
        app.buttons["collapse-2001"].tap()
        XCTAssertEqual(app.buttons["collapse-2001"].label, "Expand comment by alex")
        app.buttons["collapse-2001"].tap()
        let replies = app.buttons["replies-2001"]
        if !replies.isHittable { app.swipeUp() }
        replies.tap()
        XCTAssertTrue(app.staticTexts["comment-text-3001"].waitForExistence(timeout: 5))
    }

    func testOfflineFeedSurvivesRelaunch() {
        let app = launch()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        app.terminate()
        let offline = launch(["--preserve-state", "--offline"])
        XCTAssertTrue(offline.buttons["story-1001"].waitForExistence(timeout: 10))
        XCTAssertTrue(offline.staticTexts["You’re offline. Check your connection and try again."].waitForExistence(timeout: 5))
    }

    func testAppearanceAndAccessibility() throws {
        let app = launch(["-appearance", "dark"])
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription]) { issue in
                // iOS fades scroll content behind the floating tab bar. Audit
                // fully visible content, not partially obscured offscreen rows.
                guard issue.auditType == .contrast, let element = issue.element else { return false }
                let frame = element.frame
                let tabBar = app.tabBars.firstMatch
                guard tabBar.exists, !frame.isEmpty,
                      tabBar.frame.minY > app.frame.midY else { return false }
                return frame.maxY > tabBar.frame.minY
            }
        }
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Compact stories"].waitForExistence(timeout: 5))
    }

    func testCaptureScreenshots() {
        let app = launch()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        attach(app, name: "01-Stories-Light")
        app.buttons["story-1001"].tap()
        XCTAssertTrue(app.buttons["collapse-2001"].waitForExistence(timeout: 5))
        attach(app, name: "02-Discussion-Light")
        app.buttons["bookmark-story"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Saved"].tap()
        attach(app, name: "03-Saved-Light")
        app.terminate()
        let dark = launch(["-appearance", "dark"])
        XCTAssertTrue(dark.buttons["story-1001"].waitForExistence(timeout: 10))
        attach(dark, name: "04-Stories-Dark")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
