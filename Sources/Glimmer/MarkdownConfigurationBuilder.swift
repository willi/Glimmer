import Foundation
import SwiftUI

/// Builder pattern for creating MarkdownConfiguration instances
public class MarkdownConfigurationBuilder {
    // MARK: - Feature Flags
    // GitHub-specific extensions are off by default (see MarkdownConfiguration).
    private var enableMentions = false
    private var enableIssueReferences = false
    private var enableAutolinks = false
    private var enableCommitSHAs = false
    private var enableRepositoryReferences = false
    private var enablePullRequestReferences = false
    private var enableEmojiShortcodes = false
    private var enableFootnotes = true
    private var enableCaching = true
    private var enableRenderCaching = true
    
    // MARK: - Styling Properties
    private var baseFont: Font = .body
    private var codeFont: Font = .system(.callout, design: .monospaced)
    private var headingFonts: [Font] = [
        .largeTitle.bold(), .title.bold(), .title2.bold(),
        .title3.bold(), .headline, .subheadline.bold()
    ]
    private var linkColor: Color = .blue
    private var mentionColor: Color = .mint
    private var issueColor: Color = .blue
    private var codeBackgroundColor: Color = Color.secondary.opacity(0.1)
    private var blockquoteColor: Color = .secondary
    private var imageContentMode: ContentMode = .fit
    private var imageMaxWidth: CGFloat?
    private var imageMaxHeight: CGFloat?
    private var codeBlockTheme: CodeHighlightingTheme = .light
    
    // MARK: - Performance Limits
    private var maxBlockIterations = 10000
    private var maxInlineIterations = 50000
    private var maxCacheSizeMB = 50
    private var cacheTimeToLiveSeconds: TimeInterval = 300
    private var maxRenderCacheEntries = 4096
    
    // MARK: - Interaction Handlers
    private var onImageTap: (@Sendable (URL, String) -> Void)?
    private var markdownExtensions: [MarkdownExtension] = []
    
    // MARK: - Validation Options
    private var enableStrictMode = false
    private var enablePerformanceTracking = false
    
    public init() {}
    
    // MARK: - Feature Configuration
    
    /// Enables every GitHub-specific extension: @mentions, issue/PR/repo
    /// references, commit SHAs, emoji shortcodes, and bare-URL autolinks.
    @discardableResult
    public func enableGitHubFeatures() -> Self {
        enableMentions = true
        enableIssueReferences = true
        enableCommitSHAs = true
        enableRepositoryReferences = true
        enablePullRequestReferences = true
        enableEmojiShortcodes = true
        enableAutolinks = true
        return self
    }

    /// Disables every GitHub-specific extension (the default state).
    @discardableResult
    public func disableGitHubFeatures() -> Self {
        enableMentions = false
        enableIssueReferences = false
        enableCommitSHAs = false
        enableRepositoryReferences = false
        enablePullRequestReferences = false
        enableEmojiShortcodes = false
        enableAutolinks = false
        return self
    }
    
    @discardableResult
    public func setMentions(_ enabled: Bool) -> Self {
        enableMentions = enabled
        return self
    }
    
    @discardableResult
    public func setIssueReferences(_ enabled: Bool) -> Self {
        enableIssueReferences = enabled
        return self
    }
    
    @discardableResult
    public func setAutolinks(_ enabled: Bool) -> Self {
        enableAutolinks = enabled
        return self
    }
    
    @discardableResult
    public func setCommitSHAs(_ enabled: Bool) -> Self {
        enableCommitSHAs = enabled
        return self
    }
    
    @discardableResult
    public func setRepositoryReferences(_ enabled: Bool) -> Self {
        enableRepositoryReferences = enabled
        return self
    }
    
    @discardableResult
    public func setPullRequestReferences(_ enabled: Bool) -> Self {
        enablePullRequestReferences = enabled
        return self
    }
    
    @discardableResult
    public func setEmojiShortcodes(_ enabled: Bool) -> Self {
        enableEmojiShortcodes = enabled
        return self
    }
    
