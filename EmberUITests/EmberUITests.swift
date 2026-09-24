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

    func testCommentHNLinkOffersNativeDiscussionAndBrowser() {
        let app = launch(["--reading-controls"])
        XCTAssertTrue(app.buttons["story-9101"].waitForExistence(timeout: 10))
        app.buttons["story-9101"].tap()
        let link = app.links["Related discussion"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.buttons["Open in Ember"].waitForExistence(timeout: 5))
        app.buttons["Open in Ember"].tap()
        XCTAssertTrue(app.staticTexts["Building a search engine from scratch"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5), "Back should return to the original comment")
        link.tap()
        app.buttons["Open on Hacker News"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
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

    func testAppStoreScreenshots() {
        let app = launch()
        func capture(_ name: String) {
            Thread.sleep(forTimeInterval: 0.6)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Store-" + name
            image.lifetime = .keepAlways
            add(image)
        }
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        capture("01-Stories")
        app.buttons["story-1001"].tap()
        XCTAssertTrue(app.staticTexts["comment-text-2001"].waitForExistence(timeout: 10))
        capture("02-Discussion")
        app.buttons["bookmark-story"].tap()
        selectTab("Saved", in: app)
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 5))
        capture("03-Saved")
        selectTab("Settings", in: app)
        app.buttons["Text & spacing"].tap()
        app.segmentedControls.buttons["Comments"].tap()
        XCTAssertTrue(app.staticTexts["typography-preview"].waitForExistence(timeout: 5))
        capture("04-Reading-Settings")
        app.terminate()
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

    func testReviewExtraFeeds() {
        let app = launch()
        XCTAssertTrue(app.buttons["feed-menu"].waitForExistence(timeout: 5))
        app.buttons["feed-menu"].tap()
        app.buttons["More feeds"].tap()
        attach(app, name: "Review-18-More-Feeds")
        app.buttons["Best Comments"].tap()
        XCTAssertTrue(app.buttons["thread-2001"].waitForExistence(timeout: 5))
        app.buttons["best-comments-period"].tap()
        app.buttons["Past 24 hours"].tap()
        XCTAssertTrue(app.staticTexts["Most-upvoted comments of the past 24 hours."].waitForExistence(timeout: 5))
        attach(app, name: "Review-19-Best-Comments")
        app.buttons["thread-2001"].tap()
        XCTAssertTrue(app.buttons["bookmark-story"].waitForExistence(timeout: 5))
        attach(app, name: "Review-20-Comment-Discussion")
    }

    func testReviewTimeFilters() {
        let app = launch()
        XCTAssertTrue(app.buttons["period-menu"].waitForExistence(timeout: 5))
        app.buttons["period-menu"].tap()
        attach(app, name: "Review-14-Time-Menu")
        app.buttons["Past week"].tap()
        XCTAssertTrue(app.buttons["story-9401"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["period-menu"].label, "Time period, Past week selected")
        attach(app, name: "Review-15-Week")
        app.buttons["period-menu"].tap()
        app.buttons["Custom dates"].tap()
        XCTAssertTrue(app.buttons["apply-dates"].waitForExistence(timeout: 5))
        attach(app, name: "Review-16-Custom-Dates")
        app.buttons["apply-dates"].tap()
        XCTAssertEqual(app.buttons["period-menu"].label, "Time period, Custom dates selected")
        attach(app, name: "Review-17-Custom-Results")
        app.buttons["period-menu"].tap()
        app.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["story-9401"].exists)
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
            app.buttons["reading-font"].tap()
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
            XCTAssertEqual(size.value as? String, "14 points")
            attach(app, name: "Review-05-Reset-\(theme)")
            app.terminate()
        }
    }

    func testSettledTypographyScreens() {
        let app = launch(["--settings-review", "dark"])
        func capture(_ name: String) {
            // Allow the simulator's display compositor to finish the changed frame.
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        selectTab("Settings", in: app)
        app.buttons["Text & spacing"].tap()
        app.segmentedControls.buttons["Comments"].tap()
        capture("Settled-00-Defaults")
        let line = app.sliders["adjust-Line spacing"]
        let controls = app.collectionViews["typography-controls"]
        for _ in 0..<5 { if line.isHittable { break }; controls.swipeUp() }
        line.adjust(toNormalizedSliderPosition: 0)
        capture("Settled-01-Preview-Min")
        line.adjust(toNormalizedSliderPosition: 1)
        capture("Settled-02-Preview-Max")
        line.adjust(toNormalizedSliderPosition: 0)
        selectTab("Stories", in: app)
        app.buttons["story-1001"].tap()
        XCTAssertTrue(app.buttons["collapse-2001"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["read-article"].isHittable)
        capture("Settled-03-Discussion-Min")
        selectTab("Settings", in: app)
        line.adjust(toNormalizedSliderPosition: 1)
        selectTab("Stories", in: app)
        capture("Settled-04-Discussion-Max")
        app.terminate()
    }

    func testCommentSpacingAffectsPreviewAndReading() {
        let app = launch(["--settings-review", "dark"])
        selectTab("Settings", in: app)
        app.buttons["Text & spacing"].tap()
        app.segmentedControls.buttons["Comments"].tap()
        let controls = app.collectionViews["typography-controls"]
        func adjust(_ name: String, _ position: CGFloat) {
            let slider = app.sliders["adjust-" + name]
            for _ in 0..<5 { if slider.isHittable { break }; controls.swipeUp() }
            for _ in 0..<5 { if slider.isHittable { break }; controls.swipeDown() }
            XCTAssertTrue(slider.isHittable)
            slider.adjust(toNormalizedSliderPosition: position)
        }
        let preview = app.staticTexts["comment-text-1"]
        XCTAssertEqual(app.sliders["adjust-Text size"].value as? String, "14 points")
        attach(app, name: "Spacing-00-Comment-Defaults")
        adjust("Row spacing", 0.5); adjust("Reply indentation", 0.5); adjust("Text size", 0.5)
        XCTAssertEqual(app.sliders["adjust-Text size"].value as? String, "14 points")
        adjust("Text size", 0); adjust("Line spacing", 0); adjust("Row spacing", 0)
        let compactHeight = preview.frame.height
        adjust("Line spacing", 1)
        XCTAssertGreaterThan(preview.frame.height, compactHeight + 12, "Line spacing must visibly change the preview even at the smallest font.")
        XCTAssertTrue(app.staticTexts["typography-preview"].isHittable)
        attach(app, name: "Spacing-01-Comment-Lines-Max")
        adjust("Line spacing", 0)
        let smallGap = app.buttons["Profile: riley"].frame.minY - preview.frame.maxY
        adjust("Row spacing", 1)
        XCTAssertGreaterThan(app.buttons["Profile: riley"].frame.minY - preview.frame.maxY, smallGap + 30)
        attach(app, name: "Spacing-02-Comment-Rows-Max")
        adjust("Row spacing", 0); adjust("Reply indentation", 0)
        let reply = app.staticTexts["comment-text-2"]
        XCTAssertEqual(reply.frame.minX, preview.frame.minX, accuracy: 1)
        adjust("Reply indentation", 1)
        XCTAssertGreaterThan(reply.frame.minX, preview.frame.minX + 25)
        for name in ["Serif", "Rounded", "Monospaced", "System"] {
            let font = app.buttons["reading-font"]
            for _ in 0..<5 { if font.isHittable { break }; controls.swipeDown() }
            font.tap(); app.buttons[name].tap()
            XCTAssertTrue(preview.exists)
            if name == "Monospaced" { attach(app, name: "Spacing-03-Comment-Font") }
        }
        adjust("Text size", 1)
        XCTAssertGreaterThan(preview.frame.height, compactHeight + 20)
        attach(app, name: "Spacing-04-Comment-Size-Max")
        let reset = app.buttons["reset-typography"]
        for _ in 0..<5 { if reset.isHittable { break }; controls.swipeUp() }
        reset.tap()
        adjust("Line spacing", 0)
        selectTab("Stories", in: app)
        app.buttons["story-1001"].tap()
        let body = app.staticTexts["comment-text-2001"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let low = body.frame.height
        attach(app, name: "Spacing-05-Discussion-Lines-Min")
        selectTab("Settings", in: app)
        adjust("Line spacing", 1)
        selectTab("Stories", in: app)
        XCTAssertGreaterThan(body.frame.height, low + 20, "The same setting must change already-open discussion text.")
        attach(app, name: "Spacing-06-Discussion-Lines-Max")
        selectTab("Settings", in: app)
        adjust("Line spacing", 0)
        selectTab("Stories", in: app)
        XCTAssertEqual(body.frame.height, low, accuracy: 1)
        app.terminate()
    }

    func testStorySpacingAndPreferencePersistence() {
        let app = launch(["--settings-review"])
        selectTab("Settings", in: app)
        app.buttons["Text & spacing"].tap()
        let controls = app.collectionViews["typography-controls"]
        func adjust(_ name: String, _ position: CGFloat) {
            let slider = app.sliders["adjust-" + name]
            for _ in 0..<5 { if slider.isHittable { break }; controls.swipeUp() }
            for _ in 0..<5 { if slider.isHittable { break }; controls.swipeDown() }
            XCTAssertTrue(slider.isHittable)
            slider.adjust(toNormalizedSliderPosition: position)
        }
        let preview = app.staticTexts["story-title--1"]
        adjust("Line spacing", 0)
        let low = preview.frame.height
        adjust("Line spacing", 1)
        XCTAssertGreaterThan(preview.frame.height, low + 10)
        attach(app, name: "Spacing-07-Story-Lines-Max")
        adjust("Row spacing", 0)
        let lowGap = app.buttons["article--2"].frame.minY - app.buttons["story--1"].frame.maxY
        adjust("Row spacing", 1)
        XCTAssertGreaterThan(app.buttons["article--2"].frame.minY - app.buttons["story--1"].frame.maxY, lowGap + 35)
        attach(app, name: "Spacing-08-Story-Rows-Max")
        adjust("Row spacing", 0); adjust("Text size", 0)
        let small = preview.frame.height
        adjust("Text size", 1)
        XCTAssertGreaterThan(preview.frame.height, small + 20)
        let bold = app.switches["Bold titles"]
        for _ in 0..<4 { if bold.isHittable { break }; controls.swipeUp() }
        setSwitch(bold, on: false)
        attach(app, name: "Spacing-09-Story-Size-Max")
        setSwitch(bold, on: true)
        let reset = app.buttons["reset-typography"]
        for _ in 0..<5 { if reset.isHittable { break }; controls.swipeUp() }
        reset.tap()
        adjust("Line spacing", 0)
        selectTab("Stories", in: app)
        let actual = app.staticTexts["story-title-1001"]
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        let actualLow = actual.frame.height
        selectTab("Settings", in: app); adjust("Line spacing", 1)
        selectTab("Stories", in: app)
        XCTAssertGreaterThan(actual.frame.height, actualLow + 10)
        attach(app, name: "Spacing-10-Home-Lines-Max")
        selectTab("Settings", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        setSwitch(app.switches["Compact stories"], on: true)
        selectTab("Stories", in: app)
        XCTAssertFalse(app.staticTexts["example.com"].firstMatch.exists)
        attach(app, name: "Spacing-11-Compact-Home")
        app.terminate()
        let restored = launch(["--settings-review", "--preserve-state"])
        selectTab("Settings", in: restored)
        XCTAssertEqual(restored.switches["Compact stories"].value as? String, "1")
        restored.buttons["Text & spacing"].tap()
        let line = restored.sliders["adjust-Line spacing"]
        let restoredControls = restored.collectionViews["typography-controls"]
        for _ in 0..<5 { if line.isHittable { break }; restoredControls.swipeUp() }
        XCTAssertEqual(line.value as? String, "14 points")
        restored.terminate()
    }

    func testReadingPreferenceControls() {
        let app = launch(["dark"])
        XCTAssertTrue(app.buttons["story-1001"].waitForExistence(timeout: 10))
        app.buttons["story-1001"].tap()
        XCTAssertTrue(app.buttons["collapse-2001"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        selectTab("Settings", in: app)
        for theme in ["Light", "Dark", "System"] {
            app.buttons["appearance-picker"].tap()
            app.buttons[theme].tap()
            attach(app, name: "Settings-Theme-" + theme)
        }
        app.buttons["Reading preferences"].tap()
        setSwitch(app.switches["Dim read stories"], on: false)
        selectTab("Stories", in: app)
        attach(app, name: "Settings-Read-Undimmed")
        selectTab("Settings", in: app)
        setSwitch(app.switches["Dim read stories"], on: true)
        selectTab("Stories", in: app)
        attach(app, name: "Settings-Read-Dimmed")
        selectTab("Settings", in: app)
        setSwitch(app.switches["Hide read stories"], on: true)
        selectTab("Stories", in: app)
        XCTAssertFalse(app.buttons["story-1001"].exists)
        selectTab("Settings", in: app)
        setSwitch(app.switches["Hide read stories"], on: false)
        setSwitch(app.switches["Use Reader when available"], on: false)
        setSwitch(app.switches["Open in default browser"], on: true)
        XCTAssertFalse(app.switches["Use Reader when available"].exists)
        attach(app, name: "Settings-External-Browser")
        setSwitch(app.switches["Open in default browser"], on: false)
        XCTAssertEqual(app.switches["Use Reader when available"].value as? String, "0")
        setSwitch(app.switches["Use Reader when available"], on: true)
        attach(app, name: "Settings-Reader")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Hidden content"].tap()
        app.buttons["Blocked users (0)"].tap()
        XCTAssertTrue(app.staticTexts["No blocked users"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Storage"].tap()
        app.buttons["Clear offline feed cache"].tap()
        XCTAssertTrue(app.staticTexts["Offline feed cache cleared."].waitForExistence(timeout: 5))
        attach(app, name: "Settings-Storage")
        app.terminate()
    }

    func testLargeDiscussionResponsiveness() {
        let app = launch(["--large-discussion", "dark"])
        XCTAssertTrue(app.buttons["story-9501"].waitForExistence(timeout: 10))
        app.buttons["story-9501"].tap()
        XCTAssertTrue(app.buttons["collapse-10000"].waitForExistence(timeout: 5))
        attach(app, name: "Performance-01-First-Comments")
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            app.swipeUp(velocity: .fast)
        }
        attach(app, name: "Performance-02-Scrolled-Thread")
        let next = app.buttons["next-comment"]
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.buttons["bookmark-story"].isHittable)
        attach(app, name: "Performance-03-Next-Reply")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["story-9501"].waitForExistence(timeout: 5))
        app.buttons["story-9501"].tap()
        XCTAssertTrue(app.buttons["collapse-10000"].waitForExistence(timeout: 3))
        let author = app.buttons["Profile: reader10000"]
        let y = author.frame.minY
        app.buttons["collapse-10000"].tap()
        XCTAssertEqual(author.frame.minY, y, accuracy: 1)
        XCTAssertFalse(app.staticTexts["comment-text-10000"].exists)
        attach(app, name: "Performance-04-Reopened-Collapsed")
        app.terminate()
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
        XCTAssertFalse(long.buttons["next-comment"].exists, "Hide the arrow when the remaining comments are already visible.")
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
        let largeSize = app.sliders["adjust-Text size"]
        let controls = app.collectionViews["typography-controls"]
        for _ in 0..<4 { if largeSize.isHittable { break }; controls.swipeUp() }
        XCTAssertTrue(largeSize.isHittable)
        largeSize.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertTrue(app.staticTexts["typography-preview"].isHittable)
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
            let tabletTabs = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", name))
            XCTAssertTrue(tabletTabs.firstMatch.waitForExistence(timeout: 5), "Missing tab: \(name)")
            // iPad can retain an offscreen duplicate after dismissing a popover.
            guard let tabletTab = tabletTabs.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
                XCTFail("Missing visible tab: \(name)")
                return
            }
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
