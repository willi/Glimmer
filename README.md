# Glimmer

Glimmer renders markdown natively on iOS, and it is built for answers that stream in. Text is laid out once by
TextKit 2 and never reflows. The parser is cmark-gfm, vendored from [swift-cmark](https://github.com/swiftlang/swift-cmark)
(`gfm` branch): the same GitHub Flavored Markdown that `remark-gfm` renders on the web. A streaming answer is revealed phrase by phrase: each phrase
fades in over about 600 ms, paced against the arriving text, the way Gemini's app reveals its answers.

Glimmer 2.0 is a rewrite. See [Migrating from 1.x](#migrating-from-1x).

## Requirements

- iOS 18 or later to run
- Xcode 27 or later (the iOS 27 SDK) to build: on iOS 27 Glimmer renders only the text near the screen through an
  API that SDK introduced
- Swift 6

## Installation

Add Glimmer with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/willi/Glimmer.git", from: "2.0.0"),
]
```

## Quick start (UIKit)

`GlimmerView` is a `UIView`. Size it with Auto Layout (a width constraint gives it an intrinsic height) or with
`sizeThatFits(_:)`.

```swift
let view = GlimmerView()
view.onLinkTap = { url in UIApplication.shared.open(url) }
view.update(markdown: "# Hello\n\nThis is **Glimmer**.")
```

## Streaming

Pass the whole answer received so far, every time. Glimmer parses and composes only what changed, off the main
thread, and reveals the new text phrase by phrase. Use one `revealID` per message: a view re-created for the same
message (a reused cell, say) resumes the reveal instead of replaying it.

```swift
let view = GlimmerView()
let messageID = "message-1"
var received = ""
for chunk in ["Glimmer reveals ", "an answer ", "phrase by phrase."] {
    received += chunk
    view.update(markdown: received, isStreaming: true, revealID: messageID)
}
view.update(markdown: received, isStreaming: false, revealID: messageID)
```

While an answer reveals, the view's height ends at the last revealed line and never shrinks. `onHeightChange` fires
whenever the height may have changed.

## SwiftUI

`GlimmerText` wraps `GlimmerView`:

```swift
struct Answer: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        ScrollView {
            GlimmerText(text, isStreaming: isStreaming, revealID: "message-1") { url in print(url) }
                .padding()
        }
    }
}
```

The configuration is read when the view is created. To apply a different one, give the view a new identity, for
example with `.id(themeVersion)`.

## Configuration

`GlimmerConfiguration` holds everything besides the markdown:

```swift
var configuration = GlimmerConfiguration()
configuration.theme.linkColor = .systemPurple
configuration.reveal = .smooth(GlimmerRevealOptions())
configuration.dataDetectors = [.phoneNumber]
configuration.allowsFind = true
let view = GlimmerView(configuration: configuration)
```

- **`theme`** (`GlimmerTheme`): fonts per role (body, H1–H6, code, table, table header, caption), dynamic colors,
  spacing, and options such as link underlines and the code-block header. Fonts scale with Dynamic Type.
- **`extensions`**: custom syntax. See [Extensions](#extensions).
- **`highlighter`** (`GlimmerHighlighter`): syntax highlighting for code blocks. The default,
  `GlimmerBasicHighlighter`, covers keywords, strings, comments and numbers in common languages.
- **`imageLoader`** (`GlimmerImageLoader`): loads standalone images. `nil` shows each image's alt text in its
  reserved space. A load never shifts the text below, because the space is reserved before the image arrives.
- **`reveal`**: `.smooth(GlimmerRevealOptions())`, with fade duration, pacing and phrase-length options, or `.none`.
  When Reduce Motion is on, text always appears at once.
- **`dataDetectors`**: phone numbers, addresses and so on. Off by default.
- **`allowsFind`**: turns on the system Find interaction. Present it with
  `view.findInteraction?.presentFindNavigator(showingReplace: false)`.

## Extensions

A `GlimmerExtension` can rewrite the markdown before parsing (`preprocess(_:)`) and turn tokens in plain text into
inline chips (`scan(_:)`, with an optional view from `makeInlineView(for:theme:)`). A chip's `source` is what copy
writes, and its `accessibilityLabel` is what VoiceOver reads.

```swift
struct Citations: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            return GlimmerInlineToken(range: range, kind: "citation", displayText: label, source: label,
                                      accessibilityLabel: "Source \(label.dropFirst().dropLast())")
        }
    }
}

