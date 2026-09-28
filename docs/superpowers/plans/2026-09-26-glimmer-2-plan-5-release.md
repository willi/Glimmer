# Glimmer 2.0 — Plan 5: Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Glimmer 2.0. Delete 1.x, finish the two §4.2 streaming costs, measure spec §3 on an iPhone 16 Pro Max, rebuild the demo around the engine, close the loose ends from Plans 1–4, rewrite the docs, and tag `2.0.0`.

**Architecture:** XcodeGen generates the demo project (`Examples/GlimmerDemo/project.yml`), so it gains a UI-test target. With that target, `XCTHitchMetric` runs against a benchmark screen on the device. The streaming code block's highlighting moves into the composer: the embed carries its highlighted text from the worker, and the main thread only applies the changed lines. A streaming table keeps the labels and measurements of rows that did not change. 1.x (52 source files, about 37,000 lines, plus its tests, resource and demo screens) is deleted outright.

**Tech Stack:** Swift 6, iOS 18+ (the UI-test target needs iOS 26 for `XCTHitchMetric`), UIKit, TextKit 2, XCTest, XCUITest, XcodeGen 2.x.

**Spec:** `docs/superpowers/specs/2026-09-25-glimmer-2-engine-design.md` (§3 success criteria, §4.2 highlighting, §10 deleted in 2.0 and the demo, §11 performance and visual testing, §12 phases 6–7)

**Builds on:** Plans 1–4, complete on `glimmer-2` (HEAD `51e1fc5`). Plan 4's review is fixed; its deferred minors are Tasks 7–8 here.

**Rulings carried in this plan:**
- *"Only on closed code lines" (§4.2).* The composer highlights a streaming code block's whole code on the worker, open last line included. A closing `*/` can recolor earlier lines, so highlighting a prefix would still need the whole text. Once highlighting is off the main thread, the open line's cost doesn't matter. The main thread still receives only the lines whose text or colors changed.
- *Settled answers compose on main.* `update(markdown:)` for a settled answer composes synchronously, so a host can size it in the same layout pass (Plan 3). That compose highlights on main, and the document cache makes it a once-per-answer cost. Only the streaming path is required to keep highlighting off main.
- *An older device (§13).* None is connected. The harness records only the iPhone 16 Pro Max, and the results doc says so.
- *`xctrace` head-to-head with Gemini (§11).* Skipped: `xctrace` hangs in this environment (see the SuperMe profiling notes), and the Gemini teardown already gives Gemini's ~3 ms per tick. The benchmark's own frame monitor and `XCTHitchMetric` are the evidence.
- *`height(forWidth:)` resizing the text view for a size query at another width during a reveal (Plan 2).* It changes only if Task 6's device run shows hitches while SwiftUI sizes a streaming answer.
- *A fading unit falling back to its whole box when its embed view was never made (Plan 3).* It stays: that happens only off screen, and it corrects itself when the view appears.

## Global Constraints

- The branch is `glimmer-2`. Commit after every task. **Do not add `Co-Authored-By` trailers. Do not push, and do not push the tag.**
- Swift 6 language mode, iOS 18 minimum for the library and the demo app, no package dependencies. The UI-test target's deployment target is iOS 26.0.
- **TextKit 2 only.** Never read `layoutManager`.
- No force unwrapping (`!`) and no force casts in library code. Tests may force-unwrap.
- In tests, write `CGFloat.greatestFiniteMagnitude`, never `.greatestFiniteMagnitude`, in `CGSize(width: <literal>, …)`.
- Library test command, with a passing run ending in `** TEST SUCCEEDED **`:
  ```bash
  DEST='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0'
  xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/<TestClass> 2>&1 | tail -5
  ```
  xcodebuild sometimes hangs after printing results; kill it once the log shows `Test Suite 'Selected tests' passed|failed`. Run one xcodebuild at a time.
- The **engine suite** is every class in `Tests/GlimmerTests/Engine/` whose file name ends in `Tests.swift`. After Task 2 it is the whole test target.
- **Demo:** the project is generated. After adding, moving or deleting a demo file, run `xcodegen generate` in `Examples/GlimmerDemo` and commit the regenerated `GlimmerDemo.xcodeproj` with the change. Build and UI-test the demo on simulator `69D2BAC9-1BB2-4A2A-A361-3150710B8462` (iPhone 18 Pro, iOS 27.2) with `-derivedDataPath .build/demo-dd`:
  ```bash
  xcodebuild -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo \
    -destination 'id=69D2BAC9-1BB2-4A2A-A361-3150710B8462' -derivedDataPath .build/demo-dd test 2>&1 | tail -5
  ```
- **Device:** "WW 16", an iPhone 16 Pro Max, UDID `00008140-00044C9001F3001C`. Signing is automatic with team `RUV7V2TGVX`; pass `-allowProvisioningUpdates`. Never enter a password or any credential. If a device run needs one, or the device is locked or unavailable, ledger it, write the exact command into the results doc for Willi, and continue.
- Check free disk space (`df -h /`) before the first build of each task. Delete only `.build/demo-dd` if space runs short; a full disk once purged simulator runtimes.

## Review Focus

These are the five inputs the spec implies but no earlier test exercises, ordered from most likely to bite a real user down. Each has a test in the task that owns the code.

