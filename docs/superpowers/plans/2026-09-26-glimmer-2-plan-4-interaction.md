# Glimmer 2.0 — Plan 4: Interaction and Accessibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a Glimmer answer behave like native text for a person using it: copy gives both plain text and markdown, a selection never reaches text still being revealed, hosts can add edit-menu and link-menu items, and VoiceOver reads a revealing answer, code blocks, tables and chips sensibly. The small compose and visual items deferred from Plans 1–3 are fixed along the way.

**Architecture:** The composer records each paragraph's markdown structure as attributes: its container prefix, whether it is in a tight list, and explicit strong and emphasis marks. A pure `GlimmerMarkdownSerializer` turns any range of composed text back into markdown or plain text, and it is tested by round-tripping fixtures (markdown → compose → serialize → compose must be equivalent). `GlimmerTextView.copy(_:)` writes both flavors. `GlimmerView` clamps the selection to the revealed length and adds host menu items through `UITextViewDelegate`. While a reveal runs it presents itself to VoiceOver as one element whose label is the revealed text, and hands back to the text view at settle.

**Tech Stack:** Swift 6, iOS 18+, UIKit (`UITextViewDelegate` edit and link menus, `UIPasteboard`, `UIFindInteraction`, `UIAccessibilityContainerDataTable`), TextKit 2, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-25-glimmer-2-engine-design.md` (§6 interaction and accessibility; §11 "copy serialization" unit tests)

**Builds on:** Plans 1–3, complete on `glimmer-2` (HEAD `9e6be02`). Plan 3's final review is fixed. Plan 5 will delete 1.x, rebuild the demo, run the on-device harness, move highlighting to the worker, append table rows incrementally, update the README and tag `2.0.0`.

**Ruling carried in this plan (spec §6 conflict):** the spec says tables "keep their own selection inside". Table cells are `UILabel`s. Making each cell selectable would need a text view per cell, costing memory and layout time for every table, and it would complicate copy across cells. Instead, a table is selected as one unit from outside (like every embed) and copies as its markdown source, which serves what people copy tables for. Code blocks keep their own selection, as they do now.

## Global Constraints

- The branch is `glimmer-2`. Commit after every task. **Do not add `Co-Authored-By` trailers. Do not push.**
- Swift 6 language mode, iOS 18 minimum, no package dependencies. Engine code goes under `Sources/Glimmer/Engine/`. Do not touch 1.x sources.
- **TextKit 2 only.** Never read `layoutManager`.
- No force unwrapping (`!`) and no force casts in library code. Tests may force-unwrap.
- In tests, write `CGFloat.greatestFiniteMagnitude`, never `.greatestFiniteMagnitude`, in `CGSize(width: <literal>, …)`.
- Test command, with a passing run ending in `** TEST SUCCEEDED **`:
  ```bash
  DEST='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0'
  xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/<TestClass> 2>&1 | tail -5
  ```
  xcodebuild sometimes hangs after printing results; kill it once the log shows `Test Suite 'Selected tests' passed|failed`. Run one xcodebuild at a time.
- The **engine suite** is every class in `Tests/GlimmerTests/Engine/` whose file name ends in `Tests.swift`. Completion is gated on it; the 1.x suite is red on `main` and out of scope.
- Reading `UIPasteboard.general` in the test runner fails ("Operation not authorized"). Tests use a named pasteboard: `UIPasteboard(name: UIPasteboard.Name("glimmer.test.copy"), create: true)`.
- The markdown pasteboard type is `net.daringfireball.markdown` (spec §6), written as UTF-8 `Data`. Plain text is written as a `String` under `UTType.utf8PlainText.identifier`.

## Review Focus

These are the five inputs the spec implies but the main tests don't exercise, ordered from most likely to bite a real user down. Each has a test in the task that owns the code.

1. **Copying a selection that starts mid-paragraph or inside a list marker** → no stray `>`, `#` or marker at the start. Test: Task 2 `testPartialSelectionOmitsBlockSyntax`.
2. **Text containing markdown-looking characters** (a literal `*`, `snake_case`, a line starting `1.` or `#`) → the copied markdown renders the same text, not new formatting. Test: Task 2 `testLiteralMarkdownCharactersSurviveARoundTrip`.
3. **Two quotes one after another** (separate blocks, not one quote with two paragraphs) → the copied markdown keeps them separate. Test: Task 2 `testAdjacentQuotesStaySeparate`.
4. **Copying while an answer is still streaming** → the pasteboard holds only revealed text. Test: Task 3 `testCopyWhileStreamingCopiesOnlyRevealedText`.
5. **A regenerated (non-append) stream while VoiceOver reads the revealing answer** → the label follows the new text, never runs past it, and nothing crashes. Test: Task 4 `testRevealLabelFollowsAReplacedStream`.

---

## File Structure

```
Sources/Glimmer/Engine/
  Theme/GlimmerAttributeKeys.swift             MODIFY  glimmerMarkdownPrefix, glimmerTightList, glimmerStrong, glimmerEmphasis (T1)
  Theme/GlimmerTheme.swift                     MODIFY  headingFont guard (T5)
  Compose/GlimmerComposer.swift                MODIFY  prefix/tight stamps, marker colors (T1, T5)
  Compose/GlimmerComposer+Inlines.swift        MODIFY  strong/emphasis stamps, inline image source (T1)
  Interact/GlimmerMarkdownSerializer.swift     CREATE  markdown and plain text from composed text (T2)
  Interact/GlimmerSelection.swift              CREATE  the selection handed to host menu actions (T3)
  Render/GlimmerTextView.swift                 MODIFY  copy override, injectable pasteboard (T3)
  GlimmerView.swift                            MODIFY  markdownSource(for:), selection clamp, menus, accessibility, frame/center (T2–T4, T6)
  GlimmerConfiguration.swift                   MODIFY  dataDetectors, allowsFind (T3)
  Embeds/GlimmerCodeBlockView.swift            MODIFY  accessibility (T4)
  Embeds/GlimmerTableView.swift                MODIFY  data-table accessibility, grid without animations, update equality (T4, T5)
  Extensions/GlimmerExtension.swift            MODIFY  GlimmerInlineToken.accessibilityLabel (T4)
  Extensions/GlimmerInlineAttachment.swift     MODIFY  chip accessibility label (T4)
  Parse/GlimmerParser.swift                    MODIFY  language() splits on any whitespace (T5)
Tests/GlimmerTests/Engine/
  GlimmerComposerTests.swift                   MODIFY  (T1, T5)
  GlimmerThemeTests.swift                      MODIFY  (T1, T5)
  GlimmerMarkdownSerializerTests.swift         CREATE  (T2)
  GlimmerInteractionTests.swift                CREATE  (T3)
  GlimmerAccessibilityTests.swift              CREATE  (T4)
  GlimmerExtensionTests.swift                  MODIFY  (T5)
  GlimmerParserTests.swift                     MODIFY  (T5)
  GlimmerTableViewTests.swift                  MODIFY  (T5)
  GlimmerVisibleBandTests.swift                MODIFY  (T6)
  GlimmerStreamingPerformanceTests.swift       MODIFY  (T6)
```

---

### Task 1: The composer records markdown structure

**Files:**
- Modify: `Sources/Glimmer/Engine/Theme/GlimmerAttributeKeys.swift`
- Modify: `Sources/Glimmer/Engine/Compose/GlimmerComposer.swift` (`Context`, `appendList`, `appendTextParagraph`, `appendEmbed`)
- Modify: `Sources/Glimmer/Engine/Compose/GlimmerComposer+Inlines.swift` (`.strong`, `.emphasis`, `.image`)
- Test: `Tests/GlimmerTests/Engine/GlimmerComposerTests.swift`, `Tests/GlimmerTests/Engine/GlimmerThemeTests.swift`

**Interfaces:**
- Produces:
  - `NSAttributedString.Key.glimmerMarkdownPrefix` (`String`, on a whole paragraph): the markdown written before the paragraph's content on its first line, **before** any list marker. That is quote markers and list indentation, e.g. `"> "`, `"   "`, `">   "`.
  - `.glimmerTightList` (`Bool`, on a whole paragraph): the paragraph belongs to a tight list's item.
  - `.glimmerStrong` / `.glimmerEmphasis` (`Bool`): on text inside `**…**` / `*…*`. Font traits stay; these marks are what copy reads, because heading fonts are bold too.
  - `.glimmerSource` also marks an inline image's alt run, with the image's markdown.

