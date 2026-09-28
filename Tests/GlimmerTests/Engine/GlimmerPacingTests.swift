import XCTest
@testable import Glimmer

final class GlimmerPacingTests: XCTestCase {
    private let options = GlimmerRevealOptions()

    func testSmallBacklogRevealsAtTheBaseRate() {
        var pacing = GlimmerPacing(options: options)
        pacing.updateRate(backlog: 10, isStreaming: true, now: 0)
        XCTAssertEqual(pacing.rate, 60)
        XCTAssertEqual(pacing.interval(forPhraseLength: 30), 0.5, accuracy: 1e-9)
    }

    func testRateFollowsTheBacklogSmoothly() {
        var pacing = GlimmerPacing(options: options)
        pacing.updateRate(backlog: 0, isStreaming: true, now: 0)
        pacing.updateRate(backlog: 600, isStreaming: true, now: 0.05)
        // target 600 / 0.4 = 1500; 0.05 s of 0.25 s smoothing moves a fifth of the way from 60.
        XCTAssertEqual(pacing.rate, 60 + (1500 - 60) * 0.2, accuracy: 1e-6)
    }

    func testDrainUsesTheDrainDuration() {
        var pacing = GlimmerPacing(options: options)
        pacing.updateRate(backlog: 300, isStreaming: false, now: 0)
        XCTAssertEqual(pacing.rate, 200, accuracy: 1e-9)
    }

    func testDrainFinishesByTheDeadline() {
        var pacing = GlimmerPacing(options: options)
        pacing.updateRate(backlog: 1000, isStreaming: false, now: 0)
        // 0.1 s before the 1.5 s deadline, 100 characters remain: at least 1000 chars/s is needed.
        pacing.updateRate(backlog: 100, isStreaming: false, now: 1.4)
        XCTAssertGreaterThanOrEqual(pacing.rate, 1000 - 1e-6)
    }

    func testStreamingAgainClearsTheDrainDeadline() {
        var pacing = GlimmerPacing(options: options)
        pacing.updateRate(backlog: 1000, isStreaming: false, now: 0)
        pacing.updateRate(backlog: 10, isStreaming: true, now: 10)
        XCTAssertEqual(pacing.rate, options.baseRate, accuracy: 1e-6)
    }

    func testIntervalNeverDropsBelowMinimumSpacing() {
        var pacing = GlimmerPacing(options: options)
        pacing.updateRate(backlog: 10_000, isStreaming: true, now: 0)
        XCTAssertEqual(pacing.interval(forPhraseLength: 1), options.minPhraseSpacing)
    }

    func testFastRatesAskForLongerPhrases() {
        var pacing = GlimmerPacing(options: options)
        pacing.updateRate(backlog: 3000, isStreaming: false, now: 0)
        XCTAssertEqual(pacing.rate, 2000, accuracy: 1e-9)
        XCTAssertEqual(pacing.minimumPhraseLength, 120)
    }
}
