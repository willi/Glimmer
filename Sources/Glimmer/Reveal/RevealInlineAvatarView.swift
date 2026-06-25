import SwiftUI

extension RevealBlock {
    /// The resolved base font for this block's inline text, used to size inline
    /// avatars to the line height (mirrors the settled attachment, which sizes
    /// the avatar to its block base font's `lineHeight`). Headings use their
    /// configured heading font; everything else uses the body font.
    func avatarBaseFont(_ configuration: MarkdownConfiguration) -> Font {
        if case .heading(let level) = kind,
           level >= 1, level - 1 < configuration.headingFonts.count {
            return configuration.headingFonts[level - 1]
        }
        return configuration.baseFont
    }
}

/// Renders a single inline-avatar marker atom inside the reveal flow layout.
/// Cross-platform shell: on UIKit it draws the circular avatar; elsewhere
/// (e.g. the macOS test host) it collapses to nothing so no replacement-
/// character box appears.
struct RevealInlineAvatarAtomView: View {
    let imageURL: URL
    /// The block's base font; the avatar diameter is its UIFont line height.
    let baseFont: Font
    /// Trail-fade / scramble opacity applied to the avatar (1 elsewhere).
    var opacity: Double = 1
    /// Wrapping link target; when set together with `onLinkTap`, the avatar taps through.
    var linkURL: URL?
    var onLinkTap: ((URL) -> Void)?

    var body: some View {
        #if canImport(UIKit)
        let lineHeight = FontMapping.platformFont(from: baseFont).lineHeight
        let avatar = RevealInlineAvatarView(imageURL: imageURL, lineHeight: lineHeight)
            .opacity(opacity)
            .accessibilityHidden(true)
        if let linkURL, let onLinkTap {
            avatar
                .contentShape(Circle())
                .onTapGesture { onLinkTap(linkURL) }
        } else {
            avatar
        }
        #else
        Color.clear.frame(width: 0, height: 0)
        #endif
    }
}

#if canImport(UIKit)
/// A circular, line-height-sized inline avatar matching the settled
/// `NSTextAttachment` avatar (`ImageLoadingManager.circularImage`): aspect-fill,
/// center-cropped, clipped to a circle, sized to the surrounding line height.
struct RevealInlineAvatarView: View {
    let imageURL: URL
    let lineHeight: CGFloat

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .empty, .failure:
                Circle().fill(Color(uiColor: .systemGray6))
            @unknown default:
                Circle().fill(Color(uiColor: .systemGray6))
            }
        }
        .frame(width: lineHeight, height: lineHeight)
        .clipShape(Circle())
    }
}
#endif
