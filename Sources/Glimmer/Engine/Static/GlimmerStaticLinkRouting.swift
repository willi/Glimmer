import SwiftUI

/// Sends link taps to `onLinkTap` when there is one. Without one it leaves the environment's `openURL` alone, so a
/// handler the host installed higher up still receives the taps.
struct GlimmerStaticLinkRouting: ViewModifier {
    let onLinkTap: ((URL) -> Void)?

    func body(content: Content) -> some View {
        if let onLinkTap {
            content.environment(\.openURL, OpenURLAction { url in
                onLinkTap(url)
                return .handled
            })
        } else {
            content
        }
    }
}
