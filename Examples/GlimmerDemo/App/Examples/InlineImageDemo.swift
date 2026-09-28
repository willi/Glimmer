import Glimmer
import SwiftUI

/// Images inside a paragraph: line-height squares that load through the configuration's image loader.
struct InlineImageDemo: View {
    let markdownWithImages = """
        This is a paragraph with an inline image: ![Swift Logo](https://developer.apple.com/assets/elements/icons/swift/swift-64x64.png) right in the middle of the text.

        You can also have multiple images in a line: ![Icon 1](https://picsum.photos/20/20) and ![Icon 2](https://picsum.photos/20/20) flowing with the text.

        Images work with other formatting too: **Bold text with ![tiny icon](https://picsum.photos/16/16) inside** and *italics with ![another icon](https://picsum.photos/16/16) too*.
        """

    let simpleInlineExample =
        "Check out this inline Swift logo: ![Swift](https://developer.apple.com/assets/elements/icons/swift/swift-64x64.png) - pretty cool!"

    @State private var useAssetProvider = false

    /// `DemoImageLoader` serves web URLs and, for a bare name such as `dog`, an asset or SF Symbol.
    private static let configuration = GlimmerConfiguration(imageLoader: DemoImageLoader())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Inline Image Demo")
                    .font(.largeTitle)
                    .bold()

                Text("Simple Inline Example")
                    .font(.headline)

                // Simple inline image in text
                sample(simpleInlineExample, tint: .gray)

                Text("Multiple Images with Formatting")
                    .font(.headline)

                // More complex example with multiple images
                sample(markdownWithImages, tint: .gray)

                Divider()

                Text("Custom Image Provider")
                    .font(.headline)

                Toggle("Use Asset Image Provider", isOn: $useAssetProvider)

                if useAssetProvider {
                    Text("Using local assets:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    sample("Local image: ![Dog](dog) from app bundle", tint: .blue)
                } else {
                    Text("Using default URL provider:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    sample("Remote image: ![Random](https://picsum.photos/30/30) from URL", tint: .green)
                }

                Divider()

                Text("Loading States")
                    .font(.headline)

                Text("An image shows a placeholder until it loads; a failed load keeps the placeholder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Example with slow-loading image
                sample("Slow loading image: ![Large Image](https://picsum.photos/200/300) may take a moment...", tint: .orange)

                // Example with broken image URL
                sample("Broken image: ![Missing](https://example.com/nonexistent-image.jpg) will show error state.", tint: .red)
            }
            .padding()
        }
        .navigationTitle("Inline Images")
    }

    private func sample(_ markdown: String, tint: Color) -> some View {
        GlimmerText(markdown, configuration: Self.configuration)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack { InlineImageDemo() }
}
