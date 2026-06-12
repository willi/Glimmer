# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

**iOS-only package - requires Xcode and iOS Simulator**

### Testing
```bash
# Run all tests (requires iOS Simulator; substitute any installed device —
# list with: xcrun simctl list devices available)
xcodebuild -scheme Glimmer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Run specific test
xcodebuild -scheme Glimmer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:GlimmerTests/MarkdownParserTests
```

### Demo App
```bash
# Open demo in Xcode
open Examples/GlimmerDemo/GlimmerDemo.xcodeproj
# Then run on iOS Simulator (iOS 17+)
```

### Build Package
```bash
# Build package (iOS only)
xcodebuild -scheme Glimmer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Important Notes
- **iOS-only package**: `swift test` on macOS will fail due to UIKit dependencies
- **Scheme name**: The package scheme is `Glimmer` (there is no `Glimmer-Package` scheme)
- **Swift Package Manager**: Primary package manifest uses Swift tools 5.9+
- **Public API surface**: Keep minimal and well-documented
- **Demo app sources**: `Examples/GlimmerDemo/GlimmerDemo.xcodeproj` uses an explicit source file list — new demo `.swift` files must be added to `project.pbxproj` (PBXBuildFile + PBXFileReference + Sources phase) or the app target won't compile them

## Architecture Overview

Glimmer is a **SwiftUI-native** Markdown renderer built specifically for iOS 17+. The architecture prioritizes SwiftUI integration:

```
Markdown Text → Parser (AST) → AttributedString → SwiftUI Views
```

### SwiftUI Components (Primary Interface)

**Views** (`Sources/Glimmer/Views/`) - The main SwiftUI API
- `MarkdownView`: Primary SwiftUI view with tap handlers for links, mentions, issues
- `MarkdownTextWithAsyncImages`: SwiftUI view supporting inline async image loading
- `StreamingMarkdownView`: SwiftUI view for real-time markdown updates
- `AttributedTextView`: SwiftUI wrapper for attributed text rendering
- `MarkdownText`: Pure SwiftUI text rendering without images
- `GlimmerRevealView` (`Sources/Glimmer/Reveal/`): Animated per-token reveal of streaming markdown (11 styles)

**SwiftUI Integration Features**
- Native `AttributedString` rendering for optimal SwiftUI performance
- SwiftUI environment integration (color scheme, dynamic type)
- Declarative configuration via builder pattern
- Reactive updates with `@State`, `@Binding`, and `@Observable` (Swift 6)
- Native SwiftUI tap gesture handling
- Modern observation with `@Observable` macro for view models

### Core Components

**Parser Pipeline** (`Sources/Glimmer/Parser/`)
- `MarkdownParser`: Main entry point, generates AST for SwiftUI consumption
- `BlockParser`: Handles block-level elements (headings, lists, code blocks, tables)
- `InlineParser`: Processes inline elements (bold, italic, links, images, emojis)
- `GFMExtensions`: GitHub-specific features (@mentions, issues, commit SHAs)
- `StreamingMarkdownParser`: Incremental parsing for SwiftUI real-time updates
- `CachedMarkdownParser`: LRU cache with TTL for SwiftUI performance
- `ParallelParser`: Multi-threaded parsing for large documents

**Rendering** (`Sources/Glimmer/Rendering/`)
- `MarkdownRenderer`: Converts AST to `AttributedString` for SwiftUI `Text`
- `CustomRenderer`: Protocol for alternative formats (HTML/PlainText)

**Streaming Reveal** (`Sources/Glimmer/Reveal/`)
- Pipeline: buffer → parse (cached) → `RevealFlattener` (AST → `RevealAtom`s with stable ordinal ids) → `RevealDriver` (clock-paced `revealedCount` with adaptive catch-up) → `GlimmerRevealView` (renders visible atoms, newest animate in)
- `RevealStyle`/`RevealTreatment`/`RevealConfiguration`: the 11 styles, their granularities (char/word/line), cadences, and entrance treatments (`RevealTypes.swift`)
- `RevealProgressStore`: monotonic per-`revealID` progress so re-mounted views resume instead of replaying
- `RevealPacing`/`RevealTrail`: pure, unit-tested pacing and trail-opacity math
- Settle strategy A: the reveal view IS the settled view — no engine swap, no layout pop; styling reuses `MarkdownRenderer.renderInlines` via `beginSession`

**Configuration**
- `MarkdownConfiguration`: SwiftUI-friendly configuration with builder API
- Presets: `.default`, `.github`, `.minimal`, `.performance`
- **GitHub-specific extensions are OFF by default** (@mentions, issue/PR/repo references, commit SHAs, emoji shortcodes, bare-URL autolinks). Opt in via `.github`, `enableGitHubFeatures()`, or individual flags. Tables/task lists/strikethrough are always parsed.
- Follows Apple HIG for typography, colors, and spacing

### Key Design Patterns

1. **AST-based parsing**: Parse once, render multiple formats
2. **Protocol-driven rendering**: Extensible output formats via `MarkdownRendererProtocol`
3. **Lazy evaluation**: Deferred parsing for large documents via windowing
4. **Parallel processing**: Automatic multi-threading for documents >10KB
5. **Smart caching**: Size-limited (50MB) LRU cache with TTL and memory pressure handling

## Development Conventions

### Code Style
- **Modern SwiftUI** architecture (iOS 17+, Swift 6.0+)
- **Apple HIG compliance** for all UI components
- Swift 6 observation (`@Observable` macro for view models)
- Swift 6 concurrency (`async`/`await`, `@MainActor` for UI updates)
- Use `@State` for view-local state, `@Observable` for shared state
- Follow Swift API Design Guidelines
- 4-space indentation, ~120 char line length
- Naming: Types `UpperCamelCase`, methods/properties `lowerCamelCase`
- Use `// MARK: -` for section organization
- Access control: internal by default, explicit public API
- No external dependencies
- Prefer SwiftUI native solutions over UIKit bridging