1. **A streaming code block whose later line changes earlier lines' colors** (a `/*` closed a few lines later) → the earlier lines recolor, with highlighting still off the main thread. Test: Task 3 `testAClosingCommentRecolorsEarlierLines`.
2. **A streamed table row that widens a column** → earlier rows are measured again at the new column widths, so nothing is clipped or overlaps. Test: Task 4 `testIncrementalLayoutMatchesAFreshTable`.
3. **The last table row growing in place** (a cell's text lengthens, a ragged row gains a cell) → that row's labels update rather than being kept as unchanged. Test: Task 4 `testALastRowThatGrowsInPlaceUpdates`.
4. **A text-size or configuration change while an answer reveals** (the lab's controls, Dynamic Type) → the answer restyles in place and keeps revealing from where it was, without replaying. Test: Task 5 `testRestylingMidRevealKeepsRevealing`.
5. **The benchmark on a 60 Hz screen** (Low Power Mode, or a non-ProMotion phone) → frames are judged against the display's actual frame duration, so a steady 60 Hz run reports no hitches. Test: Task 6 `FrameHitchCounterTests.testASteadySixtyHertzRunHasNoHitches`.

---

## File Structure

```
Package.swift                                        MODIFY  drop the emoji resource; defaultLocalization "en" (T2, T8)
Sources/Glimmer/                                     DELETE  everything except Engine/ (T2)
Sources/Glimmer/Engine/
  Highlight/GlimmerCodeHighlighting.swift            CREATE  highlighted code, off the main actor (T3)
  Embeds/GlimmerEmbed.swift                          MODIFY  codeBlock carries its highlighted text (T3)
  Embeds/GlimmerBlockAttachment.swift                MODIFY  factory passes the highlight (T3)
  Embeds/GlimmerCodeBlockView.swift                  MODIFY  uses the embed's highlight; localized strings (T3, T8)
  Embeds/GlimmerTableView.swift                      MODIFY  incremental rows and layout; lazy accessibility cells (T4)
  Compose/GlimmerComposer.swift                      MODIFY  highlights code; list tightness per level; checkbox state (T3, T7, T8)
  Theme/GlimmerAttributeKeys.swift                   MODIFY  glimmerListTightness, glimmerListOpens replace glimmerTightList (T7)
  Interact/GlimmerMarkdownSerializer.swift           MODIFY  separators, per-line escapes, cosmetics, accessibility text (T7, T8)
  GlimmerView.swift                                  MODIFY  findInteraction, host accessibility grouping, band refresh without animation (T8)
  GlimmerText.swift                                  MODIFY  editMenuActions, linkMenuActions (T5)
  Resources/Localizable.xcstrings                    CREATE  the library's three strings (T8)
Tests/GlimmerTests/*.swift (outside Engine/)         DELETE  1.x tests (T2)
Tests/GlimmerTests/Engine/
  GlimmerCodeHighlightingTests.swift                 CREATE  (T3)
  GlimmerTableViewTests.swift                        MODIFY  (T4)
  GlimmerViewStreamingTests.swift                    MODIFY  (T5)
  GlimmerTextTests.swift                             CREATE  (T5)
  GlimmerStreamingPerformanceTests.swift             MODIFY  embed budget at the spec's 2 ms; reveal cost per frame (T4, T6)
  GlimmerMarkdownSerializerTests.swift               MODIFY  (T7)
  GlimmerComposerTests.swift, GlimmerThemeTests.swift MODIFY  (T7, T8)
  GlimmerAccessibilityTests.swift                    MODIFY  (T8)
  GlimmerReadmeExampleTests.swift                    CREATE  the README's code, compiled (T9)
Examples/
  Package.swift, GlimmerDemo.xcodeproj (outer)       DELETE  unused wrapper package and stale project (T1)
  README.md                                          REWRITE (T9)
  GlimmerDemo/project.yml                            CREATE  XcodeGen spec (T1)
  GlimmerDemo/GlimmerDemo.xcodeproj                  REGENERATE (T1, then every demo task)
  GlimmerDemo/App/*.swift, Assets.xcassets           MOVE from GlimmerDemo/ (T1); 1.x screens deleted (T2)
  GlimmerDemo/App/BenchmarkDemo.swift, FrameMonitor.swift  CREATE (T6)
  GlimmerDemo/Shared/FrameHitchCounter.swift         CREATE  compiled into the app and the UI tests (T6)
  GlimmerDemo/UITests/*.swift                        CREATE  launch, frame counter, hitch benchmark (T1, T6)
docs/superpowers/perf/2026-09-26-glimmer-2-plan-5-device-results.md  CREATE (T6)
README.md, CLAUDE.md, AGENTS.md                      REWRITE for 2.0 (T9)
```

---

### Task 1: A generated demo project with a UI-test target

**Files:**
- Create: `Examples/GlimmerDemo/project.yml`, `Examples/GlimmerDemo/UITests/LaunchUITests.swift`
- Move: `Examples/GlimmerDemo/*.swift` and `Examples/GlimmerDemo/Assets.xcassets` → `Examples/GlimmerDemo/App/`
- Regenerate: `Examples/GlimmerDemo/GlimmerDemo.xcodeproj`; generated `Examples/GlimmerDemo/App/Info.plist`
- Delete: `Examples/GlimmerDemo.xcodeproj` (a stale second project), `Examples/Package.swift` (a package wrapping the demo sources, which nothing builds)
- Modify: `CLAUDE.md` (its note on the explicit source list)

**Interfaces:**
- Produces:
  - Scheme `GlimmerDemo`, which builds the app and tests with `GlimmerDemoUITests`.
  - Source folders `App/` (app only), `Shared/` (app and UI tests) and `UITests/`.
  - Bundle IDs `dk.wu.GlimmerDemo` and `dk.wu.GlimmerDemoUITests`.

The current demo project lists every source file by hand, and adding a UI-test target to a hand-written `project.pbxproj` is error-prone. XcodeGen generates both targets from a short spec. The generated project is committed, so opening the demo never needs XcodeGen.

- [ ] **Step 1: Write the failing UI test**

Create `Examples/GlimmerDemo/UITests/LaunchUITests.swift`:

```swift
import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func testEngineGalleryOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["--engine-gallery"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Engine Gallery"].waitForExistence(timeout: 15))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run the demo test command from Global Constraints. Expected: FAIL. The current scheme has no test action ("Scheme GlimmerDemo is not currently configured for the test action").

- [ ] **Step 3: Move the sources and write the XcodeGen spec**

```bash
cd Examples/GlimmerDemo && mkdir -p App Shared UITests
git mv *.swift Assets.xcassets App/
git rm -r -q ../GlimmerDemo.xcodeproj ../Package.swift
```

Create `Examples/GlimmerDemo/project.yml`:

```yaml
name: GlimmerDemo
options:
  bundleIdPrefix: dk.wu
  deploymentTarget:
    iOS: "18.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    DEVELOPMENT_TEAM: RUV7V2TGVX
    CODE_SIGN_STYLE: Automatic
packages:
  Glimmer:
    path: ../..
targets:
  GlimmerDemo:
    type: application
    platform: iOS
    sources:
      - path: App
      - path: Shared
    dependencies:
      - package: Glimmer
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Glimmer
        UILaunchScreen: {}
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        # ProMotion: without this key an iPhone app is capped at 60 Hz, which would hide hitches at 120 Hz.
        CADisableMinimumFrameDurationOnPhone: true
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dk.wu.GlimmerDemo
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        TARGETED_DEVICE_FAMILY: "1,2"
  GlimmerDemoUITests:
    type: bundle.ui-testing
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: UITests
      - path: Shared
    dependencies:
      - target: GlimmerDemo
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dk.wu.GlimmerDemoUITests
        GENERATE_INFOPLIST_FILE: YES
        TEST_TARGET_NAME: GlimmerDemo
schemes:
  GlimmerDemo:
    build:
      targets:
        GlimmerDemo: all
        GlimmerDemoUITests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - GlimmerDemoUITests
    profile:
      config: Release
    archive:
      config: Release
```

`Shared/` is empty until Task 6. XcodeGen accepts an empty source folder; if it doesn't, add `Shared/.gitkeep` and ledger it.

Then generate:

```bash
cd Examples/GlimmerDemo && xcodegen generate
```

In `CLAUDE.md`, replace the bullet that starts `**Demo app sources**` with:

```markdown
- **Demo app**: `Examples/GlimmerDemo/GlimmerDemo.xcodeproj` is generated by XcodeGen from `Examples/GlimmerDemo/project.yml`. After adding, moving or deleting a demo file, run `xcodegen generate` in `Examples/GlimmerDemo` and commit the regenerated project.
```

- [ ] **Step 4: Run to verify it passes**

Run the demo test command. Expected: `testEngineGalleryOpens` passes. Also launch the app with no arguments and screenshot it: the demo list appears, as before.

- [ ] **Step 5: Engine suite and commit**

Run the engine suite. Expected: all pass (the library is unchanged).

```bash
git add -A Examples CLAUDE.md
git commit -m "Demo: generate the project with XcodeGen and add a UI-test target

The hand-maintained project listed every source file; a generated one picks
up App/, Shared/ and UITests/ and carries a UI-test target for the device
harness. The stale second project and the unused wrapper package are gone.
The app opts into 120 Hz with CADisableMinimumFrameDurationOnPhone."
```

---

### Task 2: Delete 1.x

**Files:**
- Delete from `Sources/Glimmer/`: `Export/`, `Glimmer.swift`, `Linter/`, `MarkdownConfiguration.swift`, `MarkdownConfigurationBuilder.swift`, `MarkdownExtension.swift`, `Parser/`, `Rendering/`, `Resources/`, `Reveal/`, `Utilities/`, `Views/`
- Delete: every `Tests/GlimmerTests/*.swift` outside `Engine/` (keep `Tests/GlimmerTests/Fixtures/CommonMark`, used by `SpecExamples`)
- Delete from `Examples/GlimmerDemo/App/`:
  - `EdgeCasesDemo.swift`, `EditorTextView.swift`, `GFMDemo.swift`, `GitHubEmojiDemo.swift`, `GlimmerDemo.swift`
  - `InlineImageDemo.swift`, `LinterDemoView.swift`, `LivePreviewDemo.swift`, `MainDemos.swift`
  - `ParallelParsingDemo.swift`, `QuickExampleView.swift`, `StreamingRevealDemo.swift`, `TappableImageExample.swift`
- Modify: `Package.swift` (drop the resource), `Examples/GlimmerDemo/App/ContentView.swift`, `Examples/GlimmerDemo/App/GlimmerDemoApp.swift`

**Interfaces:**
- Produces: a `Glimmer` module whose public API is only the 2.0 engine.

Spec §10 lists what goes. Nothing in `Engine/` references a 1.x type (checked by name while writing this plan), so the deletion needs no engine change.

- [ ] **Step 1: Record the 1.x surface (the "failing" check)**

```bash
grep -rlE "MarkdownView|StreamingMarkdownView|RevealStyle|MarkdownLinter|ParallelMarkdownParser|GlimmerTrailTextView" Sources Examples Tests | wc -l
```

Expected: well over zero. This check is the task's test: Step 3 must bring it to zero.

- [ ] **Step 2: Delete**

```bash
cd Sources/Glimmer && git rm -r -q Export Glimmer.swift Linter MarkdownConfiguration.swift MarkdownConfigurationBuilder.swift \
  MarkdownExtension.swift Parser Rendering Resources Reveal Utilities Views && cd ../..
find Tests/GlimmerTests -maxdepth 1 -name "*.swift" -exec git rm -q {} +
cd Examples/GlimmerDemo/App && git rm -q EdgeCasesDemo.swift EditorTextView.swift GFMDemo.swift GitHubEmojiDemo.swift \
  GlimmerDemo.swift InlineImageDemo.swift LinterDemoView.swift LivePreviewDemo.swift MainDemos.swift \
  ParallelParsingDemo.swift QuickExampleView.swift StreamingRevealDemo.swift TappableImageExample.swift && cd ../../..
```

In `Package.swift`, remove the `resources:` argument (and its comment) from the `Glimmer` target.

Replace `Examples/GlimmerDemo/App/ContentView.swift` with:

```swift
import SwiftUI

/// The demo's screens: every element, streaming by hand, and a long answer.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Gallery", destination: EngineGalleryDemo())
                NavigationLink("Streaming Lab", destination: StreamingLabDemo())
                NavigationLink("Long Answer", destination: LongAnswerDemo())
            }
            .navigationTitle("Glimmer")
        }
    }
}
```

In `GlimmerDemoApp.swift`, delete the `--reveal-demo` branch (it opened the deleted 1.x `StreamingRevealDemo`). Then run `xcodegen generate` in `Examples/GlimmerDemo`.

- [ ] **Step 3: Verify**

Run the Step 1 command again. Expected: `0`. Then run:
- `git grep -n "emoji_urls" -- Package.swift Sources`. Expected: nothing.
- The engine suite, now the whole test target. Expected: all pass. Record the count in the ledger.
- The demo test command. Expected: `testEngineGalleryOpens` passes.

- [ ] **Step 4: Commit**

```bash
git add -A Package.swift Sources Tests Examples
git commit -m "Delete Glimmer 1.x

The Swift parser, the parallel, cached and streaming parsers, the
AttributedString, HTML and plain-text renderers, the SwiftUI views, the 12
reveal styles and their drivers, the linter, the exporter, the GitHub
extensions, the emoji tables, their tests and the 1.x demo screens (spec
§10). Glimmer is now the TextKit 2 engine alone."
```

---

### Task 3: Highlighting on the worker

**Files:**
- Create: `Sources/Glimmer/Engine/Highlight/GlimmerCodeHighlighting.swift`
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerEmbed.swift`, `Embeds/GlimmerCodeBlockView.swift`, `Embeds/GlimmerBlockAttachment.swift` (factory), `Compose/GlimmerComposer.swift` (`.codeBlock` case), `Interact/GlimmerMarkdownSerializer.swift` (pattern)
- Modify tests that pattern-match `.codeBlock`: `GlimmerComposerTests.swift`, `GlimmerStreamingDocumentTests.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerCodeHighlightingTests.swift`

**Interfaces:**
- Produces:
  - `enum GlimmerCodeHighlighting { static func highlightedCode(_ code: String, language: String?, theme: GlimmerTheme, highlighter: any GlimmerHighlighter) -> NSAttributedString }`, nonisolated.
  - `GlimmerEmbed.codeBlock(language: String?, code: String, highlighted: NSAttributedString? = nil)`.
  - `GlimmerCodeBlockView.init(code:language:theme:highlighter:highlighted:)`, where `highlighted` defaults to `nil`, meaning the view highlights the code itself.

- [ ] **Step 1: Write the failing tests**

Create `Tests/GlimmerTests/Engine/GlimmerCodeHighlightingTests.swift`:

```swift
import UIKit
import XCTest
@testable import Glimmer

/// The basic highlighter, counting the calls made on the main thread.
final class ThreadRecordingHighlighter: GlimmerHighlighter, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let base = GlimmerBasicHighlighter()

    var mainThreadCalls: Int { lock.withLock { calls } }

    func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan] {
        if Thread.isMainThread { lock.withLock { calls += 1 } }
        return base.highlight(code, language: language)
    }
}

@MainActor
final class GlimmerCodeHighlightingTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func streamingView(highlighter: any GlimmerHighlighter) -> (GlimmerView, UIWindow) {
        var configuration = GlimmerConfiguration(imageLoader: nil, highlighter: highlighter)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        return (view, hostInWindow(view, width: 390, height: 800))
    }

    func testStreamingCodeIsNeverHighlightedOnMain() async throws {
        let highlighter = ThreadRecordingHighlighter()
        let (view, window) = streamingView(highlighter: highlighter)
        var markdown = "Here:\n\n```swift\n"
        for line in 1...20 {
            markdown += "let value\(line) = \(line) // line \(line)\n"
            view.update(markdown: markdown, isStreaming: true)
            await view.pendingDocument?.value
            settle(view)
        }
        XCTAssertNotNil(findSubview(GlimmerCodeBlockView.self, in: view), "the code view was made on main")
        XCTAssertEqual(highlighter.mainThreadCalls, 0)
        _ = window
    }

    func testAClosingCommentRecolorsEarlierLines() async throws {
        let (view, window) = streamingView(highlighter: GlimmerBasicHighlighter())
        view.update(markdown: "```c\n/* a\nb\n", isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        view.update(markdown: "```c\n/* a\nb\n*/\nint c;\n", isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let code = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view)).textView.textStorage
        let string = code.string as NSString
        let color = { (word: String) in code.attribute(.foregroundColor, at: string.range(of: word).location, effectiveRange: nil) as? UIColor }
        XCTAssertEqual(color("b"), theme.syntaxCommentColor, "inside the now-closed comment")
        XCTAssertEqual(color("int"), theme.syntaxKeywordColor, "after it")
        _ = window
    }

    func testTheComposerHighlightsTheEmbed() throws {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse("```swift\nlet x = 1\n```"))
        let attachment = try XCTUnwrap(blockAttachments(in: text).first)
        guard case .codeBlock(_, _, let highlighted) = attachment.embed else { return XCTFail("expected code") }
        let keyword = try XCTUnwrap(highlighted).attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(keyword, theme.syntaxKeywordColor)
    }
}
```

`testAClosingCommentRecolorsEarlierLines` passes before this task too, because the view re-highlights the whole code on main today. It guards the move (Review Focus 1). The other two fail.

- [ ] **Step 2: Run to verify**

Run the test command for `GlimmerCodeHighlightingTests`. Expected: compile error in `testTheComposerHighlightsTheEmbed` (`.codeBlock` has two associated values). With that test commented out, `testStreamingCodeIsNeverHighlightedOnMain` fails with a main-thread count above 20 and the recolor test passes. Restore the test.

- [ ] **Step 3: Move highlighting out of the view**

Create `Sources/Glimmer/Engine/Highlight/GlimmerCodeHighlighting.swift`, moving `highlightedCode` and `color(for:theme:)` out of `GlimmerCodeBlockView` unchanged apart from their home:

```swift
import UIKit

