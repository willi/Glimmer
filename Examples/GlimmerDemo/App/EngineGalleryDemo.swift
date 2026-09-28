import Glimmer
import SwiftUI

/// Glimmer 2.0: every markdown element rendered natively by `GlimmerText`.
struct EngineGalleryDemo: View {
    // `--gallery-dark` and `--gallery-large-text` open with those on, for screenshots.
    @State private var isDark = ProcessInfo.processInfo.arguments.contains("--gallery-dark")
    @State private var isLargeText = ProcessInfo.processInfo.arguments.contains("--gallery-large-text")
    /// The markdown copy writes for the selection, shown by the "Show Markdown" edit-menu item.
    @State private var shownMarkdown: String?
    /// `--engine-gallery-parity` shows only the 1.x-parity sections, for screenshots.
    private let text = ProcessInfo.processInfo.arguments.contains("--engine-gallery-parity")
        ? Self.parity : Self.sample + "\n\n" + Self.parity
    /// Emoji shortcodes and mentions are opt-in; the gallery shows them.
    private static let configuration = GlimmerConfiguration(extensions: [GlimmerEmojiShortcodes(), GlimmerMentions()])

    var body: some View {
        ScrollView {
            GlimmerText(
                text,
                configuration: Self.configuration,
                onLinkTap: { url in print("Tapped \(url)") },
                onTokenTap: { token in print("Tapped \(token.kind) \(token.payload)") },
                editMenuActions: { selection in
                    [UIAction(title: "Show Markdown") { _ in shownMarkdown = selection.markdown }]
                }
            )
            .padding(16)
        }
        // `--engine-gallery-bottom` opens scrolled to the end, for screenshots of the lower elements.
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--engine-gallery-bottom") ? .bottom : .top)
        .navigationTitle("Engine Gallery")
        .toolbar {
            ToolbarItemGroup {
                Toggle("Large Text", isOn: $isLargeText)
                Toggle("Dark", isOn: $isDark)
            }
        }
        .dynamicTypeSize(isLargeText ? .accessibility1 : .large)
        .preferredColorScheme(isDark ? .dark : nil)
        .alert("Markdown", isPresented: Binding(get: { shownMarkdown != nil }, set: { if !$0 { shownMarkdown = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shownMarkdown ?? "")
        }
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

    /// Glimmer 1.x markup that 2.0 renders too. Kept apart from `sample`, which the long-answer and benchmark screens
    /// repeat.
    static let parity = """
    ## Footnotes

    Glimmer numbers footnotes[^glimmer] by first reference, the way the web does[^web]. A marker whose note never \
    arrives[^missing] is still a number.

    [^glimmer]: Markers are superscript numbers in the link colour.
    [^web]: remark-gfm renders them the same way, without a heading.

    ## Emoji and mentions

    Ship it :rocket: :tada: — GitHub's own :octocat: is an image. Thanks @ada and @grace-hopper; ada@example.com \
    stays an address, and 10:30 stays a time.

    ## Inline images

    An image ![rocket](https://github.githubassets.com/images/icons/emoji/unicode/1f680.png?v8) sits in the line, \
    a square as tall as the text.

    ## More languages

    ```json
    {"name": "Ada", "languages": ["swift", "sql"], "active": true}
    ```

    ```sql
    SELECT name FROM users WHERE active = TRUE -- only active
    ```

    ```yaml
    name: Glimmer # the package
    version: 2.0
    ```
    """
}
