# Glimmer 2.0 — native markdown and streaming engine

Status: design approved in conversation, awaiting written-spec review
Branch: `glimmer-2`
Date: 2026-09-25

## 1. Why

Glimmer 1.x renders with SwiftUI `Text`/`AttributedString`, a hand-written 11k-line Swift parser, and twelve reveal
styles. It falls short of Google Gemini's iOS app in four ways, and this rewrite has to close all four:

1. **Streaming smoothness**: stutter, catch-up lurches, and layout jumps while tokens arrive.
2. **Markdown visual quality**: the typography and the list, heading, code and table rendering look less polished, and the parser
   has correctness bugs (nested strong inside a link leaks raw `**`; loose ordered lists number every item "1.").
3. **Text interaction**: native selection, copy, links and data detectors.
4. **Long-answer performance**: main-thread cost, memory and scrolling on long answers and long conversations.

### What Gemini actually does (teardown, 2026-09-25, Gemini iOS 1.2026.3770306)

The findings come from static analysis of the App Store IPA (only resources, imports and fixups were read; nothing was
decrypted) and an on-device all-process Time Profiler trace on an iPhone 16 Pro Max while an answer streamed.

- **Native rendering, not a web view.** The answer lives in a TextKit 1 `UITextView` (`_performTextKit1LayoutCalculation`,
  `NSLayoutManager` drawing through `_UITextTiledLayer`). That view is inside a self-sizing `UICollectionView` cell backed
  by a diffable data source.
- **Pacing is decoupled from the network.** An `NSTimer` fires about every 17 ms (about 60 Hz, even on a 120 Hz display).
  Each tick calls `applySnapshot` → `reconfigureItemsAtIndexPaths:` → `-[UITextView setAttributedText:]` with the
  **whole** answer, which triggers an Auto Layout self-sizing pass and a full TextKit 1 re-layout. The median cost is 3 ms per tick and the
  p90 is 5 ms, and it grows with answer length.
- **The fade was measured from a screen recording.** Text appears a phrase at a time (3–8 words). Each phrase fades from 0 to full ink
  over **about 600 ms, roughly linearly**. Phrase starts are 70–230 ms apart, so 3–4 phrases are mid-fade at once.
  Nothing moves and nothing reflows.

Gemini's quality comes from pacing plus plain native text. We keep that and remove its cost: the fades run in Core
Animation on the GPU, and TextKit only lays out the tail that changed.

## 2. Goals and non-goals

**Goals**

- Glimmer 2.0 ships a UIKit-native engine covering parse, compose, layout, reveal and interaction. SuperMe's native chat
  adopts it and deletes its own markdown renderer (that migration is a separate follow-up spec).
- Selection runs continuously across a whole answer.
- The reveal matches Gemini's measured behaviour: phrase-level, a roughly 600 ms linear fade, staggered starts, no motion
  or reflow, pacing decoupled from arrival, and adaptive catch-up.
- Parsing follows the CommonMark and GFM specs (the same GFM that superme-web renders with `remark-gfm`).
- Styling comes from a theme. SuperMe's theme will be ported from superme-web's `TokenizedMarkdown` styles in the
  adoption spec.

**Non-goals**

- LaTeX/math and Mermaid.
- Multiple reveal styles. There is one reveal plus `none`, and Reduce Motion uses `none`.
- Source compatibility with 1.x. This release is intentionally breaking.
- The linter, exporters, GitHub mention/issue/SHA extensions and emoji shortcodes (all deleted, §10).

## 3. Success criteria

Measured on an iPhone 16 Pro Max in a Release build, using a long mixed answer of about 5,000 words with headings, lists, quotes, code,
tables, images and SFM chips:

| Metric | Budget | Gemini today |
|---|---|---|
| Main-thread work per reveal frame | ~0 (Core Animation drives the fades) | ~3 ms median per 60 Hz tick |
| Applying one network update on main (tail edit; parse and compose run off-main) | ≤ 2 ms p95 | whole-document re-set and re-layout every tick |
| Starting a phrase (segment rects plus one layer) | ≤ 0.2 ms | — |
| Configuring a settled answer on cell reuse (cached document and height) | ≤ 4 ms | — |
| Hitches while streaming and scrolling (`XCTHitchMetric`) | 0 | — |

Behavioural criteria:

- The streamed result is pixel-identical to the settled render once the reveal completes.
- Once a glyph is visible it never moves (no reflow). Reported height never shrinks during streaming.
- Selection and copy work mid-stream, limited to revealed text.

