import XCTest

/// UI tests referencing DemoApp accessibility identifiers.
/// `profile.avatar.refresh` is an orphan: it matches no crawled element.
final class ProfileUITests: XCTestCase {
    func testToggleNotifications() {
        let app = XCUIApplication()
        app.launch()
        app.switches["profile.notifications"].tap()
        XCTAssertTrue(app.switches["profile.notifications"].exists)
    }

    func testSaveProfile() {
        let app = XCUIApplication()
        app.launch()
        app.textFields["profile.displayName"].tap()
        app.buttons["profile.save"].tap()
    }

    func testRefreshAvatar() {
        let app = XCUIApplication()
        app.launch()
        // Orphan identifier — the control was renamed, the test never followed.
        app.buttons["profile.avatar.refresh"].tap()
    }
}

final class CheckoutUITests: XCTestCase {
    func testApplyCoupon() {
        let app = XCUIApplication()
        app.launch()
        app.textFields["checkout.coupon"].typeText("AGENT10")
        app.buttons["checkout.pay"].tap()
    }
}