How the prefix works: a paragraph that carries a list marker (`glimmerListMarker`) gets the prefix of the line the marker sits on. Every other paragraph of that item, and every block nested in it, gets that prefix plus as many spaces as the marker's source has characters (`"- "` → 2, `"12. "` → 4). That is exactly the indentation CommonMark needs for continuation lines. Quotes add `"> "`.

- [ ] **Step 1: Write the failing tests**

Append to `GlimmerComposerTests.swift` (inside the class):

```swift
    private func prefix(of substring: String, in text: NSAttributedString) -> String? {
        attributes(of: substring, in: text)[.glimmerMarkdownPrefix] as? String
    }

    func testParagraphsRecordTheirMarkdownPrefix() {
        let text = compose("> - outer\n>   - inner\n>\n>   more of outer")
        XCTAssertEqual(prefix(of: "outer", in: text), "> ", "a marker line inside a quote")
        XCTAssertEqual(prefix(of: "inner", in: text), ">   ", "nested under a two-character marker")
        XCTAssertEqual(prefix(of: "more of outer", in: text), ">   ", "a continuation paragraph of the outer item")
        XCTAssertEqual(prefix(of: "Plain", in: compose("Plain")), "")
    }

    func testOrderedMarkersIndentTheirContentByTheirWidth() {
        let text = compose("10. ten\n\n    ```\n    code\n    ```")
        let code = (text.string as NSString).range(of: "\u{FFFC}").location
        XCTAssertEqual(text.attribute(.glimmerMarkdownPrefix, at: code, effectiveRange: nil) as? String, "    ")
    }

    func testQuoteOpeningAListItemPutsItsMarkerAfterTheBullet() {
        let text = compose("- > quoted")
        XCTAssertEqual(prefix(of: "quoted", in: text), "")
        XCTAssertEqual(attributes(of: "•", in: text)[.glimmerListMarker] as? String, "- > ")
    }

    func testTightListParagraphsAreMarked() {
        XCTAssertEqual(attributes(of: "b", in: compose("- a\n- b"))[.glimmerTightList] as? Bool, true)
        XCTAssertNil(attributes(of: "b", in: compose("- a\n\n- b"))[.glimmerTightList])
        XCTAssertNil(attributes(of: "p", in: compose("p"))[.glimmerTightList])
    }

    func testStrongAndEmphasisAreMarkedButHeadingsAreNot() {
        let text = compose("# Head\n\n**b** and *i*")
        XCTAssertEqual(attributes(of: "b", in: text)[.glimmerStrong] as? Bool, true)
        XCTAssertEqual(attributes(of: "i", in: text)[.glimmerEmphasis] as? Bool, true)
        XCTAssertNil(attributes(of: "Head", in: text)[.glimmerStrong], "a heading's bold font is not strong text")
    }

    func testInlineImageKeepsItsMarkdown() {
        let text = compose("see ![alt](https://example.com/a.png) here")
        XCTAssertEqual(attributes(of: "alt", in: text)[.glimmerSource] as? String, "![alt](https://example.com/a.png)")
    }
```

In `GlimmerThemeTests.testAttributeKeysAreNamespaced`, add:

```swift
        XCTAssertEqual(NSAttributedString.Key.glimmerQuoteContinues.rawValue, "glimmer.quoteContinues")
        XCTAssertEqual(NSAttributedString.Key.glimmerMarkdownPrefix.rawValue, "glimmer.markdownPrefix")
        XCTAssertEqual(NSAttributedString.Key.glimmerTightList.rawValue, "glimmer.tightList")
        XCTAssertEqual(NSAttributedString.Key.glimmerStrong.rawValue, "glimmer.strong")
        XCTAssertEqual(NSAttributedString.Key.glimmerEmphasis.rawValue, "glimmer.emphasis")
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerComposerTests` and `GlimmerThemeTests`. Expected: compile errors for the four new keys. Once Step 3's keys exist (and before Step 4), the tests FAIL because nothing is stamped yet.

- [ ] **Step 3: The keys**

Append inside the `extension NSAttributedString.Key` in `GlimmerAttributeKeys.swift`:

```swift
    /// The markdown before a paragraph's content on its first line, before any list marker: quote markers and list
    /// indentation (`String`, on a whole paragraph). Used by copy.
    static let glimmerMarkdownPrefix = NSAttributedString.Key("glimmer.markdownPrefix")
    /// `true` on a whole paragraph inside a tight list's item: copy joins such paragraphs without a blank line.
    static let glimmerTightList = NSAttributedString.Key("glimmer.tightList")
    /// `true` on text inside `**…**`. The font is bold too, but so are headings; copy reads this mark.
    static let glimmerStrong = NSAttributedString.Key("glimmer.strong")
    /// `true` on text inside `*…*`.
    static let glimmerEmphasis = NSAttributedString.Key("glimmer.emphasis")
```

- [ ] **Step 4: The composer stamps them**

In `GlimmerComposer.Context`, add:

```swift
        /// Markdown written before a paragraph's content on continuation lines: quote markers and list indentation.
        var markdownPrefix = ""
        /// Markdown written before the marker on an item's first line (the enclosing container's prefix).
        var markerLinePrefix = ""
        /// Inside a tight list's item.
        var isTight = false
```

In `append(_:context:marker:to:)`, `.blockQuote` case, after `inner.quoteDepth += 1`, add the quote's `"> "` to the continuation prefix. A quote that opens a list item (`- > quoted`) is written with the `>` after the marker, so its marker's source carries it. Pass `quotedMarker` instead of `marker` to the first child:

```swift
            inner.markdownPrefix += "> "
            // A quote that opens a list item is written "- > …": the marker's source carries the quote's ">".
            let quotedMarker = marker.map { marker in
                let copy = NSMutableAttributedString(attributedString: marker)
                let source = copy.attribute(.glimmerListMarker, at: 0, effectiveRange: nil) as? String ?? ""
                copy.addAttribute(.glimmerListMarker, value: source + "> ", range: NSRange(location: 0, length: copy.length))
                return copy as NSAttributedString
            }
```

`markerLinePrefix` is set only by `appendList`: a paragraph that carries a marker writes the prefix of the line its list's marker sits on.

In `appendList`, inside the `for (offset, item) in list.items.enumerated()` loop, build a per-item context from `inner` before appending the item's blocks. The existing loop body uses `inner`; replace those uses with `itemContext`:

```swift
            let markerSource = markers[offset].attribute(.glimmerListMarker, at: 0, effectiveRange: nil) as? String ?? ""
            var itemContext = inner
            itemContext.markerLinePrefix = context.markdownPrefix
            itemContext.markdownPrefix = context.markdownPrefix + String(repeating: " ", count: markerSource.count)
            itemContext.isTight = list.isTight
            let marker = markers[offset]
            if item.blocks.isEmpty {
                appendTextParagraph([], font: theme.bodyFont, context: itemContext, marker: marker, to: output)
            }
            for (index, block) in item.blocks.enumerated() {
                append(block, context: itemContext, marker: index == 0 ? marker : nil, to: output)
            }
```

A list nested in the item is appended with `itemContext`, whose `markdownPrefix` is the item's content indentation, so the nested list's marker lines use it (through `context.markdownPrefix` in the nested `appendList`).

Add a helper to `GlimmerComposer` and call it from `appendTextParagraph` (after the paragraph style is added, with `marker != nil`) and from `appendEmbed` (after its attributes are added, with `hasMarker: false`):

```swift
    /// Records what copy needs to write this paragraph back as markdown.
    private func stampMarkdown(context: Context, hasMarker: Bool, range: NSRange, in output: NSMutableAttributedString) {
        output.addAttribute(.glimmerMarkdownPrefix, value: hasMarker ? context.markerLinePrefix : context.markdownPrefix, range: range)
        if context.isTight { output.addAttribute(.glimmerTightList, value: true, range: range) }
    }
```

In `GlimmerComposer+Inlines.swift`:

```swift
            case .emphasis(let children):
                var emphasized = adding(.traitItalic, to: attributes)
                emphasized[.glimmerEmphasis] = true
                appendInlines(children, attributes: emphasized, to: output)
            case .strong(let children):
                var strong = adding(.traitBold, to: attributes)
                strong[.glimmerStrong] = true
                appendInlines(children, attributes: strong, to: output)
```

and in `.image(_, _, let alt)` bind the source too — `case .image(let source, _, let alt):` — and add `faded[.glimmerSource] = "![\(alt)](\(source))"`.

- [ ] **Step 5: Run to verify they pass**

Run the test command for `GlimmerComposerTests`, `GlimmerThemeTests`, `GlimmerStreamParityTests` and `GlimmerStreamingDocumentTests`. Expected: PASS. Parity holds because the stamps are deterministic.