### Testing Approach
- XCTest framework in `Tests/GlimmerTests/`
- Test method naming: `test<Feature><Scenario>`
- Focus on behavior outcomes (parsed blocks, rendered output)
- Edge cases in dedicated test files
- Use `--filter` for focused test runs
- Include screenshots when UI rendering changes

### Performance Considerations
- Parser optimizations critical for user experience
- Benchmark large documents (100+ KB)
- Memory management via fragment pools
- Parallel parsing threshold: 10KB documents
- Measure performance with large inputs to avoid regressions
- Performance-sensitive code in parsers/renderers requires careful testing
- **Benchmark harness**: `ProfilingBenchmarkTests/testPhaseTimings` prints per-phase timings over a ~0.5MB complex corpus; `testProfilingLoop` (opt-in: `TEST_RUNNER_GLIMMER_PROFILING=1`) runs a long loop for attaching Instruments. Benchmark in Release: add `-configuration Release ENABLE_TESTABILITY=YES` (Debug roughly doubles parse times)
- **Render cache sizing**: `maxRenderCacheEntries` (default 4096) must exceed the block count of documents being re-rendered, or the LRU thrashes to a 0% hit rate on sequential renders
- Profiling-verified hot paths: `AttributedString` rope operations and grapheme walking dominate render/flatten; prefer fewer, larger AttributedString operations over many small slices (a run-based tokenizer rewrite measured *slower* than rope sub-slicing — see `RevealTokenization.swift`)

## Common Development Tasks

### Adding SwiftUI Interactivity
1. Add tap handler to `MarkdownView` (e.g., `onCommitTap`)
2. Update `AttributedTextView` for gesture recognition
3. Ensure `@MainActor` for UI updates
4. Test with SwiftUI previews

### Adding a New Inline Element
1. Define token type in `MarkdownParserTypes.swift`
2. Add parsing logic to `InlineParser.swift`
3. Update `MarkdownRenderer.swift` to generate `AttributedString`
4. Add SwiftUI rendering in `MarkdownView` if interactive
5. Add tests to `Tests/GlimmerTests/`

### Adding a New Block Element
1. Define block type in `MarkdownParserTypes.swift`
2. Add detection in `BlockParser.swift`
3. Create SwiftUI view component in `MarkdownView.swift`
4. Handle `AttributedString` generation in `MarkdownRenderer.swift`
5. Test with SwiftUI previews and edge cases

