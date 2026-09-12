import XCTest

@MainActor final class EmberUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let appearance = extra.contains("dark") ? "dark" : "light"
        app.launchEnvironment["EMBER_TEST_APPEARANCE"] = appearance
        app.launchArguments = ["--ui-testing"] + extra.filter { !["-appearance", "dark", "light"].contains($0) }
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
        attach(app, name: "Audit-32-No-Results")
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
        attach(offline, name: "Audit-31-Offline-Cached")
    }

    func testAppearanceAndAccessibility() throws {
        let app = launch(["-appearance", "dark"])
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        try auditAccessibility(app)
        app.buttons["story-1001"].tap()
        XCTAssertTrue(app.buttons["collapse-2001"].waitForExistence(timeout: 5))
        attach(app, name: "Audit-25-Discussion-Dark")
        try auditAccessibility(app)
        selectTab("Saved", in: app)
        try auditAccessibility(app)
        selectTab("Search", in: app)
        try auditAccessibility(app)
        selectTab("Settings", in: app)
        XCTAssertTrue(app.switches["Compact stories"].waitForExistence(timeout: 5))
        try auditAccessibility(app)
    }

    private func auditAccessibility(_ app: XCUIApplication) throws {
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
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in dark.frame.width > dark.frame.height }, object: dark)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        XCTAssertTrue(dark.buttons["story-1001"].isHittable)
        attach(dark, name: "Audit-33-Landscape-Stories")
    }

    func testAuditMainFlows() {
        let app = launch()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        attach(app, name: "Audit-01-Stories")
        app.buttons["feed-menu"].tap()
        attach(app, name: "Audit-02-Feed-Menu")
        app.buttons["Ask HN"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Ask HN"].waitForExistence(timeout: 5))
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
        collections.buttons["Reading preferences"].tap()
        XCTAssertTrue(collections.switches["Use Reader when available"].waitForExistence(timeout: 5))
        attach(collections, name: "Audit-19-Reading-Preferences")
        setSwitch(collections.switches["Open in default browser"], on: true)
        let readerHidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: collections.switches["Use Reader when available"])
        XCTAssertEqual(XCTWaiter.wait(for: [readerHidden], timeout: 5), .completed)
        setSwitch(collections.switches["Open in default browser"], on: false)
        XCTAssertTrue(collections.switches["Use Reader when available"].waitForExistence(timeout: 5))
        collections.navigationBars.buttons.element(boundBy: 0).tap()
        collections.buttons["Hidden content"].tap()
        attach(collections, name: "Audit-20-Hidden-Content")
        collections.buttons["Blocked users (0)"].tap()
        attach(collections, name: "Audit-21-Blocked-Empty")
        collections.navigationBars.buttons.element(boundBy: 0).tap()
        collections.navigationBars.buttons.element(boundBy: 0).tap()
        collections.buttons["Storage"].tap()
        attach(collections, name: "Audit-22-Storage")
        collections.buttons["Clear offline feed cache"].tap()
        XCTAssertTrue(collections.staticTexts["Offline feed cache cleared."].waitForExistence(timeout: 5))
        collections.navigationBars.buttons.element(boundBy: 0).tap()
        collections.swipeUp()
        attach(collections, name: "Audit-10-Settings-Lower")
        reveal(collections.buttons["Help & support"], in: collections)
        collections.buttons["Help & support"].tap()
        attach(collections, name: "Audit-11-Help")
        collections.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(collections.buttons["Privacy"], in: collections)
        collections.buttons["Privacy"].tap()
        attach(collections, name: "Audit-12-Privacy")
        collections.swipeUp()
        attach(collections, name: "Audit-34-Privacy-Lower")
        collections.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(collections.buttons["Acknowledgments"], in: collections)
        collections.buttons["Acknowledgments"].tap()
        attach(collections, name: "Audit-35-Acknowledgments")
        collections.terminate()
        let discussion = launch()
        XCTAssertTrue(discussion.buttons["story-1001"].waitForExistence(timeout: 10))
        discussion.buttons["story-1001"].tap()
        XCTAssertTrue(discussion.buttons["collapse-2001"].waitForExistence(timeout: 5))
        attach(discussion, name: "Audit-13-Discussion")
        discussion.buttons["story-author"].tap()
        XCTAssertTrue(discussion.staticTexts["Karma"].waitForExistence(timeout: 5))
        attach(discussion, name: "Audit-23-Profile")
        discussion.navigationBars.buttons.element(boundBy: 0).tap()
        let replies = discussion.buttons["replies-2001"]
        reveal(replies, in: discussion); replies.tap()
        XCTAssertTrue(discussion.staticTexts["comment-text-3001"].waitForExistence(timeout: 5))
        attach(discussion, name: "Audit-14-Replies")
        discussion.terminate()
        let offline = launch(["--offline"])
        XCTAssertTrue(offline.staticTexts["You’re offline. Check your connection and try again."].waitForExistence(timeout: 10))
        attach(offline, name: "Audit-15-Offline-Empty")
    }

    func testArticleAndTitleOpenBrowser() {
        let app = launch()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        app.buttons["story-1001"].tap()
        for identifier in ["read-article", "article-title"] {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
            app.buttons[identifier].tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
            app.buttons["Done"].tap()
            XCTAssertTrue(app.buttons["bookmark-story"].waitForExistence(timeout: 5))
        }
        app.swipeUp()
        app.buttons["Discussion actions"].tap()
        let menuArticle = app.buttons.matching(identifier: "Read article").allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(menuArticle)
        menuArticle?.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
    }

    func testJobsDoNotInviteComments() {
        let app = launch()
        XCTAssertTrue(app.buttons["feed-menu"].waitForExistence(timeout: 5))
        app.buttons["feed-menu"].tap()
        app.buttons["Jobs"].tap()
        XCTAssertTrue(app.buttons["story-1007"].waitForExistence(timeout: 10))
        app.buttons["story-1007"].tap()
        XCTAssertTrue(app.buttons["read-article"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["read-article"].label, "View job")
        XCTAssertFalse(app.staticTexts["Quiet for now"].exists)
        attach(app, name: "Audit-24-Job")
    }

    func testStorageConfirmationKeepsBookmarks() {
        let app = launch()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        app.buttons["story-1001"].tap()
        XCTAssertTrue(app.buttons["bookmark-story"].waitForExistence(timeout: 5))
        app.buttons["bookmark-story"].tap()
        selectTab("Settings", in: app)
        app.buttons["Storage"].tap()
        app.buttons["Clear reading history"].tap()
        let message = app.staticTexts["This removes the selected data from this device and can’t be undone."]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        attach(app, name: "Audit-26-Clear-History-Confirmation")
        app.buttons["confirm-clear-data"].tap()
        selectTab("Saved", in: app)
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 5))
        app.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No reading history"].waitForExistence(timeout: 5))
    }

    func testReportAndUnblockFlow() {
        let app = launch()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        app.buttons["story-1001"].tap()
        app.buttons["Discussion actions"].tap()
        app.buttons["Report story"].tap()
        XCTAssertTrue(app.buttons["Open item on Hacker News"].waitForExistence(timeout: 5))
        attach(app, name: "Audit-27-Report")
        app.buttons["Block julia on this device"].tap()
        XCTAssertTrue(app.buttons["User blocked"].exists)
        selectTab("Settings", in: app)
        app.buttons["Hidden content"].tap()
        app.buttons["Blocked users (1)"].tap()
        XCTAssertTrue(app.buttons["Unblock"].waitForExistence(timeout: 5))
        attach(app, name: "Audit-28-Blocked-User")
        app.buttons["Unblock"].tap()
        XCTAssertTrue(app.staticTexts["No blocked users"].waitForExistence(timeout: 5))
    }

    func testPollOptionsAndCompactLayout() {
        let app = launch()
        XCTAssertTrue(app.buttons["feed-menu"].waitForExistence(timeout: 5))
        app.buttons["feed-menu"].tap()
        app.buttons["New"].tap()
        XCTAssertTrue(app.buttons["story-1008"].waitForExistence(timeout: 10))
        app.buttons["story-1008"].tap()
        XCTAssertTrue(app.staticTexts["Over morning coffee"].waitForExistence(timeout: 5))
        attach(app, name: "Audit-29-Poll")
        selectTab("Settings", in: app)
        setSwitch(app.switches["Compact stories"], on: true)
        selectTab("Stories", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        attach(app, name: "Audit-30-Compact-Stories")
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

    private func setSwitch(_ element: XCUIElement, on: Bool) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let expected = on ? "1" : "0"
        if element.value as? String != expected {
            // SwiftUI exposes the whole form row as a switch. Target its thumb.
            element.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -25, dy: 0)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
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
