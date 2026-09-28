# Glimmer 2.0 — Plan 2: Streaming and Reveal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stream markdown into `GlimmerView` with Gemini's reveal. Each update touches only the open tail: tail re-parse, per-block re-compose, and one TextKit 2 editing transaction. Text appears phrase by phrase, each phrase fading 0→1 over 600 ms in a Core Animation mask. The height grows one revealed line at a time, the reveal resumes across re-created views, and the final result is identical to a settled render.

**Architecture:** `GlimmerStreamingDocument` owns the composed text. It tail-heals the markdown, re-parses from the last top-level block's start line, and returns a `GlimmerDocumentEdit`, which `GlimmerTextView.apply(_:)` applies. `GlimmerRevealEngine` is a pure state machine over UTF-16 offsets and seconds: `GlimmerPacing` sets the rate, `GlimmerPhraseChunker` picks the phrases, and it tracks fade/settle times. `GlimmerRevealMask` turns the engine's state into a `CALayer` mask. `GlimmerView` wires these together with a `GlimmerRevealClock` that wakes only when a phrase starts or settles.

**Tech Stack:** Swift 6, iOS 18+, UIKit, TextKit 2 (`NSTextContentStorage.performEditingTransaction`, `NSTextLayoutManager.enumerateTextSegments`), Core Animation (`CABasicAnimation` on a mask sublayer), vendored cmark-gfm, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-25-glimmer-2-engine-design.md` (§4.1 streaming document and tail healing, §4.2 `DocumentEdit`, §4.3 editing transactions, §5 reveal, §11 parity and stability tests)

**Builds on:** Plan 1 (`docs/superpowers/plans/2026-09-25-glimmer-2-plan-1-foundation.md`), which is complete on `glimmer-2`. Read its ledger rulings in `.superpowers/sdd/2026-09-25-glimmer-2-plan-1-foundation/progress.md`, especially the TextKit 2 isolation pattern and `CGFloat.greatestFiniteMagnitude` in tests.

**Evidence behind the design (measured 2026-09-26, Debug build, iOS 27 simulator):**

| Operation | 1k words | 5k words | 20k words |
|---|---|---|---|
| Full cmark parse | 0.51 ms | 2.21 ms | 7.68 ms |
| Compose the whole document | 1.9 ms | 7.7 ms | 30 ms |
| Compose the last block | 0.13 ms | 0.03 ms | 0.04 ms |

Appending in a TextKit 2 editing transaction kept the first paragraph's layout-fragment object (it was reused) and re-laid out only the edited one: 0.94 ms including `ensureLayout`. Both a full re-parse and a full re-compose on every update would exceed the spec's 2 ms p95 budget on long answers, so this plan does neither.

**Constraint found in Plan 1's review fix (2026-09-26):** TextKit 2 inside a `UITextView` lays out only the lines its viewport covers, even after `ensureLayout(for: documentRange)`. So `GlimmerView` keeps the text view's frame at the full document height (`fitTextViewToContent`) and clips itself to the revealed height, rather than sizing the text view to the revealed height. Measuring through `UITextView.sizeThatFits` on every update is a cost that Task 11's recording and Plan 3's harness must check against the §3 budget.

**Ruling carried in this plan (spec §5.2 conflict):** with phrases capped at 8 words and starts at least 60 ms apart, peak throughput is about 750 characters a second. A 3,000-character burst would then need about 4 s to drain, not the spec's "about 1.5 s". The resolution is that a phrase grows until it carries at least `rate × minPhraseSpacing` characters, so fast streams reveal in larger phrases (as Gemini's does) while starts stay at least 60 ms apart.

## Global Constraints

- The branch is `glimmer-2`. Commit after every task. **Do not add `Co-Authored-By` trailers.**
- Swift 6 language mode, iOS 18 minimum, no package dependencies. New code goes under `Sources/Glimmer/Engine/`. Do not touch 1.x sources.
- **TextKit 2 only.** Never read `layoutManager`.
- **No per-frame main-thread work in the reveal.** Never use a `CADisplayLink`. Core Animation runs every fade. The main thread works only when text arrives, a phrase starts, a phrase settles, or the layout changes.
- `NSTextAttachmentViewProvider` overrides stay on the Plan 1 pattern: a `nonisolated(unsafe) let` local plus `MainActor.assumeIsolated`.
- No force unwrapping (`!`) and no force casts in library code. Tests may force-unwrap literal URLs.
- In tests, write `CGFloat.greatestFiniteMagnitude`, never `.greatestFiniteMagnitude`, in `CGSize(width: <literal>, …)`.
- Test command, with a passing run ending in `** TEST SUCCEEDED **`:
  ```bash
  DEST='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0'
  xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/<TestClass> 2>&1 | tail -5
  ```
  xcodebuild sometimes hangs after printing its results. If the log shows `Executed N tests` and the process has not exited, kill it.
- The whole 1.x suite is already red on `main` (see Plan 1's ledger). Completion is gated on the engine test classes only.

## Review Focus

These are the five inputs the spec implies but the main tests don't exercise, ordered from most likely to bite a real user down. Each has a test in the task that owns the code.

1. **A regenerated or replaced stream** (the new markdown is not an extension of the old) → full re-parse, the revealed length is clamped to the new text, and the reveal continues without a crash. Test: Task 9 `testReplacedStreamKeepsRevealing`.
2. **A huge burst** (a whole long answer in one update, then the stream ends) → the reveal drains within the drain duration plus one fade, and phrase starts stay at least `minPhraseSpacing` apart. Test: Task 7 `testHugeBurstDrainsWithinDrainDuration`.
3. **A stream that ends mid-syntax** (`**bol`, then `isStreaming: false`) → the final render uses the raw, unhealed markdown, exactly like a settled render. Test: Task 3 `testEndingStreamUsesRawMarkdown`.
4. **A width change mid-reveal** → phrase geometry is rebuilt and each fade continues from its current opacity instead of restarting. Test: Task 8 `testWidthChangeRebuildsPhraseGeometry`.
5. **Empty or whitespace keep-alive updates while streaming** → no phrases, zero height, and no crash. Test: Task 9 `testEmptyStreamingUpdateStaysEmpty`.

---

## File Structure

```
Sources/Glimmer/Engine/
  Parse/GlimmerParser.swift              (modify) parseWithLines: blocks + 1-based start lines
  Compose/GlimmerComposer.swift          (modify) composeBlock(_:isFirst:); compose = blocks joined
  Stream/GlimmerTailHealer.swift         closes/holds back half-typed syntax at the tail
  Stream/GlimmerStreamingDocument.swift  tail re-parse, block diff, GlimmerDocumentEdit
  Render/GlimmerTextView.swift           (modify) apply(_ edit:), segmentRects, lineRect, textRange
  Reveal/GlimmerRevealOptions.swift      public options + GlimmerReveal (.none / .smooth)
  Reveal/GlimmerPhraseChunker.swift      phrase boundaries over UTF-16 text
  Reveal/GlimmerPacing.swift             backlog-following reveal rate
  Reveal/GlimmerRevealEngine.swift       pure reveal state machine
  Reveal/GlimmerRevealMask.swift         CALayer mask rendering
  Reveal/GlimmerRevealClock.swift        clock protocol + Task-based system clock
  Reveal/GlimmerRevealStore.swift        per-message revealed length, LRU-bounded
  GlimmerConfiguration.swift             (modify) reveal option
  GlimmerView.swift                      (modify) streaming update, reveal wiring, revealed height
  GlimmerText.swift                      (modify) isStreaming / revealID
Tests/GlimmerTests/Engine/
  EngineTestSupport.swift                (modify) assertEquivalent, ManualRevealClock
  GlimmerComposerBlockTests.swift
  GlimmerTailHealerTests.swift
  GlimmerStreamingDocumentTests.swift
  GlimmerTextViewEditTests.swift
  GlimmerPhraseChunkerTests.swift
  GlimmerPacingTests.swift
  GlimmerRevealEngineTests.swift
  GlimmerRevealMaskTests.swift
  GlimmerViewStreamingTests.swift
  StreamingFixtures.swift
  GlimmerStreamParityTests.swift
Examples/GlimmerDemo/StreamingLabDemo.swift  (+ pbxproj, ContentView, GlimmerDemoApp)
```

---

### Task 1: Start lines from the parser and per-block composition

**Files:**
- Modify: `Sources/Glimmer/Engine/Parse/GlimmerParser.swift`
- Modify: `Sources/Glimmer/Engine/Compose/GlimmerComposer.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerComposerBlockTests.swift`

**Interfaces:**
- Consumes: Plan 1's `GlimmerParser` and `GlimmerComposer`.
- Produces:
  - `static func GlimmerParser.parseWithLines(_ markdown: String) -> [(block: GlimmerBlock, startLine: Int)]` (1-based lines). `parse(_:)` becomes `parseWithLines(_:).map(\.block)`.
  - `func GlimmerComposer.composeBlock(_ block: GlimmerBlock, isFirst: Bool) -> NSAttributedString`, which always ends in `"\n"` unless it is empty.
  - `compose(_:)` is now exactly `composeBlock` over each block, joined, with the final `"\n"` removed.
  - Headings get `blockSpacing` above them unless they open the document. `Context.isDocumentStart` carries that into nested blocks.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerComposerBlockTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerComposerBlockTests: XCTestCase {
    private let theme = GlimmerTheme.default

    func testParseWithLinesReportsStartLines() {
        let parsed = GlimmerParser.parseWithLines("# A\n\npara\n\n- x\n- y\n\n```\ncode\n```")
        XCTAssertEqual(parsed.map(\.startLine), [1, 3, 5, 8])
        XCTAssertEqual(parsed.map(\.block), GlimmerParser.parse("# A\n\npara\n\n- x\n- y\n\n```\ncode\n```"))
    }

    func testComposeIsBlocksJoinedWithoutTheFinalNewline() {
        let markdown = "# Title\n\nSome **bold** text.\n\n- one\n- two\n\n> quoted\n\n```swift\nlet x = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |"
        let blocks = GlimmerParser.parse(markdown)
        let composer = GlimmerComposer(theme: theme)
        let joined = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            let fragment = composer.composeBlock(block, isFirst: index == 0)
            XCTAssertTrue(fragment.string.hasSuffix("\n"), "block \(index) must end in a newline")
            joined.append(fragment)
        }
        joined.deleteCharacters(in: NSRange(location: joined.length - 1, length: 1))
        assertEquivalent(composer.compose(blocks), joined, "compose vs joined blocks")
    }

    func testHeadingOpeningTheDocumentHasNoSpaceAbove() {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse("# Title"))
        let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.paragraphSpacingBefore, 0)
    }

    func testNestedHeadingLaterInTheDocumentGetsBlockSpace() {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse("para\n\n> # Quoted heading"))
        let location = (text.string as NSString).range(of: "Quoted").location
        let style = text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.paragraphSpacingBefore, theme.blockSpacing)
    }
}
```

Append to `Tests/GlimmerTests/Engine/EngineTestSupport.swift`:
```swift
/// Compares two attributed strings run by run. Attachments compare by type, because every composition creates new
/// attachment objects; every other attribute value must be `isEqual`.
func assertEquivalent(
    _ lhs: NSAttributedString, _ rhs: NSAttributedString, _ message: String,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(lhs.string, rhs.string, message, file: file, line: line)
    guard lhs.string == rhs.string else { return }
    var index = 0
    while index < lhs.length {
        var lhsRange = NSRange()
        var rhsRange = NSRange()
        let left = lhs.attributes(at: index, effectiveRange: &lhsRange)
        let right = rhs.attributes(at: index, effectiveRange: &rhsRange)
        XCTAssertEqual(Set(left.keys.map(\.rawValue)), Set(right.keys.map(\.rawValue)), "\(message): keys at \(index)", file: file, line: line)
        for (key, leftValue) in left {
            guard let rightValue = right[key] else { continue }
            if let leftAttachment = leftValue as? NSTextAttachment, let rightAttachment = rightValue as? NSTextAttachment {
                XCTAssertTrue(type(of: leftAttachment) == type(of: rightAttachment), "\(message): attachment at \(index)", file: file, line: line)
            } else {
                XCTAssertTrue((leftValue as AnyObject).isEqual(rightValue), "\(message): \(key.rawValue) at \(index)", file: file, line: line)
            }
        }
        index = min(NSMaxRange(lhsRange), NSMaxRange(rhsRange))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerComposerBlockTests 2>&1 | tail -5`
Expected: a build failure, `type 'GlimmerParser' has no member 'parseWithLines'`.

- [ ] **Step 3: Give the parser start lines**

In `Sources/Glimmer/Engine/Parse/GlimmerParser.swift`, replace the whole `public static func parse(_ markdown: String) -> [GlimmerBlock] { … }` function with:
```swift
    public static func parse(_ markdown: String) -> [GlimmerBlock] {
        parseWithLines(markdown).map(\.block)
    }

    /// Top-level blocks with the 1-based source line each starts on. `GlimmerStreamingDocument` uses the last
    /// block's line to re-parse only the open tail.
    static func parseWithLines(_ markdown: String) -> [(block: GlimmerBlock, startLine: Int)] {
        _ = registration
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else { return [] }
        defer { cmark_parser_free(parser) }
        for name in extensionNames {
            if let syntaxExtension = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntaxExtension)
            }
        }
        var source = markdown
        source.withUTF8 { bytes in
            guard let base = bytes.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: bytes.count) { characters in
                cmark_parser_feed(parser, characters, bytes.count)
            }
        }
        guard let document = cmark_parser_finish(parser) else { return [] }
        defer { cmark_node_free(document) }
        return children(of: document).compactMap { node in
            block(node).map { (block: $0, startLine: Int(cmark_node_get_start_line(node))) }
        }
    }
