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
        selectTab("Saved", in: app)
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 5))
        app.terminate()
        let restored = launch(["--preserve-state"])
        selectTab("Saved", in: restored)
        XCTAssertTrue(restored.buttons["story-1001"].waitForExistence(timeout: 5))
    }

    func testSearchAndEmptyResults() {
        let app = launch()
        selectTab("Search", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("synthesizer")
        XCTAssertTrue(app.buttons["story-1003"].waitForExistence(timeout: 5))
        field.buttons["Clear text"].tap()
        field.tap()
        field.typeText("zzzznomatch")
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
        selectTab("Settings", in: app)
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
        selectTab("Saved", in: app)
        attach(app, name: "03-Saved-Light")
        app.terminate()
        let dark = launch(["-appearance", "dark"])
        XCTAssertTrue(dark.buttons["story-1001"].waitForExistence(timeout: 10))
        attach(dark, name: "04-Stories-Dark")
    }

    func testAuditMainFlows() {
        let app = launch()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        attach(app, name: "Audit-01-Stories")
        app.buttons["feed-menu"].tap()
        attach(app, name: "Audit-02-Feed-Menu")
        app.buttons["Ask HN"].firstMatch.tap()
        XCTAssertTrue(app.buttons["story-1004"].waitForExistence(timeout: 5))
        app.buttons["story-1004"].tap()
        XCTAssertTrue(app.buttons["bookmark-story"].waitForExistence(timeout: 5))
        attach(app, name: "Audit-03-Text-Post")
        selectTab("Search", in: app)
        attach(app, name: "Audit-04-Search-Empty")
        let field = app.searchFields.firstMatch
        field.tap(); field.typeText("synthesizer\n")
        XCTAssertTrue(app.buttons["story-1003"].waitForExistence(timeout: 5))
        attach(app, name: "Audit-05-Search-Results")
        app.buttons["Search filters"].tap()
        attach(app, name: "Audit-06-Search-Filters")
        // Relaunch keeps each capture route independent of popover dismissal.
        app.terminate()
        let collections = launch()
        selectTab("Saved", in: collections)
        attach(collections, name: "Audit-07-Saved-Empty")
        collections.buttons["History"].tap()
        attach(collections, name: "Audit-08-History-Empty")
        selectTab("Settings", in: collections)
        attach(collections, name: "Audit-09-Settings")
        collections.swipeUp()
        attach(collections, name: "Audit-10-Settings-Lower")
        reveal(collections.buttons["Help & support"], in: collections)
        collections.buttons["Help & support"].tap()
        attach(collections, name: "Audit-11-Help")
        collections.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(collections.buttons["Privacy"], in: collections)
        collections.buttons["Privacy"].tap()
        attach(collections, name: "Audit-12-Privacy")
        collections.terminate()
        let discussion = launch()
        XCTAssertTrue(discussion.buttons["story-1001"].waitForExistence(timeout: 10))
        discussion.buttons["story-1001"].tap()
        XCTAssertTrue(discussion.buttons["collapse-2001"].waitForExistence(timeout: 5))
        attach(discussion, name: "Audit-13-Discussion")
        let replies = discussion.buttons["replies-2001"]
        reveal(replies, in: discussion); replies.tap()
        XCTAssertTrue(discussion.staticTexts["comment-text-3001"].waitForExistence(timeout: 5))
        attach(discussion, name: "Audit-14-Replies")
        discussion.terminate()
        let offline = launch(["--offline"])
        XCTAssertTrue(offline.staticTexts["You’re offline. Check your connection and try again."].waitForExistence(timeout: 10))
        attach(offline, name: "Audit-15-Offline-Empty")
    }

    func testAuditLargeText() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        attach(app, name: "Audit-16-Large-Text-Feed")
        app.buttons["story-1001"].tap()
        XCTAssertTrue(app.buttons["bookmark-story"].waitForExistence(timeout: 5))
        attach(app, name: "Audit-17-Large-Text-Discussion")
        app.swipeUp()
        attach(app, name: "Audit-18-Large-Text-Comments")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func selectTab(_ name: String, in app: XCUIApplication) {
        let phoneTab = app.tabBars.buttons[name]
        if phoneTab.exists {
            phoneTab.tap()
        } else {
            // iPad's floating top tabs are exposed as cells, not a TabBar.
            let tabletTab = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", name)).firstMatch
            XCTAssertTrue(tabletTab.waitForExistence(timeout: 5), "Missing tab: \(name)")
            tabletTab.tap()
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
