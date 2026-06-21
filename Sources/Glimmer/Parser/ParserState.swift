import Foundation

/// Parser state with position tracking and fragment buffer
public struct ParserState {
    let text: String
    // String.Index-based cursor for efficient navigation
    var currentIndex: String.Index
    let endIndex: String.Index
    var line: Int
    var column: Int
    // Enables ASCII/UTF-8 fast path scans for inline parsing
    var asciiFastPath: Bool
    private var asciiFastPathChecked: Bool
    private let sourceASCIIFastPath: Bool?

    // Fragment buffer for accumulating text efficiently
    private var fragmentBuffer: String
    private var pendingLiteralRange: Range<String.Index>?

    public init(text: String) {
        self.text = text
        self.currentIndex = text.startIndex
        self.endIndex = text.endIndex
        self.line = 1
        self.column = 1
        self.asciiFastPath = false
        self.asciiFastPathChecked = false
        self.sourceASCIIFastPath = nil
        self.fragmentBuffer = String()
        self.pendingLiteralRange = nil
    }

    init(text: String, sourceASCIIFastPath: Bool?) {
        self.text = text
        self.currentIndex = text.startIndex
        self.endIndex = text.endIndex
        self.line = 1
        self.column = 1
        self.asciiFastPath = false
        self.asciiFastPathChecked = false
        self.sourceASCIIFastPath = sourceASCIIFastPath
        self.fragmentBuffer = String()
        self.pendingLiteralRange = nil
    }

    init(
        text: String,
        currentIndex: String.Index,
        endIndex: String.Index,
        line: Int = 1,
        column: Int = 1,
        asciiFastPath: Bool? = nil,
        sourceASCIIFastPath: Bool? = nil
    ) {
        self.text = text
        self.currentIndex = currentIndex
        self.endIndex = endIndex
        self.line = line
        self.column = column
        if let asciiFastPath {
            self.asciiFastPath = asciiFastPath
        } else {
            self.asciiFastPath = ParsingHelpers.isASCII(in: text, from: currentIndex, to: endIndex)
        }
        self.asciiFastPathChecked = true
        self.sourceASCIIFastPath = sourceASCIIFastPath
        self.fragmentBuffer = String()
        self.pendingLiteralRange = nil
    }

    // MARK: - Navigation (String.Index-based)

    @inline(__always)
    var isAtEnd: Bool { currentIndex >= endIndex }

    @inline(__always)
    mutating func enableASCIIFastPathIfPossible() {
        guard !asciiFastPath, !asciiFastPathChecked else { return }
        asciiFastPath = ParsingHelpers.isASCII(in: text, from: currentIndex, to: endIndex)
        asciiFastPathChecked = true
    }

    mutating func repeatFullTextASCIIEligibilityScanForTesting() {
        asciiFastPath = ParsingHelpers.isASCII(text)
        asciiFastPathChecked = true
    }

    @inline(__always)
    var inlineRangeASCIIFastPath: Bool? {
        sourceASCIIFastPath == true ? true : nil
    }

    @inline(__always)
    mutating func finish() {
        currentIndex = endIndex
    }

    @inline(__always)
    func current() -> Character? {
        guard !isAtEnd else { return nil }
        return text[currentIndex]
    }

    @inline(__always)
    func peek(_ n: Int = 1) -> Character? {
        guard n >= 0 else { return nil }
        var idx = currentIndex
        var k = n
        while k > 0 && idx < endIndex {
            idx = text.index(after: idx)
            k -= 1
        }
        if idx >= endIndex { return nil }
        return text[idx]
    }

    @inline(__always)
    mutating func advance() {
        guard !isAtEnd else { return }
        if asciiFastPath {
            let byte = text.utf8[currentIndex]
            if byte == 0x0D {
                let nextIndex = text.utf8.index(after: currentIndex)
                if nextIndex < endIndex, text.utf8[nextIndex] == 0x0A {
                    currentIndex = text.utf8.index(after: nextIndex)
                    column += 1
                    return
                }
            }

            currentIndex = text.utf8.index(after: currentIndex)
            if byte == 0x0A {
                line += 1
                column = 1
            } else {
                column += 1
            }
            return
        }

        advanceByCharacter()
    }

