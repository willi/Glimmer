import Foundation

/// GitHub Flavored Markdown extensions parser
public struct GFMExtensions {
    private static let httpPrefix: [UInt8] = [0x68, 0x74, 0x74, 0x70, 0x3A, 0x2F, 0x2F]
    private static let httpsPrefix: [UInt8] = [0x68, 0x74, 0x74, 0x70, 0x73, 0x3A, 0x2F, 0x2F]
    private static let ftpPrefix: [UInt8] = [0x66, 0x74, 0x70, 0x3A, 0x2F, 0x2F]
    private static let mailtoPrefix: [UInt8] = [0x6D, 0x61, 0x69, 0x6C, 0x74, 0x6F, 0x3A]
    private static let wwwPrefix: [UInt8] = [0x77, 0x77, 0x77, 0x2E]

    
    // MARK: - Task Lists
    
    /// Parse task list markers in list items
    public static func parseTaskMarker(_ text: String) -> (isTask: Bool, isChecked: Bool, content: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("[ ] ") {
            return (true, false, String(trimmed.dropFirst(4)))
        } else if trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
            return (true, true, String(trimmed.dropFirst(4)))
        }
        
        return (false, false, text)
    }
    
    // MARK: - Tables
    
    /// Parse a complete table from lines
    public static func parseTable(lines: [String], configuration: MarkdownConfiguration) -> (headers: [MarkdownParser.TableCell], rows: [[MarkdownParser.TableCell]], alignments: [MarkdownParser.TableAlignment])? {
        guard lines.count >= 2 else { return nil }
        
        // Parse separator line for alignments
        let alignments = parseTableAlignments(lines[1])
        guard !alignments.isEmpty else { return nil }
        
        // Parse header
        let headers = parseTableRow(lines[0], alignments: alignments, configuration: configuration)
        
        // Parse body rows
        var rows: [[MarkdownParser.TableCell]] = []
        for i in 2..<lines.count {
            let row = parseTableRow(lines[i], alignments: alignments, configuration: configuration)
            rows.append(row)
        }
        
        return (headers, rows, alignments)
    }

    static func parseTable(
        source: String,
        lineRanges: [Range<String.Index>],
        configuration: MarkdownConfiguration,
        precomputedAlignments: [MarkdownParser.TableAlignment]? = nil
    ) -> (headers: [MarkdownParser.TableCell], rows: [[MarkdownParser.TableCell]], alignments: [MarkdownParser.TableAlignment])? {
        guard lineRanges.count >= 2 else { return nil }

        let alignments = precomputedAlignments ?? parseTableAlignments(source: source, range: lineRanges[1])
        guard !alignments.isEmpty else { return nil }

        let headers = parseTableRow(source: source, range: lineRanges[0], alignments: alignments, configuration: configuration)

        var rows: [[MarkdownParser.TableCell]] = []
        rows.reserveCapacity(max(0, lineRanges.count - 2))
        for range in lineRanges.dropFirst(2) {
            rows.append(parseTableRow(source: source, range: range, alignments: alignments, configuration: configuration))
        }

        return (headers, rows, alignments)
    }
    
    /// Parse table row into cells
    public static func parseTableRow(_ line: String, alignments: [MarkdownParser.TableAlignment]? = nil, configuration: MarkdownConfiguration) -> [MarkdownParser.TableCell] {
        if let cells = parseASCIITableRow(line, alignments: alignments, configuration: configuration) {
            return cells
        }

        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        var cells: [MarkdownParser.TableCell] = []
        cells.reserveCapacity(parts.count)
        for (index, part) in parts.enumerated() {
            // Skip leading and trailing empty cells from pipe characters
            if index == 0 && part.isEmpty { continue }
            if index == parts.count - 1 && part.isEmpty { continue }
            
            // Parse inline content for the cell
            let content = InlineParser.parseInlineOptimized(part, configuration: configuration)
            let alignment = alignments?[safe: cells.count] ?? .left
            cells.append(MarkdownParser.TableCell(content: content, alignment: alignment))
        }
        
        return cells
    }

    private static func parseTableRow(
        source: String,
        range: Range<String.Index>,
        alignments: [MarkdownParser.TableAlignment]?,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.TableCell] {
        if let cells = parseASCIITableRow(
            source: source,
            range: range,
            alignments: alignments,
            configuration: configuration
        ) {
            return cells
        }

        return parseTableRow(String(source[range]), alignments: alignments, configuration: configuration)
    }
    
    /// Parse table alignment row
    public static func parseTableAlignments(_ line: String) -> [MarkdownParser.TableAlignment] {
        if let alignments = parseASCIITableAlignments(line) {
            return alignments
        }

        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        var alignments: [MarkdownParser.TableAlignment] = []
        alignments.reserveCapacity(parts.count)
        
        for part in parts {
            if part.isEmpty { continue }
            
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            
            // Must contain at least one dash
            guard trimmed.contains("-") else { continue }
            
            // Check for colons indicating alignment
            let startsWithColon = trimmed.first == ":"
            let endsWithColon = trimmed.last == ":"
            
            if startsWithColon && endsWithColon {
                alignments.append(.center)
            } else if endsWithColon {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }
        
        return alignments
    }

    private static func parseTableAlignments(
        source: String,
        range: Range<String.Index>
    ) -> [MarkdownParser.TableAlignment] {
        if let alignments = parseASCIITableAlignments(source: source, range: range) {
            return alignments
        }

        return parseTableAlignments(String(source[range]))
    }

    private static func parseASCIITableRow(
        _ line: String,
        alignments: [MarkdownParser.TableAlignment]?,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.TableCell]? {
        parseASCIITableRow(
            line,
            alignments: alignments,
            configuration: configuration,
            materializeCellRanges: false
        )
    }

    private static func parseASCIITableRow(
        source: String,
        range: Range<String.Index>,
        alignments: [MarkdownParser.TableAlignment]?,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.TableCell]? {
        parseASCIITableRow(
            source: source,
            range: range,
            alignments: alignments,
            configuration: configuration,
            materializeCellRanges: false
        )
    }

    static func parseASCIITableRowByCopyingCellsForTesting(
        _ line: String,
        alignments: [MarkdownParser.TableAlignment]?,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.TableCell]? {
        guard let ranges = asciiTableCellRanges(in: line) else {
            return nil
        }

        var cells: [MarkdownParser.TableCell] = []
        cells.reserveCapacity(ranges.count)

        for (partIndex, range) in ranges.enumerated() {
            let isEmpty = range.lowerBound == range.upperBound
            if partIndex == 0 && isEmpty { continue }
            if partIndex == ranges.count - 1 && isEmpty { continue }

            let content = InlineParser.parseInlineOptimized(String(line[range]), configuration: configuration)
            let alignment = alignments?[safe: cells.count] ?? .left
            cells.append(MarkdownParser.TableCell(content: content, alignment: alignment))
        }

        return cells
    }

    static func parseASCIITableRowByMaterializingRangesForTesting(
        _ line: String,
        alignments: [MarkdownParser.TableAlignment]?,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.TableCell]? {
        parseASCIITableRow(
            line,
            alignments: alignments,
            configuration: configuration,
            materializeCellRanges: true
        )
    }

    static func parseASCIITableRowByParsingPlainCellsForTesting(
        _ line: String,
        alignments: [MarkdownParser.TableAlignment]?,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.TableCell]? {
        parseASCIITableRowInSinglePass(
            source: line,
            range: line.startIndex..<line.endIndex,
            alignments: alignments,
            configuration: configuration,
            usePlainTextCellFastPath: false
        )
    }

    private static func parseASCIITableRow(
        _ line: String,
        alignments: [MarkdownParser.TableAlignment]?,
        configuration: MarkdownConfiguration,
        materializeCellRanges: Bool
    ) -> [MarkdownParser.TableCell]? {
        parseASCIITableRow(
            source: line,
            range: line.startIndex..<line.endIndex,
            alignments: alignments,
            configuration: configuration,
            materializeCellRanges: materializeCellRanges
        )
    }

    private static func parseASCIITableRow(
        source: String,
        range: Range<String.Index>,
        alignments: [MarkdownParser.TableAlignment]?,
        configuration: MarkdownConfiguration,
        materializeCellRanges: Bool
    ) -> [MarkdownParser.TableCell]? {
        if materializeCellRanges {
            return parseASCIITableRowByMaterializingCellRanges(
                source: source,
                range: range,
                alignments: alignments,
                configuration: configuration
            )
        }

        return parseASCIITableRowInSinglePass(
            source: source,
            range: range,
            alignments: alignments,
            configuration: configuration,
            usePlainTextCellFastPath: true
        )
    }

    private static func parseASCIITableRowByMaterializingCellRanges(
        source: String,
        range: Range<String.Index>,
        alignments: [MarkdownParser.TableAlignment]?,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.TableCell]? {
        guard let ranges = asciiTableCellRanges(in: source, range: range) else {
            return nil
        }

        var cells: [MarkdownParser.TableCell] = []
        cells.reserveCapacity(ranges.count)

        for (partIndex, range) in ranges.enumerated() {
            let isEmpty = range.lowerBound == range.upperBound
            if partIndex == 0 && isEmpty { continue }
            if partIndex == ranges.count - 1 && isEmpty { continue }

            let content = InlineParser.parseInlineElements(
                in: source,
                from: range.lowerBound,
                to: range.upperBound,
                configuration: configuration,
                asciiFastPath: true
            )
            let alignment = alignments?[safe: cells.count] ?? .left
            cells.append(MarkdownParser.TableCell(content: content, alignment: alignment))
        }

        return cells
    }

    private static func parseASCIITableRowInSinglePass(
        source: String,
        range: Range<String.Index>,
        alignments: [MarkdownParser.TableAlignment]?,
        configuration: MarkdownConfiguration,
        usePlainTextCellFastPath: Bool
    ) -> [MarkdownParser.TableCell]? {
        guard let utf8Start = range.lowerBound.samePosition(in: source.utf8),
              let utf8End = range.upperBound.samePosition(in: source.utf8) else {
            return nil
        }

        let utf8 = source.utf8
        var cells: [MarkdownParser.TableCell] = []
        cells.reserveCapacity(4)

        var cellStart = utf8Start
        var index = utf8Start
        var partIndex = 0

        while true {
            if index == utf8End || utf8[index] == 0x7C { // |
                let trimmed = trimASCIITableWhitespace(in: utf8, lowerBound: cellStart, upperBound: index)
                guard let lowerBound = String.Index(trimmed.lowerBound, within: source),
                      let upperBound = String.Index(trimmed.upperBound, within: source) else {
                    return nil
                }

                let isEmpty = lowerBound == upperBound
                if !(partIndex == 0 && isEmpty) && !(index == utf8End && isEmpty) {
                    let content: [MarkdownParser.InlineNode]
                    if usePlainTextCellFastPath,
                       let plainText = plainASCIITableCellText(
                           source: source,
                           utf8: utf8,
                           lowerBound: trimmed.lowerBound,
                           upperBound: trimmed.upperBound,
                           configuration: configuration
                       ) {
                        content = plainText.isEmpty ? [] : [.text(plainText)]
                    } else {
                        content = InlineParser.parseInlineElements(
                            in: source,
                            from: lowerBound,
                            to: upperBound,
                            configuration: configuration,
                            asciiFastPath: true
                        )
                    }
                    let alignment = alignments?[safe: cells.count] ?? .left
                    cells.append(MarkdownParser.TableCell(content: content, alignment: alignment))
                }

                partIndex += 1
                if index == utf8End { break }
                cellStart = utf8.index(after: index)
            } else if utf8[index] >= 0x80 {
                return nil
            }

            index = utf8.index(after: index)
        }

        return cells
    }

    private static func plainASCIITableCellText(
        source: String,
        utf8: String.UTF8View,
        lowerBound: String.UTF8View.Index,
        upperBound: String.UTF8View.Index,
        configuration: MarkdownConfiguration
    ) -> String? {
        guard configuration.markdownExtensions.isEmpty else {
            return nil
        }

        let checksIssueReferences = configuration.enableIssueReferences
        let checksRepositoryReferences = configuration.enableRepositoryReferences
        let checksEmojiShortcodes = configuration.enableEmojiShortcodes
        let checksMentions = configuration.enableMentions
        let checksCommitSHAs = configuration.enableCommitSHAs
        let checksAutolinks = configuration.enableAutolinks

        var index = lowerBound
        while index < upperBound {
            let byte = utf8[index]
            switch byte {
            case 0x21, // !
                 0x2A, // *
                 0x3C, // <
                 0x5B, // [
                 0x5C, // backslash
                 0x5F, // _
                 0x60, // `
                 0x7E: // ~
                return nil
            case 0x23 where checksIssueReferences: // #
                return nil
            case 0x2F where checksRepositoryReferences: // /
                return nil
            case 0x3A where checksEmojiShortcodes: // :
                return nil
            case 0x40 where checksMentions: // @
                return nil
            case 0x66, // f
                 0x68, // h
                 0x6D, // m
                 0x77: // w
                if checksAutolinks, containsPotentialBareAutolink(in: utf8, at: index, end: upperBound) {
                    return nil
                }
            default:
                break
            }

            if checksCommitSHAs,
               containsPotentialCommitSHA(in: utf8, at: index, start: lowerBound, end: upperBound) {
                return nil
            }

            index = utf8.index(after: index)
        }

        guard let stringLowerBound = String.Index(lowerBound, within: source),
              let stringUpperBound = String.Index(upperBound, within: source) else {
            return nil
        }
        return String(source[stringLowerBound..<stringUpperBound])
    }

    private static func containsPotentialCommitSHA(
        in utf8: String.UTF8View,
        at index: String.UTF8View.Index,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Bool {
        guard index < end, ParsingHelpers.isASCIIHex(utf8[index]) else {
            return false
        }

        if index > start {
            let previous = utf8[utf8.index(before: index)]
            if ParsingHelpers.isASCIIAlnum(previous) {
                return false
            }
        }

        var scan = index
        var count = 0
        while scan < end, count < 40, ParsingHelpers.isASCIIHex(utf8[scan]) {
            count += 1
            scan = utf8.index(after: scan)
        }

        guard count >= 7 else {
            return false
        }

        return scan >= end || !ParsingHelpers.isASCIIAlnum(utf8[scan])
    }

    private static func containsPotentialBareAutolink(
        in utf8: String.UTF8View,
        at index: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Bool {
        switch utf8[index] {
        case 0x66: // f
            return hasASCIIPrefix(ftpPrefix, in: utf8, at: index, end: end)
        case 0x68: // h
            return hasASCIIPrefix(httpPrefix, in: utf8, at: index, end: end) ||
                hasASCIIPrefix(httpsPrefix, in: utf8, at: index, end: end)
        case 0x6D: // m
            return hasASCIIPrefix(mailtoPrefix, in: utf8, at: index, end: end)
        case 0x77: // w
            return hasASCIIPrefix(wwwPrefix, in: utf8, at: index, end: end)
        default:
            return false
        }
    }

    private static func hasASCIIPrefix(
        _ prefix: [UInt8],
        in utf8: String.UTF8View,
        at index: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Bool {
        var scan = index
        for byte in prefix {
            guard scan < end, utf8[scan] == byte else {
                return false
            }
            scan = utf8.index(after: scan)
        }
        return true
    }

    private static func parseASCIITableAlignments(_ line: String) -> [MarkdownParser.TableAlignment]? {
        parseASCIITableAlignmentsInSinglePass(source: line, range: line.startIndex..<line.endIndex)
    }

    static func parseASCIITableAlignmentsByCharacterScanningForTesting(
        _ line: String
    ) -> [MarkdownParser.TableAlignment]? {
        guard let ranges = asciiTableCellRanges(in: line) else {
            return nil
        }

        return parseASCIITableAlignments(line, ranges: ranges, useUTF8ByteScan: false)
    }

    static func parseASCIITableAlignmentsByMaterializingRangesForTesting(
        _ line: String
    ) -> [MarkdownParser.TableAlignment]? {
        guard let ranges = asciiTableCellRanges(in: line) else {
            return nil
        }

        return parseASCIITableAlignmentsWithBytes(in: line.utf8, ranges: ranges)
    }

    private static func parseASCIITableAlignments(
        _ line: String,
        ranges: [Range<String.Index>],
        useUTF8ByteScan: Bool
    ) -> [MarkdownParser.TableAlignment] {
        if useUTF8ByteScan {
            return parseASCIITableAlignmentsWithBytes(in: line.utf8, ranges: ranges)
        }

        var alignments: [MarkdownParser.TableAlignment] = []
        alignments.reserveCapacity(ranges.count)

        for range in ranges {
            if range.lowerBound == range.upperBound { continue }

            var containsDash = false
            var index = range.lowerBound
            while index < range.upperBound {
                if line[index] == "-" {
                    containsDash = true
                    break
                }
                index = line.index(after: index)
            }

            guard containsDash else { continue }

            let startsWithColon = line[range.lowerBound] == ":"
            let beforeEnd = line.index(before: range.upperBound)
            let endsWithColon = line[beforeEnd] == ":"

            if startsWithColon && endsWithColon {
                alignments.append(.center)
            } else if endsWithColon {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }

        return alignments
    }

    private static func parseASCIITableAlignments(
        source: String,
        range: Range<String.Index>
    ) -> [MarkdownParser.TableAlignment]? {
        parseASCIITableAlignmentsInSinglePass(source: source, range: range)
    }

    private static func parseASCIITableAlignments(
        source: String,
        ranges: [Range<String.Index>],
        useUTF8ByteScan: Bool
    ) -> [MarkdownParser.TableAlignment] {
        if useUTF8ByteScan {
            return parseASCIITableAlignmentsWithBytes(in: source.utf8, ranges: ranges)
        }

        var alignments: [MarkdownParser.TableAlignment] = []
        alignments.reserveCapacity(ranges.count)

        for range in ranges {
            if range.lowerBound == range.upperBound { continue }

            var containsDash = false
            var index = range.lowerBound
            while index < range.upperBound {
                if source[index] == "-" {
                    containsDash = true
                    break
                }
                index = source.index(after: index)
            }

            guard containsDash else { continue }

            let startsWithColon = source[range.lowerBound] == ":"
            let beforeEnd = source.index(before: range.upperBound)
            let endsWithColon = source[beforeEnd] == ":"

            if startsWithColon && endsWithColon {
                alignments.append(.center)
            } else if endsWithColon {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }

        return alignments
    }

    private static func parseASCIITableAlignmentsWithBytes(
        in utf8: String.UTF8View,
        ranges: [Range<String.Index>]
    ) -> [MarkdownParser.TableAlignment] {
        var alignments: [MarkdownParser.TableAlignment] = []
        alignments.reserveCapacity(ranges.count)

        for range in ranges {
            guard range.lowerBound < range.upperBound else { continue }

            var containsDash = false
            var index = range.lowerBound
            while index < range.upperBound {
                if utf8[index] == 0x2D { // -
                    containsDash = true
                    break
                }
                index = utf8.index(after: index)
            }

            guard containsDash else { continue }

            let startsWithColon = utf8[range.lowerBound] == 0x3A // :
            let beforeEnd = utf8.index(before: range.upperBound)
            let endsWithColon = utf8[beforeEnd] == 0x3A // :

            if startsWithColon && endsWithColon {
                alignments.append(.center)
            } else if endsWithColon {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }

        return alignments
    }

    private static func parseASCIITableAlignmentsInSinglePass(
        source: String,
        range: Range<String.Index>
    ) -> [MarkdownParser.TableAlignment]? {
        guard let utf8Start = range.lowerBound.samePosition(in: source.utf8),
              let utf8End = range.upperBound.samePosition(in: source.utf8) else {
            return nil
        }

        let utf8 = source.utf8
        var alignments: [MarkdownParser.TableAlignment] = []
        alignments.reserveCapacity(4)

        var cellStart = utf8Start
        var index = utf8Start

        while true {
            if index == utf8End || utf8[index] == 0x7C { // |
                appendASCIITableAlignment(
                    in: utf8,
                    lowerBound: cellStart,
                    upperBound: index,
                    into: &alignments
                )

                if index == utf8End { break }
                cellStart = utf8.index(after: index)
            } else if utf8[index] >= 0x80 {
                return nil
            }

            index = utf8.index(after: index)
        }

        return alignments
    }

    private static func appendASCIITableAlignment(
        in utf8: String.UTF8View,
        lowerBound: String.UTF8View.Index,
        upperBound: String.UTF8View.Index,
        into alignments: inout [MarkdownParser.TableAlignment]
    ) {
        let trimmed = trimASCIITableWhitespace(in: utf8, lowerBound: lowerBound, upperBound: upperBound)
        guard trimmed.lowerBound < trimmed.upperBound else {
            return
        }

        var containsDash = false
        var index = trimmed.lowerBound
        while index < trimmed.upperBound {
            if utf8[index] == 0x2D { // -
                containsDash = true
                break
            }
            index = utf8.index(after: index)
        }

        guard containsDash else {
            return
        }

        let startsWithColon = utf8[trimmed.lowerBound] == 0x3A // :
        let beforeEnd = utf8.index(before: trimmed.upperBound)
        let endsWithColon = utf8[beforeEnd] == 0x3A // :

        if startsWithColon && endsWithColon {
            alignments.append(.center)
        } else if endsWithColon {
            alignments.append(.right)
        } else {
            alignments.append(.left)
        }
    }

    private static func asciiTableCellRanges(in line: String) -> [Range<String.Index>]? {
        guard let utf8Start = line.startIndex.samePosition(in: line.utf8),
              let utf8End = line.endIndex.samePosition(in: line.utf8) else {
            return nil
        }

        let utf8 = line.utf8
        var ranges: [Range<String.Index>] = []
        ranges.reserveCapacity(4)

        var cellStart = utf8Start
        var index = utf8Start

        while true {
            if index == utf8End || utf8[index] == 0x7C { // |
                let trimmed = trimASCIITableWhitespace(in: utf8, lowerBound: cellStart, upperBound: index)
                guard let lowerBound = String.Index(trimmed.lowerBound, within: line),
                      let upperBound = String.Index(trimmed.upperBound, within: line) else {
                    return nil
                }
                ranges.append(lowerBound..<upperBound)

                if index == utf8End { break }
                cellStart = utf8.index(after: index)
            } else if utf8[index] >= 0x80 {
                return nil
            }

            index = utf8.index(after: index)
        }

        return ranges
    }

    private static func asciiTableCellRanges(
        in source: String,
        range: Range<String.Index>
    ) -> [Range<String.Index>]? {
        guard let utf8Start = range.lowerBound.samePosition(in: source.utf8),
              let utf8End = range.upperBound.samePosition(in: source.utf8) else {
            return nil
        }

        let utf8 = source.utf8
        var ranges: [Range<String.Index>] = []
        ranges.reserveCapacity(4)

        var cellStart = utf8Start
        var index = utf8Start

        while true {
            if index == utf8End || utf8[index] == 0x7C { // |
                let trimmed = trimASCIITableWhitespace(in: utf8, lowerBound: cellStart, upperBound: index)
                guard let lowerBound = String.Index(trimmed.lowerBound, within: source),
                      let upperBound = String.Index(trimmed.upperBound, within: source) else {
                    return nil
                }
                ranges.append(lowerBound..<upperBound)

                if index == utf8End { break }
                cellStart = utf8.index(after: index)
            } else if utf8[index] >= 0x80 {
                return nil
            }

            index = utf8.index(after: index)
        }

        return ranges
    }

    private static func trimASCIITableWhitespace(
        in utf8: String.UTF8View,
        lowerBound: String.UTF8View.Index,
        upperBound: String.UTF8View.Index
    ) -> Range<String.UTF8View.Index> {
        var lowerBound = lowerBound
        var upperBound = upperBound

        while lowerBound < upperBound && isASCIITableWhitespace(utf8[lowerBound]) {
            lowerBound = utf8.index(after: lowerBound)
        }

        while lowerBound < upperBound {
            let previous = utf8.index(before: upperBound)
            guard isASCIITableWhitespace(utf8[previous]) else {
                break
            }
            upperBound = previous
        }

        return lowerBound..<upperBound
    }

    @inline(__always)
    private static func isASCIITableWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09
    }
    
    // MARK: - Autolinks
    
    /// Detect and parse autolinks in text
    public static func parseAutolink(text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        // Standard URLs
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || 
           trimmed.hasPrefix("ftp://") || trimmed.hasPrefix("mailto:") {
            return URL(string: trimmed)
        }
        
        // www URLs
        if trimmed.hasPrefix("www.") {
            return URL(string: "http://\(trimmed)")
        }
        
        // Email addresses
        if isValidEmail(trimmed) {
            return URL(string: "mailto:\(trimmed)")
        }
        
        return nil
    }
    
    /// Check if string is a valid email address
    public static func isValidEmail(_ text: String) -> Bool {
        // Simple email validation
        let parts = text.split(separator: "@")
        guard parts.count == 2 else { return false }
        
        let localPart = parts[0]
        let domainPart = parts[1]
        
        // Basic checks
        guard !localPart.isEmpty && !domainPart.isEmpty else { return false }
        guard domainPart.contains(".") else { return false }
        
        // Check for valid characters
        let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_+"))
        let textChars = CharacterSet(charactersIn: text)
        
        return validChars.isSuperset(of: textChars.subtracting(CharacterSet(charactersIn: "@")))
    }
    
    // MARK: - GitHub-Specific References
    
    /// Parse GitHub mention (@username)
    public static func parseMention(_ text: String) -> String? {
        guard text.hasPrefix("@") else { return nil }
        
        let username = String(text.dropFirst())
        
        // Username validation (GitHub rules)
        guard !username.isEmpty else { return nil }
        guard username.count <= 39 else { return nil }
        
        // Must contain only alphanumeric, dash, or underscore
        for char in username {
            if !char.isLetter && !char.isNumber && char != "-" && char != "_" {
                return nil
            }
        }
        
        // Cannot start or end with dash
        if username.first == "-" || username.last == "-" {
            return nil
        }
        
        // Cannot have consecutive dashes
        if username.contains("--") {
            return nil
        }
        
        return username
    }
    
    /// Parse GitHub issue reference (#123)
    public static func parseIssueReference(_ text: String) -> Int? {
        guard text.hasPrefix("#") else { return nil }
        
        let numberStr = String(text.dropFirst())
        return Int(numberStr)
    }
    
    /// Parse GitHub commit SHA
    public static func parseCommitSHA(_ text: String) -> String? {
        // Must be 7-40 hex characters
        guard text.count >= 7 && text.count <= 40 else { return nil }
        
        // Check all characters are hex
        for char in text {
            if !ParsingHelpers.isHexChar(char) {
                return nil
            }
        }
        
        return text
    }
    
    /// Parse GitHub repository reference (owner/repo)
    public static func parseRepositoryReference(_ text: String) -> (owner: String, repo: String)? {
        let parts = text.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        
        let owner = String(parts[0])
        let repo = String(parts[1])
        
        // Validate owner
        guard isValidGitHubUsername(owner) else { return nil }
        
        // Validate repo name
        guard isValidGitHubRepoName(repo) else { return nil }
        
        return (owner, repo)
    }
    
    /// Parse GitHub pull request reference (owner/repo#123)
    public static func parsePullRequestReference(_ text: String) -> (owner: String, repo: String, number: Int)? {
        let parts = text.split(separator: "#", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        
        guard let repoRef = parseRepositoryReference(String(parts[0])) else { return nil }
        guard let number = Int(parts[1]) else { return nil }
        
        return (repoRef.owner, repoRef.repo, number)
    }
    
    // MARK: - Strikethrough
    
    /// Parse strikethrough text (~~text~~)
    public static func parseStrikethrough(_ text: String) -> String? {
        guard text.hasPrefix("~~") && text.hasSuffix("~~") else { return nil }
        guard text.count > 4 else { return nil }
        
        let content = String(text.dropFirst(2).dropLast(2))
        return content.isEmpty ? nil : content
    }
    
    // MARK: - Helper Methods
    
    private static func isValidGitHubUsername(_ username: String) -> Bool {
        guard !username.isEmpty && username.count <= 39 else { return false }
        
        for char in username {
            if !char.isLetter && !char.isNumber && char != "-" && char != "_" {
                return false
            }
        }
        
        // Cannot start or end with dash
        if username.first == "-" || username.last == "-" {
            return false
        }
        
        // Cannot have consecutive dashes
        if username.contains("--") {
            return false
        }
        
        return true
    }
    
    private static func isValidGitHubRepoName(_ repo: String) -> Bool {
        guard !repo.isEmpty && repo.count <= 100 else { return false }
        
        for char in repo {
            if !char.isLetter && !char.isNumber && char != "-" && char != "_" && char != "." {
                return false
            }
        }
        
        // Cannot be just "." or ".."
        if repo == "." || repo == ".." {
            return false
        }
        
        return true
    }
}

// MARK: - Array Extension

private extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}