/// Styled code for a code block. Pure and nonisolated: the composer calls it on the view's worker while an answer
/// streams, and the code view only when it was given no highlight.
enum GlimmerCodeHighlighting {
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

In `GlimmerEmbed`:

```swift
    /// `highlighted` is the code styled by the composer on the worker; nil makes the view highlight it.
    case codeBlock(language: String?, code: String, highlighted: NSAttributedString? = nil)
```

and update its patterns: `case let (.codeBlock(language, code, _), .codeBlock(oldLanguage, oldCode, _)):` in `continues`, and `case .codeBlock(_, let code, _):` in `revealUnitLengths`. Update the serializer's `plainText(of:)` pattern the same way, and the two tests' patterns (`case .codeBlock(let language, let code, _)`, `case .codeBlock(_, let code, _)`, `case .codeBlock(let language, _, _)`).

In `GlimmerComposer.append`, `.codeBlock` case:

```swift
        case .codeBlock(let language, let code):
            let highlighted = GlimmerCodeHighlighting.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
            appendEmbed(.codeBlock(language: language, code: code, highlighted: highlighted),
                        source: Self.fencedSource(code, language: language), context: context, marker: marker, to: output)
```

In `GlimmerEmbedViewFactory.makeView`:

```swift
        case .codeBlock(let language, let code, let highlighted):
            return GlimmerCodeBlockView(code: code, language: language, theme: attachment.theme,
                                        highlighter: attachment.highlighter, highlighted: highlighted)
```

In `GlimmerCodeBlockView`:
- `init` gains `highlighted: NSAttributedString? = nil`, and starts with `self.highlighted = highlighted ?? GlimmerCodeHighlighting.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)`.
- `update(to:)` becomes:

```swift
    func update(to embed: GlimmerEmbed) {
        guard case .codeBlock(let language, let code, let highlighted) = embed,
              code != self.code || language != self.language else { return }
        self.code = code
        self.language = language
        let old = self.highlighted
        self.highlighted = highlighted
            ?? GlimmerCodeHighlighting.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
        let edit = GlimmerStreamingDocument.trimmingUnchangedParagraphs(
            of: GlimmerDocumentEdit(range: NSRange(location: 0, length: old.length), replacement: self.highlighted), in: old
        )
        textView.apply(edit)
        metricsStorage.performEditingTransaction {
            metricsStorage.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        let unchangedLines = (old.string as NSString).substring(to: edit.range.location).filter { $0 == "\n" }.count
        measureLines(fromLine: unchangedLines, at: edit.range.location)
        setNeedsLayout()
    }
```

- Delete the view's own `highlightedCode` and `color(for:theme:)`. Update the doc comment above `update(to:)`: the composer highlights the whole code on the worker (a closing `*/` can recolor earlier lines, and hosts bring their own highlighters), and only the lines whose text or colors changed reach TextKit.

- [ ] **Step 4: Run to verify they pass**

Run the test command for `GlimmerCodeHighlightingTests`, `GlimmerCodeBlockViewTests`, `GlimmerComposerTests`, `GlimmerStreamingDocumentTests`, `GlimmerStreamParityTests` and `GlimmerTextViewTests`. Expected: PASS.

- [ ] **Step 5: Engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: highlight streaming code on the worker

The composer styles a code block's code on the view's worker and the embed
carries it, so a streaming code block's main-thread work is applying the
lines that changed (spec §4.2)."
```

---

### Task 4: Tables stream row by row

**Files:**
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerTableView.swift`
- Modify: `Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift` (the embed budget)
- Test: `Tests/GlimmerTests/Engine/GlimmerTableViewTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `GlimmerTableView.update(to:)` keeps the labels, natural widths and row heights of the rows before the first changed one.

A streamed row today rebuilds every label, and the next layout measures every cell. From now on, only the rows from the first changed one onward are rebuilt and measured. The earlier rows keep their measurements while the column widths hold. When a new row changes the column widths, every row is measured again.

- [ ] **Step 1: Write the failing tests**

Append to `GlimmerTableViewTests`:

```swift
    private func cell(_ text: String) -> NSAttributedString { NSAttributedString(string: text) }

    func testAppendingARowKeepsEarlierLabels() {
        let header = [cell("Name"), cell("Value")]
        let rows = (1...3).map { [cell("row \($0)"), cell("\($0)")] }
        let table = GlimmerTableView(header: header, rows: rows, alignments: [.none, .none], theme: .default)
        let before = table.cellLabels.flatMap { $0 }
        table.update(to: .table(header: header, rows: rows + [[cell("row 4"), cell("4")]], alignments: [.none, .none]))
        XCTAssertEqual(table.cellLabels.count, 5)
        XCTAssertTrue(zip(before, table.cellLabels.prefix(4).flatMap { $0 }).allSatisfy { $0 === $1 }, "earlier rows keep their labels")
        XCTAssertEqual(table.cellLabels[4][0].attributedText?.string, "row 4")
        XCTAssertEqual((table.accessibilityElements ?? []).count, 10, "the new row reaches VoiceOver")
    }

