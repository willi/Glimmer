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

    /// Runs the engine to completion in 10 ms steps, returning every phrase in start order.
    private func allPhrases(_ engine: inout GlimmerRevealEngine, until limit: TimeInterval = 20) -> [GlimmerRevealEngine.Phrase] {
        var seen: [GlimmerRevealEngine.Phrase] = []
        var time = 0.0
        while !engine.isComplete, time < limit {
            engine.advance(to: time)
            for phrase in engine.phrases where !seen.contains(phrase) { seen.append(phrase) }
            time += 0.01
        }
        return seen
    }

    func testEmbedRevealsOneUnitAtATime() {
        let text = "Intro line here.\n\u{FFFC}\nAfter the code block ends." as NSString
        let embed = text.range(of: "\u{FFFC}").location
        var engine = GlimmerRevealEngine(options: GlimmerRevealOptions())
        engine.textChanged(text, isStreaming: false, now: 0, embedUnits: [embed: [12, 12, 12]])
        let phrases = allPhrases(&engine)
        let units = phrases.filter { $0.unit != nil }
        XCTAssertEqual(units.map(\.unit), [0, 1, 2])
        XCTAssertTrue(units.allSatisfy { $0.range == NSRange(location: embed, length: 1) })
        XCTAssertEqual(units.map(\.start), units.map(\.start).sorted())
        XCTAssertFalse(phrases.contains { $0.unit == nil && NSLocationInRange(embed, $0.range) }, "no text phrase covers the embed")
        let after = phrases.first { $0.unit == nil && $0.range.location > embed }
        XCTAssertGreaterThan(after?.start ?? 0, units.last?.start ?? .infinity, "text after the embed waits for its last unit")
        XCTAssertTrue(engine.isComplete)
    }

    func testEmbedAtTheEndWaitsForMoreUnits() {
        let text = "Code:\n\u{FFFC}" as NSString
        let embed = text.length - 1
        var engine = GlimmerRevealEngine(options: GlimmerRevealOptions())
        engine.textChanged(text, isStreaming: true, now: 0, embedUnits: [embed: [8, 8]])
        engine.advance(to: 5)
        XCTAssertEqual(engine.unitsRevealed[embed], 2)
        XCTAssertEqual(engine.revealedLength, embed, "the embed may still grow")
        engine.textChanged(text, isStreaming: true, now: 5, embedUnits: [embed: [8, 8, 8]])
        engine.advance(to: 10)
        XCTAssertEqual(engine.unitsRevealed[embed], 3)
        engine.textChanged(text, isStreaming: false, now: 10, embedUnits: [embed: [8, 8, 8]])
        engine.advance(to: 20)
        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.settledLength, text.length)
    }

    func testSettledUnitsAreCountedPerEmbed() {
        let text = "\u{FFFC}\nTail words keep going here." as NSString
        var engine = GlimmerRevealEngine(options: GlimmerRevealOptions())
        engine.textChanged(text, isStreaming: false, now: 0, embedUnits: [0: [5, 5]])
        engine.advance(to: 0)
        XCTAssertEqual(engine.unitsRevealed[0], 1)
        engine.advance(to: GlimmerRevealOptions().fadeDuration + 0.01)
        XCTAssertGreaterThanOrEqual(engine.unitsSettled[0] ?? 0, 1)
        XCTAssertEqual(engine.settledLength, 0, "the embed character settles only with its last unit")
    }

    func testFadingUnitsSurviveMoreText() {
        let text = "\u{FFFC}" as NSString
        var engine = GlimmerRevealEngine(options: GlimmerRevealOptions())
        engine.textChanged(text, isStreaming: true, now: 0, embedUnits: [0: [6, 6]])
        engine.advance(to: 0.1)
        let fading = engine.phrases.filter { $0.unit != nil }
        XCTAssertFalse(fading.isEmpty)
        // The code block gains a line mid-fade: the lines already fading keep fading.
        engine.textChanged(text, isStreaming: true, now: 0.1, embedUnits: [0: [6, 6, 6]])
        XCTAssertEqual(engine.phrases.filter { $0.unit != nil }, fading)
    }
}
