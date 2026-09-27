import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func testEngineGalleryOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["--engine-gallery"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Engine Gallery"].waitForExistence(timeout: 15))
    }
}
