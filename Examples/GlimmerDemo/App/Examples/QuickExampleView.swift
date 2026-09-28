import Glimmer
import SwiftUI

/// One markdown document on `.demoGitHub`: 1.x's README and GitHub Features examples.
struct QuickExampleView: View {
    let title: String
    let markdown: String
    @State private var lastTap: String?

    var body: some View {
        ScrollView {
            GlimmerText(
                markdown,
                configuration: .demoGitHub,
                onLinkTap: { lastTap = "Link \($0.absoluteString)" },
                onTokenTap: { lastTap = $0.demoDescription }
            )
            .padding()
        }
        .safeAreaInset(edge: .bottom) { DemoTapBanner(text: lastTap) }
        .navigationTitle(title)
    }
}

// MARK: - Example Content

let readmeExample = """
# Welcome to Glimmer! 🚀

Glimmer is a **powerful** and *flexible* Swift package for rendering **GitHub Flavored Markdown** in SwiftUI.

## Key Features

✅ Full GFM support with tables, task lists, and more\\
✅ Syntax highlighting for 18+ languages\\
✅ Interactive elements (tappable links, mentions, issues)\\
✅ Streaming for real-time updates\\
✅ Parsing off the main thread\\
✅ Copy as markdown or plain text\\
✅ Streaming support for real-time content

## Installation

Add Glimmer to your project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/willi/Glimmer", from: "2.0.0")
]
```

## Usage

```swift
import SwiftUI
import Glimmer

struct ContentView: View {
    var body: some View {
        GlimmerText("# Hello, **Glimmer**!")
    }
}
```

Made with ❤️ using Swift and SwiftUI.
"""

let githubExample = """
# GitHub Features Demo

## Mentions
Hey @octocat, check out this cool feature! Thanks to @defunkt and @mojombo for GitHub!

## Issues and Pull Requests
- Fixed critical bug in #1337
- Merged performance improvements from PR #42
- Working on feature request #999

## Emoji Support 
:rocket: Launch ready!\\
:tada: Celebration time!\\
:bug: Fixed that bug!\\
:sparkles: New features added!

## Task Lists
- [x] Implement GFM parser
- [x] Add syntax highlighting
- [x] Create interactive elements
- [ ] Write more documentation
- [ ] Add more themes

## Auto-linking
Visit https://github.com for more info\\
Contact us at support@github.com

## Combined Example
As @torvalds mentioned in #1, the Linux kernel (see https://kernel.org) is now available! :penguin:
"""