- [ ] **Step 6: Run the engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: record each paragraph's markdown structure for copy

Paragraphs carry their container prefix (quote markers and list indentation)
and whether they sit in a tight list; strong and emphasized text carry
explicit marks, since heading fonts are bold too; inline images keep their
markdown."
```

---

### Task 2: Markdown and plain text from composed text

**Files:**
- Create: `Sources/Glimmer/Engine/Interact/GlimmerMarkdownSerializer.swift`
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (`markdownSource(for:)`)
- Test: `Tests/GlimmerTests/Engine/GlimmerMarkdownSerializerTests.swift`

**Interfaces:**
- Consumes: Task 1's keys; `glimmerListMarker`, `glimmerSource`, `glimmerInlineCode`, `glimmerQuoteContinues`, `.accessibilityTextHeadingLevel`, `.link`, `.strikethroughStyle`; `GlimmerBlockAttachment.embed`, `GlimmerInlineAttachment.token`
- Produces: `enum GlimmerMarkdownSerializer { static func markdown(from: NSAttributedString, range: NSRange) -> String; static func plainText(from: NSAttributedString, range: NSRange) -> String }`; `GlimmerView.markdownSource(for range: NSRange? = nil) -> String` (public)

The rules the serializer follows:
- **Paragraphs**, split on `\n`. A paragraph's block syntax is written only when the range includes the paragraph's start. That covers its prefix, its list marker's source, and `#`s from its heading level.
- **Between paragraphs:** markdown gets one newline between two tight-list paragraphs and a blank line otherwise. The blank line carries the containers both paragraphs share (the common prefix of their `glimmerMarkdownPrefix`, with trailing spaces trimmed). If the first paragraph closes quote levels (`glimmerQuoteContinues` = k), only k quote markers carry over. Plain text always uses one newline.
- **Runs inside a paragraph:**
  - A list-marker run becomes its source, or nothing if the paragraph's start is not selected.
  - A block attachment becomes its `glimmerSource` in markdown, or its plain text (code, tab-separated table rows, alt text, `---`) in plain text.
  - A chip becomes `token.source` or `token.displayText`.
  - An inline-image run becomes its `glimmerSource` or its alt text.
  - Other runs are grouped by style and written with `**`, `*`, `~~`, backtick fences and `[text](url)`. Whitespace at a group's edges stays outside the delimiters, and plain text is backslash-escaped.
- **Lines inside a paragraph** (an embed's multi-line source, a hard break `U+2028` written as `\` + newline) continue with the paragraph's continuation prefix: its prefix, plus spaces for its marker.

- [ ] **Step 1: Write the failing tests**

Create `Tests/GlimmerTests/Engine/GlimmerMarkdownSerializerTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerMarkdownSerializerTests`. Expected: compile errors (`GlimmerMarkdownSerializer`, `markdownSource`).

- [ ] **Step 3: The serializer**

Create `Sources/Glimmer/Engine/Interact/GlimmerMarkdownSerializer.swift`:

```swift
import UIKit

/// Turns composed text back into markdown or plain text, for copy and `GlimmerView.markdownSource(for:)`. It reads
/// what the composer records: each paragraph's container prefix (`glimmerMarkdownPrefix`), list markers
/// (`glimmerListMarker`), heading levels, tight lists, quote ends, inline styles, and the markdown source of embeds,
/// chips and inline images. A paragraph's block syntax is written only when the range includes its start.
enum GlimmerMarkdownSerializer {
    static func markdown(from text: NSAttributedString, range: NSRange) -> String {
        serialize(text, range: range, asMarkdown: true)
    }

    static func plainText(from text: NSAttributedString, range: NSRange) -> String {
        serialize(text, range: range, asMarkdown: false)
    }

    // MARK: - Paragraphs

    private struct Paragraph {
        /// The paragraph without its terminating newline.
        let content: NSRange
        let prefix: String
        let isTight: Bool
        /// Quote levels that continue past this paragraph, when it closes a quote.
        let quoteContinues: Int?
        let headingLevel: Int?
        /// Only a list marker: the item opens with a list or an embed, written on the next line.
        let isMarkerOnly: Bool

        init(_ text: NSAttributedString, range whole: NSRange) {
            var content = whole
            if content.length > 0, (text.string as NSString).character(at: NSMaxRange(content) - 1) == 0x0A {
                content.length -= 1
            }
            self.content = content
            let attributes = text.attributes(at: whole.location, effectiveRange: nil)
            prefix = attributes[.glimmerMarkdownPrefix] as? String ?? ""
            isTight = attributes[.glimmerTightList] as? Bool ?? false
            quoteContinues = attributes[.glimmerQuoteContinues] as? Int
            headingLevel = (attributes[.accessibilityTextHeadingLevel] as? Int).flatMap { $0 > 0 ? $0 : nil }
            var marker = NSRange()
            isMarkerOnly = content.length > 0
                && text.attribute(.glimmerListMarker, at: content.location, longestEffectiveRange: &marker, in: content) != nil
                && NSMaxRange(marker) >= NSMaxRange(content)
        }
    }

    private static func serialize(_ text: NSAttributedString, range: NSRange, asMarkdown: Bool) -> String {
        let string = text.string as NSString
        let wanted = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        guard wanted.length > 0 else { return "" }
        var output = ""
        var previous: Paragraph?
        var location = wanted.location
        while location < NSMaxRange(wanted) {
            let whole = string.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(whole)
            let paragraph = Paragraph(text, range: whole)
            let includesStart = wanted.location <= paragraph.content.location
            let selected = NSIntersectionRange(paragraph.content, wanted)
            // A selection that starts on a paragraph's newline takes nothing from that paragraph.
            guard selected.length > 0 || includesStart else { continue }
            if let previous { output += separator(after: previous, before: paragraph, asMarkdown: asMarkdown) }
            output += write(paragraph, selected: selected, includesStart: includesStart, in: text, asMarkdown: asMarkdown)
            previous = paragraph
        }
        return output
    }

    /// One newline inside a tight list or after a marker-only line, else a blank line carrying the containers both
    /// paragraphs share.
    private static func separator(after first: Paragraph, before second: Paragraph, asMarkdown: Bool) -> String {
        guard asMarkdown else { return "\n" }
        if first.isMarkerOnly || (first.isTight && second.isTight) { return "\n" }
        var shared = String(zip(first.prefix, second.prefix).prefix { $0 == $1 }.map(\.0))
        if let continuing = first.quoteContinues {
            // The first paragraph closes quote levels: only the ones that continue carry across the blank line.
            var kept = ""
            var quotes = 0
            for character in shared {
                if character == ">" {
                    guard quotes < continuing else { break }
                    quotes += 1
                }
                kept.append(character)
            }
            shared = kept
        }
        while shared.last == " " { shared.removeLast() }
        return "\n" + shared + "\n"
    }

    private static func write(
        _ paragraph: Paragraph, selected: NSRange, includesStart: Bool, in text: NSAttributedString, asMarkdown: Bool
    ) -> String {
        let string = text.string as NSString
        var marker = ""
        var body = ""
        var segments: [Segment] = []
        func flush() {
            body += asMarkdown ? inlineMarkdown(segments) : segments.map(\.text).joined()
            segments.removeAll()
        }
        if selected.length > 0 {
            text.enumerateAttributes(in: selected, options: []) { attributes, run, _ in
                if let source = attributes[.glimmerListMarker] as? String {
                    if includesStart { marker = source }
                } else if let attachment = attributes[.attachment] as? GlimmerBlockAttachment {
                    flush()
                    body += asMarkdown ? attributes[.glimmerSource] as? String ?? "" : plainText(of: attachment.embed)
                } else if let chip = attributes[.attachment] as? GlimmerInlineAttachment {
                    flush()
                    body += asMarkdown ? chip.token.source : chip.token.displayText
                } else if let source = attributes[.glimmerSource] as? String {
                    // An inline image's alt text: written once, however its runs split.
                    var whole = NSRange()
                    _ = text.attribute(.glimmerSource, at: run.location, longestEffectiveRange: &whole, in: selected)
                    flush()
                    if whole.location == run.location { body += asMarkdown ? source : string.substring(with: whole) }
                } else {
                    segments.append(Segment(text: string.substring(with: run), style: Style(attributes)))
                }
            }
            flush()
        }
        guard asMarkdown else { return marker + body.replacingOccurrences(of: "\u{2028}", with: "\n") }
        // Later lines of the paragraph (an embed's source, a hard break) continue inside its containers.
        let continuation = includesStart ? paragraph.prefix + String(repeating: " ", count: marker.count) : ""
        body = body.replacingOccurrences(of: "\u{2028}", with: "\\\n")
            .replacingOccurrences(of: "\n", with: "\n" + continuation)
        guard includesStart else { return body }
        let heading = paragraph.headingLevel.map { String(repeating: "#", count: $0) + " " } ?? ""
        return paragraph.prefix + marker + heading + escapingBlockStart(body)
    }

    // MARK: - Inline runs

    private struct Segment {
        var text: String
        let style: Style
    }

    private struct Style: Equatable {
        /// Outermost first.
        let marks: [Mark]
        let isCode: Bool

        init(_ attributes: [NSAttributedString.Key: Any]) {
            var marks: [Mark] = []
            if let url = attributes[.link] as? URL { marks.append(.link(url)) }
            if attributes[.glimmerStrong] as? Bool == true { marks.append(.strong) }
            if attributes[.glimmerEmphasis] as? Bool == true { marks.append(.emphasis) }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { marks.append(.strikethrough) }
            self.marks = marks
            isCode = attributes[.glimmerInlineCode] as? Bool ?? false
        }
    }

    private enum Mark: Equatable {
        case link(URL), strong, emphasis, strikethrough

        var opening: String {
            switch self {
            case .link: "["
            case .strong: "**"
            case .emphasis: "*"
            case .strikethrough: "~~"
            }
        }

        var closing: String {
            switch self {
            case .link(let url): "](\(GlimmerMarkdownSerializer.destination(url)))"
            case .strong: "**"
            case .emphasis: "*"
            case .strikethrough: "~~"
            }
        }
    }

    /// Writes styled runs, opening and closing marks as the style changes, so nesting comes back as it was parsed
    /// (`**a *b* c**`). A delimiter never has whitespace on its inner side (`** bold**` would not parse): edge
    /// whitespace moves outside it.
    private static func inlineMarkdown(_ segments: [Segment]) -> String {
        // One piece per style: two code spans side by side would read as one span.
        var merged: [Segment] = []
        for segment in segments {
            if let last = merged.last, last.style == segment.style {
                merged[merged.count - 1].text += segment.text
            } else {
                merged.append(segment)
            }
        }
        var output = ""
        var open: [Mark] = []
        func close(from index: Int) {
            let trailing = String(output.reversed().prefix(while: \.isWhitespace).reversed())
            output.removeLast(trailing.count)
            for mark in open[index...].reversed() { output += mark.closing }
            open.removeSubrange(index...)
            output += trailing
        }
        for segment in merged {
            if let stale = open.firstIndex(where: { !segment.style.marks.contains($0) }) { close(from: stale) }
            var piece = segment.style.isCode ? codeSpan(segment.text) : escaped(segment.text)
            let opening = segment.style.marks.filter { !open.contains($0) }
            if !opening.isEmpty {
                let leading = String(piece.prefix(while: \.isWhitespace))
                piece.removeFirst(leading.count)
                output += leading
                // Whitespace alone opens nothing; the next styled piece opens the marks.
                if !piece.isEmpty {
                    output += opening.map(\.opening).joined()
                    open += opening
                }
            }
            output += piece
        }
        if !open.isEmpty { close(from: 0) }
        return output
    }

    private static func codeSpan(_ code: String) -> String {
        let fence = String(repeating: "`", count: longestBacktickRun(in: code) + 1)
        // A span that starts or ends with a backtick, or with a space at both ends, needs a space inside the fence.
        let pads = code.hasPrefix("`") || code.hasSuffix("`")
            || (code.hasPrefix(" ") && code.hasSuffix(" ") && code.contains { $0 != " " })
        let pad = pads ? " " : ""
        return fence + pad + code + pad + fence
    }

    static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    private static func destination(_ url: URL) -> String {
        let string = url.absoluteString
        return string.contains { $0 == " " || $0 == "(" || $0 == ")" } ? "<\(string)>" : string
    }

    /// Backslash-escapes characters that could start inline syntax.
    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_[]<~".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// Escapes a paragraph start that would read as block syntax: a heading, a quote, a bullet or a numbered item.
    private static func escapingBlockStart(_ body: String) -> String {
        if body.hasPrefix("#") || body.hasPrefix(">") { return "\\" + body }
        if body == "-" || body == "+" || body.hasPrefix("- ") || body.hasPrefix("+ ") { return "\\" + body }
        if let match = body.prefixMatch(of: #/(\d{1,9})[.)](?: |$)/#) {
            return String(match.1) + "\\" + body[match.1.endIndex...]
        }
        return body
    }

    // MARK: - Embeds

    private static func plainText(of embed: GlimmerEmbed) -> String {
        switch embed {
        case .codeBlock(_, let code):
            code
        case .table(let header, let rows, _):
            ([header] + rows).map { $0.map(\.string).joined(separator: "\t") }.joined(separator: "\n")
        case .image(_, let alt):
            alt
        case .thematicBreak:
            "---"
        }
    }
}
```

- [ ] **Step 4: Embed sources that round-trip**

The kitchen sink's table has styled cells and its code shows a fence, so both sources must carry that. In `GlimmerComposer.append`:

```swift
        case .codeBlock(let language, let code):
            appendEmbed(.codeBlock(language: language, code: code), source: Self.fencedSource(code, language: language),
                        context: context, marker: marker, to: output)
        case .table(let table):
            let embed = tableEmbed(table)
            appendEmbed(embed, source: tableSource(embed), context: context, marker: marker, to: output)
