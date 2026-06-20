# Glimmer

A high-performance, SwiftUI-native Markdown parser and renderer with full GitHub Flavored Markdown (GFM) support.

## Features

### Core Features
- 🚀 **High Performance**: Optimized parsing with efficient memory management
- 📝 **Full GFM Support**: Complete GitHub Flavored Markdown specification support, including all GitHub autolinks
- 🎨 **Beautiful Rendering**: Proper nested list formatting, flexible image rendering, and themed syntax highlighting
- 🌈 **Extended Syntax Highlighting**: 18+ languages including Swift, Go, Rust, TypeScript, Python, Ruby, Java, C++, SQL, HTML, CSS, and JSON
- 🔗 **Interactive Elements**: Tappable links, @mentions, issue references, commit SHAs, and repository references (GitHub-specific extensions are opt-in via `.github`)
- 🔧 **Highly Configurable**: Fluent builder API for easy configuration with presets for common use cases
- 📱 **iOS Native**: Optimized specifically for iOS 18+
- 🎯 **SwiftUI Native**: Built specifically for SwiftUI with `AttributedString` rendering
- 🌓 **Dark Mode Support**: Automatic theme adaptation for UI elements
- 😊 **Emoji Support**: Over 1900 GitHub emoji shortcodes with automatic conversion
- 🖼️ **Inline Images**: Async loading of inline images with loading/error states
- 🎭 **Custom GitHub Emojis**: Support for GitHub's custom emojis (octocat, atom, etc.) as inline images

### Advanced Features
- ⚡ **Parallel Parsing**: Multi-threaded parsing for documents >10KB with configurable concurrency
- 💾 **Advanced Caching**: Size-limited cache (50MB default) with TTL, LRU eviction, and memory pressure handling
- 🌊 **Streaming Support**: Process markdown incrementally with `StreamingMarkdownView` for real-time updates
- ✨ **Streaming Reveal**: Animated per-word/character reveal of streaming LLM output via `GlimmerRevealView` — 11 styles (typewriter, word fade, blur-in, shimmer, diffusion, trail fade, …) with adaptive catch-up and cross-remount resume
- 🔍 **Markdown Linting**: 20+ configurable lint rules with severity levels and fix suggestions
- 📤 **Multiple Export Formats**: Export to HTML, Plain Text, or back to Markdown
- 🎭 **Custom Renderers**: Protocol-based extensibility for custom output formats
- 🔄 **Live Preview Demo**: Diff-based updates with debouncing in the demo app
- 📊 **Performance Metrics**: Built-in performance tracking and benchmarking
- 🧩 **Modular Architecture**: Clean separation of concerns with focused modules
- 🔧 **Configuration Builder**: Fluent API for easy customization

## Installation

### Swift Package Manager

Add Glimmer to your project through Xcode:

1. File → Add Package Dependencies
2. Add the package URL or local path
3. Select "Glimmer" product

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../Packages/Glimmer")
]
```

## Usage

### Basic Usage

```swift
import Glimmer
import SwiftUI

struct ContentView: View {
    let markdown = """
    # Hello, Glimmer!
    
    This is a **bold** statement with *italic* text.
    
    Here is a footnote reference.[^1]
    
    [^1]: This is the footnote's content.
    
    ```swift
    struct MyView: View {
        var body: some View {
            Text("Hello, Syntax Highlighting!")
        }
    }
    ```
    """
    
    var body: some View {
        MarkdownView(markdown: markdown)
    }
}
```

### Advanced Usage

```swift
// Use with custom configuration
MarkdownView(
    markdown: markdown,
    configuration: MarkdownConfiguration(
        baseFont: .custom("Georgia", size: 16),
        codeFont: .custom("Menlo", size: 14),
        textColor: .primary,            // Foreground color for body text
        linkColor: .purple,
        codeBlockTheme: .dark // Use a dark theme for code blocks
    )
)

