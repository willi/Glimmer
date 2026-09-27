# Glimmer 2.0 Plan 8: the 1.x Examples app, on Glimmer 2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every screen of Glimmer 1.x's Examples app (`/Users/willi/work/Glimmer1/Examples/GlimmerDemo`, 13 screens) runs flawlessly in Glimmer's demo app on Glimmer 2. Screens built on removed features get their 2.0 equivalent, and the linter screen goes.

**Decisions (Willi, Sept 27):**
- The screens live in Glimmer's demo (`Examples/GlimmerDemo`, XcodeGen), next to Gallery, Streaming Lab, Long Answer and Benchmark.
- Removed features get 2.0 equivalents: the benchmarks use 2.0's own numbers, export becomes what copy writes, and the reveal styles become the one reveal with its options. The linter screen is dropped.
- Glimmer gains `onImageTap`.

**Architecture:** The ported screens go in `Examples/GlimmerDemo/App/Examples/`, one file per 1.x file, with 1.x's content strings kept. Only claims about 1.x-only features change, where the text states them as facts. `MarkdownView(…, configuration: .github, onMentionTap:, onIssueTap:)` maps to `GlimmerText(…, configuration: .demoGitHub, onLinkTap:, onTokenTap:)`. `.demoGitHub` is a demo-side configuration with:
- `GlimmerEmojiShortcodes`;
- `GlimmerMentions`;
- a demo `GitHubIssueReferences` extension (tappable `#123` text). It shows how a host writes its own, as the README recommends.

**Tech Stack:** SwiftUI, Glimmer 2 (iOS 26 floor), XcodeGen.

## Global Constraints

- Two new public APIs, and nothing else:
  - `GlimmerView.onImageTap` / `GlimmerText(onImageTap:)`: `(URL, String) -> Void`, called with the image's URL and alt text for a standalone image or an inline image square.
  - `GlimmerView.plainText(for:)`: the plain-text counterpart of `markdownSource(for:)`, which the Export tab needs.
- Every screen: no crash, no console errors from Glimmer, and it looks right in light, dark and large text.
- After adding files, run `cd Examples/GlimmerDemo && xcodegen generate` and commit the regenerated project.
- No Co-Authored-By trailers. Don't push.

## Screen mapping

| 1.x screen | 2.0 screen |
|---|---|
| Basic Features (tabs Basic, Interactive, Code) | Same tabs. Interactive uses `.demoGitHub` with link and token taps (a mention's username, an issue's number). |
| Advanced Features → Config | 2.0 configuration toggles: emoji/mentions extensions, underlined links, code block header, image loader on/off, and a theme picker (default, or large body font) |
| Advanced Features → Streaming | `GlimmerText` streaming with Start, Stop and Reset |
| Advanced Features → Export | Markdown and plain text as copy writes them (`markdownSource(for:)`, `plainText(for:)`). HTML is gone. |
| Markdown Linter | dropped |
| GitHub Flavored Markdown (10 sections) | Same sections, on `.demoGitHub` |
| Edge Cases | Same content, on `.demoGitHub` |
| Inline Images | `GlimmerText` sections. The local-asset case uses a demo image loader that serves `dog` from an SF Symbol. |
| Tappable Images | `onImageTap` → an alert with the URL |
| GitHub Emojis | The toggle turns `GlimmerEmojiShortcodes` on and off |
| Live Preview | A `TextEditor` above `GlimmerText` (2.0 recomposes only what changed) |
| Streaming Reveal | Hosts: SwiftUI `GlimmerText` and UIKit `GlimmerView`. Reveal: smooth or none, with a fade-duration option. Simulate Stream and Play Full Text. |
| Parallel Parsing + Performance Benchmarks | One "Performance" screen: parse, settled render and streamed render times for a chosen document size and number of runs |
| README Example, GitHub Features | Quick examples on `.demoGitHub` |

## Review Focus

1. Every screen opens, scrolls to its end and goes back without a crash: a UI test visits them all (Task 5).
2. Tapping an image, a mention and an issue reference calls the right handler (Tasks 1, 3).
3. The Edge Cases content is 1.x's stress corpus. Anything it renders wrong is a library bug to fix here, not paper over.
4. Dark mode and large text on every screen: screenshots are reviewed (Task 5).

