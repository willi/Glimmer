import Foundation

/// A block attachment and the embed it was composed with, at an offset within its block's fragment.
struct GlimmerEmbeddedAttachment {
    let attachment: GlimmerBlockAttachment
    let embed: GlimmerEmbed
    let offset: Int
}

/// An attachment kept across a re-compose whose embed grew. `GlimmerView` hands the embed to the attachment's view
/// before applying the text edit.
struct GlimmerEmbedUpdate {
    let attachment: GlimmerBlockAttachment
    let embed: GlimmerEmbed
}

/// The attachments of a block being re-composed, offered back to the composer in order, so a growing code block or
/// table keeps its attachment and with it its view. Also records every attachment the composer emits, which becomes
/// the next re-compose's candidates.
final class GlimmerAttachmentReuse {
    private var candidates: [GlimmerEmbeddedAttachment]
    private(set) var updates: [GlimmerEmbedUpdate] = []
    private(set) var emitted: [GlimmerEmbeddedAttachment] = []

    init(_ candidates: [GlimmerEmbeddedAttachment] = []) {
        self.candidates = candidates
    }

    /// The next candidate if `embed` continues it; nil if a new attachment is needed.
    func attachment(for embed: GlimmerEmbed) -> GlimmerBlockAttachment? {
        guard let candidate = candidates.first, embed.continues(candidate.embed) else { return nil }
        candidates.removeFirst()
        updates.append(GlimmerEmbedUpdate(attachment: candidate.attachment, embed: embed))
        return candidate.attachment
    }

    /// Notes an attachment the composer put at `offset` in the fragment it is building.
    func record(_ attachment: GlimmerBlockAttachment, embed: GlimmerEmbed, at offset: Int) {
        emitted.append(GlimmerEmbeddedAttachment(attachment: attachment, embed: embed, offset: offset))
    }
}