## 4. Architecture

Five units, each with one job and a narrow interface:

```
network text ──▶ GlimmerView.update(markdown:isStreaming:)
                    │
                    ▼  (off main actor)
               ┌─────────┐   blocks    ┌──────────┐  DocumentEdit
               │  Parse  │ ──────────▶ │ Compose  │ ─────────────┐
               └─────────┘             └──────────┘              │
                                                                 ▼  (main actor)
                                     ┌────────────┐  ranges  ┌──────────┐
                                     │   Reveal   │ ◀─────── │  Render  │
                                     │ clock+mask │ ───────▶ │ TextView │
                                     └────────────┘  layers  └──────────┘
                                                                 │
                                                           ┌──────────┐
                                                           │ Interact │
                                                           └──────────┘
```

### 4.1 Parse

- **Vendored cmark-gfm** as a C target in the package, pinned to the exact latest release tag at vendoring time, with its
  licence files kept alongside. It adds no package dependency. The GFM extensions used are table,
  strikethrough, autolink and tasklist.
- A Swift wrapper turns the cmark tree into an immutable, `Sendable` block tree
  (`GlimmerBlock`/`GlimmerInline`) with source ranges.
- **Streaming document**: it keeps *committed* blocks (everything before the last block boundary that can no longer change)
  and re-parses only the open tail on each update. Committed blocks are never parsed again.
- **Tail healing** before parsing the tail: open inline syntax at the end of the buffer is closed optimistically
  (`**bold` → `**bold**`, an unclosed code span, a half-finished link `[text](ur` → text only, an unclosed code
  fence → a fence-closed block). The healed characters never reach the rendered text. They only stop half-finished syntax
  from rendering as raw markers or restyling after it has been revealed.