---

### Task 1: `onImageTap` and `plainText(for:)`

**Files:**
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift`, `GlimmerText.swift`, `Embeds/GlimmerImageEmbedView.swift`, `Compose/GlimmerInlineImageView.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerImageTapTests.swift`

- [ ] **Failing tests:**
  - `testTappingAStandaloneImageCallsOnImageTap`
  - `testTappingAnInlineImageCallsOnImageTap`
  - `testImagesAreNotTappableWithoutAHandler`
  - `testPlainTextOfTheWholeAnswer`

  Drive the tap through the image view's tap gesture action; test code can call the handler method directly.
- [ ] **Implement:**
  - Both image views get a `UITapGestureRecognizer`. It's enabled only while a handler is set, and `accessibilityTraits` gains `.button` then.
  - The view finds the handler through its `GlimmerView` ancestor, `onImageTap`.
  - `plainText(for:)` wraps the serializer.
- [ ] Run the tests and the engine suite, then commit `Engine: onImageTap; GlimmerView.plainText(for:)`.

### Task 2: Demo scaffolding

**Files:**
- Create in `Examples/GlimmerDemo/App/Examples/`:
  - `DemoConfiguration.swift` (`.demoGitHub`);
  - `GitHubIssueReferences.swift` (demo extension);
  - `DemoImageLoader.swift` (URL loader, plus SF Symbols for bare names such as `dog`).
- Modify: `ContentView.swift`. The sections become "Glimmer 2.0" (Gallery, Streaming Lab, Long Answer, Benchmark), then "Core", "Advanced", "Performance" and "Quick Examples", as in 1.x.

- [ ] Write the three helpers. The issue extension matches `(?<![\w/])#(\d+)\b` as `.text(tappable: true)` (kind `issue`), with `appliesInsideLinks` false.
- [ ] Commit once Task 3's first screen compiles against it.

### Task 3: The rendering screens

**Files:** Create `BasicFeaturesDemo.swift`, `GFMDemo.swift`, `EdgeCasesDemo.swift`, `InlineImageDemo.swift`, `TappableImageExample.swift`, `GitHubEmojiDemo.swift` and `QuickExampleView.swift` (with the README and GitHub Features content).

- [ ] Port each screen: 1.x's content strings verbatim, and the views rebuilt on `GlimmerText`.
- [ ] Build, launch each screen on the simulator, screenshot it, and fix what is wrong.
- [ ] Commit `Demo: 1.x rendering screens on Glimmer 2`.

### Task 4: The interactive screens

**Files:** Create `AdvancedDemo.swift` (Config, Streaming and Export tabs), `LivePreviewDemo.swift`, `StreamingRevealDemo.swift` and `PerformanceDemo.swift`.

- [ ] Port each screen per the mapping.
- [ ] Build, screenshot and fix.
- [ ] Commit `Demo: 1.x interactive screens on Glimmer 2`.

### Task 5: Every screen, verified

**Files:**
- Create: `Examples/GlimmerDemo/UITests/ExamplesUITests.swift`
- Modify: `Examples/README.md`

- [ ] **The UI test:** open each screen from the list, scroll to the end, check for its title, go back. Also:
  - Basic Features: tap each tab.
  - Streaming Reveal: start the stream and wait for the text.
  - Tappable Images: tap an image and check the alert.
- [ ] **Screenshots** of every screen in light, dark and large text, reviewed. Fix what's wrong: rendering bugs in the library get a failing engine test first.
- [ ] **Console:** run the app with `simctl launch --console` through the UI test, and grep for Glimmer, Auto Layout and TextKit errors.
- [ ] **README:** list the screens and their launch arguments.
- [ ] Run the demo UI tests and the engine suite, then commit `Demo: every 1.x example verified on Glimmer 2`.

## Out of scope

- The linter, HTML export, parallel parsing and the 12 reveal styles themselves: 2.0 non-goals.
- SuperMe.