### Adding a Reveal Style
1. Add the case to `RevealStyle` in `RevealTypes.swift` and fill in every mapping switch (`displayName`, `granularity`, `treatment`, `nominalUnitIntervalMs`, `unitsPerStep` — all exhaustive, the compiler enforces it)
2. If it needs a new entrance animation, add a `RevealTreatment` case, its curve in `RevealTreatments.swift`, and either a per-unit effect in `RevealUnitView` or a dedicated render path in `GlimmerRevealView` (see `RevealTrailTextView`/`RevealScrambleTextView` for cursor-driven styles)
3. Update the mapping assertions in `Tests/GlimmerTests/RevealStyleTests.swift`; put any pure math in `RevealPacing.swift` and test it in `RevealDriverTests.swift`
4. The demo picker picks up new styles automatically via `RevealStyle.allCases`

### Extending GitHub Features
1. Add pattern matching in `GFMExtensions.swift`
2. Update `MarkdownView` for SwiftUI tap callbacks
3. Use `async`/`await` for network features if needed
4. Consider caching implications

### SwiftUI Performance Optimization
1. Use `@State` for local state, `@Observable` for shared models
2. Leverage SwiftUI's automatic view diffing
3. Profile with Instruments (SwiftUI template)
4. Minimize `AttributedString` regeneration
5. Use `AsyncStream` for streaming updates (not Combine)
6. Test with `PerformanceBenchmarks`

## Module Responsibilities

- **Views**: SwiftUI components, the primary API for consumers
- **Parser**: AST generation optimized for SwiftUI rendering
- **Rendering**: AST to `AttributedString` conversion for SwiftUI `Text`
- **Reveal**: Animated streaming reveal (atom model, paced driver, reveal-aware views)
- **Utilities**: SwiftUI helpers (font mapping, text measurement, themes)
- **Linter**: Markdown validation rules
- **Export**: AST to markdown/HTML conversion

## Modern SwiftUI & Swift 6 Best Practices

### State Management
- Use `@State` for view-local state
- Use `@Observable` macro for view models (replaces `ObservableObject`)
- Use `@Binding` for two-way data flow
- Avoid `@StateObject`/`@ObservedObject` - use `@State` with `@Observable` instead
- Use `@Environment` for dependency injection

### Concurrency
- Use `@MainActor` for all UI-related code
- Leverage Swift 6 strict concurrency checking
- Prefer `async`/`await` over completion handlers
- Use `AsyncStream` for reactive streams (not Combine)
- Use SwiftUI's `.task` modifier for async operations
- Implement `Sendable` conformance for concurrent types

### SwiftUI Patterns
- Prefer SwiftUI native components over UIKit bridging
- Use view modifiers for reusable styling
- Leverage `ViewBuilder` for composable views
- Use `@Environment(\.dismiss)` for navigation
- Prefer declarative navigation APIs (iOS 16+)

### Apple Human Interface Guidelines (HIG)
- **Typography**: Use Dynamic Type for accessibility, prefer SF fonts
- **Colors**: Respect system colors and dark mode with `@Environment(\.colorScheme)`
- **Spacing**: Use standard iOS spacing (8pt grid system)
- **Touch targets**: Minimum 44x44pt for tappable elements
- **Accessibility**: Support VoiceOver, Dynamic Type, and Reduce Motion
- **Platform conventions**: Follow iOS navigation patterns and gestures
- **Semantic colors**: Use `.primary`, `.secondary`, `.accentColor`
- **Safe areas**: Respect safe area insets for all content
- **Adaptive layouts**: Support all iOS device sizes and orientations

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
            .navigationBarTitleDisplayMode(.large) // iOS navigation pattern
            .task {
                await viewModel.loadContent()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Markdown content")
    }
}
```

## Commit Guidelines
- Use present-tense summaries (e.g., "Add streaming parser chunking")
- Small, focused commits preferred
- Conventional Commits welcome (e.g., `feat(parser): add lazy windowing`)
- PR requirements:
  - Describe changes and rationale
  - Link related issues
  - Include tests for new behavior
  - Update docs/examples when relevant