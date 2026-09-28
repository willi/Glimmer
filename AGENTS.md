# Repository Guidelines

Glimmer is an iOS-only Swift package: a TextKit 2 markdown engine for streaming answers, with a vendored cmark-gfm
parser. The design spec is `docs/superpowers/specs/2026-09-25-glimmer-2-engine-design.md`. The implementation plans
and their results are in `docs/superpowers/plans/` and `docs/superpowers/perf/`.

## Project structure

- `Sources/cmark-gfm`, `Sources/cmark-gfm-extensions`: cmark-gfm, vendored unchanged (see `VENDORED.md`).
- `Sources/Glimmer/Engine/`: the engine.
  - `GlimmerView.swift`: the public `UIView`. It owns the text view, the reveal, the worker and height reporting.
  - `GlimmerText.swift`: the SwiftUI wrapper. `GlimmerConfiguration.swift`: everything besides the markdown.
  - `Parse/`: cmark → an immutable, `Sendable` block tree (`GlimmerBlock`, `GlimmerInline`).
  - `Stream/`: the streaming document (committed blocks and an open tail), tail healing, the per-view
    `GlimmerDocumentWorker` actor, and the settled-document cache.
  - `Compose/`: blocks → one `NSAttributedString`, styled by the theme. It also records the markdown structure that
    copy reads back.
  - `Render/`: `GlimmerTextView` (TextKit 2 `UITextView`) and the layout fragments that draw quote bars and
    inline-code pills.
  - `Embeds/`: code blocks, tables, images and rules, shown as attachment views.
  - `Reveal/`: the pacing engine, the phrase chunker, the clock and the Core Animation mask.
  - `Interact/`: copy serialization (`GlimmerMarkdownSerializer`) and `GlimmerSelection`.
  - `Extensions/`, `Highlight/`, `Theme/`, `Resources/` (localized strings).
- `Tests/GlimmerTests/Engine/`: all tests. `EngineTestSupport.swift` has the helpers: `hostInWindow`, `settle`,
  `ManualRevealClock`, `assertEquivalent`, `threadCPUTime`. `Fixtures/CommonMark` holds the spec examples.
- `Examples/GlimmerDemo/`: the demo app. `project.yml` is its XcodeGen spec. `App/` holds the app, `UITests/` its UI
  tests, and `Shared/` code compiled into both.

## Build, test and run

The package is iOS-only; `swift test` on macOS fails. Use a simulator destination with an explicit OS, because a bare
device name is ambiguous when several runtimes are installed:

```bash
DEST='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0'
xcodebuild -scheme Glimmer -destination "$DEST" test
xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerComposerTests
```

- xcodebuild sometimes hangs after printing results. Once the log shows `Test Suite 'Selected tests' passed` (or
  `failed`), kill it.
- The performance gates have Debug and Release budgets. For Release, run:
  `xcodebuild -scheme Glimmer -destination "$DEST" -configuration Release test ENABLE_TESTABILITY=YES -only-testing:GlimmerTests/GlimmerStreamingPerformanceTests`.
  They retry once, but heavy load from other processes can still fail them. Rerun when the machine is quieter before
  believing a regression.
- Demo:

  ```bash
  cd Examples/GlimmerDemo && xcodegen generate
  open GlimmerDemo.xcodeproj
  ```

  After adding, moving or deleting a demo file, run `xcodegen generate` and commit the regenerated project. Launch
  arguments: `--engine-gallery`, `--gallery-dark`, `--gallery-large-text`, `--streaming-lab`, `--benchmark`.
- Demo UI tests: `xcodebuild -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo -destination 'id=<simulator>' test`.
- Device harness, in Release on a connected iPhone that is unlocked:
  - `-scheme GlimmerDevicePerf` runs the package's performance tests, hosted by the demo app. A package test bundle
    can't run on a device by itself.
  - `-scheme GlimmerDemo -only-testing:GlimmerDemoUITests/BenchmarkHitchUITests` runs the benchmark under
    `XCTHitchMetric`.
  - Pass `-configuration Release -allowProvisioningUpdates`.

## Engine rules

- **TextKit 2 only.** Never read `layoutManager` on a text view; it silently switches the view to TextKit 1.
- **The text container is unbounded.** `GlimmerTextView` keeps scrolling enabled but never scrolls (the pan never
  begins, and the offset stays at zero). A finite container height makes late-text lookups linear, and TextKit lays
  out nothing beyond it.
- **Only a band renders.** On iOS 27, `viewportBounds(for:)` limits rendering to the text near the screen. Nothing
  outside that band has a layout or an attachment view, so measure with `laidOutHeight(from:)` and
  `frameForTextAttachment`, not views.
- **Edits are small.** Updates are `GlimmerDocumentEdit`s applied in one editing transaction, trimmed to the
  paragraphs that changed. Never set the whole text during streaming.
- **Main-thread work is measured, not guessed.** With the worker, Core Animation lays out and draws while a test
  awaits. Timers around the test's own calls under-measure, so measure main-thread CPU with `threadCPUTime()`.
- **Accessibility needs the live runtime.** A unit test can't see what VoiceOver sees, because UIKit's accessibility
  runtime isn't active in the test host. Check it with an XCUITest query (see `LaunchUITests`).

## Coding style

- Swift 6 language mode, strict concurrency. Four-space indentation. Types `UpperCamelCase`, members
  `lowerCamelCase`.
- No force unwraps or force casts in library code.
- One type per file where practical, named after the type.
- Keep the public API small and documented: every public declaration has a doc comment.
- Comments say why, not what.

## Testing

- XCTest, with tests in `Tests/GlimmerTests/Engine/<Area>Tests.swift`.
- Write the failing test first and watch it fail.
- Copy changes round-trip: markdown → compose → serialize → compose must give an equivalent text
  (`assertEquivalent`).
- Reading `UIPasteboard.general` in the test runner fails. Use a named pasteboard.

## Commits

- Present-tense summaries ("Engine: stream table rows without rebuilding the table"), with a body that says why.
- Small, focused commits, each leaving the package building and its tests green.
- Include screenshots in PRs when rendering changes.