    func testIncrementalLayoutMatchesAFreshTable() {
        let header = [cell("Name"), cell("Value")]
        var rows = (1...3).map { [cell("row \($0)"), cell("\($0)")] }
        let table = GlimmerTableView(header: header, rows: rows, alignments: [.none, .none], theme: .default)
        _ = table.layout(forWidth: 300)
        rows.append([cell("a much longer name that widens the first column and wraps"), cell("4")])
        table.update(to: .table(header: header, rows: rows, alignments: [.none, .none]))
        let fresh = GlimmerTableView(header: header, rows: rows, alignments: [.none, .none], theme: .default)
        XCTAssertEqual(table.layout(forWidth: 300), fresh.layout(forWidth: 300))
    }

    func testALastRowThatGrowsInPlaceUpdates() {
        let header = [cell("a"), cell("b")]
        let table = GlimmerTableView(header: header, rows: [[cell("1"), cell("2")]], alignments: [.none, .none], theme: .default)
        table.update(to: .table(header: header, rows: [[cell("1"), cell("23")]], alignments: [.none, .none]))
        XCTAssertEqual(table.cellLabels[1][1].attributedText?.string, "23")
        let ragged = GlimmerTableView(header: header, rows: [[cell("1")]], alignments: [.none, .none], theme: .default)
        ragged.update(to: .table(header: header, rows: [[cell("1"), cell("2")]], alignments: [.none, .none]))
        XCTAssertEqual(ragged.cellLabels[1][1].attributedText?.string, "2")
        XCTAssertEqual(ragged.layout(forWidth: 300),
                       GlimmerTableView(header: header, rows: [[cell("1"), cell("2")]], alignments: [.none, .none], theme: .default)
                           .layout(forWidth: 300))
    }
```

- [ ] **Step 2: Run to verify**

Run the test command for `GlimmerTableViewTests`. Expected: `testAppendingARowKeepsEarlierLabels` FAILS, because every label is replaced. The other two pass already: the full rebuild is correct, and they guard the incremental path (Review Focus 2 and 3).

- [ ] **Step 3: Incremental rows**

In `GlimmerTableView`, add:

```swift
    /// Per row, each cell's natural width (padded, capped); kept for rows that did not change.
    private var naturalRowWidths: [[CGFloat]] = []
    /// Row heights and the column widths they were measured at; kept for rows that did not change while the widths
    /// hold.
    private var measuredRows: (columnWidths: [CGFloat], heights: [CGFloat])?
    /// Built when VoiceOver first asks, and again after a change.
    private var cellElementsCache: [[GlimmerTableCellElement]]?
```

Replace `cellElements` with a computed property that builds `cellElementsCache` on demand from `cellLabels`. Make `rebuildCells` set `cellElementsCache = nil`, `naturalRowWidths = []` and `measuredRows = nil` instead of building elements.

Replace the `update(to:)` body after its `guard !unchanged else { return }` (keep the padded comparison from Plan 4) with:

```swift
        guard alignments == self.alignments, incoming.first?.count == cells.first?.count else {
            // The columns changed (a header cell or an alignment): rebuild.
            self.alignments = alignments
            rebuildCells(header: header, rows: rows)
            cachedLayout = nil
            setNeedsLayout()
            return
        }
        let firstChanged = zip(incoming, cells).firstIndex { new, old in !zip(new, old).allSatisfy { $0.isEqual(to: $1) } }
            ?? min(incoming.count, cells.count)
        // Rows from the first change: update labels in place, add labels for new rows, drop labels for removed rows.
        for row in firstChanged..<incoming.count {
            if row < cellLabels.count {
                for (column, text) in incoming[row].enumerated() where !text.isEqual(to: cells[row][column]) {
                    cellLabels[row][column].attributedText = text
                }
            } else {
                cellLabels.append(incoming[row].enumerated().map { column, text in makeLabel(text, column: column) })
            }
        }
        for label in cellLabels.dropFirst(incoming.count).joined() { label.removeFromSuperview() }
        cellLabels.removeSubrange(min(incoming.count, cellLabels.count)...)
        cells = incoming
        naturalRowWidths.removeSubrange(min(firstChanged, naturalRowWidths.count)...)
        if let measured = measuredRows {
            measuredRows = (measured.columnWidths, Array(measured.heights.prefix(firstChanged)))
        }
        cellElementsCache = nil
        cachedLayout = nil
        setNeedsLayout()
```

Extract the label construction in `rebuildCells` into `makeLabel(_:column:)` (numberOfLines 0, attributed text, alignment per column, added to `content`), used by both.

Replace `layout(forWidth:)`'s measuring with:

```swift
    func layout(forWidth width: CGFloat) -> Layout {
        if let cachedLayout, cachedLayout.width == width { return cachedLayout.layout }
        let padding = Self.cellPadding
        let columns = cells.first?.count ?? 0
        let maxColumn = max(theme.maxTableColumnWidth, Self.minimumColumnWidth)
        while naturalRowWidths.count < cells.count {
            naturalRowWidths.append(cells[naturalRowWidths.count].map { min(ceil($0.size().width) + padding * 2, maxColumn) })
        }
        var natural = Array(repeating: Self.minimumColumnWidth, count: columns)
        for row in naturalRowWidths {
            for (column, width) in row.enumerated() { natural[column] = max(natural[column], width) }
        }
        let total = natural.reduce(0, +)
        let widths = total > 0 && total < width ? natural.map { $0 * width / total } : natural
        // Heights measured at these column widths stay valid; any other widths measure every row again.
        var heights = measuredRows?.columnWidths == widths ? measuredRows?.heights ?? [] : []
        while heights.count < cells.count {
            heights.append(cells[heights.count].enumerated().map { column, text in
                let bounds = text.boundingRect(
                    with: CGSize(width: max(1, widths[column] - padding * 2), height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                return ceil(bounds.height) + padding * 2
            }.max() ?? padding * 2)
        }
        measuredRows = (widths, heights)
        let layout = Layout(columnWidths: widths, rowHeights: heights)
        cachedLayout = (width, layout)
        return layout
    }
```

- [ ] **Step 4: Run to verify they pass**

Run the test command for `GlimmerTableViewTests`, `GlimmerAccessibilityTests`, `GlimmerEmbedStreamingTests` and `GlimmerTextViewTests` (every class that builds or streams a table). Expected: PASS.

- [ ] **Step 5: The spec's budget for streaming embeds**

In `GlimmerStreamingPerformanceTests`, the Release `embedStreamingBudget` becomes the spec's 2 ms, and its comment goes:

```swift
    #else
    private let budget: Duration = .milliseconds(2)
    private let embedStreamingBudget: Duration = .milliseconds(2)
    #endif
```

Run the perf class in Release:

```bash
xcodebuild -scheme Glimmer -destination "$DEST" -configuration Release test ENABLE_TESTABILITY=YES \
  -only-testing:GlimmerTests/GlimmerStreamingPerformanceTests 2>&1 | grep -E "PERF|passed|failed" | tail -20
```

Expected: PASS, with long code and long table apply p95 at or under 2 ms. If either misses on the simulator, don't loosen the gate silently. Ledger the numbers as a ruling, set that gate to the measured p95 rounded up to the next half millisecond, and let Task 6's device run decide.

- [ ] **Step 6: Engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: stream table rows without rebuilding the table

Rows before the first changed one keep their labels, natural widths and
heights while the column widths hold; VoiceOver's cells are built when
asked. Streaming embeds now meet the spec's 2 ms apply budget in Release."
```

---

### Task 5: The demo around the engine, and GlimmerText's menus

**Files:**
- Modify: `Sources/Glimmer/Engine/GlimmerText.swift`
- Modify: `Examples/GlimmerDemo/App/EngineGalleryDemo.swift`, `StreamingLabDemo.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerTextTests.swift` (create), `GlimmerViewStreamingTests.swift`

**Interfaces:**
- Consumes: `GlimmerView.editMenuActions`, `GlimmerView.linkMenuActions`, `GlimmerSelection` (Plan 4)
- Produces: `GlimmerText.init(_:isStreaming:revealID:configuration:onLinkTap:editMenuActions:linkMenuActions:)`. The two new parameters default to nil.

Spec §10 wants the demo to have:
- a gallery covering every element in light and dark, at the default and an accessibility text size;
- a streaming lab with speed presets, Gemini-cadence replay, pause and resume, and light and dark;
- a long-answer benchmark (Task 6).

SwiftUI hosts (SuperMe's `MarkdownView` call sites become `GlimmerText`) need the Plan 4 menu hooks too.

- [ ] **Step 1: Write the failing tests**

Create `Tests/GlimmerTests/Engine/GlimmerTextTests.swift`:

```swift
import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTextTests: XCTestCase {
    func testMenuHooksReachTheView() throws {
        let text = GlimmerText(
            "Hello [docs](https://example.com)",
            editMenuActions: { _ in [UIAction(title: "Ask") { _ in }] },
            linkMenuActions: { _ in [UIAction(title: "Open in App") { _ in }] }
        )
        let host = UIHostingController(rootView: text.frame(width: 320))
        let window = hostInWindow(host.view, width: 320, height: 400)
        let view = try XCTUnwrap(findSubview(GlimmerView.self, in: host.view))
        XCTAssertNotNil(view.editMenuActions)
        XCTAssertNotNil(view.linkMenuActions)
        _ = window
    }
}
```

Append to `GlimmerViewStreamingTests` (Review Focus 4):

```swift
    func testRestylingMidRevealKeepsRevealing() async throws {
        let (view, clock, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.5)
        let revealed = try XCTUnwrap(view.engine).revealedLength
        XCTAssertGreaterThan(revealed, 0)
        // A configuration change (like a Dynamic Type change) composes the whole answer again.
        var configuration = view.configuration
        configuration.theme.paragraphSpacing += 2
        view.configuration = configuration
        let engine = try XCTUnwrap(view.engine, "still revealing")
        XCTAssertGreaterThanOrEqual(engine.revealedLength, revealed, "no replay from the start")
        XCTAssertEqual(view.textView.textStorage.string, GlimmerComposer(theme: configuration.theme)
            .compose(GlimmerParser.parse(answer)).string)
        _ = window
    }
```

- [ ] **Step 2: Run to verify**

Run the test command for `GlimmerTextTests` and `GlimmerViewStreamingTests`. Expected: a compile error for the new `GlimmerText` parameters. `testRestylingMidRevealKeepsRevealing` is expected to pass already, since `composeSynchronously` keeps the engine; it pins that behavior. If it fails, the failure is a bug: fix it in Step 3 and ledger it.

- [ ] **Step 3: GlimmerText's hooks**

In `GlimmerText`, add stored properties with doc comments, init parameters at the end with `nil` defaults, and set both on the view in `updateUIView`:

```swift
    /// Items appended to the edit menu for a selection. See `GlimmerView.editMenuActions`.
    public var editMenuActions: ((GlimmerSelection) -> [UIMenuElement])?
    /// Items appended to a link's menu. See `GlimmerView.linkMenuActions`.
    public var linkMenuActions: ((URL) -> [UIMenuElement])?
```

```swift
        view.editMenuActions = editMenuActions
        view.linkMenuActions = linkMenuActions
```

- [ ] **Step 4: Run to verify they pass**

Run the test command for `GlimmerTextTests` and `GlimmerViewStreamingTests`. Expected: PASS.

- [ ] **Step 5: Gallery and lab**

`EngineGalleryDemo`:
- Add a `@State private var isLargeText = false`, a second toolbar toggle "Large Text", and `.dynamicTypeSize(isLargeText ? .accessibility1 : .large)` next to `.preferredColorScheme`.
- Pass `editMenuActions: { selection in [UIAction(title: "Show Markdown") { _ in shownMarkdown = selection.markdown }] }`, with `@State private var shownMarkdown: String?` driving an `.alert("Markdown", isPresented:)` whose message is the markdown. This shows copy's serializer at work, and it's the only way to see the markdown flavor on a device.
- Launch arguments: `--gallery-dark` and `--gallery-large-text` start with those toggles on, for screenshots.

`StreamingLabDemo`:
- Add a Pause/Resume button (`streamingLab.pause`) that sets `@State private var isPaused = false`. While paused, the streaming task waits before appending its next chunk (`while isPaused { try? await Task.sleep(for: .milliseconds(50)) }`), and `isStreaming` stays true, so the reveal catches up and then waits.
- Add a Light/Dark toggle (`streamingLab.dark`) applied with `.preferredColorScheme`.
- Keep the Gemini, Bursty and Slow cadence presets and the Stream/Stop button.

Run `xcodegen generate` if any file was added (none is expected). Build and install the demo, then take simulator screenshots:
- the gallery in light, in dark (`--engine-gallery --gallery-dark`), and in large text (`--engine-gallery --gallery-large-text`);
- the lab mid-stream, paused, and resumed.

Check each by eye against the previous gallery screenshots: nothing clipped, overlapping or mis-colored.

- [ ] **Step 6: Engine suite, demo tests and commit**

Run the engine suite and the demo test command. Expected: all pass.

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine Examples
git commit -m "Demo: gallery sizes and menus, lab pause and theme; GlimmerText menus

The gallery shows every element in light and dark at the default and an
accessibility text size, and a Show Markdown edit-menu item shows what copy
writes. The streaming lab pauses and resumes and switches light and dark.
GlimmerText passes edit and link menu hooks through."
```

---

### Task 6: The benchmark, the device harness and the §3 numbers

**Files:**
- Create: `Examples/GlimmerDemo/Shared/FrameHitchCounter.swift`, `Examples/GlimmerDemo/App/FrameMonitor.swift`, `Examples/GlimmerDemo/App/BenchmarkDemo.swift`
- Create: `Examples/GlimmerDemo/UITests/FrameHitchCounterTests.swift`, `Examples/GlimmerDemo/UITests/BenchmarkHitchUITests.swift`
- Modify: `Examples/GlimmerDemo/App/ContentView.swift`, `GlimmerDemoApp.swift`
- Modify: `Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift` (reveal cost per frame)
- Create: `docs/superpowers/perf/2026-09-26-glimmer-2-plan-5-device-results.md`

**Interfaces:**
- Produces:
  - `struct FrameHitchCounter { mutating func record(timestamp: Double, frameDuration: Double); var frames: Int; var hitches: Int; var worstInterval: Double }`.
  - Launch argument `--benchmark` opens `BenchmarkDemo`.
  - Accessibility identifiers `benchmark.start` (button), `benchmark.scrollView` and `benchmark.summary`. The summary label reads `done frames=<n> hitches=<n> worst=<ms>ms` once streaming ends, and `idle` or `running` before that.

The benchmark shows a settled 5,000-word answer (earlier chat history), then streams a second answer of about 1,000 words below it at Gemini's cadence. A seeded generator makes every run identical. The scroll view follows the bottom until a person (or the UI test) scrolls. While it runs, a `CADisplayLink` at 120 Hz counts frames that arrive more than 1.5 frame durations late. The UI test wraps the run in `XCTHitchMetric` and swipes up and down during the stream.

- [ ] **Step 1: Write the failing tests**

Create `Examples/GlimmerDemo/UITests/FrameHitchCounterTests.swift` (plain XCTest; it doesn't launch the app):

```swift
import XCTest

final class FrameHitchCounterTests: XCTestCase {
    func testASteadySixtyHertzRunHasNoHitches() {
        var counter = FrameHitchCounter()
        for frame in 0..<120 { counter.record(timestamp: Double(frame) / 60, frameDuration: 1.0 / 60) }
        XCTAssertEqual(counter.frames, 120)
        XCTAssertEqual(counter.hitches, 0)
    }

    func testALateFrameAtOneHundredTwentyHertzIsAHitch() {
        var counter = FrameHitchCounter()
        let frame = 1.0 / 120
        var time = 0.0
        for _ in 0..<10 { counter.record(timestamp: time, frameDuration: frame); time += frame }
        time += 0.050 - frame
        counter.record(timestamp: time, frameDuration: frame)
        XCTAssertEqual(counter.hitches, 1)
        XCTAssertEqual(counter.worstInterval, 0.050, accuracy: 0.0001)
    }
}
```

Create `Examples/GlimmerDemo/UITests/BenchmarkHitchUITests.swift`:

```swift
import XCTest

final class BenchmarkHitchUITests: XCTestCase {
    /// Streams about 1,000 words below a settled 5,000-word answer at Gemini's cadence while scrolling. On a device,
    /// the app's frame monitor must report no hitches (spec §3); XCTHitchMetric records the system's view of the same
    /// run in the result bundle.
    @MainActor
    func testStreamingBelowALongAnswerDoesNotHitch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark"]
        app.launch()
        let start = app.buttons["benchmark.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        let summary = app.staticTexts["benchmark.summary"]
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            start.tap()
            let answer = app.scrollViews["benchmark.scrollView"]
            for _ in 0..<4 {
                answer.swipeDown(velocity: .slow)
                answer.swipeUp(velocity: .fast)
            }
            let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'done'"), object: summary)
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 180), .completed)
        }
        print("BENCHMARK \(summary.label)")
        #if !targetEnvironment(simulator)
        XCTAssertTrue(summary.label.contains(" hitches=0 "), summary.label)
        #endif
    }
}
```

Append to `GlimmerStreamingPerformanceTests` (spec §3, first row):

```swift
    /// Spec §3: between network updates a reveal costs the main thread about nothing per frame. Core Animation runs
    /// the fades; the main thread only starts phrases (a layer each) when the clock wakes it.
    func testARevealBetweenUpdatesCostsAlmostNothingPerFrame() async {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = .smooth(GlimmerRevealOptions())
        let view = GlimmerView(configuration: configuration)
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: String(longMixedAnswer.prefix(2_000)), isStreaming: true)
        await view.pendingDocument?.value
        let start = threadCPUTime()
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        let perFrame = (threadCPUTime() - start) / 240
        print("PERF reveal main-thread CPU per 120 Hz frame: \(perFrame)")
        XCTAssertLessThan(perFrame, .microseconds(500))
        _ = window
    }
