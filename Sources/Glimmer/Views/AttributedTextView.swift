import SwiftUI
#if canImport(UIKit)
import UIKit

/// Class to manage image loading and notify when complete
@MainActor
class ImageLoadingManager: ObservableObject {
    @Published var loadedImages: Set<URL> = []
    @Published var failedImages: Set<URL> = []
    private var attachments: [URL: ImageTextAttachment] = [:]
    private var loadingTasks: [URL: Task<Void, Never>] = [:]
    
    var allAttachments: [URL: ImageTextAttachment] {
        return attachments
    }
    
    func loadImage(from url: URL, attachment: ImageTextAttachment) async {
        // Store the attachment
        attachments[url] = attachment
        
        // Avoid duplicate loading
        if loadedImages.contains(url) || failedImages.contains(url) {
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                if attachment.isAvatar {
                    // Avatar sentinel: render a circular, center-cropped image sized to
                    // the surrounding line height (bounds were set in createImageAttachment).
                    let diameter = attachment.bounds.height > 0 ? attachment.bounds.height : 20
                    attachment.image = ImageLoadingManager.circularImage(from: image, diameter: diameter)
                    attachment.bounds = CGRect(
                        origin: attachment.bounds.origin,
                        size: CGSize(width: diameter, height: diameter)
                    )
                } else {
                    // Calculate proper size maintaining aspect ratio
                    let targetHeight = attachment.bounds.height > 0 ? attachment.bounds.height : 75
                    let aspectRatio = image.size.width / image.size.height
                    let scaledSize = CGSize(
                        width: targetHeight * aspectRatio,
                        height: targetHeight
                    )

                    // Update attachment with loaded image
                    attachment.image = image
                    attachment.bounds = CGRect(
                        origin: attachment.bounds.origin,
                        size: scaledSize
                    )
                }

                // Store reference and trigger update
                attachments[url] = attachment
                loadedImages.insert(url)
            } else {
                failedImages.insert(url)
            }
        } catch {
            failedImages.insert(url)
            
            // Update placeholder to show error state
            if let errorPlaceholder = createErrorPlaceholder(size: attachment.bounds.size) {
                attachment.image = errorPlaceholder
                attachments[url] = attachment
            }
        }
    }
    
    private func createErrorPlaceholder(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        
        let rect = CGRect(origin: .zero, size: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: min(6, size.width * 0.12))
        
        UIColor.systemRed.withAlphaComponent(0.1).setFill()
        path.fill()
        
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: min(size.width * 0.4, 24), weight: .regular)
        if let icon = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: symbolConfig) {
            let iconSize = icon.size
            let iconRect = CGRect(
                x: (size.width - iconSize.width) / 2,
                y: (size.height - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            
            UIColor.systemRed.set()
            icon.draw(in: iconRect)
        }

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Produces a circular, center-cropped (aspect-fill) image of the given diameter.
    /// Used for the `avatar` sentinel so inline avatars render like a round emoji.
    static func circularImage(from image: UIImage, diameter: CGFloat) -> UIImage {
        let side = max(diameter, 1)
        let canvas = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: canvas, format: .preferred())
        return renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: canvas)).addClip()
            // Aspect-fill the source into the square so the circle is fully covered.
            let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
            var drawRect = CGRect(origin: .zero, size: canvas)
            if aspect > 1 {
                let scaledWidth = side * aspect
                drawRect = CGRect(x: (side - scaledWidth) / 2, y: 0, width: scaledWidth, height: side)
            } else if aspect < 1 {
                let scaledHeight = side / aspect
                drawRect = CGRect(x: 0, y: (side - scaledHeight) / 2, width: side, height: scaledHeight)
            }
            image.draw(in: drawRect)
        }
    }
}

/// A UIViewRepresentable that displays NSAttributedString with inline images using NSTextAttachment
struct AttributedTextView: View {
    let nodes: [MarkdownParser.InlineNode]
    let configuration: MarkdownConfiguration
    let baseFont: Font?
    let onImageTap: ((URL, String) -> Void)?
    /// Called when a tapped attachment is wrapped in a link (e.g. a linked avatar);
    /// receives the link target rather than the image URL. Defaults to `nil`.
    var onLinkTap: ((URL) -> Void)? = nil
    @StateObject private var imageLoader = ImageLoadingManager()

    var body: some View {
        AttributedTextViewRepresentable(
            nodes: nodes,
            configuration: configuration,
            baseFont: baseFont,
            onImageTap: onImageTap,
            onLinkTap: onLinkTap,
            imageLoader: imageLoader,
            refreshTrigger: imageLoader.loadedImages.count + imageLoader.failedImages.count
        )
    }
}

