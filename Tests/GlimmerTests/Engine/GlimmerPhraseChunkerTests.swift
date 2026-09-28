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

    func testPunctuationBeforeAClosingQuoteEndsAPhrase() {
        let text = "He said \"stop now.\" Then more words follow here"
        XCTAssertEqual(end(text, streaming: true), (text as NSString).range(of: "Then").location)
    }

    func testLanguagesWithoutSpacesRevealBeforeTheParagraphEnds() throws {
        for text in [
            "这是一个正在流式生成的中文回答。它包含多个完整句子，但是没有使用空格分隔单词。",
            "これはストリーミング中の日本語の回答です。文章の途中でも順番に表示します。",
            "นี่คือข้อความภาษาไทยที่กำลังแสดงผลทีละส่วนโดยไม่ต้องรอจนจบข้อความ",
        ] {
            let boundary = try XCTUnwrap(end(text, streaming: true), text)
            XCTAssertGreaterThan(boundary, 0)
            XCTAssertLessThan(boundary, (text as NSString).length)
            XCTAssertEqual((text as NSString).rangeOfComposedCharacterSequence(at: boundary).location, boundary)
        }
    }

    func testLinguisticFallbackDoesNotSplitALatinWordOrEmoji() throws {
        let text = "这是包含supercalifragilisticexpialidocious以及👨‍👩‍👧‍👦家庭表情的中文回答。后续文字仍然继续到达。"
        let boundary = try XCTUnwrap(end(text, streaming: true))
        let latin = (text as NSString).range(of: "supercalifragilisticexpialidocious")
        XCTAssertFalse(boundary > latin.location && boundary < NSMaxRange(latin))
        XCTAssertEqual((text as NSString).rangeOfComposedCharacterSequence(at: boundary).location, boundary)
    }

    func testUnspacedParagraphsAreChunkedWhenAlreadyComplete() throws {
        let paragraph = "这是一个已经完整到达的中文回答。它仍然需要分成多个短语逐步显示，而不是整段一次出现。"
        for text in [paragraph, paragraph + "\n"] {
            for streaming in [true, false] {
                let boundary = try XCTUnwrap(end(text, streaming: streaming))
                XCTAssertLessThan(boundary, (paragraph as NSString).length)
            }
        }
    }

    func testAccentedLatinIdentifiersKeepTheirWordBoundaries() {
        XCTAssertNil(end("café-this-is-one-long-identifier-with-a-trailing-word", streaming: true))
    }

    func testShortUnspacedLinesStopAtTheNewline() {
        for streaming in [true, false] {
            XCTAssertEqual(end("你好\n", streaming: streaming), 3)
            XCTAssertEqual(end("你好\nnext words follow here", streaming: streaming), 3)
            let line = "你好👨‍👩‍👧‍👦\n"
            XCTAssertEqual(end(line + "next words follow here", streaming: streaming), (line as NSString).length)
        }
    }

    func testLongLatinWordsAcrossATokenizationWindowStayWhole() throws {
        let word = String(repeating: "x", count: 600)
        let text = "这包含" + word + "以及其他连续到达的中文文本。"
        let latin = (text as NSString).range(of: word)
        for streaming in [true, false] {
            var start = 0
            while let boundary = end(text, from: start, streaming: streaming) {
                XCTAssertGreaterThan(boundary, start)
                XCTAssertFalse(boundary > latin.location && boundary < NSMaxRange(latin))
                start = boundary
            }
            XCTAssertGreaterThanOrEqual(start, NSMaxRange(latin), "the complete word eventually reveals")
            if !streaming { XCTAssertEqual(start, (text as NSString).length) }
        }
    }

    func testLatinCompoundsInsideUnspacedTextStayWhole() {
        for word in [
            "café-this-is-one-long-identifier-with-a-trailing-word",
            "long-identifier's-name-with-many-parts-to-preserve",
            "one’two’three’four’five’six’seven’eight’nine",
            String(repeating: "x", count: 252) + "-" + String(repeating: "y", count: 100),
        ] {
            let text = "这包含" + word + "以及其他连续到达的中文文本。"
            let compound = (text as NSString).range(of: word)
            for streaming in [true, false] {
                var start = 0
                while let boundary = end(text, from: start, streaming: streaming) {
                    XCTAssertGreaterThan(boundary, start)
                    XCTAssertFalse(boundary > compound.location && boundary < NSMaxRange(compound), word)
                    start = boundary
                }
                XCTAssertGreaterThanOrEqual(start, NSMaxRange(compound), "the complete compound eventually reveals")
                if !streaming { XCTAssertEqual(start, (text as NSString).length) }
            }
        }
    }
}
