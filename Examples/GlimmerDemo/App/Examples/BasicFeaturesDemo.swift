import Glimmer
import SwiftUI

/// 1.x's first screen: the basics, links and GitHub references, and highlighted code, one tab each.
struct BasicFeaturesDemo: View {
    @State private var selectedTab = DemoExample.launchSection ?? 0
    @State private var lastTap: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Basic", systemImage: "text.alignleft", value: 0) {
                ScrollView {
                    GlimmerText(basicMarkdown)
                        .padding()
                }
            }

            Tab("Interactive", systemImage: "hand.tap", value: 1) {
                ScrollView {
                    GlimmerText(
                        interactiveMarkdown,
                        configuration: .demoGitHub,
                        onLinkTap: { lastTap = "Link \($0.absoluteString)" },
                        onTokenTap: { lastTap = $0.demoDescription }
                    )
                    .padding()
                }
                .safeAreaInset(edge: .bottom) { DemoTapBanner(text: lastTap) }
            }

            Tab("Code", systemImage: "curlybraces", value: 2) {
                ScrollView {
                    GlimmerText(codeMarkdown)
                        .padding()
                }
            }
        }
        .navigationTitle("Basic Features")
    }

    private let basicMarkdown = """
    # Markdown Basics
    
    ## Text Formatting
    
    This is **bold text**, this is *italic text*, and this is ***bold italic***.
    
    You can also use `inline code` and ~~strikethrough~~.
    
    ## Lists
    
    ### Unordered List
    - First item
    - Second item
      - Nested item
      - Another nested item
    - Third item
    
    ### Ordered List
    1. First step
    2. Second step
       1. Sub-step A
       2. Sub-step B
    3. Third step
    
    ## Blockquotes
    
    > This is a blockquote.
    > It can span multiple lines.
    >
    > > And can be nested too!
    
    ## Tables
    
    | Feature | Status | Notes |
    |---------|--------|-------|
    | Parsing | ✅ | Fast and efficient |
    | Rendering | ✅ | SwiftUI native |
    | Themes | ✅ | Light and dark |
    
    ## Horizontal Rule
    
    ---
    
    ## Task Lists
    
    - [x] Completed task
    - [ ] Pending task
    - [x] Another completed task
    """

    private let interactiveMarkdown = """
    # Interactive Elements
    
    ## Links
    - [Apple Developer](https://developer.apple.com)
    - [Swift.org](https://swift.org)
    - [GitHub](https://github.com)
    
    ## GitHub Features
    
    ### Mentions
    Thanks to @tim, @craig, and @johnny for their contributions!
    
    ### Issues and PRs
    - Fixed in #1234
    - See PR #5678
    - Related to issue #90
    
    ### Auto-linking
    - URLs: https://example.com/path/to/page
    - Email: support@example.com
    
    ## Combined Example
    As mentioned by @alice in #123, the solution at https://docs.swift.org works great!
    """

    private let codeMarkdown = """
    # Syntax Highlighting
    
    ## Swift
    ```swift
    struct ContentView: View {
        @State private var count = 0
        
        var body: some View {
            Button("Count: \\(count)") {
                count += 1
            }
        }
    }
    ```
    
    ## Python
    ```python
    def quicksort(arr):
        if len(arr) <= 1:
            return arr
        pivot = arr[len(arr) // 2]
        left = [x for x in arr if x < pivot]
        middle = [x for x in arr if x == pivot]
        right = [x for x in arr if x > pivot]
        return quicksort(left) + middle + quicksort(right)
    ```
    
    ## JavaScript
    ```javascript
    const fibonacci = (n) => {
        if (n <= 1) return n;
        return fibonacci(n - 1) + fibonacci(n - 2);
    };
    
    console.log(fibonacci(10));
    ```
    """
}
