import Foundation

/// Custom `AttributedString` attribute carrying the image URL of an inline
/// avatar during the reveal animation. The reveal flattens inline content into
/// per-word `AttributedString`s; a normal inline image is baked in as the text
/// `[Image: alt]`. For avatars (`alt == "avatar"`, case-insensitive) we instead
/// emit a single Object-Replacement-Character (`\u{FFFC}`) carrying this
/// attribute, and the per-word reveal renderers swap that marker for a circular
/// avatar view — visually identical to the settled `NSTextAttachment` avatar.
///
/// This attribute never reaches the settled / export renderers: the settled
/// path re-parses the real markdown, and the marker is only produced by the
/// reveal flattener.
enum GlimmerAvatarImageAttribute: AttributedStringKey {
    typealias Value = URL
    static let name = "glimmer.avatarImageURL"
}

extension AttributeScopes {
    /// Glimmer's private attribute scope (currently just the avatar marker).
    struct GlimmerAttributes: AttributeScope {
        let glimmerAvatarImageURL: GlimmerAvatarImageAttribute
    }

    var glimmer: GlimmerAttributes.Type { GlimmerAttributes.self }
}

extension AttributeDynamicLookup {
    /// Enables `attributedString.glimmerAvatarImageURL` / `run.glimmerAvatarImageURL`.
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.GlimmerAttributes, T>
    ) -> T {
        self[T.self]
    }
}

extension AttributedString {
    /// The Object-Replacement-Character that stands in for one inline avatar
    /// during the reveal (a single, countable "word").
    static let glimmerAvatarMarkerCharacter = "\u{FFFC}"

    /// A one-character attributed marker for an inline avatar: an
    /// Object-Replacement-Character carrying `imageURL` (custom attribute) plus,
    /// when present, the wrapping link as `.link` (so the avatar stays tappable).
    static func glimmerAvatarMarker(imageURL: URL, linkURL: URL?) -> AttributedString {
        var marker = AttributedString(glimmerAvatarMarkerCharacter)
        marker.glimmerAvatarImageURL = imageURL
        if let linkURL {
            marker.link = linkURL
        }
        return marker
    }

    /// The avatar image URL if any run of this slice carries the avatar marker
    /// attribute; `nil` for ordinary text. A path-1 marker atom is exactly the
    /// one-character marker, so the first run answers immediately.
    var avatarImageURL: URL? {
        for run in runs {
            if let url = run.glimmerAvatarImageURL { return url }
        }
        return nil
    }
}
