import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func testEngineGalleryOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["--engine-gallery"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Engine Gallery"].waitForExistence(timeout: 15))
    }

    /// VoiceOver builds a task line's label from its text and skips the checkbox image, so the line must carry its
    /// state as text.
    @MainActor
    func testTaskCheckboxesReadTheirState() {
        let app = XCUIApplication()
        app.launchArguments = ["--engine-gallery"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Engine Gallery"].waitForExistence(timeout: 15))
        let lines = app.descendants(matching: .any)
        let done = lines.matching(NSPredicate(format: "label CONTAINS 'Done task' AND label CONTAINS 'Checked'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "no task line reads its checked state")
        XCTAssertFalse(done.label.contains("Unchecked"), done.label)
        XCTAssertTrue(lines.matching(NSPredicate(format: "label CONTAINS 'Open task' AND label CONTAINS 'Unchecked'")).firstMatch.exists)
    }
}
