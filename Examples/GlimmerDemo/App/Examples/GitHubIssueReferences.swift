import Foundation
import Glimmer

/// `#123` issue and pull request references as tappable text: an extension a host writes for itself. A tap reports
/// kind "issue" with payload "number" through `onTokenTap`. Not inside links, code, or after a word or a slash
/// (`a#1`, `/path#1`).
struct GitHubIssueReferences: GlimmerExtension {
    nonisolated(unsafe) private static let reference = try? NSRegularExpression(pattern: #"(?<![\w/#])#(\d+)\b"#)
    nonisolated(unsafe) private static let partial = try? NSRegularExpression(pattern: #"(?<![\w/#])#\d*$"#)

    var appliesInsideLinks: Bool { false }

    func scan(_ text: String) -> [GlimmerInlineToken] {
        guard text.contains("#"), let expression = Self.reference else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text), let digits = Range(match.range(at: 1), in: text) else {
                return nil
            }
            let number = String(text[digits])
            return GlimmerInlineToken(
                range: range, kind: "issue", payload: ["number": number], displayText: "#" + number,
                source: "#" + number, accessibilityLabel: "Issue \(number)", presentation: .text(tappable: true)
            )
        }
    }

    /// A number still arriving at the end of a stream: holding it back keeps `#1` from turning blue a digit at a time.
    func streamingHoldBack(in markdown: String) -> Int {
        guard markdown.last?.isNumber == true || markdown.last == "#", let expression = Self.partial else { return 0 }
        let tail = String(markdown.suffix(12))
        guard let match = expression.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
              let range = Range(match.range, in: tail) else { return 0 }
        return tail[range].count
    }
}