    @discardableResult
    public func setFootnotes(_ enabled: Bool) -> Self {
        enableFootnotes = enabled
        return self
    }
    
    @discardableResult
    public func setCaching(_ enabled: Bool) -> Self {
        enableCaching = enabled
        return self
    }
    
    @discardableResult
    public func setRenderCaching(_ enabled: Bool) -> Self {
        enableRenderCaching = enabled
        return self
    }
    
    // MARK: - Styling Configuration
    
    @discardableResult
    public func setTheme(_ theme: CodeHighlightingTheme) -> Self {
        codeBlockTheme = theme
        
        // Adjust colors based on theme
        switch theme {
        case .dark:
            codeBackgroundColor = Color.black.opacity(0.3)
            linkColor = .cyan
        case .light:
            codeBackgroundColor = Color.secondary.opacity(0.1)
            linkColor = .blue
        default:
            // Fallback for any future themes
            codeBackgroundColor = Color.secondary.opacity(0.1)
            linkColor = .blue
        }
        
        return self
    }
    
    @discardableResult
    public func setBaseFont(_ font: Font) -> Self {
        baseFont = font
        return self
    }
    
    @discardableResult
    public func setCodeFont(_ font: Font) -> Self {
        codeFont = font
        return self
    }
    
    @discardableResult
    public func setHeadingFonts(_ fonts: [Font]) -> Self {
        headingFonts = fonts
        return self
    }
    
    @discardableResult
    public func setLinkColor(_ color: Color) -> Self {
        linkColor = color
        return self
    }
    
    @discardableResult
    public func setMentionColor(_ color: Color) -> Self {
        mentionColor = color
        return self
    }
    
    @discardableResult
    public func setIssueColor(_ color: Color) -> Self {
        issueColor = color
        return self
    }
    
    @discardableResult
    public func setCodeBackgroundColor(_ color: Color) -> Self {
        codeBackgroundColor = color
        return self
    }
    
    @discardableResult
    public func setBlockquoteColor(_ color: Color) -> Self {
        blockquoteColor = color
        return self
    }
    
    @discardableResult
    public func setImageContentMode(_ mode: ContentMode) -> Self {
        imageContentMode = mode
        return self
    }
    
    @discardableResult
    public func setImageSize(maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil) -> Self {
        imageMaxWidth = maxWidth
        imageMaxHeight = maxHeight
        return self
    }
    
    // MARK: - Performance Configuration
    
    @discardableResult
    public func setMaxIterations(blocks: Int? = nil, inline: Int? = nil) -> Self {
        if let blocks = blocks {
            maxBlockIterations = blocks
        }
        if let inline = inline {
            maxInlineIterations = inline
        }
        return self
    }
    
    @discardableResult
    public func setCacheSettings(maxSizeMB: Int? = nil, timeToLiveSeconds: TimeInterval? = nil) -> Self {
        if let maxSizeMB = maxSizeMB {
            self.maxCacheSizeMB = maxSizeMB
        }
        if let timeToLiveSeconds = timeToLiveSeconds {
            self.cacheTimeToLiveSeconds = timeToLiveSeconds
        }
        return self
    }
    
    @discardableResult
    public func setMaxRenderCacheEntries(_ entries: Int) -> Self {
        maxRenderCacheEntries = max(1, entries)
        return self
    }
    
    @discardableResult
    public func setStrictMode(_ enabled: Bool) -> Self {
        enableStrictMode = enabled
        return self
    }
    
    @discardableResult
    public func setPerformanceTracking(_ enabled: Bool) -> Self {
        enablePerformanceTracking = enabled
        return self
    }
    
    @discardableResult
    public func setOnImageTap(_ handler: (@Sendable (URL, String) -> Void)?) -> Self {
        onImageTap = handler
        return self
    }

    @discardableResult
    public func addExtension(_ markdownExtension: MarkdownExtension) -> Self {
        markdownExtensions.append(markdownExtension)
        return self
    }