    mutating func advanceByCharacterForTesting() {
        advanceByCharacter()
    }

    @inline(__always)
    private mutating func advanceByCharacter() {
        guard !isAtEnd else { return }
        let ch = text[currentIndex]
        if ch == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        currentIndex = text.index(after: currentIndex)
    }

    @inline(__always)
    mutating func advance(by n: Int) {
        var k = n
        while k > 0 { advance(); k -= 1 }
    }

    @inline(__always)
    mutating func advanceLine() {
        guard !isAtEnd else { return }
        let utf8 = text.utf8
        let start = currentIndex
        var index = start
        var sawNonASCII = false

        while index < endIndex {
            let byte = utf8[index]
            if byte == 0x0D {
                advanceLineByCharacter()
                return
            }

            if byte == 0x0A {
                line += 1
                column = 1
                currentIndex = utf8.index(after: index)
                return
            }

            if byte >= 0x80 {
                sawNonASCII = true
            }
            index = utf8.index(after: index)
        }

        guard !sawNonASCII else {
            advanceLineByCharacter()
            return
        }

        column += utf8.distance(from: start, to: endIndex)
        currentIndex = endIndex
    }

    mutating func advanceLineByCharacterForTesting() {
        advanceLineByCharacter()
    }

    @inline(__always)
    private mutating func advanceLineByCharacter() {
        while let ch = current(), ch != "\n" { advance() }
        if let ch = current(), ch == "\n" { advance() }
    }

    @inline(__always)
    mutating func advanceToLineEnd() {
        guard !isAtEnd else { return }
        let utf8 = text.utf8
        let utf8Start = currentIndex
        let utf8End = endIndex
        var utf8Index = utf8Start
        var columnAdvance = 0
        while utf8Index < utf8End {
            let byte = utf8[utf8Index]
            if byte == 0x0A {
                column += columnAdvance
                currentIndex = utf8Index
                return
            }
            if byte >= 0x80 {
                advanceToLineEndByCharacter()
                return
            }
            columnAdvance += 1
            utf8Index = utf8.index(after: utf8Index)
        }

        column += columnAdvance
        currentIndex = endIndex
    }

    mutating func advanceToLineEndByDistanceAccountingForTesting() {
        guard !isAtEnd else { return }
        let utf8 = text.utf8
        let utf8Start = currentIndex
        let utf8End = endIndex
        var utf8Index = utf8Start
        while utf8Index < utf8End {
            let byte = utf8[utf8Index]
            if byte == 0x0A {
                column += utf8.distance(from: utf8Start, to: utf8Index)
                currentIndex = utf8Index
                return
            }
            if byte >= 0x80 {
                advanceToLineEndByCharacter()
                return
            }
            utf8Index = utf8.index(after: utf8Index)
        }

        column += utf8.distance(from: utf8Start, to: utf8End)
        currentIndex = endIndex
    }

    @inline(__always)
    private mutating func advanceToLineEndByCharacter() {
        while let ch = current(), ch != "\n" {
            advance()
        }
    }

    // Move forward to a given index; assumes target >= currentIndex
    mutating func advance(to target: String.Index) {
        var idx = currentIndex
        while idx < target && idx < endIndex {
            advance()
            idx = currentIndex
        }
    }