@MainActor
private struct AttributedTextViewRepresentable: UIViewRepresentable {
    let nodes: [MarkdownParser.InlineNode]
    let configuration: MarkdownConfiguration
    let baseFont: Font?
    let onImageTap: ((URL, String) -> Void)?
    let onLinkTap: ((URL) -> Void)?
    let imageLoader: ImageLoadingManager
    let refreshTrigger: Int
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = false // Disable selection to prevent link handling
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0 // Allow unlimited lines
        textView.textContainer.widthTracksTextView = true
        textView.delegate = context.coordinator
        
        // Disable automatic link detection
        textView.dataDetectorTypes = []
        
        // Important: Don't use autolayout constraints - let SwiftUI handle sizing
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Set up tap gesture for images / linked attachments
        if onImageTap != nil || onLinkTap != nil {
            let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            textView.addGestureRecognizer(tapGesture)
        }
        
        return textView
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        // Calculate the size needed for the text
        guard let width = proposal.width else { return nil }
        
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        // Create attributed string with image loader and existing attachments
        let renderer = InlineImageRenderer(
            configuration: configuration, 
            baseFont: baseFont,
            imageLoader: imageLoader,
            existingAttachments: imageLoader.allAttachments
        )
        let attributedString = renderer.render(nodes)
        
        // Always update when we have loaded images
        if textView.attributedText?.string != attributedString.string || refreshTrigger > 0 {
            textView.attributedText = attributedString
            textView.invalidateIntrinsicContentSize()
            textView.setNeedsDisplay()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        let parent: AttributedTextViewRepresentable
        
        init(_ parent: AttributedTextViewRepresentable) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }

            let location = gesture.location(in: textView)
            let position = textView.closestPosition(to: location) ?? textView.beginningOfDocument
            let offset = textView.offset(from: textView.beginningOfDocument, to: position)

            guard offset < textView.attributedText.length else { return }
            let attributes = textView.attributedText.attributes(at: offset, effectiveRange: nil)

            // Any link target (a text link OR a linked image such as an avatar
            // `[![avatar](img)](href)`) opens its destination — the whole run is
            // tappable, not just the image glyph.
            if let onLinkTap = parent.onLinkTap,
               let linkURL = Coordinator.linkURL(from: attributes[.link]) {
                onLinkTap(linkURL)
                return
            }
            // A bare (non-linked) image attachment falls back to the image handler.
            if let attachment = attributes[.attachment] as? ImageTextAttachment {
                parent.onImageTap?(attachment.imageURL, attachment.altText)
            }
        }

        private static func linkURL(from value: Any?) -> URL? {
            if let url = value as? URL { return url }
            if let string = value as? String { return URL(string: string) }
            return nil
        }
        
        func textViewDidChange(_ textView: UITextView) {
            textView.invalidateIntrinsicContentSize()
        }
    }
    
}

/// Custom NSTextAttachment that stores image URL and alt text
class ImageTextAttachment: NSTextAttachment, @unchecked Sendable {
    let imageURL: URL
    let altText: String

    /// `true` when this is the host's avatar sentinel (`alt == "avatar"`, case-insensitive).
    /// Avatar attachments render small, circular, and baseline-aligned like an inline emoji.
    var isAvatar: Bool { altText.caseInsensitiveCompare("avatar") == .orderedSame }

    init(imageURL: URL, altText: String, image: UIImage?) {
        self.imageURL = imageURL
        self.altText = altText
        super.init(data: nil, ofType: nil)
        self.image = image
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Helper to create NSAttributedString with inline images
@MainActor
struct InlineImageRenderer {
    let configuration: MarkdownConfiguration
    let baseFont: UIFont
    let imageLoader: ImageLoadingManager?
    let existingAttachments: [URL: ImageTextAttachment]
    
    init(configuration: MarkdownConfiguration, baseFont: Font? = nil, imageLoader: ImageLoadingManager? = nil, existingAttachments: [URL: ImageTextAttachment] = [:]) {
        self.configuration = configuration
        self.imageLoader = imageLoader
        self.existingAttachments = existingAttachments
        
        // Convert SwiftUI Font to UIFont
        let font = baseFont ?? configuration.baseFont
        // Best-effort mapping from SwiftUI Font to UIFont
        self.baseFont = FontMapping.platformFont(from: font)
    }
    
    func render(_ nodes: [MarkdownParser.InlineNode]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        for node in nodes {
            let nodeResult = renderNode(node)
            
            result.append(nodeResult)
        }
        
        // Apply default paragraph style to entire result
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = .natural
        paragraphStyle.lineSpacing = 2
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        applyTextRunSpacing(to: result)
        
        return result
    }

    private func applyTextRunSpacing(to result: NSMutableAttributedString) {
        guard result.length > 0 else { return }

        let fullRange = NSRange(location: 0, length: result.length)
        var textRanges: [NSRange] = []
        result.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                textRanges.append(range)
            }
        }

        for range in textRanges {
            result.addAttribute(.kern, value: 0, range: range)
        }
    }
    