```

Add to `GlimmerComposer`:

```swift
    /// A fence longer than any backtick run in the code, so code that shows a fence copies intact.
    static func fencedSource(_ code: String, language: String?) -> String {
        let fence = String(repeating: "`", count: max(3, GlimmerMarkdownSerializer.longestBacktickRun(in: code) + 1))
        return "\(fence)\(language ?? "")\n\(code)\n\(fence)"
    }
```

and replace `tableSource(_ table: GlimmerTable)` with a version that writes each composed cell as markdown (styles, code, links), with pipes escaped:

```swift
    private func tableSource(_ embed: GlimmerEmbed) -> String {
        guard case .table(let header, let rows, let alignments) = embed else { return "" }
        func line(_ cells: [NSAttributedString]) -> String {
            let written = cells.map { cell in
                GlimmerMarkdownSerializer.markdown(from: cell, range: NSRange(location: 0, length: cell.length))
                    .replacingOccurrences(of: "|", with: "\\|")
            }
            return "| " + written.joined(separator: " | ") + " |"
        }
        let divider = "| " + alignments.map { alignment in
            switch alignment {
            case .left: ":---"
            case .center: ":---:"
            case .right: "---:"
            case .none: "---"
            }
        }.joined(separator: " | ") + " |"
        return ([line(header), divider] + rows.map(line)).joined(separator: "\n")
    }
```

- [ ] **Step 5: `markdownSource(for:)`**

In `GlimmerView`, under `linkAction(for:)`:

```swift
    /// The markdown for `range` of the shown text (UTF-16 offsets, as in `UITextView.selectedRange`), or — for nil —
    /// the whole answer exactly as last given to `update`. Backs "Copy answer" buttons.
    public func markdownSource(for range: NSRange? = nil) -> String {
        guard let range else { return markdown }
        return GlimmerMarkdownSerializer.markdown(from: textView.textStorage, range: range)
    }
```

- [ ] **Step 6: Run to verify they pass**

Run the test command for `GlimmerMarkdownSerializerTests`, `GlimmerComposerTests`, `GlimmerStreamParityTests` and `GlimmerStreamingDocumentTests`. Expected: PASS. If a round trip fails, the failure message prints the copied markdown. Compare it with the source: the serializer's output is the thing under test, not the fixture.

- [ ] **Step 7: Run the engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: serialize composed text back to markdown and plain text

GlimmerMarkdownSerializer writes any range of an answer as markdown (block
prefixes, list markers, headings, inline styles, embed and chip sources,
escapes) or plain text. Fixtures round-trip: markdown, compose, serialize,
compose again gives the same text. GlimmerView.markdownSource(for:) backs
Copy answer."
```

---

### Task 3: Copy, selection while streaming, menus, data detectors, find

