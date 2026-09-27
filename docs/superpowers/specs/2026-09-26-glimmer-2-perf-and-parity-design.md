# Glimmer 2.0 — performance and 1.x parity (addendum)

An addendum to `2026-09-25-glimmer-2-engine-design.md`. Glimmer 2.0 is complete on `glimmer-2` (local tag `2.0.0`).
This covers the two pieces of work before SuperMe adopts it:

- **Part A** closes the performance gaps measured on an iPhone 16 Pro Max.
- **Part B** restores the 1.x markdown that SuperMe relies on.

Part A is Plan 6. Part B is Plan 7.

## 1. Why

**Performance.** The Plan 5 device run
(`docs/superpowers/perf/2026-09-26-glimmer-2-plan-5-device-results.md`) missed three §3 criteria:
- zero hitches: the benchmark drops 5–9 frames per 30 s, a hitch-time ratio of 2.3 ms/s;
- a 4 ms cached configure: it measures 27 ms, and about 57 ms once the first draw is counted;
- about zero main-thread work per reveal frame.

A follow-up spike put a probe on the device that recorded every main-thread busy slice and named the steps inside
each dropped frame. It found:

| Cost on the device (Release) | Size | Share of the drops |
|---|---|---|
| `fitTextViewToContent` resizing the text view when a streaming answer outgrows its slack band | up to 9.4 ms, plus 5–9 ms of layout and commit after it | most of them |
| Re-rendering the band while scrolling (`layoutViewport`) | up to 6.7 ms, plus drawing about a screen of new fragments | some |
| Drawing the first band on a configure (three screens tall) | about 52 ms of a 57 ms configure | the configure miss |
| A phrase start (the settled line's 512-character segment query, and re-hashing the answer for resume) | about 1.1 ms | none on its own |
| A code block or table growing by a line or row during a reveal | at most 4.7 ms | none on its own |
| A streaming code block's apply | 1.97–2.20 ms p95 | at the 2 ms budget |

A prose-only reveal costs 0.06 ms of main-thread CPU per frame, which already meets "about zero".

**Parity.** SuperMe's iOS app turns on three 1.x features that 2.0 doesn't have: `@username` mentions, `:emoji:`
shortcodes, and footnotes (on by default in 1.x). 2.0 also dropped images inside a paragraph and seven highlighting
languages. Without footnotes, 2.0 shows `[^1]` as literal text. A one-word footnote
(`[^n]: note`) is worse: CommonMark reads it as a link reference definition, so the note disappears and the marker
becomes a link. superme-web renders footnotes (remark-gfm) but not emoji shortcodes or `@username`. Willi chose to
keep the 1.x behaviour for those two on iOS.

## 2. Goals and non-goals

**Goals**
- On an iPhone 16 Pro Max, streaming below a long answer while scrolling drops no frames. The gate is the benchmark's
  hitch-time ratio ≤ 1 ms/s, with zero hitches as the target.
- A cached settled answer's first frame costs a third or less of today's 57 ms. Its screen draws in the first frame,
  and the rest of the band a frame later.
- A phrase start costs ≤ 0.5 ms median on the device.
- A streaming code block's apply is ≤ 2 ms p95 on the device.
- 2.0 renders footnotes, `:emoji:` shortcodes, `@username` mentions, images inside paragraphs, and code in JSON, SQL,
  YAML, HTML/XML, CSS, C# and PHP. Hosts that relied on these in 1.x lose nothing.

**Non-goals**
- A 4 ms cached configure. That needs a reuse cache of laid-out text views, which is a separate decision.
- GitHub issue, commit, repository and pull-request references. They are opt-in in 1.x and SuperMe keeps them off.
- Inline footnotes (`^[…]`), which remark-gfm doesn't support.
- A sheet when a footnote marker is tapped, which the web doesn't have.
- Math, `==highlight==`, and GitHub alerts. Neither version has them.

## 3. Part A: performance

### A1. The text view never resizes while an answer streams

`GlimmerView` gives its text view a fixed, very large height once, and doesn't change it as the text grows. The view
already reports its own height (the content, or the last revealed line while revealing) and clips to its bounds, so
nothing visible changes. The layout facts that make this safe are already true:
- the text container is unbounded;
- TextKit renders only the band near the screen (iOS 27);
- measurements come from `laidOutHeight(from:)`, never from the frame.

The plan first proves a tall text view is harmless:
- The mask layer and the text view's own layer have no backing store, so size costs no memory.
- Selection, the edit menu, and VoiceOver's line elements keep their frames.
- On iOS 18–26, where the band doesn't exist, nothing lays out beyond the text.

If any check fails, the fallback is geometric growth: double the height when the text outgrows it. Resizes then happen
logarithmically often, rarely rather than never.

### A2. Render in smaller steps

- **Scrolling.** The band re-renders once the screen has moved a quarter screen past the rendered band's edge, not
  half a screen. Each refresh then brings in less new text.
- **Configure.** The first layout after a configure renders only the visible screen. The full band (a screen above
  and below) follows on the next run-loop turn. A cached answer's first frame draws a third of what it does today,
  and the rest is spread over later frames.

### A3. Cheaper phrase starts

- **Settled line.** The mask builds the settled part of the current line from the phrase rects it already holds.
  It asks TextKit only for the line's top when the settled offset moves to a new line, and drops the 512-character
  segment query.
- **Resume.** The reveal store's prefix hash is computed once per text version, not on every wake.

### A4. A streaming code block's apply stays under 2 ms

`GlimmerCodeBlockView.update(to:)` finds the lines to replace by comparing the old and new text and highlight spans,
not by comparing attributed paragraphs. Streaming usually appends, and spans are cheap to compare. A span change on an
earlier line, such as a closing `*/` recolouring the lines above, still reaches TextKit.

### Verification

Every item is measured on the device, with the Plan 5 harness:
- `GlimmerDevicePerf` and the benchmark, both in Release;
- the hands-off benchmark run through `devicectl`;
- the throwaway attribution probe, which is re-applied, not committed, to confirm which slices went away.

The benchmark also gains a flick-speed scroll (about 2,000 pt/s with deceleration) beside its eased scroll, because
the Plan 5 reviewer found the eased one gentler than a reader's flick.

Device gates move to the new baselines with headroom, as Plan 5's review set them.

## 4. Part B: 1.x parity

### B1. Footnotes, as the web renders them

- **Parsing.** Glimmer turns on cmark-gfm's footnote option, so definitions (`[^label]: text`, with indented
  continuation lines and paragraphs) parse as footnote definitions, and references to them as footnote references. A
  one-word definition is no longer read as a link reference definition. A literal `[^label]` left in text, because
  its definition hasn't arrived yet, is treated as a reference too.
