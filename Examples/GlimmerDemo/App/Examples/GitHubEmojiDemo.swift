import Glimmer
import SwiftUI

/// `GlimmerEmojiShortcodes`: GitHub's `:shortcodes:`, standard ones as emoji and GitHub's own as inline images.
struct GitHubEmojiDemo: View {
    let customEmojiExample = """
    # GitHub Custom Emojis
    
    ## Regular Unicode Emojis
    These render as text: :rocket: :smile: :heart: :+1:
    
    ## Custom GitHub Emojis (as images)
    These should render as inline images:
    - Octocat: :octocat:
    - Atom: :atom:
    - Electron: :electron:
    - Basecamp: :basecamp:
    - Bowtie: :bowtie:
    - Shipit: :shipit:
    
    ## Mixed in sentences
    The :octocat: mascot is awesome! Let's :shipit: with :electron: and :atom:!
    
    ## Emojis in different contexts
    **Bold with emoji: :octocat: is bold**
    *Italic with emoji: :atom: is italic*
    ~~Strikethrough with emoji: :basecamp: is struck~~
    
    ## In lists
    - :octocat: GitHub's mascot
    - :atom: Atom editor
    - :electron: Electron framework
    
    ## In code blocks (should not render)
    ```
    This :octocat: should not render as an emoji
    ```
    
    Inline code: `:rocket:` should not render either.
    """

    @State private var usesShortcodes = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("GitHub Emoji Demo")
                    .font(.largeTitle)
                    .bold()

                Toggle("Emoji Shortcodes Extension", isOn: $usesShortcodes)
                    .padding(.bottom)
                    .accessibilityIdentifier("emoji.toggle")

                if usesShortcodes {
                    Text("With GlimmerEmojiShortcodes in the configuration:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    GlimmerText(customEmojiExample, configuration: GlimmerConfiguration(extensions: [GlimmerEmojiShortcodes()]))
                        .padding()
                        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Without it, shortcodes stay text:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    GlimmerText(customEmojiExample)
                        .padding()
                        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                Text("Notes")
                    .font(.headline)

                Text("""
                • Regular emojis like :rocket: render as Unicode text
                • Custom emojis like :octocat: render as inline images
                • Images load through the configuration's image loader
                • A failed load keeps the placeholder
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("GitHub Emojis")
    }
}

#Preview {
    NavigationStack { GitHubEmojiDemo() }
}