```

- [ ] **Step 2: Run to verify they fail**

Run the demo test command. Expected: compile errors, since `FrameHitchCounter` doesn't exist and `benchmark.start` is never found. Run the test command for `GlimmerStreamingPerformanceTests/testARevealBetweenUpdatesCostsAlmostNothingPerFrame`. It is expected to pass: it measures existing behavior for the §3 table and is not a RED test.

- [ ] **Step 3: Counter, monitor, benchmark**

Create `Examples/GlimmerDemo/Shared/FrameHitchCounter.swift`:

```swift
/// Counts hitches in a run of frame timestamps. A frame that arrives more than one and a half frame durations after
/// the one before it missed at least one refresh. The duration comes from the display link, so a 60 Hz screen (Low
/// Power Mode) is judged at 60 Hz, not against a 120 Hz budget.
struct FrameHitchCounter {
    private(set) var frames = 0
    private(set) var hitches = 0
    private(set) var worstInterval: Double = 0
    private var last: Double?

    mutating func record(timestamp: Double, frameDuration: Double) {
        defer { last = timestamp }
        frames += 1
        guard let last else { return }
        let interval = timestamp - last
        worstInterval = max(worstInterval, interval)
        if interval > frameDuration * 1.5 { hitches += 1 }
    }
}
```

Create `Examples/GlimmerDemo/App/FrameMonitor.swift`:

```swift
import QuartzCore
import UIKit