**Files:**
- Create: `Sources/Glimmer/Engine/Interact/GlimmerSelection.swift`
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift` (`pasteboard`, `copy(_:)`)
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (delegate: selection clamp, edit menu, link menu; `editMenuActions`, `linkMenuActions`; configuration applied in `rebuildDocument`)
- Modify: `Sources/Glimmer/Engine/GlimmerConfiguration.swift` (`dataDetectors`, `allowsFind`)
- Test: `Tests/GlimmerTests/Engine/GlimmerInteractionTests.swift`

**Interfaces:**
- Consumes: Task 2's serializer
- Produces:
  - `public struct GlimmerSelection: Sendable { public let range: NSRange; public let plainText: String; public let markdown: String }`
  - `GlimmerView.editMenuActions: ((GlimmerSelection) -> [UIMenuElement])?`
  - `GlimmerView.linkMenuActions: ((URL) -> [UIMenuElement])?`
  - `GlimmerView.linkMenu(for:defaultMenu:) -> UIMenu` (internal)
  - `GlimmerTextView.pasteboard: UIPasteboard`, `GlimmerTextView.copiesMarkdown: Bool`
  - `GlimmerConfiguration.dataDetectors: UIDataDetectorTypes` (default `[]`)
  - `GlimmerConfiguration.allowsFind: Bool` (default `false`)

- [ ] **Step 1: Write the failing tests**

Create `Tests/GlimmerTests/Engine/GlimmerInteractionTests.swift`:

```swift
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerInteractionTests: XCTestCase {
    private let pasteboard = UIPasteboard(name: UIPasteboard.Name("glimmer.test.copy"), create: true)!

    private func string(_ type: String) -> String? {
        let value = pasteboard.items.first?[type]
        if let string = value as? String { return string }
        if let data = value as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    private func settledView(_ markdown: String) -> (GlimmerView, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: markdown)
        view.textView.pasteboard = pasteboard
        return (view, window)
    }

    func testCopyWritesPlainTextAndMarkdown() {
        let (view, window) = settledView("Some **bold** text.\n\n- item")
        view.textView.selectedRange = NSRange(location: 0, length: view.textView.textStorage.length)
        view.textView.copy(nil)
        XCTAssertEqual(string(UTType.utf8PlainText.identifier), "Some bold text.\n- item")
        XCTAssertEqual(string("net.daringfireball.markdown"), "Some **bold** text.\n\n- item")
        _ = window
    }

    func testSelectionNeverReachesUnrevealedText() async throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: String(repeating: "Streaming words arrive one phrase at a time. ", count: 8), isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.2)
        let revealed = try XCTUnwrap(view.engine).revealedLength
        XCTAssertLessThan(revealed, view.textView.textStorage.length)
        view.textView.selectedRange = NSRange(location: 0, length: view.textView.textStorage.length)
        view.textViewDidChangeSelection(view.textView)
        XCTAssertLessThanOrEqual(NSMaxRange(view.textView.selectedRange), revealed)
        _ = window
    }

    func testCopyWhileStreamingCopiesOnlyRevealedText() async throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 390, height: 800)
        view.textView.pasteboard = pasteboard
        let answer = String(repeating: "Streaming words arrive one phrase at a time. ", count: 8)
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.2)
        view.textView.selectedRange = NSRange(location: 0, length: view.textView.textStorage.length)
        view.textViewDidChangeSelection(view.textView)
        view.textView.copy(nil)
        let copied = try XCTUnwrap(string(UTType.utf8PlainText.identifier))
        XCTAssertLessThan(copied.count, answer.count)
        XCTAssertTrue(answer.hasPrefix(copied))
        _ = window
    }

    func testEditMenuAddsHostActions() throws {
        let (view, window) = settledView("Ask about this sentence.")
        var received: GlimmerSelection?
        view.editMenuActions = { selection in
            received = selection
            return [UIAction(title: "Ask SuperMe") { _ in }]
        }
        let range = (view.textView.textStorage.string as NSString).range(of: "this sentence")
        let menu = try XCTUnwrap(view.textView(view.textView, editMenuForTextIn: range, suggestedActions: []))
        XCTAssertTrue(menu.children.contains { ($0 as? UIAction)?.title == "Ask SuperMe" })
        XCTAssertEqual(received?.plainText, "this sentence")
        XCTAssertEqual(received?.markdown, "this sentence")
        _ = window
    }

    func testLinkMenuKeepsTheDefaultAndAddsHostItems() {
        let (view, window) = settledView("[docs](https://example.com)")
        view.linkMenuActions = { url in [UIAction(title: "Open in App \(url.host() ?? "")") { _ in }] }
        let menu = view.linkMenu(for: URL(string: "https://example.com")!,
                                 defaultMenu: UIMenu(children: [UIAction(title: "Copy Link") { _ in }]))
        XCTAssertEqual(menu.children.compactMap { ($0 as? UIAction)?.title }, ["Copy Link", "Open in App example.com"])
        _ = window
    }

    func testCopyInsideACodeBlockCopiesTheCodeAsIs() {
        let code = GlimmerCodeBlockView(code: "let snake_case = 1", language: "swift", theme: .default,
                                        highlighter: GlimmerBasicHighlighter())
        code.textView.pasteboard = pasteboard
        code.textView.selectedRange = NSRange(location: 0, length: code.textView.textStorage.length)
        code.textView.copy(nil)
        XCTAssertEqual(pasteboard.string, "let snake_case = 1")
        XCTAssertNil(string("net.daringfireball.markdown"), "code copies as code, not as escaped markdown")
    }

    func testDataDetectorsAndFindFollowTheConfiguration() {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        XCTAssertEqual(GlimmerView(configuration: configuration).textView.dataDetectorTypes, [])
        configuration.dataDetectors = [.phoneNumber, .link]
        configuration.allowsFind = true
        let view = GlimmerView(configuration: configuration)
        XCTAssertEqual(view.textView.dataDetectorTypes, [.phoneNumber, .link])
        XCTAssertTrue(view.textView.isFindInteractionEnabled)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerInteractionTests`. Expected: compile errors (`pasteboard`, `GlimmerSelection`, `editMenuActions`, `linkMenu`, `dataDetectors`, `allowsFind`, `textViewDidChangeSelection`). Check the SDK for `UITextItem.MenuConfiguration`'s initializer and preview type before writing Step 4 (`xcrun --sdk iphonesimulator --show-sdk-path`, then grep `UITextItem` in UIKit's headers or swiftinterface).

- [ ] **Step 3: Selection type, configuration, copy**

Create `Sources/Glimmer/Engine/Interact/GlimmerSelection.swift`:

```swift
import Foundation

/// A selection in an answer, as host menu actions receive it.
public struct GlimmerSelection: Sendable {
    /// UTF-16 offsets into the shown text.
    public let range: NSRange
    public let plainText: String
    public let markdown: String
}
```

In `GlimmerConfiguration`, add the two properties with doc comments and init parameters at the end, with defaults:

```swift
    /// Data detectors on the text (phone numbers, addresses, …). Off by default: they cost main-thread time.
    public var dataDetectors: UIDataDetectorTypes
    /// Whether the text offers the system Find interaction.
    public var allowsFind: Bool
```

with `dataDetectors: UIDataDetectorTypes = [], allowsFind: Bool = false` in `init`. If `UIDataDetectorTypes` is not `Sendable` in this SDK, store `dataDetectorsRawValue: UInt` privately and expose `dataDetectors` as a computed property; ledger the ruling.

In `GlimmerTextView`, add:

```swift
    /// Where Copy writes. The general pasteboard unless a host (or a test) redirects it.
    var pasteboard: UIPasteboard = .general
    /// False for a code block's text, which copies as the code itself.
    var copiesMarkdown = true

    /// Copies the selection as plain text and as markdown (`net.daringfireball.markdown`), so a paste into a
    /// markdown-aware app keeps lists, code and emphasis.
    override func copy(_ sender: Any?) {
        let range = selectedRange
        guard range.length > 0 else { return }
        guard copiesMarkdown else {
            pasteboard.string = (textStorage.string as NSString).substring(with: range)
            return
        }
        let plain = GlimmerMarkdownSerializer.plainText(from: textStorage, range: range)
        let markdown = GlimmerMarkdownSerializer.markdown(from: textStorage, range: range)
        pasteboard.setItems([[
            UTType.utf8PlainText.identifier: plain,
            "net.daringfireball.markdown": Data(markdown.utf8),
        ]])
    }
```

(`import UniformTypeIdentifiers` at the top.) In `GlimmerCodeBlockView.init`, set `textView.copiesMarkdown = false`, and route its pasteboard through the view's own (`pasteboard.didSet { textView.pasteboard = pasteboard }` on the code block's `pasteboard` property) so a host redirecting one redirects both.

- [ ] **Step 4: Delegate: selection clamp, menus; configuration applied**

In `GlimmerView`, add:

```swift
    /// Items appended to the edit menu for a selection (for example "Ask about this").
    public var editMenuActions: ((GlimmerSelection) -> [UIMenuElement])?
    /// Items appended to a link's menu.
    public var linkMenuActions: ((URL) -> [UIMenuElement])?

    /// The link's default menu plus the host's items.
    func linkMenu(for url: URL, defaultMenu: UIMenu) -> UIMenu {
        guard let linkMenuActions else { return defaultMenu }
        return defaultMenu.replacingChildren(defaultMenu.children + linkMenuActions(url))
    }
```

and extend `extension GlimmerView: UITextViewDelegate`:

```swift
    /// While a reveal runs, the selection stops at the revealed text: nobody can select or copy words not shown yet.
    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard let engine else { return }
        let limit = engine.revealedLength
        let selected = textView.selectedRange
        guard NSMaxRange(selected) > limit else { return }
        let start = min(selected.location, limit)
        textView.selectedRange = NSRange(location: start, length: limit - start)
    }

    public func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let editMenuActions, range.length > 0 else { return nil }
        let selection = GlimmerSelection(
            range: range,
            plainText: GlimmerMarkdownSerializer.plainText(from: textView.textStorage, range: range),
            markdown: GlimmerMarkdownSerializer.markdown(from: textView.textStorage, range: range)
        )
        return UIMenu(children: suggestedActions + editMenuActions(selection))
    }

    public func textView(
        _ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
        guard case .link(let url) = textItem.content, linkMenuActions != nil else { return nil }
        return UITextItem.MenuConfiguration(preview: .default, menu: linkMenu(for: url, defaultMenu: defaultMenu))
    }
