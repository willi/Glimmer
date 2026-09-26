import XCTest
@testable import Glimmer

final class GlimmerPhraseChunkerTests: XCTestCase {
    private func end(_ text: String, from start: Int = 0, streaming: Bool) -> Int? {
        GlimmerPhraseChunker.phraseEnd(in: text as NSString, from: start, isStreaming: streaming, minWords: 3, maxWords: 8)
    }

    func testStopsAtEightWords() {
        XCTAssertEqual(end("The quick brown fox jumps over the lazy dog today.", streaming: false), 40)
    }

    func testStopsAfterPunctuationOnceItHasThreeWords() {
        XCTAssertEqual(end("One two three, four five", streaming: true), 15)
        XCTAssertEqual(end("Alpha beta gamma delta. Next words here", streaming: true), 24)
    }

    func testShortSentenceRunsToTheEndWhenNotStreaming() {
        XCTAssertEqual(end("Hi, you there.", streaming: false), 14)
    }

    func testLineEndClosesAPhrase() {
        XCTAssertEqual(end("Short line\nNext", streaming: true), 11)
    }

    func testBlockAttachmentIsItsOwnPhrase() {
        XCTAssertEqual(end("\u{FFFC}\nText after", streaming: true), 2)
    }

    func testWaitsForCompleteWordsWhileStreaming() {
        XCTAssertNil(end("one two thr", streaming: true))
        XCTAssertEqual(end("one two three fo", streaming: true), 14)
    }

    func testFlushesTheRemainderWhenNotStreaming() {
        XCTAssertEqual(end("one two", streaming: false), 7)
    }

    func testStartsMidText() {
        let text = "Alpha beta gamma delta. Next words here and more"
        XCTAssertEqual(end(text, from: 24, streaming: false), (text as NSString).length)
    }

    func testNeverSplitsGraphemes() {
        let text = "👋🏽 hello there friend"
        XCTAssertEqual(end(text, streaming: false), (text as NSString).length)
    }

    func testNothingLeftReturnsNil() {
        XCTAssertNil(end("done", from: 4, streaming: false))
    }
}