// Interactive usage with callbacks (GitHub extensions need the .github preset)
MarkdownView(
    markdown: content,
    configuration: .github,
    onLinkTap: { url in 
        // Handle link tap
        print("Tapped link: \(url)")
    },
    onMentionTap: { username in 
        // Handle @mention tap
        print("Tapped mention: @\(username)")
    },
    onIssueTap: { issueNumber in 
        // Handle #issue tap
        print("Tapped issue: #\(issueNumber)")
    }
)

// Configuration Builder API
let config = MarkdownConfiguration.builder()
    .enableGitHubFeatures()
    .setTheme(.dark)
    .setImageSize(maxWidth: 300)
    .setCacheSettings(maxSizeMB: 50, timeToLiveSeconds: 300)
    .build()

MarkdownView(markdown: content, configuration: config)

// Streaming markdown for real-time updates
StreamingMarkdownView(markdown: streamingContent)

// Parallel and streaming strategies are available for large documents

// Export to different formats
let blocks = MarkdownParser.parse(markdown)
let html = HTMLMarkdownRenderer().render(blocks: blocks)
let plainText = PlainTextMarkdownRenderer().render(blocks: blocks)
let exportedMarkdown = MarkdownExporter.export(blocks)

// Inline images with async loading
let markdownWithImages = """
Here's an inline image: ![Logo](https://example.com/logo.png) in the text.
GitHub emojis work too: :rocket: :octocat: :atom:
"""

// Use MarkdownTextWithAsyncImages for inline image support
MarkdownTextWithAsyncImages(markdownWithImages)
```

## Supported Markdown Features

### Block Elements
- **Headings** (H1-H6)
- **Paragraphs**
- **Lists** (ordered, unordered, nested with proper formatting)
- **Task Lists** with checkboxes
- **Blockquotes**
- **Code Blocks** with syntax highlighting for Swift, Python, JavaScript, and Ruby
- **Tables**
- **Horizontal Rules**
- **Footnotes**

### Inline Elements
- **Bold** (`**text**` or `__text__`)
- **Italic** (`*text*` or `_text_`)
- **Strikethrough** (`~~text~~`)
- **Inline Code** (`` `code` ``)
- **Links** (`[text](url)`)
- **Images** (`![alt](url)`)
- **Autolinks** (`<https://example.com>` or `<user@example.com>`)

### GitHub Extensions

> **Disabled by default.** All GitHub-specific extensions below (except task lists, which are core markdown here) are opt-in: use the `MarkdownConfiguration.github` preset, `MarkdownConfiguration.builder().enableGitHubFeatures()`, or the individual `enable…` flags. The default configuration renders plain CommonMark-style markdown (including tables, task lists, and strikethrough).