```

In `rebuildDocument()`, before `composeSynchronously()`:

```swift
        textView.dataDetectorTypes = configuration.dataDetectors
        textView.isFindInteractionEnabled = configuration.allowsFind
```

- [ ] **Step 5: Run to verify they pass**

Run the test command for `GlimmerInteractionTests` and `GlimmerViewTests`. Expected: PASS.

- [ ] **Step 6: On-simulator check, engine suite, commit**

Build and run the demo. Open Long Answer (2.0), long-press a word in a bulleted item, drag the end handle into the next paragraph, and tap Copy. Then run `xcrun simctl pbpaste <udid>`. Expected: the plain text of the selection, with `- ` before the item. Screenshot the selection and edit menu.

Run every engine test class. Expected: all pass.

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: copy markdown, stop selection at the reveal, host menu items

Copy writes plain text and net.daringfireball.markdown. While a reveal runs
the selection stops at the revealed text. Hosts append edit-menu and
link-menu items; data detectors and Find are opt-in configuration."
```

---

### Task 4: VoiceOver

**Files:**
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (accessibility while revealing; hand-back at settle)
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerCodeBlockView.swift`
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerTableView.swift` (`UIAccessibilityContainerDataTable`)
- Modify: `Sources/Glimmer/Engine/Extensions/GlimmerExtension.swift` (`GlimmerInlineToken.accessibilityLabel`)
- Modify: `Sources/Glimmer/Engine/Extensions/GlimmerInlineAttachment.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerAccessibilityTests.swift`

**Interfaces:**
- Consumes: Task 2's `GlimmerMarkdownSerializer.plainText(from:range:)`
- Produces: `GlimmerInlineToken.accessibilityLabel: String?` (public, init parameter with default `nil`); `GlimmerTableView` conforms to `UIAccessibilityContainerDataTable`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GlimmerTests/Engine/GlimmerAccessibilityTests.swift`:

```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerAccessibilityTests: XCTestCase {
    private let answer = "First sentence of the answer arrives now. Then a second sentence follows it closely, and more."
    private let theme = GlimmerTheme.default

    private func revealingView() -> (GlimmerView, ManualRevealClock, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        return (view, clock, hostInWindow(view, width: 320, height: 800))
    }

    func testRevealingViewIsOneElementWithTheRevealedText() async {
        let (view, clock, window) = revealingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.2)
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertTrue(view.textView.accessibilityElementsHidden)
        let label = view.accessibilityLabel ?? ""
        XCTAssertFalse(label.isEmpty)
        XCTAssertLessThan(label.count, answer.count, "only what is revealed")
        XCTAssertTrue(answer.hasPrefix(label))
        _ = window
    }

    func testSettleHandsAccessibilityBackToTheTextView() async {
        let (view, clock, window) = revealingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        view.update(markdown: answer, isStreaming: false)
        await view.pendingDocument?.value
        clock.advance(to: 30)
        XCTAssertNil(view.engine)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertFalse(view.textView.accessibilityElementsHidden)
        _ = window
    }

    func testRevealLabelFollowsAReplacedStream() async {
        let (view, clock, window) = revealingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.5)
        let regenerated = "A short new answer."
        view.update(markdown: regenerated, isStreaming: true)
        await view.pendingDocument?.value
        let label = view.accessibilityLabel ?? ""
        XCTAssertLessThanOrEqual(label.count, regenerated.count)
        XCTAssertTrue(regenerated.hasPrefix(label))
        _ = window
    }

    func testCodeBlockReadsItsLanguageAndOffersCopy() {
        let code = GlimmerCodeBlockView(code: "let x = 1", language: "swift", theme: theme, highlighter: GlimmerBasicHighlighter())
        XCTAssertEqual(code.textView.accessibilityLabel, "Code, swift")
        XCTAssertFalse(code.languageLabel.isAccessibilityElement)
        let elements = code.accessibilityElements as? [NSObject] ?? []
        XCTAssertTrue(elements.contains(code.textView))
        XCTAssertTrue(elements.contains(code.copyButton))
        let plain = GlimmerCodeBlockView(code: "x", language: nil, theme: theme, highlighter: GlimmerBasicHighlighter())
        XCTAssertEqual(plain.textView.accessibilityLabel, "Code")
    }

    func testTableIsADataTableWithHeaders() throws {
        let cell = { (text: String) in NSAttributedString(string: text) }
        let table = GlimmerTableView(header: [cell("Name"), cell("Value")], rows: [[cell("a"), cell("1")], [cell("b"), cell("2")]],
                                     alignments: [.none, .none], theme: theme)
        table.frame = CGRect(x: 0, y: 0, width: 300, height: table.embedHeight(forWidth: 300))
        table.layoutIfNeeded()
        XCTAssertEqual(table.accessibilityContainerType, .dataTable)
        XCTAssertEqual(table.accessibilityRowCount(), 3)
        XCTAssertEqual(table.accessibilityColumnCount(), 2)
        let element = try XCTUnwrap(table.accessibilityDataTableCellElement(forRow: 2, column: 1) as? UIAccessibilityElement)
        XCTAssertEqual(element.accessibilityLabel, "2")
        let headers = table.accessibilityHeaderElements(forColumn: 1)?.compactMap { ($0 as? UIAccessibilityElement)?.accessibilityLabel }
        XCTAssertEqual(headers, ["Value"])
    }

    func testChipReadsItsAccessibilityLabel() {
        let text = "Ada"
        let token = GlimmerInlineToken(range: text.startIndex..<text.endIndex, kind: "mention", displayText: "@Ada",
                                       source: "[Ada,@1]", accessibilityLabel: "Mention, Ada")
        let chip = GlimmerInlineAttachment(token: token, glimmerExtension: NoViewExtension(), theme: theme)
        XCTAssertEqual(chip.chipView().accessibilityLabel, "Mention, Ada")
        let plainToken = GlimmerInlineToken(range: text.startIndex..<text.endIndex, kind: "k", displayText: "@Ada", source: "s")
        let plainChip = GlimmerInlineAttachment(token: plainToken, glimmerExtension: NoViewExtension(), theme: theme)
        XCTAssertEqual(plainChip.chipView().accessibilityLabel, "@Ada")
    }
}

private struct NoViewExtension: GlimmerExtension {}
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerAccessibilityTests`. Expected: compile errors (`accessibilityLabel:` in the token init, the data-table methods). After Step 3 adds the token property, the view, code, table and chip assertions FAIL.

- [ ] **Step 3: The revealing view as one element**

In `GlimmerView`, add:

```swift
    // MARK: - Accessibility

    /// While a reveal runs the view is one element that reads what is revealed so far. The text view underneath is
    /// hidden, because its unrevealed text is laid out but invisible. At settle the text view takes over, with
    /// line and word navigation and the links rotor.
    public override var isAccessibilityElement: Bool {
        get { engine != nil }
        set {}
    }

    public override var accessibilityLabel: String? {
        get {
            guard let engine else { return super.accessibilityLabel }
            let revealed = min(engine.revealedLength, textView.textStorage.length)
            return GlimmerMarkdownSerializer.plainText(from: textView.textStorage, range: NSRange(location: 0, length: revealed))
        }
        set { super.accessibilityLabel = newValue }
    }

    public override var accessibilityTraits: UIAccessibilityTraits {
        get { engine != nil ? [.staticText, .updatesFrequently] : super.accessibilityTraits }
        set { super.accessibilityTraits = newValue }
    }
