import Glimmer
import SwiftUI

/// Demo view showing inline image support in Glimmer
struct InlineImageDemo: View {
    let markdownWithImages = """
        This is a paragraph with an inline image: ![Swift Logo](https://developer.apple.com/assets/elements/icons/swift/swift-64x64.png) right in the middle of the text.

        You can also have multiple images in a line: ![Icon 1](https://picsum.photos/20/20) and ![Icon 2](https://picsum.photos/20/20) flowing with the text.

        Images work with other formatting too: **Bold text with ![tiny icon](https://picsum.photos/16/16) inside** and *italics with ![another icon](https://picsum.photos/16/16) too*.
        """

    let simpleInlineExample =
        "Check out this inline Swift logo: ![Swift](https://developer.apple.com/assets/elements/icons/swift/swift-64x64.png) - pretty cool!"

    @State private var useAssetProvider = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Inline Image Demo")
                    .font(.largeTitle)
                    .bold()

                Text("Simple Inline Example")
                    .font(.headline)

                // Simple inline image in text
                MarkdownTextWithAsyncImages(simpleInlineExample)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)

                Text("Multiple Images with Formatting")
                    .font(.headline)

                // More complex example with multiple images
                MarkdownTextWithAsyncImages(markdownWithImages)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)

                Divider()

                Text("Custom Image Provider")
                    .font(.headline)

                Toggle("Use Asset Image Provider", isOn: $useAssetProvider)

                if useAssetProvider {
                    Text("Using local assets:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    MarkdownTextWithAsyncImages("Local image: ![Dog](dog) from app bundle")
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Text("Using default URL provider:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    MarkdownTextWithAsyncImages(
                        "Remote image: ![Random](https://picsum.photos/30/30) from URL"
                    )
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }

                Divider()

                Text("Loading States")
                    .font(.headline)

                Text("Images show different symbols for loading, error, and success states.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Example with slow-loading image
                MarkdownTextWithAsyncImages(
                    "Slow loading image: ![Large Image](https://picsum.photos/200/300) may take a moment..."
                )
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                
                // Example with broken image URL
                MarkdownTextWithAsyncImages(
                    "Broken image: ![Missing](https://example.com/nonexistent-image.jpg) will show error state."
                )
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Inline Images")
    }
}

#Preview {
    NavigationStack {
        InlineImageDemo()
    }
}

#Preview {
    NavigationStack {
        InlineImageDemo()
    }
}