- **@mentions** (e.g., @username)
- **Issue References** (e.g., #123)
- **Task Lists** (`- [ ]` and `- [x]`)
- **Extended Autolinks** (bare URLs without angle brackets)
  - URLs: `https://github.com`, `http://example.com`, `www.example.com`
  - Email addresses are not auto-linked without angle brackets
- **Commit SHAs** (e.g., `a5c3785ed8d6a35868bc169f07e40e889087fd2e`)
  - Displays first 7 characters but preserves full SHA
- **Repository References** (e.g., `facebook/react`, `apple/swift`)
  - Links to GitHub repository
- **Pull Request References** (e.g., `apple/swift-evolution#1988`)
  - Combines repository reference with issue number
- **Emoji Shortcodes** (e.g., `:rocket:`, `:+1:`, `:octocat:`)
  - Over 1900 GitHub emoji shortcodes supported
  - Custom GitHub emojis (`:octocat:`, `:atom:`, `:basecamp:`, etc.) render as inline images
  - Emoji images automatically sized to match text height

## Configuration Builder

The new fluent builder API makes configuration easy and discoverable:

```swift
let config = MarkdownConfiguration.builder()
    .enableGitHubFeatures()
    .setTheme(.dark)
    .setImageSize(maxWidth: 300)
    .setCacheSettings(maxSizeMB: 100, timeToLiveSeconds: 600)
    .setMaxIterations(blocks: 5000, inline: 25000)
    .setPerformanceTracking(true)
    .build()

// Or use presets
let githubConfig = MarkdownConfiguration.github
let minimalConfig = MarkdownConfiguration.minimal
let performanceConfig = MarkdownConfiguration.performance
```

## Syntax Highlighting

Code blocks can be highlighted by specifying a language. **18+ languages** are now supported including:

- **Systems**: Swift, Go, Rust, C/C++, Java, Kotlin
- **Web**: TypeScript, JavaScript, PHP, HTML, CSS, JSON, YAML
- **Scripting**: Python, Ruby, Shell/Bash, SQL

You can customize the look and feel using `CodeHighlightingTheme`. Two themes, `.light` and `.dark`, are provided out of the box.

```swift
MarkdownView(
    markdown: """
    ```python
    def hello_world():
        print("Hello from Glimmer!")
    ```
    """,
    configuration: MarkdownConfiguration(
        codeBlockTheme: .dark // Or .light, or a custom theme
    )
)
```

## Markdown Linting

Glimmer includes a comprehensive markdown linter with 20+ configurable rules:

```swift
let issues = MarkdownLinter.lint(markdown, configuration: .strict)

for issue in issues {
    print("[\(issue.rule)] Line \(issue.line):\(issue.column) - \(issue.message)")
    if let suggestion = issue.suggestion {
        print("  💡 \(suggestion)")
    }
}
```

### Lint Rule Categories

- **Structure**: Title heading requirements, incremental heading levels
- **Formatting**: Line length, trailing spaces, consistent list markers
- **Links**: Empty links, broken local links, reference link preferences
- **Code**: Language specification, empty code blocks, consistent fence style
- **Style**: Consistent emphasis markers, whitespace rules

### Configuration

```swift
var config = MarkdownLinter.LintConfiguration()
config.maxLineLength = 100
config.requireTitleHeading = true
config.incrementalHeadings = true
config.fencedCodeLanguage = true
config.consistentListMarkers = true

// Or use presets
let strictConfig = MarkdownLinter.LintConfiguration.strict
```

## Advanced Parsing Strategies

### Parallel Parsing

Leverage multiple CPU cores for large documents:

```swift
// Configure parallel parsing
let config = ParallelMarkdownParser.ParallelConfiguration(
    concurrency: 4,                    // Number of threads
    minimumSizeThreshold: 10000,      // Min size to trigger parallel
    chunkSize: 5000                   // Size of each chunk
)

let parser = ParallelMarkdownParser(parallelConfig: config)

// Parse with progress tracking
parser.parseAsync(markdown, 
    progress: { progress in
        print("Parsing: \(Int(progress * 100))%")
    },
    completion: { blocks in
        // Use parsed blocks
    }
)

// Or parse synchronously when progress callbacks are not needed
let blocks = parser.parse(markdown)
```

For detailed timing reports, use the demo app's Performance Benchmarks screen or
`Tests/GlimmerTests/ProfilingBenchmarkTests.swift`.

### Streaming Parser

Process large markdown documents incrementally:

```swift
let parser = StreamingMarkdownParser(configuration: .default)

// Process chunks as they arrive
for chunk in dataStream {
    let blocks = parser.parseChunk(chunk)
    // Render completed blocks immediately
    updateUI(with: blocks)
}

// Get any remaining blocks
let finalBlocks = parser.finish()
```

### Use Cases

- **Real-time editing**: Show preview as users type
- **Large files**: Process multi-megabyte documents without memory issues
- **Network streaming**: Display content as it downloads
- **Progressive rendering**: Better perceived performance

## Streaming Reveal

`GlimmerRevealView` renders streaming LLM/chat output with per-unit animated reveal — fully styled markdown from the first frame (no raw `**` markers), settling into Glimmer's normal rendering with zero layout pop because the reveal path *is* the settled path.

```swift
GlimmerRevealView(
    markdown: message.text,                        // grows as tokens stream in
    reveal: RevealConfiguration(
        style: .wordFade,                          // any of the 11 styles
        catchUp: .adaptive(maxLagSeconds: 1.5),    // accelerate when the buffer races ahead
        isStreaming: message.isStreaming,
        revealID: message.turnID                   // resume across re-mounts (optimistic→final swaps)
    ),
    onLinkTap: { url in /* handle */ },
    onComplete: { /* reveal finished */ }
)

// One-shot mode for previews/demos (fits long inputs into a duration cap):
GlimmerRevealView.demo("# Hello **world**", style: .shimmer, durationCap: 6)
```

**Styles** (`RevealStyle`): `typewriter` (blinking caret), `llmTokens`, `wordFade`, `blurIn`, `lineSlide`, `charCascade`, `shimmer`, `tracking`, `diffusion` (scramble→lock), `waveGlow`, and `trailFade` (a soft opacity gradient trailing the cursor, like Gemini's reveal). Use `.none` to opt out entirely.

The reveal cadence is clock-driven and decoupled from how fast text arrives; rich elements (code blocks, tables, images, blockquotes) reveal as whole units, links stay tappable, VoiceOver reads the full text, and Reduce Motion downgrades to a plain progressive reveal. For append-only streams, `GlimmerRevealView` uses an internal `RevealSession` that reuses completed parsed/flattened blocks and reparses only the current tail, falling back to the canonical full parse path for replacements or unsafe boundaries. Try every style in the demo app under **Advanced Demos → Streaming Reveal**.

## Custom Renderers

Render markdown to different output formats:

### HTML Renderer

```swift
let htmlRenderer = HTMLMarkdownRenderer(options: .init(
    includeCSS: true,
    cssClasses: .defaultClasses,
    syntaxHighlightTheme: "github",
    wrapInHTML: true  // Full HTML document
))

let html = htmlRenderer.render(blocks: blocks, configuration: .default)
```

### Plain Text Renderer

```swift
let plainRenderer = PlainTextMarkdownRenderer()
let plainText = plainRenderer.render(blocks: blocks, configuration: .default)
// Extracts text content without formatting
```

### Custom Renderer Protocol

```swift
struct MyCustomRenderer: MarkdownRendererProtocol {
    typealias Output = MyCustomFormat
    
    func render(blocks: [BlockNode], configuration: MarkdownConfiguration) -> Output {
        // Custom rendering logic
    }
}
```

## Live Preview with Diffing

A diff-based live preview example is available in
`Examples/GlimmerDemo/LivePreviewDemo.swift`.

This utility is currently demo-only and is not part of Glimmer's public library API.

## AST Export

Convert parsed markdown back to text with customizable options:

```swift
// Parse markdown to AST
let blocks = MarkdownParser.parse(markdown, configuration: .default)

// Export back to markdown
let exportedMarkdown = MarkdownExporter.export(blocks, options: .default)

// Custom export options
var options = MarkdownExporter.ExportOptions()
options.useATXHeaders = true  // Use ### style headers
options.emphasisMarker = "_"  // Use _ for emphasis
options.strongMarker = "**"   // Use ** for strong
options.unorderedListMarker = "-"  // Use - for lists
options.indentSize = 2  // Spaces per indent level

let customExport = MarkdownExporter.export(blocks, options: options)
```

## Architecture

Glimmer uses a modular architecture:

```
Sources/Glimmer/
├── Glimmer.swift
├── MarkdownConfiguration.swift
├── MarkdownConfigurationBuilder.swift
├── Parser/
│   ├── BlockParser.swift
│   ├── CachedMarkdownParser.swift
│   ├── CancellableParallelOperation.swift
│   ├── GFMExtensions.swift
│   ├── GitHubEmojiLookup.swift
│   ├── GitHubEmojis.swift
│   ├── InlineParser.swift
│   ├── MarkdownParser.swift
│   ├── MarkdownParserTypes.swift
│   ├── ParallelParser.swift
│   ├── ParserState.swift
│   └── StreamingMarkdownParser.swift
├── Rendering/
│   ├── CustomRenderer.swift
│   └── MarkdownRenderer.swift
├── Reveal/
│   ├── GlimmerRevealView.swift
│   ├── RevealAtom.swift
│   ├── RevealDriver.swift
│   ├── RevealFlattener.swift
│   ├── RevealFlowLayout.swift
│   ├── RevealPacing.swift
│   ├── RevealProgressStore.swift
│   ├── RevealSession.swift
│   ├── RevealTokenization.swift
│   ├── RevealTreatments.swift
│   └── RevealTypes.swift
├── Views/
│   ├── AttributedTextView.swift
│   ├── FootnoteDetailView.swift
│   ├── MarkdownBlockStableID.swift
│   ├── MarkdownInlineAttributedCache.swift
│   ├── MarkdownText.swift
│   ├── MarkdownTextWithAsyncImages.swift
│   ├── MarkdownView.swift
│   ├── PerformanceDemo.swift
│   └── StreamingMarkdownView.swift
├── Linter/MarkdownLinter.swift
├── Export/MarkdownExporter.swift
└── Utilities/
    ├── CodeHighlightingTheme.swift
    ├── FontMapping.swift
    ├── ListFormatting.swift
    ├── ParsingHelpers.swift
    ├── SyntaxHighlighter.swift
    └── TextMeasurement.swift
```

## Debugging

### Table Cell Debugging

When debugging table layout issues, you can enable green borders on table cells to visualize their boundaries:

1. In `MarkdownView.swift`, locate the `MarkdownTableCell` and `InteractiveTableCell` structs
2. Add `.border(Color.green)` to the cell views:

```swift
// For MarkdownTableCell
}
.frame(width: width, alignment: alignment(for: cell.alignment))
.clipped()
.border(Color.green)  // Add this line

// For InteractiveTableCell  
}
.clipped()
.border(Color.green)  // Add this line
```

3. For empty cells in incomplete rows, add the border to placeholder views:

```swift
Color.clear
    .frame(width: cellIndex < columnWidths.count ? columnWidths[cellIndex] : 100)
    .border(Color.green)  // Add this line
```

These green borders help visualize:
- Exact cell boundaries and widths
- Cell alignment in the grid
- Empty cell placement
- Overall table structure

Remember to remove these debug borders before committing your changes.

## Performance

The parser includes several advanced optimizations:

### Core Optimizations
- **Efficient parsing**: Consolidated parser implementation with optimized memory management
- **Lazy evaluation**: Defer parsing blocks until needed for large documents
- **Parallel processing**: Multi-threaded parsing with 3.2x speedup on 4-core systems
- **Smart caching**: LRU cache with size limits (50MB default) and TTL
- **Memory management**: Fragment pools and efficient buffer reuse with memory pressure handling

### Performance Benchmarks

Interactive benchmarks are available in the demo app:

- Open `Examples/GlimmerDemo/GlimmerDemo.xcodeproj`
- Run the app on an iOS 18+ simulator
- Navigate to Performance Demos → Performance Benchmarks
- Configure corpus size, iterations, and streaming chunk size, then Run

Advanced toggles for experimentation:
- `InlineParser.useUTF8FastPath = true` to enable a UTF‑8 byte-scanning fast path for some ASCII patterns
- `GitHubEmojis.useLazyEmojiURLMap = true` to load a small JSON override map and fall back to the static full map

For CLI profiling, `Tests/GlimmerTests/ProfilingBenchmarkTests.swift` prints per-phase timings (parse, render, cache warm/cold, reveal flatten, and incremental reveal-session growth) over a ~0.5MB complex corpus, and its `testProfilingLoop` (opt in with `GLIMMER_PROFILING=1`) runs a long loop for attaching Instruments. Benchmark in Release when comparing numbers:

```bash
xcodebuild -scheme Glimmer -configuration Release ENABLE_TESTABILITY=YES -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:GlimmerTests/ProfilingBenchmarkTests/testPhaseTimings
```

`Tests/GlimmerTests/MarkdownDisplayProfilingTests.swift` provides an opt-in SwiftUI scroll/layout loop for display profiling. Run it under Instruments or `xcrun xctrace` with:

```bash
TEST_RUNNER_GLIMMER_DISPLAY_PROFILING=1 TEST_RUNNER_GLIMMER_DISPLAY_PROFILE_SECONDS=8 \
xcodebuild -scheme Glimmer -configuration Release ENABLE_TESTABILITY=YES -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:GlimmerTests/MarkdownDisplayProfilingTests/testMarkdownDisplayScrollLoop
```

### Benchmark Results
- **Large documents**: Optimized for fast parsing
- **Memory usage**: Efficient memory management with consolidated parsers
- **Cache hit rate**: 95%+ for repeated parsing
- **Parallel speedup**: 3.2x on 4-core systems
- **Streaming**: Handles 100MB+ documents efficiently
- **Streaming reveal**: Append-only growth reuses completed reveal blocks via `RevealSession` instead of reparsing and flattening the whole buffer on every token update

### Advanced Caching
```swift
// Configure cache settings
let config = MarkdownConfiguration.builder()
    .setCacheSettings(
        maxSizeMB: 100,           // Maximum cache size
        timeToLiveSeconds: 600    // Cache entry TTL
    )
    .build()

// Cache automatically handles:
// - Size limits with LRU eviction
// - Time-based expiration
// - Memory pressure (iOS)
// - Thread-safe operations
```

The per-block render cache (`maxRenderCacheEntries`, default 4096) must comfortably exceed the block count of the largest documents you re-render — an LRU smaller than the working set thrashes on sequential renders and hits 0%. The `.performance` preset uses 8192. Repeated inline SwiftUI display rendering also uses `MarkdownInlineAttributedCache`, keyed by inline AST semantics and render mode.

### Performance Metrics
Use the benchmark harnesses for timing and the cache APIs for hit/miss counters:

```swift
let blocks = Glimmer.parse(markdown, configuration: .performance)
let renderStats = Glimmer.getRenderCacheStatistics()

let cache = CachedMarkdownParser()
_ = cache.parse(markdown, configuration: .performance)
let parserStats = cache.getCacheStatistics()
```

### Memory Pressure Handling
On iOS, the cache automatically responds to memory warnings:
- **Normal**: Cleans expired entries
- **Warning**: Evicts 50% of LRU entries  
- **Critical**: Clears entire cache

## Requirements

- iOS 18.0+
- Swift 6.0+
- Xcode 16.0+

## Testing

This package targets iOS; prefer running tests in an iOS simulator.
`swift build` / `swift test` on macOS are not supported for this package.

Examples (from the repo root):

```bash
# List schemes
xcodebuild -list

# Run tests on an installed iOS simulator (update device name if needed;
# list devices with: xcrun simctl list devices available)
xcodebuild -scheme Glimmer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Or open Package.swift in Xcode and run the GlimmerTests target
```

## Examples

Check out the `Examples/` directory for comprehensive demos showcasing all of Glimmer's features.

### Demo Structure

#### Core Demos
- **Basic Features**: Markdown basics, interactive elements, and syntax highlighting
- **Advanced Features**: Configuration builder, streaming, performance testing, and export
- **Markdown Linter**: Real-time validation and best practices checking

#### Advanced Demos
- **Streaming Reveal**: All 11 reveal styles with a simulated LLM token stream and one-shot playback
- **GitHub Flavored Markdown**, **Edge Cases**, **Inline Images**, **GitHub Emojis**, **Live Preview**

#### Performance Demos
- **Parallel Parsing**: Multi-threaded parsing with metrics
- **Performance Benchmarks**: Compare Sequential, Parallel, and Streaming

#### Quick Examples
- **README Example**: Common markdown patterns
- **GitHub Features**: GitHub-specific extensions

### Running Examples

```bash
open Examples/GlimmerDemo/GlimmerDemo.xcodeproj

# Optional: build demo from CLI
xcodebuild -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo -destination 'generic/platform=iOS Simulator' build
```

See [Examples/README.md](Examples/README.md) for detailed documentation.

## License

MIT License - see [LICENSE](LICENSE) file for details.
