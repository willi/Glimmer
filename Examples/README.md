# Glimmer Examples

This directory contains example projects demonstrating how to use Glimmer.

## GlimmerDemo

A comprehensive SwiftUI app showcasing Glimmer's markdown parsing and rendering capabilities.

### Demo Structure

The demo app is organized into three main categories:

#### Core Demos
- **Basic Features**: Comprehensive demonstration of markdown basics, interactive elements, and syntax highlighting
- **Advanced Features**: Configuration builder, streaming, performance testing, and export capabilities
- **Markdown Linter**: Real-time markdown validation and best practices checking

#### Advanced Demos
- **GitHub Flavored Markdown**: Complete GFM specification with all GitHub-specific features across 10 categories
- **Edge Cases**: Comprehensive test suite for challenging markdown scenarios and parser edge cases
- **Inline Images**: Async loading of inline images with loading/error states and SF Symbol indicators
- **Tappable Images**: Custom image tap handling and interactive image URLs
- **GitHub Emojis**: Custom GitHub emojis (octocat, atom, etc.) rendered as properly-sized inline images
- **Live Preview (Demo)**: Diff-based markdown updates with editor/preview split view

#### Performance Demos
- **Parallel Parsing**: Multi-threaded parsing with performance metrics and comparisons
- **Performance Benchmarks**: Compare Sequential, Parallel, and Streaming with configurable runs

#### Quick Examples
- **README Example**: Shows a typical README with all common markdown elements
- **GitHub Features**: Demonstrates GitHub-specific markdown extensions

## How to Run the Examples

### Option 1: Open in Xcode (Recommended)

1. **Open the project**:
   ```bash
   cd Examples
   open GlimmerDemo.xcodeproj
   ```

2. **Select a target**: Choose iPhone or iPad
3. **Run**: Press ⌘R or click the Run button

### Option 2: Create a New App

1. **Create a new SwiftUI project** in Xcode
2. **Add Glimmer as a package dependency**:
   - File → Add Package Dependencies
   - Add local path to the Glimmer root directory
3. **Import and use**:
   ```swift
   import SwiftUI
   import Glimmer
   
   @main
   struct MyApp: App {
       var body: some Scene {
           WindowGroup {
               ContentView() // From GlimmerDemo
           }
       }
   }
   ```

### Option 3: Command Line (xcodebuild)

```bash
# From repo root, list schemes
xcodebuild -list -project Examples/GlimmerDemo.xcodeproj

# Build the demo app for iOS Simulator
xcodebuild -project Examples/GlimmerDemo.xcodeproj -scheme GlimmerDemo -destination 'generic/platform=iOS Simulator' build
```

## Features Demonstrated

### Basic Markdown
- Headers (H1-H6)
- Bold, italic, strikethrough text
- Ordered and unordered lists
- Blockquotes (including nested)
- Horizontal rules
- Tables with alignment
- Task lists

### Code & Syntax
- Inline code
- Code blocks with syntax highlighting
- Support for 18+ languages
- Theme customization (light/dark)

### Interactive Elements
- Clickable links with custom handlers
- GitHub @mentions
- Issue/PR references (#123)
- Auto-linking URLs and emails
- Footnotes with popover support
- Inline images with async loading
- GitHub custom emojis as images

### Advanced Features
- **Streaming**: Real-time progressive rendering
- **Parallel Parsing**: Multi-threaded for large documents
- **Custom Renderers**: Export to HTML, plain text, or markdown
- **Configuration Builder**: Fluent API for customization
- **Markdown Linting**: Validate and improve markdown quality

## Example Usage

### Basic Integration

```swift
import Glimmer

struct ContentView: View {
    let markdown = """
    # Welcome to Glimmer!
    
    This is **bold** and this is *italic*.
    
    - List item 1
    - List item 2
    
    [Visit GitHub](https://github.com)
    """
    
    var body: some View {
        MarkdownView(markdown: markdown)
    }
}
```

### Interactive Features

```swift
MarkdownView(
    markdown: content,
    configuration: .default,
    onLinkTap: { url in
        print("Link tapped: \(url)")
    },
    onMentionTap: { username in
        print("Mention: @\(username)")
    },
    onIssueTap: { issue in
        print("Issue: #\(issue)")
    }
)
```

### Streaming Content

```swift
StreamingMarkdownView(markdown: streamingContent)
```

### Custom Configuration

```swift
let config = MarkdownConfiguration.builder()
    .enableGitHubFeatures()
    .setTheme(.dark)
    .setImageSize(maxWidth: 300)
    .setCacheSettings(maxSizeMB: 50, timeToLiveSeconds: 300)
    .build()

MarkdownView(markdown: content, configuration: config)
```

### Inline Images

```swift
// Markdown with inline images and custom emojis
let markdown = """
Here's an inline image: ![Logo](https://example.com/logo.png)
GitHub emojis: :rocket: :octocat: :atom: :basecamp:
"""

// Use MarkdownTextWithAsyncImages for inline image support
MarkdownTextWithAsyncImages(markdown)
```

## Project Structure

```
Examples/
├── README.md                     # This file
├── Package.swift                 # SPM configuration
├── GlimmerDemo.xcodeproj/       # Xcode project
└── GlimmerDemo/
    ├── ContentView.swift         # Main navigation
    ├── EdgeCasesDemo.swift       # Edge cases and parser stress demos
    ├── EditorTextView.swift      # UITextView wrapper for live preview editor
    ├── GFMDemo.swift             # GitHub Flavored Markdown demo
    ├── GitHubEmojiDemo.swift     # GitHub custom emoji demo
    ├── GlimmerDemo.swift         # Shared demo content
    ├── GlimmerDemoApp.swift      # App entry point
    ├── InlineImageDemo.swift     # Inline image loading demo
    ├── LinterDemoView.swift      # Linter demo
    ├── LivePreviewDemo.swift     # Diff-based live preview demo
    ├── MainDemos.swift           # Basic/advanced demo tabs
    ├── ParallelParsingDemo.swift # Parallel parsing demo
    ├── QuickExampleView.swift    # Simple example viewer
    └── TappableImageExample.swift # Image tap callbacks demo
```

## Requirements

- iOS 18.0+
- Xcode 16.0+
- Swift 6.0+

## Troubleshooting

### Build Errors

If you encounter build errors:
1. Clean build folder: Product → Clean Build Folder (⌘⇧K)
2. Reset package caches: File → Packages → Reset Package Caches
3. Delete derived data and restart Xcode
4. Use `xcodebuild` (not `swift build`/`swift test`) for this iOS-only package

### Import Errors

If "No such module 'Glimmer'" appears:
1. Ensure Glimmer is properly added as a dependency
2. Check that minimum deployment targets match
3. Verify the package path is correct

## License

See the main project LICENSE file for details.
