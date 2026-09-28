# Glimmer 2.0 — Plan 1: Foundation (parse → compose → TextKit 2 render) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render any CommonMark/GFM markdown natively in one TextKit 2 `UITextView`. The parser is vendored cmark-gfm, code blocks, tables, images and rules are embedded views, inline-code pills and quote bars are custom layout-fragment decorations, extensions can add inline chips, and a public `GlimmerView`/`GlimmerText` API sits on top. It is proven in a demo gallery.

**Architecture:** `GlimmerParser` wraps vendored cmark-gfm and produces an immutable `GlimmerBlock` tree. `GlimmerComposer` turns that tree into one `NSAttributedString` per document. Prose becomes styled text. Embeds become `GlimmerBlockAttachment`s whose `NSTextAttachmentViewProvider` hosts `GlimmerEmbedView`s at full width. `GlimmerTextView` is a non-scrolling TextKit 2 `UITextView`, and its layout-manager delegate returns `GlimmerLayoutFragment`s that draw decorations without moving glyphs.

**Tech Stack:** Swift 6 (tools 6.0), iOS 18+, UIKit, TextKit 2 (`NSTextLayoutManager`, `NSTextAttachmentViewProvider`, `NSTextLayoutFragment`), SwiftUI (`UIViewRepresentable` wrapper), vendored cmark-gfm 0.29.0.gfm.13 (C), XCTest.

**Spec:** `docs/superpowers/specs/2026-09-25-glimmer-2-engine-design.md`

**Roadmap (separate plans, written after this one lands):**
- **Plan 2, streaming and reveal (spec §4.1 streaming document, tail healing, §4.2 `DocumentEdit`, §4.3 editing transactions, §5):**
  streaming document and tail healing, append-only edits, the pacing clock, the phrase chunker, the Core Animation mask,
  the revealed-height rule, `GlimmerRevealState`, Reduce Motion, and stream-versus-settled parity and stability tests.
- **Plan 3, interaction, performance and cleanup (spec §6, §3, §10, §11):**
  selection clamping, copy as markdown, `markdownSource(for:)`, data detectors, the edit menu, VoiceOver, height and
  document caches, the on-device performance harness, deleting all 1.x code, the README, and tagging `2.0.0`.

## Global Constraints

- The branch is `glimmer-2` in `/Users/willi/work/Glimmer`. Commit after every task. **Do not add `Co-Authored-By` trailers**; that is the repository owner's standing preference.
- `Package.swift` keeps `// swift-tools-version: 6.0` and `platforms: [.iOS(.v18)]`. The package takes no dependencies. cmark-gfm is **vendored** from `swiftlang/swift-cmark` branch `gfm` at commit `0c8947bbd58c491c54aae114aca40621cddc8357` (`CMARK_GFM_VERSION_STRING "0.29.0.gfm.13"`), and its `COPYING` licence file is kept.
- All new engine code lives under `Sources/Glimmer/Engine/`. **Do not modify or delete 1.x sources in this plan.** Plan 3 deletes them. New type names are prefixed `Glimmer` and must not collide with 1.x names; 1.x already defines `Glimmer`, `GlimmerAttributes`, `GlimmerRevealView`, `GlimmerRevealViewController` and `GlimmerTrailTextView`.
- **TextKit 2 only.** Never read `layoutManager` on any Glimmer text view, because that silently switches it to TextKit 1. Use `textLayoutManager`.
- No force unwrapping (`!`) and no force casts (`as!`) in library code. `fatalError` is allowed only in `required init?(coder:)`.
- UIKit types are `@MainActor`. `GlimmerBlock`/`GlimmerInline` are `Sendable` value types. `NSAttributedString` is **not** `Sendable` in this SDK, so `GlimmerEmbed` and `GlimmerComposer` are main-actor-only in Plan 1.
- Tests use XCTest. Test classes that touch UIKit are marked `@MainActor`.
- Test and build commands use a fixed simulator, because a plain `name=iPhone 17 Pro` is ambiguous on this Mac:
  ```bash
  DEST='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0'
  xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/<TestClass> 2>&1 | tail -5
  ```
  A passing run ends with `** TEST SUCCEEDED **`, and a failing one with `** TEST FAILED **` plus the failing assertions above it.

## Review Focus

These are the five inputs the spec implies but no task's main tests exercise, ordered from most likely to bite a real user down. Each has a test in the task that owns the code.

