import SwiftUI

private struct RevealStartAttribute: TextAttribute {
    let time: Double
}

/// Opacity is applied at drawing time, preserving native shaping, colored
/// links, inline backgrounds and decorations without rebuilding attributes
/// or measuring individual words at display refresh frequency.
private struct SmoothTrailTextRenderer: TextRenderer {
    let time: Double

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                var drawing = context
                if let start = run[RevealStartAttribute.self] {
                    drawing.opacity *= RevealSmoothTrail.opacity(age: time - start.time)
                }
                drawing.draw(run)
            }
        }
    }
}

struct RevealSmoothTrailTextView: View {
    let block: RevealBlock
    let revealedCount: Int
    let trail: RevealSmoothTrailState
    let configuration: MarkdownConfiguration
    let onLinkTap: (URL) -> Void

    var body: some View {
        // Construct text once per input/cursor change, outside the frame clock.
        let words = block.words.filter { $0.atoms.contains { $0.revealIndex <= revealedCount } }
        let text = contiguousText(words)
        let hasAvatars = block.words.contains { word in
            word.atoms.contains { atom in
                if case .text(let string) = atom.kind { return string.avatarImageURL != nil }
                return false
            }
        }
        let active = words.contains { word in
            word.atoms.contains { trail.starts[$0.revealIndex] != nil }
        }
        TimelineView(.animation(paused: !active)) { _ in
            // A monotonic clock matches the driver and ignores wall-clock changes.
            let time = ProcessInfo.processInfo.systemUptime
            if hasAvatars {
                avatarContent(words, time: time)
            } else {
                text.textRenderer(SmoothTrailTextRenderer(time: time))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, OpenURLAction { url in
                        onLinkTap(url)
                        return .handled
                    })
            }
        }
        .transaction { $0.animation = nil }
    }

    private func contiguousText(_ words: [RevealWord]) -> Text {
        words.flatMap(\.atoms).reduce(Text("")) { result, atom in
            guard atom.revealIndex <= revealedCount else { return result }
            let unit: Text
            switch atom.kind {
            case .text(let string), .space(let string):
                guard string.avatarImageURL == nil else { return result }
                unit = Text(string)
            case .lineBreak:
                unit = Text("\n")
            case .block:
                return result
            }
            if let time = trail.starts[atom.revealIndex] {
                return result + unit.customAttribute(RevealStartAttribute(time: time))
            }
            return result + unit
        }
    }

    /// Inline avatars need a view. Keep Glimmer's established flow path for
    /// these blocks, using the same shared block clock and temporal envelope.
    private func avatarContent(_ words: [RevealWord], time: Double) -> some View {
        RevealFlowLayout(lineSpacing: 2) {
            ForEach(mergedRevealWords(words), id: \.word.id) { item in
                if item.word.isLineBreak {
                    Color.clear.frame(width: 0, height: 0).revealLineBreak()
                } else if let atom = item.word.atoms.first {
                    let opacity = trail.starts[atom.revealIndex].map {
                        RevealSmoothTrail.opacity(age: time - $0)
                    } ?? 1
                    switch atom.kind {
                    case .text(let string):
                        if let imageURL = string.avatarImageURL {
                            RevealInlineAvatarAtomView(
                                imageURL: imageURL,
                                baseFont: block.avatarBaseFont(configuration),
                                opacity: opacity,
                                linkURL: atom.url,
                                onLinkTap: onLinkTap
                            )
                        } else {
                            Text(appending(item.trailingSpace, to: string))
                                .opacity(opacity)
                                .environment(\.openURL, OpenURLAction { url in
                                    onLinkTap(url)
                                    return .handled
                                })
                        }
                    case .space(let string):
                        Text(string)
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }
}
