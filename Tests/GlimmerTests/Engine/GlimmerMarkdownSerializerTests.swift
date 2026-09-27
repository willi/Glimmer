import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerMarkdownSerializerTests: XCTestCase {
    private let composer = GlimmerComposer(theme: .default)

    private func compose(_ markdown: String) -> NSAttributedString {
        composer.compose(GlimmerParser.parse(markdown))
    }

    private func markdown(_ text: NSAttributedString, _ range: NSRange? = nil) -> String {
        GlimmerMarkdownSerializer.markdown(from: text, range: range ?? NSRange(location: 0, length: text.length))
    }

    /// Everything the composer knows how to draw, including characters that look like markdown.
    static let kitchenSink = """
    # Title

    A paragraph with **bold**, *italic*, ~~struck~~, `code`, a [link](https://example.com/docs), \
    literal \\*stars\\*, snake_case and a hard break\\
    before this line.

    1. First
    2. Second with **bold**
       - nested bullet
       - [x] done task
    3. Third

    > Quote with *emphasis*
    >
    > > Nested quote

    - Item with code:

      ```swift
      let x = 1
      ```

    | a | b |
    |:--|--:|
    | **1** | `2` |

    ````md
    ```
    inner fence
    ```
    ````

    ---

    ![Alt text](https://example.com/image.png)

    - > quoted item

    \\# not a heading, 1\\. not a list
    """

    func testMarkdownRoundTrips() {
        for (name, source) in StreamingFixtures.all + [("kitchen sink", Self.kitchenSink)] {
            let original = compose(source)
            let copied = markdown(original)
            assertEquivalent(compose(copied), original, "\(name) round trip; copied:\n\(copied)")
        }
    }

    func testListsAndQuotesComeBackAsMarkdown() {
        XCTAssertEqual(markdown(compose("- a\n- b")), "- a\n- b")
        XCTAssertEqual(markdown(compose("1. a\n\n2. b")), "1. a\n\n2. b")
        XCTAssertEqual(markdown(compose("> a\n>\n> b")), "> a\n>\n> b")
        XCTAssertEqual(markdown(compose("## Head")), "## Head")
        XCTAssertEqual(markdown(compose("- [ ] todo")), "- [ ] todo")
    }

    func testPartialSelectionOmitsBlockSyntax() {
        let text = compose("> ## Quoted heading here\n\n- item one\n- item two")
        let start = (text.string as NSString).range(of: "heading").location
        let end = NSMaxRange((text.string as NSString).range(of: "item one"))
        XCTAssertEqual(markdown(text, NSRange(location: start, length: end - start)), "heading here\n\n- item one")
        let insideMarker = (text.string as NSString).range(of: "item two").location - 1
        XCTAssertEqual(markdown(text, NSRange(location: insideMarker, length: text.length - insideMarker)), "item two")
    }

    func testLiteralMarkdownCharactersSurviveARoundTrip() {
        let source = "Use \\* and \\_ and \\` literally.\n\n\\#hashtag\n\n1\\. not a list\n\n\\> not a quote"
        let original = compose(source)
        assertEquivalent(compose(markdown(original)), original, "literals")
    }

    func testAdjacentQuotesStaySeparate() {
        let original = compose("> first\n\nplain\n\n> second")
        assertEquivalent(compose(markdown(original)), original, "quote, paragraph, quote")
        let twoQuotes = compose("> first\n\n\n> second")
        assertEquivalent(compose(markdown(twoQuotes)), twoQuotes, "two quotes")
    }

    func testEmphasisDelimitersHugTheText() {
        XCTAssertEqual(markdown(compose("a **bold** b")), "a **bold** b")
        XCTAssertEqual(markdown(compose("***both***")), "***both***")
        XCTAssertEqual(markdown(compose("[**bold link**](https://x.io)")), "[**bold link**](https://x.io)")
    }

    func testCodeBlockInsideAListItemCopiesIndented() {
        let original = compose("1. Run:\n\n   ```sh\n   make\n   ```")
        let copied = markdown(original)
        XCTAssertTrue(copied.contains("\n   ```sh\n   make\n   ```"), copied)
        assertEquivalent(compose(copied), original, "code in a list item")
    }

    func testTaskItemChildrenKeepTheirStructure() {
        let nested = compose("- [ ] Buy milk\n  - whole\n  - skim")
        XCTAssertEqual(markdown(nested), "- [ ] Buy milk\n  - whole\n  - skim")
        assertEquivalent(compose(markdown(nested)), nested, "a sublist under a task item")
        let fenced = compose("- [x] Step\n\n  ```sh\n  make\n  ```")
        assertEquivalent(compose(markdown(fenced)), fenced, "a code block under a task item; copied:\n\(markdown(fenced))")
    }

    func testPlainTextKeepsMarkersAndEmbedContent() {
        let text = compose("- item\n\n```\nlet x = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(GlimmerMarkdownSerializer.plainText(from: text, range: NSRange(location: 0, length: text.length)),
                       "- item\nlet x = 1\na\tb\n1\t2")
    }

    func testMarkdownSourceWithoutARangeIsTheAnswerAsGiven() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "Hello *there*")
        XCTAssertEqual(view.markdownSource(), "Hello *there*")
        let range = (view.textView.textStorage.string as NSString).range(of: "there")
        XCTAssertEqual(view.markdownSource(for: range), "*there*")
        _ = window
    }

    func testLinesAfterAHardBreakEscapeBlockSyntax() {
        for source in ["line\\\n\\# not a heading", "line\\\n\\- not a list", "line\\\n\\> not a quote"] {
            let original = compose(source)
            assertEquivalent(compose(markdown(original)), original, "\(source); copied: \(markdown(original))")
        }
    }

    func testListLoosenessComesBackPerList() {
        for source in [
            "- a\n  - x\n\n  - y\n- b",      // tight list, loose sublist
            "- a\n\n  - x\n  - y\n\n- b",    // loose list, tight sublist
            "1. a\n   - x\n2. b",            // tight throughout
        ] {
            let original = compose(source)
            assertEquivalent(compose(markdown(original)), original, "\(source.debugDescription); copied: \(markdown(original).debugDescription)")
        }
    }

    func testMarkerOnlyLinesCopyCleanly() {
        let text = compose("- ```\n  x\n  ```")
        XCTAssertEqual(markdown(text), "-\n  ```\n  x\n  ```")
        let tab = (text.string as NSString).range(of: "\t").location
        XCTAssertFalse(markdown(text, NSRange(location: tab, length: text.length - tab)).hasPrefix("\n"))
    }

    func testAnImageInsideALinkKeepsItsLink() {
        let original = compose("see [![logo](https://x.io/a.png)](https://x.io) here")
        XCTAssertEqual(markdown(original), "see [![logo](https://x.io/a.png)](https://x.io) here")
    }

    func testEntitiesAndIntrawordUnderscoresStayLiteral() {
        let original = compose("AT&amp;T and &amp;copy; in snake_case")
        let copied = markdown(original)
        XCTAssertTrue(copied.contains("snake_case"), copied)
        assertEquivalent(compose(copied), original, "copied: \(copied)")
    }
}
