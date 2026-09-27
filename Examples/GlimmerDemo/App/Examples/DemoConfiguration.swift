import Glimmer

extension GlimmerConfiguration {
    /// What 1.x called `.github`: emoji shortcodes, `@mentions` and `#123` references, with images loaded by
    /// `DemoImageLoader`.
    static var demoGitHub: GlimmerConfiguration {
        GlimmerConfiguration(
            extensions: [GlimmerEmojiShortcodes(), GlimmerMentions(), GitHubIssueReferences()],
            imageLoader: DemoImageLoader()
        )
    }
}
