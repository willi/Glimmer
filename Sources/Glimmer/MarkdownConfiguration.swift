
import SwiftUI

/// A comprehensive configuration for the Glimmer parser and renderer.
///
/// This single configuration object allows you to customize both the parsing features
/// (like GitHub-flavored extensions) and the visual styling of the rendered output.
public struct MarkdownConfiguration: Hashable, Sendable {
    // MARK: - Feature Flags

    // GitHub-specific extensions (mentions, issue/PR/repo references, commit
    // SHAs, emoji shortcodes, bare-URL autolinks) are OFF by default: plain
    // CommonMark-style rendering out of the box. Opt in per flag, or all at
    // once via `MarkdownConfiguration.github` /
    // `MarkdownConfigurationBuilder.enableGitHubFeatures()`.
    // (Tables, task lists, and strikethrough are always parsed.)

    /// Enables or disables the parsing of GitHub-style @mentions (e.g., `@username`).
    /// Default: `false`.
    public var enableMentions: Bool

    /// Enables or disables the parsing of GitHub-style issue references (e.g., `#123`).
    /// Default: `false`.
    public var enableIssueReferences: Bool

    /// Enables or disables the automatic conversion of bare URLs and email addresses into tappable links.
    /// Default: `false`.
    public var enableAutolinks: Bool

    /// Enables or disables the conversion of full-length commit SHAs into tappable links.
    /// Default: `false`.
    public var enableCommitSHAs: Bool

    /// Enables or disables the conversion of repository references (e.g., `owner/repo`) into tappable links.
    /// Default: `false`.
    public var enableRepositoryReferences: Bool

    /// Enables or disables the conversion of pull request references (e.g., `owner/repo#123`) into tappable links.
    /// Default: `false`.
    public var enablePullRequestReferences: Bool

    /// Enables or disables the conversion of emoji shortcodes (e.g., `:rocket:`) into Unicode characters or images.
    /// Default: `false`.
    public var enableEmojiShortcodes: Bool

    /// Enables or disables the parsing of footnotes (e.g., `[^1]`).
    /// Default: `true`.
    public var enableFootnotes: Bool

    /// Enables or disables the internal caching mechanism for parsed markdown.
    /// Disabling this can be useful for debugging but may impact performance for frequently rendered content.
    /// Default: `true`.
    public var enableCaching: Bool
    /// Enables caching of rendered blocks to reduce repeated work across renders.
    /// Default: `true`.
    public var enableRenderCaching: Bool

    // MARK: - Styling Properties

    /// The base font used for all text that doesn't have a more specific style.
    /// Default: `.body`.
    public var baseFont: Font

    /// The font used for inline code (`code`) and fenced code blocks (```code```).
    /// Default: `.system(.callout, design: .monospaced)`.
    public var codeFont: Font

    /// An array of fonts for heading levels 1 through 6.
    public var headingFonts: [Font]

    /// The base foreground color for body text (paragraphs, headings, list text).
    /// Inline elements with their own color (links, mentions, code) are unaffected.
    /// Default: `.primary`.
    public var textColor: Color

    /// The color for tappable links.
    /// Default: `.blue`.
    public var linkColor: Color

    /// The color for tappable @mentions.
    /// Default: `.mint`.
    public var mentionColor: Color

    /// The color for tappable #issue references.
    /// Default: `.blue`.
    public var issueColor: Color

    /// The background color for inline code and fenced code blocks.
    /// Default: `Color.secondary.opacity(0.1)`.
    public var codeBackgroundColor: Color

    /// The color of the vertical bar for blockquotes.
    /// Default: `.secondary`.
    public var blockquoteColor: Color

    /// The content mode for images, determining how they are resized.
    /// Default: `.fit`.
    public var imageContentMode: ContentMode
    
    /// Maximum width for images (nil means no limit)
    /// Default: `nil`.
    public var imageMaxWidth: CGFloat?
    
    /// Maximum height for images (nil means no limit)
    /// Default: `nil`.
    public var imageMaxHeight: CGFloat?

    /// The theme for syntax highlighting in code blocks.
    /// Default: `.light`.
    public var codeBlockTheme: CodeHighlightingTheme
    
    // MARK: - Performance Limits
    
    /// Maximum number of block parsing iterations to prevent infinite loops
    /// Default: `10000`.
    public var maxBlockIterations: Int
    
    /// Maximum number of inline parsing iterations to prevent infinite loops
    /// Default: `50000`.
    public var maxInlineIterations: Int
    
