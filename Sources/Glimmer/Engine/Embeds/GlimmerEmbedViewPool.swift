import UIKit

/// Code block views built and laid out once while idle. A fresh code block view's first frame costs about three times
/// a warmed one's (its first layout sets up its text view), and a streamed fence lands in a frame that also applies
/// the edit, so while an answer streams one view per theme waits here for the next fence.
@MainActor
final class GlimmerEmbedViewPool {
    static let shared = GlimmerEmbedViewPool()

    private var codeBlocks: [GlimmerTheme: GlimmerCodeBlockView] = [:]
    private var preparing: Set<GlimmerTheme> = []
    /// The view that last asked for a prepared view: the window a replacement is laid out in.
    private weak var host: UIView?

    init() {
        // Under memory pressure the prepared views go; the next stream prepares again.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }
    }

    func hasCodeBlockView(for theme: GlimmerTheme) -> Bool { codeBlocks[theme] != nil }

    func peekCodeBlockView(for theme: GlimmerTheme) -> GlimmerCodeBlockView? { codeBlocks[theme] }

    func removeAll() {
        codeBlocks.removeAll()
        preparing.removeAll()
    }

    /// The prepared code block view for `theme`, showing `embed`, or nil; a replacement is prepared on the next turn.
    func takeCodeBlockView(for embed: GlimmerEmbed, theme: GlimmerTheme, highlighter: any GlimmerHighlighter) -> GlimmerCodeBlockView? {
        guard let view = codeBlocks.removeValue(forKey: theme) else { return nil }
        view.highlighter = highlighter
        view.update(to: embed)
        // Only a stream waits for its next fence; a settled answer that took the view needs no replacement.
        if let host = host as? GlimmerView, host.isStreaming {
            prepareCodeBlockView(theme: theme, highlighter: highlighter, in: host)
        }
        return view
    }

    /// Builds a code block view for `theme` on the next run-loop turn and lays it out once, hidden, inside `host`.
    func prepareCodeBlockView(theme: GlimmerTheme, highlighter: any GlimmerHighlighter, in host: UIView) {
        self.host = host
        guard codeBlocks[theme] == nil, !preparing.contains(theme) else { return }
        preparing.insert(theme)
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated { [weak self, weak host] in
                guard let self, self.preparing.remove(theme) != nil, self.codeBlocks[theme] == nil else { return }
                // Empty text needs no highlighting; a host's highlighter must never run on main.
                let view = GlimmerCodeBlockView(code: "", language: nil, theme: theme, highlighter: highlighter,
                                                highlighted: NSAttributedString())
                if let host, host.window != nil {
                    view.isHidden = true
                    view.frame = CGRect(x: 0, y: 0, width: max(host.bounds.width, 1), height: view.embedHeight(forWidth: host.bounds.width))
                    host.addSubview(view)
                    view.layoutIfNeeded()
                    view.removeFromSuperview()
                    view.isHidden = false
                }
                self.codeBlocks[theme] = view
            }
        }
    }
}