1. **Empty or whitespace-only markdown** (an answer whose first token hasn't arrived) → no blocks, an empty string, and zero height, with no crash. Tests: Task 2 `testEmptyInputHasNoBlocks`, Task 9 `testEmptyMarkdownComposesToEmptyString`, Task 12 `testEmptyMarkdownHasZeroHeight`.
2. **Emoji, RTL and combining characters** → attribute ranges stay aligned to the right text (UTF-16 `NSRange` throughout). Test: Task 9 `testEmojiAndRTLKeepAttributeRanges`.
3. **Very long unbreakable tokens** (URLs, minified code, a wide table cell) → prose wraps inside the width, code scrolls horizontally, and a table column is capped and wraps. Tests: Task 5 `testCodeBlockHeightIgnoresWidthAndLongLinesScroll`, Task 6 `testLongUnbreakableCellWrapsWithinMaxColumnWidth`, Task 12 `testLongURLStaysWithinWidth`.
4. **Width changes** (rotation, split view) → embeds resize to the new width and height is recomputed. Test: Task 8 `testEmbedsResizeWhenWidthChanges`.
5. **Nested containers** (a quote containing a list containing code) → correct structure and indents, with no crash. Tests: Task 2 `testQuoteContainingListContainingCode`, Task 9 `testQuoteListCodeNestingIndents`.

---

## File Structure

```
Package.swift                                           (modify: C targets, test resources)
Sources/cmark-gfm/…                                     (vendored C, src/)
Sources/cmark-gfm/VENDORED.md                           (provenance)
Sources/cmark-gfm-extensions/…                          (vendored C, extensions/)
Sources/Glimmer/Engine/
  Parse/GlimmerNode.swift                               block/inline tree (Sendable values)
  Parse/GlimmerParser.swift                             cmark-gfm → GlimmerBlock
  Theme/GlimmerTheme.swift                              fonts, colors, spacing; Dynamic Type scaling
  Theme/GlimmerAttributeKeys.swift                      custom NSAttributedString keys
  Highlight/GlimmerHighlighter.swift                    protocol + span
  Highlight/GlimmerBasicHighlighter.swift               regex tokenizer for common languages
  Embeds/GlimmerEmbedView.swift                         protocol: height(forWidth:)
  Embeds/GlimmerRuleView.swift                          thematic break
  Embeds/GlimmerCodeBlockView.swift                     header + copy + horizontally scrolling code
  Embeds/GlimmerTableView.swift                         scrolling grid with cached column layout
  Embeds/GlimmerImageLoader.swift                       loader protocol + URLSession default
  Embeds/GlimmerImageEmbedView.swift                    reserved-size image with alt fallback
  Embeds/GlimmerEmbed.swift                             embed payload enum
  Embeds/GlimmerBlockAttachment.swift                   NSTextAttachment + view provider + factory
  Render/GlimmerTextView.swift                          TextKit 2 UITextView subclass
  Render/GlimmerLayoutFragment.swift                    pill + quote-bar decorations and delegate
  Compose/GlimmerComposer.swift                         blocks → NSAttributedString
  Compose/GlimmerComposer+Inlines.swift                 inline styling + extension token scanning
  Extensions/GlimmerExtension.swift                     extension protocol + token
  Extensions/GlimmerInlineAttachment.swift              inline chip attachment + provider
  GlimmerConfiguration.swift                            public configuration
  GlimmerView.swift                                     public UIKit view
  GlimmerText.swift                                     public SwiftUI wrapper
Tests/GlimmerTests/Engine/
  EngineTestSupport.swift                               window hosting, subview search, waits, fragments
  CMarkLinkTests.swift
  GlimmerParserTests.swift
  GlimmerConformanceTests.swift  + SpecExamples.swift
  GlimmerThemeTests.swift
  GlimmerCodeBlockViewTests.swift
  GlimmerTableViewTests.swift
  GlimmerImageEmbedViewTests.swift
  GlimmerTextViewTests.swift
  GlimmerComposerTests.swift
  GlimmerLayoutFragmentTests.swift
  GlimmerExtensionTests.swift
  GlimmerViewTests.swift
Tests/GlimmerTests/Fixtures/CommonMark/spec.txt, extensions.txt
Examples/GlimmerDemo/EngineGalleryDemo.swift            (+ pbxproj, ContentView, GlimmerDemoApp)
```

---

### Task 1: Vendor cmark-gfm as C targets

**Files:**
- Create: `Sources/cmark-gfm/**` (copied from upstream `src/`), `Sources/cmark-gfm/VENDORED.md`
- Create: `Sources/cmark-gfm-extensions/**` (copied from upstream `extensions/`)
- Modify: `Package.swift`
- Test: `Tests/GlimmerTests/Engine/CMarkLinkTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: Clang modules `cmark_gfm` and `cmark_gfm_extensions`, importable from the `Glimmer` target and the test target. The C API used later includes `cmark_parser_new`, `cmark_parser_attach_syntax_extension`, `cmark_find_syntax_extension`, `cmark_parser_feed`, `cmark_parser_finish`, `cmark_parser_free`, `cmark_node_free`, `cmark_node_first_child`, `cmark_node_next`, `cmark_node_get_type`, `cmark_node_get_type_string`, `cmark_node_get_literal`, `cmark_node_get_url`, `cmark_node_get_title`, `cmark_node_get_heading_level`, `cmark_node_get_list_type`, `cmark_node_get_list_start`, `cmark_node_get_list_tight`, `cmark_node_get_fence_info`, `cmark_gfm_core_extensions_ensure_registered`, `cmark_gfm_extensions_get_table_columns`, `cmark_gfm_extensions_get_table_alignments` and `cmark_gfm_extensions_get_tasklist_item_checked`.

- [ ] **Step 1: Write the failing test**

`Tests/GlimmerTests/Engine/CMarkLinkTests.swift`:
```swift
import Foundation
import XCTest
import cmark_gfm
import cmark_gfm_extensions

final class CMarkLinkTests: XCTestCase {
    func testCMarkRendersStrongToHTML() throws {
        let markdown = "**hi**"
        let html = try markdown.withCString { pointer -> String in
            let output = try XCTUnwrap(cmark_markdown_to_html(pointer, strlen(pointer), CMARK_OPT_DEFAULT))
            defer { free(output) }
            return String(cString: output)
        }
        XCTAssertEqual(html, "<p><strong>hi</strong></p>\n")
    }

    func testGFMExtensionsRegister() {
        cmark_gfm_core_extensions_ensure_registered()
        for name in ["table", "strikethrough", "autolink", "tasklist"] {
            XCTAssertNotNil(cmark_find_syntax_extension(name), "missing extension \(name)")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/CMarkLinkTests 2>&1 | tail -5`
Expected: a build failure containing `no such module 'cmark_gfm'`.

- [ ] **Step 3: Vendor the sources at the pinned commit**

```bash
cd /Users/willi/work/Glimmer
SRC="$(mktemp -d)/swift-cmark"
git init -q "$SRC"
git -C "$SRC" fetch -q --depth 1 https://github.com/swiftlang/swift-cmark.git 0c8947bbd58c491c54aae114aca40621cddc8357
git -C "$SRC" checkout -q FETCH_HEAD
grep -q '"0.29.0.gfm.13"' "$SRC/src/include/cmark-gfm_version.h" && echo "version ok"
mkdir -p Sources/cmark-gfm Sources/cmark-gfm-extensions
cp -R "$SRC/src/." Sources/cmark-gfm/
cp -R "$SRC/extensions/." Sources/cmark-gfm-extensions/
cp "$SRC/COPYING" Sources/cmark-gfm/COPYING
cp "$SRC/COPYING" Sources/cmark-gfm-extensions/COPYING
ls Sources/cmark-gfm/include/module.modulemap Sources/cmark-gfm-extensions/include/module.modulemap
```
Expected: `version ok`, and both `module.modulemap` paths are printed.

Create `Sources/cmark-gfm/VENDORED.md`:
```markdown
# Vendored cmark-gfm

- Source: https://github.com/swiftlang/swift-cmark (branch `gfm`)
- Commit: 0c8947bbd58c491c54aae114aca40621cddc8357
- Version: 0.29.0.gfm.13
- Copied: `src/` → `Sources/cmark-gfm/`, `extensions/` → `Sources/cmark-gfm-extensions/`, `COPYING` into both.
- Local changes: none. To update, re-run the copy at a new commit and bump this file.
```

- [ ] **Step 4: Declare the targets**

Replace `Package.swift` with:
```swift
// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Glimmer",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "Glimmer",
            targets: ["Glimmer"]),
    ],
    dependencies: [],
    targets: [
        // Vendored from swiftlang/swift-cmark (gfm branch). See Sources/cmark-gfm/VENDORED.md.
        .target(
            name: "cmark-gfm",
            path: "Sources/cmark-gfm",
            exclude: ["scanners.re", "libcmark-gfm.pc.in", "config.h.in", "CMakeLists.txt", "COPYING", "VENDORED.md"]
        ),
        .target(
            name: "cmark-gfm-extensions",
            dependencies: ["cmark-gfm"],
            path: "Sources/cmark-gfm-extensions",
            exclude: ["CMakeLists.txt", "ext_scanners.re", "COPYING"]
        ),
        .target(
            name: "Glimmer",
            dependencies: ["cmark-gfm", "cmark-gfm-extensions"],
            resources: [
                // Emoji URL map for optional lazy loading (1.x; removed in Plan 3)
                .process("Resources/emoji_urls.json")
            ]
        ),
        .testTarget(
            name: "GlimmerTests",
            dependencies: ["Glimmer", "cmark-gfm", "cmark-gfm-extensions"]
        ),
    ]
)
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/CMarkLinkTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`. If SwiftPM warns about unhandled files, add them to that target's `exclude` list and re-run. Do not edit the vendored C.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/cmark-gfm Sources/cmark-gfm-extensions Tests/GlimmerTests/Engine/CMarkLinkTests.swift
git commit -m "Vendor cmark-gfm 0.29.0.gfm.13 as C targets"
```

---

### Task 2: Block tree and parser wrapper

**Files:**
- Create: `Sources/Glimmer/Engine/Parse/GlimmerNode.swift`
- Create: `Sources/Glimmer/Engine/Parse/GlimmerParser.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerParserTests.swift`

**Interfaces:**
- Consumes: the cmark C API (Task 1).
- Produces:
  - `public enum GlimmerBlock: Equatable, Sendable`, with cases `paragraph([GlimmerInline])`, `heading(level: Int, [GlimmerInline])`, `blockQuote([GlimmerBlock])`, `list(GlimmerList)`, `codeBlock(language: String?, code: String)`, `table(GlimmerTable)`, `thematicBreak` and `htmlBlock(String)`.
  - `public struct GlimmerList` with `kind: Kind` (`.bullet` or `.ordered(start: Int)`), `isTight: Bool` and `items: [GlimmerListItem]`.
  - `public struct GlimmerListItem` with `checkbox: Bool?` and `blocks: [GlimmerBlock]`.
  - `public struct GlimmerTable` with `alignments: [Alignment]` (`.none`, `.left`, `.center` or `.right`), `header: [[GlimmerInline]]` and `rows: [[[GlimmerInline]]]`.
  - `public indirect enum GlimmerInline: Equatable, Sendable`, with cases `text(String)`, `code(String)`, `emphasis([GlimmerInline])`, `strong([GlimmerInline])`, `strikethrough([GlimmerInline])`, `link(destination: String, title: String?, [GlimmerInline])`, `image(source: String, title: String?, alt: String)`, `softBreak`, `lineBreak` and `html(String)`.
  - `public static func GlimmerInline.plainText(_ inlines: [GlimmerInline]) -> String`.
  - `public enum GlimmerParser { public static func parse(_ markdown: String) -> [GlimmerBlock] }`. Adjacent text nodes are merged, so one `.text` holds a whole run of plain text.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerParserTests.swift`:
```swift
import XCTest
@testable import Glimmer

final class GlimmerParserTests: XCTestCase {
    func testParagraphWithInlineStyles() {
        XCTAssertEqual(
            GlimmerParser.parse("Hello **bold** *em* `code` ~~gone~~"),
            [.paragraph([
                .text("Hello "), .strong([.text("bold")]), .text(" "),
                .emphasis([.text("em")]), .text(" "), .code("code"), .text(" "),
                .strikethrough([.text("gone")]),
            ])]
        )
    }

    func testHeadingLevels() {
        XCTAssertEqual(
            GlimmerParser.parse("# One\n###### Six"),
            [.heading(level: 1, [.text("One")]), .heading(level: 6, [.text("Six")])]
        )
    }

    func testStrongInsideLinkParsesAsNestedStrong() {
        // Glimmer 1.x leaked the raw `**` here.
        XCTAssertEqual(
            GlimmerParser.parse("[**Ada**](https://superme.ai/u/1)"),
            [.paragraph([.link(destination: "https://superme.ai/u/1", title: nil, [.strong([.text("Ada")])])])]
        )
    }

    func testLooseOrderedListKeepsNumbering() {
        // Glimmer 1.x numbered every loose item "1.".
        guard case .list(let list)? = GlimmerParser.parse("1. one\n\n2. two\n\n3. three").first else {
            return XCTFail("expected a list")
        }
        XCTAssertEqual(list.kind, .ordered(start: 1))
        XCTAssertFalse(list.isTight)
        XCTAssertEqual(list.items.count, 3)
    }

    func testTaskListCheckboxes() {
        guard case .list(let list)? = GlimmerParser.parse("- [x] done\n- [ ] todo\n- plain").first else {
            return XCTFail("expected a list")
        }
        XCTAssertEqual(list.items.map(\.checkbox), [true, false, nil])
        XCTAssertEqual(list.items[0].blocks, [.paragraph([.text("done")])])
    }

    func testFencedCodeKeepsLanguageAndDropsTrailingNewline() {
        XCTAssertEqual(
            GlimmerParser.parse("```swift title=x\nlet x = 1\n```"),
            [.codeBlock(language: "swift", code: "let x = 1")]
        )
        XCTAssertEqual(GlimmerParser.parse("    indented"), [.codeBlock(language: nil, code: "indented")])
    }

    func testTableWithAlignments() {
        XCTAssertEqual(
            GlimmerParser.parse("| a | b |\n|:--|--:|\n| 1 | 2 |"),
            [.table(GlimmerTable(
                alignments: [.left, .right],
                header: [[.text("a")], [.text("b")]],
                rows: [[[.text("1")], [.text("2")]]]
            ))]
        )
    }

    func testBareURLAutolinks() {
        XCTAssertEqual(
            GlimmerParser.parse("Visit https://example.com today"),
            [.paragraph([
                .text("Visit "),
                .link(destination: "https://example.com", title: nil, [.text("https://example.com")]),
                .text(" today"),
            ])]
        )
    }

    func testImageAltTitleAndBreaks() {
        XCTAssertEqual(
            GlimmerParser.parse("![Alt *text*](https://x.y/a.png \"T\")"),
            [.paragraph([.image(source: "https://x.y/a.png", title: "T", alt: "Alt text")])]
        )
        XCTAssertEqual(GlimmerParser.parse("a  \nb"), [.paragraph([.text("a"), .lineBreak, .text("b")])])
        XCTAssertEqual(GlimmerParser.parse("a\nb"), [.paragraph([.text("a"), .softBreak, .text("b")])])
    }

    func testRawHTMLIsKept() {
        XCTAssertEqual(
            GlimmerParser.parse("a <b>x</b>"),
            [.paragraph([.text("a "), .html("<b>"), .text("x"), .html("</b>")])]
        )
    }

    func testBracketedTextStaysOneTextRun() {
        // Extensions scan whole text runs, so cmark's split text nodes must be merged.
        XCTAssertEqual(GlimmerParser.parse("See [3] now"), [.paragraph([.text("See [3] now")])])
    }

    func testEmptyInputHasNoBlocks() {
        XCTAssertEqual(GlimmerParser.parse(""), [])
        XCTAssertEqual(GlimmerParser.parse("   \n\n  "), [])
    }

    func testQuoteContainingListContainingCode() {
        let blocks = GlimmerParser.parse("> 1. step\n>    ```swift\n>    let x = 1\n>    ```")
        guard case .blockQuote(let quoted)? = blocks.first,
              case .list(let list)? = quoted.first else {
            return XCTFail("expected quote > list, got \(blocks)")
        }
        XCTAssertEqual(list.kind, .ordered(start: 1))
        XCTAssertEqual(list.items.first?.blocks, [
            .paragraph([.text("step")]),
            .codeBlock(language: "swift", code: "let x = 1"),
        ])
    }

    func testPlainTextFlattensMarkup() {
        let inlines: [GlimmerInline] = [.text("a "), .strong([.text("b")]), .softBreak, .code("c"), .image(source: "u", title: nil, alt: "d")]
        XCTAssertEqual(GlimmerInline.plainText(inlines), "a b cd")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerParserTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerParser' in scope`.

- [ ] **Step 3: Write the node types**

`Sources/Glimmer/Engine/Parse/GlimmerNode.swift`:
```swift
import Foundation

/// A block-level markdown element. Produced by `GlimmerParser`, consumed by `GlimmerComposer`.
public enum GlimmerBlock: Equatable, Sendable {
    case paragraph([GlimmerInline])
    case heading(level: Int, [GlimmerInline])
    case blockQuote([GlimmerBlock])
    case list(GlimmerList)
    case codeBlock(language: String?, code: String)
    case table(GlimmerTable)
    case thematicBreak
    case htmlBlock(String)
}

public struct GlimmerList: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bullet
        case ordered(start: Int)
    }

    public var kind: Kind
    public var isTight: Bool
    public var items: [GlimmerListItem]

    public init(kind: Kind, isTight: Bool, items: [GlimmerListItem]) {
        self.kind = kind
        self.isTight = isTight
        self.items = items
    }
}

public struct GlimmerListItem: Equatable, Sendable {
    /// `nil` for a plain item; `true`/`false` for a checked/unchecked task item.
    public var checkbox: Bool?
    public var blocks: [GlimmerBlock]

    public init(checkbox: Bool? = nil, blocks: [GlimmerBlock]) {
        self.checkbox = checkbox
        self.blocks = blocks
    }
}

public struct GlimmerTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable {
        case none, left, center, right
    }

    public var alignments: [Alignment]
    public var header: [[GlimmerInline]]
    public var rows: [[[GlimmerInline]]]

    public init(alignments: [Alignment], header: [[GlimmerInline]], rows: [[[GlimmerInline]]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }
}

/// An inline markdown element.
public indirect enum GlimmerInline: Equatable, Sendable {
    case text(String)
    case code(String)
    case emphasis([GlimmerInline])
    case strong([GlimmerInline])
    case strikethrough([GlimmerInline])
    case link(destination: String, title: String?, [GlimmerInline])
    case image(source: String, title: String?, alt: String)
    case softBreak
    case lineBreak
    case html(String)
}

extension GlimmerInline {
    /// The visible text of a run of inlines with markup removed. Breaks become spaces.
    public static func plainText(_ inlines: [GlimmerInline]) -> String {
        inlines.map { inline in
            switch inline {
            case .text(let text), .code(let text), .html(let text):
                text
            case .emphasis(let children), .strong(let children), .strikethrough(let children), .link(_, _, let children):
                plainText(children)
            case .image(_, _, let alt):
                alt
            case .softBreak, .lineBreak:
                " "
            }
        }.joined()
    }
}
```

- [ ] **Step 4: Write the parser**

`Sources/Glimmer/Engine/Parse/GlimmerParser.swift`:
```swift
import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Parses CommonMark plus GFM tables, strikethrough, autolinks and task lists into Glimmer's block tree.
public enum GlimmerParser {
    private typealias Node = UnsafeMutablePointer<cmark_node>

    private static let extensionNames = ["table", "strikethrough", "autolink", "tasklist"]
    private static let registration: Void = cmark_gfm_core_extensions_ensure_registered()

    public static func parse(_ markdown: String) -> [GlimmerBlock] {
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
        return blocks(in: document)
    }

    // MARK: - Blocks

    private static func blocks(in node: Node) -> [GlimmerBlock] {
        children(of: node).compactMap(block)
    }

    private static func block(_ node: Node) -> GlimmerBlock? {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_PARAGRAPH:
            return .paragraph(inlines(in: node))
        case CMARK_NODE_HEADING:
            return .heading(level: Int(cmark_node_get_heading_level(node)), inlines(in: node))
        case CMARK_NODE_BLOCK_QUOTE:
            return .blockQuote(blocks(in: node))
        case CMARK_NODE_LIST:
            return .list(list(node))
        case CMARK_NODE_CODE_BLOCK:
            return .codeBlock(language: language(node), code: codeLiteral(node))
        case CMARK_NODE_HTML_BLOCK:
            return .htmlBlock(string(cmark_node_get_literal(node)))
        case CMARK_NODE_THEMATIC_BREAK:
            return .thematicBreak
        default:
            return typeString(node) == "table" ? .table(table(node)) : nil
        }
    }

    private static func list(_ node: Node) -> GlimmerList {
        let kind: GlimmerList.Kind = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
            ? .ordered(start: Int(cmark_node_get_list_start(node)))
            : .bullet
        let items = children(of: node).map { item in
            GlimmerListItem(
                checkbox: typeString(item) == "tasklist" ? cmark_gfm_extensions_get_tasklist_item_checked(item) : nil,
                blocks: blocks(in: item)
            )
        }
        return GlimmerList(kind: kind, isTight: cmark_node_get_list_tight(node) != 0, items: items)
    }

    private static func table(_ node: Node) -> GlimmerTable {
        let columns = Int(cmark_gfm_extensions_get_table_columns(node))
        let rawAlignments = cmark_gfm_extensions_get_table_alignments(node)
        let alignments: [GlimmerTable.Alignment] = (0..<columns).map { index in
            let raw = rawAlignments.map { $0[index] } ?? 0
            switch raw {
            case UInt8(ascii: "l"): return .left
            case UInt8(ascii: "c"): return .center
            case UInt8(ascii: "r"): return .right
            default: return .none
            }
        }
        var header: [[GlimmerInline]] = []
        var rows: [[[GlimmerInline]]] = []
        for row in children(of: node) {
            let cells = children(of: row).map { inlines(in: $0) }
            if typeString(row) == "table_header" {
                header = cells
            } else {
                rows.append(cells)
            }
        }
        return GlimmerTable(alignments: alignments, header: header, rows: rows)
    }

    private static func language(_ node: Node) -> String? {
        let info = string(cmark_node_get_fence_info(node)).trimmingCharacters(in: .whitespaces)
        guard let word = info.split(separator: " ").first, !word.isEmpty else { return nil }
        return String(word)
    }

    private static func codeLiteral(_ node: Node) -> String {
        var code = string(cmark_node_get_literal(node))
        if code.hasSuffix("\n") { code.removeLast() }
        return code
    }

    // MARK: - Inlines

    private static func inlines(in node: Node) -> [GlimmerInline] {
        var result: [GlimmerInline] = []
        for child in children(of: node) {
            guard let inline = inline(child) else { continue }
            if case .text(let next) = inline, case .text(let previous)? = result.last {
                result[result.count - 1] = .text(previous + next)
            } else {
                result.append(inline)
            }
        }
        return result
    }

    private static func inline(_ node: Node) -> GlimmerInline? {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_TEXT:
            return .text(string(cmark_node_get_literal(node)))
        case CMARK_NODE_CODE:
            return .code(string(cmark_node_get_literal(node)))
        case CMARK_NODE_EMPH:
            return .emphasis(inlines(in: node))
        case CMARK_NODE_STRONG:
            return .strong(inlines(in: node))
        case CMARK_NODE_SOFTBREAK:
            return .softBreak
        case CMARK_NODE_LINEBREAK:
            return .lineBreak
        case CMARK_NODE_HTML_INLINE:
            return .html(string(cmark_node_get_literal(node)))
        case CMARK_NODE_LINK:
            return .link(
                destination: string(cmark_node_get_url(node)),
                title: nonEmpty(cmark_node_get_title(node)),
                inlines(in: node)
            )
        case CMARK_NODE_IMAGE:
            return .image(
                source: string(cmark_node_get_url(node)),
                title: nonEmpty(cmark_node_get_title(node)),
                alt: GlimmerInline.plainText(inlines(in: node))
            )
        default:
            return typeString(node) == "strikethrough" ? .strikethrough(inlines(in: node)) : nil
        }
    }

    // MARK: - Helpers

    private static func children(of node: Node) -> [Node] {
        var result: [Node] = []
        var child = cmark_node_first_child(node)
        while let current = child {
            result.append(current)
            child = cmark_node_next(current)
        }
        return result
    }

    private static func typeString(_ node: Node) -> String {
        string(cmark_node_get_type_string(node))
    }

    private static func string(_ raw: UnsafePointer<CChar>?) -> String {
        raw.map { String(cString: $0) } ?? ""
    }

    private static func nonEmpty(_ raw: UnsafePointer<CChar>?) -> String? {
        let value = string(raw)
        return value.isEmpty ? nil : value
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerParserTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Glimmer/Engine/Parse Tests/GlimmerTests/Engine/GlimmerParserTests.swift
git commit -m "Engine: parse markdown with cmark-gfm into a Sendable block tree"
```

---

### Task 3: CommonMark and GFM conformance harness

**Files:**
- Create: `Tests/GlimmerTests/Fixtures/CommonMark/spec.txt`, `Tests/GlimmerTests/Fixtures/CommonMark/extensions.txt` (copied from the vendored commit's `test/`)
- Create: `Tests/GlimmerTests/Engine/SpecExamples.swift`
- Modify: `Package.swift` (test target resources)
- Test: `Tests/GlimmerTests/Engine/GlimmerConformanceTests.swift`

**Interfaces:**
- Consumes: `GlimmerParser.parse(_:)`, `GlimmerBlock` and `GlimmerInline` (Task 2).
- Produces: `struct SpecExample { file: String; number: Int; markdown: String; html: String }` and `enum SpecExamples { static func load(_ name: String) throws -> [SpecExample] }` (test-only).

- [ ] **Step 1: Copy the fixtures and declare them as test resources**

```bash
cd /Users/willi/work/Glimmer
SRC="$(mktemp -d)/swift-cmark"
git init -q "$SRC"
git -C "$SRC" fetch -q --depth 1 https://github.com/swiftlang/swift-cmark.git 0c8947bbd58c491c54aae114aca40621cddc8357
git -C "$SRC" checkout -q FETCH_HEAD
mkdir -p Tests/GlimmerTests/Fixtures/CommonMark
cp "$SRC/test/spec.txt" "$SRC/test/extensions.txt" Tests/GlimmerTests/Fixtures/CommonMark/
```
In `Package.swift`, change the test target to:
```swift
        .testTarget(
            name: "GlimmerTests",
            dependencies: ["Glimmer", "cmark-gfm", "cmark-gfm-extensions"],
            resources: [.copy("Fixtures")]
        ),
```

- [ ] **Step 2: Write the loader and the failing tests**

`Tests/GlimmerTests/Engine/SpecExamples.swift`:
```swift
import Foundation
import XCTest

/// One example from a cmark spec file: markdown input and the reference HTML.
struct SpecExample {
    let file: String
    let number: Int
    let markdown: String
    let html: String
}

enum SpecExamples {
    /// Loads `Fixtures/CommonMark/<name>.txt`, which uses the cmark spec format
    /// (32-backtick "example" fences, `.` between markdown and HTML, `→` for tabs).
    static func load(_ name: String) throws -> [SpecExample] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures/CommonMark"),
            "missing fixture \(name).txt"
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        let fence = String(repeating: "`", count: 32)
        var examples: [SpecExample] = []
        var markdown: [String] = []
        var html: [String] = []
        var state = 0 // 0 outside, 1 reading markdown, 2 reading html
        for line in text.components(separatedBy: "\n") {
            switch state {
            case 0 where line.hasPrefix(fence + " example"):
                state = 1
                markdown = []
                html = []
            case 1 where line == ".":
                state = 2
            case 1:
                markdown.append(line)
            case 2 where line == fence:
                examples.append(SpecExample(
                    file: name,
                    number: examples.count + 1,
                    markdown: markdown.joined(separator: "\n").replacingOccurrences(of: "→", with: "\t") + "\n",
                    html: html.joined(separator: "\n")
                ))
                state = 0
            case 2:
                html.append(line)
            default:
                break
            }
        }
        return examples
    }
}
```

`Tests/GlimmerTests/Engine/GlimmerConformanceTests.swift`:
```swift
import XCTest
@testable import Glimmer

final class GlimmerConformanceTests: XCTestCase {
    func testCommonMarkExamplesNeverLoseContent() throws {
        let examples = try SpecExamples.load("spec")
        XCTAssertGreaterThan(examples.count, 600)
        assertNoContentLoss(examples)
    }

    func testGFMExtensionExamplesNeverLoseContent() throws {
        let examples = try SpecExamples.load("extensions")
        XCTAssertGreaterThan(examples.count, 20)
        assertNoContentLoss(examples)
    }

    func testEveryNodeKindIsReachable() throws {
        var kinds = Set<String>()
        for example in try SpecExamples.load("spec") + SpecExamples.load("extensions") {
            for block in GlimmerParser.parse(example.markdown) { collectKinds(block, into: &kinds) }
        }
        let expected: Set<String> = [
            "paragraph", "heading", "blockQuote", "list", "task", "codeBlock", "table", "thematicBreak", "htmlBlock",
            "text", "code", "emphasis", "strong", "strikethrough", "link", "image", "softBreak", "lineBreak", "html",
        ]
        XCTAssertEqual(expected.subtracting(kinds), [], "node kinds never produced")
    }

    // MARK: - Helpers

    /// Whenever cmark's reference HTML has content, the Glimmer tree must too. (The reverse is not asserted:
    /// some fixtures enable options, such as footnotes and tag filtering, that Glimmer leaves off.)
    private func assertNoContentLoss(_ examples: [SpecExample], file: StaticString = #filePath, line: UInt = #line) {
        for example in examples where !example.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            XCTAssertFalse(
                GlimmerParser.parse(example.markdown).isEmpty,
                "\(example.file) example \(example.number) lost content: \(example.markdown.debugDescription)",
                file: file, line: line
            )
        }
    }

    private func collectKinds(_ block: GlimmerBlock, into kinds: inout Set<String>) {
        switch block {
        case .paragraph(let inlines):
            kinds.insert("paragraph"); inlines.forEach { collectKinds($0, into: &kinds) }
        case .heading(_, let inlines):
            kinds.insert("heading"); inlines.forEach { collectKinds($0, into: &kinds) }
        case .blockQuote(let blocks):
            kinds.insert("blockQuote"); blocks.forEach { collectKinds($0, into: &kinds) }
        case .list(let list):
            kinds.insert("list")
            for item in list.items {
                if item.checkbox != nil { kinds.insert("task") }
                item.blocks.forEach { collectKinds($0, into: &kinds) }
            }
        case .codeBlock:
            kinds.insert("codeBlock")
        case .table(let table):
            kinds.insert("table")
            (table.header + table.rows.flatMap { $0 }).forEach { $0.forEach { collectKinds($0, into: &kinds) } }
        case .thematicBreak:
            kinds.insert("thematicBreak")
        case .htmlBlock:
            kinds.insert("htmlBlock")
        }
    }

    private func collectKinds(_ inline: GlimmerInline, into kinds: inout Set<String>) {
        switch inline {
        case .text: kinds.insert("text")
        case .code: kinds.insert("code")
        case .emphasis(let children): kinds.insert("emphasis"); children.forEach { collectKinds($0, into: &kinds) }
        case .strong(let children): kinds.insert("strong"); children.forEach { collectKinds($0, into: &kinds) }
        case .strikethrough(let children): kinds.insert("strikethrough"); children.forEach { collectKinds($0, into: &kinds) }
        case .link(_, _, let children): kinds.insert("link"); children.forEach { collectKinds($0, into: &kinds) }
        case .image: kinds.insert("image")
        case .softBreak: kinds.insert("softBreak")
        case .lineBreak: kinds.insert("lineBreak")
        case .html: kinds.insert("html")
        }
    }
}
```

- [ ] **Step 3: Run the tests**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerConformanceTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`. This task adds no production code, so the tests pass once the fixtures load. If `testEveryNodeKindIsReachable` or a content-loss assertion fails, the parser wrapper from Task 2 has a mapping gap. Fix it in `GlimmerParser.swift` and add a regression case to `GlimmerParserTests`. **Do not** weaken the assertion.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Tests/GlimmerTests/Fixtures Tests/GlimmerTests/Engine/SpecExamples.swift Tests/GlimmerTests/Engine/GlimmerConformanceTests.swift
git commit -m "Engine: run the CommonMark and GFM spec examples through the parser"
```

---

### Task 4: Theme and attribute keys

**Files:**
- Create: `Sources/Glimmer/Engine/Theme/GlimmerTheme.swift`
- Create: `Sources/Glimmer/Engine/Theme/GlimmerAttributeKeys.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerThemeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public struct GlimmerTheme: Sendable`, with these `var`s:
  - fonts: `bodyFont`, `codeFont`, `headingFonts: [UIFont]` (H1…H6), `tableFont`, `tableHeaderFont` and `captionFont`;
  - colors: `textColor`, `secondaryTextColor`, `linkColor`, `inlineCodeBackground`, `codeBlockBackground`, `quoteBarColor`, `tableBorderColor`, `tableHeaderBackground`, `syntaxKeywordColor`, `syntaxStringColor`, `syntaxCommentColor` and `syntaxNumberColor`;
  - spacing and sizing: `lineHeightMultiple`, `paragraphSpacing`, `tightListSpacing`, `blockSpacing`, `listIndent`, `quoteIndent`, `embedPadding`, `embedCornerRadius`, `maxTableColumnWidth`, `imagePlaceholderAspect` and `maxImageHeight`;
  - options: `underlinesLinks` and `showsCodeBlockHeader`.

  It also provides `public static var default: GlimmerTheme`, `public func headingFont(level: Int) -> UIFont` (clamped to 1…6) and `public func scaled(for traits: UITraitCollection) -> GlimmerTheme`. Internal keys: `NSAttributedString.Key.glimmerInlineCode` (Bool), `.glimmerQuoteDepth` (Int), `.glimmerListMarker` (String, the markdown marker) and `.glimmerSource` (String, markdown for copy).

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerThemeTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

final class GlimmerThemeTests: XCTestCase {
    func testDefaultHasSixShrinkingHeadingSizes() {
        let sizes = GlimmerTheme.default.headingFonts.map(\.pointSize)
        XCTAssertEqual(sizes.count, 6)
        XCTAssertEqual(sizes, sizes.sorted(by: >))
    }

    func testHeadingLevelIsClamped() {
        let theme = GlimmerTheme.default
        XCTAssertEqual(theme.headingFont(level: 0), theme.headingFonts[0])
        XCTAssertEqual(theme.headingFont(level: 9), theme.headingFonts[5])
    }

    func testScalingFollowsDynamicType() {
        let theme = GlimmerTheme.default
        let large = theme.scaled(for: UITraitCollection(preferredContentSizeCategory: .large))
        let huge = theme.scaled(for: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
        XCTAssertGreaterThan(huge.bodyFont.pointSize, large.bodyFont.pointSize)
        XCTAssertGreaterThan(huge.codeFont.pointSize, large.codeFont.pointSize)
        XCTAssertGreaterThan(huge.headingFonts[0].pointSize, large.headingFonts[0].pointSize)
    }

    func testColorsAdaptToDarkMode() {
        let color = GlimmerTheme.default.textColor
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotEqual(light, dark)
    }

    func testAttributeKeysAreNamespaced() {
        XCTAssertEqual(NSAttributedString.Key.glimmerInlineCode.rawValue, "glimmer.inlineCode")
        XCTAssertEqual(NSAttributedString.Key.glimmerQuoteDepth.rawValue, "glimmer.quoteDepth")
        XCTAssertEqual(NSAttributedString.Key.glimmerListMarker.rawValue, "glimmer.listMarker")
        XCTAssertEqual(NSAttributedString.Key.glimmerSource.rawValue, "glimmer.source")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerThemeTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerTheme' in scope`.

- [ ] **Step 3: Implement**

`Sources/Glimmer/Engine/Theme/GlimmerTheme.swift`:
```swift
import UIKit

/// Visual styling for rendered markdown.
///
/// Fonts are base (unscaled) fonts; `scaled(for:)` applies Dynamic Type. Colors should be dynamic
/// (`UIColor` with light/dark variants) because Glimmer never re-renders just for an appearance change.
/// Start from `.default` and change what you need.
public struct GlimmerTheme: Sendable {
    public var bodyFont: UIFont
    public var codeFont: UIFont
    /// Heading fonts for levels 1–6 (index 0 is H1).
    public var headingFonts: [UIFont]
    public var tableFont: UIFont
    public var tableHeaderFont: UIFont
    /// Small UI text such as a code block's language label.
    public var captionFont: UIFont

    public var textColor: UIColor
    public var secondaryTextColor: UIColor
    public var linkColor: UIColor
    public var inlineCodeBackground: UIColor
    public var codeBlockBackground: UIColor
    public var quoteBarColor: UIColor
    public var tableBorderColor: UIColor
    public var tableHeaderBackground: UIColor
    public var syntaxKeywordColor: UIColor
    public var syntaxStringColor: UIColor
    public var syntaxCommentColor: UIColor
    public var syntaxNumberColor: UIColor

    public var lineHeightMultiple: CGFloat
    /// Space after a paragraph.
    public var paragraphSpacing: CGFloat
    /// Space after an item in a tight list.
    public var tightListSpacing: CGFloat
    /// Space around headings and embedded blocks.
    public var blockSpacing: CGFloat
    public var listIndent: CGFloat
    public var quoteIndent: CGFloat
    /// Inner padding of code blocks, tables and images.
    public var embedPadding: CGFloat
    public var embedCornerRadius: CGFloat
    public var maxTableColumnWidth: CGFloat
    /// Width ÷ height of the box reserved for an image before it loads.
    public var imagePlaceholderAspect: CGFloat
    public var maxImageHeight: CGFloat

    public var underlinesLinks: Bool
    public var showsCodeBlockHeader: Bool

    public func headingFont(level: Int) -> UIFont {
        headingFonts[min(max(level, 1), headingFonts.count) - 1]
    }

    /// A copy with every font scaled for the traits' content size category.
    public func scaled(for traits: UITraitCollection) -> GlimmerTheme {
        let metrics = UIFontMetrics.default
        func scale(_ font: UIFont) -> UIFont { metrics.scaledFont(for: font, compatibleWith: traits) }
        var copy = self
        copy.bodyFont = scale(bodyFont)
        copy.codeFont = scale(codeFont)
        copy.headingFonts = headingFonts.map(scale)
        copy.tableFont = scale(tableFont)
        copy.tableHeaderFont = scale(tableHeaderFont)
        copy.captionFont = scale(captionFont)
        return copy
    }
}

extension GlimmerTheme {
    /// Apple HIG defaults: system fonts and semantic colors.
    public static var `default`: GlimmerTheme {
        GlimmerTheme(
            bodyFont: .systemFont(ofSize: 17),
            codeFont: .monospacedSystemFont(ofSize: 15, weight: .regular),
            headingFonts: [
                .systemFont(ofSize: 28, weight: .bold),
                .systemFont(ofSize: 22, weight: .bold),
                .systemFont(ofSize: 20, weight: .semibold),
                .systemFont(ofSize: 17, weight: .semibold),
                .systemFont(ofSize: 15, weight: .semibold),
                .systemFont(ofSize: 13, weight: .semibold),
            ],
            tableFont: .systemFont(ofSize: 15),
            tableHeaderFont: .systemFont(ofSize: 15, weight: .semibold),
            captionFont: .systemFont(ofSize: 13, weight: .medium),
            textColor: .label,
            secondaryTextColor: .secondaryLabel,
            linkColor: .link,
            inlineCodeBackground: .tertiarySystemFill,
            codeBlockBackground: .secondarySystemBackground,
            quoteBarColor: .separator,
            tableBorderColor: .separator,
            tableHeaderBackground: .secondarySystemBackground,
            syntaxKeywordColor: .systemPink,
            syntaxStringColor: .systemRed,
            syntaxCommentColor: .secondaryLabel,
            syntaxNumberColor: .systemPurple,
            lineHeightMultiple: 1.2,
            paragraphSpacing: 12,
            tightListSpacing: 4,
            blockSpacing: 16,
            listIndent: 24,
            quoteIndent: 16,
            embedPadding: 12,
            embedCornerRadius: 12,
            maxTableColumnWidth: 260,
            imagePlaceholderAspect: 16.0 / 9.0,
            maxImageHeight: 320,
            underlinesLinks: false,
            showsCodeBlockHeader: true
        )
    }
}
```

`Sources/Glimmer/Engine/Theme/GlimmerAttributeKeys.swift`:
```swift
import Foundation

extension NSAttributedString.Key {
    /// `true` on inline code. `GlimmerLayoutFragment` draws a pill behind it.
    static let glimmerInlineCode = NSAttributedString.Key("glimmer.inlineCode")
    /// Blockquote nesting depth (`Int`) on a whole paragraph. `GlimmerLayoutFragment` draws one bar per level.
    static let glimmerQuoteDepth = NSAttributedString.Key("glimmer.quoteDepth")
    /// The markdown for a list marker (`"- "`, `"3. "`, `"- [x] "`) on the marker text, used by copy.
    static let glimmerListMarker = NSAttributedString.Key("glimmer.listMarker")
    /// Markdown source (`String`) for an attachment or chip, used by copy.
    static let glimmerSource = NSAttributedString.Key("glimmer.source")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerThemeTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Theme Tests/GlimmerTests/Engine/GlimmerThemeTests.swift
git commit -m "Engine: add GlimmerTheme with Dynamic Type scaling and attribute keys"
```

---

### Task 5: Embed protocol, rule view, highlighter, code block view

**Files:**
- Create: `Sources/Glimmer/Engine/Embeds/GlimmerEmbedView.swift`
- Create: `Sources/Glimmer/Engine/Embeds/GlimmerRuleView.swift`
- Create: `Sources/Glimmer/Engine/Highlight/GlimmerHighlighter.swift`
- Create: `Sources/Glimmer/Engine/Highlight/GlimmerBasicHighlighter.swift`
- Create: `Sources/Glimmer/Engine/Embeds/GlimmerCodeBlockView.swift`
- Create: `Tests/GlimmerTests/Engine/EngineTestSupport.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerCodeBlockViewTests.swift`

**Interfaces:**
- Consumes: `GlimmerTheme` (Task 4).
- Produces:
  - `@MainActor protocol GlimmerEmbedView: UIView { func embedHeight(forWidth width: CGFloat) -> CGFloat }`
  - `@MainActor final class GlimmerRuleView: UIView, GlimmerEmbedView`, created with `init(theme: GlimmerTheme)`
  - `public struct GlimmerHighlightSpan: Equatable, Sendable`, with `range: NSRange` and `kind: Kind` (`.keyword`, `.string`, `.comment` or `.number`)
  - `public protocol GlimmerHighlighter: Sendable { func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan] }`
  - `public struct GlimmerBasicHighlighter: GlimmerHighlighter`, created with `public init()`
  - `@MainActor final class GlimmerCodeBlockView: UIView, GlimmerEmbedView`, created with `init(code: String, language: String?, theme: GlimmerTheme, highlighter: any GlimmerHighlighter)`. It exposes `let code`, `let language`, `let textView: UITextView`, `let copyButton: UIButton`, `let languageLabel: UILabel`, `static let headerHeight: CGFloat = 44` and `static func highlightedCode(_:language:theme:highlighter:) -> NSAttributedString`.
  - Test support: `hostInWindow(_:width:height:) -> UIWindow`, `settle(_:)` and `findSubview(_:in:)`.

- [ ] **Step 1: Write the test support file**

`Tests/GlimmerTests/Engine/EngineTestSupport.swift`:
```swift
import UIKit
import XCTest

/// Puts `view` in a visible window at the given size and lets layout finish.
/// Keep the returned window alive for the rest of the test (`let window = …`).
@MainActor
@discardableResult
func hostInWindow(_ view: UIView, width: CGFloat, height: CGFloat) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: max(height, 1)))
    view.frame = CGRect(x: 0, y: 0, width: width, height: height)
    window.addSubview(view)
    window.makeKeyAndVisible()
    settle(view)
    return window
}

/// Lets UIKit and TextKit finish a layout pass, including attachment views that appear a run-loop turn later.
@MainActor
func settle(_ view: UIView) {
    view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    view.layoutIfNeeded()
}

@MainActor
func findSubview<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
    if let match = root as? T { return match }
    for subview in root.subviews {
        if let match = findSubview(type, in: subview) { return match }
    }
    return nil
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerCodeBlockViewTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerCodeBlockViewTests: XCTestCase {
    private let theme = GlimmerTheme.default

    func testRuleViewHeightIsPaddingAroundAHairline() {
        let rule = GlimmerRuleView(theme: theme)
        XCTAssertEqual(rule.embedHeight(forWidth: 300), theme.blockSpacing + 1)
        XCTAssertEqual(rule.embedHeight(forWidth: 900), theme.blockSpacing + 1)
    }

    func testBasicHighlighterFindsSwiftTokens() {
        // "let" is 0..<3, "\"hi\"" is 8..<12, "// note 42" is 13..<23.
        let code = #"let x = "hi" // note 42"#
        let spans = GlimmerBasicHighlighter().highlight(code, language: "swift")
        XCTAssertTrue(spans.contains(GlimmerHighlightSpan(range: NSRange(location: 0, length: 3), kind: .keyword)))
        XCTAssertTrue(spans.contains(GlimmerHighlightSpan(range: NSRange(location: 8, length: 4), kind: .string)))
        XCTAssertTrue(spans.contains(GlimmerHighlightSpan(range: NSRange(location: 13, length: 10), kind: .comment)))
        // The comment is applied last so it wins over the number inside it.
        XCTAssertEqual(spans.last?.kind, .comment)
    }

    func testUnknownLanguageHasNoSpans() {
        XCTAssertEqual(GlimmerBasicHighlighter().highlight("let x = 1", language: "klingon"), [])
        XCTAssertEqual(GlimmerBasicHighlighter().highlight("let x = 1", language: nil), [])
    }

    func testHighlightedCodeColorsKeywords() {
        let text = GlimmerCodeBlockView.highlightedCode("let x = 1", language: "swift", theme: theme, highlighter: GlimmerBasicHighlighter())
        let color = text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, theme.syntaxKeywordColor)
        XCTAssertEqual(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont, theme.codeFont)
    }

    func testCodeBlockHeightIgnoresWidthAndLongLinesScroll() {
        let longLine = "let value = \"" + String(repeating: "x", count: 400) + "\""
        let view = GlimmerCodeBlockView(code: longLine, language: "swift", theme: theme, highlighter: GlimmerBasicHighlighter())
        let height = view.embedHeight(forWidth: 300)
        XCTAssertEqual(height, view.embedHeight(forWidth: 600))
        XCTAssertGreaterThan(height, GlimmerCodeBlockView.headerHeight + theme.embedPadding * 2)

        let window = hostInWindow(view, width: 300, height: height)
        XCTAssertGreaterThan(view.textView.contentSize.width, 300, "long lines scroll instead of wrapping")
        XCTAssertLessThan(view.textView.contentSize.width, 10_000)
        _ = window
    }

    func testCopyButtonCopiesTheCode() {
        let view = GlimmerCodeBlockView(code: "print(1)", language: "python", theme: theme, highlighter: GlimmerBasicHighlighter())
        UIPasteboard.general.string = ""
        view.copyButton.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(UIPasteboard.general.string, "print(1)")
        XCTAssertEqual(view.copyButton.accessibilityLabel, "Copy code")
    }

    func testHeaderShowsLanguage() {
        let view = GlimmerCodeBlockView(code: "x", language: "Swift", theme: theme, highlighter: GlimmerBasicHighlighter())
        XCTAssertEqual(view.languageLabel.text, "swift")
        let plain = GlimmerCodeBlockView(code: "x", language: nil, theme: theme, highlighter: GlimmerBasicHighlighter())
        XCTAssertEqual(plain.languageLabel.text, "code")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerCodeBlockViewTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerRuleView' in scope`.

- [ ] **Step 4: Implement the protocol, rule view and highlighter**

`Sources/Glimmer/Engine/Embeds/GlimmerEmbedView.swift`:
```swift
import UIKit

/// A view that renders one embedded block (code, table, image, rule) inside the text flow.
@MainActor
protocol GlimmerEmbedView: UIView {
    /// The height the view needs at `width`. Called during TextKit layout, so it must be cheap once warmed up.
    func embedHeight(forWidth width: CGFloat) -> CGFloat
}
```

`Sources/Glimmer/Engine/Embeds/GlimmerRuleView.swift`:
```swift
import UIKit

/// A thematic break: a hairline centered in `blockSpacing` of space.
@MainActor
final class GlimmerRuleView: UIView, GlimmerEmbedView {
    private let line = UIView()
    private let spacing: CGFloat

    init(theme: GlimmerTheme) {
        spacing = theme.blockSpacing
        super.init(frame: .zero)
        line.backgroundColor = theme.tableBorderColor
        addSubview(line)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func embedHeight(forWidth width: CGFloat) -> CGFloat { spacing + 1 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let thickness = 1 / max(traitCollection.displayScale, 1)
        line.frame = CGRect(x: 0, y: (bounds.height - thickness) / 2, width: bounds.width, height: thickness)
    }
}
```

`Sources/Glimmer/Engine/Highlight/GlimmerHighlighter.swift`:
```swift
import Foundation

/// A colored range in a code block.
public struct GlimmerHighlightSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case keyword, string, comment, number
    }

    /// UTF-16 range into the highlighted code.
    public var range: NSRange
    public var kind: Kind

    public init(range: NSRange, kind: Kind) {
        self.range = range
        self.kind = kind
    }
}

/// Supplies syntax colors for code blocks. Later spans win where spans overlap.
public protocol GlimmerHighlighter: Sendable {
    func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan]
}
```

`Sources/Glimmer/Engine/Highlight/GlimmerBasicHighlighter.swift`:
```swift
import Foundation

/// A small regex tokenizer for common languages: keywords, numbers, strings, comments.
/// Good enough for chat answers; supply your own `GlimmerHighlighter` for full grammars.
public struct GlimmerBasicHighlighter: GlimmerHighlighter {
    public init() {}

    public func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan] {
        guard let family = Family(language) else { return [] }
        let whole = NSRange(location: 0, length: (code as NSString).length)
        var spans: [GlimmerHighlightSpan] = []
        func collect(_ pattern: String, _ kind: GlimmerHighlightSpan.Kind) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: code, range: whole) {
                spans.append(GlimmerHighlightSpan(range: match.range, kind: kind))
            }
        }
        collect("\\b(?:" + family.keywords.joined(separator: "|") + ")\\b", .keyword)
        collect("\\b\\d+(?:\\.\\d+)?\\b", .number)
        collect(#""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#, .string)
        for pattern in family.commentPatterns { collect(pattern, .comment) }
        return spans
    }
}

extension GlimmerBasicHighlighter {
    struct Family {
        let keywords: [String]
        let commentPatterns: [String]

        private static let lineComment = "//[^\\n]*"
        private static let blockComment = "/\\*[\\s\\S]*?\\*/"
        private static let hashComment = "#[^\\n]*"

        init?(_ language: String?) {
            switch language?.lowercased() {
            case "swift":
                keywords = ["let", "var", "func", "return", "if", "else", "guard", "for", "in", "while", "struct", "class",
                            "enum", "protocol", "extension", "import", "switch", "case", "default", "break", "continue",
                            "true", "false", "nil", "self", "Self", "init", "throws", "throw", "try", "async", "await",
                            "some", "any", "public", "private", "internal", "fileprivate", "static", "where"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "python", "py":
                keywords = ["def", "return", "if", "elif", "else", "for", "in", "while", "class", "import", "from", "as",
                            "with", "try", "except", "finally", "raise", "True", "False", "None", "and", "or", "not",
                            "lambda", "yield", "async", "await", "pass", "break", "continue"]
                commentPatterns = [Self.hashComment]
            case "javascript", "js", "jsx", "typescript", "ts", "tsx":
                keywords = ["const", "let", "var", "function", "return", "if", "else", "for", "of", "in", "while", "class",
                            "import", "from", "export", "default", "new", "this", "true", "false", "null", "undefined",
                            "async", "await", "try", "catch", "finally", "throw", "typeof", "interface", "type",
                            "extends", "implements"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "ruby", "rb":
                keywords = ["def", "end", "return", "if", "elsif", "else", "unless", "for", "in", "while", "class",
                            "module", "require", "do", "true", "false", "nil", "self", "yield", "begin", "rescue", "ensure"]
                commentPatterns = [Self.hashComment]
            case "go", "golang":
                keywords = ["func", "return", "if", "else", "for", "range", "package", "import", "var", "const", "type",
                            "struct", "interface", "map", "chan", "go", "defer", "select", "switch", "case", "default",
                            "true", "false", "nil"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "java", "kotlin", "kt":
                keywords = ["class", "interface", "fun", "val", "var", "public", "private", "protected", "static", "final",
                            "void", "return", "if", "else", "for", "while", "new", "this", "true", "false", "null",
                            "import", "package", "extends", "implements", "when", "object", "override"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "c", "h", "cpp", "c++", "objc", "objective-c":
                keywords = ["int", "char", "float", "double", "void", "return", "if", "else", "for", "while", "struct",
                            "typedef", "enum", "static", "const", "unsigned", "signed", "sizeof", "switch", "case",
                            "default", "break", "continue", "NULL", "true", "false"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "rust", "rs":
                keywords = ["fn", "let", "mut", "return", "if", "else", "for", "in", "while", "loop", "match", "struct",
                            "enum", "impl", "trait", "use", "pub", "mod", "crate", "self", "Self", "true", "false",
                            "None", "Some", "Ok", "Err", "async", "await", "where"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "bash", "sh", "shell", "zsh":
                keywords = ["if", "then", "else", "fi", "for", "in", "do", "done", "while", "case", "esac", "function",
                            "return", "export", "local", "echo"]
                commentPatterns = [Self.hashComment]
            default:
                return nil
            }
        }
    }
}
```

- [ ] **Step 5: Implement the code block view**

`Sources/Glimmer/Engine/Embeds/GlimmerCodeBlockView.swift`:
```swift
import UIKit

/// A fenced code block: a header (language + Copy) above selectable, syntax-colored code that scrolls
/// horizontally instead of wrapping. Its height does not depend on width.
@MainActor
final class GlimmerCodeBlockView: UIView, GlimmerEmbedView {
    static let headerHeight: CGFloat = 44

    let code: String
    let language: String?
    let textView = UITextView(usingTextLayoutManager: true)
    let copyButton = UIButton(type: .system)
    let languageLabel = UILabel()

    private let theme: GlimmerTheme
    private let highlighted: NSAttributedString
    private var cachedTextSize: CGSize?

    init(code: String, language: String?, theme: GlimmerTheme, highlighter: any GlimmerHighlighter) {
        self.code = code
        self.language = language
        self.theme = theme
        highlighted = Self.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
        super.init(frame: .zero)

        backgroundColor = theme.codeBlockBackground
        layer.cornerRadius = theme.embedCornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let padding = theme.embedPadding
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        textView.showsVerticalScrollIndicator = false
        textView.textContainerInset = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(width: textSize.width + 1, height: CGFloat.greatestFiniteMagnitude)
        textView.attributedText = highlighted
        addSubview(textView)

        languageLabel.text = language?.lowercased() ?? "code"
        languageLabel.font = theme.captionFont
        languageLabel.textColor = theme.secondaryTextColor
        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyButton.tintColor = theme.secondaryTextColor
        copyButton.accessibilityLabel = "Copy code"
        copyButton.addAction(UIAction { [weak self] _ in
            UIPasteboard.general.string = self?.code
        }, for: .primaryActionTriggered)
        if theme.showsCodeBlockHeader {
            addSubview(languageLabel)
            addSubview(copyButton)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Unwrapped size of the highlighted code.
    var textSize: CGSize {
        if let cachedTextSize { return cachedTextSize }
        let bounds = highlighted.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let size = CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        cachedTextSize = size
        return size
    }

    func embedHeight(forWidth width: CGFloat) -> CGFloat {
        (theme.showsCodeBlockHeader ? Self.headerHeight : 0) + theme.embedPadding * 2 + textSize.height
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let headerHeight = theme.showsCodeBlockHeader ? Self.headerHeight : 0
        if theme.showsCodeBlockHeader {
            copyButton.frame = CGRect(x: bounds.width - headerHeight, y: 0, width: headerHeight, height: headerHeight)
            languageLabel.frame = CGRect(
                x: theme.embedPadding, y: 0,
                width: max(0, copyButton.frame.minX - theme.embedPadding), height: headerHeight
            )
        }
        textView.frame = CGRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))
    }

    static func highlightedCode(
        _ code: String, language: String?, theme: GlimmerTheme, highlighter: any GlimmerHighlighter
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = theme.lineHeightMultiple
        let result = NSMutableAttributedString(string: code, attributes: [
            .font: theme.codeFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraph,
        ])
        for span in highlighter.highlight(code, language: language) where NSMaxRange(span.range) <= result.length {
            result.addAttribute(.foregroundColor, value: color(for: span.kind, theme: theme), range: span.range)
        }
        return result
    }

    private static func color(for kind: GlimmerHighlightSpan.Kind, theme: GlimmerTheme) -> UIColor {
        switch kind {
        case .keyword: theme.syntaxKeywordColor
        case .string: theme.syntaxStringColor
        case .comment: theme.syntaxCommentColor
        case .number: theme.syntaxNumberColor
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerCodeBlockViewTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Glimmer/Engine/Embeds Sources/Glimmer/Engine/Highlight Tests/GlimmerTests/Engine/EngineTestSupport.swift Tests/GlimmerTests/Engine/GlimmerCodeBlockViewTests.swift
git commit -m "Engine: add rule and code block embeds with a basic highlighter"
```

---

### Task 6: Table view

**Files:**
- Create: `Sources/Glimmer/Engine/Embeds/GlimmerTableView.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerTableViewTests.swift`

**Interfaces:**
- Consumes: `GlimmerEmbedView` and `hostInWindow` (Task 5), `GlimmerTheme` (Task 4), `GlimmerTable.Alignment` (Task 2).
- Produces: `@MainActor final class GlimmerTableView: UIView, GlimmerEmbedView`, created with `init(header: [NSAttributedString], rows: [[NSAttributedString]], alignments: [GlimmerTable.Alignment], theme: GlimmerTheme)`. It provides `struct Layout: Equatable { columnWidths: [CGFloat]; rowHeights: [CGFloat]; contentWidth; height }`, `func layout(forWidth:) -> Layout` (cached per width), `let scrollView: UIScrollView`, `private(set) var cellLabels: [[UILabel]]` (row 0 is the header) and `static let cellPadding: CGFloat = 10`.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerTableViewTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTableViewTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func cell(_ text: String, header: Bool = false) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: header ? theme.tableHeaderFont : theme.tableFont])
    }

    func testShortTableFillsTheWidth() {
        let table = GlimmerTableView(
            header: [cell("a", header: true), cell("b", header: true)],
            rows: [[cell("1"), cell("2")]],
            alignments: [.left, .right],
            theme: theme
        )
        let layout = table.layout(forWidth: 300)
        XCTAssertEqual(layout.contentWidth, 300, accuracy: 0.5)
        XCTAssertEqual(layout.rowHeights.count, 2)
        XCTAssertEqual(table.embedHeight(forWidth: 300), layout.height)

        let window = hostInWindow(table, width: 300, height: layout.height)
        XCTAssertLessThanOrEqual(table.scrollView.contentSize.width, 300.5)
        _ = window
    }

    func testWideTableScrollsHorizontally() {
        let header = (0..<6).map { cell("Column number \($0)", header: true) }
        let row = (0..<6).map { cell("Some longer cell value \($0)") }
        let table = GlimmerTableView(header: header, rows: [row], alignments: Array(repeating: .none, count: 6), theme: theme)
        let layout = table.layout(forWidth: 300)
        XCTAssertGreaterThan(layout.contentWidth, 300)
        let window = hostInWindow(table, width: 300, height: layout.height)
        XCTAssertGreaterThan(table.scrollView.contentSize.width, 300)
        _ = window
    }

    func testLongUnbreakableCellWrapsWithinMaxColumnWidth() {
        let table = GlimmerTableView(
            header: [cell("h", header: true)],
            rows: [[cell(String(repeating: "x", count: 300))]],
            alignments: [.none],
            theme: theme
        )
        let layout = table.layout(forWidth: 300)
        XCTAssertLessThanOrEqual(layout.columnWidths[0], max(theme.maxTableColumnWidth, 300) + 0.5)
        XCTAssertGreaterThan(layout.rowHeights[1], theme.tableFont.lineHeight * 2, "the long cell wraps onto several lines")
    }

    func testAlignmentsMapToLabels() {
        let table = GlimmerTableView(
            header: [cell("a", header: true), cell("b", header: true), cell("c", header: true)],
            rows: [[cell("1"), cell("2"), cell("3")]],
            alignments: [.left, .center, .right],
            theme: theme
        )
        XCTAssertEqual(table.cellLabels[1].map(\.textAlignment), [.left, .center, .right])
    }

    func testRaggedRowsArePadded() {
        let table = GlimmerTableView(
            header: [cell("a", header: true), cell("b", header: true)],
            rows: [[cell("only one")]],
            alignments: [.none, .none],
            theme: theme
        )
        XCTAssertEqual(table.cellLabels[1].count, 2)
    }

    func testLayoutIsCachedPerWidth() {
        let table = GlimmerTableView(header: [cell("a", header: true)], rows: [[cell("1")]], alignments: [.none], theme: theme)
        XCTAssertEqual(table.layout(forWidth: 300), table.layout(forWidth: 300))
        XCTAssertNotEqual(table.layout(forWidth: 300).columnWidths, table.layout(forWidth: 200).columnWidths)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerTableViewTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerTableView' in scope`.

- [ ] **Step 3: Implement**

`Sources/Glimmer/Engine/Embeds/GlimmerTableView.swift`:
```swift
import UIKit

/// A GFM table. Columns size to their content, capped at `maxTableColumnWidth`, and expand to fill the width when
/// the table is narrower than the text. Wider tables scroll horizontally.
@MainActor
final class GlimmerTableView: UIView, GlimmerEmbedView {
    struct Layout: Equatable {
        var columnWidths: [CGFloat]
        var rowHeights: [CGFloat]
        var contentWidth: CGFloat { columnWidths.reduce(0, +) }
        var height: CGFloat { rowHeights.reduce(0, +) }
    }

    static let cellPadding: CGFloat = 10
    private static let minimumColumnWidth: CGFloat = 44

    let scrollView = UIScrollView()
    private(set) var cellLabels: [[UILabel]] = []

    private let content = UIView()
    private let headerBackground = UIView()
    private let grid = CAShapeLayer()
    private let cells: [[NSAttributedString]]
    private let theme: GlimmerTheme
    private var cachedLayout: (width: CGFloat, layout: Layout)?

    init(header: [NSAttributedString], rows: [[NSAttributedString]], alignments: [GlimmerTable.Alignment], theme: GlimmerTheme) {
        self.theme = theme
        let columns = max(header.count, rows.map(\.count).max() ?? 0, alignments.count)
        func padded(_ row: [NSAttributedString]) -> [NSAttributedString] {
            row + Array(repeating: NSAttributedString(), count: max(0, columns - row.count))
        }
        cells = [padded(header)] + rows.map(padded)
        super.init(frame: .zero)

        layer.cornerRadius = theme.embedCornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        clipsToBounds = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        addSubview(scrollView)
        scrollView.addSubview(content)
        headerBackground.backgroundColor = theme.tableHeaderBackground
        content.addSubview(headerBackground)
        grid.fillColor = nil
        grid.lineWidth = 1
        content.layer.addSublayer(grid)

        cellLabels = cells.map { row in
            row.enumerated().map { column, text in
                let label = UILabel()
                label.numberOfLines = 0
                label.attributedText = text
                label.textAlignment = Self.textAlignment(column < alignments.count ? alignments[column] : .none)
                content.addSubview(label)
                return label
            }
        }
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: GlimmerTableView, _: UITraitCollection) in
            view.updateColors()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func embedHeight(forWidth width: CGFloat) -> CGFloat { layout(forWidth: width).height }

    func layout(forWidth width: CGFloat) -> Layout {
        if let cachedLayout, cachedLayout.width == width { return cachedLayout.layout }
        let padding = Self.cellPadding
        let columns = cells.first?.count ?? 0
        let maxColumn = max(theme.maxTableColumnWidth, Self.minimumColumnWidth)
        var natural = Array(repeating: Self.minimumColumnWidth, count: columns)
        for row in cells {
            for (column, text) in row.enumerated() {
                natural[column] = max(natural[column], min(ceil(text.size().width) + padding * 2, maxColumn))
            }
        }
        let total = natural.reduce(0, +)
        let widths = total > 0 && total < width ? natural.map { $0 * width / total } : natural
        let rowHeights = cells.map { row in
            row.enumerated().map { column, text in
                let bounds = text.boundingRect(
                    with: CGSize(width: max(1, widths[column] - padding * 2), height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                return ceil(bounds.height) + padding * 2
            }.max() ?? padding * 2
        }
        let layout = Layout(columnWidths: widths, rowHeights: rowHeights)
        cachedLayout = (width, layout)
        return layout
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = layout(forWidth: bounds.width)
        let padding = Self.cellPadding
        scrollView.frame = bounds
        scrollView.contentSize = CGSize(width: layout.contentWidth, height: layout.height)
        content.frame = CGRect(origin: .zero, size: scrollView.contentSize)
        headerBackground.frame = CGRect(x: 0, y: 0, width: layout.contentWidth, height: layout.rowHeights.first ?? 0)

        let path = UIBezierPath()
        var y: CGFloat = 0
        for (rowIndex, labels) in cellLabels.enumerated() {
            var x: CGFloat = 0
            for (column, label) in labels.enumerated() {
                label.frame = CGRect(
                    x: x + padding, y: y + padding,
                    width: max(0, layout.columnWidths[column] - padding * 2),
                    height: max(0, layout.rowHeights[rowIndex] - padding * 2)
                )
                x += layout.columnWidths[column]
                if column < labels.count - 1 {
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + layout.rowHeights[rowIndex]))
                }
            }
            y += layout.rowHeights[rowIndex]
            if rowIndex < cellLabels.count - 1 {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: layout.contentWidth, y: y))
            }
        }
        grid.path = path.cgPath
    }

    private func updateColors() {
        let border = theme.tableBorderColor.resolvedColor(with: traitCollection).cgColor
        layer.borderColor = border
        grid.strokeColor = border
    }

    private static func textAlignment(_ alignment: GlimmerTable.Alignment) -> NSTextAlignment {
        switch alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case .none: .natural
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerTableViewTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Embeds/GlimmerTableView.swift Tests/GlimmerTests/Engine/GlimmerTableViewTests.swift
git commit -m "Engine: add a horizontally scrolling table embed with cached column layout"
```

---

### Task 7: Image loader and image embed

**Files:**
- Create: `Sources/Glimmer/Engine/Embeds/GlimmerImageLoader.swift`
- Create: `Sources/Glimmer/Engine/Embeds/GlimmerImageEmbedView.swift`
- Modify: `Tests/GlimmerTests/Engine/EngineTestSupport.swift` (add `waitUntil`)
- Test: `Tests/GlimmerTests/Engine/GlimmerImageEmbedViewTests.swift`

**Interfaces:**
- Consumes: `GlimmerEmbedView` (Task 5), `GlimmerTheme` (Task 4).
- Produces:
  - `public protocol GlimmerImageLoader: Sendable { func loadImage(from url: URL) async throws -> UIImage }`
  - `public struct GlimmerURLSessionImageLoader: GlimmerImageLoader`, created with `public init()`
  - `@MainActor final class GlimmerImageEmbedView: UIView, GlimmerEmbedView`, created with `init(source: URL, alt: String, theme: GlimmerTheme, loader: (any GlimmerImageLoader)?)`. It exposes `let imageView: UIImageView` and `let altLabel: UILabel`.
  - Test support: `waitUntil(timeout:_:) async -> Bool`

- [ ] **Step 1: Add the wait helper**

Append to `Tests/GlimmerTests/Engine/EngineTestSupport.swift`:
```swift
/// Polls `condition` until it is true or `timeout` (wall clock) passes.
@MainActor
func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerImageEmbedViewTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

private struct StubImageLoader: GlimmerImageLoader {
    let result: Result<UIImage, URLError>
    func loadImage(from url: URL) async throws -> UIImage { try result.get() }
}

@MainActor
final class GlimmerImageEmbedViewTests: XCTestCase {
    private let theme = GlimmerTheme.default
    private let url = URL(string: "https://example.com/a.png")!  // test-only literal

    private func tallImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 40)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 40))
        }
    }

    func testImageLoadsWithoutChangingHeight() async {
        let view = GlimmerImageEmbedView(source: url, alt: "chart", theme: theme, loader: StubImageLoader(result: .success(tallImage())))
        let before = view.embedHeight(forWidth: 300)
        XCTAssertEqual(before, 300 / theme.imagePlaceholderAspect, accuracy: 0.5)
        let loaded = await waitUntil { view.imageView.image != nil }
        XCTAssertTrue(loaded)
        XCTAssertEqual(view.embedHeight(forWidth: 300), before, "a finished load must not change layout")
        XCTAssertTrue(view.altLabel.isHidden)
    }

    func testFailedLoadShowsAltText() async {
        let view = GlimmerImageEmbedView(source: url, alt: "chart", theme: theme, loader: StubImageLoader(result: .failure(URLError(.badServerResponse))))
        let shown = await waitUntil { !view.altLabel.isHidden }
        XCTAssertTrue(shown)
        XCTAssertEqual(view.altLabel.text, "chart")
        XCTAssertEqual(view.accessibilityLabel, "chart")
    }

    func testNoLoaderShowsAltTextImmediately() {
        let view = GlimmerImageEmbedView(source: url, alt: "chart", theme: theme, loader: nil)
        XCTAssertFalse(view.altLabel.isHidden)
    }

    func testHeightIsCappedByMaxImageHeight() {
        let view = GlimmerImageEmbedView(source: url, alt: "", theme: theme, loader: nil)
        XCTAssertEqual(view.embedHeight(forWidth: 2000), theme.maxImageHeight)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerImageEmbedViewTests 2>&1 | tail -5`
Expected: a build failure, `cannot find type 'GlimmerImageLoader' in scope`.

- [ ] **Step 4: Implement**

`Sources/Glimmer/Engine/Embeds/GlimmerImageLoader.swift`:
```swift
import UIKit

/// Loads images for markdown image embeds. Plug in your app's image cache here.
public protocol GlimmerImageLoader: Sendable {
    func loadImage(from url: URL) async throws -> UIImage
}

/// The default loader: a plain `URLSession.shared` fetch with no caching beyond URLSession's own.
public struct GlimmerURLSessionImageLoader: GlimmerImageLoader {
    public init() {}

    public func loadImage(from url: URL) async throws -> UIImage {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        return image
    }
}
```

`Sources/Glimmer/Engine/Embeds/GlimmerImageEmbedView.swift`:
```swift
import UIKit

/// A standalone markdown image. The box is sized before loading (placeholder aspect, capped height) and never
/// resizes, so a finished load cannot shift the text below it; the image is aspect-fit inside the box.
@MainActor
final class GlimmerImageEmbedView: UIView, GlimmerEmbedView {
    let imageView = UIImageView()
    let altLabel = UILabel()

    private let theme: GlimmerTheme

    init(source: URL, alt: String, theme: GlimmerTheme, loader: (any GlimmerImageLoader)?) {
        self.theme = theme
        super.init(frame: .zero)
        backgroundColor = theme.codeBlockBackground
        layer.cornerRadius = theme.embedCornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = alt

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        altLabel.text = alt
        altLabel.font = theme.captionFont
        altLabel.textColor = theme.secondaryTextColor
        altLabel.textAlignment = .center
        altLabel.numberOfLines = 0
        altLabel.isHidden = true
        addSubview(altLabel)

        guard let loader else {
            altLabel.isHidden = false
            return
        }
        Task { [weak self] in
            do {
                let image = try await loader.loadImage(from: source)
                self?.imageView.image = image
            } catch {
                self?.altLabel.isHidden = false
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func embedHeight(forWidth width: CGFloat) -> CGFloat {
        min(width / theme.imagePlaceholderAspect, theme.maxImageHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        altLabel.frame = bounds.insetBy(dx: theme.embedPadding, dy: theme.embedPadding)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerImageEmbedViewTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Glimmer/Engine/Embeds/GlimmerImageLoader.swift Sources/Glimmer/Engine/Embeds/GlimmerImageEmbedView.swift Tests/GlimmerTests/Engine/EngineTestSupport.swift Tests/GlimmerTests/Engine/GlimmerImageEmbedViewTests.swift
git commit -m "Engine: add a fixed-size image embed with a pluggable loader"
```

---

### Task 8: Block attachments and the TextKit 2 text view

**Files:**
- Create: `Sources/Glimmer/Engine/Embeds/GlimmerEmbed.swift`
- Create: `Sources/Glimmer/Engine/Embeds/GlimmerBlockAttachment.swift`
- Create: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerTextViewTests.swift`

**Interfaces:**
- Consumes: all embed views (Tasks 5–7), `GlimmerTheme`, `GlimmerHighlighter`, `GlimmerImageLoader` and `GlimmerTable.Alignment`.
- Produces:
  - `enum GlimmerEmbed`, with cases `codeBlock(language: String?, code: String)`, `table(header: [NSAttributedString], rows: [[NSAttributedString]], alignments: [GlimmerTable.Alignment])`, `image(source: URL, alt: String)` and `thematicBreak`.
  - `final class GlimmerBlockAttachment: NSTextAttachment`, created with `init(embed: GlimmerEmbed, theme: GlimmerTheme, highlighter: any GlimmerHighlighter, imageLoader: (any GlimmerImageLoader)?)`. It exposes `let embed`, `let theme`, `let highlighter` and `let imageLoader`.
  - `final class GlimmerEmbedViewProvider: NSTextAttachmentViewProvider`, with bounds of full width minus `position.x` and a height from `embedHeight(forWidth:)`.
  - `@MainActor enum GlimmerEmbedViewFactory { static func makeView(for attachment: GlimmerBlockAttachment) -> any GlimmerEmbedView }`.
  - `@MainActor final class GlimmerTextView: UITextView`, created with `init()`. It provides `func apply(theme: GlimmerTheme)`, `private(set) var theme: GlimmerTheme`, a `sizeThatFits(_:)` that returns 0 for empty text or zero width, and an intrinsic height for the current width.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerTextViewTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTextViewTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func attachment(_ embed: GlimmerEmbed) -> NSAttributedString {
        NSAttributedString(attachment: GlimmerBlockAttachment(
            embed: embed, theme: theme, highlighter: GlimmerBasicHighlighter(), imageLoader: nil
        ))
    }

    private func document(_ parts: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(part)
        }
        result.addAttribute(.font, value: theme.bodyFont, range: NSRange(location: 0, length: result.length))
        return result
    }

    func testStaysOnTextKit2() {
        let textView = GlimmerTextView()
        textView.attributedText = NSAttributedString(string: "Hello")
        XCTAssertNotNil(textView.textLayoutManager)
        XCTAssertFalse(textView.isScrollEnabled)
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
    }

    func testEmptyTextAndZeroWidthMeasureZero() {
        let textView = GlimmerTextView()
        XCTAssertEqual(textView.sizeThatFits(CGSize(width: 300, height: .greatestFiniteMagnitude)).height, 0)
        textView.attributedText = NSAttributedString(string: "Hello")
        XCTAssertEqual(textView.sizeThatFits(CGSize(width: 0, height: .greatestFiniteMagnitude)).height, 0)
    }

    func testCodeBlockAttachmentHostsAFullWidthView() throws {
        let code = GlimmerEmbed.codeBlock(language: "swift", code: "let x = 1\nlet y = 2")
        let textView = GlimmerTextView()
        textView.attributedText = document([NSAttributedString(string: "Before"), attachment(code), NSAttributedString(string: "After")])
        let height = textView.sizeThatFits(CGSize(width: 390, height: .greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: height)

        let view = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: textView))
        XCTAssertEqual(view.frame.width, 390, accuracy: 0.5)
        XCTAssertEqual(view.frame.height, view.embedHeight(forWidth: 390), accuracy: 0.5)
        XCTAssertGreaterThan(height, view.frame.height)
        _ = window
    }

    func testFactoryBuildsEveryEmbedKind() {
        let url = URL(string: "https://example.com/a.png")!  // test-only literal
        let embeds: [GlimmerEmbed] = [
            .codeBlock(language: nil, code: "x"),
            .table(header: [NSAttributedString(string: "h")], rows: [], alignments: [.none]),
            .image(source: url, alt: "a"),
            .thematicBreak,
        ]
        let kinds = embeds.map { embed in
            let attachment = GlimmerBlockAttachment(embed: embed, theme: theme, highlighter: GlimmerBasicHighlighter(), imageLoader: nil)
            return String(describing: type(of: GlimmerEmbedViewFactory.makeView(for: attachment)))
        }
        XCTAssertEqual(kinds, ["GlimmerCodeBlockView", "GlimmerTableView", "GlimmerImageEmbedView", "GlimmerRuleView"])
    }

    func testEmbedsResizeWhenWidthChanges() throws {
        let words = String(repeating: "wrap these words ", count: 30)
        let textView = GlimmerTextView()
        textView.attributedText = document([NSAttributedString(string: words), attachment(.thematicBreak)])
        let wide = textView.sizeThatFits(CGSize(width: 390, height: .greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: wide)
        let rule = try XCTUnwrap(findSubview(GlimmerRuleView.self, in: textView))
        XCTAssertEqual(rule.frame.width, 390, accuracy: 0.5)

        let narrow = textView.sizeThatFits(CGSize(width: 250, height: .greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(narrow, wide)
        textView.frame = CGRect(x: 0, y: 0, width: 250, height: narrow)
        settle(textView)
        let resized = try XCTUnwrap(findSubview(GlimmerRuleView.self, in: textView))
        XCTAssertEqual(resized.frame.width, 250, accuracy: 0.5)
        _ = window
    }

    func testThemeSetsLinkAttributes() {
        var themed = theme
        themed.underlinesLinks = true
        let textView = GlimmerTextView()
        textView.apply(theme: themed)
        XCTAssertEqual(textView.linkTextAttributes[.foregroundColor] as? UIColor, themed.linkColor)
        XCTAssertEqual(textView.linkTextAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerTextViewTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerTextView' in scope`.

- [ ] **Step 3: Implement the embed payload and attachment**

`Sources/Glimmer/Engine/Embeds/GlimmerEmbed.swift`:
```swift
import Foundation

/// A block rendered as its own view inside the text flow. Table cells arrive already styled by the composer.
enum GlimmerEmbed {
    case codeBlock(language: String?, code: String)
    case table(header: [NSAttributedString], rows: [[NSAttributedString]], alignments: [GlimmerTable.Alignment])
    case image(source: URL, alt: String)
    case thematicBreak
}
```

`Sources/Glimmer/Engine/Embeds/GlimmerBlockAttachment.swift`:
```swift
import UIKit

/// A full-width attachment whose view comes from `GlimmerEmbedViewFactory`.
/// Put it in its own paragraph (`\n` before and after).
final class GlimmerBlockAttachment: NSTextAttachment {
    let embed: GlimmerEmbed
    let theme: GlimmerTheme
    let highlighter: any GlimmerHighlighter
    let imageLoader: (any GlimmerImageLoader)?

    init(embed: GlimmerEmbed, theme: GlimmerTheme, highlighter: any GlimmerHighlighter, imageLoader: (any GlimmerImageLoader)?) {
        self.embed = embed
        self.theme = theme
        self.highlighter = highlighter
        self.imageLoader = imageLoader
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewProvider(
        for parentView: UIView?, location: any NSTextLocation, textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = GlimmerEmbedViewProvider(
            textAttachment: self, parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager, location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

/// Creates the embed view and sizes the attachment to the full available width.
final class GlimmerEmbedViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? GlimmerBlockAttachment else { return }
        view = GlimmerEmbedViewFactory.makeView(for: attachment)
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
        proposedLineFragment: CGRect, position: CGPoint
    ) -> CGRect {
        let width = max(0, proposedLineFragment.width - position.x)
        let height = (view as? any GlimmerEmbedView)?.embedHeight(forWidth: width) ?? 0
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

@MainActor
enum GlimmerEmbedViewFactory {
    static func makeView(for attachment: GlimmerBlockAttachment) -> any GlimmerEmbedView {
        switch attachment.embed {
        case .codeBlock(let language, let code):
            return GlimmerCodeBlockView(code: code, language: language, theme: attachment.theme, highlighter: attachment.highlighter)
        case .table(let header, let rows, let alignments):
            return GlimmerTableView(header: header, rows: rows, alignments: alignments, theme: attachment.theme)
        case .image(let source, let alt):
            return GlimmerImageEmbedView(source: source, alt: alt, theme: attachment.theme, loader: attachment.imageLoader)
        case .thematicBreak:
            return GlimmerRuleView(theme: attachment.theme)
        }
    }
}
```

- [ ] **Step 4: Implement the text view**

`Sources/Glimmer/Engine/Render/GlimmerTextView.swift`:
```swift
import UIKit

/// The TextKit 2 surface for a composed markdown document: non-scrolling, selectable, not editable.
/// Never read `layoutManager` here — it silently switches the view to TextKit 1.
@MainActor
final class GlimmerTextView: UITextView {
    private(set) var theme: GlimmerTheme = .default
    private var lastLayoutWidth: CGFloat = 0

    init() {
        // On iOS 16+, a nil text container gives a TextKit 2 text view.
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        dataDetectorTypes = []
        apply(theme: .default)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(theme: GlimmerTheme) {
        self.theme = theme
        var link: [NSAttributedString.Key: Any] = [.foregroundColor: theme.linkColor]
        if theme.underlinesLinks { link[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        linkTextAttributes = link
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard size.width > 0, attributedText.length > 0 else { return CGSize(width: max(size.width, 0), height: 0) }
        let fitted = super.sizeThatFits(CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: size.width, height: ceil(fitted.height))
    }

    override var intrinsicContentSize: CGSize {
        let height = bounds.width > 0 ? sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height : 0
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width != lastLayoutWidth else { return }
        lastLayoutWidth = bounds.width
        invalidateIntrinsicContentSize()
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerTextViewTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`. A TextKit 2 spike on 2026-09-25 (iOS 27.0 simulator) confirmed three things. Overriding `viewProvider(for:)` makes `usesTextAttachmentView` true with `data: nil, ofType: nil`. The view is placed inside the text view. `proposedLineFragment.width - position.x` equals the container width minus line-fragment padding.

- [ ] **Step 6: Commit**

```bash
git add Sources/Glimmer/Engine/Embeds/GlimmerEmbed.swift Sources/Glimmer/Engine/Embeds/GlimmerBlockAttachment.swift Sources/Glimmer/Engine/Render/GlimmerTextView.swift Tests/GlimmerTests/Engine/GlimmerTextViewTests.swift
git commit -m "Engine: host embed views in a TextKit 2 text view through attachment view providers"
```

---

### Task 9: Composer (blocks → attributed string)

**Files:**
- Create: `Sources/Glimmer/Engine/Compose/GlimmerComposer.swift`
- Create: `Sources/Glimmer/Engine/Compose/GlimmerComposer+Inlines.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerComposerTests.swift`

**Interfaces:**
- Consumes: `GlimmerBlock`/`GlimmerInline`/`GlimmerParser` (Task 2), `GlimmerTheme` and the keys (Task 4), `GlimmerHighlighter` (Task 5), `GlimmerImageLoader` (Task 7), and `GlimmerEmbed`/`GlimmerBlockAttachment` (Task 8).
- Produces: `@MainActor struct GlimmerComposer`, with stored properties declared in this order: `var theme: GlimmerTheme`, `var highlighter: any GlimmerHighlighter = GlimmerBasicHighlighter()`, `var imageLoader: (any GlimmerImageLoader)? = nil`. It provides `func compose(_ blocks: [GlimmerBlock]) -> NSAttributedString` (no trailing newline) and `func compose(inlines: [GlimmerInline], font: UIFont) -> NSAttributedString`. Task 11 appends `var extensions: [any GlimmerExtension] = []` as the last stored property.

The attributed-string contract, which later tasks rely on:
- **Paragraphs:** every paragraph ends with `\n` (except the last in the document) and carries a `.paragraphStyle`.
- **Headings** carry `.accessibilityTextHeadingLevel`.
- **List markers** are `"•\t"`, `"◦\t"`, `"▪︎\t"` (cycling by depth), `"<n>.\t"`, or a checkbox image attachment followed by `"\t"`. Each carries `.glimmerListMarker`. The list paragraph has `firstLineHeadIndent = indent - listIndent`, `headIndent = indent` and a tab stop at `indent`.
- **Quotes:** a quoted paragraph carries `.glimmerQuoteDepth` and uses `secondaryTextColor`.
- **Inline code** carries `.glimmerInlineCode = true` and the code font at 0.9× the surrounding size.
- **Embeds** are a `"\u{FFFC}\n"` paragraph carrying `.glimmerSource`, `lineHeightMultiple = 1` and `paragraphSpacing = blockSpacing`.
- **Images:** a paragraph whose only content is one image becomes an `.image` embed. An image inside running text renders as its alt text in `secondaryTextColor`.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerComposerTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerComposerTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func compose(_ markdown: String) -> NSAttributedString {
        GlimmerComposer(theme: theme).compose(GlimmerParser.parse(markdown))
    }

    private func attributes(of substring: String, in text: NSAttributedString, file: StaticString = #filePath, line: UInt = #line) -> [NSAttributedString.Key: Any] {
        let range = (text.string as NSString).range(of: substring)
        guard range.location != NSNotFound else {
            XCTFail("missing \(substring.debugDescription) in \(text.string.debugDescription)", file: file, line: line)
            return [:]
        }
        return text.attributes(at: range.location, effectiveRange: nil)
    }

    private func style(of substring: String, in text: NSAttributedString) -> NSParagraphStyle? {
        attributes(of: substring, in: text)[.paragraphStyle] as? NSParagraphStyle
    }

    private func blockAttachment(in text: NSAttributedString) -> GlimmerBlockAttachment? {
        var found: GlimmerBlockAttachment?
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if let attachment = value as? GlimmerBlockAttachment { found = attachment; stop.pointee = true }
        }
        return found
    }

    func testParagraphTextAndBoldTrait() {
        let text = compose("Hello **bold** world")
        XCTAssertEqual(text.string, "Hello bold world")
        XCTAssertEqual(attributes(of: "Hello", in: text)[.font] as? UIFont, theme.bodyFont)
        let bold = attributes(of: "bold", in: text)[.font] as? UIFont
        XCTAssertTrue(bold?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    }

    func testHeadingUsesHeadingFontAndLevel() {
        let text = compose("# Title\n\nBody")
        XCTAssertEqual(text.string, "Title\nBody")
        XCTAssertEqual(attributes(of: "Title", in: text)[.font] as? UIFont, theme.headingFont(level: 1))
        XCTAssertEqual(attributes(of: "Title", in: text)[.accessibilityTextHeadingLevel] as? Int, 1)
    }

    func testInlineCodeIsTaggedAndMonospaced() {
        let code = attributes(of: "let", in: compose("Use `let` here"))
        XCTAssertEqual(code[.glimmerInlineCode] as? Bool, true)
        let font = code[.font] as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
    }

    func testLinkCarriesURL() {
        let link = attributes(of: "site", in: compose("[site](https://example.com)"))
        XCTAssertEqual(link[.link] as? URL, URL(string: "https://example.com"))
    }

    func testBulletListMarkersAndHangingIndent() {
        let text = compose("- one\n- two")
        XCTAssertEqual(text.string, "•\tone\n•\ttwo")
        XCTAssertEqual(attributes(of: "•", in: text)[.glimmerListMarker] as? String, "- ")
        let first = style(of: "one", in: text)
        XCTAssertEqual(first?.headIndent, theme.listIndent)
        XCTAssertEqual(first?.firstLineHeadIndent, 0)
        XCTAssertEqual(first?.tabStops.first?.location, theme.listIndent)
        XCTAssertEqual(first?.paragraphSpacing, theme.tightListSpacing)
        XCTAssertEqual(style(of: "two", in: text)?.paragraphSpacing, theme.paragraphSpacing, "the last item of a tight list restores normal spacing")
    }

    func testOrderedListStartsAtGivenNumber() {
        let text = compose("3. three\n4. four")
        XCTAssertEqual(text.string, "3.\tthree\n4.\tfour")
        XCTAssertEqual(attributes(of: "3.", in: text)[.glimmerListMarker] as? String, "3. ")
    }

    func testNestedListIndentsTwice() {
        let text = compose("- outer\n  - inner")
        XCTAssertEqual(text.string, "•\touter\n◦\tinner")
        XCTAssertEqual(style(of: "inner", in: text)?.headIndent, theme.listIndent * 2)
    }

    func testTaskListUsesCheckboxAndMarkdownSource() {
        let text = compose("- [x] done")
        XCTAssertNotNil(text.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(text.attribute(.glimmerListMarker, at: 0, effectiveRange: nil) as? String, "- [x] ")
        XCTAssertTrue(text.string.hasSuffix("\tdone"))
    }

    func testBlockQuoteIndentsTagsDepthAndDims() {
        let text = compose("> quoted")
        let quoted = attributes(of: "quoted", in: text)
        XCTAssertEqual(quoted[.glimmerQuoteDepth] as? Int, 1)
        XCTAssertEqual(quoted[.foregroundColor] as? UIColor, theme.secondaryTextColor)
        XCTAssertEqual(style(of: "quoted", in: text)?.headIndent, theme.quoteIndent)
    }

    func testCodeBlockBecomesAttachmentWithSource() throws {
        let text = compose("```swift\nlet x = 1\n```")
        XCTAssertEqual(text.string, "\u{FFFC}")
        let attachment = try XCTUnwrap(blockAttachment(in: text))
        guard case .codeBlock(let language, let code) = attachment.embed else { return XCTFail("expected code") }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let x = 1")
        XCTAssertEqual(text.attribute(.glimmerSource, at: 0, effectiveRange: nil) as? String, "```swift\nlet x = 1\n```")
        let paragraph = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.lineHeightMultiple, 1)
    }

    func testTableBecomesAttachmentWithComposedCells() throws {
        let text = compose("| a | **b** |\n|---|---|\n| 1 | 2 |")
        let attachment = try XCTUnwrap(blockAttachment(in: text))
        guard case .table(let header, let rows, _) = attachment.embed else { return XCTFail("expected table") }
        XCTAssertEqual(header.map(\.string), ["a", "b"])
        XCTAssertEqual(rows.map { $0.map(\.string) }, [["1", "2"]])
        let boldHeader = header[1].attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(boldHeader?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertEqual(text.attribute(.glimmerSource, at: 0, effectiveRange: nil) as? String, "| a | b |\n| --- | --- |\n| 1 | 2 |")
    }

    func testStandaloneImageIsEmbedInlineImageIsAltText() throws {
        let standalone = compose("![Chart](https://example.com/c.png)")
        let attachment = try XCTUnwrap(blockAttachment(in: standalone))
        guard case .image(let source, let alt) = attachment.embed else { return XCTFail("expected image") }
        XCTAssertEqual(source, URL(string: "https://example.com/c.png"))
        XCTAssertEqual(alt, "Chart")

        let inline = compose("See ![icon](https://example.com/i.png) here")
        XCTAssertEqual(inline.string, "See icon here")
        XCTAssertEqual(attributes(of: "icon", in: inline)[.foregroundColor] as? UIColor, theme.secondaryTextColor)
    }

    func testThematicBreakIsEmbed() throws {
        let text = compose("above\n\n---\n\nbelow")
        XCTAssertEqual(text.string, "above\n\u{FFFC}\nbelow")
        let attachment = try XCTUnwrap(blockAttachment(in: text))
        guard case .thematicBreak = attachment.embed else { return XCTFail("expected rule") }
    }

    func testEmptyMarkdownComposesToEmptyString() {
        XCTAssertEqual(compose("").length, 0)
        XCTAssertEqual(compose("  \n\n ").length, 0)
    }

    func testEmojiAndRTLKeepAttributeRanges() {
        let text = compose("👋🏽 مرحبا **bold** ✓")
        XCTAssertEqual(text.string, "👋🏽 مرحبا bold ✓")
        let bold = attributes(of: "bold", in: text)[.font] as? UIFont
        XCTAssertTrue(bold?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        let wave = attributes(of: "✓", in: text)[.font] as? UIFont
        XCTAssertFalse(wave?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? true)
    }

    func testQuoteListCodeNestingIndents() throws {
        let text = compose("> 1. step\n>    ```swift\n>    let x = 1\n>    ```")
        XCTAssertEqual(text.string, "1.\tstep\n\u{FFFC}")
        let embedStyle = text.attribute(.paragraphStyle, at: text.length - 1, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(embedStyle?.headIndent, theme.quoteIndent + theme.listIndent)
        XCTAssertEqual(text.attribute(.glimmerQuoteDepth, at: text.length - 1, effectiveRange: nil) as? Int, 1)
    }

    func testSoftAndHardBreaks() {
        XCTAssertEqual(compose("a\nb").string, "a b")
        XCTAssertEqual(compose("a  \nb").string, "a\u{2028}b")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerComposerTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerComposer' in scope`.

- [ ] **Step 3: Implement block composition**

`Sources/Glimmer/Engine/Compose/GlimmerComposer.swift`:
```swift
import UIKit

/// Turns a `GlimmerBlock` tree into one attributed string for a `GlimmerTextView`.
///
/// Prose becomes text with paragraph styles; code blocks, tables, standalone images and rules become full-width
/// `GlimmerBlockAttachment`s. The theme must already be scaled for Dynamic Type (`GlimmerTheme.scaled(for:)`).
@MainActor
struct GlimmerComposer {
    var theme: GlimmerTheme
    var highlighter: any GlimmerHighlighter = GlimmerBasicHighlighter()
    var imageLoader: (any GlimmerImageLoader)? = nil

    struct Context {
        var indent: CGFloat = 0
        var quoteDepth = 0
        var listDepth = 0
        /// Overrides `paragraphSpacing` (tight lists).
        var paragraphSpacing: CGFloat?
    }

    func compose(_ blocks: [GlimmerBlock]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for block in blocks { append(block, context: Context(), marker: nil, to: output) }
        if output.string.hasSuffix("\n") {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
        return output
    }

    /// Styled text for a run of inlines, without paragraph styling. Table cells use this.
    func compose(inlines: [GlimmerInline], font: UIFont) -> NSAttributedString {
        let output = NSMutableAttributedString()
        appendInlines(inlines, attributes: [.font: font, .foregroundColor: theme.textColor], to: output)
        return output
    }

    // MARK: - Blocks

    private func append(_ block: GlimmerBlock, context: Context, marker: NSAttributedString?, to output: NSMutableAttributedString) {
        switch block {
        case .paragraph(let inlines):
            if let image = standaloneImage(inlines) {
                appendEmbed(.image(source: image.url, alt: image.alt), source: "![\(image.alt)](\(image.url.absoluteString))",
                            context: context, marker: marker, to: output)
            } else {
                appendTextParagraph(inlines, font: theme.bodyFont, context: context, marker: marker, to: output)
            }
        case .heading(let level, let inlines):
            appendTextParagraph(inlines, font: theme.headingFont(level: level), context: context, marker: marker,
                                headingLevel: level, spacingBefore: output.length > 0 ? theme.blockSpacing : 0, to: output)
        case .blockQuote(let blocks):
            var inner = context
            inner.indent += theme.quoteIndent
            inner.quoteDepth += 1
            for (index, child) in blocks.enumerated() {
                append(child, context: inner, marker: index == 0 ? marker : nil, to: output)
            }
        case .list(let list):
            if let marker { appendTextParagraph([], font: theme.bodyFont, context: context, marker: marker, to: output) }
            appendList(list, context: context, to: output)
        case .codeBlock(let language, let code):
            appendEmbed(.codeBlock(language: language, code: code), source: "```\(language ?? "")\n\(code)\n```",
                        context: context, marker: marker, to: output)
        case .table(let table):
            appendEmbed(tableEmbed(table), source: tableSource(table), context: context, marker: marker, to: output)
        case .thematicBreak:
            appendEmbed(.thematicBreak, source: "---", context: context, marker: marker, to: output)
        case .htmlBlock(let html):
            appendTextParagraph([.text(html.trimmingCharacters(in: .newlines))], font: theme.bodyFont, context: context,
                                marker: marker, to: output)
        }
    }

    private func appendList(_ list: GlimmerList, context: Context, to output: NSMutableAttributedString) {
        var inner = context
        inner.indent += theme.listIndent
        inner.listDepth += 1
        inner.paragraphSpacing = list.isTight ? theme.tightListSpacing : nil
        for (offset, item) in list.items.enumerated() {
            let marker = listMarker(kind: list.kind, index: offset, checkbox: item.checkbox, context: inner)
            if item.blocks.isEmpty {
                appendTextParagraph([], font: theme.bodyFont, context: inner, marker: marker, to: output)
            }
            for (index, block) in item.blocks.enumerated() {
                append(block, context: inner, marker: index == 0 ? marker : nil, to: output)
            }
        }
        if list.isTight { setSpacingOfLastParagraph(context.paragraphSpacing ?? theme.paragraphSpacing, in: output) }
    }

    private func appendTextParagraph(
        _ inlines: [GlimmerInline], font: UIFont, context: Context, marker: NSAttributedString?,
        headingLevel: Int? = nil, spacingBefore: CGFloat = 0, to output: NSMutableAttributedString
    ) {
        let start = output.length
        let attributes = baseAttributes(font: font, context: context)
        if let marker { output.append(marker) }
        appendInlines(inlines, attributes: attributes, to: output)
        output.append(NSAttributedString(string: "\n", attributes: attributes))
        let range = NSRange(location: start, length: output.length - start)
        let style = paragraphStyle(context: context, hasMarker: marker != nil)
        style.paragraphSpacingBefore = spacingBefore
        output.addAttribute(.paragraphStyle, value: style, range: range)
        if context.quoteDepth > 0 { output.addAttribute(.glimmerQuoteDepth, value: context.quoteDepth, range: range) }
        if let headingLevel { output.addAttribute(.accessibilityTextHeadingLevel, value: headingLevel, range: range) }
    }

    private func appendEmbed(
        _ embed: GlimmerEmbed, source: String, context: Context, marker: NSAttributedString?,
        to output: NSMutableAttributedString
    ) {
        if let marker { appendTextParagraph([], font: theme.bodyFont, context: context, marker: marker, to: output) }
        let start = output.length
        let attachment = GlimmerBlockAttachment(embed: embed, theme: theme, highlighter: highlighter, imageLoader: imageLoader)
        output.append(NSAttributedString(attachment: attachment))
        output.append(NSAttributedString(string: "\n"))
        let range = NSRange(location: start, length: output.length - start)
        let style = paragraphStyle(context: context, hasMarker: false)
        style.lineHeightMultiple = 1
        style.paragraphSpacing = theme.blockSpacing
        output.addAttributes([.paragraphStyle: style, .font: theme.bodyFont, .glimmerSource: source], range: range)
        if context.quoteDepth > 0 { output.addAttribute(.glimmerQuoteDepth, value: context.quoteDepth, range: range) }
    }

    // MARK: - Styles

    func baseAttributes(font: UIFont, context: Context) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: context.quoteDepth > 0 ? theme.secondaryTextColor : theme.textColor]
    }

    private func paragraphStyle(context: Context, hasMarker: Bool) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.lineHeightMultiple
        style.headIndent = context.indent
        style.firstLineHeadIndent = hasMarker ? max(0, context.indent - theme.listIndent) : context.indent
        style.tabStops = hasMarker ? [NSTextTab(textAlignment: .natural, location: context.indent, options: [:])] : []
        style.paragraphSpacing = context.paragraphSpacing ?? theme.paragraphSpacing
        return style
    }

    private func setSpacingOfLastParagraph(_ spacing: CGFloat, in output: NSMutableAttributedString) {
        guard output.length > 0 else { return }
        let range = (output.string as NSString).paragraphRange(for: NSRange(location: output.length - 1, length: 0))
        guard let current = output.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
              let style = current.mutableCopy() as? NSMutableParagraphStyle else { return }
        style.paragraphSpacing = spacing
        output.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private func listMarker(kind: GlimmerList.Kind, index: Int, checkbox: Bool?, context: Context) -> NSAttributedString {
        let color = context.quoteDepth > 0 ? theme.secondaryTextColor : theme.textColor
        let marker = NSMutableAttributedString()
        let source: String
        if let checkbox {
            let symbol = UIImage(systemName: checkbox ? "checkmark.square.fill" : "square")?
                .withTintColor(checkbox ? theme.linkColor : theme.secondaryTextColor, renderingMode: .alwaysOriginal)
            let box = NSTextAttachment()
            box.image = symbol
            let side = ceil(theme.bodyFont.capHeight + 6)
            box.bounds = CGRect(x: 0, y: (theme.bodyFont.capHeight - side) / 2, width: side, height: side)
            marker.append(NSAttributedString(attachment: box))
            source = checkbox ? "- [x] " : "- [ ] "
        } else {
            switch kind {
            case .bullet:
                let bullets = ["•", "◦", "▪︎"]
                marker.append(NSAttributedString(string: bullets[(context.listDepth - 1) % bullets.count], attributes: [
                    .font: theme.bodyFont, .foregroundColor: theme.secondaryTextColor,
                ]))
                source = "- "
            case .ordered(let start):
                let number = start + index
                marker.append(NSAttributedString(string: "\(number).", attributes: [.font: theme.bodyFont, .foregroundColor: color]))
                source = "\(number). "
            }
        }
        marker.append(NSAttributedString(string: "\t", attributes: [.font: theme.bodyFont]))
        marker.addAttribute(.glimmerListMarker, value: source, range: NSRange(location: 0, length: marker.length))
        return marker
    }

    // MARK: - Embeds

    private func standaloneImage(_ inlines: [GlimmerInline]) -> (url: URL, alt: String)? {
        let meaningful = inlines.filter { inline in
            switch inline {
            case .softBreak, .lineBreak: false
            case .text(let text): !text.trimmingCharacters(in: .whitespaces).isEmpty
            default: true
            }
        }
        guard meaningful.count == 1, case .image(let source, _, let alt) = meaningful[0], let url = URL(string: source) else {
            return nil
        }
        return (url, alt)
    }

    private func tableEmbed(_ table: GlimmerTable) -> GlimmerEmbed {
        .table(
            header: table.header.map { compose(inlines: $0, font: theme.tableHeaderFont) },
            rows: table.rows.map { row in row.map { compose(inlines: $0, font: theme.tableFont) } },
            alignments: table.alignments
        )
    }

    private func tableSource(_ table: GlimmerTable) -> String {
        func line(_ cells: [[GlimmerInline]]) -> String {
            "| " + cells.map { GlimmerInline.plainText($0) }.joined(separator: " | ") + " |"
        }
        let divider = "| " + table.alignments.map { alignment in
            switch alignment {
            case .left: ":---"
            case .center: ":---:"
            case .right: "---:"
            case .none: "---"
            }
        }.joined(separator: " | ") + " |"
        return ([line(table.header), divider] + table.rows.map(line)).joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Implement inline composition**

`Sources/Glimmer/Engine/Compose/GlimmerComposer+Inlines.swift`:
```swift
import UIKit

extension GlimmerComposer {
    func appendInlines(_ inlines: [GlimmerInline], attributes: [NSAttributedString.Key: Any], to output: NSMutableAttributedString) {
        for inline in inlines {
            switch inline {
            case .text(let text):
                appendText(text, attributes: attributes, to: output)
            case .code(let code):
                var codeAttributes = attributes
                let size = (attributes[.font] as? UIFont ?? theme.bodyFont).pointSize
                codeAttributes[.font] = theme.codeFont.withSize(size * 0.9)
                codeAttributes[.glimmerInlineCode] = true
                output.append(NSAttributedString(string: code, attributes: codeAttributes))
            case .emphasis(let children):
                appendInlines(children, attributes: adding(.traitItalic, to: attributes), to: output)
            case .strong(let children):
                appendInlines(children, attributes: adding(.traitBold, to: attributes), to: output)
            case .strikethrough(let children):
                var struck = attributes
                struck[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                appendInlines(children, attributes: struck, to: output)
            case .link(let destination, _, let children):
                var linked = attributes
                if let url = URL(string: destination) { linked[.link] = url }
                appendInlines(children, attributes: linked, to: output)
            case .image(_, _, let alt):
                var faded = attributes
                faded[.foregroundColor] = theme.secondaryTextColor
                output.append(NSAttributedString(string: alt, attributes: faded))
            case .softBreak:
                output.append(NSAttributedString(string: " ", attributes: attributes))
            case .lineBreak:
                output.append(NSAttributedString(string: "\u{2028}", attributes: attributes))
            case .html(let html):
                output.append(NSAttributedString(string: html, attributes: attributes))
            }
        }
    }

    /// Appends plain text. Task 11 adds extension token scanning here.
    func appendText(_ text: String, attributes: [NSAttributedString.Key: Any], to output: NSMutableAttributedString) {
        output.append(NSAttributedString(string: text, attributes: attributes))
    }

    private func adding(_ trait: UIFontDescriptor.SymbolicTraits, to attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        guard let font = attributes[.font] as? UIFont,
              let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait)) else {
            return attributes
        }
        var updated = attributes
        updated[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
        return updated
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerComposerTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Glimmer/Engine/Compose Tests/GlimmerTests/Engine/GlimmerComposerTests.swift
git commit -m "Engine: compose the block tree into one attributed string with embeds"
```

---

### Task 10: Layout-fragment decorations (inline-code pills, quote bars)

**Files:**
- Create: `Sources/Glimmer/Engine/Render/GlimmerLayoutFragment.swift`
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift`
- Modify: `Tests/GlimmerTests/Engine/EngineTestSupport.swift` (add `layoutFragments`)
- Test: `Tests/GlimmerTests/Engine/GlimmerLayoutFragmentTests.swift`

**Interfaces:**
- Consumes: `GlimmerTextView` (Task 8), `GlimmerComposer` (Task 9), `.glimmerInlineCode` and `.glimmerQuoteDepth` (Task 4).
- Produces:
  - `final class GlimmerLayoutFragment: NSTextLayoutFragment`, with `var theme: GlimmerTheme?`, `func inlineCodePillRects() -> [CGRect]` and `func quoteBarRects() -> [CGRect]`. Rects are in fragment coordinates.
  - `final class GlimmerLayoutFragmentProvider: NSObject, NSTextLayoutManagerDelegate`, created with `init(theme:)`, with `var theme`.
  - `GlimmerTextView` installs a provider in `init()` and updates its theme in `apply(theme:)`.
  - Test support: `layoutFragments(_ textView: UITextView) -> [NSTextLayoutFragment]`.

- [ ] **Step 1: Add the fragment helper to test support**

Append to `Tests/GlimmerTests/Engine/EngineTestSupport.swift`:
```swift
/// Every layout fragment of a TextKit 2 text view, with layout ensured.
@MainActor
func layoutFragments(_ textView: UITextView) -> [NSTextLayoutFragment] {
    guard let manager = textView.textLayoutManager else { return [] }
    manager.ensureLayout(for: manager.documentRange)
    var fragments: [NSTextLayoutFragment] = []
    manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
        fragments.append(fragment)
        return true
    }
    return fragments
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerLayoutFragmentTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerLayoutFragmentTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func hostedTextView(_ markdown: String) -> (GlimmerTextView, UIWindow) {
        let textView = GlimmerTextView()
        textView.apply(theme: theme)
        textView.attributedText = GlimmerComposer(theme: theme).compose(GlimmerParser.parse(markdown))
        let height = textView.sizeThatFits(CGSize(width: 390, height: .greatestFiniteMagnitude)).height
        return (textView, hostInWindow(textView, width: 390, height: height))
    }

    func testEveryFragmentIsAGlimmerFragment() {
        let (textView, window) = hostedTextView("One\n\nTwo\n\n> Three")
        let fragments = layoutFragments(textView)
        XCTAssertFalse(fragments.isEmpty)
        XCTAssertTrue(fragments.allSatisfy { $0 is GlimmerLayoutFragment })
        _ = window
    }

    func testInlineCodeProducesOnePillAfterLeadingText() throws {
        let (textView, window) = hostedTextView("Use `let` here")
        let fragment = try XCTUnwrap(layoutFragments(textView).first as? GlimmerLayoutFragment)
        let pills = fragment.inlineCodePillRects()
        XCTAssertEqual(pills.count, 1)
        let pill = try XCTUnwrap(pills.first)
        XCTAssertGreaterThan(pill.minX, 10, "the pill starts after \"Use \"")
        XCTAssertGreaterThan(pill.width, 10)
        XCTAssertLessThan(pill.maxX, 390)
        _ = window
    }

    func testNestedQuoteDrawsOneBarPerLevel() throws {
        let (textView, window) = hostedTextView("> > deep")
        let fragment = try XCTUnwrap(layoutFragments(textView).first as? GlimmerLayoutFragment)
        let bars = fragment.quoteBarRects()
        XCTAssertEqual(bars.count, 2)
        XCTAssertEqual(bars[1].minX, theme.quoteIndent, accuracy: 0.5)
        XCTAssertEqual(bars[0].height, fragment.layoutFragmentFrame.height, accuracy: 0.5)
        _ = window
    }

    func testPlainParagraphHasNoDecorations() throws {
        let (textView, window) = hostedTextView("Nothing special")
        let fragment = try XCTUnwrap(layoutFragments(textView).first as? GlimmerLayoutFragment)
        XCTAssertEqual(fragment.inlineCodePillRects(), [])
        XCTAssertEqual(fragment.quoteBarRects(), [])
        _ = window
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerLayoutFragmentTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerLayoutFragment' in scope`.

- [ ] **Step 4: Implement the fragment and its delegate**

`Sources/Glimmer/Engine/Render/GlimmerLayoutFragment.swift`:
```swift
import UIKit

/// Draws decorations that must not move glyphs: rounded pills behind inline code and one bar per blockquote level.
final class GlimmerLayoutFragment: NSTextLayoutFragment {
    var theme: GlimmerTheme?

    static let pillHorizontalInset: CGFloat = 3
    static let quoteBarWidth: CGFloat = 3

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.insetBy(dx: -(Self.pillHorizontalInset + 1), dy: -2)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        if let theme {
            let traits = UITraitCollection.current
            context.saveGState()
            context.setFillColor(theme.quoteBarColor.resolvedColor(with: traits).cgColor)
            for rect in quoteBarRects() {
                context.fill(rect.offsetBy(dx: point.x, dy: point.y))
            }
            context.setFillColor(theme.inlineCodeBackground.resolvedColor(with: traits).cgColor)
            for rect in inlineCodePillRects() {
                context.addPath(UIBezierPath(roundedRect: rect.offsetBy(dx: point.x, dy: point.y), cornerRadius: 4).cgPath)
                context.fillPath()
            }
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }

    /// One full-height bar per quote level, at `level × quoteIndent`.
    func quoteBarRects() -> [CGRect] {
        guard let theme,
              let paragraph = textElement as? NSTextParagraph,
              paragraph.attributedString.length > 0,
              let depth = paragraph.attributedString.attribute(.glimmerQuoteDepth, at: 0, effectiveRange: nil) as? Int,
              depth > 0 else { return [] }
        let height = layoutFragmentFrame.height
        return (0..<depth).map { level in
            CGRect(x: CGFloat(level) * theme.quoteIndent, y: 0, width: Self.quoteBarWidth, height: height)
        }
    }

    /// A rounded background behind each inline-code run, split per line.
    func inlineCodePillRects() -> [CGRect] {
        var rects: [CGRect] = []
        for line in textLineFragments {
            let text = line.attributedString
            let lineRange = line.characterRange
            guard lineRange.length > 0, NSMaxRange(lineRange) <= text.length else { continue }
            text.enumerateAttribute(.glimmerInlineCode, in: lineRange) { value, range, _ in
                guard value != nil,
                      let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont else { return }
                let startX = line.locationForCharacter(at: range.location).x
                let endX = line.locationForCharacter(at: NSMaxRange(range)).x
                let baseline = line.typographicBounds.minY + line.glyphOrigin.y
                rects.append(CGRect(
                    x: line.typographicBounds.minX + startX - Self.pillHorizontalInset,
                    y: baseline - font.ascender - 1,
                    width: endX - startX + Self.pillHorizontalInset * 2,
                    height: font.ascender - font.descender + 2
                ))
            }
        }
        return rects
    }
}

/// Hands TextKit a `GlimmerLayoutFragment` for every paragraph.
final class GlimmerLayoutFragmentProvider: NSObject, NSTextLayoutManagerDelegate {
    var theme: GlimmerTheme

    init(theme: GlimmerTheme) {
        self.theme = theme
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = GlimmerLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.theme = theme
        return fragment
    }
}
```

- [ ] **Step 5: Install the provider in the text view**

In `Sources/Glimmer/Engine/Render/GlimmerTextView.swift`:
- Add a stored property below `private var lastLayoutWidth: CGFloat = 0`:
  ```swift
      /// Strongly held: the text layout manager's delegate is weak.
      private let fragmentProvider = GlimmerLayoutFragmentProvider(theme: .default)
  ```
- In `init()`, before `apply(theme: .default)`, add:
  ```swift
          textLayoutManager?.delegate = fragmentProvider
  ```
- In `apply(theme:)`, after `self.theme = theme`, add:
  ```swift
          fragmentProvider.theme = theme
  ```

- [ ] **Step 6: Run the tests to verify they pass, then rerun the text view tests**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerLayoutFragmentTests -only-testing:GlimmerTests/GlimmerTextViewTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Glimmer/Engine/Render Tests/GlimmerTests/Engine/EngineTestSupport.swift Tests/GlimmerTests/Engine/GlimmerLayoutFragmentTests.swift
git commit -m "Engine: draw inline-code pills and quote bars from custom layout fragments"
```

---

### Task 11: Extensions and inline chips

**Files:**
- Create: `Sources/Glimmer/Engine/Extensions/GlimmerExtension.swift`
- Create: `Sources/Glimmer/Engine/Extensions/GlimmerInlineAttachment.swift`
- Modify: `Sources/Glimmer/Engine/Compose/GlimmerComposer.swift` (add the `extensions` property)
- Modify: `Sources/Glimmer/Engine/Compose/GlimmerComposer+Inlines.swift` (token scanning in `appendText`)
- Test: `Tests/GlimmerTests/Engine/GlimmerExtensionTests.swift`

**Interfaces:**
- Consumes: `GlimmerComposer` (Task 9), `GlimmerTextView` (Tasks 8 and 10), `.glimmerSource` (Task 4) and `hostInWindow`/`findSubview` (Task 5).
- Produces:
  - `public struct GlimmerInlineToken: Equatable, Sendable`, with `range: Range<String.Index>`, `kind: String`, `payload: [String: String]`, `displayText: String` and `source: String`, and `public init(range:kind:payload:displayText:source:)`.
  - `public protocol GlimmerExtension: Sendable`, with `func preprocess(_ markdown: String) -> String`, `func scan(_ text: String) -> [GlimmerInlineToken]` and `@MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView?`. Default implementations are no-ops.
  - `final class GlimmerInlineAttachment: NSTextAttachment`, created with `init(token:glimmerExtension:theme:)`, plus `GlimmerInlineViewProvider`, which sizes to the font's line height and sits on the baseline.
  - `GlimmerComposer.extensions: [any GlimmerExtension]`, the last stored property, defaulting to `[]`.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerExtensionTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

/// Turns `[3]` into a citation chip.
private struct CitationExtension: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            return GlimmerInlineToken(
                range: range, kind: "citation", payload: ["index": String(label.dropFirst().dropLast())],
                displayText: label, source: label
            )
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? {
        let label = UILabel()
        label.text = token.payload["index"]
        label.font = theme.captionFont
        label.accessibilityIdentifier = "citation"
        return label
    }
}

@MainActor
final class GlimmerExtensionTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func compose(_ markdown: String, extensions: [any GlimmerExtension]) -> NSAttributedString {
        GlimmerComposer(theme: theme, extensions: extensions).compose(GlimmerParser.parse(markdown))
    }

    func testCitationBecomesInlineAttachmentWithSource() {
        let text = compose("See [3] now", extensions: [CitationExtension()])
        XCTAssertEqual(text.string, "See \u{FFFC} now")
        XCTAssertTrue(text.attribute(.attachment, at: 4, effectiveRange: nil) is GlimmerInlineAttachment)
        XCTAssertEqual(text.attribute(.glimmerSource, at: 4, effectiveRange: nil) as? String, "[3]")
    }

    func testWithoutExtensionsTextIsUntouched() {
        XCTAssertEqual(compose("See [3] now", extensions: []).string, "See [3] now")
    }

    func testChipsInsideBoldKeepBoldFont() {
        let text = compose("**See [3]**", extensions: [CitationExtension()])
        let font = text.attribute(.font, at: 4, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    }

    func testTwoTokensInOneRun() {
        XCTAssertEqual(compose("a [1] b [2] c", extensions: [CitationExtension()]).string, "a \u{FFFC} b \u{FFFC} c")
    }

    func testInlineChipIsHostedAtLineHeight() throws {
        let textView = GlimmerTextView()
        textView.attributedText = compose("See [3] now", extensions: [CitationExtension()])
        let height = textView.sizeThatFits(CGSize(width: 390, height: .greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: height)
        let chip = try XCTUnwrap(textView.allSubviews.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "citation" })
        XCTAssertEqual(chip.frame.height, ceil(theme.bodyFont.lineHeight), accuracy: 1)
        _ = window
    }
}

private extension UIView {
    var allSubviews: [UIView] { subviews + subviews.flatMap(\.allSubviews) }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerExtensionTests 2>&1 | tail -5`
Expected: a build failure, `cannot find type 'GlimmerExtension' in scope`.

- [ ] **Step 3: Implement the extension API**

`Sources/Glimmer/Engine/Extensions/GlimmerExtension.swift`:
```swift
import UIKit

/// A custom inline token found in a run of plain text (a mention, a citation, …).
public struct GlimmerInlineToken: Equatable, Sendable {
    /// Range in the text passed to `GlimmerExtension.scan(_:)`.
    public var range: Range<String.Index>
    public var kind: String
    public var payload: [String: String]
    /// Plain text used when there is no view, and for accessibility.
    public var displayText: String
    /// Markdown copied for this token.
    public var source: String

    public init(range: Range<String.Index>, kind: String, payload: [String: String] = [:], displayText: String, source: String) {
        self.range = range
        self.kind = kind
        self.payload = payload
        self.displayText = displayText
        self.source = source
    }
}

/// Adds custom syntax to Glimmer.
public protocol GlimmerExtension: Sendable {
    /// Rewrites markdown before parsing, for example turning a custom token into a standard link.
    func preprocess(_ markdown: String) -> String
    /// Finds tokens in a run of plain text. Returned ranges must index into `text`.
    func scan(_ text: String) -> [GlimmerInlineToken]
    /// The view shown for a token, sized to the line height. Return nil to show `displayText` as a label.
    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView?
}

extension GlimmerExtension {
    public func preprocess(_ markdown: String) -> String { markdown }
    public func scan(_ text: String) -> [GlimmerInlineToken] { [] }
    @MainActor public func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? { nil }
}
```

`Sources/Glimmer/Engine/Extensions/GlimmerInlineAttachment.swift`:
```swift
import UIKit

/// An inline chip for an extension token. It is laid out at the line height, on the baseline.
final class GlimmerInlineAttachment: NSTextAttachment {
    let token: GlimmerInlineToken
    let glimmerExtension: any GlimmerExtension
    let theme: GlimmerTheme

    init(token: GlimmerInlineToken, glimmerExtension: any GlimmerExtension, theme: GlimmerTheme) {
        self.token = token
        self.glimmerExtension = glimmerExtension
        self.theme = theme
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewProvider(
        for parentView: UIView?, location: any NSTextLocation, textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = GlimmerInlineViewProvider(
            textAttachment: self, parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager, location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

final class GlimmerInlineViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? GlimmerInlineAttachment else { return }
        if let custom = attachment.glimmerExtension.makeInlineView(for: attachment.token, theme: attachment.theme) {
            view = custom
        } else {
            let label = UILabel()
            label.text = attachment.token.displayText
            label.font = attachment.theme.bodyFont
            label.textColor = attachment.theme.linkColor
            view = label
        }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
        proposedLineFragment: CGRect, position: CGPoint
    ) -> CGRect {
        let font = attributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
        let height = ceil(font.lineHeight)
        let fitted = view?.sizeThatFits(CGSize(width: proposedLineFragment.width, height: height)).width ?? 0
        return CGRect(x: 0, y: font.descender, width: min(ceil(fitted), proposedLineFragment.width), height: height)
    }
}
```

- [ ] **Step 4: Scan text in the composer**

In `Sources/Glimmer/Engine/Compose/GlimmerComposer.swift`, add the last stored property below `var imageLoader: (any GlimmerImageLoader)? = nil`:
```swift
    var extensions: [any GlimmerExtension] = []
```

In `Sources/Glimmer/Engine/Compose/GlimmerComposer+Inlines.swift`, replace `appendText(_:attributes:to:)` with:
```swift
    /// Appends plain text, turning extension tokens into inline chips.
    func appendText(_ text: String, attributes: [NSAttributedString.Key: Any], to output: NSMutableAttributedString) {
        let tokens = extensions.flatMap { glimmerExtension in
            glimmerExtension.scan(text)
                .filter { $0.range.lowerBound >= text.startIndex && $0.range.upperBound <= text.endIndex }
                .map { (glimmerExtension: glimmerExtension, token: $0) }
        }.sorted { $0.token.range.lowerBound < $1.token.range.lowerBound }

        var cursor = text.startIndex
        for match in tokens where match.token.range.lowerBound >= cursor {
            if cursor < match.token.range.lowerBound {
                output.append(NSAttributedString(string: String(text[cursor..<match.token.range.lowerBound]), attributes: attributes))
            }
            var chip = attributes
            chip[.attachment] = GlimmerInlineAttachment(token: match.token, glimmerExtension: match.glimmerExtension, theme: theme)
            chip[.glimmerSource] = match.token.source
            output.append(NSAttributedString(string: "\u{FFFC}", attributes: chip))
            cursor = match.token.range.upperBound
        }
        if cursor < text.endIndex {
            output.append(NSAttributedString(string: String(text[cursor...]), attributes: attributes))
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass, then rerun the composer tests**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerExtensionTests -only-testing:GlimmerTests/GlimmerComposerTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Glimmer/Engine/Extensions Sources/Glimmer/Engine/Compose Tests/GlimmerTests/Engine/GlimmerExtensionTests.swift
git commit -m "Engine: let extensions turn text tokens into inline chip views"
```

---

### Task 12: Public API — configuration, `GlimmerView`, `GlimmerText`

**Files:**
- Create: `Sources/Glimmer/Engine/GlimmerConfiguration.swift`
- Create: `Sources/Glimmer/Engine/GlimmerView.swift`
- Create: `Sources/Glimmer/Engine/GlimmerText.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerViewTests.swift`

**Interfaces:**
- Consumes: every earlier engine type.
- Produces:
  - `public struct GlimmerConfiguration: Sendable`, with `theme`, `extensions`, `imageLoader` and `highlighter`, `public init(theme:extensions:imageLoader:highlighter:)` (all defaulted) and `public static var default`.
  - `@MainActor public final class GlimmerView: UIView`. It is created with `public init(configuration:)` and provides `public var configuration`, `public var onLinkTap: ((URL) -> Void)?`, `public var onHeightChange: (() -> Void)?`, `public func update(markdown: String)`, `sizeThatFits`, `intrinsicContentSize`, the internal `let textView: GlimmerTextView`, the internal `func linkAction(for:) -> UIAction?` and conformance to `UITextViewDelegate`.
  - `public struct GlimmerText: UIViewRepresentable`, created with `public init(_ markdown: String, configuration: GlimmerConfiguration = .default, onLinkTap: ((URL) -> Void)? = nil)`.
  - Plan 2 adds the `isStreaming:` overload and reveal. Plan 3 adds `markdownSource(for:)` and data detectors.

- [ ] **Step 1: Write the failing tests**

`Tests/GlimmerTests/Engine/GlimmerViewTests.swift`:
```swift
import UIKit
import XCTest
@testable import Glimmer

private struct ShoutExtension: GlimmerExtension {
    func preprocess(_ markdown: String) -> String { markdown.replacingOccurrences(of: "!!", with: "**") }
}

@MainActor
final class GlimmerViewTests: XCTestCase {
    func testRendersMarkdownIntoTheTextView() {
        let view = GlimmerView()
        view.update(markdown: "# Hi\n\nThere")
        XCTAssertEqual(view.textView.attributedText.string, "Hi\nThere")
    }

    func testEmptyMarkdownHasZeroHeight() {
        let view = GlimmerView()
        view.update(markdown: "")
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 320, height: .greatestFiniteMagnitude)).height, 0)
        view.update(markdown: "   \n ")
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 320, height: .greatestFiniteMagnitude)).height, 0)
    }

    func testPreprocessRunsBeforeParsing() {
        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [ShoutExtension()]))
        view.update(markdown: "!!loud!!")
        let font = view.textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertEqual(view.textView.attributedText.string, "loud")
    }

    func testLongURLStaysWithinWidth() throws {
        let view = GlimmerView()
        view.update(markdown: "https://example.com/" + String(repeating: "a", count: 300))
        let height = view.sizeThatFits(CGSize(width: 320, height: .greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(height, 0)
        let window = hostInWindow(view, width: 320, height: height)
        let manager = try XCTUnwrap(view.textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        XCTAssertLessThanOrEqual(manager.usageBoundsForTextContainer.width, 320.5)
        _ = window
    }

    func testDynamicTypeScalesFonts() {
        let view = GlimmerView()
        view.update(markdown: "Body")
        let window = hostInWindow(view, width: 320, height: 200)
        let before = (view.textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? 0
        view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        settle(view)
        let after = (view.textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? 0
        XCTAssertGreaterThan(after, before)
        _ = window
    }

    func testIntrinsicHeightTracksWidth() {
        let view = GlimmerView()
        view.update(markdown: String(repeating: "Some words that wrap. ", count: 20))
        let window = hostInWindow(view, width: 390, height: 100)
        let wide = view.intrinsicContentSize.height
        view.frame.size.width = 250
        settle(view)
        XCTAssertGreaterThan(view.intrinsicContentSize.height, wide)
        _ = window
    }

    func testLinkActionRequiresAHandler() throws {
        let view = GlimmerView()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertNil(view.linkAction(for: url))
        view.onLinkTap = { _ in }
        XCTAssertNotNil(view.linkAction(for: url))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerViewTests 2>&1 | tail -5`
Expected: a build failure, `cannot find 'GlimmerView' in scope`.

- [ ] **Step 3: Implement the configuration**

`Sources/Glimmer/Engine/GlimmerConfiguration.swift`:
```swift
import UIKit

/// Everything a `GlimmerView` needs besides the markdown itself.
public struct GlimmerConfiguration: Sendable {
    public var theme: GlimmerTheme
    public var extensions: [any GlimmerExtension]
    /// Loads standalone images. `nil` shows each image's alt text in its reserved box.
    public var imageLoader: (any GlimmerImageLoader)?
    public var highlighter: any GlimmerHighlighter

    public init(
        theme: GlimmerTheme = .default,
        extensions: [any GlimmerExtension] = [],
        imageLoader: (any GlimmerImageLoader)? = GlimmerURLSessionImageLoader(),
        highlighter: any GlimmerHighlighter = GlimmerBasicHighlighter()
    ) {
        self.theme = theme
        self.extensions = extensions
        self.imageLoader = imageLoader
        self.highlighter = highlighter
    }

    public static var `default`: GlimmerConfiguration { GlimmerConfiguration() }
}
```

- [ ] **Step 4: Implement the UIKit view**

`Sources/Glimmer/Engine/GlimmerView.swift`:
```swift
import UIKit

/// Renders markdown natively with TextKit 2.
///
/// Size it with Auto Layout (a width constraint gives an intrinsic height) or call `sizeThatFits(_:)` with a finite
/// width. `onHeightChange` fires whenever the height may have changed.
@MainActor
public final class GlimmerView: UIView {
    public var configuration: GlimmerConfiguration {
        didSet { render() }
    }
    public var onLinkTap: ((URL) -> Void)?
    public var onHeightChange: (() -> Void)?

    let textView = GlimmerTextView()
    private(set) var markdown = ""
    private var lastWidth: CGFloat = 0

    public init(configuration: GlimmerConfiguration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        textView.delegate = self
        addSubview(textView)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: GlimmerView, _: UITraitCollection) in
            view.render()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Replaces the rendered markdown. Rendering the same string twice does nothing.
    public func update(markdown: String) {
        guard markdown != self.markdown else { return }
        self.markdown = markdown
        render()
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        textView.sizeThatFits(size)
    }

    public override var intrinsicContentSize: CGSize {
        let height = bounds.width > 0 ? sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height : 0
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        guard bounds.width != lastWidth else { return }
        lastWidth = bounds.width
        invalidateIntrinsicContentSize()
        onHeightChange?()
    }

    func linkAction(for url: URL) -> UIAction? {
        guard let onLinkTap else { return nil }
        return UIAction { _ in onLinkTap(url) }
    }

    private func render() {
        let theme = configuration.theme.scaled(for: traitCollection)
        textView.apply(theme: theme)
        let source = configuration.extensions.reduce(markdown) { $1.preprocess($0) }
        let composer = GlimmerComposer(
            theme: theme,
            highlighter: configuration.highlighter,
            imageLoader: configuration.imageLoader,
            extensions: configuration.extensions
        )
        textView.attributedText = composer.compose(GlimmerParser.parse(source))
        invalidateIntrinsicContentSize()
        setNeedsLayout()
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

- [ ] **Step 5: Implement the SwiftUI wrapper**

`Sources/Glimmer/Engine/GlimmerText.swift`:
```swift
import SwiftUI

/// SwiftUI wrapper for `GlimmerView`. The configuration is read once, when the view is created. Markdown and
/// `onLinkTap` update in place.
public struct GlimmerText: UIViewRepresentable {
    public var markdown: String
    public var configuration: GlimmerConfiguration
    public var onLinkTap: ((URL) -> Void)?

    public init(_ markdown: String, configuration: GlimmerConfiguration = .default, onLinkTap: ((URL) -> Void)? = nil) {
        self.markdown = markdown
        self.configuration = configuration
        self.onLinkTap = onLinkTap
    }

    public func makeUIView(context: Context) -> GlimmerView {
        let view = GlimmerView(configuration: configuration)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    public func updateUIView(_ view: GlimmerView, context: Context) {
        view.onLinkTap = onLinkTap
        view.update(markdown: markdown)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: GlimmerView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerViewTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Glimmer/Engine/GlimmerConfiguration.swift Sources/Glimmer/Engine/GlimmerView.swift Sources/Glimmer/Engine/GlimmerText.swift Tests/GlimmerTests/Engine/GlimmerViewTests.swift
git commit -m "Engine: add GlimmerView, GlimmerText and GlimmerConfiguration"
```

---

### Task 13: Demo gallery and full-suite check

**Files:**
- Create: `Examples/GlimmerDemo/EngineGalleryDemo.swift`
- Modify: `Examples/GlimmerDemo/GlimmerDemo.xcodeproj/project.pbxproj` (three entries)
- Modify: `Examples/GlimmerDemo/ContentView.swift`
- Modify: `Examples/GlimmerDemo/GlimmerDemoApp.swift`

**Interfaces:**
- Consumes: `GlimmerText` and `GlimmerConfiguration` (Task 12).
- Produces: an "Engine Gallery (2.0)" demo screen, also reachable with the launch argument `--engine-gallery`.

- [ ] **Step 1: Write the gallery screen**

`Examples/GlimmerDemo/EngineGalleryDemo.swift`:
````swift
import Glimmer
import SwiftUI

/// Glimmer 2.0: every markdown element rendered natively by `GlimmerText`.
struct EngineGalleryDemo: View {
    @State private var isDark = false

    var body: some View {
        ScrollView {
            GlimmerText(Self.sample) { url in
                print("Tapped \(url)")
            }
            .padding(16)
        }
        .navigationTitle("Engine Gallery")
        .toolbar {
            Toggle("Dark", isOn: $isDark)
        }
        .preferredColorScheme(isDark ? .dark : .light)
    }

    static let sample = """
    # Glimmer 2.0

    A paragraph with **bold**, *italic*, ~~strikethrough~~, `inline code`, and a [link](https://example.com). \
    Bare URLs autolink too: https://superme.ai.

    ## Lists

    - First item
    - Second item with a longer line that wraps onto the next line to show the hanging indent
      - Nested item
    1. Ordered one
    2. Ordered two
    - [x] Done task
    - [ ] Open task

    ### Quote

    > Quoted text is dimmed and gets a bar.
    > > Nested quotes get two.

    ```swift
    struct Greeting {
        let name: String // a comment
        func text() -> String { "Hello, \\(name)! 42" }
    }
    ```

    | Feature | Status | Notes |
    |:--|:-:|--:|
    | Tables | ✅ | Scroll when wide |
    | Code | ✅ | Highlighted |

    ---

    ![A placeholder image](https://picsum.photos/800/450)

    Emoji and RTL: 👋🏽 مرحبا — done.
    """
}
````

- [ ] **Step 2: Register the file in the demo project**

In `Examples/GlimmerDemo/GlimmerDemo.xcodeproj/project.pbxproj`, add these three lines, each directly after the matching `StreamingRevealDemo.swift` line, keeping the same indentation. First confirm the IDs are unused: `grep -c "A1F00130\|A1F00131" Examples/GlimmerDemo/GlimmerDemo.xcodeproj/project.pbxproj` must print `0`.
- After the `StreamingRevealDemo.swift in Sources */ = {isa = PBXBuildFile; …` line:
  ```
  		A1F001312E49A00000DEMO01 /* EngineGalleryDemo.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1F001302E49A00000DEMO01 /* EngineGalleryDemo.swift */; };
  ```
- After the `StreamingRevealDemo.swift */ = {isa = PBXFileReference; …` line:
  ```
  		A1F001302E49A00000DEMO01 /* EngineGalleryDemo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = EngineGalleryDemo.swift; sourceTree = SOURCE_ROOT; };
  ```
- After the `StreamingRevealDemo.swift in Sources */,` line in the Sources build phase:
  ```
  				A1F001312E49A00000DEMO01 /* EngineGalleryDemo.swift in Sources */,
  ```

- [ ] **Step 3: Wire up navigation and the launch argument**

In `Examples/GlimmerDemo/ContentView.swift`, add this as the first line inside `Section("Core Demos") {`:
```swift
                    NavigationLink("Engine Gallery (2.0)", destination: EngineGalleryDemo())
```
In `Examples/GlimmerDemo/GlimmerDemoApp.swift`, replace the `WindowGroup` body with:
```swift
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--engine-gallery") {
                NavigationStack { EngineGalleryDemo() }
            } else if ProcessInfo.processInfo.arguments.contains("--reveal-demo") {
                NavigationStack { StreamingRevealDemo() }
                    .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--reveal-dark") ? .dark : nil)
                    .transformEnvironment(\.dynamicTypeSize) { size in
                        if ProcessInfo.processInfo.arguments.contains("--reveal-large-text") { size = .accessibility1 }
                    }
            } else {
                ContentView()
            }
        }
```

- [ ] **Step 4: Build, launch and check the gallery on the simulator**

```bash
cd /Users/willi/work/Glimmer
xcodebuild -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo -destination "$DEST" -derivedDataPath .build/demo-dd build 2>&1 | tail -3
SIM=$(xcrun simctl list devices available | grep "iPhone 17 Pro Max (" | head -1 | grep -oE "[0-9A-F-]{36}")
xcrun simctl boot "$SIM" 2>/dev/null; xcrun simctl install "$SIM" .build/demo-dd/Build/Products/Debug-iphonesimulator/GlimmerDemo.app
xcrun simctl launch "$SIM" dk.wu.GlimmerDemo --engine-gallery
sleep 3; xcrun simctl io "$SIM" screenshot .build/engine-gallery-light.png
xcrun simctl ui "$SIM" appearance dark; sleep 1; xcrun simctl io "$SIM" screenshot .build/engine-gallery-dark.png
xcrun simctl ui "$SIM" appearance light
```
Expected: `** BUILD SUCCEEDED **`. Open both screenshots and check each item:
- headings with a clear size step;
- bullets hanging with wrapped lines aligned to the text;
- the nested bullet `◦`, and ordered numbers;
- checkbox symbols;
- the quote dimmed with one bar, and the nested quote with two bars;
- a rounded pill behind `inline code`;
- a code block with a "swift" header and Copy icon, keywords, a string, a comment and a number in distinct colors;
- a bordered table with a header background and a centered/right-aligned column;
- a hairline rule;
- the image box (the picture appears, or its alt text does);
- the emoji/RTL line intact;
- dark mode switching every color with no black-on-black.

Fix any visual defect in the owning task's file, re-run that task's tests, and re-screenshot.

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`. That covers both the new engine tests and the untouched 1.x tests.

- [ ] **Step 6: Commit**

```bash
git add Examples/GlimmerDemo
git commit -m "Demo: add the Glimmer 2.0 engine gallery"
```