    // Move directly to a String.Index
    mutating func move(to target: String.Index) {
        guard target != currentIndex else { return }

        // Forward movement can preserve position tracking by advancing.
        if target > currentIndex {
            if asciiFastPath,
               let utf8Target = target.samePosition(in: text.utf8) {
                moveForwardASCII(to: target, utf8Target: utf8Target)
            } else {
                advance(to: target)
            }
            return
        }

        // Backward movement: adjust line/column by scanning only the rewound region.
        var newlineCount = 0
        var probe = currentIndex
        while probe > target {
            let prev = text.index(before: probe)
            if text[prev] == "\n" { newlineCount += 1 }
            probe = prev
        }
        line = max(1, line - newlineCount)

        var scan = target
        var newColumn = 1
        while scan > text.startIndex {
            let prev = text.index(before: scan)
            if text[prev] == "\n" { break }
            newColumn += 1
            scan = prev
        }
        column = newColumn
        currentIndex = target
    }

    @inline(__always)
    private mutating func moveForwardASCII(to target: String.Index, utf8Target: String.UTF8View.Index) {
        let utf8 = text.utf8
        var index = currentIndex
        var consumedColumns = 0
        var lineBreaks = 0
        var bytesAfterLastLineBreak = 0

        while index < utf8Target {
            let byte = utf8[index]
            if byte == 0x0D {
                let nextIndex = utf8.index(after: index)
                if nextIndex < endIndex, nextIndex < utf8Target, utf8[nextIndex] == 0x0A {
                    if lineBreaks == 0 {
                        consumedColumns += 1
                    } else {
                        bytesAfterLastLineBreak += 1
                    }
                    index = utf8.index(after: nextIndex)
                    continue
                }
            }

            index = utf8.index(after: index)
            if byte == 0x0A {
                lineBreaks += 1
                bytesAfterLastLineBreak = 0
            } else if lineBreaks == 0 {
                consumedColumns += 1
            } else {
                bytesAfterLastLineBreak += 1
            }
        }

        if lineBreaks == 0 {
            column += consumedColumns
        } else {
            line += lineBreaks
            column = bytesAfterLastLineBreak + 1
        }
        currentIndex = target
    }

    @inline(__always)
    mutating func moveASCII(to target: String.Index) {
        guard target != currentIndex else { return }
        guard target > currentIndex, asciiFastPath else {
            move(to: target)
            return
        }

        column += text.utf8.distance(from: currentIndex, to: target)
        currentIndex = target
    }

    @inline(__always)
    mutating func moveASCII(
        to target: String.Index,
        consumedBytes: Int,
        lineBreaks: Int,
        bytesAfterLastLineBreak: Int
    ) {
        guard target != currentIndex else { return }
        guard target > currentIndex, asciiFastPath else {
            move(to: target)
            return
        }

        if lineBreaks == 0 {
            column += consumedBytes
        } else {
            line += lineBreaks
            column = bytesAfterLastLineBreak + 1
        }
        currentIndex = target
    }

    // Snapshot/restore position
    struct Mark {
        let index: String.Index
        let line: Int
        let column: Int
    }

    @inline(__always)
    func mark() -> Mark {
        Mark(index: currentIndex, line: line, column: column)
    }

    @inline(__always)
    mutating func restore(_ m: Mark) {
        currentIndex = m.index
        line = m.line
        column = m.column
    }

    @inline(__always)
    func index(offsetBy n: Int) -> String.Index? {
        guard n >= 0 else { return nil }
        var idx = currentIndex
        var k = n
        while k > 0 && idx < endIndex {
            idx = text.index(after: idx)
            k -= 1
        }
        return k == 0 ? idx : nil
    }

    // MARK: - Text Access

    func substring(from start: Int, to end: Int) -> String {
        guard start < end && start >= 0 && end <= text.count else {
            return ""
        }
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        return String(text[startIndex..<endIndex])
    }

    func substring(from start: String.Index, to end: String.Index) -> String {
        guard start <= end && end <= endIndex else { return "" }
        return String(text[start..<end])
    }

    func remainingSubstring() -> String {
        guard !isAtEnd else { return "" }
        return String(text[currentIndex..<endIndex])
    }

    // Check if current line is empty (spaces/tabs only until newline or end)
    @inline(__always)
    func isAtEmptyLine() -> Bool {
        let utf8 = text.utf8
        var index = currentIndex
        while index < endIndex {
            switch utf8[index] {
            case 0x20, 0x09: // space, tab
                index = utf8.index(after: index)
                continue
            case 0x0A: // newline
                return true
            default:
                return false
            }
        }
        return true
    }

