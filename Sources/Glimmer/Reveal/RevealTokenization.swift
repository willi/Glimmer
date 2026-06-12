import SwiftUI

extension AttributedString {
    /// Splits into alternating word / whitespace slices, preserving attributes.
    /// Consecutive whitespace characters collapse into a single slice.
    func revealTokens() -> [(slice: AttributedString, isWhitespace: Bool)] {
        var tokens: [(slice: AttributedString, isWhitespace: Bool)] = []
        guard !characters.isEmpty else { return tokens }
        var runStart = startIndex
        var runIsSpace = characters[startIndex].isWhitespace
        var i = characters.index(after: startIndex)
        while i < endIndex {
            let isSpace = characters[i].isWhitespace
            if isSpace != runIsSpace {
                tokens.append((AttributedString(self[runStart..<i]), runIsSpace))
                runStart = i
                runIsSpace = isSpace
            }
            i = characters.index(after: i)
        }
        tokens.append((AttributedString(self[runStart..<endIndex]), runIsSpace))
        return tokens
    }

    /// Splits into single-character slices, preserving attributes.
    func revealCharacters() -> [AttributedString] {
        var result: [AttributedString] = []
        var i = startIndex
        while i < endIndex {
            let next = characters.index(after: i)
            result.append(AttributedString(self[i..<next]))
            i = next
        }
        return result
    }
}