    @discardableResult
    public func addExtensions(_ markdownExtensions: [MarkdownExtension]) -> Self {
        self.markdownExtensions.append(contentsOf: markdownExtensions)
        return self
    }
    
    // MARK: - Preset Configurations
    
    @discardableResult
    public func useMinimalConfiguration() -> Self {
        enableMentions = false
        enableIssueReferences = false
        enableAutolinks = false
        enableCommitSHAs = false
        enableRepositoryReferences = false
        enablePullRequestReferences = false
        enableEmojiShortcodes = false
        enableFootnotes = false
        enableCaching = false
        enableRenderCaching = false
        return self
    }
    
    @discardableResult
    public func useFullConfiguration() -> Self {
        enableMentions = true
        enableIssueReferences = true
        enableAutolinks = true
        enableCommitSHAs = true
        enableRepositoryReferences = true
        enablePullRequestReferences = true
        enableEmojiShortcodes = true
        enableFootnotes = true
        enableCaching = true
        enableRenderCaching = true
        return self
    }
    
    @discardableResult
    public func usePerformanceConfiguration() -> Self {
        enableCaching = true
        maxBlockIterations = 5000
        maxInlineIterations = 25000
        maxCacheSizeMB = 100
        cacheTimeToLiveSeconds = 600
        maxRenderCacheEntries = 8192
        enableRenderCaching = true
        enablePerformanceTracking = true
        return self
    }
    
    // MARK: - Build
    
    public func build() -> MarkdownConfiguration {
        return MarkdownConfiguration(
            enableMentions: enableMentions,
            enableIssueReferences: enableIssueReferences,
            enableAutolinks: enableAutolinks,
            enableCommitSHAs: enableCommitSHAs,
            enableRepositoryReferences: enableRepositoryReferences,
            enablePullRequestReferences: enablePullRequestReferences,
            enableEmojiShortcodes: enableEmojiShortcodes,
            enableFootnotes: enableFootnotes,
            enableCaching: enableCaching,
            enableRenderCaching: enableRenderCaching,
            baseFont: baseFont,
            codeFont: codeFont,
            headingFonts: headingFonts,
            linkColor: linkColor,
            mentionColor: mentionColor,
            issueColor: issueColor,
            codeBackgroundColor: codeBackgroundColor,
            blockquoteColor: blockquoteColor,
            imageContentMode: imageContentMode,
            imageMaxWidth: imageMaxWidth,
            imageMaxHeight: imageMaxHeight,
            codeBlockTheme: codeBlockTheme,
            maxBlockIterations: maxBlockIterations,
            maxInlineIterations: maxInlineIterations,
            maxCacheSizeMB: maxCacheSizeMB,
            cacheTimeToLiveSeconds: cacheTimeToLiveSeconds,
            maxRenderCacheEntries: maxRenderCacheEntries,
            onImageTap: onImageTap,
            markdownExtensions: markdownExtensions,
            enableStrictMode: enableStrictMode,
            enablePerformanceTracking: enablePerformanceTracking
        )
    }
}

// MARK: - Extension for Convenience

public extension MarkdownConfiguration {
    /// Create a configuration using the builder pattern
    static func builder() -> MarkdownConfigurationBuilder {
        return MarkdownConfigurationBuilder()
    }
    
    /// Preset configuration for GitHub README files
    static var github: MarkdownConfiguration {
        return MarkdownConfigurationBuilder()
            .enableGitHubFeatures()
            .setTheme(.light)
            .build()
    }
    
    /// Preset configuration for minimal markdown
    static var minimal: MarkdownConfiguration {
        return MarkdownConfigurationBuilder()
            .useMinimalConfiguration()
            .build()
    }
    
    /// Preset configuration optimized for performance
    static var performance: MarkdownConfiguration {
        return MarkdownConfigurationBuilder()
            .usePerformanceConfiguration()
            .build()
    }
}