    /// Maximum cache size in megabytes for parsed content
    /// Default: `50`.
    public var maxCacheSizeMB: Int
    
    /// Time-to-live for cache entries in seconds
    /// Default: `300` (5 minutes).
    public var cacheTimeToLiveSeconds: TimeInterval
    /// Maximum number of cached rendered blocks retained in-memory (LRU).
    /// Must comfortably exceed the block count of the largest documents you
    /// re-render, or sequential renders thrash the LRU and hit 0%.
    /// Default: `4096`.
    public var maxRenderCacheEntries: Int
    
    // MARK: - Interaction Handlers
    
    /// Handler called when an inline image is tapped
    /// Default: `nil`.
    public var onImageTap: (@Sendable (URL, String) -> Void)?

    /// Host-provided syntax/rendering extensions.
    /// Default: `[]`.
    public var markdownExtensions: [MarkdownExtension]
    
    // MARK: - Validation Options
    
    /// Enable strict markdown validation mode
    /// Default: `false`.
    public var enableStrictMode: Bool
    
    /// Enable performance tracking and metrics
    /// Default: `false`.
    public var enablePerformanceTracking: Bool

    /// Public initializer to allow for custom configurations.
    public init(
        enableMentions: Bool = false,
        enableIssueReferences: Bool = false,
        enableAutolinks: Bool = false,
        enableCommitSHAs: Bool = false,
        enableRepositoryReferences: Bool = false,
        enablePullRequestReferences: Bool = false,
        enableEmojiShortcodes: Bool = false,
        enableFootnotes: Bool = true,
        enableCaching: Bool = true,
        enableRenderCaching: Bool = true,
        baseFont: Font = .body,
        codeFont: Font = .system(.callout, design: .monospaced),
        headingFonts: [Font] = [
            .largeTitle.bold(), .title.bold(), .title2.bold(),
            .title3.bold(), .headline, .subheadline.bold()
        ],
        textColor: Color = .primary,
        linkColor: Color = .blue,
        mentionColor: Color = .mint,
        issueColor: Color = .blue,
        codeBackgroundColor: Color = Color.secondary.opacity(0.1),
        blockquoteColor: Color = .secondary,
        imageContentMode: ContentMode = .fit,
        imageMaxWidth: CGFloat? = nil,
        imageMaxHeight: CGFloat? = nil,
        codeBlockTheme: CodeHighlightingTheme = .light,
        maxBlockIterations: Int = 10000,
        maxInlineIterations: Int = 50000,
        maxCacheSizeMB: Int = 50,
        cacheTimeToLiveSeconds: TimeInterval = 300,
        maxRenderCacheEntries: Int = 4096,
        onImageTap: (@Sendable (URL, String) -> Void)? = nil,
        markdownExtensions: [MarkdownExtension] = [],
        enableStrictMode: Bool = false,
        enablePerformanceTracking: Bool = false
    ) {
        self.enableMentions = enableMentions
        self.enableIssueReferences = enableIssueReferences
        self.enableAutolinks = enableAutolinks
        self.enableCommitSHAs = enableCommitSHAs
        self.enableRepositoryReferences = enableRepositoryReferences
        self.enablePullRequestReferences = enablePullRequestReferences
        self.enableEmojiShortcodes = enableEmojiShortcodes
        self.enableFootnotes = enableFootnotes
        self.enableCaching = enableCaching
        self.enableRenderCaching = enableRenderCaching
        self.baseFont = baseFont
        self.codeFont = codeFont
        self.headingFonts = headingFonts
        self.textColor = textColor
        self.linkColor = linkColor
        self.mentionColor = mentionColor
        self.issueColor = issueColor
        self.codeBackgroundColor = codeBackgroundColor
        self.blockquoteColor = blockquoteColor
        self.imageContentMode = imageContentMode
        self.imageMaxWidth = imageMaxWidth
        self.imageMaxHeight = imageMaxHeight
        self.codeBlockTheme = codeBlockTheme
        self.maxBlockIterations = maxBlockIterations
        self.maxInlineIterations = maxInlineIterations
        self.maxCacheSizeMB = maxCacheSizeMB
        self.cacheTimeToLiveSeconds = cacheTimeToLiveSeconds
        self.maxRenderCacheEntries = maxRenderCacheEntries
        self.onImageTap = onImageTap
        self.markdownExtensions = markdownExtensions
        self.enableStrictMode = enableStrictMode
        self.enablePerformanceTracking = enablePerformanceTracking
    }

    /// The default configuration for Glimmer.
    public static let `default` = MarkdownConfiguration()
    
