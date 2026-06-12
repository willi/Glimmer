import SwiftUI

extension AttributedString {
    /// Splits into alternating word / whitespace slices, preserving attributes.
    /// Consecutive whitespace characters collapse into a single slice.
    /// `containsNewline` is computed during the same walk so callers never
    /// re-scan whitespace slices (always false for word slices).
    /// Implementation note: walks the rope's `characters` view once and emits
    /// rope sub-slices per token. A run-based rebuild (plain-String walking +
    /// per-segment AttributedString construction) was measured slower — the
    /// small-string construct/append churn outweighs the cheaper grapheme walk.
    func revealTokens() -> [(slice: AttributedString, isWhitespace: Bool, containsNewline: Bool)] {
        var tokens: [(slice: AttributedString, isWhitespace: Bool, containsNewline: Bool)] = []
        guard !characters.isEmpty else { return tokens }
        var runStart = startIndex
        var runIsSpace = characters[startIndex].isWhitespace
        var runHasNewline = runIsSpace && characters[startIndex].isNewline
        var i = characters.index(after: startIndex)
        while i < endIndex {
            let ch = characters[i]
            let isSpace = ch.isWhitespace
            if isSpace != runIsSpace {
                tokens.append((AttributedString(self[runStart..<i]), runIsSpace, runHasNewline))
                runStart = i
                runIsSpace = isSpace
                runHasNewline = false
            }
            if isSpace && ch.isNewline { runHasNewline = true }
            i = characters.index(after: i)
        }
        tokens.append((AttributedString(self[runStart..<endIndex]), runIsSpace, runHasNewline))
        return tokens
    }

    /// Splits into single-character slices, preserving attributes. Iterates
    /// runs so each character is rebuilt from a plain `String` plus the run's
    /// attributes — much cheaper than slicing the underlying rope per
    /// character (rope index validation + node copies dominate profiles).
    func revealCharacters() -> [AttributedString] {
        var result: [AttributedString] = []
        for run in runs {
            let attributes = run.attributes
            for ch in String(self[run.range].characters) {
                result.append(AttributedString(String(ch), attributes: attributes))
            }
        }
        return result
    }
}
