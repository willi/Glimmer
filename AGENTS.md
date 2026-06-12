# Repository Guidelines

## Project Structure & Module Organization
- `Sources/Glimmer/`: Main library code.
  - `Parser/`, `Rendering/`, `Reveal/`, `Views/`, `Utilities/`, `Linter/`, `Export/` modules.
- `Tests/GlimmerTests/`: XCTest suites (e.g., `GlimmerTests.swift`, `MarkdownParserTests.swift`).
- `Examples/GlimmerDemo/`: SwiftUI demo app (Xcode project) showcasing features.
- `Package.swift`: SwiftPM manifest (Swift tools 5.9, iOS 17 target).

## Build, Test, and Development Commands
- Xcode (recommended): Open `Package.swift` or `Examples/GlimmerDemo/GlimmerDemo.xcodeproj`, choose an iOS 17+ simulator, then run tests for the `GlimmerTests` target.
- CLI with Xcode: `xcodebuild -scheme Glimmer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
  - The package scheme is `Glimmer`. Substitute any installed simulator (`xcrun simctl list devices available`).
- Run a specific test: `xcodebuild -scheme Glimmer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:GlimmerTests/MarkdownParserTests`.
- Build the package (iOS-only): `xcodebuild -scheme Glimmer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
- Run demo: `open Examples/GlimmerDemo/GlimmerDemo.xcodeproj` and run the `GlimmerDemo` target on a simulator. New demo `.swift` files must be added to the app target in `project.pbxproj` (explicit source list).
Note: This package is iOS-only; `swift test` / `swift build` on macOS will fail due to UIKit.

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines.
- Indentation: 4 spaces; keep lines ~120 chars when practical.
- Naming: Types `UpperCamelCase`; methods/properties `lowerCamelCase`.
- Access control: Default to internal, mark public API explicitly.
- Organization: Use `// MARK:` groups (as in existing files) and keep modules cohesive (`Parser`, `Views`, etc.).
- Formatting/Linting: No enforced tools in-repo; prefer SwiftFormat/SwiftLint locally before PRs.

Additional conventions for this project:
- Modern SwiftUI (iOS 17+, Swift 6) across all UI components.
- Prefer SwiftUI-native solutions over UIKit bridging; no external dependencies.
- Concurrency: use `async`/`await`, apply `@MainActor` to UI mutations, and adopt Swift 6 strict concurrency where applicable.
- Observation: prefer the `@Observable` macro for view models; use `@State` for view-local state and `@Binding` for two-way data.
- Apple HIG compliance (typography, colors, spacing, touch targets, accessibility, safe areas, adaptive layouts).

## Testing Guidelines
- Framework: XCTest.
- Location: Place tests under `Tests/GlimmerTests/` with filenames ending in `Tests.swift`.
- Conventions: Test methods start with `test...` (e.g., `test<Feature><Scenario>`) and assert behavior-focused outcomes (e.g., parsed block counts, attributed output non-empty). Group edge cases in dedicated test files.
- Running: use `xcodebuild -scheme Glimmer ... test` against an iOS simulator (`swift test` does not work on macOS); use `-only-testing:` for focused runs.

## Commit & Pull Request Guidelines
- Commits: Use clear, present-tense summaries (e.g., "Add streaming parser chunking"). Small, focused commits preferred.
- Conventional Commits are welcome (e.g., `feat(parser): add lazy windowing`).
- PRs must: describe changes and rationale, link issues, include tests for new behavior, update docs/examples when relevant, and pass the test suite on an iOS simulator.
- Screenshots: Include when UI rendering changes (SwiftUI views, demos).

Additional note: Keep the public API surface minimal and well-documented.

## Security & Configuration Tips
- Platform: iOS 17+ only. Ensure simulator/device targets match.
- Performance-sensitive code (parsers/renderers): avoid regressions; measure with large inputs where possible.

## Architecture Overview
- Core flow: Markdown → `Parser` (AST) → `AttributedString` → SwiftUI `Views` or exporters.
- Public surface: `Glimmer` entry points and `MarkdownView` convenience APIs; keep additions minimal and well-documented.

### SwiftUI Components (Primary Interface)
- `MarkdownView`: Primary SwiftUI view with tap handlers for links, mentions, issues.
- `MarkdownTextWithAsyncImages`: SwiftUI view supporting inline async image loading.
- `StreamingMarkdownView`: SwiftUI view for real-time markdown updates.
- `GlimmerRevealView`: Animated per-token reveal of streaming markdown (11 `RevealStyle`s, adaptive catch-up, resume via `revealID`); lives in `Sources/Glimmer/Reveal/`.
- `AttributedTextView`: SwiftUI wrapper for attributed text rendering.
- `MarkdownText`: Pure SwiftUI text rendering without images.

### Parser Pipeline
- `MarkdownParser`: Main entry point, generates AST for rendering.
- `BlockParser`: Handles block-level elements (headings, lists, code blocks, tables).
- `InlineParser`: Processes inline elements (bold, italic, links, images, emojis).
- `GFMExtensions`: GitHub-specific features (@mentions, issues, commit SHAs).
- `StreamingMarkdownParser`: Incremental parsing for real-time updates.
- `CachedMarkdownParser`: LRU cache with TTL for performance.
- `ParallelParser`: Multi-threaded parsing for large documents.

### Rendering
- `MarkdownRenderer`: Converts AST to `AttributedString` for SwiftUI `Text`.
- `CustomRenderer`: Protocol for alternative formats (HTML/PlainText).

