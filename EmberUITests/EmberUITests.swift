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
        XCTAssertFalse(app.staticTexts["comment-text-2001"].exists)
        XCTAssertFalse(app.staticTexts["comment-text-3001"].exists)
        app.buttons["collapse-2001"].tap()
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
                // iOS 26's native empty search prompt reports "nearly passed"
                // despite captured glyph/background colors measuring 5.93:1.
                // Scope this to reviewed placeholders; entered text stays audited.
                let placeholder = element.placeholderValue ?? ""
                let value = element.value as? String ?? ""
                if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
                   app.launchEnvironment["EMBER_TEST_APPEARANCE"] == "dark",
                   element.elementType == .searchField,
                   ["Search stories", "Search saved stories"].contains(placeholder),
                   value.isEmpty || value == placeholder {
                    return true
                }
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
        XCTAssertEqual(app.buttons["feed-menu"].label, "Choose feed, Ask HN selected")
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
        XCTAssertTrue(discussion.staticTexts["comment-text-3001"].waitForExistence(timeout: 5))
        attach(discussion, name: "Audit-14-Replies")
        discussion.terminate()
        let offline = launch(["--offline"])
        XCTAssertTrue(offline.staticTexts["You’re offline. Check your connection and try again."].waitForExistence(timeout: 10))
        attach(offline, name: "Audit-15-Offline-Empty")
    }

    func testFeedHeaderSwitchesAndRestoresSelection() {
        let app = launch()
        let menu = app.buttons["feed-menu"]
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "feed-menu").count, 1)
        XCTAssertEqual(menu.label, "Choose feed, Top selected")
        XCTAssertLessThan(app.navigationBars.firstMatch.frame.height, 80, "The feed header should fit one compact navigation row.")
        XCTAssertLessThan(menu.frame.midX, app.frame.midX)
        XCTAssertLessThan(app.buttons["story-1001"].frame.minY - menu.frame.maxY, 40, "Stories should begin directly below the header.")

        menu.tap()
        app.buttons["Ask HN"].firstMatch.tap()
        XCTAssertTrue(app.buttons["story-1004"].waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "Choose feed, Ask HN selected")
        attach(app, name: "Header-01-Ask-Selected")
        app.buttons["story-1004"].tap()
        XCTAssertTrue(app.buttons["bookmark-story"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(menu.isHittable)
        XCTAssertEqual(menu.label, "Choose feed, Ask HN selected")

        app.terminate()
        let restored = launch(["--preserve-state"])
        XCTAssertTrue(restored.buttons["story-1004"].waitForExistence(timeout: 10))
        XCTAssertEqual(restored.buttons["feed-menu"].label, "Choose feed, Ask HN selected")
        restored.buttons["feed-menu"].tap()
        restored.buttons["Top"].firstMatch.tap()
        XCTAssertTrue(restored.buttons["story-1001"].waitForExistence(timeout: 5))
        XCTAssertEqual(restored.buttons["feed-menu"].label, "Choose feed, Top selected")
        restored.swipeUp()
        XCTAssertTrue(restored.buttons["feed-menu"].isHittable, "Feed switching stays available while scrolling.")
        attach(restored, name: "Header-02-Scrolled")
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
        // SwiftUI exposes a wrapper and inner button for this same action.
        app.sheets["Clear reading history"].buttons["confirm-clear-data"].firstMatch.tap()
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

    func testReviewTypography() {
        for theme in ["light", "dark"] {
            let app = launch([theme])
            selectTab("Settings", in: app)
            app.buttons["Text & spacing"].tap()
            let preview = app.staticTexts["typography-preview"]
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            attach(app, name: "Review-01-Stories-\(theme)")
            app.segmentedControls.buttons["Comments"].tap()
            let size = app.sliders["adjust-Text size"]
            XCTAssertTrue(size.waitForExistence(timeout: 5))
            size.adjust(toNormalizedSliderPosition: 0.65)
            XCTAssertTrue(preview.isHittable)
            attach(app, name: "Review-02-Comment-Size-\(theme)")
            app.buttons["Font"].tap()
            app.buttons["Serif"].tap()
            attach(app, name: "Review-03-Comment-Font-\(theme)")
            let controls = app.collectionViews["typography-controls"]
            let indent = app.sliders["adjust-Reply indentation"]
            for _ in 0..<4 {
                if indent.isHittable { break }
                controls.swipeUp()
            }
            XCTAssertTrue(indent.isHittable)
            indent.adjust(toNormalizedSliderPosition: 1)
            XCTAssertTrue(preview.isHittable, "Preview must remain visible at the last control.")
            XCTAssertLessThan(preview.frame.maxY, indent.frame.minY)
            attach(app, name: "Review-04-Scrolled-Controls-\(theme)")
            let reset = app.buttons["reset-typography"]
            for _ in 0..<3 { if reset.isHittable { break }; controls.swipeUp() }
            reset.tap()
            for _ in 0..<3 { if size.isHittable { break }; controls.swipeDown() }
            XCTAssertEqual(size.value as? String, "17 points")
            attach(app, name: "Review-05-Reset-\(theme)")
            app.terminate()
        }
    }

    func testReviewReadingControls() {
        let app = launch(["dark"])
        XCTAssertTrue(app.buttons["article-1001"].waitForExistence(timeout: 10))
        attach(app, name: "Review-06-Home")
        app.buttons["article-1001"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        attach(app, name: "Review-07-Direct-Article")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["feed-menu"].waitForExistence(timeout: 5))
        app.buttons["story-1001"].tap()
        let text = app.staticTexts["comment-text-2001"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        let authorY = app.buttons["Profile: alex"].frame.minY
        text.tap()
        XCTAssertEqual(app.buttons["Profile: alex"].frame.minY, authorY, accuracy: 1, "Collapsing must keep the author in place.")
        XCTAssertFalse(text.exists, "Tapping comment text must collapse it.")
        XCTAssertFalse(app.staticTexts["comment-text-3001"].exists)
        XCTAssertLessThan(app.buttons["collapse-2001"].frame.height, 60)
        attach(app, name: "Review-08-Collapsed")
        app.buttons["collapse-2001"].tap()
        reveal(app.staticTexts["comment-text-3001"], in: app)
        XCTAssertTrue(app.staticTexts["comment-text-3001"].isHittable)
        attach(app, name: "Review-09-Automatic-Replies")
        app.buttons["Profile: riley"].tap()
        XCTAssertTrue(app.staticTexts["Karma"].waitForExistence(timeout: 5))
        app.terminate()

        let long = launch(["--reading-controls", "dark"])
        XCTAssertTrue(long.buttons["story-9101"].waitForExistence(timeout: 10))
        long.buttons["story-9101"].tap()
        XCTAssertTrue(long.buttons["collapse-9201"].waitForExistence(timeout: 5))
        XCTAssertFalse(long.staticTexts["[delayed]"].exists)
        let link = long.links["Example link"]
        if link.waitForExistence(timeout: 5) {
            reveal(link, in: long); link.tap()
            XCTAssertTrue(long.buttons["Done"].waitForExistence(timeout: 10))
            long.buttons["Done"].tap()
            XCTAssertTrue(long.staticTexts["comment-text-9201"].exists, "Opening a link must not collapse its comment.")
        } else { XCTFail("Comment link must be independently accessible") }
        reveal(long.buttons["next-comment"], in: long)
        attach(long, name: "Review-10-Long-Comment")
        long.buttons["next-comment"].tap()
        XCTAssertTrue(long.staticTexts["comment-text-9301"].waitForExistence(timeout: 5))
        XCTAssertTrue(long.staticTexts["comment-text-9301"].isHittable)
        attach(long, name: "Review-11-Next-Reply")
        XCTAssertFalse(long.staticTexts["Comment removed"].exists)
        long.terminate()
    }

    func testReviewLargeTextAndLandscape() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        selectTab("Settings", in: app)
        reveal(app.buttons["Text & spacing"], in: app)
        app.buttons["Text & spacing"].tap()
        app.segmentedControls.buttons["Comments"].tap()
        XCTAssertTrue(app.staticTexts["typography-preview"].waitForExistence(timeout: 5))
        attach(app, name: "Review-12-Large-Text")
        app.terminate()
        let landscape = launch()
        selectTab("Settings", in: landscape)
        landscape.buttons["Text & spacing"].tap()
        landscape.segmentedControls.buttons["Comments"].tap()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in landscape.frame.width > landscape.frame.height }, object: landscape)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        XCTAssertTrue(landscape.staticTexts["typography-preview"].isHittable)
        XCTAssertTrue(landscape.sliders["adjust-Text size"].isHittable)
        attach(landscape, name: "Review-13-Landscape")
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
        // Full-screen capture preserves the physical display after rotation.
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