```

- [ ] **Step 4: Compose block by block**

In `Sources/Glimmer/Engine/Compose/GlimmerComposer.swift`:
- Add to `struct Context`, after `var paragraphSpacing: CGFloat?`:
  ```swift
          /// True while composing the document's first top-level block (no heading space above it).
          var isDocumentStart = false
  ```
- Replace `func compose(_ blocks: [GlimmerBlock]) -> NSAttributedString { … }` with:
  ```swift
      func compose(_ blocks: [GlimmerBlock]) -> NSAttributedString {
          let output = NSMutableAttributedString()
          for (index, block) in blocks.enumerated() { output.append(composeBlock(block, isFirst: index == 0)) }
          if output.length > 0 { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
          return output
      }

      /// One top-level block, ending in "\n". `compose(_:)` is exactly these joined with the final "\n" removed, which
      /// is what lets `GlimmerStreamingDocument` re-compose only the blocks that changed.
      func composeBlock(_ block: GlimmerBlock, isFirst: Bool) -> NSAttributedString {
          let output = NSMutableAttributedString()
          var context = Context()
          context.isDocumentStart = isFirst
          append(block, context: context, marker: nil, to: output)
          return output
      }
  ```
- In `append(_:context:marker:to:)`, in the `.heading` case, change `spacingBefore: output.length > 0 ? theme.blockSpacing : 0` to:
  ```swift
  spacingBefore: output.length > 0 || !context.isDocumentStart ? theme.blockSpacing : 0
  ```

- [ ] **Step 5: Run the new tests and the Plan 1 composer tests**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerComposerBlockTests -only-testing:GlimmerTests/GlimmerComposerTests -only-testing:GlimmerTests/GlimmerParserTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Glimmer/Engine/Parse/GlimmerParser.swift Sources/Glimmer/Engine/Compose/GlimmerComposer.swift Tests/GlimmerTests/Engine/GlimmerComposerBlockTests.swift Tests/GlimmerTests/Engine/EngineTestSupport.swift
git commit -m "Engine: report block start lines and compose block by block"
```

---

### Task 2: Tail healer

**Files:**
- Create: `Sources/Glimmer/Engine/Stream/GlimmerTailHealer.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerTailHealerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum GlimmerTailHealer`, with `static func heal(_ markdown: String) -> String` and `static func openFence(in markdown: String) -> String?`.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerTailHealerTests.swift`:
```swift
import XCTest
@testable import Glimmer

final class GlimmerTailHealerTests: XCTestCase {
    private let cases: [(input: String, healed: String)] = [
        ("Hello **wor", "Hello **wor**"),
        ("Hello **wor ", "Hello **wor** "),
        ("Hello **", "Hello "),
        ("**b *", "**b** "),
        ("a *b **c", "a *b **c***"),
        ("use `co", "use `co`"),
        ("**a `b", "**a `b`**"),
        ("~~old", "~~old~~"),
        ("* item **b", "* item **b**"),
        ("```swift\nlet x", "```swift\nlet x\n```"),
        ("~~~\ncode\n", "~~~\ncode\n~~~"),
        ("see [docs](https://ex", "see [docs](https://ex)"),
        ("see [do", "see do"),
        ("[a](b) c [d", "[a](b) c d"),
        ("see ![alt](http", "see "),
        ("see ![al", "see "),
        ("see [3]", "see "),
        ("para\n\n| a | b |", "para\n\n"),
        ("| a | b |\n|---|---|\n| 1 |", "| a | b |\n|---|---|\n| 1 |"),
        ("text\n\n**Bold", "text\n\n**Bold**"),
        ("**x\n\ny", "**x\n\ny"),
        ("done.", "done."),
        ("`a` and **b**", "`a` and **b**"),
        ("", ""),
    ]

    func testHealsEveryCase() {
        for (input, healed) in cases {
            XCTAssertEqual(GlimmerTailHealer.heal(input), healed, "healing \(input.debugDescription)")
        }
    }

    func testOpenFenceDetection() {
        XCTAssertEqual(GlimmerTailHealer.openFence(in: "````js\nx"), "````")
        XCTAssertNil(GlimmerTailHealer.openFence(in: "```\nx\n```"))
        XCTAssertNil(GlimmerTailHealer.openFence(in: "inline ``` not a fence"))
    }

    func testHealedMarkdownRendersWithoutRawMarkers() {
        let text = GlimmerComposerTestHelper.plainText(GlimmerTailHealer.heal("Some **bold and `code"))
        XCTAssertFalse(text.contains("*"))
        XCTAssertFalse(text.contains("`"))
    }
}

/// Plain rendered text of markdown, for assertions that care only about visible characters.
enum GlimmerComposerTestHelper {
    static func plainText(_ markdown: String) -> String {
        GlimmerParser.parse(markdown).map { block -> String in
            if case .paragraph(let inlines) = block { return GlimmerInline.plainText(inlines) }
            return ""
        }.joined(separator: "\n")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerTailHealerTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerTailHealer' in scope`.

- [ ] **Step 3: Implement**

`Sources/Glimmer/Engine/Stream/GlimmerTailHealer.swift`:
```swift
import Foundation

/// Closes markdown that is still being typed at the end of a streaming buffer, so half-finished syntax renders in its
/// final style instead of as raw markers that restyle a moment later. Only an open code fence or the last paragraph is
/// touched; everything before it is returned unchanged. Apply it only while streaming.
enum GlimmerTailHealer {
    static func heal(_ markdown: String) -> String {
        if let fence = openFence(in: markdown) {
            return markdown + (markdown.hasSuffix("\n") ? "" : "\n") + fence
        }
        let tailStart = markdown.range(of: "\n\n", options: .backwards)?.upperBound ?? markdown.startIndex
        var tail = String(markdown[tailStart...])
        tail = holdBackTableHeader(tail)
        tail = healLinks(tail)
        tail = closeInlineDelimiters(tail)
        return String(markdown[..<tailStart]) + tail
    }

    // MARK: - Code fences

    /// The fence that would close a fence still open at the end of `markdown`, or nil.
    static func openFence(in markdown: String) -> String? {
        var open: (marker: Character, count: Int)?
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let content = line.drop { $0 == " " }
            guard line.count - content.count <= 3, let first = content.first, first == "`" || first == "~" else { continue }
            let run = content.prefix { $0 == first }.count
            guard run >= 3 else { continue }
            let rest = content.dropFirst(run)
            if let current = open {
                if first == current.marker, run >= current.count, rest.allSatisfy({ $0 == " " }) { open = nil }
            } else if first == "~" || !rest.contains("`") {
                open = (first, run)
            }
        }
        return open.map { String(repeating: $0.marker, count: $0.count) }
    }

    // MARK: - Tables

    /// A lone `| a | b |` line is a table header waiting for its delimiter row; shown early it renders raw pipes.
    private static func holdBackTableHeader(_ tail: String) -> String {
        var lines = tail.components(separatedBy: "\n")
        let pipeLines = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("|") }
        guard pipeLines.count == 1, let index = pipeLines.first,
              lines[(index + 1)...].allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return tail }
        lines.removeSubrange(index...)
        return lines.joined(separator: "\n") + (index > 0 ? "\n" : "")
    }

    // MARK: - Links and images

    private static func healLinks(_ tail: String) -> String {
        // `![alt` or `![alt](partial` — hold the whole image back until it is complete.
        if let match = tail.firstMatch(of: #/!\[[^\]]*(\]\([^)\s]*)?$/#) {
            return String(tail[..<match.range.lowerBound])
        }
        // `[text](partial` — close the destination so the text already renders as a link.
        if tail.firstMatch(of: #/\[[^\]]*\]\([^)\s]*$/#) != nil {
            return tail + ")"
        }
        // `[text]` — may still become a link (or an extension token); hold it back for a moment.
        if let match = tail.firstMatch(of: #/\[[^\]]*\]$/#) {
            return String(tail[..<match.range.lowerBound])
        }
        // `[partial` — drop the bracket and keep the text.
        if let match = tail.firstMatch(of: #/\[[^\]]*$/#) {
            var healed = tail
            healed.remove(at: match.range.lowerBound)
            return healed
        }
        return tail
    }

    // MARK: - Emphasis, strikethrough, code spans

    /// Closes `**`, `*`, `~~` and `` ` `` left open, innermost first, before any trailing whitespace (a closer after a
    /// space would not be right-flanking). A dangling opener with nothing after it is dropped instead.
    private static func closeInlineDelimiters(_ tail: String) -> String {
        var body = tail
        var trailing = ""
        func moveTrailingWhitespace() {
            while let last = body.last, last.isWhitespace {
                trailing.insert(last, at: trailing.startIndex)
                body.removeLast()
            }
        }
        moveTrailingWhitespace()
        var open = openDelimiters(in: body)
        while let last = open.last, body.hasSuffix(last) {
            body.removeLast(last.count)
            open.removeLast()
            moveTrailingWhitespace()
        }
        return body + open.reversed().joined() + trailing
    }

    private static func openDelimiters(in text: String) -> [String] {
        var open: [String] = []
        let characters = Array(text)
        var index = 0
        var atLineStart = true
        func toggle(_ marker: String) {
            if let existing = open.lastIndex(of: marker) { open.remove(at: existing) } else { open.append(marker) }
        }
        func next(_ offset: Int) -> Character? {
            index + offset < characters.count ? characters[index + offset] : nil
        }
        while index < characters.count {
            let character = characters[index]
            if open.last == "`" {
                if character == "`" { open.removeLast() }
                index += 1
                atLineStart = false
                continue
            }
            switch character {
            case "\n":
                atLineStart = true
                index += 1
                continue
            case " ", "\t":
                index += 1
                continue
            case "`":
                open.append("`")
            case "*" where next(1) == "*":
                toggle("**")
                index += 2
                atLineStart = false
                continue
            case "*" where atLineStart && next(1) == " ":
                break // a list bullet, not emphasis
            case "*":
                toggle("*")
            case "~" where next(1) == "~":
                toggle("~~")
                index += 2
                atLineStart = false
                continue
            default:
                break
            }
            atLineStart = false
            index += 1
        }
        return open
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerTailHealerTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`. If a case fails, fix the healer rather than the expectation, unless the expected string would render worse. Rule and ledger that.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Stream/GlimmerTailHealer.swift Tests/GlimmerTests/Engine/GlimmerTailHealerTests.swift
git commit -m "Engine: heal half-typed markdown at the end of a stream"
```

---

### Task 3: Streaming document

**Files:**
- Create: `Sources/Glimmer/Engine/Stream/GlimmerStreamingDocument.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerStreamingDocumentTests.swift`

**Interfaces:**
- Consumes: `GlimmerParser.parseWithLines` and `GlimmerComposer.composeBlock` (Task 1), `GlimmerTailHealer.heal` (Task 2) and `assertEquivalent` (Task 1).
- Produces:
  - `struct GlimmerDocumentEdit`, with `range: NSRange` (in the previous text) and `replacement: NSAttributedString`.
  - `@MainActor final class GlimmerStreamingDocument`, created with `init(composer: GlimmerComposer)`. It exposes `private(set) var text: NSMutableAttributedString`, `private(set) var blocks: [GlimmerBlock]` and `private(set) var blockOffsets: [Int]` (the UTF-16 start of each block in `text`), and provides `func update(markdown: String, isStreaming: Bool) -> GlimmerDocumentEdit?`.
  - Behaviour: `markdown` must already be preprocessed by extensions. The tail is healed only while `isStreaming`. `text` always equals `composer.compose(GlimmerParser.parse(isStreaming ? heal(markdown) : markdown))`.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerStreamingDocumentTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerStreamingDocumentTests: XCTestCase {
    private let composer = GlimmerComposer(theme: .default)

    private func freshCompose(_ markdown: String, isStreaming: Bool) -> NSAttributedString {
        composer.compose(GlimmerParser.parse(isStreaming ? GlimmerTailHealer.heal(markdown) : markdown))
    }

    func testFirstUpdateInsertsEverything() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        let edit = try XCTUnwrap(document.update(markdown: "Hello **wor", isStreaming: true))
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 0))
        XCTAssertEqual(document.text.string, "Hello wor")
        let font = document.text.attribute(.font, at: 6, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false, "the healed tail is already bold")
    }

    func testAppendingToTheLastParagraphReplacesOnlyIt() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Para one.\n\nPara tw", isStreaming: true)
        let edit = try XCTUnwrap(document.update(markdown: "Para one.\n\nPara two.", isStreaming: true))
        XCTAssertEqual(edit.range.location, ("Para one.\n" as NSString).length)
        XCTAssertEqual(document.text.string, "Para one.\nPara two.")
    }

    func testNewBlockReinsertsTheSeparator() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "One", isStreaming: true)
        let edit = try XCTUnwrap(document.update(markdown: "One\n\nTwo", isStreaming: true))
        XCTAssertEqual(edit.range, NSRange(location: 3, length: 0))
        XCTAssertEqual(edit.replacement.string, "\nTwo")
        XCTAssertEqual(document.text.string, "One\nTwo")
    }

    func testUnchangedMarkdownReturnsNil() {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Same", isStreaming: true)
        XCTAssertNil(document.update(markdown: "Same", isStreaming: true))
    }

    func testReplacedTextFallsBackToAFullParse() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Alpha\n\nBeta", isStreaming: true)
        let edit = try XCTUnwrap(document.update(markdown: "Gamma\n\nBeta", isStreaming: true))
        XCTAssertEqual(edit.range.location, 0)
        XCTAssertEqual(document.text.string, "Gamma\nBeta")
    }

    func testEndingStreamUsesRawMarkdown() {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Say **bol", isStreaming: true)
        XCTAssertEqual(document.text.string, "Say bol")
        _ = document.update(markdown: "Say **bol", isStreaming: false)
        XCTAssertEqual(document.text.string, "Say **bol", "the settled render must match a static render exactly")
    }

    func testRemovingBlocksTrimsTheSeparator() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "One\n\nTwo", isStreaming: true)
        _ = try XCTUnwrap(document.update(markdown: "One", isStreaming: false))
        XCTAssertEqual(document.text.string, "One")
    }

    func testEveryPrefixMatchesAFreshCompose() {
        let markdown = """
        # Title

        Some **bold** and `code` with a [link](https://example.com).

        - one
        - two with *em*
          - nested

        > quoted **text**

        ```swift
        let x = 1
        ```

        | a | b |
        |---|---|
        | 1 | 2 |

        Last paragraph.
        """
        let document = GlimmerStreamingDocument(composer: composer)
        let mirror = NSMutableAttributedString()
        let characters = Array(markdown)
        var previousLastOffset = 0
        for end in stride(from: 1, through: characters.count, by: 2) {
            let prefix = String(characters[..<end])
            if let edit = document.update(markdown: prefix, isStreaming: true) {
                XCTAssertGreaterThanOrEqual(edit.range.location, min(previousLastOffset, mirror.length),
                                            "committed blocks changed at prefix \(end)")
                mirror.replaceCharacters(in: edit.range, with: edit.replacement)
            }
            assertEquivalent(document.text, freshCompose(prefix, isStreaming: true), "prefix \(end)")
            assertEquivalent(mirror, document.text, "mirror at prefix \(end)")
            previousLastOffset = max(0, (document.blockOffsets.last ?? 1) - 1)
        }
        if let edit = document.update(markdown: markdown, isStreaming: false) {
            mirror.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        assertEquivalent(document.text, freshCompose(markdown, isStreaming: false), "final")
        assertEquivalent(mirror, document.text, "final mirror")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerStreamingDocumentTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerStreamingDocument' in scope`.

- [ ] **Step 3: Implement**

`Sources/Glimmer/Engine/Stream/GlimmerStreamingDocument.swift`:
```swift
import UIKit

/// A change to a document's text: replace `range` of the previous text with `replacement`.
struct GlimmerDocumentEdit {
    let range: NSRange
    let replacement: NSAttributedString
}

/// The document behind a streaming `GlimmerView`.
///
/// Each update re-parses from the start of the last top-level block (earlier blocks cannot change when text is
/// appended), re-composes only blocks that differ, and returns one edit covering the changed tail. Anything that is not
/// an append, or that uses link reference definitions, re-parses in full. `text` always equals a fresh
/// `compose(parse(…))` of the same (healed) markdown.
@MainActor
final class GlimmerStreamingDocument {
    private(set) var text = NSMutableAttributedString()
    private(set) var blocks: [GlimmerBlock] = []
    /// UTF-16 offset in `text` where each block's composed text starts.
    private(set) var blockOffsets: [Int] = []

    private var fragments: [NSAttributedString] = []
    private var startLines: [Int] = []
    private var source = ""
    private let composer: GlimmerComposer

    init(composer: GlimmerComposer) {
        self.composer = composer
    }

    /// Moves the document to `markdown` (already preprocessed by extensions). Returns the edit that turns the previous
    /// `text` into the new one, or nil when nothing changed.
    func update(markdown: String, isStreaming: Bool) -> GlimmerDocumentEdit? {
        let newSource = isStreaming ? GlimmerTailHealer.heal(markdown) : markdown
        guard newSource != source else { return nil }
        let parsed = parse(newSource)
        source = newSource

        var firstChanged = parsed.searchFrom
        while firstChanged < min(blocks.count, parsed.blocks.count), blocks[firstChanged] == parsed.blocks[firstChanged] {
            firstChanged += 1
        }
        guard firstChanged < max(blocks.count, parsed.blocks.count) else {
            startLines = parsed.startLines
            return nil
        }

        let prefixLength = firstChanged > 0 ? blockOffsets[firstChanged - 1] + fragments[firstChanged - 1].length : 0
        var newFragments = Array(fragments[..<firstChanged])
        var newOffsets = Array(blockOffsets[..<firstChanged])
        var running = prefixLength
        for index in firstChanged..<parsed.blocks.count {
            let fragment = composer.composeBlock(parsed.blocks[index], isFirst: index == 0)
            newFragments.append(fragment)
            newOffsets.append(running)
            running += fragment.length
        }
        let newTextLength = max(0, running - 1)
        let editStart = min(prefixLength, text.length, newTextLength)

        // The new text from `editStart` to its end: the tail of the last kept block's newline, then the new blocks.
        let replacement = NSMutableAttributedString()
        if editStart < prefixLength, firstChanged > 0 {
            let previous = newFragments[firstChanged - 1]
            let keep = prefixLength - editStart
            replacement.append(previous.attributedSubstring(from: NSRange(location: previous.length - keep, length: keep)))
        }
        for fragment in newFragments[firstChanged...] { replacement.append(fragment) }
        let expectedLength = newTextLength - editStart
        if replacement.length > expectedLength {
            replacement.deleteCharacters(in: NSRange(location: expectedLength, length: replacement.length - expectedLength))
        }

        let edit = GlimmerDocumentEdit(range: NSRange(location: editStart, length: text.length - editStart), replacement: replacement)
        text.replaceCharacters(in: edit.range, with: replacement)
        blocks = parsed.blocks
        startLines = parsed.startLines
        fragments = newFragments
        blockOffsets = newOffsets
        return edit
    }

    // MARK: - Parsing

    /// Blocks and start lines for `newSource`, plus the first block index that could differ from the current blocks.
    private func parse(_ newSource: String) -> (blocks: [GlimmerBlock], startLines: [Int], searchFrom: Int) {
        if let lastLine = startLines.last,
           !Self.hasLinkReferenceDefinition(newSource),
           let oldTailStart = Self.index(ofLine: lastLine, in: source),
           newSource.utf8.starts(with: source.utf8[..<oldTailStart]),
           let newTailStart = Self.index(ofLine: lastLine, in: newSource) {
            let tail = GlimmerParser.parseWithLines(String(newSource[newTailStart...]))
            return (
                Array(blocks.dropLast()) + tail.map(\.block),
                Array(startLines.dropLast()) + tail.map { $0.startLine + lastLine - 1 },
                max(0, blocks.count - 1)
            )
        }
        let all = GlimmerParser.parseWithLines(newSource)
        return (all.map(\.block), all.map(\.startLine), 0)
    }

    /// Where 1-based `line` starts in `string`, or nil if the string has fewer lines.
    static func index(ofLine line: Int, in string: String) -> String.Index? {
        guard line > 1 else { return string.startIndex }
        var newlines = 0
        var index = string.utf8.startIndex
        while index < string.utf8.endIndex {
            if string.utf8[index] == UInt8(ascii: "\n") {
                newlines += 1
                if newlines == line - 1 { return string.utf8.index(after: index) }
            }
            index = string.utf8.index(after: index)
        }
        return nil
    }

    /// Link reference definitions can change earlier blocks, so a document using them always re-parses in full.
    static func hasLinkReferenceDefinition(_ markdown: String) -> Bool {
        markdown.contains(#/(?m)^ {0,3}\[[^\]]+\]:/#)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerStreamingDocumentTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`. `testEveryPrefixMatchesAFreshCompose` is the canonical-equivalence guard. If a prefix diverges, the tail re-parse is not equivalent there. Find the construct (the failing prefix is in the message) and either fix the tail start or make that construct fall back to a full parse, as link reference definitions do. Ledger the ruling.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Stream/GlimmerStreamingDocument.swift Tests/GlimmerTests/Engine/GlimmerStreamingDocumentTests.swift
git commit -m "Engine: stream markdown with tail re-parse and per-block edits"
```

---

### Task 4: Text view edits and reveal geometry

**Files:**
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerTextViewEditTests.swift`

**Interfaces:**
- Consumes: `GlimmerDocumentEdit` and `GlimmerStreamingDocument` (Task 3), and Plan 1's `hostInWindow`, `settle` and `layoutFragments`.
- Produces, on `GlimmerTextView`:
  - `func apply(_ edit: GlimmerDocumentEdit)`, one editing transaction.
  - `func textRange(for range: NSRange) -> NSTextRange?`
  - `func segmentRects(for range: NSRange) -> [CGRect]`, in container coordinates, which equal view coordinates because the inset is zero.
  - `func lineRect(atCharacter index: Int) -> CGRect?`

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerTextViewEditTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTextViewEditTests: XCTestCase {
    private let composer = GlimmerComposer(theme: .default)

    func testAppendingKeepsEarlierLayoutFragments() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        let textView = GlimmerTextView()
        if let edit = document.update(markdown: "First paragraph.\n\nSecond", isStreaming: true) { textView.apply(edit) }
        let window = hostInWindow(textView, width: 390, height: 400)
        let before = layoutFragments(textView).map(ObjectIdentifier.init)
        let edit = try XCTUnwrap(document.update(markdown: "First paragraph.\n\nSecond paragraph grows.", isStreaming: true))
        textView.apply(edit)
        let after = layoutFragments(textView).map(ObjectIdentifier.init)
        XCTAssertEqual(textView.textStorage.string, document.text.string)
        XCTAssertEqual(before.first, after.first, "the untouched first paragraph keeps its layout fragment")
        _ = window
    }

    func testSegmentRectsCoverEveryLineOfAWrappedRange() {
        let textView = GlimmerTextView()
        textView.attributedText = composer.compose(GlimmerParser.parse(String(repeating: "wrapping words ", count: 20)))
        let window = hostInWindow(textView, width: 200, height: 600)
        let rects = textView.segmentRects(for: NSRange(location: 0, length: textView.textStorage.length))
        XCTAssertGreaterThan(rects.count, 1)
        XCTAssertEqual(rects.first?.minY ?? -1, 0, accuracy: 0.5)
        XCTAssertLessThanOrEqual(rects.map(\.maxX).max() ?? 0, 200.5)
        _ = window
    }

    func testLineRectCoversAWholeLineHeight() throws {
        let theme = GlimmerTheme.default
        let textView = GlimmerTextView()
        textView.attributedText = composer.compose(GlimmerParser.parse("Hello there"))
        let window = hostInWindow(textView, width: 390, height: 200)
        let rect = try XCTUnwrap(textView.lineRect(atCharacter: 0))
        XCTAssertGreaterThanOrEqual(rect.height, theme.bodyFont.lineHeight - 0.5)
        XCTAssertNil(textView.lineRect(atCharacter: textView.textStorage.length))
        _ = window
    }

    func testBlockAttachmentSegmentMatchesTheEmbed() throws {
        let textView = GlimmerTextView()
        textView.attributedText = composer.compose(GlimmerParser.parse("```\nx\ny\n```"))
        let height = textView.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: height)
        let code = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: textView))
        let rect = try XCTUnwrap(textView.segmentRects(for: NSRange(location: 0, length: 1)).first)
        XCTAssertEqual(rect.height, code.frame.height, accuracy: 1)
        _ = window
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerTextViewEditTests 2>&1 | tail -5`
Expected: a build failure, `value of type 'GlimmerTextView' has no member 'apply'`. (There is `apply(theme:)`; the unlabeled `apply(_:)` does not exist yet.)

- [ ] **Step 3: Implement**

In `Sources/Glimmer/Engine/Render/GlimmerTextView.swift`, add these members after `layoutSubviews()`:
```swift
    // MARK: - Streaming edits

    /// Applies a document edit in one TextKit 2 editing transaction, so only the changed paragraphs lay out again.
    func apply(_ edit: GlimmerDocumentEdit) {
        if let content = textLayoutManager?.textContentManager as? NSTextContentStorage {
            content.performEditingTransaction {
                textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            }
        } else {
            textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        invalidateIntrinsicContentSize()
    }

    // MARK: - Reveal geometry

    func textRange(for range: NSRange) -> NSTextRange? {
        guard let content = textLayoutManager?.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// Rects covering the glyphs of `range`, one per line segment, in the text view's coordinates.
    func segmentRects(for range: NSRange) -> [CGRect] {
        guard range.length > 0, NSMaxRange(range) <= textStorage.length,
              let manager = textLayoutManager, let textRange = textRange(for: range) else { return [] }
        manager.ensureLayout(for: textRange)
        var rects: [CGRect] = []
        manager.enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
            rects.append(frame)
            return true
        }
        return rects
    }

    /// The line box holding the character at `index`, or nil past the end of the text.
    func lineRect(atCharacter index: Int) -> CGRect? {
        guard index >= 0, index < textStorage.length else { return nil }
        return segmentRects(for: NSRange(location: index, length: 1)).first
    }
```

- [ ] **Step 4: Run the tests, plus the Plan 1 text view tests**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerTextViewEditTests -only-testing:GlimmerTests/GlimmerTextViewTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Render/GlimmerTextView.swift Tests/GlimmerTests/Engine/GlimmerTextViewEditTests.swift
git commit -m "Engine: apply streaming edits in one transaction and expose line geometry"
```

---

### Task 5: Reveal options and the phrase chunker

**Files:**
- Create: `Sources/Glimmer/Engine/Reveal/GlimmerRevealOptions.swift`
- Create: `Sources/Glimmer/Engine/Reveal/GlimmerPhraseChunker.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerPhraseChunkerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct GlimmerRevealOptions: Equatable, Sendable`, with defaults `fadeDuration` 0.6, `baseRate` 60, `targetLag` 0.4, `drainDuration` 1.5, `minPhraseSpacing` 0.06, `rateSmoothing` 0.25, `minPhraseWords` 3 and `maxPhraseWords` 8, and `public init()`.
  - `public enum GlimmerReveal: Equatable, Sendable { case none, smooth(GlimmerRevealOptions) }`.
  - `enum GlimmerPhraseChunker { static func phraseEnd(in text: NSString, from start: Int, isStreaming: Bool, minWords: Int, maxWords: Int) -> Int? }`.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerPhraseChunkerTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerPhraseChunkerTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerPhraseChunker' in scope`.

- [ ] **Step 3: Implement**

`Sources/Glimmer/Engine/Reveal/GlimmerRevealOptions.swift`:
```swift
import Foundation

/// Tuning for the streaming reveal: phrases paced against the arriving text, each fading in (spec §5).
public struct GlimmerRevealOptions: Equatable, Sendable {
    /// Seconds for a phrase to fade from transparent to opaque (linear).
    public var fadeDuration: TimeInterval = 0.6
    /// The slowest reveal speed, in UTF-16 characters per second.
    public var baseRate: Double = 60
    /// How far behind the arrived text the reveal aims to stay while streaming.
    public var targetLag: TimeInterval = 0.4
    /// Once streaming ends, the remaining text is revealed within about this long.
    public var drainDuration: TimeInterval = 1.5
    /// The smallest gap between two phrase starts. Fast streams get longer phrases instead of faster starts.
    public var minPhraseSpacing: TimeInterval = 0.06
    /// How gradually the speed follows the backlog; larger is smoother.
    public var rateSmoothing: TimeInterval = 0.25
    public var minPhraseWords = 3
    public var maxPhraseWords = 8

    public init() {}
}

/// Whether and how a streaming answer is revealed.
public enum GlimmerReveal: Equatable, Sendable {
    /// Text appears as soon as it arrives.
    case none
    /// Gemini-style phrase fades paced against the arriving text.
    case smooth(GlimmerRevealOptions)
}
```

`Sources/Glimmer/Engine/Reveal/GlimmerPhraseChunker.swift`:
```swift
import Foundation

/// Splits arriving text into reveal phrases.
enum GlimmerPhraseChunker {
    /// The UTF-16 offset where the phrase starting at `start` ends, or nil while not enough complete text has arrived.
    ///
    /// A phrase ends after punctuation once it has `minWords` words, at `maxWords` words, or at a line end. Words and
    /// grapheme clusters are never split; a block attachment on its own line is a phrase by itself. While streaming, a
    /// word counts only once whitespace follows it.
    static func phraseEnd(in text: NSString, from start: Int, isStreaming: Bool, minWords: Int, maxWords: Int) -> Int? {
        let length = text.length
        guard start < length else { return nil }
        var index = start
        var words = 0
        var inWord = false
        var lastWordEndsWithPunctuation = false
        var lastCompleteEnd: Int?
        while index < length {
            let range = text.rangeOfComposedCharacterSequence(at: index)
            let character = text.substring(with: range)
            if character == "\n" { return NSMaxRange(range) }
            if character == " " || character == "\t" {
                if inWord {
                    inWord = false
                    words += 1
                    if words >= maxWords || (words >= minWords && lastWordEndsWithPunctuation) {
                        return endOfWhitespace(in: text, from: NSMaxRange(range))
                    }
                }
                lastCompleteEnd = NSMaxRange(range)
            } else {
                inWord = true
                lastWordEndsWithPunctuation = character.count == 1 && ",.;:!?".contains(character)
            }
            index = NSMaxRange(range)
        }
        if !isStreaming { return length }
        if words >= minWords, let lastCompleteEnd { return lastCompleteEnd }
        return nil
    }

    /// Past the spaces after a phrase, and past one line end if that is what follows them.
    private static func endOfWhitespace(in text: NSString, from index: Int) -> Int {
        var end = index
        while end < text.length {
            let unit = text.character(at: end)
            if unit == 0x20 || unit == 0x09 { end += 1; continue }
            if unit == 0x0A { end += 1 }
            break
        }
        return end
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerPhraseChunkerTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Reveal/GlimmerRevealOptions.swift Sources/Glimmer/Engine/Reveal/GlimmerPhraseChunker.swift Tests/GlimmerTests/Engine/GlimmerPhraseChunkerTests.swift
git commit -m "Engine: add reveal options and split arriving text into phrases"
```

---

### Task 6: Pacing

**Files:**
- Create: `Sources/Glimmer/Engine/Reveal/GlimmerPacing.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerPacingTests.swift`

**Interfaces:**
- Consumes: `GlimmerRevealOptions` (Task 5).
- Produces: `struct GlimmerPacing`, created with `init(options:)`. It exposes `private(set) var rate: Double` and provides `mutating func updateRate(backlog: Int, isStreaming: Bool, now: TimeInterval)`, `var minimumPhraseLength: Int` and `func interval(forPhraseLength length: Int) -> TimeInterval`.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerPacingTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerPacingTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerPacing' in scope`.

- [ ] **Step 3: Implement**

`Sources/Glimmer/Engine/Reveal/GlimmerPacing.swift`:
```swift
import Foundation

/// The reveal speed. It follows the backlog of arrived-but-unrevealed text smoothly, never drops below `baseRate`, and
/// empties the backlog within `drainDuration` once streaming ends. When the speed would need phrases closer together
/// than `minPhraseSpacing`, phrases get longer instead.
struct GlimmerPacing {
    let options: GlimmerRevealOptions
    /// Characters per second.
    private(set) var rate: Double
    private var lastUpdate: TimeInterval?

    init(options: GlimmerRevealOptions) {
        self.options = options
        rate = options.baseRate
    }

    mutating func updateRate(backlog: Int, isStreaming: Bool, now: TimeInterval) {
        let window = max(isStreaming ? options.targetLag : options.drainDuration, 0.001)
        let target = max(options.baseRate, Double(backlog) / window)
        if let lastUpdate {
            let blend = min(1, max(0, now - lastUpdate) / max(options.rateSmoothing, 0.001))
            rate += (target - rate) * blend
        } else {
            rate = target
        }
        lastUpdate = now
    }

    /// Characters a phrase should carry so phrase starts stay at least `minPhraseSpacing` apart at this rate.
    var minimumPhraseLength: Int {
        Int((rate * options.minPhraseSpacing).rounded(.up))
    }

    /// Seconds from one phrase starting to the next.
    func interval(forPhraseLength length: Int) -> TimeInterval {
        max(options.minPhraseSpacing, Double(length) / rate)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerPacingTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Reveal/GlimmerPacing.swift Tests/GlimmerTests/Engine/GlimmerPacingTests.swift
git commit -m "Engine: pace the reveal against the backlog"
```

---

### Task 7: Reveal engine

**Files:**
- Create: `Sources/Glimmer/Engine/Reveal/GlimmerRevealEngine.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerRevealEngineTests.swift`

**Interfaces:**
- Consumes: `GlimmerRevealOptions` and `GlimmerPhraseChunker` (Task 5), `GlimmerPacing` (Task 6).
- Produces: `struct GlimmerRevealEngine`, created with `init(options: GlimmerRevealOptions, alreadyRevealed: Int = 0)`. It has:
  - `struct Phrase: Equatable { var range: NSRange; var start: TimeInterval }`;
  - `let options`;
  - read-only state: `phrases: [Phrase]` (active, oldest first), `revealedLength`, `settledLength`, `isStreaming` and `nextPhraseStart: TimeInterval?`;
  - methods `mutating func textChanged(_ text: NSString, isStreaming: Bool, now: TimeInterval)` and `mutating func advance(to now: TimeInterval)`;
  - computed `var nextWake: TimeInterval?` and `var isComplete: Bool`.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerRevealEngineTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerRevealEngineTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerRevealEngine' in scope`.

- [ ] **Step 3: Implement**

`Sources/Glimmer/Engine/Reveal/GlimmerRevealEngine.swift`:
```swift
import Foundation

/// Decides what is revealed when. Works on UTF-16 offsets and seconds only (no UIKit), so it is unit-tested with a
/// hand-driven clock. `GlimmerView` feeds it the text and the time; `GlimmerRevealMask` draws its state.
struct GlimmerRevealEngine {
    struct Phrase: Equatable {
        var range: NSRange
        var start: TimeInterval
    }

    let options: GlimmerRevealOptions
    /// Phrases that have started but not finished fading, oldest first.
    private(set) var phrases: [Phrase] = []
    /// Characters covered by started phrases.
    private(set) var revealedLength: Int
    /// Characters whose fade has finished.
    private(set) var settledLength: Int
    private(set) var isStreaming = true
    private(set) var nextPhraseStart: TimeInterval?

    private var text: NSString = ""
    private var pacing: GlimmerPacing
    /// When the next phrase may start once more text arrives, if the reveal is waiting for text.
    private var earliestNextStart: TimeInterval?

    init(options: GlimmerRevealOptions, alreadyRevealed: Int = 0) {
        self.options = options
        pacing = GlimmerPacing(options: options)
        revealedLength = alreadyRevealed
        settledLength = alreadyRevealed
    }

    /// The whole current text. What was revealed stays revealed, clamped if the text got shorter.
    mutating func textChanged(_ text: NSString, isStreaming: Bool, now: TimeInterval) {
        self.text = text
        self.isStreaming = isStreaming
        revealedLength = min(revealedLength, text.length)
        settledLength = min(settledLength, revealedLength)
        phrases = phrases.compactMap { phrase in
            let end = min(NSMaxRange(phrase.range), revealedLength)
            guard end > phrase.range.location else { return nil }
            return Phrase(range: NSRange(location: phrase.range.location, length: end - phrase.range.location), start: phrase.start)
        }
        if nextPhraseStart == nil, revealedLength < text.length {
            nextPhraseStart = max(now, earliestNextStart ?? now)
        }
    }

    /// Starts every phrase due by `now` and settles every fade finished by `now`.
    mutating func advance(to now: TimeInterval) {
        while let due = nextPhraseStart, due <= now {
            pacing.updateRate(backlog: text.length - revealedLength, isStreaming: isStreaming, now: due)
            guard var end = chunk(from: revealedLength) else {
                nextPhraseStart = nil
                earliestNextStart = due
                break
            }
            // Fast streams: grow the phrase instead of starting phrases closer than `minPhraseSpacing`.
            while end - revealedLength < pacing.minimumPhraseLength, end < text.length, let next = chunk(from: end) {
                end = next
            }
            let phrase = Phrase(range: NSRange(location: revealedLength, length: end - revealedLength), start: due)
            phrases.append(phrase)
            revealedLength = end
            nextPhraseStart = due + pacing.interval(forPhraseLength: phrase.range.length)
        }
        while let first = phrases.first, first.start + options.fadeDuration <= now {
            phrases.removeFirst()
            settledLength = NSMaxRange(first.range)
        }
        if phrases.isEmpty { settledLength = revealedLength }
    }

    /// The next time `advance(to:)` has work to do, or nil when idle.
    var nextWake: TimeInterval? {
        let start = revealedLength < text.length ? nextPhraseStart : nil
        return [start, phrases.first.map { $0.start + options.fadeDuration }].compactMap { $0 }.min()
    }

    var isComplete: Bool {
        !isStreaming && revealedLength >= text.length && phrases.isEmpty
    }

    private func chunk(from start: Int) -> Int? {
        GlimmerPhraseChunker.phraseEnd(in: text, from: start, isStreaming: isStreaming,
                                       minWords: options.minPhraseWords, maxWords: options.maxPhraseWords)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerRevealEngineTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Reveal/GlimmerRevealEngine.swift Tests/GlimmerTests/Engine/GlimmerRevealEngineTests.swift
git commit -m "Engine: add the reveal state machine"
```

---

### Task 8: Reveal mask

**Files:**
- Create: `Sources/Glimmer/Engine/Reveal/GlimmerRevealMask.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerRevealMaskTests.swift`

**Interfaces:**
- Consumes: `GlimmerTextView.segmentRects`/`lineRect` (Task 4) and `GlimmerRevealEngine` (Task 7).
- Produces: `@MainActor final class GlimmerRevealMask`, with:
  - `let layer: CALayer`;
  - `func update(in textView: GlimmerTextView, engine: GlimmerRevealEngine, now: TimeInterval)`;
  - `func invalidateGeometry()`;
  - test accessors `settledRect: CGRect`, `settledLinePath: CGPath?`, `phraseLayerCount: Int` and `phraseLayer(startingAt: Int) -> CAShapeLayer?`.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerRevealMaskTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerRevealMaskTests: XCTestCase {
    private let options = GlimmerRevealOptions()

    private func hosted(_ markdown: String, width: CGFloat = 390) -> (GlimmerTextView, UIWindow) {
        let textView = GlimmerTextView()
        textView.attributedText = GlimmerComposer(theme: .default).compose(GlimmerParser.parse(markdown))
        let height = textView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        return (textView, hostInWindow(textView, width: width, height: height))
    }

    private func engine(for textView: GlimmerTextView, streaming: Bool, advancedTo time: TimeInterval) -> GlimmerRevealEngine {
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged(NSString(string: textView.textStorage.string), isStreaming: streaming, now: 0)
        engine.advance(to: time)
        return engine
    }

    func testNothingRevealedCoversNothing() {
        let (textView, window) = hosted("Hidden until revealed.")
        let mask = GlimmerRevealMask()
        mask.update(in: textView, engine: GlimmerRevealEngine(options: options), now: 0)
        XCTAssertEqual(mask.settledRect.height, 0)
        XCTAssertEqual(mask.phraseLayerCount, 0)
        XCTAssertTrue(mask.settledLinePath?.isEmpty ?? true)
        _ = window
    }

    func testStartedPhraseFadesInOverItsGlyphs() throws {
        let (textView, window) = hosted("One two three four five six seven eight nine ten eleven")
        let engine = engine(for: textView, streaming: true, advancedTo: 0)
        let mask = GlimmerRevealMask()
        mask.update(in: textView, engine: engine, now: 0)
        let phrase = try XCTUnwrap(engine.phrases.first)
        let layer = try XCTUnwrap(mask.phraseLayer(startingAt: 0))
        let fade = try XCTUnwrap(layer.animation(forKey: "glimmer.fade") as? CABasicAnimation)
        XCTAssertEqual(fade.fromValue as? Double, 0)
        XCTAssertEqual(fade.toValue as? Double, 1)
        XCTAssertEqual(fade.duration, options.fadeDuration, accuracy: 1e-6)
        XCTAssertEqual(layer.opacity, 1, "the model value is opaque so the layer stays visible after the fade")
        let covered = try XCTUnwrap(layer.path?.boundingBox)
        for rect in textView.segmentRects(for: phrase.range) {
            XCTAssertTrue(covered.insetBy(dx: -0.5, dy: -0.5).contains(rect))
        }
        _ = window
    }

    func testSettledTextIsCoveredWithoutPhraseLayers() {
        let (textView, window) = hosted("Short settled line.")
        let engine = engine(for: textView, streaming: false, advancedTo: 5)
        let mask = GlimmerRevealMask()
        mask.update(in: textView, engine: engine, now: 5)
        XCTAssertEqual(mask.phraseLayerCount, 0)
        XCTAssertEqual(mask.settledRect.height, textView.bounds.height, accuracy: 0.5)
        _ = window
    }

    func testWidthChangeRebuildsPhraseGeometry() throws {
        let words = (1...40).map { "word\($0)" }.joined(separator: " ")
        let (textView, window) = hosted(words, width: 390)
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged(NSString(string: textView.textStorage.string), isStreaming: false, now: 0)
        engine.advance(to: 0)
        let mask = GlimmerRevealMask()
        mask.update(in: textView, engine: engine, now: 0)
        let before = try XCTUnwrap(mask.phraseLayer(startingAt: 0)?.path?.boundingBox)

        textView.frame.size.width = 180
        settle(textView)
        mask.update(in: textView, engine: engine, now: 0.3)
        let layer = try XCTUnwrap(mask.phraseLayer(startingAt: 0))
        XCTAssertNotEqual(layer.path?.boundingBox, before)
        let fade = try XCTUnwrap(layer.animation(forKey: "glimmer.fade") as? CABasicAnimation)
        XCTAssertEqual(fade.fromValue as? Double ?? 0, 0.5, accuracy: 0.01, "continues from the current opacity")
        XCTAssertEqual(fade.duration, 0.3, accuracy: 0.01)
        _ = window
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerRevealMaskTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerRevealMask' in scope`.

- [ ] **Step 3: Implement**

`Sources/Glimmer/Engine/Reveal/GlimmerRevealMask.swift`:
```swift
import UIKit

/// Draws a reveal as a mask on the text view. Settled text sits under one opaque rect plus the settled part of the
/// current line; each fading phrase has its own layer whose opacity Core Animation runs from 0 to 1; text not yet
/// revealed is simply not covered. It changes only when a phrase starts or settles or the layout changes — never per
/// frame — and it does not depend on the background, so it works over glass and gradients.
@MainActor
final class GlimmerRevealMask {
    let layer = CALayer()

    private let settledLayer = CALayer()
    private let settledLineLayer = CAShapeLayer()
    private var phraseLayers: [Int: CAShapeLayer] = [:]
    private var geometryWidth: CGFloat = -1

    init() {
        settledLayer.backgroundColor = UIColor.black.cgColor
        settledLineLayer.fillColor = UIColor.black.cgColor
        layer.addSublayer(settledLayer)
        layer.addSublayer(settledLineLayer)
    }

    var settledRect: CGRect { settledLayer.frame }
    var settledLinePath: CGPath? { settledLineLayer.path }
    var phraseLayerCount: Int { phraseLayers.count }
    func phraseLayer(startingAt location: Int) -> CAShapeLayer? { phraseLayers[location] }

    /// Forces phrase geometry to be rebuilt on the next update (theme or text changes that move glyphs).
    func invalidateGeometry() {
        geometryWidth = -1
    }

    func update(in textView: GlimmerTextView, engine: GlimmerRevealEngine, now: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let bounds = textView.bounds
        layer.frame = bounds
        let rebuild = bounds.width != geometryWidth
        geometryWidth = bounds.width

        // Settled: every line above the first unsettled character, plus that line's settled part.
        let firstUnsettled = engine.settledLength
        let lineTop = textView.lineRect(atCharacter: firstUnsettled)?.minY ?? bounds.height
        settledLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: lineTop)
        let lineStart = max(0, firstUnsettled - 512)
        let settledOnLine = textView.segmentRects(for: NSRange(location: lineStart, length: firstUnsettled - lineStart))
            .filter { $0.minY >= lineTop - 0.5 }
        settledLineLayer.path = Self.path(settledOnLine)

        // Fading: one layer per active phrase, keyed by its start offset.
        var live = Set<Int>()
        for phrase in engine.phrases {
            let key = phrase.range.location
            live.insert(key)
            let existing = phraseLayers[key]
            guard existing == nil || rebuild else { continue }
            let phraseLayer = existing ?? CAShapeLayer()
            phraseLayer.fillColor = UIColor.black.cgColor
            phraseLayer.path = Self.path(textView.segmentRects(for: phrase.range))
            phraseLayer.opacity = 1
            let elapsed = min(max(0, now - phrase.start), engine.options.fadeDuration)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = elapsed / engine.options.fadeDuration
            fade.toValue = 1.0
            fade.duration = max(0.001, engine.options.fadeDuration - elapsed)
            fade.timingFunction = CAMediaTimingFunction(name: .linear)
            fade.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
            phraseLayer.add(fade, forKey: "glimmer.fade")
            if existing == nil {
                layer.addSublayer(phraseLayer)
                phraseLayers[key] = phraseLayer
            }
        }
        for (key, stale) in phraseLayers where !live.contains(key) {
            stale.removeFromSuperlayer()
            phraseLayers[key] = nil
        }
    }

    private static func path(_ rects: [CGRect]) -> CGPath {
        let path = CGMutablePath()
        for rect in rects { path.addRect(rect.insetBy(dx: -1, dy: -2)) }
        return path
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerRevealMaskTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Reveal/GlimmerRevealMask.swift Tests/GlimmerTests/Engine/GlimmerRevealMaskTests.swift
git commit -m "Engine: render the reveal as a Core Animation mask"
```

---

### Task 9: Streaming `GlimmerView` — clock, store, reveal wiring, revealed height

**Files:**
- Create: `Sources/Glimmer/Engine/Reveal/GlimmerRevealClock.swift`
- Create: `Sources/Glimmer/Engine/Reveal/GlimmerRevealStore.swift`
- Modify: `Sources/Glimmer/Engine/GlimmerConfiguration.swift`
- Modify (replace the file): `Sources/Glimmer/Engine/GlimmerView.swift`
- Modify: `Sources/Glimmer/Engine/GlimmerText.swift`
- Modify: `Tests/GlimmerTests/Engine/EngineTestSupport.swift` (add `ManualRevealClock`)
- Test: `Tests/GlimmerTests/Engine/GlimmerViewStreamingTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces:
  - `@MainActor protocol GlimmerRevealClock: AnyObject`, with `var now: TimeInterval { get }`, `func wake(at:_:)` and `func cancel()`; plus `GlimmerSystemRevealClock`.
  - `@MainActor final class GlimmerRevealStore`, with `static let shared`, `init(capacity:)`, `revealedLength(for:) -> Int?`, `record(_:for:)` (monotonic) and `clear(_:)`.
  - `GlimmerConfiguration.reveal: GlimmerReveal`, defaulting to `.smooth(GlimmerRevealOptions())`.
  - `GlimmerView.update(markdown: String, isStreaming: Bool, revealID: String? = nil)`, with Plan 1's `update(markdown:)` forwarding as `isStreaming: false`.
  - Internal: `var clock`, `private(set) var engine`, `let revealMask`, `func advanceReveal()`.
  - `GlimmerText.init(_:isStreaming:revealID:configuration:onLinkTap:)`.

- [ ] **Step 1: Add the manual clock to test support**

Append to `Tests/GlimmerTests/Engine/EngineTestSupport.swift`:
```swift
/// A reveal clock tests drive by hand: `advance(to:)` fires every due wake-up in order.
@MainActor
final class ManualRevealClock: GlimmerRevealClock {
    private(set) var now: TimeInterval = 0
    private(set) var scheduled: TimeInterval?
    private var action: (@MainActor () -> Void)?

    func wake(at time: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        scheduled = time
        self.action = action
    }

    func cancel() {
        scheduled = nil
        action = nil
    }

    func advance(to time: TimeInterval) {
        while let due = scheduled, due <= time, let pending = action {
            now = due
            scheduled = nil
            action = nil
            pending()
        }
        now = max(now, time)
    }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerViewStreamingTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerViewStreamingTests: XCTestCase {
    private let answer = "First sentence of the answer arrives now. Then a second sentence follows it closely, and a third one wraps onto more lines of the view."

    private func streamingView(width: CGFloat = 320) -> (GlimmerView, ManualRevealClock, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: width, height: 800)
        return (view, clock, window)
    }

    private func fullHeight(_ view: GlimmerView) -> CGFloat {
        view.textView.sizeThatFits(CGSize(width: view.bounds.width, height: CGFloat.greatestFiniteMagnitude)).height
    }

    func testStreamingStartsMaskedAndRevealsFromTheFirstPhrase() throws {
        let (view, _, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        XCTAssertNotNil(view.textView.layer.mask)
        let engine = try XCTUnwrap(view.engine)
        XCTAssertGreaterThan(engine.revealedLength, 0)
        XCTAssertLessThan(engine.revealedLength, view.textView.textStorage.length)
        XCTAssertLessThan(view.intrinsicContentSize.height, fullHeight(view), "height ends at the last revealed line")
        _ = window
    }

    func testStaticUpdateShowsEverythingWithoutAMask() {
        let (view, _, window) = streamingView()
        view.update(markdown: answer)
        XCTAssertNil(view.textView.layer.mask)
        XCTAssertNil(view.engine)
        XCTAssertEqual(view.intrinsicContentSize.height, fullHeight(view), accuracy: 0.5)
        _ = window
    }

    func testRevealCompletesAndRemovesTheMask() {
        let (view, clock, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        view.update(markdown: answer, isStreaming: false)
        clock.advance(to: 10)
        XCTAssertNil(view.engine)
        XCTAssertNil(view.textView.layer.mask)
        XCTAssertEqual(view.intrinsicContentSize.height, fullHeight(view), accuracy: 0.5)
        _ = window
    }

    func testHeightGrowsWithRevealedLinesAndNeverShrinks() {
        let (view, clock, window) = streamingView(width: 240)
        var reported: [CGFloat] = []
        view.onHeightChange = { reported.append(view.intrinsicContentSize.height) }
        view.update(markdown: answer, isStreaming: true)
        var time = 0.0
        while view.engine != nil, time < 10 {
            time += 0.05
            if time > 1 { view.update(markdown: answer, isStreaming: false) }
            clock.advance(to: time)
        }
        XCTAssertGreaterThan(reported.count, 2, "the height grows line by line")
        XCTAssertEqual(reported, reported.sorted(), "the height never shrinks while revealing")
        _ = window
    }

    func testNoRevealShowsTextImmediately() {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        let window = hostInWindow(view, width: 320, height: 800)
        view.update(markdown: answer, isStreaming: true)
        XCTAssertNil(view.textView.layer.mask)
        XCTAssertNil(view.engine)
        _ = window
    }

    func testRevealIDResumesWithoutReplaying() throws {
        let store = GlimmerRevealStore.shared
        store.clear("resume-test")
        let (first, clock, window) = streamingView()
        first.update(markdown: answer, isStreaming: true, revealID: "resume-test")
        first.update(markdown: answer, isStreaming: false, revealID: "resume-test")
        clock.advance(to: 10)
        XCTAssertEqual(store.revealedLength(for: "resume-test"), first.textView.textStorage.length)

        let (second, _, secondWindow) = streamingView()
        second.update(markdown: answer, isStreaming: true, revealID: "resume-test")
        let engine = try XCTUnwrap(second.engine)
        XCTAssertEqual(engine.revealedLength, second.textView.textStorage.length)
        XCTAssertEqual(second.revealMask.phraseLayerCount, 0, "nothing fades in again")
        _ = window
        _ = secondWindow
    }

    func testReplacedStreamKeepsRevealing() throws {
        let (view, clock, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        clock.advance(to: 0.5)
        view.update(markdown: "A completely different regenerated answer with new words in it.", isStreaming: true)
        let engine = try XCTUnwrap(view.engine)
        XCTAssertLessThanOrEqual(engine.revealedLength, view.textView.textStorage.length)
        view.update(markdown: "A completely different regenerated answer with new words in it.", isStreaming: false)
        clock.advance(to: 10)
        XCTAssertNil(view.engine)
        _ = window
    }

    func testEmptyStreamingUpdateStaysEmpty() {
        let (view, clock, window) = streamingView()
        view.update(markdown: "", isStreaming: true)
        view.update(markdown: "   ", isStreaming: true)
        clock.advance(to: 1)
        XCTAssertEqual(view.intrinsicContentSize.height, 0)
        XCTAssertEqual(view.engine?.phrases.count ?? 0, 0)
        _ = window
    }

    func testStoreIsMonotonicAndBounded() {
        let store = GlimmerRevealStore(capacity: 2)
        store.record(10, for: "a")
        store.record(5, for: "a")
        XCTAssertEqual(store.revealedLength(for: "a"), 10)
        store.record(1, for: "b")
        store.record(1, for: "c")
        XCTAssertNil(store.revealedLength(for: "a"), "least recently used is evicted")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerViewStreamingTests 2>&1 | tail -5`
Expected: a build failure, `cannot find type 'GlimmerRevealClock' in scope`.

- [ ] **Step 4: Implement the clock and the store**

`Sources/Glimmer/Engine/Reveal/GlimmerRevealClock.swift`:
```swift
import QuartzCore

/// Time and wake-ups for the reveal. Tests substitute a manual clock.
@MainActor
protocol GlimmerRevealClock: AnyObject {
    var now: TimeInterval { get }
    /// Calls `action` at (or just after) `time`, replacing any earlier request.
    func wake(at time: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

/// Media time and a sleeping task. It wakes only for phrase starts and settles, never per frame.
@MainActor
final class GlimmerSystemRevealClock: GlimmerRevealClock {
    private var task: Task<Void, Never>?

    var now: TimeInterval { CACurrentMediaTime() }

    func wake(at time: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        let delay = max(0, time - now)
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
```

`Sources/Glimmer/Engine/Reveal/GlimmerRevealStore.swift`:
```swift
import Foundation

/// How much of each message has been revealed, so a re-created or re-configured view resumes instead of replaying.
/// Keyed by the host's message id; bounded, least recently used out; lengths only grow.
@MainActor
final class GlimmerRevealStore {
    static let shared = GlimmerRevealStore()

    private let capacity: Int
    private var lengths: [String: Int] = [:]
    private var recent: [String] = []

    init(capacity: Int = 256) {
        self.capacity = capacity
    }

    func revealedLength(for id: String) -> Int? {
        lengths[id]
    }

    func record(_ length: Int, for id: String) {
        lengths[id] = max(lengths[id] ?? 0, length)
        recent.removeAll { $0 == id }
        recent.append(id)
        if recent.count > capacity { lengths[recent.removeFirst()] = nil }
    }

    func clear(_ id: String) {
        lengths[id] = nil
        recent.removeAll { $0 == id }
    }
}
```

- [ ] **Step 5: Add the reveal option to the configuration**

In `Sources/Glimmer/Engine/GlimmerConfiguration.swift`:
- Add a stored property after `public var highlighter: any GlimmerHighlighter`:
  ```swift
      /// How streaming text appears. Reduce Motion always shows text immediately.
      public var reveal: GlimmerReveal
  ```
- Add `reveal: GlimmerReveal = .smooth(GlimmerRevealOptions())` as the last `init` parameter, and `self.reveal = reveal` in the body.

- [ ] **Step 6: Replace `GlimmerView`**

Replace `Sources/Glimmer/Engine/GlimmerView.swift` with:
```swift
import UIKit

/// Renders markdown natively with TextKit 2, and reveals a streaming answer phrase by phrase.
///
/// Size it with Auto Layout (a width constraint gives an intrinsic height) or call `sizeThatFits(_:)` with a finite
/// width. While a reveal runs, the height ends at the last revealed line. `onHeightChange` fires whenever the height
/// may have changed.
@MainActor
public final class GlimmerView: UIView {
    public var configuration: GlimmerConfiguration {
        didSet { rebuildDocument() }
    }
    public var onLinkTap: ((URL) -> Void)?
    public var onHeightChange: (() -> Void)?

    let textView = GlimmerTextView()
    let revealMask = GlimmerRevealMask()
    /// The reveal's time source; tests substitute a manual clock.
    var clock: any GlimmerRevealClock = GlimmerSystemRevealClock()
    private(set) var markdown = ""
    private(set) var isStreaming = false
    private(set) var revealID: String?
    private(set) var engine: GlimmerRevealEngine?

    private var document: GlimmerStreamingDocument
    private var lastWidth: CGFloat = 0
    private var lastReportedHeight: CGFloat = -1

    public init(configuration: GlimmerConfiguration = .default) {
        self.configuration = configuration
        document = GlimmerStreamingDocument(composer: GlimmerComposer(theme: configuration.theme))
        super.init(frame: .zero)
        // While revealing, this view is shorter than the text and clips the rest (see `fitTextViewToContent`).
        clipsToBounds = true
        textView.delegate = self
        addSubview(textView)
        rebuildDocument()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: GlimmerView, _: UITraitCollection) in
            view.rebuildDocument()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows a finished document immediately.
    public func update(markdown: String) {
        update(markdown: markdown, isStreaming: false)
    }

    /// Shows `markdown`, the accumulated text so far. While `isStreaming` is true — and until the reveal it started
    /// finishes — new text is revealed per `configuration.reveal`. Pass the same `revealID` for the same message so a
    /// re-created view resumes instead of replaying.
    public func update(markdown: String, isStreaming: Bool, revealID: String? = nil) {
        guard markdown != self.markdown || isStreaming != self.isStreaming || revealID != self.revealID else { return }
        if revealID != self.revealID { endReveal() }
        self.markdown = markdown
        self.isStreaming = isStreaming
        self.revealID = revealID
        if let edit = document.update(markdown: preprocessed(markdown), isStreaming: isStreaming) {
            textView.apply(edit)
            fitTextViewToContent()
        }
        startRevealIfNeeded()
        engine?.textChanged(NSString(string: textView.textStorage.string), isStreaming: isStreaming, now: clock.now)
        advanceReveal()
        reportHeightIfChanged()
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: height(forWidth: size.width))
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height(forWidth: bounds.width))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        fitTextViewToContent()
        if let engine { revealMask.update(in: textView, engine: engine, now: clock.now) }
        guard bounds.width != lastWidth else { return }
        lastWidth = bounds.width
        reportHeightIfChanged()
    }

    func linkAction(for url: URL) -> UIAction? {
        guard let onLinkTap else { return nil }
        return UIAction { _ in onLinkTap(url) }
    }

    // MARK: - Reveal

    /// Starts due phrases, settles finished fades, redraws the mask and schedules the next wake-up.
    func advanceReveal() {
        guard var current = engine else { return }
        let now = clock.now
        current.advance(to: now)
        if let revealID { GlimmerRevealStore.shared.record(current.revealedLength, for: revealID) }
        if current.isComplete {
            endReveal()
            reportHeightIfChanged()
            return
        }
        engine = current
        revealMask.update(in: textView, engine: current, now: now)
        reportHeightIfChanged()
        if let wake = current.nextWake {
            clock.wake(at: wake) { [weak self] in self?.advanceReveal() }
        } else {
            clock.cancel()
        }
    }

    private var revealOptions: GlimmerRevealOptions? {
        guard case .smooth(let options) = configuration.reveal, !UIAccessibility.isReduceMotionEnabled else { return nil }
        return options
    }

    private func startRevealIfNeeded() {
        guard engine == nil, isStreaming, let options = revealOptions else { return }
        let resumed = revealID.flatMap { GlimmerRevealStore.shared.revealedLength(for: $0) } ?? 0
        engine = GlimmerRevealEngine(options: options, alreadyRevealed: min(resumed, textView.textStorage.length))
        revealMask.invalidateGeometry()
        textView.layer.mask = revealMask.layer
    }

    private func endReveal() {
        engine = nil
        clock.cancel()
        textView.layer.mask = nil
    }

    // MARK: - Document

    private func preprocessed(_ markdown: String) -> String {
        configuration.extensions.reduce(markdown) { $1.preprocess($0) }
    }

    /// Re-composes everything (theme, configuration or text size changed).
    private func rebuildDocument() {
        let theme = configuration.theme.scaled(for: traitCollection)
        textView.apply(theme: theme)
        document = GlimmerStreamingDocument(composer: GlimmerComposer(
            theme: theme,
            highlighter: configuration.highlighter,
            imageLoader: configuration.imageLoader,
            extensions: configuration.extensions
        ))
        _ = document.update(markdown: preprocessed(markdown), isStreaming: isStreaming)
        textView.attributedText = document.text
        fitTextViewToContent()
        if revealOptions == nil { endReveal() }
        revealMask.invalidateGeometry()
        engine?.textChanged(NSString(string: textView.textStorage.string), isStreaming: isStreaming, now: clock.now)
        advanceReveal()
        reportHeightIfChanged()
    }

    // MARK: - Height

    /// The full document's height at `width` or, while revealing, the bottom of the last revealed line.
    private func height(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        if let engine, engine.revealedLength < textView.textStorage.length {
            guard engine.revealedLength > 0 else { return 0 }
            if textView.bounds.width != width {
                let fullHeight = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
                textView.frame = CGRect(x: 0, y: 0, width: width, height: fullHeight)
            }
            return ceil(textView.lineRect(atCharacter: engine.revealedLength - 1)?.maxY ?? 0)
        }
        return textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    /// Keeps the text view as tall as the whole document. TextKit 2 inside a text view lays out only what its viewport
    /// covers (verified in Plan 1's review fix), and the mask needs geometry for text below the revealed line.
    private func fitTextViewToContent() {
        guard bounds.width > 0 else { return }
        let fullHeight = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
        textView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height, fullHeight))
    }

    private func reportHeightIfChanged() {
        let height = height(forWidth: bounds.width)
        guard height != lastReportedHeight else { return }
        lastReportedHeight = height
        invalidateIntrinsicContentSize()
        onHeightChange?()
    }
}

extension GlimmerView: UITextViewDelegate {
    public func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return linkAction(for: url) ?? defaultAction
    }
}
```

- [ ] **Step 7: Stream from SwiftUI**

In `Sources/Glimmer/Engine/GlimmerText.swift`:
- Add stored properties after `public var markdown: String`:
  ```swift
      public var isStreaming: Bool
      public var revealID: String?
  ```
- Replace the initializer with:
  ```swift
      public init(
          _ markdown: String,
          isStreaming: Bool = false,
          revealID: String? = nil,
          configuration: GlimmerConfiguration = .default,
          onLinkTap: ((URL) -> Void)? = nil
      ) {
          self.markdown = markdown
          self.isStreaming = isStreaming
          self.revealID = revealID
          self.configuration = configuration
          self.onLinkTap = onLinkTap
      }
  ```
- In `updateUIView`, replace `view.update(markdown: markdown)` with `view.update(markdown: markdown, isStreaming: isStreaming, revealID: revealID)`.

- [ ] **Step 8: Run the streaming tests and the Plan 1 view tests**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerViewStreamingTests -only-testing:GlimmerTests/GlimmerViewTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add Sources/Glimmer/Engine/Reveal/GlimmerRevealClock.swift Sources/Glimmer/Engine/Reveal/GlimmerRevealStore.swift Sources/Glimmer/Engine/GlimmerConfiguration.swift Sources/Glimmer/Engine/GlimmerView.swift Sources/Glimmer/Engine/GlimmerText.swift Tests/GlimmerTests/Engine/EngineTestSupport.swift Tests/GlimmerTests/Engine/GlimmerViewStreamingTests.swift
git commit -m "Engine: stream and reveal in GlimmerView and GlimmerText"
```

---

### Task 10: Stream parity and stability suite

**Files:**
- Create: `Tests/GlimmerTests/Engine/StreamingFixtures.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerStreamParityTests.swift`

**Interfaces:**
- Consumes: `GlimmerView` streaming (Task 9), `GlimmerStreamingDocument` (Task 3), and `assertEquivalent` and `ManualRevealClock` (test support).
- Produces: `enum StreamingFixtures { static let all: [(name: String, markdown: String)] }` (test-only).

- [ ] **Step 1: Write the fixtures**

`Tests/GlimmerTests/Engine/StreamingFixtures.swift`:
````swift
/// Realistic answers for streaming tests. No setext headings or link reference definitions: those legitimately
/// restyle earlier text (see the plan's ruling on tail re-parse).
enum StreamingFixtures {
    static let all: [(name: String, markdown: String)] = [
        ("prose", """
        Here is a short answer with **bold words**, some *emphasis*, a `code span`, and a [link](https://example.com/docs). \
        It keeps going for a while so the reveal has several lines to work through.

        A second paragraph follows. It mentions emoji 👋🏽 and a bit of right-to-left text: مرحبا بالعالم. Then it ends.
        """),
        ("lists", """
        ## Steps

        1. Install the package.
        2. Configure the **theme** and the extensions.
        3. Stream the answer:
           - start the request
           - append each chunk
        - [x] Parser done
        - [ ] Reveal tuned
        """),
        ("code-and-table", """
        Use this snippet:

        ```swift
        let view = GlimmerView()
        view.update(markdown: text, isStreaming: true)
        ```

        | Option | Default |
        |:--|--:|
        | fade | 0.6 s |
        | base rate | 60 chars/s |

        That is all.
        """),
        ("quotes-and-headings", """
        # Summary

        > The answer is quoted here with **emphasis**.
        > > And a nested quote.

        ### Details

        Final line after the quotes, with a trailing link to [the spec](https://example.com/spec).
        """),
        ("mixed", """
        Intro sentence before a rule.

        ---

        - item with `inline code`
        - item with ~~strikethrough~~

        Closing paragraph that is long enough to wrap across more than one line on a phone-sized screen width.
        """),
    ]
}
````

- [ ] **Step 2: Write the tests**

`Tests/GlimmerTests/Engine/GlimmerStreamParityTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerStreamParityTests: XCTestCase {
    private let width: CGFloat = 320
    private let configuration = GlimmerConfiguration(imageLoader: nil)

    func testDocumentMatchesAFreshComposeAtEveryPrefix() {
        let composer = GlimmerComposer(theme: .default)
        for fixture in StreamingFixtures.all {
            let document = GlimmerStreamingDocument(composer: composer)
            let characters = Array(fixture.markdown)
            for end in stride(from: 1, through: characters.count, by: 3) {
                let prefix = String(characters[..<end])
                _ = document.update(markdown: prefix, isStreaming: true)
                assertEquivalent(document.text, composer.compose(GlimmerParser.parse(GlimmerTailHealer.heal(prefix))),
                                 "\(fixture.name) prefix \(end)")
            }
            _ = document.update(markdown: fixture.markdown, isStreaming: false)
            assertEquivalent(document.text, composer.compose(GlimmerParser.parse(fixture.markdown)), "\(fixture.name) final")
        }
    }

    func testCommittedBlocksNeverChangeWhileStreaming() {
        let composer = GlimmerComposer(theme: .default)
        for fixture in StreamingFixtures.all {
            let document = GlimmerStreamingDocument(composer: composer)
            let characters = Array(fixture.markdown)
            var lastBlockStart = 0
            for end in stride(from: 1, through: characters.count, by: 2) {
                if let edit = document.update(markdown: String(characters[..<end]), isStreaming: true) {
                    XCTAssertGreaterThanOrEqual(edit.range.location, max(0, lastBlockStart - 1),
                                                "\(fixture.name): a committed block changed at prefix \(end)")
                }
                lastBlockStart = document.blockOffsets.last ?? 0
            }
        }
    }

    func testStreamedViewEndsIdenticalToASettledView() throws {
        for fixture in StreamingFixtures.all {
            let streamed = GlimmerView(configuration: configuration)
            let clock = ManualRevealClock()
            streamed.clock = clock
            let streamedWindow = hostInWindow(streamed, width: width, height: 1400)
            var heights: [CGFloat] = []
            let characters = Array(fixture.markdown)
            var time = 0.0
            for end in stride(from: 1, through: characters.count, by: 25) {
                streamed.update(markdown: String(characters[..<end]), isStreaming: true, revealID: "parity-\(fixture.name)")
                time += 0.05
                clock.advance(to: time)
                heights.append(streamed.intrinsicContentSize.height)
            }
            streamed.update(markdown: fixture.markdown, isStreaming: false, revealID: "parity-\(fixture.name)")
            clock.advance(to: time + 10)
            GlimmerRevealStore.shared.clear("parity-\(fixture.name)")

            XCTAssertEqual(heights, heights.sorted(), "\(fixture.name): the height shrank while streaming")
            XCTAssertNil(streamed.engine, "\(fixture.name): the reveal did not finish")
            XCTAssertNil(streamed.textView.layer.mask)

            let settled = GlimmerView(configuration: configuration)
            let settledWindow = hostInWindow(settled, width: width, height: 1400)
            settled.update(markdown: fixture.markdown)
            assertEquivalent(streamed.textView.textStorage, settled.textView.textStorage, fixture.name)
            let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            XCTAssertEqual(streamed.sizeThatFits(size).height, settled.sizeThatFits(size).height, accuracy: 0.5)

            let height = settled.sizeThatFits(size).height
            streamed.frame.size.height = height
            settled.frame.size.height = height
            settle(streamed)
            settle(settled)
            XCTAssertEqual(snapshot(streamed), snapshot(settled), "\(fixture.name): pixels differ after the reveal")
            _ = streamedWindow
            _ = settledWindow
        }
    }

    private func snapshot(_ view: UIView) -> Data {
        UIGraphicsImageRenderer(bounds: view.bounds).pngData { view.layer.render(in: $0.cgContext) }
    }
}
```

- [ ] **Step 3: Run the suite**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerStreamParityTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`. This task writes tests only; they pass if Tasks 1–9 are correct.
- If a test fails, the bug is in Tasks 1–9. Debug it there (use superpowers:systematic-debugging) and add a focused regression test to that task's test file.
- To prove the suite has teeth, change `composeBlock`'s heading rule back to `output.length > 0` and confirm `testDocumentMatchesAFreshComposeAtEveryPrefix` or the parity test fails. Then revert and ledger the result.

- [ ] **Step 4: Commit**

```bash
git add Tests/GlimmerTests/Engine/StreamingFixtures.swift Tests/GlimmerTests/Engine/GlimmerStreamParityTests.swift
git commit -m "Engine: prove streaming matches a settled render and never moves committed text"
```

---

### Task 11: Streaming lab demo and on-simulator verification

**Files:**
- Create: `Examples/GlimmerDemo/StreamingLabDemo.swift`
- Modify: `Examples/GlimmerDemo/GlimmerDemo.xcodeproj/project.pbxproj` (three entries)
- Modify: `Examples/GlimmerDemo/ContentView.swift`
- Modify: `Examples/GlimmerDemo/GlimmerDemoApp.swift`

**Interfaces:**
- Consumes: `GlimmerText(_:isStreaming:revealID:…)` (Task 9).
- Produces: a "Streaming Lab (2.0)" demo screen, plus the launch argument `--streaming-lab`, which starts the Gemini cadence right away.

- [ ] **Step 1: Write the lab**

`Examples/GlimmerDemo/StreamingLabDemo.swift`:
````swift
import Glimmer
import SwiftUI

/// Streams a canned answer through `GlimmerText` with realistic network cadences, to judge the reveal by eye.
struct StreamingLabDemo: View {
    enum Cadence: String, CaseIterable, Identifiable {
        case gemini = "Gemini"
        case bursty = "Bursty"
        case slow = "Slow"
        var id: String { rawValue }
    }

    @State private var cadence: Cadence = .gemini
    @State private var shown = ""
    @State private var isStreaming = false
    @State private var runID = UUID()
    @State private var task: Task<Void, Never>?

    var body: some View {
        ScrollView {
            GlimmerText(shown, isStreaming: isStreaming, revealID: runID.uuidString)
                .padding(16)
        }
        .navigationTitle("Streaming Lab")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Picker("Cadence", selection: $cadence) {
                    ForEach(Cadence.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Button(isStreaming ? "Stop" : "Stream") { isStreaming ? stop() : start() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("streamingLab.toggle")
            }
            .padding()
            .background(.bar)
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--streaming-lab") { start() }
        }
    }

    private func start() {
        task?.cancel()
        runID = UUID()
        shown = ""
        isStreaming = true
        let chunks = Self.chunks(of: Self.answer, cadence: cadence)
        task = Task { @MainActor in
            for (text, delay) in chunks {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                shown += text
            }
            isStreaming = false
        }
    }

    private func stop() {
        task?.cancel()
        isStreaming = false
    }

    /// The answer split the way a server would send it for `cadence`: each chunk with the delay before it.
    static func chunks(of text: String, cadence: Cadence) -> [(String, Duration)] {
        var generator = SystemRandomNumberGenerator()
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map { String($0) + " " }
        var result: [(String, Duration)] = []
        var index = 0
        while index < words.count {
            let size: Int
            let delay: Duration
            switch cadence {
            case .gemini:
                size = Int.random(in: 3...8, using: &generator)
                delay = .milliseconds(Int.random(in: 70...230, using: &generator))
            case .bursty:
                size = Int.random(in: 20...60, using: &generator)
                delay = .milliseconds(Int.random(in: 400...1200, using: &generator))
            case .slow:
                size = 1
                delay = .milliseconds(150)
            }
            let end = min(words.count, index + size)
            result.append((words[index..<end].joined(), delay))
            index = end
        }
        return result
    }

    static let answer = """
    # Streaming with Glimmer

    Glimmer reveals an answer **phrase by phrase**, fading each one in while the network keeps sending text. \
    Nothing jumps: text is laid out once, in place, and only the newest phrases change opacity.

    ## How it works

    1. The document re-parses only the open tail.
    2. Each update edits the text view in one transaction.
    3. A Core Animation mask fades new phrases in.

    > Fast streams reveal in longer phrases, so the reveal keeps up without flickering.

    ```swift
    view.update(markdown: received, isStreaming: true, revealID: messageID)
    ```

    | Setting | Value |
    |:--|--:|
    | Fade | 0.6 s |
    | Minimum spacing | 60 ms |

    That's the whole idea — the answer ends here.
    """
}
````

- [ ] **Step 2: Register the file and add navigation**

In `Examples/GlimmerDemo/GlimmerDemo.xcodeproj/project.pbxproj`, confirm the IDs are unused (`grep -c "A1F00132\|A1F00133" …` prints `0`). Then add these lines, each directly after the matching `EngineGalleryDemo.swift` line and with the same indentation:
```
		A1F001332E49A00000DEMO01 /* StreamingLabDemo.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1F001322E49A00000DEMO01 /* StreamingLabDemo.swift */; };
```
```
		A1F001322E49A00000DEMO01 /* StreamingLabDemo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StreamingLabDemo.swift; sourceTree = SOURCE_ROOT; };
```
```
				A1F001332E49A00000DEMO01 /* StreamingLabDemo.swift in Sources */,
```
In `Examples/GlimmerDemo/ContentView.swift`, add this line after `NavigationLink("Engine Gallery (2.0)", …)`:
```swift
                    NavigationLink("Streaming Lab (2.0)", destination: StreamingLabDemo())
```
In `Examples/GlimmerDemo/GlimmerDemoApp.swift`, add the first branch of the `WindowGroup`:
```swift
            if ProcessInfo.processInfo.arguments.contains("--streaming-lab") {
                NavigationStack { StreamingLabDemo() }
            } else if ProcessInfo.processInfo.arguments.contains("--engine-gallery") {
```
It replaces the existing `if ProcessInfo.processInfo.arguments.contains("--engine-gallery") {` line; the rest of the chain is unchanged.

- [ ] **Step 3: Record the reveal and check it frame by frame**

```bash
cd /Users/willi/work/Glimmer
xcodebuild -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo -destination "$DEST" -derivedDataPath .build/demo-dd build 2>&1 | tail -2
SIM=$(xcrun simctl list devices available | grep "iPhone 17 Pro Max (" | head -1 | grep -oE "[0-9A-F-]{36}")
xcrun simctl boot "$SIM" 2>/dev/null; xcrun simctl install "$SIM" .build/demo-dd/Build/Products/Debug-iphonesimulator/GlimmerDemo.app
xcrun simctl io "$SIM" recordVideo --codec h264 --force .build/streaming-lab.mp4 & REC=$!
sleep 1; xcrun simctl launch "$SIM" dk.wu.GlimmerDemo --streaming-lab; sleep 12
kill -INT $REC; wait $REC 2>/dev/null; xcrun simctl terminate "$SIM" dk.wu.GlimmerDemo
ffmpeg -v error -y -i .build/streaming-lab.mp4 -vf "fps=6,scale=360:-1,tile=6x3" .build/streaming-lab-%02d.png
```
Expected: `** BUILD SUCCEEDED **` and contact sheets `.build/streaming-lab-01.png` and so on. Open them and check:
1. New phrases appear faint and darken over the next frames: there is a visible opacity trail across several phrases, as in Gemini's recording.
2. Text that is already visible never moves between frames. Lines only grow downward, and the content below the text follows it one line at a time.
3. The code block and table fade in as units, with no raw `**`, backticks or pipes visible mid-stream.
4. The final frame shows the complete answer.

To measure the fade, extract full-rate frames and track the ink of one phrase. The ramp from first ink to plateau should last about 0.6 s (18 frames at 30 fps):
```bash
mkdir -p .build/lab-frames && ffmpeg -v error -y -i .build/streaming-lab.mp4 -vf fps=30 .build/lab-frames/f_%04d.png
python3 - <<'EOF'
import glob
from PIL import Image
# Crop box (x0, y0, x1, y1) around one phrase of the answer's first paragraph, in video pixels; adjust after viewing a frame.
BOX = (40, 420, 600, 460)
def ink(path):
    pixels = list(Image.open(path).crop(BOX).convert("L").getdata())
    background = sorted(pixels)[int(len(pixels) * 0.9)]
    return sum(max(0, background - p) for p in pixels) / len(pixels)
for path in sorted(glob.glob(".build/lab-frames/f_*.png"))[:150]:
    print(path[-8:-4], round(ink(path), 1))
EOF
```
Fix any defect in the owning task, re-run that task's tests, and re-record.

- [ ] **Step 4: Run every engine test class**

Run:
```bash
xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/CMarkLinkTests -only-testing:GlimmerTests/GlimmerParserTests -only-testing:GlimmerTests/GlimmerConformanceTests -only-testing:GlimmerTests/GlimmerThemeTests -only-testing:GlimmerTests/GlimmerCodeBlockViewTests -only-testing:GlimmerTests/GlimmerTableViewTests -only-testing:GlimmerTests/GlimmerImageEmbedViewTests -only-testing:GlimmerTests/GlimmerTextViewTests -only-testing:GlimmerTests/GlimmerComposerTests -only-testing:GlimmerTests/GlimmerLayoutFragmentTests -only-testing:GlimmerTests/GlimmerExtensionTests -only-testing:GlimmerTests/GlimmerViewTests -only-testing:GlimmerTests/GlimmerComposerBlockTests -only-testing:GlimmerTests/GlimmerTailHealerTests -only-testing:GlimmerTests/GlimmerStreamingDocumentTests -only-testing:GlimmerTests/GlimmerTextViewEditTests -only-testing:GlimmerTests/GlimmerPhraseChunkerTests -only-testing:GlimmerTests/GlimmerPacingTests -only-testing:GlimmerTests/GlimmerRevealEngineTests -only-testing:GlimmerTests/GlimmerRevealMaskTests -only-testing:GlimmerTests/GlimmerViewStreamingTests -only-testing:GlimmerTests/GlimmerStreamParityTests 2>&1 | grep -E "Executed [0-9]+ tests|TEST" | tail -2
```
Expected: `Executed N tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Examples/GlimmerDemo
git commit -m "Demo: add the Glimmer 2.0 streaming lab"
```
