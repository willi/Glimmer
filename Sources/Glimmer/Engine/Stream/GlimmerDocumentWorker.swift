import Foundation

/// What a worker update produced, handed to the main thread once. `@unchecked` because the attributed string and the
/// attachments inside it are built by the worker, which afterwards uses the attachments only as identities (reuse and
/// trimming compare them by pointer); the main thread owns their contents from here on.
struct GlimmerDocumentResult: @unchecked Sendable {
    let edit: GlimmerDocumentEdit?
    let embedUnits: [Int: [Int]]
    /// The request's own flag: a newer request may already have ended the stream.
    let isStreaming: Bool
}

/// Runs a view's document off the main thread, one update at a time, in the order requested.
actor GlimmerDocumentWorker {
    private let document: GlimmerStreamingDocument
    private let extensions: [any GlimmerExtension]

    init(document: GlimmerStreamingDocument, extensions: [any GlimmerExtension]) {
        self.document = document
        self.extensions = extensions
    }

    func update(markdown: String, isStreaming: Bool) -> GlimmerDocumentResult {
        let source = extensions.reduce(markdown) { $1.preprocess($0) }
        let edit = document.update(markdown: source, isStreaming: isStreaming)
        return GlimmerDocumentResult(edit: edit, embedUnits: document.embedUnits, isStreaming: isStreaming)
    }
}
