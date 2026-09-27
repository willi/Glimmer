import XCTest

final class BenchmarkHitchUITests: XCTestCase {
    /// Streams about 1,000 words below a settled 5,000-word answer at Gemini's cadence while the screen scrolls through
    /// the earlier answer and back. On a device, the app's frame monitor must report a hitch-time ratio under 5 ms/s,
    /// Apple's "good"; the spec's target is zero hitches, and the device results doc tracks the distance to it.
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
        let ratio = summary.label.firstMatch(of: #/ratio=([0-9.]+)ms\/s/#).flatMap { Double($0.1) }
        XCTAssertLessThan(try XCTUnwrap(ratio, summary.label), 5, summary.label)
        #endif
    }
}