- **Extensions** (`GlimmerExtension`): `preprocess(_:) -> String` runs on the source (for example SFM's mention rewrite), and
  a text-node scan returns either styled text or an inline view token (for chips). Both run off-main.

### 4.2 Compose

- Turns blocks into **one `NSAttributedString` per answer**, styled by `GlimmerTheme`.
- Output is a `DocumentEdit`, never a whole new document: either *append* or *replace from offset N* (N is the start of the
  first changed block, which is always inside the tail).
- Prose element mapping:
  - Paragraphs and headings H1–H6 become text with theme fonts and paragraph styles.
  - Emphasis, strong, strikethrough and links become attributes. Link underlining is a theme option.
  - Lists (ordered, bulleted, task; nested) get hanging indents from paragraph styles. Markers are real text tagged with a
    `glimmer.listMarker` attribute so copy can map them back. Task checkboxes are inline SF Symbol image attachments.
  - Blockquotes are paragraph indents tagged `glimmer.quoteDepth`.
  - Inline code is tagged `glimmer.inlineCode`.
- Block embeds become full-width attachments (§4.3): code blocks, tables, images, and thematic breaks.
- Inline chips from extensions become inline attachments sized to the line height and sitting on the baseline, each carrying its source text for
  copy.
- Syntax highlighting sits behind a `GlimmerHighlighter` protocol, with a built-in tokenizer for common languages. It runs
  off-main and only on closed code lines.
- Trait changes (dark mode, Dynamic Type) re-style the existing block tree without re-parsing.

### 4.3 Render

- `GlimmerTextView` is a **TextKit 2** `UITextView`: `isScrollEnabled = false`, `isEditable = false`, `isSelectable = true`.
  Nothing may touch `layoutManager`, because that silently switches the view to TextKit 1.
- A `DocumentEdit` is applied inside one `NSTextContentStorage` editing transaction, replacing only the tail range, so
  TextKit invalidates and lays out only the changed paragraphs.
- **Decorations** are drawn by custom `NSTextLayoutFragment` subclasses, supplied through
  `textLayoutManager(_:textLayoutFragmentFor:in:)`. They cover inline-code pills and blockquote bars, draw from the tagged ranges,
  and never change glyph layout.
- **Block embeds** use `NSTextAttachment` with `NSTextAttachmentViewProvider` (iOS 15+). Bounds come from
  `attachmentBounds(for:location:textContainer:proposedLineFragment:position:)`, taking the full width of the proposed line fragment.
  - **Code block:** a header with the language and a Copy button, a horizontal scroll view, and its own selectable TextKit 2 text.
  - **Table:** a horizontally scrolling grid with a styled header row. Column widths are measured once per (content,
    width, theme) and cached.
  - **Image:** loaded through a host-provided `GlimmerImageLoader`. Space is reserved up front (the aspect ratio when known,
    otherwise a themed placeholder) so a finished load never shifts later text.
  - **Thematic break:** a hairline view.
- **Sizing.** `intrinsicContentSize` and `sizeThatFits(_:)` come from the text layout manager's usage bounds after
  `ensureLayout(for:)`. While streaming, the reported height is the bottom of the last *revealed* line (§5.4). A height cache
  is keyed by (message id, content version, width, theme).

### 4.4 Reveal

See §5.

### 4.5 Interact

See §6.

## 5. Reveal and pacing

### 5.1 Phrases

- The chunker cuts newly composed text into phrases of **3–8 words**, ending at `, . ; : ! ?` or a line break where possible.
  It never splits a word or grapheme cluster.
- An inline chip belongs to the phrase it sits in.
- Block embeds reveal internally, line by line for code and row by row for tables, using the same clock and fade on their own mask. An
  image is one phrase.

### 5.2 Pacing clock

- The revealed cursor advances at an adaptive rate in characters per second, aiming for a small **target lag** behind the arrived
  text.
- The rate is smoothed (critically damped) toward `max(baseRate, backlog / targetLag)`, so bursts from the network never cause a
  lurch.
- When `isStreaming` becomes false, the remaining backlog drains within a cap of about 1.5 s.
- Phrase starts are at least **60 ms** apart. Together with the rate, this reproduces Gemini's 70–230 ms stagger.
- The clock only wakes to start the next phrase, never per frame. It takes an injected time source for tests.
- Defaults (`baseRate`, `targetLag`, the drain cap, the minimum spacing, and fade = 0.6 s linear) live in
  `GlimmerConfiguration.reveal` and are tuned against the Gemini recording.

### 5.3 Mask

- All arrived text is laid out; unrevealed text is simply not covered by the mask. The mask is a `CALayer` set as
  `GlimmerTextView.layer.mask` and has three parts:
  - **Settled region**: one opaque rectangle covering every line whose phrases have all finished fading.
  - **Phrase layers**: one container per phrase, made of opaque rects from
    `enumerateTextSegments(in:type:.standard,options:)`, extended to the full line-fragment height so ascenders and
    descenders are covered. Each container runs `CABasicAnimation(keyPath: "opacity")` from 0 to 1 over 0.6 s, linear, with
    `preferredFrameRateRange` allowing 120 Hz.
  - **Merging**: when a phrase finishes and its line is complete, its rects fold into the settled region and the container
    is removed. That keeps about 8 or fewer layers alive.
- The mask does not depend on the background, so it works over glass and animated gradients.
- **Width, rotation and Dynamic Type**: rects are recomputed from the stored text ranges. In-flight fades restart from their
  presentation-layer opacity with the remaining duration.
- **Settle**: once the stream has ended, the backlog is empty and the last fade has finished, `layer.mask = nil`, so a settled answer carries no reveal overhead.
- The host app must set `CADisableMinimumFrameDurationOnPhone` for fades to run at 120 Hz on ProMotion. The README will
  document this.

### 5.4 Height and reuse

- While streaming, the reported height is the bottom of the last line containing a revealed phrase, so the cell grows one line at a
  time rather than tracking buffered text.
- Reveal progress lives in a `GlimmerRevealState` keyed by message ID and owned outside the view (a shared store with a
  bounded size). Cell reuse or reconfiguration resumes, never replays. Progress is monotonic.

### 5.5 Reduce Motion and `none`

Arrived text is shown immediately with no mask and no pacing.

### 5.6 Why not Metal

Gemini ships Metal shaders, but none of them draws text. Their function names (`aurora*`, `neuralGradient*` including
`…Sparks…`, `shaderLoadingFragment`, a glow, `turrellMesh`) are the colour-shifting backdrop, the loading shimmer and the
glow. The trace shows `MTKView draw` driven by a display link on the main thread, while Gemini's text is drawn on the CPU
by `NSLayoutManager` into a tiled layer. The reveal stays on Core Animation for three reasons:

- **Core Animation is already on the GPU.** A mask sublayer's opacity animation runs in the system render server with
  zero app work per frame. A Metal view needs a display-link draw call every frame, which is more main-thread work, not less.
- **A shader breaks native text.** Shaders only see pixels, so text would have to be rendered into a texture. We would
  either lose native selection, VoiceOver and system text rendering, or maintain a second, synchronized copy of the text.
- **The measured effect is plain opacity.** Gemini's reveal is a linear 0→1 fade with no blur, glow or motion, which is
  exactly what a Core Animation opacity animation does.

Revisit this only for an effect opacity can't express, such as a glow or blur on the newest phrase. That would be a Metal
overlay limited to the leading band, added only if the plain fade looks flat on device.

## 6. Interaction and accessibility

- **Selection** is native and continuous across prose. Embeds are selected as one unit (U+FFFC) from outside, and code and tables keep their own
  selection inside. While streaming, the selection is clamped to the revealed range.
- **Copy** is overridden to write plain text and markdown (`net.daringfireball.markdown`) to the pasteboard:
  - embeds and chips expand to their source (fenced code, a markdown table, a mention label);
  - list markers map back to markdown syntax.
  - A public `markdownSource(for:)` backs "Copy answer" buttons.
- **Links** use the iOS 17 `UITextItem` API. `textView(_:primaryActionFor:defaultAction:)` routes a tap to the host's `onLinkTap`, and
  `textView(_:menuConfigurationFor:defaultMenu:)` gives the native preview and menu with host items. Chips handle their own
  taps.
- **Data detectors** are opt-in through `GlimmerConfiguration.dataDetectors` and off by default, because they cost main-thread time.
- **Edit menu**: the native menu (Copy, Look Up, Translate, Share) with a delegate hook for host actions. `UIFindInteraction` is
  optional.
- **Gestures**: the view never scrolls. Long-press selects as usual, and a tap on a link triggers its action.
- **VoiceOver**:
  - While the mask is active, the view is one accessibility element whose label is the revealed plain text.
  - At settle it hands back to `UITextView`'s native accessibility: line and word navigation plus a links rotor.
  - Code blocks read "Code, <language>" with a Copy button. Tables are an accessibility container with row and column
    headers. Chips read "Mention, <name>" and "Source, <domain>".
- **Dynamic Type** is handled by the theme through `UIFontMetrics`, and Reduce Motion by §5.5.

## 7. Theme

`GlimmerTheme` is a `Sendable` value type:

- **Fonts per role**: body, H1–H6, code, table, and table header, each scaled with `UIFontMetrics`.
- **Colors**, all dynamic: text, secondary text, link, inline-code background, code-block background, quote bar, table
  border, and table header background.
- **Spacing**: paragraph spacing, spacing between blocks, list indent and marker gap, block insets, and line-height multiple.
- **Options**: link underline, and the code-block header on or off.

`GlimmerTheme.default` follows Apple's HIG. A SuperMe theme is out of scope here (adoption spec).

## 8. Public API sketch

```swift
@MainActor public final class GlimmerView: UIView {
    public init(configuration: GlimmerConfiguration = .default)
    public func update(markdown: String, isStreaming: Bool)   // accumulated source so far
    public var revealState: GlimmerRevealState?                // keyed by message id; enables resume
    public var onLinkTap: ((URL) -> Void)?
    public var onHeightChange: (() -> Void)?
    public func markdownSource(for range: NSRange? = nil) -> String
    // intrinsicContentSize and sizeThatFits(_:) are overridden
}

public struct GlimmerConfiguration: Sendable {
    public var theme: GlimmerTheme
    public var extensions: [any GlimmerExtension]
    public var reveal: GlimmerRevealOptions        // .smooth(fade:baseRate:targetLag:…) or .none
    public var dataDetectors: UIDataDetectorTypes
    public var imageLoader: (any GlimmerImageLoader)?
    public var highlighter: any GlimmerHighlighter
}

public protocol GlimmerExtension: Sendable {
    func preprocess(_ source: String) -> String
    func scan(text: Substring, context: GlimmerInlineContext) -> [GlimmerInlineReplacement]
    @MainActor func makeInlineView(for token: GlimmerInlineToken) -> UIView?
}

public struct GlimmerText: UIViewRepresentable { /* SwiftUI wrapper around GlimmerView */ }
```

Final names and signatures are settled in the implementation plan. The shape above is the contract.

## 9. Error handling

- **Parsing** cannot fail, because cmark accepts any input. Invalid UTF-8 is never passed in, since sources are Swift `String`s.
- **Image load failure** shows an alt-text placeholder at the reserved size, so it never shifts layout.
- **An extension returning nothing** leaves the text as it is.
- **Zero or unknown width**: no layout and no mask until a real width arrives, and the view reports zero height.
- **Memory pressure**: composed-document, height and table-width caches are dropped. The next configure rebuilds them.
- **A non-append update** (the source was replaced, not extended) takes the full-replace path: re-parse, compose the whole
  document, and settle revealed progress by character count, clamped to the new length.

## 10. Deleted in 2.0

- the 11k-line Swift parser, `ParallelParser`, `CachedMarkdownParser` and the streaming parser;
- the `AttributedString` renderer, `CustomRenderer` and the HTML and plain-text renderers;
- all SwiftUI views, including `MarkdownView`, `GlimmerRevealView` and `StreamingMarkdownView`;
- the 12 reveal styles, `RevealDriver`, `RevealSession`, `RevealProgressStore`, the smooth-trail public API,
  `GlimmerTrailTextView` and `GlimmerRevealViewController`;
- the linter, the markdown exporter, the GitHub mention/issue/SHA extensions, and the emoji tables and resource;
- tests covering deleted code.

The demo app is rebuilt around the new engine. It has an element gallery, a streaming lab (speed presets, Gemini-cadence replay, pause and resume,
light and dark), and a long-answer benchmark screen.

## 11. Testing

- **Unit tests** for the cmark tree mapping, tail healing (table-driven), the phrase chunker, the pacing clock with an injected clock, mask
  geometry from ranges, copy serialization, and extension scanning.
- **Conformance**: the CommonMark and GFM spec examples run through parse → compose. They assert that every node type maps and
  nothing crashes. cmark owns spec correctness.
- **Stream versus settled parity**: across a fixture corpus, the final frame after a completed reveal is pixel-identical to a settled render
  (simulator snapshot diff).
- **Stability**: every prefix of every fixture is fed in. The tests assert that revealed glyph rects never move and height never
  shrinks while streaming.
- **Performance**: Release `measure` tests cover parse, compose and apply on the corpus. The demo's on-device harness replays recorded chunk
  timings (including Gemini's cadence) under an `XCTHitchMetric` UI test. The `xctrace --all-processes` Time Profiler
  recipe gives a head-to-head against Gemini.
- **Visual**: the demo gallery covers every element in light and dark, and at the default and an accessibility text size.

## 12. Delivery phases

Each phase leaves the branch building and tested:

1. Vendor cmark-gfm, write the Swift tree wrapper, and add the conformance tests.
2. Compose and render a static document with the theme, decorations and embeds. Start the demo gallery.
3. Streaming: the streaming document, tail healing and incremental edits.
4. Reveal: the pacing clock, chunker, mask, height and resume.
5. Interaction and accessibility.
6. The performance harness and on-device validation against §3.
7. Delete the 1.x code, rewrite the README, and tag `2.0.0`.

## 13. Risks

| Risk | Mitigation |
|---|---|
| Quirks in how TextKit 2 sizes attachment views (bounds tracking, reuse) | Prototype the code and table embeds first in phase 2; `tracksTextAttachmentViewBounds`; fall back to fixed bounds from our own measurement. |
| TextKit 2 estimated heights in a non-scrolling view | `ensureLayout(for: documentRange)` before reporting size; a test asserts the reported height equals the laid-out height. |
| Mask rects drift from glyphs after an edit restyles revealed text | Tail healing prevents most restyles; any edit touching the revealed range recomputes mask rects for the affected lines. |
| Selection UI is masked in unrevealed areas | Acceptable. The selection is clamped to the revealed range anyway. |
| Swift 6 strict concurrency across the C boundary | cmark handles are confined to one parse call; only `Sendable` Swift values cross actors. |
| Budget misses on older devices | The §3 budgets target the iPhone 16 Pro Max. The harness also records an older device for information, without gating on it. |

## 14. Follow-up spec (out of scope)

SuperMe adoption:

- replace `AgentChatNativeMarkdown*`, `AgentChatNativeTrailMask` and `AgentChatNativeCodeHighlighter` with
  `GlimmerView` in the native turn cells;
- port `SFMGlimmerPlugin` to `GlimmerExtension`;
- add a SuperMe theme ported from superme-web's `TokenizedMarkdown` styles;
- replace the SwiftUI `MarkdownView` call sites with `GlimmerText`;
- remove the 12-style streaming settings demo;
- bump the pinned revision in `Packages/Features` and `Packages/Shared`.

Possible SuperMe follow-up, unrelated to Glimmer: an ambient "thinking" backdrop like Gemini's aurora. That is app chrome,
not markdown rendering; SwiftUI's `MeshGradient` or a stitchable Metal shader in `.colorEffect` would suit it.
