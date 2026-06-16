import SwiftUI

/// Glimmer - A complete GitHub Flavored Markdown implementation for SwiftUI
///
/// This standalone component provides:
/// - Full GFM parsing and rendering
/// - Interactive elements (tappable links, mentions, issues)
/// - Syntax highlighting for code blocks
/// - Customizable styling
/// - iOS 18+ optimized with Swift 6
///
/// Basic Usage:
/// ```swift
/// MarkdownView(markdown: "# Hello\nThis is **markdown**")
/// ```
///
/// Interactive Usage:
/// ```swift
/// MarkdownView(
///     markdown: content,
///     onLinkTap: { url in openURL(url) },
///     onMentionTap: { username in /* handle mention */ },
///     onIssueTap: { issueNumber in /* handle issue */ }
/// )
/// ```
public struct Glimmer {
    
    // MARK: - Configuration
    
    /// Default configuration for markdown parsing. Immutable to ensure thread safety.
    public static let defaultConfiguration = MarkdownConfiguration.default
    
    // MARK: - Caching
    
    /// Shared cache for parsed markdown
    private static let sharedCache = CachedMarkdownParser()
    
    // MARK: - Utilities
    
    /// Parse markdown to an Abstract Syntax Tree (AST).
    public static func parse(_ markdown: String, configuration: MarkdownConfiguration = .default) -> [MarkdownParser.BlockNode] {
        if configuration.enableCaching {
            return sharedCache.parse(markdown, configuration: configuration)
        }
        return MarkdownParser.parse(markdown, configuration: configuration)
    }
    
    /// Parse markdown directly to a SwiftUI `AttributedString`.
    public static func parseToAttributedString(_ markdown: String, configuration: MarkdownConfiguration = .default) -> AttributedString {
        let blocks = parse(markdown, configuration: configuration)
        // In the future, this will call the renderer. For now, it uses the parser's rendering.
        return MarkdownParser.renderBlocks(blocks, configuration: configuration)
    }
    
    
    /// Clear the parsing cache.
    public static func clearCache() {
        sharedCache.clearCache()
    }

    /// Clear the render cache (AttributedString cache for rendered blocks) and reset stats.
    public static func clearRenderCache() {
        MarkdownRenderer.clearRenderCache()
    }

    /// Get current render cache statistics (hits, misses).
    public static func getRenderCacheStatistics() -> (hits: Int, misses: Int) {
        MarkdownRenderer.getRenderCacheStats()
    }
    
}

// MARK: - Convenience Views

/// A namespace for convenient markdown views
@MainActor
public enum Markdown {
    
    /// Display a code block with optional language and configuration.
    public static func codeBlock(_ code: String, language: String? = nil, configuration: MarkdownConfiguration = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language = language {
                Text(language)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(configuration.codeFont)
                    .padding()
                    .background(configuration.codeBackgroundColor)
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }
        }
    }
    
    /// Display inline markdown content.
    public static func inline(_ markdown: String, configuration: MarkdownConfiguration = .default) -> some View {
        Text(Glimmer.parseToAttributedString(markdown, configuration: configuration))
            .textSelection(.enabled)
    }
    
    /// Create a basic, non-interactive markdown view.
    public static func text(_ markdown: String, configuration: MarkdownConfiguration = .default) -> some View {
        MarkdownView(markdown: markdown, configuration: configuration, interactive: false)
    }
    
    /// Create an interactive markdown view with tappable elements.
    public static func interactive(
        _ markdown: String,
        configuration: MarkdownConfiguration = .default,
        onLinkTap: ((URL) -> Void)? = nil,
        onMentionTap: ((String) -> Void)? = nil,
        onIssueTap: ((Int) -> Void)? = nil
    ) -> some View {
        MarkdownView(
            markdown: markdown,
            configuration: configuration,
            onLinkTap: onLinkTap,
            onMentionTap: onMentionTap,
            onIssueTap: onIssueTap
        )
    }
}

// MARK: - View Extensions

public extension View {
    
    /// Present markdown content in a sheet.
    func markdownSheet(
        isPresented: Binding<Bool>,
        title: String? = nil,
        markdown: String,
        configuration: MarkdownConfiguration = .default,
        onLinkTap: ((URL) -> Void)? = nil
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            NavigationStack {
                MarkdownView(
                    markdown: markdown,
                    configuration: configuration,
                    onLinkTap: onLinkTap
                )
                .navigationTitle(title ?? "")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Done") {
                            isPresented.wrappedValue = false
                        }
                    }
                }
            }
        }
    }
    
    /// Present release notes in a sheet
    func releaseNotesSheet(
        isPresented: Binding<Bool>,
        releaseNotes: String,
        version: String? = nil,
        configuration: MarkdownConfiguration = Glimmer.defaultConfiguration
    ) -> some View {
        self.markdownSheet(
            isPresented: isPresented,
            title: version.map { "Release Notes - \($0)" } ?? "Release Notes",
            markdown: releaseNotes,
            configuration: configuration
        )
    }
}

// MARK: - Default Handlers

public extension Glimmer {
    
    /// Create a default mention URL
    static func mentionURL(username: String) -> URL? {
        URL(string: "https://github.com/\(username)")
    }
    
    /// Create a default issue URL for a specific repository
    static func issueURL(owner: String, repo: String, issueNumber: Int) -> URL? {
        URL(string: "https://github.com/\(owner)/\(repo)/issues/\(issueNumber)")
    }
}
