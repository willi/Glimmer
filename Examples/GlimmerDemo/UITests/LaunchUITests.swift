import XCTest

final class LaunchUITests: XCTestCase {
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

    /// VoiceOver frames the text it focuses: the answer's text view must not report the tall frame it lays out in.
    @MainActor
    func testTheAnswersAccessibilityFrameHugsItsText() {
        let app = XCUIApplication()
        app.launchArguments = ["--engine-gallery"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Engine Gallery"].waitForExistence(timeout: 15))
        let answer = app.textViews.firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        XCTAssertLessThan(answer.frame.height, 20_000, "\(answer.frame)")
        XCTAssertGreaterThan(answer.frame.height, 500)
    }

    /// The gallery's own Dark toggle darkens the screen (an app-wide appearance must not override it).
    @MainActor
    func testTheGallerysDarkToggleDarkensTheScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--engine-gallery", "--gallery-dark"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Engine Gallery"].waitForExistence(timeout: 15))
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        // A pixel of background at the left edge, below the navigation bar.
        let x = 4 * Int(image.width) / 390, y = Int(image.height) * 7 / 10
        let pixel = bytes + y * image.bytesPerRow + x * image.bitsPerPixel / 8
        XCTAssertLessThan(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]), 150, "a dark background")
    }
}
