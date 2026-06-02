import SwiftUI
import Glimmer

/// Demo view showing GitHub custom emoji support with inline image rendering
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
    
    @State private var useAsyncRendering = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("GitHub Emoji Demo")
                    .font(.largeTitle)
                    .bold()
                
                Toggle("Use Async Image Rendering", isOn: $useAsyncRendering)
                    .padding(.bottom)
                
                if useAsyncRendering {
                    Text("Using async image loading for custom emojis:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    MarkdownTextWithAsyncImages(customEmojiExample)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Text("Using regular text rendering (no custom emoji images):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    MarkdownText(customEmojiExample)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Divider()
                
                Text("Notes")
                    .font(.headline)
                
                Text("""
                • Regular emojis like :rocket: render as Unicode text
                • Custom emojis like :octocat: render as inline images
                • Images load asynchronously with loading states
                • Failed loads show error indicators
                """)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("GitHub Emojis")
    }
}

#Preview {
    NavigationStack {
        GitHubEmojiDemo()
    }
}