import SwiftUI
import Glimmer

public struct ContentView: View {
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                Section("Core Demos") {
                    NavigationLink("Basic Features", destination: BasicFeaturesDemo())
                    NavigationLink("Advanced Features", destination: AdvancedDemo())
                    NavigationLink("Markdown Linter", destination: LinterDemoView())
                }
                
                Section("Advanced Demos") {
                    NavigationLink("GitHub Flavored Markdown", destination: GFMDemo())
                    NavigationLink("Edge Cases", destination: EdgeCasesDemo())
                    NavigationLink("Inline Images", destination: InlineImageDemo())
                    NavigationLink("Tappable Images", destination: TappableImageExample())
                    NavigationLink("GitHub Emojis", destination: GitHubEmojiDemo())
                    NavigationLink("Live Preview (Demo)", destination: LivePreviewDemoScreen())
                    NavigationLink("Streaming Reveal", destination: StreamingRevealDemo())
                }
                
                Section("Performance Demos") {
                    NavigationLink("Parallel Parsing", destination: ParallelParsingDemo())
                    NavigationLink("Performance Benchmarks", destination: PerformanceDemo())
                }
                
                Section("Quick Examples") {
                    NavigationLink("README Example", destination: QuickExampleView(title: "README", markdown: readmeExample))
                    NavigationLink("GitHub Features", destination: QuickExampleView(title: "GitHub", markdown: githubExample))
                }
            }
            .navigationTitle("Glimmer Demos")
        }
    }
}

// MARK: - Example Content

private let readmeExample = """
# Welcome to Glimmer! 🚀

Glimmer is a **powerful** and *flexible* Swift package for rendering **GitHub Flavored Markdown** in SwiftUI.

## Key Features

✅ Full GFM support with tables, task lists, and more
✅ Syntax highlighting for 18+ languages  
✅ Interactive elements (tappable links, mentions, issues)
✅ Streaming for real-time updates
✅ Parallel parsing for performance
✅ Custom renderers (HTML, Plain Text, Markdown)
✅ Built-in markdown linting
✅ Streaming support for real-time content

## Installation

Add Glimmer to your project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/Glimmer", from: "1.0.0")
]
```

## Usage

```swift
import SwiftUI
import Glimmer

struct ContentView: View {
    var body: some View {
        MarkdownView(markdown: "# Hello, **Glimmer**!")
    }
}
```

Made with ❤️ using Swift and SwiftUI.
"""

private let githubExample = """
# GitHub Features Demo

## Mentions
Hey @octocat, check out this cool feature! Thanks to @defunkt and @mojombo for GitHub!

## Issues and Pull Requests
- Fixed critical bug in #1337
- Merged performance improvements from PR #42
- Working on feature request #999

## Emoji Support 
:rocket: Launch ready!
:tada: Celebration time!
:bug: Fixed that bug!
:sparkles: New features added!

## Task Lists
- [x] Implement GFM parser
- [x] Add syntax highlighting
- [x] Create interactive elements
- [ ] Write more documentation
- [ ] Add more themes

## Auto-linking
Visit https://github.com for more info
Contact us at support@github.com

## Combined Example
As @torvalds mentioned in #1, the Linux kernel (see https://kernel.org) is now available! :penguin:
"""

#Preview {
    ContentView()
}
