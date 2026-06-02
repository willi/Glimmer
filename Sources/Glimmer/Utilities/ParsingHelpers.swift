import Foundation

enum ParsingHelpers {
    @inline(__always)
    static func isHexChar(_ char: Character) -> Bool {
        return (char >= "0" && char <= "9") ||
               (char >= "a" && char <= "f") ||
               (char >= "A" && char <= "F")
    }

    @inline(__always)
    static func isWhitespace(_ char: Character) -> Bool {
        return char == " " || char == "\t" || char == "\n" || char == "\r"
    }

    @inline(__always)
    static func skipSpaces(in text: String, from index: inout String.Index, end: String.Index) {
        while index < end && (text[index] == " " || text[index] == "\t") {
            index = text.index(after: index)
        }
    }

    // Scan a quoted string: title delimiters '"', '\'', or parentheses. Supports backslash escapes for quotes.
    // Returns (content, endIndexAfterClosing) or nil on failure.
    static func scanQuoted(in text: String, from start: String.Index, end: String.Index, delimiter: Character) -> (String, String.Index)? {
        var idx = start
        var result = ""
        switch delimiter {
        case Character("\""):
            while idx < end {
                let ch = text[idx]
                if ch == "\\" { // escape
                    let next = text.index(after: idx)
                    if next < end { result.append(text[next]); idx = text.index(after: next) } else { return nil }
                } else if ch == Character("\"") {
                    return (result, text.index(after: idx))
                } else {
                    result.append(ch); idx = text.index(after: idx)
                }
            }
            return nil
        case Character("'"):
            while idx < end {
                let ch = text[idx]
                if ch == "\\" {
                    let next = text.index(after: idx)
                    if next < end { result.append(text[next]); idx = text.index(after: next) } else { return nil }
                } else if ch == Character("'") {
                    return (result, text.index(after: idx))
                } else {
                    result.append(ch); idx = text.index(after: idx)
                }
            }
            return nil
        case Character("("):
            // Read until matching ')' without nesting for simplicity
            while idx < end {
                let ch = text[idx]
                if ch == ")" {
                    return (result, text.index(after: idx))
                } else if ch == "\\" {
                    let next = text.index(after: idx)
                    if next < end { result.append(text[next]); idx = text.index(after: next) } else { return nil }
                } else {
                    result.append(ch); idx = text.index(after: idx)
                }
            }
            return nil
        default:
            return nil
        }
    }

    // Scan while predicate returns true, starting at index. Advances the provided index and
    // returns the collected String. If maxCount is provided, stops after consuming that many chars.
    @inline(__always)
    static func scanWhile(in text: String, from index: inout String.Index, end: String.Index, while predicate: (Character) -> Bool, maxCount: Int? = nil) -> String {
        var result = ""
        var count = 0
        while index < end {
            let ch = text[index]
            if let max = maxCount, count >= max { break }
            if predicate(ch) {
                result.append(ch)
                index = text.index(after: index)
                count += 1
            } else {
                break
            }
        }
        return result
    }

    // Scan a balanced region given opening and closing delimiters.
    // Precondition: `start` points to the character immediately after the first opening delimiter.
    // Returns (contentBetween, indexAfterMatchingClose) or nil if not balanced before end.
    static func scanBalanced(in text: String, from start: String.Index, end: String.Index, open: Character, close: Character, allowEscape: Bool = true) -> (String, String.Index)? {
        var idx = start
        var depth = 1
        var out = ""
        while idx < end {
            let ch = text[idx]
            if allowEscape && ch == "\\" {
                let next = text.index(after: idx)
                if next < end {
                    // Preserve the escape sequence so downstream parsers can
                    // decide whether/how to unescape (e.g., link titles).
                    out.append("\\")
                    out.append(text[next])
                    idx = text.index(after: next)
                    continue
                } else {
                    return nil
                }
            }
            if ch == open {
                depth += 1
                out.append(ch)
                idx = text.index(after: idx)
            } else if ch == close {
                depth -= 1
                if depth == 0 {
                    // Do not include this closing delimiter
                    return (out, text.index(after: idx))
                } else {
                    out.append(ch)
                    idx = text.index(after: idx)
                }
            } else {
                out.append(ch)
                idx = text.index(after: idx)
            }
        }
        return nil
    }

