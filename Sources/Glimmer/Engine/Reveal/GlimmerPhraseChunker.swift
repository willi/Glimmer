import Foundation
import NaturalLanguage

/// Splits arriving text into reveal phrases.
enum GlimmerPhraseChunker {
    /// The UTF-16 offset where the phrase starting at `start` ends, or nil while not enough complete text has arrived.
    ///
    /// A phrase ends after punctuation once it has `minWords` words, at `maxWords` words, or at a line end. Words and
    /// grapheme clusters are never split; a block attachment on its own line is a phrase by itself. While streaming, a
    /// word counts only once whitespace follows it. Scripts without spaces use linguistic word boundaries instead.
    static func phraseEnd(in text: NSString, from start: Int, isStreaming: Bool, minWords: Int, maxWords: Int) -> Int? {
        let length = text.length
        guard start < length else { return nil }
        var index = start
        var words = 0
        var inWord = false
        var lastWordEndsWithPunctuation = false
        var lastCompleteEnd: Int?
        while index < length {
            let range = text.rangeOfComposedCharacterSequence(at: index)
            let character = text.substring(with: range)
            if needsLinguisticBoundaries(character) {
                return linguisticPhraseEnd(in: text, from: start, isStreaming: isStreaming,
                                           minWords: minWords, maxWords: maxWords)
            }
            if character == "\n" { return NSMaxRange(range) }
            if character == " " || character == "\t" {
                if inWord {
                    inWord = false
                    words += 1
                    if words >= maxWords || (words >= minWords && lastWordEndsWithPunctuation) {
                        return endOfWhitespace(in: text, from: NSMaxRange(range))
                    }
                }
                lastCompleteEnd = NSMaxRange(range)
            } else {
                inWord = true
                // A closing quote or bracket after punctuation ("stop.") keeps the sentence end.
                if !(character.count == 1 && "\"'\u{201D}\u{2019})]\u{00BB}".contains(character)) {
                    lastWordEndsWithPunctuation = character.count == 1 && ",.;:!?".contains(character)
                }
            }
            index = NSMaxRange(range)
        }
        if !isStreaming { return length }
        if words >= minWords, let lastCompleteEnd { return lastCompleteEnd }
        return nil
    }

    private static func needsLinguisticBoundaries(_ character: String) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0E00...0x0EFF, 0x1000...0x109F, 0x1780...0x17FF, // Thai, Lao, Myanmar, Khmer
                 0x3040...0x30FF, 0x31F0...0x31FF, // Japanese syllabaries
                 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF: // Han
                scalar.properties.isAlphabetic
            default:
                false
            }
        }
    }

    /// Tokenize a short window immediately, rather than rescanning the whole backlog for each phrase. Expand only
    /// if a long word crosses that window, so neither a Latin word nor a composed character is cut in half.
    private static func linguisticPhraseEnd(
        in text: NSString, from start: Int, isStreaming: Bool, minWords: Int, maxWords: Int
    ) -> Int? {
        var windowLength = 256
        while true {
            let limit = min(text.length, start + windowLength)
            let characterEnd = NSMaxRange(text.rangeOfComposedCharacterSequence(at: limit - 1))
            let newline = text.range(of: "\n", range: NSRange(location: start, length: characterEnd - start))
            let windowEnd = newline.location == NSNotFound ? characterEnd : NSMaxRange(newline)
            let hasMore = windowEnd < text.length
            let tail = text.substring(with: NSRange(location: start, length: windowEnd - start))
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = tail
            var words = 0
            var end: String.Index?
            var reachedLineEnd = false
            tokenizer.enumerateTokens(in: tail.startIndex..<tail.endIndex) { range, _ in
                // A final token may still grow, either in the next network chunk or beyond this window.
                guard (!isStreaming && !hasMore) || range.upperBound < tail.endIndex else { return false }
                // NLTokenizer splits long Latin words into shorter tokens. Count only the last one, so its
                // implementation limit never becomes a visible break inside a word.
                if continuesSpacedWord(in: tail, at: range.upperBound) { return true }
                words += 1
                var boundary = range.upperBound
                var hasPunctuation = false
                while boundary < tail.endIndex {
                    let character = tail[boundary]
                    if character == "\n" {
                        boundary = tail.index(after: boundary)
                        reachedLineEnd = true
                        break
                    }
                    let punctuation = ",.;:!?。！？、，；：…".contains(character)
                    guard character.isWhitespace || punctuation || "\"'\u{201D}\u{2019})]\u{00BB}」』".contains(character) else { break }
                    hasPunctuation = hasPunctuation || punctuation
                    boundary = tail.index(after: boundary)
                }
                end = boundary
                return !reachedLineEnd && words < maxWords && !(words >= minWords && hasPunctuation)
            }
            if reachedLineEnd, let end { return start + tail[..<end].utf16.count }
            if words >= minWords, let end { return start + tail[..<end].utf16.count }
            // Emoji and other non-word content can separate the last token from the line break.
            if newline.location != NSNotFound { return NSMaxRange(newline) }
            guard hasMore else { return isStreaming ? nil : text.length }
            windowLength *= 2
        }
    }

    private static func continuesSpacedWord(in text: String, at boundary: String.Index) -> Bool {
        guard boundary > text.startIndex, boundary < text.endIndex else { return false }
        func isWordCharacter(_ character: Character) -> Bool {
            (character.isLetter || character.isNumber || character == "_") && !needsLinguisticBoundaries(String(character))
        }
        func isConnector(_ character: Character) -> Bool { "-'’‐‑".contains(character) }
        let previous = text.index(before: boundary)
        let before = text[previous]
        let after = text[boundary]
        if isWordCharacter(before) {
            if isWordCharacter(after) { return true }
            if isConnector(after) {
                let following = text.index(after: boundary)
                // A connector at the window edge may still join the next word; wait for the expanded window.
                return following == text.endIndex || isWordCharacter(text[following])
            }
        }
        if isConnector(before), isWordCharacter(after), previous > text.startIndex {
            return isWordCharacter(text[text.index(before: previous)])
        }
        return false
    }

    /// Past the spaces after a phrase, and past one line end if that is what follows them.
    private static func endOfWhitespace(in text: NSString, from index: Int) -> Int {
        var end = index
        while end < text.length {
            let unit = text.character(at: end)
            if unit == 0x20 || unit == 0x09 { end += 1; continue }
            if unit == 0x0A { end += 1 }
            break
        }
        return end
    }
}