/// Asks for 120 Hz and counts the frames that arrive late while it runs.
@MainActor
final class FrameMonitor: NSObject {
    private var link: CADisplayLink?
    private(set) var counter = FrameHitchCounter()

    func start() {
        counter = FrameHitchCounter()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        counter.record(timestamp: link.timestamp, frameDuration: link.targetTimestamp - link.timestamp)
    }
}
```

Create `Examples/GlimmerDemo/App/BenchmarkDemo.swift`:

```swift
import Glimmer
import SwiftUI

/// Streams about 1,000 words below a settled 5,000-word answer at Gemini's cadence, with a frame monitor. The
/// cadence is seeded, so every run streams the same chunks at the same times. Used by BenchmarkHitchUITests.
struct BenchmarkDemo: View {
    private static let history = Array(repeating: EngineGalleryDemo.sample, count: 20).joined(separator: "\n\n---\n\n")
    private static let answer = Array(repeating: StreamingLabDemo.answer, count: 3).joined(separator: "\n\n")
    private static let configuration = GlimmerConfiguration(imageLoader: nil)

    @State private var shown = ""
    @State private var isStreaming = false
    @State private var summary = "idle"
    @State private var monitor = FrameMonitor()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GlimmerText(Self.history, configuration: Self.configuration)
                GlimmerText(shown, isStreaming: isStreaming, revealID: "benchmark", configuration: Self.configuration)
            }
            .padding(16)
        }
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .accessibilityIdentifier("benchmark.scrollView")
        .navigationTitle("Benchmark")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(summary)
                    .font(.caption.monospaced())
                    .accessibilityIdentifier("benchmark.summary")
                Spacer()
                Button("Start", action: start)
                    .buttonStyle(.borderedProminent)
                    .disabled(isStreaming)
                    .accessibilityIdentifier("benchmark.start")
            }
            .padding()
            .background(.bar)
        }
    }

    private func start() {
        shown = ""
        isStreaming = true
        summary = "running"
        monitor.start()
        var generator = SeededGenerator(seed: 42)
        let chunks = StreamingLabDemo.chunks(of: Self.answer, cadence: .gemini, using: &generator)
        Task { @MainActor in
            for (text, delay) in chunks {
                try? await Task.sleep(for: delay)
                shown += text
            }
            isStreaming = false
            // Let the reveal finish before reading the monitor.
            try? await Task.sleep(for: .seconds(3))
            monitor.stop()
            let counter = monitor.counter
            summary = String(format: "done frames=%d hitches=%d worst=%.1fms", counter.frames, counter.hitches,
                             counter.worstInterval * 1000)
        }
    }
}

/// SplitMix64: a small deterministic generator, so the benchmark's cadence is the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
```

The summary's format puts a space after `hitches=<n>` so the UI test can match ` hitches=0 ` exactly.

In `StreamingLabDemo`, make `chunks(of:cadence:)` generic over a generator (`chunks<G: RandomNumberGenerator>(of:cadence:using generator: inout G)`) and keep the old signature calling it with `SystemRandomNumberGenerator()`. Make the lab's `answer` `static let` internal (it already is) so the benchmark can reuse it.

In `ContentView`, add `NavigationLink("Benchmark", destination: BenchmarkDemo())`. In `GlimmerDemoApp`, add a `--benchmark` branch opening `NavigationStack { BenchmarkDemo() }`. Then run `xcodegen generate`.

- [ ] **Step 4: Run to verify on the simulator**

Run the demo test command. Expected:
- `FrameHitchCounterTests` pass.
- `BenchmarkHitchUITests` passes on the simulator. It doesn't assert hitches there, but it prints `BENCHMARK done …` and an `XCTHitchMetric` measurement.

Record both lines in the ledger. Screenshot the benchmark mid-stream.

- [ ] **Step 5: Run on the device**

Check that the device is connected: `xcrun devicectl list devices | grep 00008140-00044C9001F3001C`. Then run the package's performance tests on it, in Release:

```bash
xcodebuild test -scheme Glimmer -configuration Release -destination 'id=00008140-00044C9001F3001C' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=RUV7V2TGVX CODE_SIGN_STYLE=Automatic ENABLE_TESTABILITY=YES \
  -only-testing:GlimmerTests/GlimmerStreamingPerformanceTests 2>&1 | tee .build/device-perf.log | grep -E "PERF|passed|failed" | tail -30
```

and the benchmark, in Release:

```bash
xcodebuild test -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo -configuration Release \
  -destination 'id=00008140-00044C9001F3001C' -allowProvisioningUpdates \
  -only-testing:GlimmerDemoUITests/BenchmarkHitchUITests 2>&1 | tee .build/device-benchmark.log | grep -E "BENCHMARK|Hitch|passed|failed" | tail -20
```

Expected: both pass, and the device meets the §3 budgets: apply p95 ≤ 2 ms, a phrase start ≤ 0.2 ms, cached configure ≤ 4 ms, zero hitches, and a reveal costing about nothing per frame.

Some failures are not code failures:
- signing needs an interactive login;
- the device is locked;
- a "trust this developer" prompt appears on the phone.

For those, ledger the exact error, put the commands in the results doc under "To run on the device", and go on. For a budget miss, don't start a redesign here. Record the number, rule on it in the ledger, and name the options in the results doc. If the cached configure misses 4 ms: lay out less than a screen first, or reuse text views across cells. If the benchmark hitches, read `worst=` to find the phase and rule on the `height(forWidth:)` item from this plan's header.

- [ ] **Step 6: The results doc**

Create `docs/superpowers/perf/2026-09-26-glimmer-2-plan-5-device-results.md`. Give it a table of every §3 metric with its budget, the device's number and pass/miss. Beside it, show the simulator's Release numbers from Task 4, both log lines from the benchmark, and a "What the numbers mean" section written the way Plan 3's results doc explains its metrics. Name the device, the iOS version (`xcrun devicectl device info details --device 00008140-00044C9001F3001C | grep -i "osVersion"`), and the build configuration.

- [ ] **Step 7: Engine suite and commit**

```bash
git add Examples Tests/GlimmerTests/Engine docs/superpowers/perf
git commit -m "Demo: long-answer benchmark with a frame monitor; device results

The benchmark streams about 1,000 words below a settled 5,000-word answer at
a seeded Gemini cadence while a 120 Hz display link counts late frames; a UI
test wraps it in XCTHitchMetric and swipes through it. The spec §3 numbers
from an iPhone 16 Pro Max are in docs/superpowers/perf."
```

---

### Task 7: Copy that pastes back the same

**Files:**
- Modify: `Sources/Glimmer/Engine/Theme/GlimmerAttributeKeys.swift`, `Compose/GlimmerComposer.swift`, `Interact/GlimmerMarkdownSerializer.swift`
- Test: `GlimmerMarkdownSerializerTests.swift`, `GlimmerComposerTests.swift`, `GlimmerThemeTests.swift`

**Interfaces:**
- Produces: `.glimmerListTightness` (`[Bool]`: every enclosing list's tightness, outermost first, on each paragraph inside a list) and `.glimmerListOpens` (`true` on the marker paragraph of a list's first item). They replace `.glimmerTightList`.

Plan 4's review deferred these copy defects:
- a line after a hard break that starts with `#`, `-`, `+` or `>` copies as block syntax;
- a tight list with a loose sublist copies back loose;
- a marker-only line ends in a trailing space;
- a selection that starts on a marker-only line's tab starts with a newline;
- an image inside a link loses its link;
- `&` isn't escaped before an entity-like word;
- intraword `_` is escaped needlessly.

The blank line between two paragraphs belongs to the list that holds both. When the second paragraph starts a later item of its list, that list decides. When it opens a nested list, or continues an item, the item's own list decides.

- [ ] **Step 1: Write the failing tests**

Append to `GlimmerMarkdownSerializerTests`:

```swift
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
```

In `GlimmerComposerTests`, replace `testTightListParagraphsAreMarked` with:

```swift
    func testListParagraphsRecordEachListsTightness() {
        let text = compose("- a\n  - x\n\n  - y\n- b")
        XCTAssertEqual(attributes(of: "b", in: text)[.glimmerListTightness] as? [Bool], [true])
        XCTAssertEqual(attributes(of: "y", in: text)[.glimmerListTightness] as? [Bool], [true, false])
        XCTAssertEqual(attributes(of: "x", in: text)[.glimmerListOpens] as? Bool, true)
        XCTAssertNil(attributes(of: "y", in: text)[.glimmerListOpens])
        XCTAssertNil(attributes(of: "p", in: compose("p"))[.glimmerListTightness])
    }
```

In `GlimmerThemeTests.testAttributeKeysAreNamespaced`, replace the `glimmerTightList` line with the two new keys (`"glimmer.listTightness"`, `"glimmer.listOpens"`).

- [ ] **Step 2: Run to verify they fail**

Run the test command for the three classes. Expected: compile errors for the new keys; with the keys in place, each new test FAILS as described in the task introduction.

- [ ] **Step 3: Record each list's tightness**

In `GlimmerAttributeKeys`, delete `glimmerTightList` and add:

```swift
    /// Each enclosing list's tightness, outermost first (`[Bool]`, on a whole paragraph inside a list). Copy decides
    /// the gap between two paragraphs by the list that holds both.
    static let glimmerListTightness = NSAttributedString.Key("glimmer.listTightness")
    /// `true` on the marker paragraph of a list's first item.
    static let glimmerListOpens = NSAttributedString.Key("glimmer.listOpens")
```