    // MARK: - Hashable Implementation
    
    public func hash(into hasher: inout Hasher) {
        // Hash all properties except the closure
        hasher.combine(enableMentions)
        hasher.combine(enableIssueReferences)
        hasher.combine(enableAutolinks)
        hasher.combine(enableCommitSHAs)
        hasher.combine(enableRepositoryReferences)
        hasher.combine(enablePullRequestReferences)
        hasher.combine(enableEmojiShortcodes)
        hasher.combine(enableFootnotes)
        hasher.combine(enableCaching)
        hasher.combine(enableRenderCaching)
        hasher.combine(baseFont)
        hasher.combine(codeFont)
        hasher.combine(headingFonts)
        hasher.combine(textColor)
        hasher.combine(linkColor)
        hasher.combine(mentionColor)
        hasher.combine(issueColor)
        hasher.combine(codeBackgroundColor)
        hasher.combine(blockquoteColor)
        hasher.combine(imageContentMode)
        hasher.combine(imageMaxWidth)
        hasher.combine(imageMaxHeight)
        hasher.combine(codeBlockTheme)
        hasher.combine(maxBlockIterations)
        hasher.combine(maxInlineIterations)
        hasher.combine(maxCacheSizeMB)
        hasher.combine(cacheTimeToLiveSeconds)
        hasher.combine(maxRenderCacheEntries)
        hasher.combine(markdownExtensions)
        hasher.combine(enableStrictMode)
        hasher.combine(enablePerformanceTracking)
        // Note: closures are intentionally excluded from hash. Extensions must
        // bump version when parsing or rendering behavior changes.
    }
    
    public static func == (lhs: MarkdownConfiguration, rhs: MarkdownConfiguration) -> Bool {
        // Compare all properties except the closure
        return lhs.enableMentions == rhs.enableMentions &&
               lhs.enableIssueReferences == rhs.enableIssueReferences &&
               lhs.enableAutolinks == rhs.enableAutolinks &&
               lhs.enableCommitSHAs == rhs.enableCommitSHAs &&
               lhs.enableRepositoryReferences == rhs.enableRepositoryReferences &&
               lhs.enablePullRequestReferences == rhs.enablePullRequestReferences &&
               lhs.enableEmojiShortcodes == rhs.enableEmojiShortcodes &&
               lhs.enableFootnotes == rhs.enableFootnotes &&
               lhs.enableCaching == rhs.enableCaching &&
               lhs.enableRenderCaching == rhs.enableRenderCaching &&
               lhs.baseFont == rhs.baseFont &&
               lhs.codeFont == rhs.codeFont &&
               lhs.headingFonts == rhs.headingFonts &&
               lhs.textColor == rhs.textColor &&
               lhs.linkColor == rhs.linkColor &&
               lhs.mentionColor == rhs.mentionColor &&
               lhs.issueColor == rhs.issueColor &&
               lhs.codeBackgroundColor == rhs.codeBackgroundColor &&
               lhs.blockquoteColor == rhs.blockquoteColor &&
               lhs.imageContentMode == rhs.imageContentMode &&
               lhs.imageMaxWidth == rhs.imageMaxWidth &&
               lhs.imageMaxHeight == rhs.imageMaxHeight &&
               lhs.codeBlockTheme == rhs.codeBlockTheme &&
               lhs.maxBlockIterations == rhs.maxBlockIterations &&
               lhs.maxInlineIterations == rhs.maxInlineIterations &&
               lhs.maxCacheSizeMB == rhs.maxCacheSizeMB &&
               lhs.cacheTimeToLiveSeconds == rhs.cacheTimeToLiveSeconds &&
               lhs.maxRenderCacheEntries == rhs.maxRenderCacheEntries &&
               lhs.markdownExtensions == rhs.markdownExtensions &&
               lhs.enableStrictMode == rhs.enableStrictMode &&
               lhs.enablePerformanceTracking == rhs.enablePerformanceTracking
        // Note: closures are intentionally excluded from equality. Extensions
        // must bump version when parsing or rendering behavior changes.
    }
}

public extension MarkdownConfiguration {
    func addingExtension(_ markdownExtension: MarkdownExtension) -> MarkdownConfiguration {
        var copy = self
        copy.markdownExtensions.append(markdownExtension)
        return copy
    }

    func addingExtensions(_ markdownExtensions: [MarkdownExtension]) -> MarkdownConfiguration {
        var copy = self
        copy.markdownExtensions.append(contentsOf: markdownExtensions)
        return copy
    }
}