var configuration = GlimmerConfiguration()
configuration.extensions = [Citations()]
GlimmerView(configuration: configuration).update(markdown: "As shown [1].")
```

## Copy, selection and menus

Selection runs continuously across a whole answer. Code blocks and tables are selected as a unit, and a code block also
keeps its own selection inside. While an answer reveals, the selection stops at the revealed text.

Copy writes plain text and markdown (`net.daringfireball.markdown`), so a paste into a markdown-aware app keeps
lists, code, emphasis and links. `markdownSource(for:)` gives the markdown for any range, or, with no range, the whole
answer as given. Hosts can add their own edit-menu and link-menu items:

```swift
view.editMenuActions = { selection in
    [UIAction(title: "Ask about this") { _ in print(selection.markdown) }]
}
view.linkMenuActions = { url in [UIAction(title: "Copy Link") { _ in UIPasteboard.general.url = url }] }
```

`GlimmerText` takes the same two hooks.

## Accessibility

- While an answer reveals, VoiceOver reads it as one element whose label is the text revealed so far. When the
  reveal settles, the text view takes over, with line and word navigation and the links rotor.
- Code blocks read "Code, swift", then the code, then a Copy button.
- Tables are data tables with column headers.
- Chips read their extension's `accessibilityLabel`.
- Task-list items say whether they are checked.
- Headings carry their level. A host can group a settled answer into one element by setting
  `isAccessibilityElement`.

## Performance

Measured on an iPhone 16 Pro Max in a Release build, against the spec's budgets. The full tables, the misses and how to
run the harness are in [the Plan 5 results](docs/superpowers/perf/2026-09-26-glimmer-2-plan-5-device-results.md).

| Metric | Budget | iPhone 16 Pro Max |
|---|---|---|
| Applying one streamed update on the main thread, p95 (5,000-word answer) | ≤ 2 ms | 0.48 ms |
| The same, streaming a 150-line code block | ≤ 2 ms | 1.97 ms |
| The same, streaming a 40-row table | ≤ 2 ms | 0.43 ms |
| Finding the last glyph of a 5,000-word answer (most of starting a phrase) | ≤ 0.2 ms | 0.010 ms |
| Hitches while streaming and scrolling a 5,000-word answer (`XCTHitchMetric`) | 0 | 2.3 ms per s ("good" under Apple's 5); 5–9 short drops in 30 s |
| Showing a cached settled answer again (~1,200 words) | ≤ 4 ms | 27 ms (59 ms uncached) |

How it stays fast:

- **Parse and compose on a worker.** Only the open tail of the answer is parsed again, and code is highlighted there
  too. The main thread applies one small edit.
- **A visible band.** TextKit renders only the text near the screen, even in a 5,000-word answer.
- **An unbounded text container.** Finding text late in a long answer takes microseconds, not milliseconds.
- **Core Animation fades.** The reveal is a mask of phrase layers that Core Animation animates, so the main thread
  only starts phrases.
- **Streaming embeds update in place.** A code block applies only its changed lines, and a table keeps the rows it
  already measured.

## Demo app

```bash
open Examples/GlimmerDemo/GlimmerDemo.xcodeproj
```

The demo has four screens:

- **Gallery**: every element, in light and dark, at the default and an accessibility text size.
- **Streaming Lab**: cadence presets, pause and resume, light and dark.
- **Long Answer**: about 5,000 words.
- **Benchmark**: streams below a long answer and counts late frames.

The project is generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `Examples/GlimmerDemo/project.yml`.
Run `xcodegen generate` there after adding or removing demo files. See [Examples/README.md](Examples/README.md).

## Migrating from 1.x

Glimmer 2.0 replaces 1.x's SwiftUI renderer with a native engine, and its API is new.

| 1.x | 2.0 |
|---|---|
| `MarkdownView(markdown:)` | `GlimmerText(_:)` in SwiftUI, `GlimmerView` in UIKit |
| `StreamingMarkdownView`, `GlimmerRevealView` | `GlimmerText(_:isStreaming:revealID:)`, `GlimmerView.update(markdown:isStreaming:revealID:)` |
| `MarkdownConfiguration`, `MarkdownConfigurationBuilder` | `GlimmerConfiguration` and `GlimmerTheme` |
| `MarkdownExtension` | `GlimmerExtension` |
| The 12 reveal styles | One reveal (`.smooth`), or `.none` |

Gone, with no replacement:

- the markdown linter and the exporters;
- the HTML and plain-text renderers (copy still writes plain text and markdown);
- the GitHub mention, issue and SHA extensions (write a `GlimmerExtension`);
- emoji shortcodes;
- the parallel and cached parsers.

## License

Glimmer is available under the MIT license. See [LICENSE](LICENSE). It includes cmark-gfm, whose license is in
[Sources/cmark-gfm/COPYING](Sources/cmark-gfm/COPYING).