In `GlimmerComposer.Context`, replace `isTight` with `var listTightness: [Bool] = []` and add `var opensList = false`. In `appendList`, set `itemContext.listTightness = context.listTightness + [list.isTight]` and `itemContext.opensList = offset == 0`. The nested blocks of that item must not open a list unless they have a marker, so `stampMarkdown` checks `hasMarker`:

```swift
    private func stampMarkdown(context: Context, hasMarker: Bool, range: NSRange, in output: NSMutableAttributedString) {
        output.addAttribute(.glimmerMarkdownPrefix, value: hasMarker ? context.markerLinePrefix : context.markdownPrefix, range: range)
        if !context.listTightness.isEmpty { output.addAttribute(.glimmerListTightness, value: context.listTightness, range: range) }
        if hasMarker, context.opensList { output.addAttribute(.glimmerListOpens, value: true, range: range) }
    }
```

A list's marker-only paragraph (its first block is another list) carries the outer item's marker and `opensList` of the outer item. That is correct: it is the outer item's first line.

- [ ] **Step 4: The serializer**

In `GlimmerMarkdownSerializer.Paragraph`:
- Replace `isTight` with `let tightness: [Bool]`, read from `.glimmerListTightness` (default `[]`).
- Add `let hasMarker: Bool`, true when `.glimmerListMarker` is at `content.location`.
- Add `let opensList: Bool`, read from `.glimmerListOpens`.

Replace the tight check in `separator(after:before:)`:

```swift
        if first.isMarkerOnly { return "\n" }
        if let level = gapLevel(before: second), second.tightness[level] { return "\n" }
```

with:

```swift
    /// The list whose looseness decides the gap before `second`: its own list when it starts a later item of it, the
    /// enclosing item's list when it opens a nested list, and its innermost list when it continues an item. Nil
    /// outside lists and before a top-level list's first item.
    private static func gapLevel(before second: Paragraph) -> Int? {
        let depth = second.tightness.count - 1
        guard depth >= 0 else { return nil }
        guard second.hasMarker, second.opensList else { return depth }
        return depth > 0 ? depth - 1 : nil
    }
```

In `write(_:selected:includesStart:in:asMarkdown:)`:
- **Per-line escapes.** Apply `escapingBlockStart` to every line after a hard break, not only to the body's start. Split the body on `"\u{2028}"` before joining the lines with `"\\\n" + continuation`, escaping each line. An embed's source lines are exempt, as now: they're joined with `"\n"`, not `"\u{2028}"`.
- **Marker-only lines.** When the paragraph is marker-only, write the marker without its trailing space (`"-"`, `"1."`).
- **A selection starting on a marker-only line's tab.** A paragraph that doesn't include its start and writes an empty body is skipped like an empty selection. It sets no `previous` and emits no separator.

In `segments` handling, an inline-image run (`.glimmerSource` without an attachment) that also has a `.link` writes `"[" + source + "](" + destination(url) + ")"`. The link's runs around it close first (`flush()` already does that).

In `escaped(_:)`:
- Escape `&` only when the next character is a letter or `#`.
- Don't escape `_` when both neighbors are letters or digits (CommonMark never reads an intraword `_` as emphasis).

Walk the text with an index, so both neighbors are known.

- [ ] **Step 5: Run to verify they pass**

Run the test command for `GlimmerMarkdownSerializerTests`, `GlimmerComposerTests`, `GlimmerThemeTests`, `GlimmerInteractionTests` and `GlimmerStreamParityTests`. Expected: PASS, including every earlier round trip.

- [ ] **Step 6: Engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: copy keeps list looseness per list and escapes every line

Paragraphs record each enclosing list's tightness, so a tight list with a
loose sublist pastes back the same. Lines after a hard break escape block
syntax; marker-only lines lose their trailing space; an image in a link
keeps the link; entity-like ampersands are escaped and intraword
underscores are not."
```

---

### Task 8: Accessibility and host loose ends

**Files:**
- Create: `Sources/Glimmer/Engine/Resources/Localizable.xcstrings`
- Modify:
  - `Package.swift` (`defaultLocalization: "en"`; `resources: [.process("Engine/Resources")]` on the `Glimmer` target)
  - `Sources/Glimmer/Engine/GlimmerView.swift`
  - `Embeds/GlimmerCodeBlockView.swift`
  - `Interact/GlimmerMarkdownSerializer.swift`
  - `Compose/GlimmerComposer.swift` (`listMarker`)
- Test: `GlimmerAccessibilityTests.swift`, `GlimmerInteractionTests.swift`, `GlimmerVisibleBandTests.swift`, `GlimmerComposerTests.swift`

**Interfaces:**
- Produces:
  - `GlimmerView.findInteraction: UIFindInteraction?` (public, read-only).
  - `GlimmerMarkdownSerializer.plainText(from:range:forAccessibility:)`, where `forAccessibility` defaults to `false`.

These are the Plan 4 review's deferred minors, plus the task-checkbox state:
- Find has no way to open without a keyboard.
- A host can't group a settled answer for VoiceOver.
- The revealing label reads a chip's display text, while the settled chip reads its accessibility label.
- A band refresh inside a host's animation block can animate fragment views in.
- The library's strings are unlocalized.
- A task checkbox reads as "image" with no state.

- [ ] **Step 1: Write the failing tests**

Append to `GlimmerInteractionTests`:

```swift
    func testFindCanBePresentedByTheHost() {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        XCTAssertNil(GlimmerView(configuration: configuration).findInteraction)
        configuration.allowsFind = true
        XCTAssertNotNil(GlimmerView(configuration: configuration).findInteraction)
    }
```

Append to `GlimmerAccessibilityTests`:

```swift
    func testAHostCanGroupASettledAnswer() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 320, height: 800)
        view.update(markdown: "Grouped **answer**.")
        view.isAccessibilityElement = true
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.accessibilityLabel, "Grouped answer.")
        _ = window
    }

    func testTheRevealingLabelReadsChipsLikeTheSettledChip() async {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.extensions = [LabeledCitationExtension()]
        let view = GlimmerView(configuration: configuration)
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 320, height: 800)
        view.update(markdown: "Sources say so [3] and more words follow here to keep revealing.", isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 3)
        XCTAssertTrue((view.accessibilityLabel ?? "").contains("Source 3"), view.accessibilityLabel ?? "nil")
        _ = window
    }

    func testTaskCheckboxesSayWhetherTheyAreDone() {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse("- [x] done\n- [ ] open"))
        XCTAssertTrue(text.string.contains("Checked"))
        XCTAssertTrue(text.string.contains("Unchecked"))
        XCTAssertEqual(GlimmerMarkdownSerializer.markdown(from: text, range: NSRange(location: 0, length: text.length)),
                       "- [x] done\n- [ ] open", "copy still writes the task syntax")
    }
