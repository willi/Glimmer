# Glimmer 2.0 Plan 7: 1.x markdown parity

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 2.0 renders everything 1.x did that hosts relied on: footnotes (as the web shows them), opt-in `:emoji:` shortcodes, opt-in `@username` mentions with a tap callback, images inside paragraphs, and seven more highlighting languages.

**Architecture:**
- **Footnotes:** cmark-gfm's footnote option parses them. The composer numbers markers by first appearance, through a numbering it shares across a streaming document's recomposes, so numbers never change. Notes render after the last block, only once the answer settles.
- **Token presentations:** extension tokens gain a presentation (chip, text or image). Mentions and emoji are two built-in extensions using it. Tappable text tokens carry a `UITextItem` tag, so `UITextView` reports taps through the existing delegate.
- **Inline images:** an image inside a paragraph is an inline attachment, a line-height square filled by the image loader.
- **Highlighter:** the basic highlighter gains seven families and compiles each family's regex once.

**Tech Stack:** Swift 6, UIKit, TextKit 2, vendored cmark-gfm; iOS 26 floor.

**Spec:** `docs/superpowers/specs/2026-09-26-glimmer-2-perf-and-parity-design.md` §4 (Part B) and §2's goals and non-goals. Code map: 1.x sources live at `git show c9ed357^:<path>`.

## Global Constraints

- The public API additions are exactly the spec's:
  - `GlimmerTheme.footnoteFont` (default: the caption font) and `GlimmerTheme.mentionColor` (default: the link colour);
  - `GlimmerInlineToken.presentation`;
  - `GlimmerView.onTokenTap` and `GlimmerText`'s `onTokenTap:` parameter;
  - `GlimmerEmojiShortcodes` and `GlimmerMentions`.