    func isAtEmptyLineByCharacterScanningForTesting() -> Bool {
        var idx = currentIndex
        while idx < endIndex {
            let ch = text[idx]
            if ch == " " || ch == "\t" {
                idx = text.index(after: idx)
                continue
            }
            return ch == "\n"
        }
        return true
    }

    @discardableResult
    @inline(__always)
    mutating func advanceIfAtEmptyLine() -> Bool {
        let utf8 = text.utf8
        let start = currentIndex
        var index = start

        while index < endIndex {
            switch utf8[index] {
            case 0x20, 0x09: // space, tab
                index = utf8.index(after: index)
            case 0x0A: // newline
                line += 1
                column = 1
                currentIndex = utf8.index(after: index)
                return true
            default:
                return false
            }
        }

        column += utf8.distance(from: start, to: endIndex)
        currentIndex = endIndex
        return true
    }

    @discardableResult
    mutating func advanceIfAtEmptyLineBySeparateScanForTesting() -> Bool {
        guard isAtEmptyLine() else { return false }
        advanceLine()
        return true
    }

    // MARK: - Fragment Buffer Management

    @inline(__always)
    mutating func appendToFragmentBuffer(_ char: Character) {
        materializePendingLiteralRange()
        fragmentBuffer.append(char)
    }

    @inline(__always)
    mutating func appendLiteralRunToFragmentBuffer(upTo target: String.Index) {
        appendLiteralRunToFragmentBuffer(upTo: target, consumedBytes: nil)
    }

    @inline(__always)
    mutating func appendLiteralRunToFragmentBuffer(upTo target: String.Index, consumedBytes: Int?) {
        guard target > currentIndex else { return }
        if fragmentBuffer.isEmpty {
            if let range = pendingLiteralRange, range.upperBound == currentIndex {
                pendingLiteralRange = range.lowerBound..<target
            } else {
                materializePendingLiteralRange()
                pendingLiteralRange = currentIndex..<target
            }
        } else {
            materializePendingLiteralRange()
            fragmentBuffer.append(contentsOf: text[currentIndex..<target])
        }

        if asciiFastPath,
           target >= currentIndex,
           let consumedBytes {
            column += consumedBytes
            currentIndex = target
        } else if asciiFastPath,
                  target >= currentIndex {
            column += text.utf8.distance(from: currentIndex, to: target)
            currentIndex = target
        } else {
            advance(to: target)
        }
    }

    @inline(__always)
    mutating func appendLiteralRunToFragmentBufferByCopyingForTesting(upTo target: String.Index) {
        guard target > currentIndex else { return }
        materializePendingLiteralRange()
        fragmentBuffer.append(contentsOf: text[currentIndex..<target])

        if asciiFastPath,
           target >= currentIndex {
            column += text.utf8.distance(from: currentIndex, to: target)
            currentIndex = target
        } else {
            advance(to: target)
        }
    }

    mutating func flushFragmentBuffer(_ inlines: inout [MarkdownParser.InlineNode]) {
        if let range = pendingLiteralRange {
            if fragmentBuffer.isEmpty {
                inlines.append(.text(String(text[range])))
                pendingLiteralRange = nil
                return
            }

            fragmentBuffer.append(contentsOf: text[range])
            pendingLiteralRange = nil
        }

        if !fragmentBuffer.isEmpty {
            inlines.append(.text(fragmentBuffer))
            fragmentBuffer.removeAll(keepingCapacity: true)
        }
    }

    @inline(__always)
    private mutating func materializePendingLiteralRange() {
        guard let range = pendingLiteralRange else { return }
        fragmentBuffer.append(contentsOf: text[range])
        pendingLiteralRange = nil
    }
}

// MARK: - String Extension for Parser

// Int subscript removed; String.Index is canonical in parsers