    // MARK: - ASCII fast-path helpers
    @inline(__always) static func isASCIIDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
    @inline(__always) static func isASCIIHex(_ b: UInt8) -> Bool { (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66) }
    @inline(__always) static func isASCIIAlpha(_ b: UInt8) -> Bool { (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) }
    @inline(__always) static func isASCIIAlnum(_ b: UInt8) -> Bool { isASCIIDigit(b) || isASCIIAlpha(b) }

    // UTF-8 backed scanning for ASCII-only predicates.
    // Advances `index` and returns collected substring.
    static func scanWhileUTF8(
        in text: String,
        from index: inout String.Index,
        end: String.Index,
        while predicate: (UInt8) -> Bool,
        maxCount: Int? = nil
    ) -> String {
        guard let startUTF8 = index.samePosition(in: text.utf8), let endUTF8 = end.samePosition(in: text.utf8) else {
            return ""
        }
        var uidx = startUTF8
        var out: [UInt8] = []
        out.reserveCapacity(16)
        var count = 0
        while uidx < endUTF8 {
            let b = text.utf8[uidx]
            if b < 0x80 { // ASCII fast path only
                if let max = maxCount, count >= max { break }
                if predicate(b) {
                    out.append(b)
                    count += 1
                    uidx = text.utf8.index(after: uidx)
                    continue
                }
            }
            break
        }
        if let newIdx = String.Index(uidx, within: text) { index = newIdx }
        return String(decoding: out, as: UTF8.self)
    }

    // Fast ASCII content check using UTF-8 view
    @inline(__always)
    static func isASCII(_ text: String) -> Bool {
        for b in text.utf8 { if b & 0x80 != 0 { return false } }
        return true
    }

    // Find first ASCII space or tab from index to end; returns end if none found
    @inline(__always)
    static func firstASCIISpaceOrTab(in text: String, from: String.Index, end: String.Index) -> String.Index {
        guard let uStart = from.samePosition(in: text.utf8), let uEnd = end.samePosition(in: text.utf8) else {
            return end
        }
        var uidx = uStart
        while uidx < uEnd {
            let b = text.utf8[uidx]
            if b == 0x20 || b == 0x09 { // space or tab
                if let idx = String.Index(uidx, within: text) { return idx }
                break
            }
            uidx = text.utf8.index(after: uidx)
        }
        return end
    }

    // MARK: - Slugification
    /// Fast slugifier for heading IDs: keep letters, digits, spaces, and hyphens;
    /// convert spaces to single hyphens; trim leading/trailing hyphens. Lowercases ASCII.
    @inline(__always)
    static func slugifyHeading(_ text: String) -> String {
        if text.isEmpty { return "" }
        var out = String(); out.reserveCapacity(text.count)
        var prevWasHyphen = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39: // 0-9
                out.unicodeScalars.append(scalar)
                prevWasHyphen = false
            case 0x41...0x5A: // A-Z
                out.unicodeScalars.append(UnicodeScalar(scalar.value + 0x20)!) // lowercase
                prevWasHyphen = false
            case 0x61...0x7A: // a-z
                out.unicodeScalars.append(scalar)
                prevWasHyphen = false
            case 0x20, 0x09: // space or tab -> hyphen
                if !prevWasHyphen { out.append("-"); prevWasHyphen = true }
            case 0x2D: // '-'
                if !prevWasHyphen { out.append("-"); prevWasHyphen = true }
            default:
                // Skip other punctuation/marks for simplicity
                continue
            }
        }
        // Trim leading/trailing hyphens
        while out.first == "-" { out.removeFirst() }
        while out.last == "-" { out.removeLast() }
        return out
    }
}