```

In `startRevealIfNeeded(isStreaming:)`, after the mask is attached, add `textView.accessibilityElementsHidden = true`. In `endReveal()`, hand back. Move VoiceOver's focus to the text only when it was on this answer: moving it from elsewhere (an earlier message the person is reading) would yank them away.

```swift
    private func endReveal() {
        // Read before `engine` clears: while revealing, this view is the element VoiceOver focuses.
        let hadFocus = engine != nil && accessibilityElementIsFocused()
        engine = nil
        syncEmbedUnits()
        clock.cancel()
        textView.layer.mask = nil
        textView.accessibilityElementsHidden = false
        if hadFocus { UIAccessibility.post(notification: .layoutChanged, argument: textView) }
    }
```

- [ ] **Step 4: Code blocks, tables, chips**

In `GlimmerCodeBlockView.init`, after the subviews are added:

```swift
        // VoiceOver: "Code, swift", then the code, then the Copy button. The header label would repeat the language.
        textView.accessibilityLabel = language.map { "Code, \($0)" } ?? "Code"
        languageLabel.isAccessibilityElement = false
        accessibilityElements = theme.showsCodeBlockHeader ? [textView, copyButton] : [textView]
```

In `GlimmerTableView`, add the conformance and the cell elements. Each element reads its label's frame when VoiceOver asks, so a table scrolled sideways still points at the right cell:

```swift
/// One table cell for VoiceOver: its text, its position, and where its label is on screen.
final class GlimmerTableCellElement: UIAccessibilityElement, UIAccessibilityContainerDataTableCell {
    let row: Int
    let column: Int
    private weak var label: UILabel?

    init(container: GlimmerTableView, row: Int, column: Int, label: UILabel) {
        self.row = row
        self.column = column
        self.label = label
        super.init(accessibilityContainer: container)
        accessibilityLabel = label.attributedText?.string
        accessibilityTraits = row == 0 ? .header : .staticText
    }

    override var accessibilityFrame: CGRect {
        get { label.map { UIAccessibility.convertToScreenCoordinates($0.bounds, in: $0) } ?? .zero }
        set {}
    }

    func accessibilityRowRange() -> NSRange { NSRange(location: row, length: 1) }
    func accessibilityColumnRange() -> NSRange { NSRange(location: column, length: 1) }
}
```

In `GlimmerTableView`: add `private var cellElements: [[GlimmerTableCellElement]] = []`, set `accessibilityContainerType = .dataTable` in `init`, and rebuild the elements at the end of `rebuildCells(header:rows:)`:

```swift
        cellElements = cellLabels.enumerated().map { row, labels in
            labels.enumerated().map { column, label in
                GlimmerTableCellElement(container: self, row: row, column: column, label: label)
            }
        }
```

In the class body:

```swift
    override var accessibilityElements: [Any]? {
        get { cellElements.flatMap { $0 } }
        set {}
    }
```

and conform:

```swift
extension GlimmerTableView: UIAccessibilityContainerDataTable {
    func accessibilityRowCount() -> Int { cellElements.count }
    func accessibilityColumnCount() -> Int { cellElements.first?.count ?? 0 }

    func accessibilityDataTableCellElement(forRow row: Int, column: Int) -> UIAccessibilityContainerDataTableCell? {
        guard row < cellElements.count, column < cellElements[row].count else { return nil }
        return cellElements[row][column]
    }

    func accessibilityHeaderElements(forColumn column: Int) -> [UIAccessibilityContainerDataTableCell]? {
        guard let header = cellElements.first, column < header.count else { return nil }
        return [header[column]]
    }

    func accessibilityHeaderElements(forRow row: Int) -> [UIAccessibilityContainerDataTableCell]? { nil }
}
```

In `GlimmerInlineToken`, add `public var accessibilityLabel: String?` with an init parameter `accessibilityLabel: String? = nil`, documented as: "What VoiceOver reads for the chip, e.g. "Mention, Ada". Defaults to `displayText`." In `GlimmerInlineAttachment.chipView()`, before caching. The token's label wins; otherwise a view the extension labeled keeps its label, and a plain label reads the display text:

```swift
        if let label = token.accessibilityLabel {
            view.accessibilityLabel = label
        } else if view is UILabel || view.accessibilityLabel == nil {
            view.accessibilityLabel = token.displayText
        }
        view.isAccessibilityElement = true
```

Also set the attachment's own `accessibilityLabel` (NSObject's) to the same text in `init`, for whatever UIKit reads when VoiceOver meets the attachment character.

- [ ] **Step 5: Probe what VoiceOver can reach inside the text view**

Embeds and chips are subviews of the text view. Whether UIKit's accessibility for a non-editable `UITextView` exposes its subviews is not documented. Probe it with a temporary test (not committed): host a settled `GlimmerView` showing a code block and a table, and walk the accessibility tree from the view. At each node read `accessibilityElements` or `accessibilityElementCount()`/`accessibilityElement(at:)`, and descend into subviews only for non-elements. Print each element's type and label. Record the result in the ledger. If the code block and table are reachable, keep the probe's assertion as a committed test (`testEmbedsAreReachableFromTheAnswer`). If they are not, rule on it and defer to Plan 5: fixing it means taking over the text view's accessibility, which needs VoiceOver on a device to judge.

- [ ] **Step 6: Run to verify they pass**

Run the test command for `GlimmerAccessibilityTests`, `GlimmerViewStreamingTests`, `GlimmerTableViewTests`, `GlimmerCodeBlockViewTests` and `GlimmerExtensionTests`. Expected: PASS.

- [ ] **Step 7: Run the engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: VoiceOver for revealing answers, code blocks, tables and chips

While a reveal runs the view is one element reading the revealed text; at
settle the text view takes over. Code blocks read \"Code, <language>\" with a
Copy button, tables are data tables with column headers, and chips read the
label their extension gives."
```

---

### Task 5: Compose and visual loose ends

**Files:**
- Modify: `Sources/Glimmer/Engine/Parse/GlimmerParser.swift` (`language(_:)`)
- Modify: `Sources/Glimmer/Engine/Theme/GlimmerTheme.swift` (`headingFont(level:)`)
- Modify: `Sources/Glimmer/Engine/Compose/GlimmerComposer.swift` (`listMarker` bullet color)
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerTableView.swift` (grid without implicit animations; `update(to:)` equality; `grid` internal)
- Test: `GlimmerParserTests.swift`, `GlimmerThemeTests.swift`, `GlimmerComposerTests.swift`, `GlimmerExtensionTests.swift`, `GlimmerTableViewTests.swift`

These are the review minors still open from Plans 1 and 3 that affect what people see. Plan 1 deferred:
- the info string split on spaces only
- the empty-headings crash
- the bullet vs. number color
- the grid's implicit animations
- two test gaps: the key namespacing test was fixed in Task 1, and the chip-after-emoji case is below.

Plan 3 deferred the table's update equality. The code view's dead `languageLabel` line already went away in Plan 3's fix pass.

- [ ] **Step 1: Write the failing tests**

`GlimmerParserTests.swift`:

```swift
    func testFenceLanguageStopsAtAnyWhitespace() {
        guard case .codeBlock(let language, _) = GlimmerParser.parse("```swift\tlinenos\nlet x = 1\n```").first else {
            return XCTFail("expected a code block")
        }
        XCTAssertEqual(language, "swift")
    }
```

`GlimmerThemeTests.swift`:

```swift
    func testHeadingFontFallsBackToBodyWithoutHeadingFonts() {
        var theme = GlimmerTheme.default
        theme.headingFonts = []
        XCTAssertEqual(theme.headingFont(level: 2), theme.bodyFont)
    }
```

`GlimmerComposerTests.swift`:

```swift
    func testBulletsAndNumbersShareTheTextColor() {
        XCTAssertEqual(attributes(of: "•", in: compose("- a"))[.foregroundColor] as? UIColor, theme.textColor)
        XCTAssertEqual(attributes(of: "1.", in: compose("1. a"))[.foregroundColor] as? UIColor, theme.textColor)
        XCTAssertEqual(attributes(of: "•", in: compose("> - a"))[.foregroundColor] as? UIColor, theme.secondaryTextColor)
    }
