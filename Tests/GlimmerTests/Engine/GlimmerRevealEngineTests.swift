import XCTest
@testable import Glimmer

final class GlimmerRevealEngineTests: XCTestCase {
    private let options = GlimmerRevealOptions()
    private let tenWords: NSString = "One two three four five six seven eight nine ten"

    func testFirstPhraseStartsWhenTextArrives() {
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged(tenWords, isStreaming: true, now: 0)
        engine.advance(to: 0)
        XCTAssertEqual(engine.phrases, [.init(range: NSRange(location: 0, length: 40), start: 0)])
        XCTAssertEqual(engine.revealedLength, 40)
        XCTAssertGreaterThanOrEqual(engine.nextPhraseStart ?? 0, options.minPhraseSpacing)
    }

    func testPhrasesSettleAfterTheirFade() {
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged(tenWords, isStreaming: true, now: 0)
        engine.advance(to: 0)
        engine.advance(to: options.fadeDuration + 0.001)
        XCTAssertFalse(engine.phrases.contains { $0.range.location == 0 })
        XCTAssertGreaterThanOrEqual(engine.settledLength, 40)
    }

    func testWaitsForCompleteWordsWhileStreaming() {
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged("one two thr", isStreaming: true, now: 0)
        engine.advance(to: 0)
        XCTAssertEqual(engine.revealedLength, 0)
        XCTAssertTrue(engine.phrases.isEmpty)
    }

    func testFlushesAndCompletesWhenStreamingEnds() {
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged("one two", isStreaming: false, now: 0)
        engine.advance(to: 0)
        XCTAssertEqual(engine.revealedLength, 7)
        XCTAssertFalse(engine.isComplete, "still fading")
        engine.advance(to: 1)
        XCTAssertTrue(engine.isComplete)
        XCTAssertNil(engine.nextWake)
    }

    func testShorterTextClampsWhatWasRevealed() {
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged(tenWords, isStreaming: true, now: 0)
        engine.advance(to: 0)
        engine.textChanged("One two three four five", isStreaming: true, now: 0.01)
        XCTAssertEqual(engine.revealedLength, 23)
        XCTAssertEqual(engine.phrases.first?.range, NSRange(location: 0, length: 23))
    }

    func testResumeStartsFullyRevealed() {
        var engine = GlimmerRevealEngine(options: options, alreadyRevealed: 7)
        engine.textChanged("one two", isStreaming: false, now: 5)
        engine.advance(to: 5)
        XCTAssertTrue(engine.phrases.isEmpty, "nothing replays")
        XCTAssertTrue(engine.isComplete)
    }

    func testNextWakeIsTheEarliestStartOrSettle() {
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged(tenWords, isStreaming: true, now: 0)
        engine.advance(to: 0)
        let expected = min(engine.nextPhraseStart ?? .infinity, options.fadeDuration)
        XCTAssertEqual(engine.nextWake ?? -1, expected, accuracy: 1e-9)
    }

    func testTextArrivingAfterAWaitRespectsSpacing() {
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged("One two three ", isStreaming: true, now: 0)
        engine.advance(to: 0)
        engine.textChanged("One two three four five six ", isStreaming: true, now: 0.01)
        engine.advance(to: 0.01)
        XCTAssertEqual(engine.phrases.count, 1, "the second phrase waits for the pacing gap")
    }

    func testHugeBurstDrainsWithinDrainDuration() {
        let burst = String(repeating: "word ", count: 600) as NSString
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged(burst, isStreaming: true, now: 0)
        var starts: [Int: TimeInterval] = [:]
        var now = 0.0
        var ended = false
        while !engine.isComplete, now < 10 {
            if now >= 0.1, !ended {
                engine.textChanged(burst, isStreaming: false, now: now)
                ended = true
            }
            engine.advance(to: now)
            for phrase in engine.phrases { starts[phrase.range.location] = phrase.start }
            now += 0.01
        }
        XCTAssertTrue(engine.isComplete)
        XCTAssertLessThanOrEqual(now, 0.1 + options.drainDuration + options.fadeDuration + 0.5)
        let ordered = starts.values.sorted()
        for (earlier, later) in zip(ordered, ordered.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, options.minPhraseSpacing - 1e-9)
        }
    }
}
