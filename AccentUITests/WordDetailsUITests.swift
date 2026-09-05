import XCTest

final class WordDetailsUITests: XCTestCase {
    @MainActor
    private func openDetails() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-testWordDetails"]
        app.launch()
        XCTAssertTrue(app.buttons["closeWordDetails"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testCloseButtonDismissesDetails() {
        let app = openDetails()
        let close = app.buttons["closeWordDetails"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start recording"].isHittable)
    }

    @MainActor
    func testCloseWhileReferenceStarts() {
        let app = openDetails()
        app.buttons["audio-REFERENCE"].tap()
        app.buttons["closeWordDetails"].tap()
        XCTAssertTrue(app.buttons["closeWordDetails"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start recording"].isHittable)
    }

    @MainActor
    func testSwipeDownDismissesDetails() {
        let app = openDetails()
        let close = app.buttons["closeWordDetails"]
        let header = app.navigationBars.firstMatch
        XCTAssertTrue(header.exists)
        let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let end = start.withOffset(CGVector(dx: 0, dy: 350))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start recording"].isHittable)
    }

    @MainActor
    func testSwipeDownOnContentDismissesDetails() {
        let app = openDetails()
        app.scrollViews["wordDetailsContent"].swipeDown()
        XCTAssertTrue(app.buttons["closeWordDetails"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testCloseRemainsAvailableAfterScrolling() {
        let app = openDetails()
        app.scrollViews["wordDetailsContent"].swipeUp()
        let close = app.buttons["closeWordDetails"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }
}