```

`GlimmerExtensionTests.swift` (uses its `CitationExtension`):

```swift
    func testChipAfterEmojiKeepsItsRange() {
        let text = compose("👋🏽 [3] after", extensions: [CitationExtension()])
        let chip = (text.string as NSString).range(of: "\u{FFFC}").location
        XCTAssertEqual(text.string, "👋🏽 \u{FFFC} after")
        XCTAssertTrue(text.attribute(.attachment, at: chip, effectiveRange: nil) is GlimmerInlineAttachment)
        XCTAssertEqual(text.attribute(.glimmerSource, at: chip, effectiveRange: nil) as? String, "[3]")
        XCTAssertNil(text.attribute(.attachment, at: chip + 2, effectiveRange: nil))
    }
```

`GlimmerTableViewTests.swift`:

```swift
    func testGridChangesDoNotAnimate() {
        let cell = { (text: String) in NSAttributedString(string: text) }
        let table = GlimmerTableView(header: [cell("a"), cell("b")], rows: [[cell("1"), cell("2")]], alignments: [.none, .none], theme: .default)
        let window = hostInWindow(table, width: 300, height: 200)
        table.frame.size.width = 200
        table.layoutIfNeeded()
        XCTAssertNil(table.grid.animationKeys(), "the grid redraws in place")
        _ = window
    }

    func testUpdateKeepsLabelsForARaggedTableThatDidNotChange() {
        let cell = { (text: String) in NSAttributedString(string: text) }
        let header = [cell("a"), cell("b")]
        let rows = [[cell("1")]]
        let table = GlimmerTableView(header: header, rows: rows, alignments: [.none, .none], theme: .default)
        let label = table.cellLabels[1][0]
        table.update(to: .table(header: header, rows: rows, alignments: [.none, .none]))
        XCTAssertTrue(table.cellLabels[1][0] === label, "an unchanged ragged row keeps its labels")
        let bold = NSAttributedString(string: "1", attributes: [.font: UIFont.boldSystemFont(ofSize: 17)])
        table.update(to: .table(header: header, rows: [[bold]], alignments: [.none, .none]))
        XCTAssertEqual(table.cellLabels[1][0].attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont,
                       UIFont.boldSystemFont(ofSize: 17), "a restyled cell updates")
    }
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for the five classes. Expected: `grid` doesn't compile while private. With `grid` internal, each new test FAILS (the language is `"swift\tlinenos"`, the empty headings trap, the bullet is the secondary color, the grid has animation keys, the ragged row's label is replaced). The exception is `testChipAfterEmojiKeepsItsRange`, which fills a coverage gap Plan 1's review found and is expected to pass already. If it fails, that is a bug: fix it in Step 3.

For the heading test, the current code traps (index out of range). A trap is a failure, but it ends the run: apply the Step 3 guard first if the run stops there, and note it in the ledger.

- [ ] **Step 3: Fix each**

- Parser: `guard let word = info.split(whereSeparator: \.isWhitespace).first, !word.isEmpty else { return nil }`.
- Theme:

  ```swift
      public func headingFont(level: Int) -> UIFont {
          guard !headingFonts.isEmpty else { return bodyFont }
          return headingFonts[min(max(level, 1), headingFonts.count) - 1]
      }
  ```

- Composer `listMarker`: bullets use `color` (the same text-or-secondary-in-quotes color as numbers) instead of `theme.secondaryTextColor`. Why: a browser's default `::marker` inherits the text color, and one rule for both marker kinds is what the review asked for.
- Table: make `grid` `let grid = CAShapeLayer()` (internal). In `layoutSubviews`, wrap the frame and path updates in:

  ```swift
          CATransaction.begin()
          CATransaction.setDisableActions(true)
          defer { CATransaction.commit() }
  ```

  In `update(to:)`, compare padded attributed cells:

  ```swift
          let columns = max(header.count, rows.map(\.count).max() ?? 0, alignments.count)
          func padded(_ row: [NSAttributedString]) -> [NSAttributedString] {
              row + Array(repeating: NSAttributedString(), count: max(0, columns - row.count))
          }
          let incoming = [padded(header)] + rows.map(padded)
          let unchanged = alignments == self.alignments && incoming.count == cells.count
              && zip(incoming, cells).allSatisfy { new, old in new.count == old.count && zip(new, old).allSatisfy { $0.isEqual(to: $1) } }
          guard !unchanged else { return }
  ```

- [ ] **Step 4: Run to verify they pass**

Run the test command for the five classes. Expected: PASS.

- [ ] **Step 5: Run the engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: close compose and visual loose ends from earlier reviews

A fence's language stops at any whitespace, a theme without heading fonts
falls back to the body font, bullets share the numbers' color, a table's
grid no longer animates when it redraws, and an unchanged table keeps its
labels while a restyled cell updates."
```

---

### Task 6: Band and harness loose ends

**Files:**
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (`frame` and `center` refresh the band)
- Modify: `Tests/GlimmerTests/Engine/GlimmerVisibleBandTests.swift`
- Modify: `Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift` (one retry per gated measurement)

**Interfaces:** none new.

- [ ] **Step 1: Write the failing test**

In `GlimmerVisibleBandTests`, add a copy of `testLayoutPassRefreshesTheBandAfterTheHostMovesTheView` named `testMovingTheViewRefreshesTheBandWithoutALayoutPass`. It drops the `view.setNeedsLayout()` line and replaces `settle(container)` after the move with a single `RunLoop.main.run(until: Date().addingTimeInterval(0.05))`.

- [ ] **Step 2: Run to verify it fails**

Run the test command for `GlimmerVisibleBandTests`. Expected: the new test FAILS. UIKit doesn't lay out a view whose frame origin moved without a size change, so the band stays where it was.

- [ ] **Step 3: Frame and center refresh the band**

In `GlimmerView`:

```swift
    /// A host that moves the view without resizing it (content above grew) gets no layout pass; refresh the band here.
    public override var frame: CGRect {
        didSet { if frame.origin != oldValue.origin { textView.refreshVisibleBandIfNeeded() } }
    }

    public override var center: CGPoint {
        didSet { if center != oldValue { textView.refreshVisibleBandIfNeeded() } }
    }
```

- [ ] **Step 4: One retry per gated measurement**

In `GlimmerStreamingPerformanceTests`, add:

```swift
    /// Load on a shared machine (another simulator, a compile) can push one run's p95 over a gate; a real regression
    /// fails both runs. So each gated measurement gets one retry.
    private func measured<T>(passes: (T) -> Bool, _ measure: () async -> T) async -> T {
        let first = await measure()
        return passes(first) ? first : await measure()
    }
```

Wrap every `streamTail` call with it, passing the same conditions its assertions check. For example:

```swift
        let p95 = await measured(passes: { $0.update < budget && $0.layout < mainThreadBudget }) {
            await streamTail(of: longMixedAnswer, reveal: .none)
        }
```

Give the configure test the same treatment with a synchronous copy of the helper. This changes test infrastructure, not behavior, so there is no RED step. The evidence is Step 5's green runs.

- [ ] **Step 5: Run to verify, engine suite, commit**

Run the test command for `GlimmerVisibleBandTests` and `GlimmerStreamingPerformanceTests`. Expected: PASS. Then run every engine test class. Expected: all pass.

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: refresh the band when the host moves the view; retry perf gates once

Moving the view without resizing it gets no layout pass, so frame and center
changes refresh the rendered band. Each gated performance measurement gets
one retry, so load from another process does not fail the suite."
```

---

## Out of scope for this plan

- Plan 5 covers the rest:
  - moving syntax highlighting to the worker (spec §4.2)
  - appending table rows incrementally
  - deleting 1.x (§10)
  - rebuilding the demo (benchmark screen, `CADisableMinimumFrameDurationOnPhone`, and pause/resume and light/dark in the lab)
  - the on-device `XCTHitchMetric` harness and the §3 device numbers
  - the README
  - the `2.0.0` tag
- Still deferred, with reasons:
  - `height(forWidth:)` resizing the text view inside a size query: needs a separate measurement path; Plan 5, if the device harness shows a cost.
  - A fading unit falling back to the whole box when its embed's view was never created: off screen, and it corrects itself.
  - The viewport tracker not noticing a scroll view inserted above an already-placed view: UIKit gives no hook, and it is rare.
- VoiceOver on a device (rotor, reading order across chips) needs a person with VoiceOver on. These unit tests pin the properties VoiceOver reads; they do not replace listening to it.
