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
}
