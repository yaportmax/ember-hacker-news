import XCTest
final class VlohUITests: XCTestCase {
    @MainActor func testNativeNavigationAndChat() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["record-day"].waitForExistence(timeout: 10))
        attach(app, "Today")
        selectTab("Drafts", in: app)
        XCTAssertTrue(app.staticTexts["Weekend adventures"].waitForExistence(timeout: 5))
        attach(app, "Drafts")
        selectTab("Chat", in: app)
        let field = app.descendants(matching: .any)["chat-message"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Hello buddies")
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.staticTexts["Hello buddies"].waitForExistence(timeout: 5))
        app.buttons["dismiss-keyboard"].tap()
        attach(app, "Chat")
        selectTab("Settings", in: app)
        XCTAssertTrue(app.staticTexts["Your privacy"].waitForExistence(timeout: 5))
        attach(app, "Settings")
    }
    @MainActor func testEmptyDraftCannotBePublished() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["record-day"].waitForExistence(timeout: 10)); app.buttons["record-day"].tap()
        let button = app.buttons["share-vlog"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertFalse(button.isEnabled)
        attach(app, "Composer")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["record-day"].waitForExistence(timeout: 5))
    }
    @MainActor private func selectTab(_ title: String, in app: XCUIApplication) {
        // iPad places tabs at the top and does not expose an XCUI TabBar.
        let button = app.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
