import XCTest

/// 1.x's example screens on Glimmer 2: each opens from the list, scrolls to its end, and goes back.
final class ExamplesUITests: XCTestCase {
    /// Each example's id (as in `--example=<id>` and the list's `example.<id>` identifier), its navigation title, and
    /// how many tabs or sections it has.
    private static let examples: [(id: String, title: String, sections: Int)] = [
        ("basic-features", "Basic Features", 3),
        ("advanced", "Advanced Features", 3),
        ("gfm", "GitHub Flavored Markdown", 10),
        ("edge-cases", "Edge Cases", 10),
        ("inline-images", "Inline Images", 1),
        ("tappable-images", "Tappable Images", 1),
        ("github-emojis", "GitHub Emojis", 1),
        ("live-preview", "Live Preview", 1),
        ("streaming-reveal", "Streaming Reveal", 1),
        ("performance", "Performance", 1),
        ("readme", "README", 1),
        ("github-features", "GitHub", 1),
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryExampleOpensScrollsAndGoesBack() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Glimmer"].waitForExistence(timeout: 15))
        for example in Self.examples {
            let link = app.descendants(matching: .any)["example.\(example.id)"]
            for _ in 0..<6 where !link.isHittable { app.swipeUp() }
            link.tap()
            XCTAssertTrue(app.navigationBars[example.title].waitForExistence(timeout: 10), example.title)
            let pages = scrollToEnd(app, maxPages: 60)
            XCTAssertLessThan(pages.count, 60, "\(example.title) never reached its end")
            XCTAssertEqual(app.state, .runningForeground, "\(example.title) crashed")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Glimmer"].waitForExistence(timeout: 10), "back from \(example.title)")
        }
    }

    @MainActor
    private func launch(_ id: String, _ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--example=\(id)"] + arguments
        app.launch()
        return app
    }

    /// Basic Features: every tab opens, and a mention and an issue on the Interactive tab report their taps.
    @MainActor
    func testBasicFeaturesTabsAndTokenTaps() {
        let app = launch("basic-features")
        XCTAssertTrue(app.navigationBars["Basic Features"].waitForExistence(timeout: 15))
        app.buttons["Code"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Interactive"].tap()
        let banner = app.staticTexts["demo.lastTap"]
        app.links["@tim"].firstMatch.tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "tapping a mention reports it")
        XCTAssertEqual(banner.label, "Mention @tim")
        app.links["#1234"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Issue #1234"].waitForExistence(timeout: 5), "tapping an issue reports it")
        app.buttons["Basic"].tap()
    }

    /// Tappable Images: a standalone image and an inline one report their URLs.
    @MainActor
    func testTappingAnImageShowsItsURL() {
        let app = launch("tappable-images")
        XCTAssertTrue(app.navigationBars["Tappable Images"].waitForExistence(timeout: 15))
        let logo = app.buttons["SwiftUI Logo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 5))
        logo.tap()
        let alert = app.alerts["Image Tapped"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["URL: https://developer.apple.com/assets/elements/icons/swiftui/swiftui-96x96_2x.png"].exists)
        alert.buttons["OK"].tap()
    }

    /// Streaming Reveal: a simulated stream and a one-shot play reach the end of the sample, in both hosts.
    @MainActor
    func testStreamingRevealPlaysInBothHosts() {
        let app = launch("streaming-reveal")
        XCTAssertTrue(app.navigationBars["Streaming Reveal"].waitForExistence(timeout: 15))
        let end = NSPredicate(format: "label CONTAINS 'nothing to mismatch'")
        app.buttons["reveal.stream"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(end).firstMatch.waitForExistence(timeout: 30), "the stream never finished")
        app.buttons["UIKit"].tap()
        app.buttons["reveal.playFull"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(end).firstMatch.waitForExistence(timeout: 30), "the UIKit host never finished")
    }

    /// Advanced Features: the stream runs, and export writes the answer as plain text and as markdown.
    @MainActor
    func testAdvancedStreamingAndExport() {
        let app = launch("advanced", ["--section=1"])
        XCTAssertTrue(app.navigationBars["Advanced Features"].waitForExistence(timeout: 15))
        app.buttons["streaming.start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 60), "the stream never finished")
        app.buttons["Export"].tap()
        app.buttons["export.button"].tap()
        let output = app.staticTexts["export.output"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertTrue(output.label.hasPrefix("Export Demo\nConvert markdown to different formats!"), output.label)
        app.buttons["Markdown"].tap()
        app.buttons["export.button"].tap()
        XCTAssertTrue(app.staticTexts["export.output"].label.hasPrefix("# Export Demo"), app.staticTexts["export.output"].label)
    }

    /// Performance: a run reports parse, settled and streamed times.
    @MainActor
    func testPerformanceRunReportsTimes() {
        let app = launch("performance")
        XCTAssertTrue(app.navigationBars["Performance"].waitForExistence(timeout: 15))
        app.buttons["performance.run"].tap()
        let streamed = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Streamed render'")).firstMatch
        XCTAssertTrue(streamed.waitForExistence(timeout: 90), "the benchmark never finished")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Parse'")).firstMatch.exists)
    }

    /// Screenshots of every example, section by section, top to bottom, for review. Opt-in: run with
    /// `TEST_RUNNER_EXAMPLES_TOUR=light` (every page in light mode), `=appearances` (the first pages in dark mode and at
    /// an accessibility text size) or `=all` (both). The screenshots are attachments of the result bundle.
    @MainActor
    func testScreenshotTour() throws {
        let tour = ProcessInfo.processInfo.environment["EXAMPLES_TOUR"]
        try XCTSkipIf(tour == nil, "set TEST_RUNNER_EXAMPLES_TOUR to light, appearances or all")
        var appearances: [(name: String, arguments: [String], pages: Int)] = []
        if tour != "appearances" { appearances.append(("light", [], 15)) }
        if tour != "light" { appearances += [("dark", ["--dark"], 2), ("large", ["--large-text"], 2)] }
        // `TEST_RUNNER_EXAMPLES_TOUR_ONLY=gfm,edge-cases` limits the tour to those examples.
        let only = ProcessInfo.processInfo.environment["EXAMPLES_TOUR_ONLY"]?.split(separator: ",").map(String.init)
        for appearance in appearances {
            for example in Self.examples where only?.contains(example.id) ?? true {
                for section in 0..<example.sections {
                    let app = XCUIApplication()
                    app.launchArguments = ["--example=\(example.id)", "--section=\(section)"] + appearance.arguments
                    app.launch()
                    XCTAssertTrue(app.navigationBars[example.title].waitForExistence(timeout: 15), example.title)
                    // Let images load.
                    _ = app.wait(for: .unknown, timeout: 2)
                    for (page, shot) in scrollToEnd(app, maxPages: appearance.pages).enumerated() {
                        let attachment = XCTAttachment(screenshot: shot)
                        attachment.name = "\(appearance.name)-\(example.id)-s\(section)-p\(page)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                    XCTAssertEqual(app.state, .runningForeground, "\(example.id) crashed")
                }
            }
        }
    }

    /// Scrolls down about half a screen at a time until the screen stops changing, or `maxPages` screens were seen.
    /// Returns the screenshots, top first.
    @MainActor
    private func scrollToEnd(_ app: XCUIApplication, maxPages: Int) -> [XCUIScreenshot] {
        var shots = [app.screenshot()]
        while shots.count < maxPages {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.3)
            let shot = app.screenshot()
            if shot.pngRepresentation == shots.last?.pngRepresentation { break }
            shots.append(shot)
        }
        return shots
    }
}
