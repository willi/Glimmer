import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A view that renders markdown text with support for inline images using AsyncImage.
/// This view properly tracks loading, error, and success states for each image.
public struct MarkdownTextWithAsyncImages: View {
    @State private var imageStates: [String: ImageState] = [:]
    
    private let nodes: [MarkdownParser.InlineNode]
    private let configuration: MarkdownConfiguration
    
    enum ImageState {
        case loading
        case success(Image, isEmoji: Bool)
        case failure
    }
    
    public init(_ markdown: String, configuration: MarkdownConfiguration = .default) {
        self.nodes = MarkdownParser.parseInlineOptimized(markdown, configuration: configuration)
        self.configuration = configuration
    }
    
    public var body: some View {
        renderText()
            .onAppear {
                startLoadingImages()
            }
    }
    
    @ViewBuilder
    private func renderText() -> some View {
        // Build the text view by concatenating Text views
        nodes.reduce(Text("")) { result, node in
            result + renderNode(node)
        }
    }
    
    private func renderNode(_ node: MarkdownParser.InlineNode) -> Text {
        switch node {
        case .text(let string):
            return Text(string)
            
        case .emphasis(let children):
            return children.reduce(Text("")) { $0 + renderNode($1) }
                .italic()
            
        case .strong(let children):
            return children.reduce(Text("")) { $0 + renderNode($1) }
                .bold()
            
        case .strikethrough(let children):
            return children.reduce(Text("")) { $0 + renderNode($1) }
                .strikethrough()
            
        case .code(let code):
            return Text(code)
                .font(configuration.codeFont)
                .foregroundColor(.primary)
            
        case .link(_, _, let children):
            return children.reduce(Text("")) { $0 + renderNode($1) }
                .foregroundColor(configuration.linkColor)
                .underline()
            
        case .image(let url, let alt, _):
            let urlString = url.absoluteString
            
            // Check image state
            if let state = imageStates[urlString] {
                switch state {
                case .loading:
                    // Show loading symbol while fetching
                    return Text("\(Image(systemName: "photo.badge.arrow.down")) \(alt.isEmpty ? "" : "[\(alt)]")")
                        .foregroundColor(.blue.opacity(0.7))
                    
                case .success(let image, let isEmoji):
                    // Show the loaded image inline
                    // For emojis, resize to match text size
                    if isEmoji {
                        // Emoji images should be same size as text
                        return Text(image)
                    } else {
                        return Text(image)
                    }
                    
                case .failure:
                    // Show error symbol for failed images
                    return Text("\(Image(systemName: "photo.badge.exclamationmark")) \(alt.isEmpty ? "[Failed]" : "[\(alt)]")")
                        .foregroundColor(.red.opacity(0.7))
                }
            } else {
                // Initial state before loading starts
                return Text("\(Image(systemName: "photo")) \(alt.isEmpty ? "" : "[\(alt)]")")
                    .foregroundColor(.secondary)
            }
            
        case .autolink(_, _, let originalText):
            return Text(originalText)
                .foregroundColor(configuration.linkColor)
                .underline()
            
        case .mention(let username):
            return Text("@\(username)")
                .foregroundColor(configuration.mentionColor)
                .bold()
            
        case .issueReference(let number):
            return Text("#\(number)")
                .foregroundColor(configuration.issueColor)
                .bold()
            
        case .commitSHA(_, let short):
            return Text(short)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(configuration.linkColor)
            
        case .repositoryReference(let owner, let repo):
            return Text("\(owner)/\(repo)")
                .bold()
                .foregroundColor(configuration.linkColor)
            
        case .pullRequestReference(let owner, let repo, let number):
            return Text("\(owner)/\(repo)#\(number)")
                .bold()
                .foregroundColor(configuration.linkColor)
            
        case .lineBreak, .softBreak:
            return Text("\n")
            
        case .html(let tag):
            if tag.lowercased().contains("<br") {
                return Text("\n")
            }
            return Text(tag)
            
        case .footnoteReference(let label):
            let displayLabel = label.starts(with: "inline-") ? "*" : label
            return Text("[\(displayLabel)]")
                .font(.caption2)
                .baselineOffset(6)
                .foregroundColor(configuration.linkColor)

        case .extensionInline(let node):
            return Text(node.literal)
        }
    }
    
    private func startLoadingImages() {
        // Extract all image URLs
        let imageURLs = extractImageURLs(from: nodes)
        
        for url in imageURLs {
            // Set loading state
            imageStates[url.absoluteString] = .loading
            
            // Start loading the image
            Task {
                await loadImage(from: url)
            }
        }
    }
    
    private func loadImage(from url: URL) async {
        do {
            // Use URLSession to load the image data
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Check if this is a GitHub emoji URL
            let isEmoji = url.absoluteString.contains("github.githubassets.com/images/icons/emoji")
            
            // Create platform-specific image from data and convert to SwiftUI Image
            var loadedImage: Image?
            
            #if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                // For emoji images, resize to a standard size to match text
                let finalImage: UIImage
                if isEmoji {
                    // Resize emoji to approximately text height (20pt)
                    let targetSize = CGSize(width: 20, height: 20)
                    UIGraphicsBeginImageContextWithOptions(targetSize, false, 0.0)
                    uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
                    finalImage = UIGraphicsGetImageFromCurrentImageContext() ?? uiImage
                    UIGraphicsEndImageContext()
                } else {
                    finalImage = uiImage
                }
                loadedImage = Image(uiImage: finalImage)
            }
            #endif
            
            if let image = loadedImage {
                await MainActor.run {
                    imageStates[url.absoluteString] = .success(image, isEmoji: isEmoji)
                }
            } else {
                await MainActor.run {
                    imageStates[url.absoluteString] = .failure
                }
            }
        } catch {
            await MainActor.run {
                imageStates[url.absoluteString] = .failure
            }
        }
    }
    
    private func extractImageURLs(from nodes: [MarkdownParser.InlineNode]) -> [URL] {
        var urls: [URL] = []
        
        for node in nodes {
            switch node {
            case .image(let url, _, _):
                urls.append(url)
            case .emphasis(let children), .strong(let children), .strikethrough(let children):
                urls.append(contentsOf: extractImageURLs(from: children))
            case .link(_, _, let children):
                urls.append(contentsOf: extractImageURLs(from: children))
            case .extensionInline:
                break
            default:
                break
            }
        }
        
        return urls
    }
}
