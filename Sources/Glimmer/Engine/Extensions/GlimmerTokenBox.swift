import Foundation

/// An extension token carried in an attributed string (`.glimmerToken`), so a tap can report it.
final class GlimmerTokenBox: NSObject, @unchecked Sendable {
    let token: GlimmerInlineToken

    init(_ token: GlimmerInlineToken) {
        self.token = token
    }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? GlimmerTokenBox)?.token == token
    }

    override var hash: Int { token.source.hashValue }

    /// The link a tappable token's text carries, so UIKit treats it as a link: VoiceOver and the links rotor reach it,
    /// and `GlimmerView` turns its tap into `onTokenTap`. Only the scheme matters; the token is read from the text.
    /// `position` (where the token starts in the composed text) keeps tokens side by side from reading as one link.
    static func link(kind: String, at position: Int = 0) -> URL {
        // Percent-encoded down to letters and digits, the kind always makes a valid URL.
        let path = (kind.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") + "-\(position)"
        guard let url = URL(string: "glimmer-token:" + path) else { preconditionFailure("an invalid token link: \(path)") }
        return url
    }

    static func isTokenLink(_ url: URL) -> Bool { url.scheme == "glimmer-token" }

    /// The link an inline image's spoken alt text carries while the host takes image taps, so VoiceOver reaches the
    /// image once, in reading order, and activating it taps the image. `position` keeps images side by side apart.
    static func imageLink(at position: Int) -> URL {
        guard let url = URL(string: "glimmer-image:\(position)") else { preconditionFailure("an invalid image link") }
        return url
    }

    static func isImageLink(_ url: URL) -> Bool { url.scheme == "glimmer-image" }

    /// A link Glimmer adds for UIKit's sake, not one the markdown has: never copied, never given a link menu.
    static func isInternalLink(_ url: URL) -> Bool { isTokenLink(url) || isImageLink(url) }
}