- **Markers.** A reference renders as a superscript number: the theme's new `footnoteFont` (default: the caption
  font), baseline-raised, in the link colour. Numbers follow the order of first reference, as remark-gfm does. The marker is not interactive.
- **Notes.** Definitions render after the answer's last block, as a thin rule and then an ordered list of the notes
  in marker order. They use the footnote font and the secondary text colour. There is no "Footnotes" heading on
  screen; remark-gfm's heading is visually hidden too.
- **Streaming.**
  - A marker becomes a superscript the moment `[^label]` completes, whether or not its definition has arrived. Its
    number is fixed by first appearance, so text already revealed never restyles.
  - The healer withholds a trailing `[^…` until it closes.
  - Definitions stay out of the rendered text until the stream settles, and then appear at the end as new text for the
    reveal. Body text keeps arriving after a definition, and rendering the section mid-stream would put unrevealed
    text in front of revealed text.
  - A marker whose definition never arrives stays a superscript.
- **Copy.** Markers write `[^label]` (the original label). The notes write `[^label]: text`, continuation lines
  indented by four spaces.
- **VoiceOver** reads a marker's number as text, as it reads any superscript.

### B2. `:emoji:` shortcodes (opt-in)

- **Where it lives.** `GlimmerEmojiShortcodes`, a built-in `GlimmerExtension` that a host adds to
  `configuration.extensions`. It carries the GitHub shortcode table (about 1,900 entries, restored from 1.x's
  `GitHubEmojis`) as a package resource.
- **Rendering.** A standard shortcode becomes its Unicode emoji in the text. GitHub's custom ones (`:octocat:`,
  `:atom:` and so on) become inline images (B4), from their github.com URLs.
- **Scope.** Only in text: never in code spans, code blocks, or link destinations.
- **Streaming.** While streaming, an unclosed shortcode at the very end (`:rock`) is held back until it closes or
  can't be one, so a revealed `:rock` never turns into 🚀.
- **Copy.** Markdown writes the shortcode and plain text writes the emoji.