### Streaming Reveal (`Sources/Glimmer/Reveal/`)
- Buffer → parse (cached) → `RevealFlattener` (atoms with stable ids) → `RevealDriver` (clock-paced) → `GlimmerRevealView`.
- The reveal view is also the settled view (no engine swap); inline styling reuses `MarkdownRenderer.renderInlines` via `beginSession`.
- Pure pacing/trail math in `RevealPacing.swift` is unit-tested without a clock; driver tests inject a fake `sleep`.

### Configuration
- `MarkdownConfiguration`: Configuration type with builder-style API.
- Presets: `.default`, `.github`, `.minimal`, `.performance`.
- GitHub-specific extensions (mentions, issue/PR/repo refs, commit SHAs, emoji shortcodes, bare-URL autolinks) are disabled by default; opt in via `.github` or `enableGitHubFeatures()`. Tests/demos exercising GFM must pass an opted-in configuration.

### Key Design Patterns
- AST-based parsing: parse once, render multiple formats.
- Protocol-driven rendering via `MarkdownRendererProtocol`.
- Lazy evaluation for large documents via windowing.
- Parallel processing for documents above ~10KB.
- Smart caching: size-limited LRU cache with TTL and memory pressure handling.

## Performance Considerations
- Parser and renderer performance are critical; avoid regressions.
- Benchmark with large documents (100KB+) and measure memory.
- Minimize `AttributedString` regeneration and leverage SwiftUI view diffing.
- Use Instruments (SwiftUI template) to profile hot paths.
- Consider fragment pools and caching for memory efficiency.
- Benchmark harness: `ProfilingBenchmarkTests/testPhaseTimings` (per-phase timings on a complex corpus); `testProfilingLoop` with `TEST_RUNNER_GLIMMER_PROFILING=1` for Instruments attach. Benchmark in Release (`-configuration Release ENABLE_TESTABILITY=YES`).
- `maxRenderCacheEntries` (default 4096) must exceed the re-rendered document's block count or the LRU thrashes to 0% hits.

## Common Development Tasks

### Adding SwiftUI Interactivity
1. Add tap handler to `MarkdownView` (e.g., `onCommitTap`).
2. Update `AttributedTextView` for gesture recognition.
3. Ensure UI updates occur on `@MainActor`.
4. Test with SwiftUI previews.

### Adding a New Inline Element
1. Define a token type in `MarkdownParserTypes.swift`.
2. Add parsing logic to `InlineParser.swift`.
3. Update `MarkdownRenderer.swift` to generate `AttributedString`.
4. Add SwiftUI rendering in `MarkdownView` if interactive.
5. Add tests to `Tests/GlimmerTests/`.

### Adding a New Block Element
1. Define the block type in `MarkdownParserTypes.swift`.
2. Add detection in `BlockParser.swift`.
3. Create SwiftUI view component in `MarkdownView.swift`.
4. Handle `AttributedString` generation in `MarkdownRenderer.swift`.
5. Test with SwiftUI previews and edge cases.

### Extending GitHub Features
1. Add pattern matching in `GFMExtensions.swift`.
2. Update `MarkdownView` for tap callbacks.
3. Use `async`/`await` for network features if needed.
4. Consider caching implications.

### SwiftUI Performance Optimization
1. Use `@State` for local state; `@Observable` for shared models.
2. Leverage SwiftUI's automatic view diffing.
3. Profile with Instruments.
4. Minimize `AttributedString` regeneration.
5. Use `AsyncStream` for streaming updates (prefer over Combine).
6. Test with performance benchmarks where applicable.

## Modern SwiftUI & Swift 6 Best Practices

### State Management
- Use `@State` for view-local state.
- Use the `@Observable` macro for view models (replaces `ObservableObject`).
- Use `@Binding` for two-way data flow.
- Prefer `@Observable` over `@StateObject`/`@ObservedObject`.
- Use `@Environment` for dependency injection.

### Concurrency
- Apply `@MainActor` to all UI-related code.
- Prefer `async`/`await`; adopt strict concurrency checking.
- Use `AsyncStream` for reactive streams (not Combine).
- Use SwiftUI's `.task` modifier for async operations.
- Implement `Sendable` for concurrently used types as needed.

### SwiftUI Patterns
- Prefer SwiftUI-native components over UIKit bridging.
- Use view modifiers for reusable styling.
- Leverage `ViewBuilder` for composable views.
- Use `@Environment(.dismiss)` for navigation.
- Prefer declarative navigation APIs (iOS 16+).

### Apple Human Interface Guidelines (HIG)
- Typography: Use Dynamic Type; prefer SF fonts.
- Colors: Respect system colors and dark mode.
- Spacing: Use standard iOS spacing (8pt grid).
- Touch targets: Minimum 44x44pt for tappable elements.
- Accessibility: Support VoiceOver, Dynamic Type, Reduce Motion.
- Platform conventions: Follow iOS navigation patterns and gestures.
- Semantic colors: Use `.primary`, `.secondary`, `.accentColor`.
- Safe areas: Respect safe area insets.
- Adaptive layouts: Support all device sizes and orientations.

### Example: HIG-Compliant Modern View
```swift
@Observable
final class MarkdownViewModel {
    var markdown = ""
    var isLoading = false

    func loadContent() async {
        isLoading = true
        // Async work here
        isLoading = false
    }
}

struct ContentView: View {
    @State private var viewModel = MarkdownViewModel()
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        MarkdownView(markdown: viewModel.markdown)
            .safeAreaInset(edge: .bottom) {
                // Respect safe areas
            }
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.loadContent()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Markdown content")
    }
}
```
