import Foundation

/// `:emoji:` shortcodes, GitHub's set (about 1,900, restored from Glimmer 1.x). A standard shortcode becomes its emoji
/// as text; GitHub's custom ones (`:octocat:`, `:shipit:`, …) become inline images from github.com. Never in code or
/// link destinations. Copy writes the shortcode in markdown and the emoji in plain text. Opt-in: add it to
/// `GlimmerConfiguration.extensions`.
public struct GlimmerEmojiShortcodes: GlimmerExtension {
    public init() {}

    enum Entry: Equatable, Sendable {
        case unicode(String)
        case image(URL)
    }

    /// Shortcode name → emoji, loaded once from the package's `github-emoji.json`.
    static let table: [String: Entry] = {
        do {
            return try loadTable(from: Bundle.module.url(forResource: "github-emoji", withExtension: "json"))
        } catch {
            // Every shortcode would stay text without a word: say why in debug builds.
            assertionFailure("GlimmerEmojiShortcodes can't load github-emoji.json: \(error)")
            return [:]
        }
    }()

    enum TableError: Error, Equatable {
        case missingResource
        case unreadable
        case notAnObject
    }

    static func loadTable(from url: URL?) throws -> [String: Entry] {
        guard let url else { throw TableError.missingResource }
        guard let data = try? Data(contentsOf: url) else { throw TableError.unreadable }
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw TableError.notAnObject }
        var table: [String: Entry] = [:]
        table.reserveCapacity(raw.count)
        for (name, value) in raw {
            if let emoji = value as? String {
                table[name] = .unicode(emoji)
            } else if let image = (value as? [String: String])?["image"], let url = URL(string: image) {
                table[name] = .image(url)
            }
        }
        return table
    }

    public func scan(_ text: String) -> [GlimmerInlineToken] {
        guard text.contains(":") else { return [] }
        var tokens: [GlimmerInlineToken] = []
        var searchFrom = text.startIndex
        while let match = text[searchFrom...].firstMatch(of: #/:([A-Za-z0-9_+\-]{1,40}):/#) {
            let name = String(match.output.1)
            // Not glued to a word on the left: `a:b:c` and `3:1:2` are ratios, not 🅱.
            let before = match.range.lowerBound > text.startIndex ? text[text.index(before: match.range.lowerBound)] : nil
            let gluedToWord = before.map { $0.isLetter || $0.isNumber } ?? false
            guard !gluedToWord, let entry = Self.table[name] else {
                // The closing colon may open the next shortcode (`a :b:rocket:`): continue from it.
                searchFrom = text.index(before: match.range.upperBound)
                continue
            }
            let source = ":\(name):"
            switch entry {
            case .unicode(let emoji):
                tokens.append(GlimmerInlineToken(range: match.range, kind: "emoji", payload: ["name": name], displayText: emoji,
                                                 source: source, presentation: .text(tappable: false)))
            case .image(let url):
                tokens.append(GlimmerInlineToken(range: match.range, kind: "emoji", payload: ["name": name], displayText: source,
                                                 source: source, accessibilityLabel: name, presentation: .image(url)))
            }
            searchFrom = match.range.upperBound
        }
        return tokens
    }

    /// An unclosed shortcode at the very end (`:rock`) waits, so a shown `:rock` never turns into 🚀. Not after a letter
    /// or digit (`10:3` is a time), where no shortcode can start.
    public func streamingHoldBack(in markdown: String) -> Int {
        guard let match = markdown.suffix(41).firstMatch(of: #/(^|[^\p{L}\p{N}:]):[A-Za-z0-9_+\-]{1,39}$/#) else { return 0 }
        return markdown.suffix(41)[match.range].drop { $0 != ":" }.count
    }
}