### B3. `@username` mentions (opt-in)

- **Where it lives.** `GlimmerMentions`, a built-in `GlimmerExtension`.
- **What matches.** GitHub's rules: `@` followed by letters, digits and single hyphens, up to 39 characters. Not
  inside an email address, code or a link.
- **Rendering.** The mention stays text, in the theme's new `mentionColor` (default: the link colour). It wraps and
  selects like any word.
- **Tapping.** It calls `GlimmerView.onTokenTap`, and `GlimmerText`'s new `onTokenTap`, with the token.
- **Copy** writes `@username`.

This needs one API addition: an extension token can be text, not only a chip.

```swift
public struct GlimmerInlineToken {
    // existing: range, kind, payload, displayText, source, accessibilityLabel
    public var presentation: Presentation = .chip

    public enum Presentation: Sendable, Equatable {
        /// The extension's view, or a label with `displayText` (today's behaviour).
        case chip
        /// `displayText` as text; with `tappable`, in the theme's mention colour and reported through `onTokenTap`.
        case text(tappable: Bool)
        /// An inline image from `url` (B4), with `displayText` as its alt text.
        case image(URL)
    }
}
```

- `GlimmerMentions` produces `.text(tappable: true)`.
- `GlimmerEmojiShortcodes` produces `.text(tappable: false)`, or `.image` for custom emoji.
- Copy and VoiceOver treat every presentation like a chip: markdown writes `source`, plain text writes `displayText`,
  and VoiceOver reads `accessibilityLabel ?? displayText`.

### B4. Images inside a paragraph

- **Layout.** An image inside a paragraph is an inline attachment: a square the height of the surrounding line. The
  image is loaded through `configuration.imageLoader` and aspect-fitted inside the square. Until it loads, or if it
  fails, the square shows the theme's placeholder tint.
- **No reflow.** The square never changes size, so a load never moves text. That meets the spec's §4.3 promise that
  a finished load never shifts later text. The cost is that wide images, such as badges, appear small.
- **Scope.** A paragraph holding only an image stays a standalone embed, as today.
- **Copy** writes `![alt](url)`, plain text writes the alt text, and VoiceOver reads the alt text.

### B5. Seven more highlighting languages

`GlimmerBasicHighlighter` gains families for JSON, SQL, YAML, HTML/XML, CSS, C# and PHP, with keywords, strings,
comments and numbers as the existing families have. Its regular expressions compile once per family, in a static
table, rather than on every call. That was Plan 5's deferred minor, and it now matters because highlighting runs on
every streamed update.

### Tests

Each item gets:
- a composer test;
- a stream-versus-settled parity test on a fixture that uses it;
- a stability test: every prefix streamed, with no revealed glyph moving;
- a copy round-trip test.

Footnotes also get:
- the one-word definition that 2.0 used to swallow;
- a reference whose definition never arrives;
- definitions in the middle of an answer.

The gallery gains a section for each item, in light and dark.

### Theme and API additions

- `GlimmerTheme`: `footnoteFont` (default: the caption font) and `mentionColor` (default: the link colour).
- `GlimmerInlineToken.presentation`.
- `GlimmerView.onTokenTap: ((GlimmerInlineToken) -> Void)?`, and `GlimmerText`'s `onTokenTap` parameter.
- Two built-in extensions: `GlimmerEmojiShortcodes` and `GlimmerMentions`.

## 5. Risks

| Risk | Mitigation |
|---|---|
| A very tall text view upsets UIKit: VoiceOver frames, the selection loupe, scroll-to-visible | A1's checks run first. Geometric growth is the fallback. |
| Holding back an unclosed `:shortcode` or `[^…` makes the reveal wait on ordinary text with colons | Hold back only a candidate that is still at the very end of the stream and at most 40 characters long. Anything longer, or containing a space, is released. |
| Rendering footnote definitions only at settle surprises a host that shows a stream with no end | Definitions still appear when the host passes `isStreaming: false`. The README says so. |
| Inline images in a line-height square look too small for some content | The square matches 1.x's emoji-sized inline images. A standalone image line is the way to show a large image. |

## 6. Delivery

- **Plan 6: Part A.** Measured on the device after each item.
- **Plan 7: Part B.** One task per item. B4 lands before B2, because custom emoji use inline images.
- Then SuperMe adoption (the original spec's §14), which turns on `GlimmerEmojiShortcodes` and `GlimmerMentions`.
