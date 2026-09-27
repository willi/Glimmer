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
    static func link(kind: String) -> URL {
        var components = URLComponents()
        components.scheme = "glimmer-token"
        components.path = kind
        return components.url ?? URL(fileURLWithPath: kind)
    }

    static func isTokenLink(_ url: URL) -> Bool { url.scheme == "glimmer-token" }
}
