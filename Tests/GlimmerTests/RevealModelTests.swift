import XCTest
import SwiftUI
@testable import Glimmer

final class RevealModelTests: XCTestCase {

    // MARK: - Renderer session

    func testStandaloneInlineCodeStyledAfterBeginSession() {
        let config = MarkdownConfiguration.default
        var renderer = MarkdownRenderer()
        renderer.beginSession(configuration: config)
        let attributed = renderer.renderInlines(
            [.code("let x = 1")], configuration: config
        )
        XCTAssertEqual(attributed.runs.first?.font, config.codeFont,
                       "code inline must get codeFont without a full render(blocks:) pass")
    }

    func testStandaloneMentionColoredAfterBeginSession() {
        let config = MarkdownConfiguration.default
        var renderer = MarkdownRenderer()
        renderer.beginSession(configuration: config)
        let attributed = renderer.renderInlines(
            [.mention(username: "octocat")], configuration: config
        )
        XCTAssertEqual(attributed.runs.first?.foregroundColor, config.mentionColor)
    }

    // MARK: - Tokenization

    func testRevealTokensSplitsWordsAndSpaces() {
        let tokens = AttributedString("Hello brave world").revealTokens()
        XCTAssertEqual(tokens.count, 5)
        XCTAssertEqual(String(tokens[0].slice.characters), "Hello")
        XCTAssertTrue(tokens[1].isWhitespace)
        XCTAssertEqual(String(tokens[2].slice.characters), "brave")
        XCTAssertEqual(String(tokens[4].slice.characters), "world")
        XCTAssertFalse(tokens[4].isWhitespace)
    }

    func testRevealTokensCollapsedWhitespaceRuns() {
        let tokens = AttributedString("a  b").revealTokens()
        XCTAssertEqual(tokens.count, 3)
        XCTAssertEqual(String(tokens[1].slice.characters), "  ")
        XCTAssertTrue(tokens[1].isWhitespace)
    }

    func testRevealTokensEmptyString() {
        XCTAssertTrue(AttributedString("").revealTokens().isEmpty)
    }

    func testRevealTokensPreserveRunAttributes() {
        var s = AttributedString("tap here now")
        if let range = s.range(of: "here") {
            s[range].link = URL(string: "https://example.com")
        }
        let tokens = s.revealTokens()
        XCTAssertEqual(tokens[2].slice.runs.first?.link?.absoluteString, "https://example.com")
        XCTAssertNil(tokens[0].slice.runs.first?.link)
    }

    func testRevealCharactersSplitsPreservingAttributes() {
        var s = AttributedString("ab")
        s.font = .body.bold()
        let chars = s.revealCharacters()
        XCTAssertEqual(chars.count, 2)
        XCTAssertEqual(String(chars[0].characters), "a")
        XCTAssertEqual(chars[1].runs.first?.font, Font.body.bold())
    }

    func testRevealCharactersPreservePerRunAttributes() {
        var s = AttributedString("ab")
        if let range = s.range(of: "b") {
            s[range].link = URL(string: "https://example.com")
        }
        let chars = s.revealCharacters()
        XCTAssertEqual(chars.count, 2)
        XCTAssertNil(chars[0].runs.first?.link)
        XCTAssertEqual(chars[1].runs.first?.link?.absoluteString, "https://example.com")
    }

    func testRevealTokensMarkNewlineWhitespace() {
        let tokens = AttributedString("a \n b").revealTokens()
        XCTAssertEqual(tokens.count, 3) // "a", " \n ", "b"
        XCTAssertTrue(tokens[1].containsNewline)
        XCTAssertFalse(tokens[0].containsNewline)
        let plain = AttributedString("a b").revealTokens()
        XCTAssertFalse(plain[1].containsNewline)
    }

    func testRevealTokensLeadingNewline() {
        let tokens = AttributedString("\na").revealTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertTrue(tokens[0].containsNewline)
    }

    // MARK: - Flattener helpers

    private func model(_ md: String, style: RevealStyle = .wordFade) -> RevealModel {
        Glimmer.revealModel(md, style: style, configuration: .default)
    }

    private func allAtoms(_ m: RevealModel) -> [RevealAtom] {
        m.blocks.flatMap(\.words).flatMap(\.atoms)
    }

    private func atomText(_ atom: RevealAtom) -> String {
        switch atom.kind {
        case .text(let s), .space(let s): return String(s.characters)
        case .lineBreak: return "\n"
        case .block: return ""
        }
    }

    private func joinedText(_ block: RevealBlock) -> String {
        block.words.flatMap(\.atoms).map(atomText).joined()
    }

    // MARK: - Flattener

    func testWordCountSimpleParagraph() {
        let m = model("Hello brave new world")
        XCTAssertEqual(m.countableCount, 4)
        XCTAssertEqual(m.blocks.count, 1)
        XCTAssertEqual(m.blocks[0].kind, .paragraph)
    }

    func testHeadingTagAndCounts() {
        let m = model("# Title here\n\nBody text")
        XCTAssertEqual(m.blocks.count, 2)
        XCTAssertEqual(m.blocks[0].kind, .heading(level: 1))
        XCTAssertEqual(m.blocks[1].kind, .paragraph)
        XCTAssertEqual(m.countableCount, 4)
    }

    func testCharacterGranularityCountsCharsNotSpaces() {
        let m = model("Hi yo", style: .typewriter)
        XCTAssertEqual(m.countableCount, 4)
    }