```

with, at file scope:

```swift
private struct LabeledCitationExtension: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            return GlimmerInlineToken(range: range, kind: "citation", displayText: label, source: label,
                                      accessibilityLabel: "Source \(label.dropFirst().dropLast())")
        }
    }
}
```

Append to `GlimmerVisibleBandTests`:

```swift
    func testMovingTheViewInsideAnAnimationDoesNotAnimateTheText() throws {
        let container = UIView()
        let window = hostInWindow(container, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.update(markdown: long)
        let height = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        container.addSubview(view)
        settle(container)
        UIView.animate(withDuration: 1) { view.frame.origin.y = -(height / 2).rounded() }
        func animated(_ root: UIView) -> Bool {
            (root.layer.animationKeys()?.isEmpty == false) || root.subviews.contains(where: animated)
        }
        XCTAssertFalse(view.textView.subviews.contains(where: animated), "fragment views appear in place")
        _ = window
    }
```

- [ ] **Step 2: Run to verify**

Run the test command for the four classes. Expected:
- Compile errors for `findInteraction`.
- The grouping, chip-label and checkbox tests fail.
- The animation test may pass already, if UIKit adds no animation to views inserted during the layout the band refresh triggers. If it passes, apply Step 3's animation change anyway only if the test can be made to fail. Otherwise ledger a ruling that the concern doesn't reproduce, and drop that change.

- [ ] **Step 3: Implement**

`GlimmerView`:

```swift
    /// The text's Find interaction when `configuration.allowsFind` is on. Hosts present it from a toolbar or menu:
    /// `findInteraction?.presentFindNavigator(showingReplace: false)`.
    public var findInteraction: UIFindInteraction? { configuration.allowsFind ? textView.findInteraction : nil }

    /// A host's own choice to group the answer into one element; nil lets the view decide.
    private var hostGroupsAnswer: Bool?

    public override var isAccessibilityElement: Bool {
        get { engine != nil || hostGroupsAnswer == true }
        set { hostGroupsAnswer = newValue }
    }
```

`accessibilityLabel`'s getter returns the revealed text while revealing. When the host groups a settled answer and set no label of its own, it returns the whole text. Both use `plainText(…, forAccessibility: true)`.

Wrap both band refreshes in the `frame`/`center` observers in `UIView.performWithoutAnimation { textView.refreshVisibleBandIfNeeded() }`. Keep this only if Step 2's test failed without it (see Step 2).

`GlimmerMarkdownSerializer.plainText(from:range:forAccessibility:)`: with `forAccessibility`, a chip writes `token.accessibilityLabel ?? token.displayText`. `markdown(from:range:)` and `plainText(from:range:)` keep their behavior.

`GlimmerComposer.listMarker` (checkbox branch): after the checkbox attachment, append a hidden run that VoiceOver reads and nothing shows:

```swift
            // VoiceOver builds a line's label from its text and skips the image, so the state is text: tiny and clear.
            marker.append(NSAttributedString(string: checkbox ? "Checked, " : "Unchecked, ", attributes: [
                .font: theme.bodyFont.withSize(0.01), .foregroundColor: UIColor.clear,
            ]))
```

The marker's `.glimmerListMarker` range covers it, so copy still writes `- [x] `.

Localization: add `defaultLocalization: "en"` to the package and `resources: [.process("Engine/Resources")]` to the `Glimmer` target. Create `Sources/Glimmer/Engine/Resources/Localizable.xcstrings` with the three keys `Code`, `Code, %@` and `Copy code` (English values equal to the keys). In `GlimmerCodeBlockView`, read them with `String(localized: "Code", bundle: .module)`, `String(localized: "Code, \(language)", bundle: .module)` and `String(localized: "Copy code", bundle: .module)`.

- [ ] **Step 4: Run to verify, then check VoiceOver's view on the simulator**

Run the test command for the four classes plus `GlimmerCodeBlockViewTests`, `GlimmerMarkdownSerializerTests` and `GlimmerComposerTests`. Expected: PASS. Then rebuild the demo, open the gallery, and run `axe describe-ui --udid 69D2BAC9-1BB2-4A2A-A361-3150710B8462`. Expected: the task lines' labels read `Checked, Done task` and `Unchecked, Open task`. If they still read `\tDone task`, VoiceOver ignores the hidden run too: revert the checkbox change and its test, and ledger it as a deferred minor with what was tried. Also screenshot the task list: the checkboxes and text must sit exactly where they did before.

- [ ] **Step 5: Engine suite and commit**

```bash
git add Package.swift Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: Find for hosts, grouped answers, chip and checkbox speech, localizable strings

Hosts can present Find and group a settled answer for VoiceOver; the
revealing label reads chips as the settled chip does; task checkboxes say
whether they are done; the library's strings are localizable."
```

---

### Task 9: The docs for 2.0

**Files:**
- Rewrite: `README.md`, `Examples/README.md`, `CLAUDE.md`, `AGENTS.md`
- Test: `Tests/GlimmerTests/Engine/GlimmerReadmeExampleTests.swift`

**Interfaces:**
- Consumes: the whole public API; Task 6's results doc.

The README is how a host learns 2.0, and 1.x users need to know what changed. Its code examples are compiled by a test, so they can't drift from the API.

- [ ] **Step 1: Write the failing test**

Create `Tests/GlimmerTests/Engine/GlimmerReadmeExampleTests.swift`. It holds the README's examples verbatim, one test per README section:

```swift
import SwiftUI
import UIKit
import XCTest
import Glimmer

/// The README's examples, compiled and run. If one of these changes, change the README with it.
@MainActor
final class GlimmerReadmeExampleTests: XCTestCase {
    func testUIKitQuickStart() {
        let view = GlimmerView()
        view.onLinkTap = { url in UIApplication.shared.open(url) }
        view.update(markdown: "# Hello\n\nThis is **Glimmer**.")
        XCTAssertGreaterThan(view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height, 0)
    }

    func testStreaming() {
        let view = GlimmerView()
        let messageID = "message-1"
        var received = ""
        for chunk in ["Glimmer reveals ", "an answer ", "phrase by phrase."] {
            received += chunk
            view.update(markdown: received, isStreaming: true, revealID: messageID)
        }
        view.update(markdown: received, isStreaming: false, revealID: messageID)
    }

    func testSwiftUI() {
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
        _ = UIHostingController(rootView: Answer(text: "Hi", isStreaming: false))
    }

    func testConfiguration() {
        var configuration = GlimmerConfiguration()
        configuration.theme.linkColor = .systemPurple
        configuration.reveal = .smooth(GlimmerRevealOptions())
        configuration.dataDetectors = [.phoneNumber]
        configuration.allowsFind = true
        let view = GlimmerView(configuration: configuration)
        view.editMenuActions = { selection in
            [UIAction(title: "Ask about this") { _ in print(selection.markdown) }]
        }
        view.linkMenuActions = { url in [UIAction(title: "Copy Link") { _ in UIPasteboard.general.url = url }] }
        _ = view.markdownSource()
    }

    func testExtension() {
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
    }
}
```

Note `import Glimmer`, not `@testable`: this proves the examples use only public API.

- [ ] **Step 2: Run to verify**

Run the test command for `GlimmerReadmeExampleTests`. Expected: PASS if every API it uses is public. A compile error means the README would show something a host can't write: make that API public (with a doc comment) or change the example, and ledger which. `GlimmerTheme.linkColor` must be a public `var`, for instance.

- [ ] **Step 3: Write the README**

Rewrite `README.md` for 2.0. Put the examples in as they appear in the test file above, and keep every other statement checkable against the code. Sections:

1. **Glimmer**: one paragraph. Native markdown for streaming LLM answers on iOS: TextKit 2, vendored cmark-gfm (the same GFM as `remark-gfm`), and a reveal that fades phrases in the way Gemini does, with no reflow.
2. **Requirements**: iOS 18, Swift 6, Xcode 26 or later.
3. **Installation**: SwiftPM, `.package(url: "https://github.com/willi/Glimmer.git", from: "2.0.0")` (the `origin` remote's URL).
4. **Quick start (UIKit)**, **Streaming**, **SwiftUI**: the examples.
5. **Configuration**: theme, extensions, highlighter, image loader, reveal (`.smooth`/`.none`, and that Reduce Motion always shows text at once), data detectors, Find.
6. **Extensions**: preprocess and scan, chips with a view, `source` for copy, `accessibilityLabel`.
7. **Copy, selection and menus**: plain text plus `net.daringfireball.markdown`; selection clamped to revealed text; `markdownSource(for:)`; the edit and link menu hooks.
8. **Accessibility**: one element while revealing, the text view at settle; code, tables, chips, task checkboxes.
9. **Performance**: the §3 table with the device numbers from Task 6's results doc (link it), and one sentence per technique: the worker, the visible band, the unbounded container, the mask.
10. **Demo app**: `open Examples/GlimmerDemo/GlimmerDemo.xcodeproj`; its screens; `xcodegen generate` after changing its files.
11. **Migrating from 1.x**: a table mapping `MarkdownView` → `GlimmerText`, `StreamingMarkdownView`/`GlimmerRevealView` → `GlimmerText(isStreaming:)`, `MarkdownConfiguration` → `GlimmerConfiguration`, `MarkdownExtension` → `GlimmerExtension`. Then a list of what is gone with no replacement: the linter, the exporters, the GitHub mention/issue/SHA extensions, emoji shortcodes, the 12 reveal styles, HTML and plain-text renderers.
12. **License**: Glimmer's licence and the cmark-gfm notice (`Sources/cmark-gfm/COPYING`).

Rewrite `Examples/README.md`: the four screens, their launch arguments (`--engine-gallery`, `--gallery-dark`, `--gallery-large-text`, `--streaming-lab`, `--benchmark`), XcodeGen, and the UI test and device commands from Task 6.

Rewrite `CLAUDE.md` and `AGENTS.md` around the engine. Cover:
- the module layout (`Engine/Parse`, `Stream`, `Compose`, `Render`, `Reveal`, `Embeds`, `Extensions`, `Highlight`, `Interact`, `Theme`, and the root `GlimmerView`/`GlimmerText`/`GlimmerConfiguration`);
- the test command with the simulator destination from Global Constraints, and the note to kill xcodebuild after the results print;
- the demo and XcodeGen;
- the device harness commands;
- the TextKit 2 rules (never touch `layoutManager`; nothing lays out outside the viewport; the unbounded-container pattern);
- the perf-measurement lesson (measure main-thread CPU with `threadCPUTime()`, not timers, when a worker is involved).

Drop every 1.x section.

- [ ] **Step 4: Verify the docs**

```bash
grep -nE "MarkdownView|StreamingMarkdownView|RevealStyle|ParallelMarkdownParser|MarkdownLinter|MarkdownExporter" README.md CLAUDE.md AGENTS.md Examples/README.md
```

Expected: matches only inside README's "Migrating from 1.x" section. Run the test command for `GlimmerReadmeExampleTests`: PASS. Read the README once top to bottom in a Markdown preview (the demo's gallery can render it: paste it into the lab's answer temporarily, or open it in Xcode). Fix anything that reads wrong.

- [ ] **Step 5: Engine suite and commit**

```bash
git add README.md Examples/README.md CLAUDE.md AGENTS.md Tests/GlimmerTests/Engine Sources/Glimmer/Engine
git commit -m "Docs: README, examples and agent guides for Glimmer 2.0

The README covers UIKit, SwiftUI, streaming, configuration, extensions,
copy, accessibility, the device numbers and migrating from 1.x; its code is
compiled by GlimmerReadmeExampleTests. The agent guides describe the engine
instead of 1.x."
```

---

## Release (after the final review's fix pass)

When the final review's Critical and Important findings are fixed and the suite is green:

```bash
git tag -a 2.0.0 -m "Glimmer 2.0.0: a native TextKit 2 markdown engine with a Gemini-style streaming reveal"
git show --stat 2.0.0 | head -5
```

Do not push the branch or the tag. The final message tells Willi the tag exists locally and gives the commands to push both when he chooses.

## Out of scope for this plan

- SuperMe's adoption (spec §14): porting `SFMGlimmerPlugin`, the SuperMe theme, replacing `AgentChatNative*` and the `MarkdownView` call sites, bumping the pinned revision. That is its own spec and plan, in the SuperMe repos.
- Math, Mermaid and extra reveal styles (spec §2 non-goals).
- Merging `glimmer-2` into `main` and publishing the release. Willi decides when.
