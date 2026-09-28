import SwiftUI

/// 1.x's example screens, rebuilt on 2.0, in 1.x's sections. `--example=<id>` opens one directly.
enum DemoExample: String, CaseIterable, Identifiable {
    case basicFeatures = "basic-features"
    case advanced
    case gfm
    case edgeCases = "edge-cases"
    case inlineImages = "inline-images"
    case tappableImages = "tappable-images"
    case githubEmojis = "github-emojis"
    case livePreview = "live-preview"
    case streamingReveal = "streaming-reveal"
    case performance
    case readme
    case githubFeatures = "github-features"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basicFeatures: "Basic Features"
        case .advanced: "Advanced Features"
        case .gfm: "GitHub Flavored Markdown"
        case .edgeCases: "Edge Cases"
        case .inlineImages: "Inline Images"
        case .tappableImages: "Tappable Images"
        case .githubEmojis: "GitHub Emojis"
        case .livePreview: "Live Preview"
        case .streamingReveal: "Streaming Reveal"
        case .performance: "Performance"
        case .readme: "README Example"
        case .githubFeatures: "GitHub Features"
        }
    }

    enum Section: String, CaseIterable {
        case core = "Core"
        case advanced = "Advanced"
        case performance = "Performance"
        case quickExamples = "Quick Examples"
    }

    var section: Section {
        switch self {
        case .basicFeatures, .advanced: .core
        case .gfm, .edgeCases, .inlineImages, .tappableImages, .githubEmojis, .livePreview, .streamingReveal: .advanced
        case .performance: .performance
        case .readme, .githubFeatures: .quickExamples
        }
    }

    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .basicFeatures: BasicFeaturesDemo()
        case .advanced: AdvancedDemo()
        case .gfm: GFMDemo()
        case .edgeCases: EdgeCasesDemo()
        case .inlineImages: InlineImageDemo()
        case .tappableImages: TappableImageExample()
        case .githubEmojis: GitHubEmojiDemo()
        case .livePreview: LivePreviewDemoScreen()
        case .streamingReveal: StreamingRevealDemo()
        case .performance: PerformanceDemo()
        case .readme: QuickExampleView(title: "README", markdown: readmeExample)
        case .githubFeatures: QuickExampleView(title: "GitHub", markdown: githubExample)
        }
    }

    /// The tab or section `--section=<n>` asks a screen to open on.
    static var launchSection: Int? {
        ProcessInfo.processInfo.arguments.lazy
            .compactMap { $0.hasPrefix("--section=") ? Int($0.dropFirst(10)) : nil }
            .first
    }

    /// The screen `--example=<id>` asks for.
    static var launchExample: DemoExample? {
        ProcessInfo.processInfo.arguments.lazy
            .compactMap { $0.hasPrefix("--example=") ? DemoExample(rawValue: String($0.dropFirst(10))) : nil }
            .first
    }
}
