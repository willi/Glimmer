import Glimmer
import SwiftUI

/// Glimmer 2.0: every markdown element rendered natively by `GlimmerText`.
struct EngineGalleryDemo: View {
    @State private var isDark = false

    var body: some View {
        ScrollView {
            GlimmerText(Self.sample) { url in
                print("Tapped \(url)")
            }
            .padding(16)
        }
        // `--engine-gallery-bottom` opens scrolled to the end, for screenshots of the lower elements.
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--engine-gallery-bottom") ? .bottom : .top)
        .navigationTitle("Engine Gallery")
        .toolbar {
            Toggle("Dark", isOn: $isDark)
        }
        .preferredColorScheme(isDark ? .dark : nil)
    }

    static let sample = """
    # Glimmer 2.0

    A paragraph with **bold**, *italic*, ~~strikethrough~~, `inline code`, and a [link](https://example.com). \
    Bare URLs autolink too: https://superme.ai.

    ## Lists

    - First item
    - Second item with a longer line that wraps onto the next line to show the hanging indent
      - Nested item
    1. Ordered one
    2. Ordered two
    - [x] Done task
    - [ ] Open task

    ### Quote

    > Quoted text is dimmed and gets a bar.
    > > Nested quotes get two.

    ```swift
    struct Greeting {
        let name: String // a comment
        func text() -> String { "Hello, \\(name)! 42" }
    }
    ```

    | Feature | Status | Notes |
    |:--|:-:|--:|
    | Tables | ✅ | Scroll when wide |
    | Code | ✅ | Highlighted |

    ---

    ![A placeholder image](https://picsum.photos/800/450)

    Emoji and RTL: 👋🏽 مرحبا — done.
    """
}