    func testLineGranularityGroupsFourWordsPerLine() {
        let m = model("one two three four five six", style: .lineSlide)
        XCTAssertEqual(m.countableCount, 2)
        XCTAssertEqual(joinedText(m.blocks[0]), "one two three four\nfive six\n")
    }

    func testRevealIndexGatesSpacesWithPrecedingWord() {
        let m = model("one two")
        XCTAssertEqual(allAtoms(m).map(\.revealIndex), [1, 1, 2])
        XCTAssertEqual(allAtoms(m).map(\.isCountable), [true, false, true])
    }

    func testCodeBlockIsWholeBlockAtom() {
        let m = model("Before\n\n```swift\nlet x = 1\n```")
        XCTAssertEqual(m.blocks.count, 2)
        XCTAssertEqual(m.blocks[1].kind, .wholeBlock)
        XCTAssertNotNil(m.blocks[1].node)
        XCTAssertEqual(m.countableCount, 2) // "Before" word + 1 block atom
    }

    func testTableIsWholeBlockAtom() {
        let m = model("| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(m.blocks.first?.kind, .wholeBlock)
    }

    func testImageParagraphBecomesWholeBlock() {
        let m = model("![alt](https://example.com/i.png)")
        XCTAssertEqual(m.blocks.first?.kind, .wholeBlock)
    }

    func testListItemsCarryMarkerAndDepth() {
        let m = model("- alpha\n- beta")
        XCTAssertEqual(m.blocks.count, 2)
        XCTAssertEqual(m.blocks[0].kind, .listItem(marker: "• ", depth: 0))
        XCTAssertEqual(m.blocks[1].kind, .listItem(marker: "• ", depth: 0))
        XCTAssertEqual(m.countableCount, 2)
    }

    func testOrderedListMarkers() {
        let m = model("1. first\n2. second")
        XCTAssertEqual(m.blocks[0].kind, .listItem(marker: "1. ", depth: 0))
        XCTAssertEqual(m.blocks[1].kind, .listItem(marker: "2. ", depth: 0))
    }

    func testNestedListDepth() {
        let m = model("- outer\n    - inner")
        XCTAssertTrue(m.blocks.contains { $0.kind == .listItem(marker: "◦ ", depth: 1) })
    }

    func testBlockquoteTagged() {
        let m = model("> quoted words here")
        XCTAssertEqual(m.blocks[0].kind, .blockquote(depth: 1))
        XCTAssertEqual(m.countableCount, 3)
    }

    func testLinkAtomCarriesURL() {
        let m = model("see [docs](https://example.com) now")
        XCTAssertTrue(allAtoms(m).contains { $0.url?.absoluteString == "https://example.com" })
    }

    func testStableIDsAndTextOnAppend() {
        let prefix = "Alpha beta gamma. "
        let prefixM = model(prefix)
        let fullM = model(prefix + "Delta epsilon")
        let p = allAtoms(prefixM)
        let f = allAtoms(fullM)
        XCTAssertGreaterThan(f.count, p.count)
        for (pa, fa) in zip(p, f) {
            XCTAssertEqual(pa.id, fa.id)
            XCTAssertEqual(atomText(pa), atomText(fa))
            XCTAssertEqual(pa.isCountable, fa.isCountable)
        }
    }

    func testFirstRevealIndexPerBlock() {
        let m = model("one two\n\nthree four")
        XCTAssertEqual(m.blocks[0].firstRevealIndex, 1)
        XCTAssertEqual(m.blocks[1].firstRevealIndex, 3)
    }

    func testSettledTextMatchesRendererInlineOutput() {
        let md = "Some **bold** and *em* text with [a link](https://x.example) and `code`"
        let blocks = Glimmer.parse(md, configuration: .default)
        guard case .paragraph(let children) = blocks[0] else { return XCTFail("expected paragraph") }
        var renderer = MarkdownRenderer()
        renderer.beginSession(configuration: .default)
        let expected = String(renderer.renderInlines(children, configuration: .default, baseFont: MarkdownConfiguration.default.baseFont).characters)
        let m = model(md)
        XCTAssertEqual(joinedText(m.blocks[0]), expected,
                       "reveal atoms must reproduce the renderer's text exactly (seamless settle, R5)")
    }

    func testEmptyInput() {
        let m = model("")
        XCTAssertEqual(m.countableCount, 0)
        XCTAssertTrue(m.blocks.isEmpty)
    }

    func testCharGranularityKeepsWordGrouping() {
        let m = model("ab cd", style: .charCascade)
        XCTAssertEqual(m.countableCount, 4)
        let words = m.blocks[0].words.filter { !$0.isWhitespace && !$0.isLineBreak }
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[0].atoms.count, 2) // 'a', 'b' grouped in one layout word
    }

    func testInProgressLastWordKeepsIDWhileTextChanges() {
        // Spec 9.3: the streaming tail's last word changes text; its id must not.
        let p = allAtoms(model("Alpha hel"))
        let f = allAtoms(model("Alpha hello"))
        XCTAssertEqual(p.count, f.count)
        XCTAssertEqual(p.last?.id, f.last?.id)
        XCTAssertEqual(atomText(p.last!), "hel")
        XCTAssertEqual(atomText(f.last!), "hello")
    }

    func testBlocksWithoutCountablesNeverVisibleAtZero() {
        // Mid-stream artifacts like a bare "#" must not flash in before reveal starts.
        let m = model("#")
        for block in m.blocks {
            XCTAssertGreaterThan(block.firstRevealIndex, 0)
        }
    }

    func testSoftBreakParagraphCountsWordsAcrossLines() {
        let m = model("alpha\nbeta")
        XCTAssertEqual(m.countableCount, 2)
    }
}
