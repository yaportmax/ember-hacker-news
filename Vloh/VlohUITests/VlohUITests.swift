import XCTest
final class VlohUITests: XCTestCase {
    @MainActor func testGroupsChatScheduleAndSettings() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["group-friends"].waitForExistence(timeout: 10)); attach(app, "Groups")
        app.buttons["group-friends"].tap()
        XCTAssertTrue(app.buttons["record-day"].waitForExistence(timeout: 5)); attach(app, "Group")
        app.buttons["group-schedule"].tap()
        XCTAssertTrue(app.staticTexts["The next two weeks"].waitForExistence(timeout: 5)); attach(app, "Schedule")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["group-chat"].tap()
        let field = app.descendants(matching: .any)["chat-message"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Hello buddies")
        app.buttons["send-message"].tap(); XCTAssertTrue(app.staticTexts["Hello buddies"].waitForExistence(timeout: 5))
        app.buttons["dismiss-keyboard"].tap(); attach(app, "Chat")
        selectTab("Settings", in: app)
        XCTAssertTrue(app.buttons["account-settings"].waitForExistence(timeout: 5)); attach(app, "Settings")
        app.buttons["account-settings"].tap(); XCTAssertTrue(app.staticTexts["Sign-in"].waitForExistence(timeout: 5)); attach(app, "Account")
    }
    @MainActor func testContinuousRecordingAndVisualTrimming() throws {
        let app = launch(); selectTab("Record", in: app)
        let record = app.buttons["capture-toggle"]
        XCTAssertTrue(record.waitForExistence(timeout: 10)); attach(app, "Recorder")
        record.tap(); XCTAssertEqual(record.label, "Stop recording"); record.tap()
        XCTAssertTrue(app.staticTexts["1 clips saved"].waitForExistence(timeout: 10))
        XCTAssertTrue(record.exists); XCTAssertEqual(record.label, "Start recording")
        record.tap(); record.tap()
        XCTAssertTrue(app.staticTexts["2 clips saved"].waitForExistence(timeout: 10)); attach(app, "Recorder two clips")
        app.buttons["review-clips"].tap()
        let trim = app.buttons["Trim clip 1"]
        XCTAssertTrue(trim.waitForExistence(timeout: 5)); trim.tap()
        let start = app.otherElements["trim-start-handle"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let from = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 40, dy: 0)))
        XCTAssertFalse(app.staticTexts["trim-start-value"].label.contains("0.0s"))
        app.buttons["play-trim"].tap(); attach(app, "Visual trim")
        app.buttons["save-trim"].tap(); XCTAssertTrue(app.buttons["share-vlog"].waitForExistence(timeout: 5)); attach(app, "Draft")
    }
    @MainActor func testPostedVideoOpensFullScreen() throws {
        let app = launch(); app.buttons["group-friends"].tap()
        let vlog = app.buttons["vlog-preview"]
        XCTAssertTrue(vlog.waitForExistence(timeout: 5)); vlog.tap()
        XCTAssertTrue(app.buttons["close-fullscreen"].waitForExistence(timeout: 10)); attach(app, "Full screen playback")
        app.buttons["close-fullscreen"].tap(); XCTAssertTrue(app.buttons["open-fullscreen"].waitForExistence(timeout: 5))
    }
    @MainActor private func launch() -> XCUIApplication { let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch(); return app }
    @MainActor private func selectTab(_ title: String, in app: XCUIApplication) {
        let button = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) { let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
}
