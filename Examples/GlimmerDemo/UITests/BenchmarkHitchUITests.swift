import XCTest

final class BenchmarkHitchUITests: XCTestCase {
    /// Streams about 1,000 words below a settled 5,000-word answer at Gemini's cadence while scrolling. On a device,
    /// the app's frame monitor must report no hitches (spec §3); XCTHitchMetric records the system's view of the same
    /// run in the result bundle.
    @MainActor
    func testStreamingBelowALongAnswerDoesNotHitch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark"]
        app.launch()
        let start = app.buttons["benchmark.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        let summary = app.staticTexts["benchmark.summary"]
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            start.tap()
            let answer = app.scrollViews["benchmark.scrollView"]
            for _ in 0..<4 {
                answer.swipeDown(velocity: .slow)
                answer.swipeUp(velocity: .fast)
            }
            let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'done'"), object: summary)
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 180), .completed)
        }
        print("BENCHMARK \(summary.label)")
        #if !targetEnvironment(simulator)
        XCTAssertTrue(summary.label.contains(" hitches=0 "), summary.label)
        #endif
    }
}