- Both extensions are opt-in: the default configuration renders `:rocket:` and `@ada` as plain text, as today.
- Revealed text never moves or restyles while streaming. Every item gets a stability test (Task 1's helper).
- Copy: markdown writes the source (`[^label]`, `:rocket:`, `@ada`, `![alt](url)`). Plain text writes what's shown: the number, the emoji, the name, the alt text.
- No force unwraps in library code. One type per file. No Co-Authored-By trailers. Don't push.

## Review Focus

1. **A footnote marker arriving before its definition** must stay a superscript whose number never changes when the definition arrives, or if it never does. Test: Task 3 `testAMarkerKeepsItsNumberWhenItsDefinitionArrives`.
2. **A one-word footnote definition** (`[^1]: Yes.`) must be a note, not a swallowed link reference definition. Test: Task 2 `testAOneWordDefinitionIsANote`.
3. **Text with colons and at-signs that aren't tokens** (`10:30`, `a:b:c`, `ada@example.com`, `@` alone) must render and stream as plain text, with no reveal stall longer than the hold-back's 40 characters. Tests: Task 5 `testEmailsAndLoneAtSignsAreNotMentions`; Task 6 `testTimesAndRatiosAreNotShortcodes`, `testAnUnclosedShortcodeIsReleasedAfterASpace`.
4. **A mention inside a link or code** must stay link text or code. Test: Task 5 `testMentionsSkipLinksAndCode`.
5. **An inline image whose load fails, or with no loader,** keeps its square and never moves text. Test: Task 4 `testAFailedInlineImageKeepsItsSquare`.

---

### Task 1: A stability test for streamed text

**Files:**
- Create: `Tests/GlimmerTests/Engine/GlimmerStreamStabilityTests.swift`
- Modify: `Tests/GlimmerTests/Engine/EngineTestSupport.swift` (the helper)

**Interfaces:** Produces `assertStreamingKeepsShownTextInPlace(_ markdown: String, configuration: GlimmerConfiguration = GlimmerConfiguration(imageLoader: nil, reveal: .none), every step: Int = 3, file:line:)`.

The spec asks each item for "every prefix streamed, with no revealed glyph moving". The helper streams every `step`th prefix into a `GlimmerView` (reveal `.none`, 390 pt, in a window, awaiting each update).
- At each step, it records the segment rects of the text up to the start of the last paragraph that was already shown.
- It asserts those rects equal the next step's, within 0.5 pt, and that the text in that range is unchanged.
- The last paragraph may reflow as words arrive; everything before it may not.

- [ ] **Step 1:** Write the helper and `GlimmerStreamStabilityTests.testStreamingFixturesKeepShownTextInPlace`, which runs every `StreamingFixtures.all` entry.
- [ ] **Step 2:** Run it. Expected: PASS. It is a guard for today's behaviour. If a fixture fails, that's a finding: record it, and fix it if the cause is small.
- [ ] **Step 3: Prove the helper can fail.** Temporarily have the helper insert one character at offset 0 on the third step; it must report a moved glyph. Revert that, then commit `Tests: a stability check for streamed text`.

### Task 2: Footnotes, settled

**Files:**
- Modify: `Sources/Glimmer/Engine/Parse/GlimmerParser.swift`, `Parse/GlimmerNode.swift`
- Modify: `Compose/GlimmerComposer.swift`, `Compose/GlimmerComposer+Inlines.swift`
- Create: `Compose/GlimmerFootnoteNumbers.swift`
- Modify: `Theme/GlimmerTheme.swift` (`footnoteFont`, `mentionColor`), `Interact/GlimmerMarkdownSerializer.swift`
- Update the exhaustive switches the code map lists: `GlimmerNode.plainText`, `GlimmerConformanceTests.collectKinds`.
- Test: `Tests/GlimmerTests/Engine/GlimmerFootnoteTests.swift`

**Interfaces:**
- Produces:
  - `GlimmerInline.footnoteReference(label: String)`
  - `GlimmerBlock.footnoteDefinition(label: String, blocks: [GlimmerBlock])`
  - `final class GlimmerFootnoteNumbers`, a reference type with `func number(for label: String) -> Int`. It assigns 1, 2, … by first request.
  - `GlimmerComposer.footnotes: GlimmerFootnoteNumbers?`
  - `GlimmerComposer.rendersFootnoteDefinitions: Bool`

**Parsing:**
- `cmark_parser_new(CMARK_OPT_DEFAULT | CMARK_OPT_FOOTNOTES)`.
- A `CMARK_NODE_FOOTNOTE_REFERENCE` maps to `.footnoteReference(label:)`. The label is the literal of `cmark_node_parent_footnote_def(node)`, because cmark replaces the reference's own literal with its number.
- cmark leaves a reference with no definition as the text `[^label]`. After merging adjacent text nodes, split text on `\[\^([^\]\s]+)\]` into `.text` and `.footnoteReference` pieces.
- A `CMARK_NODE_FOOTNOTE_DEFINITION` maps to `.footnoteDefinition(label: literal, blocks: children)`.

**Composing:**
- **A marker:** the number from `footnotes?.number(for:)`, or a composer-local numbering when `footnotes` is nil. It uses `theme.footnoteFont`, `.baselineOffset = theme.bodyFont.capHeight - theme.footnoteFont.capHeight`, and `theme.linkColor`, with `.glimmerSource = "[^label]"`.
- **Definitions,** when `rendersFootnoteDefinitions`:
  - The first definition block composes a `.thematicBreak` embed with an empty source.
  - Each definition composes as an ordered-list item whose marker number is its footnote number. Add `itemNumbers: [Int]?` to `GlimmerList`; `listMarker` uses it when set.
  - Its paragraphs use `footnoteFont` and `secondaryTextColor`: compose them with a copy of `theme` whose `bodyFont` is `footnoteFont` and `textColor` is `secondaryTextColor`.
  - The item's `.glimmerListMarker` is `"[^label]: "`.
- When `rendersFootnoteDefinitions` is false, definition blocks compose to nothing (`composeBlock` returns empty).

**Copy:**
- `GlimmerMarkdownSerializer.continuation(ofMarker:)` returns four spaces for a marker starting with `[^`.
- A marker run's `.glimmerSource` writes `[^label]` in markdown; plain text writes the number.

- [ ] **Step 1: Failing tests** (`GlimmerFootnoteTests`):
  - `testAReferenceIsASuperscriptNumber`: `"Fact[^a] and more[^b].\n\n[^a]: One.\n[^b]: Two."`. The marker runs read "1" and "2", in `footnoteFont`, with a positive `baselineOffset`, in `linkColor`.
  - `testNumbersFollowFirstReference`: references b, a, b, with definitions in the order a, b. Markers read 1, 2, 1.
  - `testNotesFollowTheLastBlockInMarkerOrder`: the composed string ends with a rule attachment, then "1." One note, then "2." Two. They're in `footnoteFont`, and there's no "Footnotes" heading.
  - `testAOneWordDefinitionIsANote`: `"See[^1].\n\n[^1]: Yes."` renders a note "Yes.", not an empty document.
  - `testAReferenceWithoutADefinitionStaysASuperscript`: `"See[^x]."` renders marker "1" and no notes.
  - `testFootnotesCopyTheirSource`: markdown copy of the whole text is `"See[^1].\n\n[^1]: Yes."`. Plain copy reads `"See1.\n\n1. Yes."`.
  - `testNotesAreHiddenWhileStreaming`: `rendersFootnoteDefinitions = false` composes no rule and no notes.
- [ ] **Step 2:** Run them. Expected: compile errors, then failures.
- [ ] **Step 3:** Implement per the design above.
- [ ] **Step 4:** Run `GlimmerFootnoteTests`, `GlimmerComposerTests`, `GlimmerMarkdownSerializerTests`, `GlimmerConformanceTests`, then the engine suite. Expected: PASS.
- [ ] **Step 5: Commit** `Engine: footnotes, as the web shows them`.

### Task 3: Footnotes while streaming

**Files:**
- Modify: `Stream/GlimmerTailHealer.swift`, `Stream/GlimmerStreamingDocument.swift`
- Test: `GlimmerFootnoteTests.swift`, `GlimmerTailHealerTests.swift`, `GlimmerStreamStabilityTests.swift`

**Streaming document:**
- `GlimmerStreamingDocument` owns one `GlimmerFootnoteNumbers` for its lifetime and gives it to its composer, so a recomposed tail keeps earlier numbers.
- Its composer's `rendersFootnoteDefinitions` equals `!isStreaming`.
- The first settled update after streaming recomposes from the first definition block. It's appended text, so the reveal fades it in.

**Healer:**
- A trailing `\[\^[^\]\s]*$` (including a bare `[^`) is held back.
- A complete trailing `[^label]` is not held back, unlike other `[text]`: it's a marker.
- A line that is only `[^label]` or `[^label]:` at the end is held back, since it may be a definition starting.

- [ ] **Step 1: Failing tests.**
  - Healer cases:
    - `("see [^1", "see ")` and `("see [^", "see ")`;
    - `("see [^1]", "see [^1]")`;
    - `("text\n\n[^1]", "text\n\n")` and `("text\n\n[^1]:", "text\n\n")`.
  - `testAMarkerKeepsItsNumberWhenItsDefinitionArrives`: stream `"A[^x] b[^y]."`, then append the definitions and settle. Markers stay 1 and 2 throughout, and the notes appear only after settling.
  - Stability: `assertStreamingKeepsShownTextInPlace` on a footnote fixture that has references before definitions, and a definition in the middle of the answer.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the footnote, healer, stability, streaming-document and parity tests, then the engine suite. Expected: PASS.
- [ ] **Step 5: Commit** `Engine: footnote markers stream; notes appear when the answer settles`.

### Task 4: Images inside a paragraph

**Files:**
- Create: `Sources/Glimmer/Engine/Compose/GlimmerInlineImageAttachment.swift` (the attachment, its view provider and its view)
- Modify: `Compose/GlimmerComposer+Inlines.swift`, `Interact/GlimmerMarkdownSerializer.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerInlineImageTests.swift`

**Interfaces:** Produces `final class GlimmerInlineImageAttachment: NSTextAttachment`, with `source: URL`, `alt: String`, `theme`, `loader: (any GlimmerImageLoader)?` and `freshCopy()`.

- **Layout:**
  - `.image` inside a paragraph (not the standalone embed case) composes the attachment character.
  - `.glimmerSource = "![alt](url)"`.
  - It's followed by `.glimmerSpokenOnly` alt text, the way checkboxes speak.
  - Bounds: a square of `ceil(font.lineHeight)`, `y = font.descender`.
- **The view:** a `UIImageView` with `.scaleAspectFit`, `clipsToBounds`, a 3 pt corner radius and `theme.codeBlockBackground` behind it until the image loads. It loads through `loader` in a `Task`, cancelled in `isolated deinit`. It never changes size. `accessibilityElementsHidden`, because the spoken-only text reads the alt.
- **Copy:** the serializer writes the attachment's `.glimmerSource` in markdown and `alt` in plain text. It skips `.glimmerSpokenOnly` runs unless `forAccessibility`.
- **Cache:** `GlimmerDocumentCache.detached` gives each inline image attachment a fresh copy, as it does for chips.

- [ ] **Step 1: Failing tests:**
  - `testAnInlineImageIsALineHighSquare`;
  - `testAnInlineImageLoadsItsImage` (stub loader);
  - `testAFailedInlineImageKeepsItsSquare` (throwing loader, and a nil loader);
  - `testAParagraphOfOnlyAnImageIsStillAnEmbed`;
  - `testInlineImagesCopyTheirSourceAndAlt`;
  - `testVoiceOverReadsAnInlineImagesAlt` (the accessibility plain text contains the alt once);
  - stability on `"A badge ![ci](https://example.com/b.png) in text."`.
- [ ] **Step 2:** Run them. Expected: FAIL. The existing `testStandaloneImageIsEmbedInlineImageIsAltText` changes meaning: update it to the new behaviour and record a ruling.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the inline image, composer, serializer, cache, accessibility and stability tests, then the engine suite. Expected: PASS.
- [ ] **Step 5: Commit** `Engine: images inside a paragraph are line-height squares`.

### Task 5: Token presentations, `onTokenTap` and `GlimmerMentions`

**Files:**
- Modify: `Extensions/GlimmerExtension.swift` (`presentation`, `appliesInsideLinks`, `streamingHoldBack(in:)`)
- Modify: `Compose/GlimmerComposer+Inlines.swift` (text and image presentations)
- Create: `Extensions/GlimmerMentions.swift`
- Modify: `GlimmerView.swift` (`onTokenTap`, the `.tag` item), `GlimmerText.swift` (`onTokenTap:`)
- Modify: `Stream/GlimmerDocumentWorker.swift` and `GlimmerView.preprocessed` (hold-back while streaming)
- Test: `Tests/GlimmerTests/Engine/GlimmerMentionsTests.swift`, `GlimmerExtensionTests.swift`

**Interfaces:**
- Produces:
  - `GlimmerInlineToken.presentation: Presentation` (`.chip` default, `.text(tappable: Bool)`, `.image(URL)`).
  - `GlimmerExtension.appliesInsideLinks: Bool` (default true) and `GlimmerExtension.streamingHoldBack(in markdown: String) -> Int` (default 0): how many trailing characters to hold back while streaming.
  - `GlimmerView.onTokenTap: ((GlimmerInlineToken) -> Void)?`.
  - `public struct GlimmerMentions: GlimmerExtension` with `init()`.
- Consumes: Task 4's `GlimmerInlineImageAttachment` for `.image`.

**How presentations compose:**
- `.text(tappable:)` composes `displayText` with `.glimmerSource = source` and `.glimmerToken = GlimmerTokenBox(token)` (a new NSObject box and a new key).
- When tappable, it also gets `.foregroundColor = theme.mentionColor` and `.textItemTag = "glimmer-token-<n>"`. `n` is a per-composer counter; the string is unique per document.
- `.image(url)` composes a `GlimmerInlineImageAttachment` with the token's display text as its alt.
- `.chip` is unchanged.

**Taps:** `GlimmerView.textView(_:primaryActionFor:defaultAction:)` handles `case .tag(let tag)`. It finds the run with that `.textItemTag` and its `.glimmerToken`, then returns `UIAction { onTokenTap(token) }` when `onTokenTap` is set.

**Mentions:** `GlimmerMentions.scan` finds `(?<![A-Za-z0-9_])@([A-Za-z0-9](?:-?[A-Za-z0-9]){0,38})(?![A-Za-z0-9-]|\.[A-Za-z0-9])`. The token is kind `"mention"`, payload `["username": name]`, displayText `"@name"`, source `"@name"`, presentation `.text(tappable: true)`.
- `appliesInsideLinks` is false.
- `streamingHoldBack` returns the length of a trailing `@name` or `@name.` candidate (≤ 40 characters, no space).

- [ ] **Step 1: Failing tests:**
  - `testAMentionIsTappableTextInTheMentionColor`;
  - `testTappingAMentionCallsOnTokenTap` (build the action from the delegate with a `UITextItem` made from the tag);
  - `testEmailsAndLoneAtSignsAreNotMentions` (`ada@example.com`, `@`, `@-x`, `@example.com`);
  - `testMentionsSkipLinksAndCode` (`[@ada](https://x)`, `` `@ada` ``);
  - `testMentionsCopyAsTheirSource`;
  - `testWithoutTheExtensionAMentionIsPlainText`;
  - `testAChipTokenIsUnchanged` (the existing citation fixture);
  - stability on `"Thanks @ada and @grace-hopper for this."`, streamed character by character (`step: 1`).
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the mention, extension, accessibility, serializer and stability tests, then the engine suite. Expected: PASS.
- [ ] **Step 5: Commit** `Engine: extension tokens can be text or images; GlimmerMentions`.

### Task 6: `GlimmerEmojiShortcodes`

**Files:**
- Create: `Sources/Glimmer/Resources/github-emoji.json`, generated once from 1.x's `GitHubEmojis.swift` by a script in the commit message's body. Unicode names map to emoji; the 23 custom names map to `https://github.githubassets.com/images/icons/emoji/<name>.png?v8`.
- Modify: `Package.swift` (the resource)
- Create: `Extensions/GlimmerEmojiShortcodes.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerEmojiShortcodesTests.swift`

**Interfaces:** Produces `public struct GlimmerEmojiShortcodes: GlimmerExtension` with `init()`. The table loads lazily, once, from `Bundle.module`.

- `scan` finds `:([a-z0-9_+-]{1,40}):` where the name is in the table:
  - a Unicode entry becomes `.text(tappable: false)` with displayText set to the emoji;
  - a custom entry becomes `.image(url)` with displayText `":name:"`.

  Source is `":name:"` either way.
- `streamingHoldBack` returns the length of a trailing `:[a-z0-9_+-]{1,39}` with no closing colon, when the text before it doesn't end in a digit (`10:3` is a time, not a shortcode).
- Shortcodes aren't matched inside code, because `scan` never sees code.

- [ ] **Step 1: Failing tests:**
  - `testAShortcodeBecomesItsEmoji` (`:rocket:` → 🚀);
  - `testACustomShortcodeIsAnInlineImage` (`:octocat:`);
  - `testUnknownShortcodesStayText` (`:notanemoji:`);
  - `testTimesAndRatiosAreNotShortcodes` (`10:30`, `a:b:c`);
  - `testShortcodesSkipCode`;
  - `testAnUnclosedShortcodeIsReleasedAfterASpace`: streaming `"go :rock"` shows `"go "`, and `"go :rock and"` shows everything;
  - `testShortcodesCopyAsSourceAndEmoji` (markdown writes `:rocket:`, plain text writes 🚀);
  - `testTheTableHasTheGitHubSet` (≥ 1,900 names, and `octocat` is custom);
  - stability on `"Ship it :rocket: then :tada: :octocat:"`, `step: 1`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the emoji, extension and stability tests, then the engine suite. Expected: PASS.
- [ ] **Step 5: Commit** `Engine: GlimmerEmojiShortcodes`.

### Task 7: Seven more highlighting languages

**Files:** Modify `Sources/Glimmer/Engine/Highlight/GlimmerBasicHighlighter.swift`. Test `GlimmerCodeBlockViewTests.swift`.

**Families,** with keywords, strings, comments and numbers, using 1.x's `SyntaxHighlighter.swift` as the keyword source:

| Language | Aliases | Notes |
|---|---|---|
| JSON | `json` | Keys highlight as keywords; `true`, `false` and `null` are keywords. |
| SQL | `sql` | Keywords are case-insensitive; `--` and `/* */` comments. |
| YAML | `yaml`, `yml` | Keys as keywords; `#` comments. |
| HTML/XML | `html`, `xml`, `svg` | Tag and attribute names as keywords; `<!-- -->` comments. |
| CSS | `css`, `scss` | At-rules and properties as keywords; `/* */` comments. |
| C# | `csharp`, `cs`, `c#` | `//` and `/* */` comments. |
| PHP | `php` | `//`, `#` and `/* */` comments. |

`Family.pattern` is built into an `NSRegularExpression` once per family, in a `static let` table, instead of on every call. `NSRegularExpression` matching is thread-safe.

- [ ] **Step 1: Failing tests:** `testEachNewLanguageHighlightsItsTokens`, one sample per family asserting a keyword, a string and a comment span. `testTheRegexIsBuiltOncePerFamily`: highlighting the same family twice reuses one expression; check through an internal `static func expression(for:) -> NSRegularExpression?` identity.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the code block and highlighting tests, the streaming performance tests (Release sim), then the engine suite. Expected: PASS.
- [ ] **Step 5: Commit** `Highlight: JSON, SQL, YAML, HTML/XML, CSS, C# and PHP; each family's regex built once`.

### Task 8: Gallery, parity and README

**Files:**
- Modify: `Examples/GlimmerDemo/App/EngineGalleryDemo.swift` (sections; the gallery's configuration adds both extensions)
- Modify: `Tests/GlimmerTests/Engine/GlimmerStreamParityTests.swift` (a parity fixture per item)
- Modify: `README.md` (the "Gone" list, the new API, the footnotes note from the spec's risks)

- [ ] **Step 1:** A parity fixture using every item (footnotes, `:emoji:`, `@mention`, an inline image, a JSON block). Streamed and settled views end identical: text, size and snapshot. Stream with both extensions on.
- [ ] **Step 2: Gallery sections** "Footnotes", "Emoji and mentions", "Inline images" and "More languages". Screenshots in light, dark and large text; look at them.
- [ ] **Step 3: README.**
  - Remove footnotes, emoji, mentions and inline images from "Gone".
  - Document the two extensions and `onTokenTap`.
  - Note that footnote definitions appear only when the answer settles, and that hosts showing an endless stream should pass `isStreaming: false` to show them.
- [ ] **Step 4:** Run the demo UI tests and the engine suite. Commit `Demo: parity gallery; README`.

## Out of scope

- The spec's non-goals: inline footnotes `^[…]`, a footnote sheet, GitHub references, math, highlights and alerts.
- SuperMe adoption: the next piece of work.
