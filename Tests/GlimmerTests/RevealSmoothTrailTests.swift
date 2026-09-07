import XCTest
@testable import Glimmer

final class RevealSmoothTrailTests: XCTestCase {
    func testEnvelopeIsContinuousMonotonicAndFinishesDuringPause() {
        XCTAssertEqual(RevealSmoothTrail.opacity(age: -1), 0)
        XCTAssertEqual(RevealSmoothTrail.opacity(age: 0), 0)
        var previous = 0.0
        for frame in 1...60 {
            let opacity = RevealSmoothTrail.opacity(age: Double(frame) / 120)
            XCTAssertGreaterThanOrEqual(opacity, previous)
            XCTAssertLessThanOrEqual(opacity, 1)
            previous = opacity
        }
        XCTAssertEqual(previous, 1)
        XCTAssertEqual(RevealSmoothTrail.opacity(age: 30), 1)
    }

    func testPausedTailSettlesWithoutAnotherReveal() {
        var trail = RevealSmoothTrailState()
        trail.reveal(through: 3, from: 0, at: 10)
        trail.settle(at: 10.25)
        XCTAssertEqual(trail.starts.count, 3)
        XCTAssertFalse(trail.isSettled)
        trail.settle(at: 10.5)
        XCTAssertTrue(trail.isSettled)
        XCTAssertEqual(trail.settledCount, 3)
    }

    func testRestoredWordsStaySettledAndOnlyNewWordsAnimate() {
        var trail = RevealSmoothTrailState()
        trail.settleImmediately(through: 100)
        trail.reveal(through: 102, from: 100, at: 10)
        XCTAssertEqual(trail.settledCount, 100)
        XCTAssertEqual(Set(trail.starts.keys), [101, 102])
    }

    func testLongStreamRetainsOnlyItsActiveTail() {
        var trail = RevealSmoothTrailState()
        for index in 1...10_000 {
            trail.reveal(through: index, from: index - 1, at: Double(index) * 0.045)
            XCTAssertLessThanOrEqual(trail.starts.count, 12)
        }
        trail.truncate(to: 2)
        XCTAssertTrue(trail.isSettled)
        XCTAssertEqual(trail.settledCount, 2)
    }
}

@MainActor
final class RevealSmoothTrailDriverTests: XCTestCase {
    func testCompletionWaitsForFinalWordsFade() async {
        var time = 0.0
        var driver: RevealDriver!
        var sawDrainedButStillFading = false
        driver = RevealDriver(
            configuration: .init(style: .smoothTrail, catchUp: .strict),
            store: RevealProgressStore(),
            now: { time }
        ) { seconds in
            if driver.revealedCount == 2 {
                XCTAssertFalse(driver.isComplete)
                sawDrainedButStillFading = true
            }
            time += seconds
        }
        driver.update(totalCountable: 2, isStreaming: false)
        await driver.run()
        XCTAssertTrue(sawDrainedButStillFading)
        XCTAssertTrue(driver.isComplete)
        XCTAssertTrue(driver.smoothTrail.isSettled)
        XCTAssertEqual(time, 0.09 + RevealSmoothTrail.duration, accuracy: 0.002)
    }

    func testTailSettlesWhileProducerRemainsStreaming() async {
        var time = 0.0
        var driver: RevealDriver!
        var observedSettledPause = false
        driver = RevealDriver(
            configuration: .init(style: .smoothTrail, isStreaming: true),
            store: RevealProgressStore(),
            now: { time }
        ) { seconds in
            if time > 0.6 {
                observedSettledPause = driver.smoothTrail.isSettled
                XCTAssertFalse(driver.isComplete)
                driver.update(totalCountable: 1, isStreaming: false)
            }
            time += seconds
        }
        driver.update(totalCountable: 1, isStreaming: true)
        await driver.run()
        XCTAssertTrue(observedSettledPause)
    }

    func testAppendAfterCompletionCanRunAgainWithoutReplayingOldText() async {
        var time = 0.0
        let driver = RevealDriver(
            configuration: .init(style: .smoothTrail),
            store: RevealProgressStore(),
            now: { time },
            sleep: { time += $0 }
        )
        driver.update(totalCountable: 2, isStreaming: false)
        await driver.run()
        driver.update(totalCountable: 3, isStreaming: false)
        XCTAssertFalse(driver.isComplete)
        XCTAssertEqual(driver.revealedCount, 2)
        XCTAssertEqual(driver.smoothTrail.settledCount, 2)
        await driver.run()
        XCTAssertTrue(driver.isComplete)
        XCTAssertEqual(driver.revealedCount, 3)
    }

    func testCancellationDuringFinalFadeDoesNotComplete() async {
        var time = 0.0
        var driver: RevealDriver!
        driver = RevealDriver(
            configuration: .init(style: .smoothTrail),
            store: RevealProgressStore(),
            now: { time }
        ) { seconds in
            if driver.revealedCount == 1 { throw CancellationError() }
            time += seconds
        }
        driver.update(totalCountable: 1, isStreaming: false)
        await driver.run()
        XCTAssertFalse(driver.isComplete)
        XCTAssertFalse(driver.smoothTrail.isSettled)
    }

    func testCappedSnapHasNoArtificialFadeDelay() async {
        let driver = RevealDriver(
            configuration: .init(style: .smoothTrail, catchUp: .cappedSnap(maxLagSeconds: 0.1)),
            store: RevealProgressStore(),
            sleep: { _ in XCTFail("Capped snap should settle immediately") }
        )
        driver.update(totalCountable: 100, isStreaming: false)
        await driver.run()
        XCTAssertTrue(driver.isComplete)
        XCTAssertTrue(driver.smoothTrail.isSettled)
    }
}
