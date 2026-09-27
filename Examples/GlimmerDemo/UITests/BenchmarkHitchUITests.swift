import XCTest

final class BenchmarkHitchUITests: XCTestCase {
    /// Streams about 1,000 words below a settled 5,000-word answer at Gemini's cadence while the screen scrolls through
    /// the earlier answer and back. On a device, the app's frame monitor must report no hitches (spec §3);
    /// XCTHitchMetric records the system's view of the same run in the result bundle. The test doesn't touch the app
    /// while it measures: an element query snapshots the app's accessibility tree, which stalls a long answer.
    @MainActor
    func testStreamingBelowALongAnswerDoesNotHitch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark", "--benchmark-autostart"]
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            app.launch()
            // Two seconds to settle, about 30 s of streaming, and three for the reveal to finish.
            Thread.sleep(forTimeInterval: 45)
        }
        let summary = app.staticTexts["benchmark.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        print("BENCHMARK \(summary.label)")
        XCTAssertTrue(summary.label.hasPrefix("done"), summary.label)
        #if !targetEnvironment(simulator)
        XCTAssertTrue(summary.label.contains(" hitches=0 "), summary.label)
        #endif
    }
}