    private func renderNode(_ node: MarkdownParser.InlineNode) -> NSAttributedString {
        switch node {
        case .text(let text):
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.alignment = .natural
            
            return NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ])
            
        case .emphasis(let children):
            let content = NSMutableAttributedString()
            for child in children {
                content.append(renderNode(child))
            }
            
            // Apply italic
            content.enumerateAttribute(.font, in: NSRange(location: 0, length: content.length), options: []) { value, range, _ in
                if let font = value as? UIFont {
                    let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) ?? font.fontDescriptor
                    let italicFont = UIFont(descriptor: descriptor, size: font.pointSize)
                    content.addAttribute(.font, value: italicFont, range: range)
                }
            }
            return content
            
        case .strong(let children):
            let content = NSMutableAttributedString()
            for child in children {
                content.append(renderNode(child))
            }
            
            // Apply bold
            content.enumerateAttribute(.font, in: NSRange(location: 0, length: content.length), options: []) { value, range, _ in
                if let font = value as? UIFont {
                    let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) ?? font.fontDescriptor
                    let boldFont = UIFont(descriptor: descriptor, size: font.pointSize)
                    content.addAttribute(.font, value: boldFont, range: range)
                }
            }
            return content
            
        case .code(let text):
            return NSAttributedString(string: text, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular),
                .foregroundColor: UIColor.systemPink,
                .backgroundColor: UIColor.systemGray6
            ])
            
        case .link(let url, _, let children):
            let content = NSMutableAttributedString()
            for child in children {
                content.append(renderNode(child))
            }
            let fullRange = NSRange(location: 0, length: content.length)
            // The link target is carried over the whole range (including any image
            // attachment) so a tap on a linked avatar can resolve it.
            content.addAttribute(.link, value: url, range: fullRange)
            // Decorate text portions only — skip image attachments (e.g. a linked
            // avatar) so they render like an inline emoji, not as underlined blue text.
            content.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
                guard value == nil else { return }
                content.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
                if configuration.linkUnderline {
                    content.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
            }
            return content
            
        case .image(let url, let alt, _):
            // Create the attachment
            let attachment = createImageAttachment(url: url, alt: alt)
            
            // Create attributed string with attachment
            let attachmentString = NSAttributedString(attachment: attachment)
            
            return attachmentString
            
        case .autolink(let url, _, let originalText):
            var attributes: [NSAttributedString.Key: Any] = [
                .link: url,
                .font: baseFont,
                .foregroundColor: UIColor.systemBlue
            ]
            if configuration.linkUnderline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            return NSAttributedString(string: originalText, attributes: attributes)
            
        case .html(let content):
            // For now, just render the content without the HTML tag
            return NSAttributedString(string: content, attributes: [
                .font: baseFont,
                .foregroundColor: UIColor.label
            ])
            
        case .strikethrough(let children):
            let content = NSMutableAttributedString()
            for child in children {
                content.append(renderNode(child))
            }
            content.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: content.length))
            return content
            
        case .mention(let username):
            let displayText = "@\(username)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: UIColor.systemBlue,
                .link: URL(string: "mention://\(username)") ?? URL(string: "https://github.com/\(username)")!
            ]
            return NSAttributedString(string: displayText, attributes: attributes)
            
        case .issueReference(let number):
            let displayText = "#\(number)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: UIColor.systemBlue,
                .link: URL(string: "issue://\(number)") ?? URL(string: "#")!
            ]
            return NSAttributedString(string: displayText, attributes: attributes)
            
        case .lineBreak:
            return NSAttributedString(string: "\n", attributes: [
                .font: baseFont,
                .foregroundColor: UIColor.label
            ])
            
        case .softBreak:
            return NSAttributedString(string: " ", attributes: [
                .font: baseFont,
                .foregroundColor: UIColor.label
            ])
            
        case .commitSHA(let sha, let short):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular),
                .foregroundColor: UIColor.systemBlue,
                .link: URL(string: "commit://\(sha)") ?? URL(string: "#")!
            ]
            return NSAttributedString(string: short, attributes: attributes)
            
        case .repositoryReference(let owner, let repo):
            let displayText = "\(owner)/\(repo)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: UIColor.systemBlue,
                .link: URL(string: "repo://\(owner)/\(repo)") ?? URL(string: "#")!
            ]
            return NSAttributedString(string: displayText, attributes: attributes)
            
        case .pullRequestReference(let owner, let repo, let number):
            let displayText = "\(owner)/\(repo)#\(number)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: UIColor.systemBlue,
                .link: URL(string: "pr://\(owner)/\(repo)/\(number)") ?? URL(string: "#")!
            ]
            return NSAttributedString(string: displayText, attributes: attributes)
            
        case .footnoteReference(let label):
            let displayLabel = "[\(label)]"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: baseFont.pointSize * 0.8),
                .foregroundColor: UIColor.systemBlue,
                .baselineOffset: baseFont.pointSize * 0.3,
                .link: URL(string: "footnote://\(label)") ?? URL(string: "#")!
            ]
            return NSAttributedString(string: displayLabel, attributes: attributes)
            
        default:
            return NSAttributedString(string: "[\(String(describing: node))]", attributes: [
                .font: baseFont,
                .foregroundColor: UIColor.label
            ])
        }
    }
    
    private func createImageAttachment(url: URL, alt: String) -> ImageTextAttachment {
        // Check if we have an existing attachment with a loaded image
        if let existing = existingAttachments[url] {
            return existing
        }
        
        // Avatar sentinel (`alt == "avatar"`): a small, circular, baseline-aligned
        // image sized to ~1em (the base font's line height), like an inline emoji.
        let isAvatar = alt.caseInsensitiveCompare("avatar") == .orderedSame

        var imageSize: CGSize
        if isAvatar {
            let side = baseFont.lineHeight
            imageSize = CGSize(width: side, height: side)
        } else {
            // Determine image size based on URL patterns
            let urlString = url.absoluteString
            imageSize = CGSize(width: 20, height: 20) // Default inline size

            // Check for size patterns in URL
            if urlString.contains("/75/") || urlString.contains("/75x") {
                imageSize = CGSize(width: 75, height: 75)
            } else if urlString.contains("/50/") || urlString.contains("/50x") {
                imageSize = CGSize(width: 50, height: 50)
            } else if urlString.contains("/30/") || urlString.contains("/30x") {
                imageSize = CGSize(width: 30, height: 30)
            } else if urlString.contains("/20/") || urlString.contains("/20x") {
                imageSize = CGSize(width: 20, height: 20)
            } else if urlString.contains("/40/") || urlString.contains("/40x") {
                imageSize = CGSize(width: 40, height: 40)
            }

            // Don't scale down too much - keep images visible
            let maxHeight = max(baseFont.lineHeight * 2, imageSize.height)
            if imageSize.height > maxHeight {
                let scale = maxHeight / imageSize.height
                imageSize = CGSize(width: imageSize.width * scale, height: maxHeight)
            }
        }

        // Create placeholder image (circular for avatars)
        let placeholder = createPlaceholderImage(size: imageSize, circular: isAvatar)

        // Create the attachment with proper bounds for inline display
        let attachment = ImageTextAttachment(imageURL: url, altText: alt, image: placeholder)

        // Set bounds to align with text baseline.
        let yOffset: CGFloat
        if isAvatar {
            // Sit on the baseline like an emoji (mirrors web's vertical-align: -0.15em).
            yOffset = -baseFont.pointSize * 0.15
        } else {
            // Calculate y-offset to center image with text line
            yOffset = -(imageSize.height - baseFont.capHeight) / 2
        }
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: yOffset), size: imageSize)
        
        // Start async image loading if we have an image loader
        if let imageLoader = imageLoader {
            Task { @MainActor in
                await imageLoader.loadImage(from: url, attachment: attachment)
            }
        }
        
        return attachment
    }
    
    private func createPlaceholderImage(size: CGSize, isLoading: Bool = true, circular: Bool = false) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }

        let context = UIGraphicsGetCurrentContext()

        // Subtle background (circular for avatars, rounded rect otherwise)
        let rect = CGRect(origin: .zero, size: size)
        let path = circular
            ? UIBezierPath(ovalIn: rect)
            : UIBezierPath(roundedRect: rect, cornerRadius: min(6, size.width * 0.12))
        
        // Use different colors based on state
        if isLoading {
            context?.setFillColor(UIColor.systemGray6.cgColor)
        } else {
            context?.setFillColor(UIColor.systemRed.withAlphaComponent(0.1).cgColor)
        }
        path.fill()
        
        // Draw appropriate SF Symbol
        let symbolName = isLoading ? "photo.fill" : "exclamationmark.triangle.fill"
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: min(size.width * 0.4, 24), weight: .regular)
        
        if let icon = UIImage(systemName: symbolName, withConfiguration: symbolConfig) {
            let iconSize = icon.size
            let iconRect = CGRect(
                x: (size.width - iconSize.width) / 2,
                y: (size.height - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            
            // Set appropriate color
            if isLoading {
                UIColor.systemGray3.set()
            } else {
                UIColor.systemRed.set()
            }
            icon.draw(in: iconRect)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
}
#endif
