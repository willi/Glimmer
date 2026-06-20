import Foundation

/// Handles parsing of inline markdown elements
public struct InlineParser {

    private static let httpPrefix: [UInt8] = [0x68, 0x74, 0x74, 0x70, 0x3A, 0x2F, 0x2F]
    private static let httpsPrefix: [UInt8] = [0x68, 0x74, 0x74, 0x70, 0x73, 0x3A, 0x2F, 0x2F]
    private static let ftpPrefix: [UInt8] = [0x66, 0x74, 0x70, 0x3A, 0x2F, 0x2F]
    private static let mailtoPrefix: [UInt8] = [0x6D, 0x61, 0x69, 0x6C, 0x74, 0x6F, 0x3A]
    private static let wwwPrefix: [UInt8] = [0x77, 0x77, 0x77, 0x2E]

    private struct ASCIIEmphasisDelimiterRun {
        let start: String.Index
        let end: String.Index
        let length: Int
        let consumedBytes: Int
        let lineBreaks: Int
        let bytesAfterLastLineBreak: Int
    }

    private struct ASCIITextRunOptions {
        let enableMentions: Bool
        let enableIssueReferences: Bool
        let enableEmojiShortcodes: Bool
        let enableRepositoryReferences: Bool
        let enableAutolinks: Bool
        let enableCommitSHAs: Bool

        var hasScanningGitHubFeatures: Bool {
            enableRepositoryReferences || enableAutolinks || enableCommitSHAs
        }
    }

    private enum ASCIIInlineCandidate {
        enum Kind: Equatable {
            case bareAutolink
            case repositoryReference
            case commitSHA
        }

        struct RepositoryReference {
            let ownerRange: Range<String.Index>
            let repoRange: Range<String.Index>
            let afterRepo: String.Index
        }

        struct CommitSHA {
            let range: Range<String.Index>
        }

        case bareAutolink(start: String.Index)
        case repositoryReference(RepositoryReference)
        case commitSHA(CommitSHA)

        var start: String.Index {
            switch self {
            case .bareAutolink(let start):
                return start
            case .repositoryReference(let reference):
                return reference.ownerRange.lowerBound
            case .commitSHA(let sha):
                return sha.range.lowerBound
            }
        }

        var kind: Kind {
            switch self {
            case .bareAutolink:
                return .bareAutolink
            case .repositoryReference:
                return .repositoryReference
            case .commitSHA:
                return .commitSHA
            }
        }
    }

    // MARK: - Main Inline Parsing

    public static func parseInlineOptimized(_ text: String, configuration: MarkdownConfiguration = .default) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: text)
        return parseInlineElements(&state, configuration: configuration)
    }
    // Fast-path is now per-state using ParserState.asciiFastPath

    static func parseInlineElements(_ state: inout ParserState, configuration: MarkdownConfiguration) -> [MarkdownParser.InlineNode] {
        parseInlineElements(&state, configuration: configuration, prescanASCIIPlainText: false)
    }

    static func parseInlineElementsByPrescanningPlainTextForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.InlineNode] {
        parseInlineElements(
            &state,
            configuration: configuration,
            prescanASCIIPlainText: true,
            useASCIICandidateDispatch: true
        )
    }

    static func parseInlineElementsByReprobingASCIICandidatesForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.InlineNode] {
        parseInlineElements(
            &state,
            configuration: configuration,
            prescanASCIIPlainText: false,
            useASCIICandidateDispatch: false
        )
    }

    static func parseInlineElementsByCopyingLiteralRunsForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.InlineNode] {
        parseInlineElements(
            &state,
            configuration: configuration,
            prescanASCIIPlainText: false,
            useASCIICandidateDispatch: true,
            useDeferredLiteralRuns: false
        )
    }

    private static func parseInlineElements(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        prescanASCIIPlainText: Bool,
        useASCIICandidateDispatch: Bool = true,
        useDeferredLiteralRuns: Bool = true
    ) -> [MarkdownParser.InlineNode] {
        var inlines: [MarkdownParser.InlineNode] = []
        var iterationCount = 0
        var pendingASCIICandidate: ASCIIInlineCandidate?
        let maxIterations = configuration.maxInlineIterations
        let hasMarkdownExtensions = !configuration.markdownExtensions.isEmpty
        let enableFootnotes = configuration.enableFootnotes
        let enableMentions = configuration.enableMentions
        let enableIssueReferences = configuration.enableIssueReferences
        let enableEmojiShortcodes = configuration.enableEmojiShortcodes
        let enableRepositoryReferences = configuration.enableRepositoryReferences
        let enableAutolinks = configuration.enableAutolinks
        let enableCommitSHAs = configuration.enableCommitSHAs
        let hasScanningGitHubFeatures = enableRepositoryReferences || enableAutolinks || enableCommitSHAs

        // Decide ASCII fast-path once per state if not already set.
        state.enableASCIIFastPathIfPossible()

        if (prescanASCIIPlainText || !state.asciiFastPath),
           !hasScanningGitHubFeatures,
           consumeAsPlainTextIfPossible(&state, configuration: configuration, into: &inlines) {
            return inlines
        }

        while !state.isAtEnd {
            iterationCount += 1
            if iterationCount > maxIterations {
                // Add remaining text as plain text and break
                state.flushFragmentBuffer(&inlines)
                let remaining = state.remainingSubstring()
                if !remaining.isEmpty { inlines.append(.text(remaining)) }
                break
            }

            let asciiCandidate: ASCIIInlineCandidate?
            if useASCIICandidateDispatch,
               let pendingCandidate = pendingASCIICandidate,
               pendingCandidate.start == state.currentIndex {
                asciiCandidate = pendingCandidate
                pendingASCIICandidate = nil
            } else {
                if useASCIICandidateDispatch {
                    pendingASCIICandidate = nil
                }
                asciiCandidate = nil

                if !hasMarkdownExtensions {
                    var scannedCandidate: ASCIIInlineCandidate?
                    if consumeASCIITextRunIfPossible(
                        &state,
                        options: ASCIITextRunOptions(
                            enableMentions: enableMentions,
                            enableIssueReferences: enableIssueReferences,
                            enableEmojiShortcodes: enableEmojiShortcodes,
                            enableRepositoryReferences: enableRepositoryReferences,
                            enableAutolinks: enableAutolinks,
                            enableCommitSHAs: enableCommitSHAs
                        ),
                        candidate: &scannedCandidate,
                        useDeferredLiteralRuns: useDeferredLiteralRuns
                    ) {
                        if useASCIICandidateDispatch {
                            pendingASCIICandidate = scannedCandidate
                        }
                        continue
                    }
                }
            }
            let asciiCandidateKind = asciiCandidate?.kind

            let mark = state.mark()
            guard let ch = state.current() else { break }

            if hasMarkdownExtensions,
               let extensionInline = parseExtensionInline(&state, configuration: configuration) {
                state.flushFragmentBuffer(&inlines)
                inlines.append(extensionInline)
                continue
            }

            switch ch {
            case "\\":
                state.advance()
                if let escaped = state.current() {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(.text(String(escaped)))
                    state.advance()
                } else {
                    state.appendToFragmentBuffer("\\")
                }

            case "`":
                if let code = parseInlineCode(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(code)
                } else {
                    state.appendToFragmentBuffer("`")
                    state.advance()
                }

            case "*", "_":
                if let emphasis = parseEmphasis(&state, delimiter: ch, configuration: configuration) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(emphasis)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "~":
                if let strikethrough = parseStrikethrough(&state, configuration: configuration) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(strikethrough)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "[":
                if enableFootnotes, let next = state.peek(1), next == "^" {
                    if let footnote = parseFootnoteReference(&state) {
                        state.flushFragmentBuffer(&inlines)
                        inlines.append(footnote)
                    } else {
                        state.appendToFragmentBuffer(ch)
                        state.advance()
                    }
                } else if let link = parseLink(&state, configuration: configuration) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(link)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "!":
                if let next = state.peek(1), next == "[" {
                    if let image = parseImage(&state, configuration: configuration) {
                        state.flushFragmentBuffer(&inlines)
                        inlines.append(image)
                    } else {
                        state.appendToFragmentBuffer(ch)
                        state.advance()
                    }
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "<":
                if let autolink = parseUnifiedAutolink(&state, angleBracketMode: true) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(autolink)
                } else if let tag = parseHTMLTag(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(tag)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "@":
                if enableMentions, let mention = parseMention(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(mention)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "#":
                if enableIssueReferences, let issue = parseIssueReference(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(issue)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case ":":
                if enableEmojiShortcodes, let emoji = parseEmojiShortcode(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(emoji)
                } else {

                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "h", "m", "f", "w":
                if enableAutolinks,
                   (
                    asciiCandidateKind == .bareAutolink ||
                    (asciiCandidateKind == nil && shouldAttemptBareAutolink(state))
                   ),
                   let autolink = parseUnifiedAutolink(&state, angleBracketMode: false) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(autolink)
                } else if enableRepositoryReferences,
                          let repo = parseRepositoryReference(
                            &state,
                            candidate: asciiCandidate,
                            shouldProbe: asciiCandidateKind != .repositoryReference
                          ) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(repo)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            default:
                if enableRepositoryReferences,
                   let repo = parseRepositoryReference(
                    &state,
                    candidate: asciiCandidate,
                    shouldProbe: asciiCandidateKind != .repositoryReference
                   ) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(repo)
                } else if enableCommitSHAs,
                          let sha = parseCommitSHA(
                            &state,
                            candidate: asciiCandidate,
                            shouldProbe: asciiCandidateKind != .commitSHA
                          ) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(sha)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }
            }

            // Safety check: ensure we made progress
            if state.currentIndex == mark.index {
                // Fallback consume one char
                if let c = state.current() { state.appendToFragmentBuffer(c); state.advance() }
            }
        }

        state.flushFragmentBuffer(&inlines)
        return inlines
    }

    static func parseInlineElements(
        in text: String,
        from start: String.Index,
        to end: String.Index,
        configuration: MarkdownConfiguration,
        asciiFastPath: Bool? = nil,
        line: Int = 1,
        column: Int = 1
    ) -> [MarkdownParser.InlineNode] {
        var innerState = ParserState(
            text: text,
            currentIndex: start,
            endIndex: end,
            line: line,
            column: column,
            asciiFastPath: asciiFastPath
        )
        return parseInlineElements(&innerState, configuration: configuration)
    }

    private static func parseInlineElements(
        in state: ParserState,
        from start: String.Index,
        to end: String.Index,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.InlineNode] {
        return parseInlineElements(
            in: state.text,
            from: start,
            to: end,
            configuration: configuration,
            asciiFastPath: state.asciiFastPath ? true : nil,
            line: state.line,
            column: state.column
        )
    }

    private static func consumeAsPlainTextIfPossible(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        into inlines: inout [MarkdownParser.InlineNode]
    ) -> Bool {
        guard configuration.markdownExtensions.isEmpty,
              !containsActiveInlineMarker(state, configuration: configuration) else {
            return false
        }

        let remaining = state.remainingSubstring()
        if !remaining.isEmpty {
            inlines.append(.text(remaining))
        }
        state.finish()
        return true
    }

    private static func consumeASCIITextRunIfPossible(
        _ state: inout ParserState,
        options: ASCIITextRunOptions,
        candidate: inout ASCIIInlineCandidate?,
        useDeferredLiteralRuns: Bool
    ) -> Bool {
        candidate = nil

        if options.hasScanningGitHubFeatures {
            return consumeASCIITextRunByValidatingCandidates(
                &state,
                options: options,
                candidate: &candidate,
                useDeferredLiteralRuns: useDeferredLiteralRuns
            )
        }

        return consumeSimpleASCIITextRun(
            &state,
            options: options,
            useDeferredLiteralRuns: useDeferredLiteralRuns
        )
    }

    static func consumeSimpleASCIITextRunForTesting(
        _ state: inout ParserState,
        enableMentions: Bool,
        enableIssueReferences: Bool,
        enableEmojiShortcodes: Bool
    ) -> Bool {
        consumeSimpleASCIITextRun(
            &state,
            options: ASCIITextRunOptions(
                enableMentions: enableMentions,
                enableIssueReferences: enableIssueReferences,
                enableEmojiShortcodes: enableEmojiShortcodes,
                enableRepositoryReferences: false,
                enableAutolinks: false,
                enableCommitSHAs: false
            ),
            useDeferredLiteralRuns: true
        )
    }

    static func consumeCandidateValidatedASCIITextRunForTesting(
        _ state: inout ParserState,
        enableMentions: Bool,
        enableIssueReferences: Bool,
        enableEmojiShortcodes: Bool
    ) -> Bool {
        var unusedCandidate: ASCIIInlineCandidate?
        return consumeASCIITextRunByValidatingCandidates(
            &state,
            options: ASCIITextRunOptions(
                enableMentions: enableMentions,
                enableIssueReferences: enableIssueReferences,
                enableEmojiShortcodes: enableEmojiShortcodes,
                enableRepositoryReferences: false,
                enableAutolinks: false,
                enableCommitSHAs: false
            ),
            candidate: &unusedCandidate,
            useDeferredLiteralRuns: true
        )
    }

    private static func consumeSimpleASCIITextRun(
        _ state: inout ParserState,
        options: ASCIITextRunOptions,
        useDeferredLiteralRuns: Bool
    ) -> Bool {
        guard state.asciiFastPath else {
            return false
        }

        let utf8 = state.text.utf8
        let start = state.currentIndex
        let end = state.endIndex
        guard start < end else {
            return false
        }

        guard !isASCIIInlineDispatchByte(
            utf8[start],
            enableMentions: options.enableMentions,
            enableIssueReferences: options.enableIssueReferences,
            enableEmojiShortcodes: options.enableEmojiShortcodes
        ) else {
            return false
        }

        var scan = utf8.index(after: start)
        while scan < end {
            if isASCIIInlineDispatchByte(
                utf8[scan],
                enableMentions: options.enableMentions,
                enableIssueReferences: options.enableIssueReferences,
                enableEmojiShortcodes: options.enableEmojiShortcodes
            ) {
                break
            }

            scan = utf8.index(after: scan)
        }

        appendLiteralRunToFragmentBuffer(
            &state,
            upTo: scan,
            useDeferredLiteralRuns: useDeferredLiteralRuns
        )
        return true
    }

    private static func consumeASCIITextRunByValidatingCandidates(
        _ state: inout ParserState,
        options: ASCIITextRunOptions,
        candidate: inout ASCIIInlineCandidate?,
        useDeferredLiteralRuns: Bool
    ) -> Bool {
        guard state.asciiFastPath else {
            return false
        }

        let utf8 = state.text.utf8
        let start = state.currentIndex
        let end = state.endIndex
        guard start < end else {
            return false
        }

        if validatedASCIIInlineCandidate(
            in: utf8,
            at: start,
            textStart: utf8.startIndex,
            end: end,
            enableRepositoryReferences: options.enableRepositoryReferences,
            enableAutolinks: options.enableAutolinks,
            enableCommitSHAs: options.enableCommitSHAs
        ) != nil {
            return false
        }

        guard !isASCIIInlineDispatchByte(
            utf8[start],
            enableMentions: options.enableMentions,
            enableIssueReferences: options.enableIssueReferences,
            enableEmojiShortcodes: options.enableEmojiShortcodes
        ) else {
            return false
        }

        var scan = utf8.index(after: start)
        while scan < end {
            if let foundCandidate = validatedASCIIInlineCandidate(
                in: utf8,
                at: scan,
                textStart: utf8.startIndex,
                end: end,
                enableRepositoryReferences: options.enableRepositoryReferences,
                enableAutolinks: options.enableAutolinks,
                enableCommitSHAs: options.enableCommitSHAs
            ) {
                let candidateStart = foundCandidate.start
                guard candidateStart > start else {
                    return false
                }

                candidate = foundCandidate
                appendLiteralRunToFragmentBuffer(
                    &state,
                    upTo: candidateStart,
                    useDeferredLiteralRuns: useDeferredLiteralRuns
                )
                return true
            }

            if isASCIIInlineDispatchByte(
                utf8[scan],
                enableMentions: options.enableMentions,
                enableIssueReferences: options.enableIssueReferences,
                enableEmojiShortcodes: options.enableEmojiShortcodes
            ) {
                break
            }

            scan = utf8.index(after: scan)
        }

        appendLiteralRunToFragmentBuffer(
            &state,
            upTo: scan,
            useDeferredLiteralRuns: useDeferredLiteralRuns
        )
        return true
    }

    @inline(__always)
    private static func appendLiteralRunToFragmentBuffer(
        _ state: inout ParserState,
        upTo target: String.Index,
        useDeferredLiteralRuns: Bool
    ) {
        if useDeferredLiteralRuns {
            state.appendLiteralRunToFragmentBuffer(upTo: target)
        } else {
            state.appendLiteralRunToFragmentBufferByCopyingForTesting(upTo: target)
        }
    }

    private static func validatedASCIIInlineCandidate(
        in utf8: String.UTF8View,
        at index: String.UTF8View.Index,
        textStart: String.UTF8View.Index,
        end: String.UTF8View.Index,
        enableRepositoryReferences: Bool,
        enableAutolinks: Bool,
        enableCommitSHAs: Bool
    ) -> ASCIIInlineCandidate? {
        let byte = utf8[index]

        if enableAutolinks {
            switch byte {
            case 0x66, // f
                 0x68, // h
                 0x6D, // m
                 0x77: // w
                if containsPotentialBareAutolink(in: utf8, at: index, end: end) {
                    return .bareAutolink(start: index)
                }
            default:
                break
            }
        }

        if enableCommitSHAs,
           ParsingHelpers.isASCIIHex(byte),
           let range = commitSHARangeStartingWithHex(in: utf8, at: index, start: textStart, end: end) {
            return .commitSHA(.init(range: range))
        }

        if enableRepositoryReferences,
           byte == 0x2F, // /
           let reference = repositoryReferenceCandidateBeforeSlash(in: utf8, slash: index, start: textStart, end: end) {
            return .repositoryReference(reference)
        }

        return nil
    }

    @inline(__always)
    private static func isASCIIInlineDispatchByte(
        _ byte: UInt8,
        enableMentions: Bool,
        enableIssueReferences: Bool,
        enableEmojiShortcodes: Bool
    ) -> Bool {
        switch byte {
        case 0x0A, // \n
             0x0D, // \r
             0x21, // !
             0x2A, // *
             0x3C, // <
             0x5B, // [
             0x5C, // backslash
             0x5F, // _
             0x60, // `
             0x7E: // ~
            return true
        case 0x23 where enableIssueReferences: // #
            return true
        case 0x3A where enableEmojiShortcodes: // :
            return true
        case 0x40 where enableMentions: // @
            return true
        default:
            return false
        }
    }

    private static func containsActiveInlineMarker(
        _ state: ParserState,
        configuration: MarkdownConfiguration
    ) -> Bool {
        guard state.currentIndex < state.endIndex else { return false }

        return containsActiveInlineMarkerByUTF8Scanning(state, configuration: configuration)
    }

    static func containsActiveInlineMarkerForTesting(
        _ state: ParserState,
        configuration: MarkdownConfiguration
    ) -> Bool {
        containsActiveInlineMarker(state, configuration: configuration)
    }

    static func containsActiveInlineMarkerByCharacterScanningForTesting(
        _ state: ParserState,
        configuration: MarkdownConfiguration
    ) -> Bool {
        var index = state.currentIndex
        while index < state.endIndex {
            let ch = state.text[index]
            switch ch {
            case "\\", "`", "*", "_", "~", "[", "!", "<":
                return true
            case "#" where configuration.enableIssueReferences:
                return true
            case "/" where configuration.enableRepositoryReferences:
                return true
            case ":" where configuration.enableEmojiShortcodes:
                return true
            case "@" where configuration.enableMentions:
                return true
            default:
                break
            }
            index = state.text.index(after: index)
        }

        if configuration.enableCommitSHAs, containsPotentialCommitSHA(state) {
            return true
        }

        if configuration.enableAutolinks, containsPotentialBareAutolink(state) {
            return true
        }

        return false
    }

    private static func containsActiveInlineMarkerByUTF8Scanning(
        _ state: ParserState,
        configuration: MarkdownConfiguration
    ) -> Bool {
        let utf8 = state.text.utf8
        let start = state.currentIndex
        let end = state.endIndex
        let checksIssueReferences = configuration.enableIssueReferences
        let checksRepositoryReferences = configuration.enableRepositoryReferences
        let checksEmojiShortcodes = configuration.enableEmojiShortcodes
        let checksMentions = configuration.enableMentions
        let checksCommitSHAs = configuration.enableCommitSHAs
        let checksAutolinks = configuration.enableAutolinks
        var index = start

        if checksCommitSHAs || checksAutolinks {
            while index < end {
                let byte = utf8[index]
                if isActiveASCIIInlineMarker(
                    byte,
                    checksIssueReferences: checksIssueReferences,
                    checksRepositoryReferences: checksRepositoryReferences,
                    checksEmojiShortcodes: checksEmojiShortcodes,
                    checksMentions: checksMentions
                ) {
                    return true
                }

                if checksAutolinks,
                   containsPotentialBareAutolink(in: utf8, at: index, end: end) {
                    return true
                }

                if checksCommitSHAs,
                   containsPotentialCommitSHA(in: utf8, at: index, start: utf8.startIndex, end: end) {
                    return true
                }

                index = utf8.index(after: index)
            }
        } else {
            while index < end {
                let byte = utf8[index]
                if isActiveASCIIInlineMarker(
                    byte,
                    checksIssueReferences: checksIssueReferences,
                    checksRepositoryReferences: checksRepositoryReferences,
                    checksEmojiShortcodes: checksEmojiShortcodes,
                    checksMentions: checksMentions
                ) {
                    return true
                }

                index = utf8.index(after: index)
            }
        }

        return false
    }

    @inline(__always)
    private static func isActiveASCIIInlineMarker(
        _ byte: UInt8,
        checksIssueReferences: Bool,
        checksRepositoryReferences: Bool,
        checksEmojiShortcodes: Bool,
        checksMentions: Bool
    ) -> Bool {
        switch byte {
        case 0x21, // !
             0x2A, // *
             0x3C, // <
             0x5B, // [
             0x5C, // backslash
             0x5F, // _
             0x60, // `
             0x7E: // ~
            return true
        case 0x23 where checksIssueReferences: // #
            return true
        case 0x2F where checksRepositoryReferences: // /
            return true
        case 0x3A where checksEmojiShortcodes: // :
            return true
        case 0x40 where checksMentions: // @
            return true
        default:
            return false
        }
    }

    private static func containsPotentialCommitSHA(
        in utf8: String.UTF8View,
        at index: String.UTF8View.Index,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Bool {
        let byte = utf8[index]
        guard ParsingHelpers.isASCIIHex(byte) else {
            return false
        }

        return containsPotentialCommitSHAStartingWithHex(in: utf8, at: index, start: start, end: end)
    }

    private static func containsPotentialCommitSHAStartingWithHex(
        in utf8: String.UTF8View,
        at index: String.UTF8View.Index,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Bool {
        commitSHARangeStartingWithHex(in: utf8, at: index, start: start, end: end) != nil
    }

    private static func commitSHARangeStartingWithHex(
        in utf8: String.UTF8View,
        at index: String.UTF8View.Index,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Range<String.Index>? {
        if index > start {
            let previous = utf8[utf8.index(before: index)]
            if ParsingHelpers.isASCIIAlnum(previous) {
                return nil
            }
        }

        var scan = index
        var count = 0
        while scan < end, count < 40, ParsingHelpers.isASCIIHex(utf8[scan]) {
            count += 1
            scan = utf8.index(after: scan)
        }

        guard count >= 7 else {
            return nil
        }

        guard scan >= end || !ParsingHelpers.isASCIIAlnum(utf8[scan]) else {
            return nil
        }

        return index..<scan
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

    private static func repositoryReferenceCandidateBeforeSlash(
        in utf8: String.UTF8View,
        slash: String.UTF8View.Index,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> ASCIIInlineCandidate.RepositoryReference? {
        guard slash > start,
              utf8[slash] == 0x2F else {
            return nil
        }

        let repoStart = utf8.index(after: slash)
        guard repoStart < end,
              ParsingHelpers.isASCIIAlnum(utf8[repoStart]) else {
            return nil
        }

        var ownerStart = slash
        while ownerStart > start {
            let previous = utf8.index(before: ownerStart)
            let byte = utf8[previous]
            if ParsingHelpers.isASCIIAlnum(byte) || byte == 0x2D || byte == 0x5F { // - _
                ownerStart = previous
                continue
            }
            break
        }

        guard ownerStart < slash,
              ParsingHelpers.isASCIIAlpha(utf8[ownerStart]) else {
            return nil
        }

        if ownerStart > start {
            let previous = utf8[utf8.index(before: ownerStart)]
            if previous == 0x40 || previous == 0x2F || previous == 0x3A { // @ / :
                return nil
            }
        }

        var repoScan = repoStart
        while repoScan < end {
            let byte = utf8[repoScan]
            if ParsingHelpers.isASCIIAlnum(byte) || byte == 0x2D || byte == 0x5F || byte == 0x2E { // - _ .
                repoScan = utf8.index(after: repoScan)
                continue
            }
            break
        }

        guard repoScan > repoStart else {
            return nil
        }

        return .init(
            ownerRange: ownerStart..<slash,
            repoRange: repoStart..<repoScan,
            afterRepo: repoScan
        )
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

    private static func containsPotentialCommitSHA(_ state: ParserState) -> Bool {
        var index = state.currentIndex
        while index < state.endIndex {
            let ch = state.text[index]
            guard ParsingHelpers.isHexChar(ch) else {
                index = state.text.index(after: index)
                continue
            }

            if index > state.text.startIndex {
                let previous = state.text[state.text.index(before: index)]
                if previous.isLetter || previous.isNumber {
                    index = state.text.index(after: index)
                    continue
                }
            }

            var scan = index
            var count = 0
            while scan < state.endIndex, count < 40, ParsingHelpers.isHexChar(state.text[scan]) {
                count += 1
                scan = state.text.index(after: scan)
            }

            if count >= 7 {
                if scan >= state.endIndex {
                    return true
                }
                let next = state.text[scan]
                if !next.isLetter && !next.isNumber {
                    return true
                }
            }

            index = scan
        }

        return false
    }

    static func parseExtensionInline(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {
        guard !configuration.markdownExtensions.isEmpty, let ch = state.current() else { return nil }

        for markdownExtension in configuration.markdownExtensions
            where markdownExtension.shouldAttemptInlineParse(for: ch) {
            let context = MarkdownExtensionInlineContext(
                source: state.text,
                startIndex: state.currentIndex
            )
            guard let match = markdownExtension.parseInline(context),
                  match.endIndex > state.currentIndex,
                  match.endIndex <= state.endIndex else {
                continue
            }

            state.move(to: match.endIndex)
            return .extensionInline(
                MarkdownParser.ExtensionNode(
                    namespace: markdownExtension.id,
                    name: match.name,
                    literal: match.literal,
                    fields: match.fields
                )
            )
        }

        return nil
    }

    // MARK: - Inline Element Parsers

    static func parseInlineCode(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        if state.asciiFastPath {
            return parseASCIIInlineCode(&state, trimASCIIContentRangeBeforeCopying: true)
        }

        let mark = state.mark()

        // Count opening backticks
        var opening = 0
        while let ch = state.current(), ch == "`" { opening += 1; state.advance() }
        guard opening > 0 else { state.restore(mark); return nil }

        let contentStartIndex = state.currentIndex
        while let ch = state.current() {
            if ch == "`" {
                // Count closing backticks
                let closeStartIndex = state.currentIndex
                var closing = 0
                while let c = state.current(), c == "`" { closing += 1; state.advance() }
                if closing == opening {
                    let content = state.substring(from: contentStartIndex, to: closeStartIndex)
                    return .code(content.trimmingCharacters(in: .whitespaces))
                }
            } else {
                state.advance()
            }
        }

        // No matching closing backticks
        state.restore(mark)
        return nil
    }

    static func parseASCIIInlineCodeByTrimmingCopiedContentForTesting(
        _ state: inout ParserState
    ) -> MarkdownParser.InlineNode? {
        parseASCIIInlineCode(&state, trimASCIIContentRangeBeforeCopying: false)
    }

    private static func parseASCIIInlineCode(
        _ state: inout ParserState,
        trimASCIIContentRangeBeforeCopying: Bool
    ) -> MarkdownParser.InlineNode? {
        let mark = state.mark()

        let utf8 = state.text.utf8
        let utf8Start = state.currentIndex
        let utf8End = state.endIndex
        var scan = utf8Start
        var opening = 0
        var consumedBytes = 0
        var lineBreaks = 0
        var bytesAfterLastLineBreak = 0

        while scan < utf8End, utf8[scan] == 0x60 {
            opening += 1
            consumedBytes += 1
            bytesAfterLastLineBreak += 1
            scan = utf8.index(after: scan)
        }
        guard opening > 0 else {
            state.restore(mark)
            return nil
        }

        let contentStart = scan
        while scan < utf8End {
            let byte = utf8[scan]
            if byte == 0x60 {
                let closeStart = scan
                var closing = 0
                while scan < utf8End, utf8[scan] == 0x60 {
                    closing += 1
                    consumedBytes += 1
                    bytesAfterLastLineBreak += 1
                    scan = utf8.index(after: scan)
                }

                if closing == opening {
                    let contentStartIndex = contentStart
                    let closeStartIndex = closeStart
                    let afterCloseIndex = scan
                    let contentRange: Range<String.Index>
                    if trimASCIIContentRangeBeforeCopying {
                        contentRange = asciiWhitespaceTrimmedRange(
                            in: state.text.utf8,
                            start: contentStartIndex,
                            end: closeStartIndex
                        )
                    } else {
                        contentRange = contentStartIndex..<closeStartIndex
                    }
                    let content = state.substring(from: contentRange.lowerBound, to: contentRange.upperBound)
                    state.moveASCII(
                        to: afterCloseIndex,
                        consumedBytes: consumedBytes,
                        lineBreaks: lineBreaks,
                        bytesAfterLastLineBreak: bytesAfterLastLineBreak
                    )
                    if trimASCIIContentRangeBeforeCopying {
                        return .code(content)
                    }
                    return .code(content.trimmingCharacters(in: .whitespaces))
                }
            } else {
                consumedBytes += 1
                if byte == 0x0A {
                    lineBreaks += 1
                    bytesAfterLastLineBreak = 0
                } else {
                    bytesAfterLastLineBreak += 1
                }
                scan = utf8.index(after: scan)
            }
        }

        state.restore(mark)
        return nil
    }

    private static func asciiWhitespaceTrimmedRange(
        in utf8: String.UTF8View,
        start: String.Index,
        end: String.Index
    ) -> Range<String.Index> {
        var lowerBound = start
        var upperBound = end

        while lowerBound < upperBound {
            let byte = utf8[lowerBound]
            guard byte == 0x09 || byte == 0x20 else { break } // tab, space
            lowerBound = utf8.index(after: lowerBound)
        }

        while upperBound > lowerBound {
            let previous = utf8.index(before: upperBound)
            let byte = utf8[previous]
            guard byte == 0x09 || byte == 0x20 else { break } // tab, space
            upperBound = previous
        }

        return lowerBound..<upperBound
    }

    static func parseEmphasis(_ state: inout ParserState, delimiter: Character, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {

        let mark = state.mark()
        let openingRunLength = emphasisDelimiterRunLength(in: state, delimiter: delimiter)

        if openingRunLength >= 3,
           let ascii = parseASCIIEmphasisOnePass(
            &state,
            delimiter: delimiter,
            openingRunLength: openingRunLength,
            configuration: configuration
        ) {
            return ascii
        }
        state.restore(mark)

        if openingRunLength >= 3 {
            if let r = parseEmphasisWithCount(&state, delimiter: delimiter, count: 3, configuration: configuration) { return r }
            state.restore(mark)
        }
        if openingRunLength >= 2 {
            if let r = parseEmphasisWithCount(&state, delimiter: delimiter, count: 2, configuration: configuration) { return r }
            state.restore(mark)
        }
        if openingRunLength >= 1 {
            if let r = parseEmphasisWithCount(&state, delimiter: delimiter, count: 1, configuration: configuration) { return r }
            state.restore(mark)
        }
        return nil
    }

    static func parseEmphasisByRetryingDelimiterCountsForTesting(
        _ state: inout ParserState,
        delimiter: Character,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        let openingRunLength = emphasisDelimiterRunLength(in: state, delimiter: delimiter)

        if openingRunLength >= 3 {
            if let r = parseEmphasisWithCount(&state, delimiter: delimiter, count: 3, configuration: configuration) { return r }
            state.restore(mark)
        }
        if openingRunLength >= 2 {
            if let r = parseEmphasisWithCount(&state, delimiter: delimiter, count: 2, configuration: configuration) { return r }
            state.restore(mark)
        }
        if openingRunLength >= 1 {
            if let r = parseEmphasisWithCount(&state, delimiter: delimiter, count: 1, configuration: configuration) { return r }
            state.restore(mark)
        }
        return nil
    }

    private static func emphasisDelimiterRunLength(in state: ParserState, delimiter: Character) -> Int {
        var index = state.currentIndex
        var count = 0
        while index < state.endIndex, count < 3, state.text[index] == delimiter {
            count += 1
            index = state.text.index(after: index)
        }
        return count
    }

    private static func parseASCIIEmphasisOnePass(
        _ state: inout ParserState,
        delimiter: Character,
        openingRunLength: Int,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.InlineNode? {
        guard state.asciiFastPath, openingRunLength > 0 else {
            return nil
        }

        let delimiterByte: UInt8
        if delimiter == "*" {
            delimiterByte = 0x2A
        } else if delimiter == "_" {
            delimiterByte = 0x5F
        } else {
            return nil
        }

        let utf8 = state.text.utf8
        let start = state.currentIndex
        let end = state.endIndex
        guard start < end else {
            return nil
        }

        var scan = start
        var actualOpeningRunLength = 0
        var consumedBytes = 0
        var lineBreaks = 0
        var bytesAfterLastLineBreak = 0
        var firstDelimiter = start
        var secondDelimiter: String.Index?
        var thirdDelimiter: String.Index?

        @inline(__always)
        func stepped(_ byte: UInt8, _ consumedBytes: inout Int, _ lineBreaks: inout Int, _ bytesAfterLastLineBreak: inout Int) {
            consumedBytes += 1
            if byte == 0x0A {
                lineBreaks += 1
                bytesAfterLastLineBreak = 0
            } else {
                bytesAfterLastLineBreak += 1
            }
        }

        while scan < end, actualOpeningRunLength < 3, utf8[scan] == delimiterByte {
            switch actualOpeningRunLength {
            case 0:
                firstDelimiter = scan
            case 1:
                secondDelimiter = scan
            case 2:
                thirdDelimiter = scan
            default:
                break
            }
            actualOpeningRunLength += 1
            stepped(utf8[scan], &consumedBytes, &lineBreaks, &bytesAfterLastLineBreak)
            scan = utf8.index(after: scan)
        }

        let openingEnd = scan
        let maxCount = min(actualOpeningRunLength, 3)
        guard maxCount > 0 else {
            return nil
        }

        let oneContentStart = utf8.index(after: firstDelimiter)
        let twoContentStart = secondDelimiter.map { utf8.index(after: $0) }
        let threeContentStart = thirdDelimiter.map { utf8.index(after: $0) }

        var oneFailed = oneContentStart >= end || utf8[oneContentStart] == 0x20
        var twoFailed = twoContentStart.map { $0 >= end || utf8[$0] == 0x20 } ?? true
        var threeFailed = threeContentStart.map { $0 >= end || utf8[$0] == 0x20 } ?? true
        var oneRun: ASCIIEmphasisDelimiterRun?
        var twoRun: ASCIIEmphasisDelimiterRun?
        var threeRun: ASCIIEmphasisDelimiterRun?

        func contentStart(for count: Int) -> String.Index? {
            switch count {
            case 1: return oneFailed ? nil : oneContentStart
            case 2: return twoFailed ? nil : twoContentStart
            case 3: return threeFailed ? nil : threeContentStart
            default: return nil
            }
        }

        func storedRun(for count: Int) -> ASCIIEmphasisDelimiterRun? {
            switch count {
            case 1: return oneRun
            case 2: return twoRun
            case 3: return threeRun
            default: return nil
            }
        }

        func node(for count: Int, run: ASCIIEmphasisDelimiterRun) -> MarkdownParser.InlineNode? {
            guard let contentStart = contentStart(for: count) else {
                return nil
            }

            let inner = parseInlineElements(
                in: state,
                from: contentStart,
                to: run.start,
                configuration: configuration
            )
            state.moveASCII(
                to: run.end,
                consumedBytes: run.consumedBytes,
                lineBreaks: run.lineBreaks,
                bytesAfterLastLineBreak: run.bytesAfterLastLineBreak
            )

            switch count {
            case 1: return .emphasis(children: inner)
            case 2, 3: return .strong(children: inner)
            default: return nil
            }
        }

        func resolvedNodeIfHighestPendingMatched() -> MarkdownParser.InlineNode? {
            for count in stride(from: maxCount, through: 1, by: -1) {
                if let run = storedRun(for: count) {
                    return node(for: count, run: run)
                }

                if contentStart(for: count) != nil {
                    return nil
                }
            }
            return nil
        }

        func resolvedNodeAfterExhaustingInput() -> MarkdownParser.InlineNode? {
            for count in stride(from: maxCount, through: 1, by: -1) {
                if let run = storedRun(for: count) {
                    return node(for: count, run: run)
                }
            }
            return nil
        }

        func record(_ run: ASCIIEmphasisDelimiterRun, for count: Int) {
            guard let contentStart = contentStart(for: count),
                  run.start >= contentStart,
                  run.length >= count,
                  storedRun(for: count) == nil else {
                return
            }

            if run.start > contentStart {
                let previous = utf8.index(before: run.start)
                if utf8[previous] == 0x20 {
                    switch count {
                    case 1: oneFailed = true
                    case 2: twoFailed = true
                    case 3: threeFailed = true
                    default: break
                    }
                    return
                }
            }

            switch count {
            case 1: oneRun = run
            case 2: twoRun = run
            case 3: threeRun = run
            default: break
            }
        }

        func process(_ run: ASCIIEmphasisDelimiterRun) -> MarkdownParser.InlineNode? {
            for count in stride(from: maxCount, through: 1, by: -1) {
                record(run, for: count)
            }
            return resolvedNodeIfHighestPendingMatched()
        }

        if actualOpeningRunLength > 1, let secondDelimiter {
            let run = ASCIIEmphasisDelimiterRun(
                start: secondDelimiter,
                end: openingEnd,
                length: actualOpeningRunLength - 1,
                consumedBytes: consumedBytes,
                lineBreaks: lineBreaks,
                bytesAfterLastLineBreak: bytesAfterLastLineBreak
            )
            if let node = process(run) {
                return node
            }
        }

        if actualOpeningRunLength > 2, let thirdDelimiter {
            let run = ASCIIEmphasisDelimiterRun(
                start: thirdDelimiter,
                end: openingEnd,
                length: actualOpeningRunLength - 2,
                consumedBytes: consumedBytes,
                lineBreaks: lineBreaks,
                bytesAfterLastLineBreak: bytesAfterLastLineBreak
            )
            if let node = process(run) {
                return node
            }
        }

        while scan < end {
            let byte = utf8[scan]
            if byte == delimiterByte {
                let runStart = scan
                var length = 0
                while scan < end, utf8[scan] == delimiterByte {
                    length += 1
                    stepped(utf8[scan], &consumedBytes, &lineBreaks, &bytesAfterLastLineBreak)
                    scan = utf8.index(after: scan)
                }

                if let node = process(
                    ASCIIEmphasisDelimiterRun(
                        start: runStart,
                        end: scan,
                        length: length,
                        consumedBytes: consumedBytes,
                        lineBreaks: lineBreaks,
                        bytesAfterLastLineBreak: bytesAfterLastLineBreak
                    )
                ) {
                    return node
                }
                continue
            }

            stepped(byte, &consumedBytes, &lineBreaks, &bytesAfterLastLineBreak)
            scan = utf8.index(after: scan)

            if byte == 0x5C, scan < end {
                stepped(utf8[scan], &consumedBytes, &lineBreaks, &bytesAfterLastLineBreak)
                scan = utf8.index(after: scan)
            }
        }

        return resolvedNodeAfterExhaustingInput()
    }

    private static func parseEmphasisWithCount(_ state: inout ParserState, delimiter: Character, count: Int, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {
        if let ascii = parseASCIIEmphasisWithCount(
            &state,
            delimiter: delimiter,
            count: count,
            configuration: configuration
        ) {
            return ascii
        }

        let mark = state.mark()
        // Consume opening delimiters
        for _ in 0..<count {
            guard let ch = state.current(), ch == delimiter else { state.restore(mark); return nil }
            state.advance()
        }

        // Don't allow emphasis to start with whitespace
        if let ch = state.current(), ch == " " { state.restore(mark); return nil }

        let contentStartIndex = state.currentIndex
        var pendingDepth = 0
        while let ch = state.current() {
            if ch == delimiter {
                // Count run of delimiters
                let closeStartIndex = state.currentIndex
                var closeCount = 0
                while let c = state.current(), c == delimiter { closeCount += 1; state.advance() }
                if closeCount >= count && pendingDepth == 0 {
                    if closeStartIndex > contentStartIndex,
                       state.text[state.text.index(before: closeStartIndex)] == " " {
                        // Treat these delimiters as literal content and continue scanning
                        // Roll back to closeStartIndex and append one delimiter, then continue
                        state.move(to: closeStartIndex)
                        // Consume one delimiter into content and continue
                        state.advance()
                        continue
                    }
                    let inner = parseInlineElements(
                        in: state,
                        from: contentStartIndex,
                        to: closeStartIndex,
                        configuration: configuration
                    )
                    // We already consumed the full delimiter run; position is correct
                    switch count {
                    case 1: return .emphasis(children: inner)
                    case 2, 3: return .strong(children: inner)
                    default: return nil
                    }
                } else {
                    if closeCount == count { pendingDepth += 1 }
                }
            } else if ch == "\\" {
                // Skip escaped next character if present
                state.advance(); if state.current() != nil { state.advance() }
            } else {
                state.advance()
            }
        }
        state.restore(mark)
        return nil
    }

    private static func parseASCIIEmphasisWithCount(
        _ state: inout ParserState,
        delimiter: Character,
        count: Int,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.InlineNode? {
        guard state.asciiFastPath, count > 0 else {
            return nil
        }

        let delimiterByte: UInt8
        if delimiter == "*" {
            delimiterByte = 0x2A
        } else if delimiter == "_" {
            delimiterByte = 0x5F
        } else {
            return nil
        }

        let utf8 = state.text.utf8
        let start = state.currentIndex
        let end = state.endIndex
        var scan = start
        var consumedBytes = 0
        var lineBreaks = 0
        var bytesAfterLastLineBreak = 0

        @inline(__always)
        func stepped(_ byte: UInt8, _ consumedBytes: inout Int, _ lineBreaks: inout Int, _ bytesAfterLastLineBreak: inout Int) {
            consumedBytes += 1
            if byte == 0x0A {
                lineBreaks += 1
                bytesAfterLastLineBreak = 0
            } else {
                bytesAfterLastLineBreak += 1
            }
        }

        for _ in 0..<count {
            guard scan < end, utf8[scan] == delimiterByte else {
                return nil
            }
            stepped(utf8[scan], &consumedBytes, &lineBreaks, &bytesAfterLastLineBreak)
            scan = utf8.index(after: scan)
        }

        guard scan < end, utf8[scan] != 0x20 else {
            return nil
        }

        let contentStart = scan
        while scan < end {
            let byte = utf8[scan]
            if byte == delimiterByte {
                let closeStart = scan
                var closeScan = scan
                var closeCount = 0
                while closeScan < end, utf8[closeScan] == delimiterByte {
                    closeCount += 1
                    closeScan = utf8.index(after: closeScan)
                }

                if closeCount < count {
                    while scan < closeScan {
                        stepped(utf8[scan], &consumedBytes, &lineBreaks, &bytesAfterLastLineBreak)
                        scan = utf8.index(after: scan)
                    }
                    continue
                }

                if closeStart > contentStart {
                    let previous = utf8.index(before: closeStart)
                    if utf8[previous] == 0x20 {
                        return nil
                    }
                }

                var consumeClose = scan
                while consumeClose < closeScan {
                    stepped(utf8[consumeClose], &consumedBytes, &lineBreaks, &bytesAfterLastLineBreak)
                    consumeClose = utf8.index(after: consumeClose)
                }

                let inner = parseInlineElements(
                    in: state,
                    from: contentStart,
                    to: closeStart,
                    configuration: configuration
                )
                state.moveASCII(
                    to: closeScan,
                    consumedBytes: consumedBytes,
                    lineBreaks: lineBreaks,
                    bytesAfterLastLineBreak: bytesAfterLastLineBreak
                )

                switch count {
                case 1: return .emphasis(children: inner)
                case 2, 3: return .strong(children: inner)
                default: return nil
                }
            }

            stepped(byte, &consumedBytes, &lineBreaks, &bytesAfterLastLineBreak)
            scan = utf8.index(after: scan)

            if byte == 0x5C, scan < end {
                stepped(utf8[scan], &consumedBytes, &lineBreaks, &bytesAfterLastLineBreak)
                scan = utf8.index(after: scan)
            }
        }

        return nil
    }

    static func parseStrikethrough(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {
        if let ascii = parseASCIIStrikethrough(&state, configuration: configuration) {
            return ascii
        }

        return parseStrikethroughByCharacterScanningForTesting(&state, configuration: configuration)
    }

    static func parseStrikethroughByCharacterScanningForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.InlineNode? {

        let mark = state.mark()

        guard state.current() == "~", state.peek(1) == "~" else { return nil }
        state.advance(); state.advance() // consume opening ~~

        // Find closing ~~
        let contentStartIndex = state.currentIndex
        while let ch = state.current(), let next = state.peek(1) {
            if ch == "~" && next == "~" {
                // emit content between contentStartIndex and currentIndex
                let innerContent = parseInlineElements(
                    in: state,
                    from: contentStartIndex,
                    to: state.currentIndex,
                    configuration: configuration
                )
                state.advance(); state.advance() // consume closing ~~
                return .strikethrough(children: innerContent)
            }
            state.advance()
        }

        state.restore(mark)
        return nil
    }

    private static func parseASCIIStrikethrough(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.InlineNode? {
        guard state.asciiFastPath else {
            return nil
        }

        let utf8 = state.text.utf8
        let start = state.currentIndex
        let end = state.endIndex
        guard start < end, utf8[start] == 0x7E else {
            return nil
        }

        let second = utf8.index(after: start)
        guard second < end, utf8[second] == 0x7E else {
            return nil
        }

        let contentStart = utf8.index(after: second)
        var scan = contentStart
        var consumedBytes = 2
        var lineBreaks = 0
        var bytesAfterLastLineBreak = 2

        while scan < end {
            let byte = utf8[scan]
            if byte == 0x7E {
                let next = utf8.index(after: scan)
                if next < end, utf8[next] == 0x7E {
                    let innerContent = parseInlineElements(
                        in: state,
                        from: contentStart,
                        to: scan,
                        configuration: configuration
                    )
                    let afterClose = utf8.index(after: next)
                    consumedBytes += 2
                    bytesAfterLastLineBreak += 2
                    state.moveASCII(
                        to: afterClose,
                        consumedBytes: consumedBytes,
                        lineBreaks: lineBreaks,
                        bytesAfterLastLineBreak: bytesAfterLastLineBreak
                    )
                    return .strikethrough(children: innerContent)
                }
            }

            consumedBytes += 1
            if byte == 0x0A {
                lineBreaks += 1
                bytesAfterLastLineBreak = 0
            } else {
                bytesAfterLastLineBreak += 1
            }
            scan = utf8.index(after: scan)
        }

        return nil
    }

    static func parseLink(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {
        parseLink(&state, configuration: configuration, useASCIIResourceMove: true)
    }

    static func parseLinkByMovingResourceWithCharactersForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.InlineNode? {
        parseLink(&state, configuration: configuration, useASCIIResourceMove: false)
    }

    private static func parseLink(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        useASCIIResourceMove: Bool
    ) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        guard state.current() == "[" else { return nil }
        state.advance()

        // Parse link text with nested brackets
        guard let linkTextRange = parseBracketedTextRange(&state) else { state.restore(mark); return nil }

        // Inline destination: (URL [title])
        if state.current() == "(" {
            state.advance()
            guard let resource = parseInlineLinkResource(
                in: state.text,
                from: state.currentIndex,
                to: state.endIndex
            ) else {
                state.restore(mark); return nil
            }

            let textContent = parseLinkTextContent(
                in: state.text,
                bracketedText: linkTextRange,
                configuration: configuration,
                asciiFastPath: state.asciiFastPath
            )
            movePastInlineLinkResource(&state, resource: resource, useASCIIResourceMove: useASCIIResourceMove)

            if let parsedURL = URL(string: resource.destination) {
                return .link(url: parsedURL, title: resource.title, children: textContent)
            } else {
                state.restore(mark); return nil
            }
        } else if state.current() == "[" {
            // Reference style link not resolved in this implementation
            state.advance()
            while let c = state.current(), c != "]" { state.advance() }
            if state.current() == "]" { state.advance(); state.restore(mark); return nil }
        }
        state.restore(mark)
        return nil
    }

    static func parseLinkByCopyingTextAndDestinationForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        guard state.current() == "[" else { return nil }
        state.advance()

        guard let linkText = parseBracketedTextContentByCopying(&state) else {
            state.restore(mark)
            return nil
        }

        if state.current() == "(" {
            state.advance()
            guard let (inner, after) = ParsingHelpers.scanBalanced(
                in: state.text,
                from: state.currentIndex,
                end: state.endIndex,
                open: "(",
                close: ")",
                allowEscape: true
            ) else {
                state.restore(mark)
                return nil
            }

            var destinationStart = inner.startIndex
            ParsingHelpers.skipSpaces(in: inner, from: &destinationStart, end: inner.endIndex)
            let destinationEnd = ParsingHelpers.firstASCIISpaceOrTab(
                in: inner,
                from: destinationStart,
                end: inner.endIndex
            )
            let destination = unescapeLinkDestination(in: inner, from: destinationStart, to: destinationEnd)

            var title: String?
            if destinationEnd < inner.endIndex {
                var titleStart = destinationEnd
                ParsingHelpers.skipSpaces(in: inner, from: &titleStart, end: inner.endIndex)
                if titleStart < inner.endIndex {
                    let delimiter = inner[titleStart]
                    if delimiter == Character("\"") || delimiter == Character("'") || delimiter == Character("(") {
                        let quotedStart = inner.index(after: titleStart)
                        guard let (parsedTitle, afterTitle) = ParsingHelpers.scanQuoted(
                            in: inner,
                            from: quotedStart,
                            end: inner.endIndex,
                            delimiter: delimiter
                        ) else {
                            state.restore(mark)
                            return nil
                        }
                        title = parsedTitle
                        var trailing = afterTitle
                        ParsingHelpers.skipSpaces(in: inner, from: &trailing, end: inner.endIndex)
                    }
                }
            }

            state.move(to: after)
            var linkState = ParserState(text: linkText)
            let textContent = parseInlineElements(&linkState, configuration: configuration)
            if let parsedURL = URL(string: destination) {
                return .link(url: parsedURL, title: title, children: textContent)
            }

            state.restore(mark)
            return nil
        } else if state.current() == "[" {
            state.advance()
            while let c = state.current(), c != "]" { state.advance() }
            if state.current() == "]" {
                state.advance()
                state.restore(mark)
                return nil
            }
        }

        state.restore(mark)
        return nil
    }

    static func parseImage(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {

        let mark = state.mark()
        guard state.current() == "!", state.peek(1) == "[" else { return nil }
        state.advance(); state.advance() // consume ![

        guard let altTextRange = parseBracketedTextRange(&state) else { state.restore(mark); return nil }

        if state.current() == "(" {
            state.advance()
            guard let resource = parseInlineLinkResource(
                in: state.text,
                from: state.currentIndex,
                to: state.endIndex
            ) else {
                state.restore(mark); return nil
            }

            let altText = bracketedText(in: state.text, bracketedText: altTextRange)
            movePastInlineLinkResource(&state, resource: resource, useASCIIResourceMove: true)
            if let parsedURL = URL(string: resource.destination) {
                return .image(url: parsedURL, alt: altText, title: resource.title)
            }
            state.restore(mark); return nil
        }
        state.restore(mark)
        return nil
    }

    struct InlineLinkResource {
        let destination: String
        let title: String?
        let after: String.Index
        let asciiByteCount: Int?
    }

    private static func movePastInlineLinkResource(
        _ state: inout ParserState,
        resource: InlineLinkResource,
        useASCIIResourceMove: Bool
    ) {
        if useASCIIResourceMove,
           let asciiByteCount = resource.asciiByteCount {
            state.moveASCII(
                to: resource.after,
                consumedBytes: asciiByteCount,
                lineBreaks: 0,
                bytesAfterLastLineBreak: 0
            )
            return
        }

        state.move(to: resource.after)
    }

    private struct BracketedTextRange {
        let range: Range<String.Index>
        let containsBackslash: Bool
    }

    private static func parseInlineLinkResource(
        in text: String,
        from start: String.Index,
        to end: String.Index
    ) -> InlineLinkResource? {
        if let simple = parseSimpleInlineLinkResource(in: text, from: start, to: end) {
            return simple
        }

        return parseInlineLinkResourceWithBalancedScan(in: text, from: start, to: end)
    }

    static func parseInlineLinkResourceWithBalancedScanForTesting(
        in text: String,
        from start: String.Index,
        to end: String.Index
    ) -> InlineLinkResource? {
        parseInlineLinkResourceWithBalancedScan(in: text, from: start, to: end)
    }

    static func parseInlineLinkResourceForTesting(
        in text: String,
        from start: String.Index,
        to end: String.Index
    ) -> InlineLinkResource? {
        parseInlineLinkResource(in: text, from: start, to: end)
    }

    private static func parseSimpleInlineLinkResource(
        in text: String,
        from start: String.Index,
        to end: String.Index
    ) -> InlineLinkResource? {
        guard let utf8Start = start.samePosition(in: text.utf8),
              let utf8End = end.samePosition(in: text.utf8) else {
            return nil
        }

        let utf8 = text.utf8
        var index = utf8Start
        while index < utf8End && (utf8[index] == 0x20 || utf8[index] == 0x09) {
            index = utf8.index(after: index)
        }

        let destinationStart = index
        while index < utf8End {
            switch utf8[index] {
            case 0x29: // )
                guard index > destinationStart,
                      let destinationStartIndex = String.Index(destinationStart, within: text),
                      let close = String.Index(index, within: text),
                      let after = String.Index(utf8.index(after: index), within: text) else {
                    return nil
                }
                return InlineLinkResource(
                    destination: String(text[destinationStartIndex..<close]),
                    title: nil,
                    after: after,
                    asciiByteCount: utf8.distance(from: utf8Start, to: utf8.index(after: index))
                )

            case 0x09, // tab
                 0x20: // space
                guard index > destinationStart else {
                    return nil
                }
                return parseSimpleInlineLinkResourceTitle(
                    in: text,
                    resourceStart: utf8Start,
                    destinationStart: destinationStart,
                    destinationEnd: index,
                    titleStart: index,
                    utf8End: utf8End
                )

            case 0x0A, // newline
                 0x0D, // carriage return
                 0x22, // "
                 0x27, // '
                 0x28, // (
                 0x5C: // backslash
                return nil

            default:
                if utf8[index] >= 0x80 {
                    return nil
                }
                index = utf8.index(after: index)
            }
        }

        return nil
    }

    private static func parseSimpleInlineLinkResourceTitle(
        in text: String,
        resourceStart: String.UTF8View.Index,
        destinationStart: String.UTF8View.Index,
        destinationEnd: String.UTF8View.Index,
        titleStart: String.UTF8View.Index,
        utf8End: String.UTF8View.Index
    ) -> InlineLinkResource? {
        let utf8 = text.utf8
        var titleIndex = titleStart
        while titleIndex < utf8End && (utf8[titleIndex] == 0x20 || utf8[titleIndex] == 0x09) {
            titleIndex = utf8.index(after: titleIndex)
        }

        guard titleIndex < utf8End else {
            return nil
        }

        if utf8[titleIndex] == 0x29 {
            guard let destinationStartIndex = String.Index(destinationStart, within: text),
                  let destinationEndIndex = String.Index(destinationEnd, within: text),
                  let after = String.Index(utf8.index(after: titleIndex), within: text) else {
                return nil
            }
            return InlineLinkResource(
                destination: String(text[destinationStartIndex..<destinationEndIndex]),
                title: nil,
                after: after,
                asciiByteCount: utf8.distance(from: resourceStart, to: utf8.index(after: titleIndex))
            )
        }

        let delimiter = utf8[titleIndex]
        guard delimiter == 0x22 || delimiter == 0x27 else {
            return nil
        }

        let titleContentStart = utf8.index(after: titleIndex)
        var scan = titleContentStart
        while scan < utf8End {
            let byte = utf8[scan]
            if byte == delimiter {
                var closeIndex = utf8.index(after: scan)
                while closeIndex < utf8End && (utf8[closeIndex] == 0x20 || utf8[closeIndex] == 0x09) {
                    closeIndex = utf8.index(after: closeIndex)
                }

                guard closeIndex < utf8End,
                      utf8[closeIndex] == 0x29,
                      let destinationStartIndex = String.Index(destinationStart, within: text),
                      let destinationEndIndex = String.Index(destinationEnd, within: text),
                      let titleStartIndex = String.Index(titleContentStart, within: text),
                      let titleEndIndex = String.Index(scan, within: text),
                      let after = String.Index(utf8.index(after: closeIndex), within: text) else {
                    return nil
                }

                return InlineLinkResource(
                    destination: String(text[destinationStartIndex..<destinationEndIndex]),
                    title: String(text[titleStartIndex..<titleEndIndex]),
                    after: after,
                    asciiByteCount: utf8.distance(from: resourceStart, to: utf8.index(after: closeIndex))
                )
            }

            if byte == 0x28 || byte == 0x29 || byte == 0x5C || byte == 0x0A || byte == 0x0D || byte >= 0x80 {
                return nil
            }
            scan = utf8.index(after: scan)
        }

        return nil
    }

    private static func parseInlineLinkResourceWithBalancedScan(
        in text: String,
        from start: String.Index,
        to end: String.Index
    ) -> InlineLinkResource? {
        guard let scanned = ParsingHelpers.scanBalancedRange(
            in: text,
            from: start,
            end: end,
            open: "(",
            close: ")",
            allowEscape: true
        ) else {
            return nil
        }

        var destinationStart = scanned.range.lowerBound
        ParsingHelpers.skipSpaces(in: text, from: &destinationStart, end: scanned.range.upperBound)
        let destinationEnd = ParsingHelpers.firstASCIISpaceOrTab(
            in: text,
            from: destinationStart,
            end: scanned.range.upperBound
        )
        let destination = unescapeLinkDestination(in: text, from: destinationStart, to: destinationEnd)

        var title: String?
        if destinationEnd < scanned.range.upperBound {
            var titleStart = destinationEnd
            ParsingHelpers.skipSpaces(in: text, from: &titleStart, end: scanned.range.upperBound)
            if titleStart < scanned.range.upperBound {
                let delimiter = text[titleStart]
                if delimiter == Character("\"") || delimiter == Character("'") || delimiter == Character("(") {
                    let quotedStart = text.index(after: titleStart)
                    guard let (parsedTitle, afterTitle) = ParsingHelpers.scanQuoted(
                        in: text,
                        from: quotedStart,
                        end: scanned.range.upperBound,
                        delimiter: delimiter
                    ) else {
                        return nil
                    }
                    title = parsedTitle
                    var trailing = afterTitle
                    ParsingHelpers.skipSpaces(in: text, from: &trailing, end: scanned.range.upperBound)
                }
            }
        }

        return InlineLinkResource(destination: destination, title: title, after: scanned.after, asciiByteCount: nil)
    }

    private static func parseBracketedTextRange(_ state: inout ParserState) -> BracketedTextRange? {
        let contentStartIndex = state.currentIndex

        if let fastRange = parseSimpleBracketedTextRange(&state, contentStartIndex: contentStartIndex) {
            return fastRange
        }

        var scan = contentStartIndex
        var depth = 1
        var containsBackslash = false
        while scan < state.endIndex, depth > 0 {
            let ch = state.text[scan]
            if ch == "\\" {
                containsBackslash = true
                let next = state.text.index(after: scan)
                if next < state.endIndex {
                    scan = state.text.index(after: next)
                } else {
                    return nil
                }
            } else if ch == "[" {
                depth += 1
                scan = state.text.index(after: scan)
            } else if ch == "]" {
                depth -= 1
                if depth == 0 {
                    let afterClose = state.text.index(after: scan)
                    state.move(to: afterClose)
                    return BracketedTextRange(
                        range: contentStartIndex..<scan,
                        containsBackslash: containsBackslash
                    )
                }
                scan = state.text.index(after: scan)
            } else {
                scan = state.text.index(after: scan)
            }
        }

        return nil
    }

    private static func parseBracketedTextContentByCopying(_ state: inout ParserState) -> String? {
        let contentStartIndex = state.currentIndex

        if let fastRange = parseSimpleBracketedTextRange(&state, contentStartIndex: contentStartIndex) {
            return String(state.text[fastRange.range])
        }

        guard let range = parseBracketedTextRange(&state) else {
            return nil
        }

        return bracketedText(in: state.text, bracketedText: range)
    }

    private static func parseSimpleBracketedTextRange(
        _ state: inout ParserState,
        contentStartIndex: String.Index
    ) -> BracketedTextRange? {
        if state.asciiFastPath {
            let utf8 = state.text.utf8
            let utf8Start = contentStartIndex
            let utf8End = state.endIndex
            var scan = utf8Start
            while scan < utf8End {
                switch utf8[scan] {
                case 0x5D: // ]
                    let afterClose = utf8.index(after: scan)
                    let closeIndex = scan
                    let afterCloseIndex = afterClose
                    state.moveASCII(to: afterCloseIndex)
                    return BracketedTextRange(range: contentStartIndex..<closeIndex, containsBackslash: false)
                case 0x5B, 0x5C: // [ or backslash
                    return nil
                default:
                    scan = utf8.index(after: scan)
                }
            }
            return nil
        }

        var scan = contentStartIndex
        while scan < state.endIndex {
            let ch = state.text[scan]
            if ch == "]" {
                state.move(to: state.text.index(after: scan))
                return BracketedTextRange(range: contentStartIndex..<scan, containsBackslash: false)
            }
            if ch == "[" || ch == "\\" {
                return nil
            }
            scan = state.text.index(after: scan)
        }

        return nil
    }

    private static func bracketedText(in text: String, bracketedText: BracketedTextRange) -> String {
        guard bracketedText.containsBackslash else {
            return String(text[bracketedText.range])
        }

        return unescapeBracketedText(in: text, range: bracketedText.range)
    }

    private static func parseLinkTextContent(
        in text: String,
        bracketedText: BracketedTextRange,
        configuration: MarkdownConfiguration,
        asciiFastPath: Bool
    ) -> [MarkdownParser.InlineNode] {
        if bracketedText.containsBackslash {
            var labelState = ParserState(text: self.bracketedText(in: text, bracketedText: bracketedText))
            return parseInlineElements(&labelState, configuration: configuration)
        }

        return parseInlineElements(
            in: text,
            from: bracketedText.range.lowerBound,
            to: bracketedText.range.upperBound,
            configuration: configuration,
            asciiFastPath: asciiFastPath ? true : nil
        )
    }

    private static func unescapeBracketedText(
        in text: String,
        range: Range<String.Index>
    ) -> String {
        var output = ""
        output.reserveCapacity(text.utf8.distance(from: range.lowerBound, to: range.upperBound))

        var index = range.lowerBound
        while index < range.upperBound {
            let ch = text[index]
            if ch == "\\" {
                let next = text.index(after: index)
                if next < range.upperBound {
                    output.append(text[next])
                    index = text.index(after: next)
                } else {
                    break
                }
            } else {
                output.append(ch)
                index = text.index(after: index)
            }
        }

        return output
    }

    private static func unescapeLinkDestination(
        in text: String,
        from start: String.Index,
        to end: String.Index
    ) -> String {
        var scan = start
        while scan < end {
            if text[scan] == "\\" {
                return unescapeLinkDestination(in: text, from: start, to: end, firstBackslash: scan)
            }
            scan = text.index(after: scan)
        }

        return String(text[start..<end])
    }

    private static func unescapeLinkDestination(
        in text: String,
        from start: String.Index,
        to end: String.Index,
        firstBackslash: String.Index
    ) -> String {
        var unescaped = ""
        unescaped.reserveCapacity(128)
        unescaped.append(contentsOf: text[start..<firstBackslash])

        var index = firstBackslash
        while index < end {
            let ch = text[index]
            if ch == "\\" {
                let next = text.index(after: index)
                if next < end {
                    unescaped.append(text[next])
                    index = text.index(after: next)
                } else {
                    break
                }
            } else {
                unescaped.append(ch)
                index = text.index(after: index)
            }
        }

        return unescaped
    }

    static func parseFootnoteReference(_ state: inout ParserState) -> MarkdownParser.InlineNode? {

        let mark = state.mark()
        guard state.current() == "[", state.peek(1) == "^" else { return nil }
        state.advance(); state.advance()
        var idxLab = state.currentIndex
        let endLab = state.endIndex
        let label: String
        if state.asciiFastPath {
            label = ParsingHelpers.scanWhileUTF8(in: state.text, from: &idxLab, end: endLab, while: { b in b != 0x5D /*]*/ && b != 0x0A /*\n*/ })
        } else {
            label = ParsingHelpers.scanWhile(in: state.text, from: &idxLab, end: endLab, while: { ch in ch != "]" && ch != "\n" })
        }
        state.move(to: idxLab)
        guard state.current() == "]" else { state.restore(mark); return nil }
        state.advance()
        guard !label.isEmpty else { state.restore(mark); return nil }
        return .footnoteReference(label: label)
    }

    static func parseHTMLTag(_ state: inout ParserState) -> MarkdownParser.InlineNode? {

        let mark = state.mark()
        guard state.current() == "<" else { return nil }
        state.advance()
        if state.current() == "/" { state.advance() }
        var tIdx = state.currentIndex
        let tEnd = state.endIndex
        let tagName: String
        if state.asciiFastPath {
            tagName = ParsingHelpers.scanWhileUTF8(in: state.text, from: &tIdx, end: tEnd, while: { b in ParsingHelpers.isASCIIAlpha(b) })
        } else {
            tagName = ParsingHelpers.scanWhile(in: state.text, from: &tIdx, end: tEnd, while: { ch in ch.isLetter })
        }
        state.move(to: tIdx)
        guard !tagName.isEmpty else { state.restore(mark); return nil }
        var tmpIdx = state.currentIndex
        let tmpEnd = state.endIndex
        if state.asciiFastPath {
            _ = ParsingHelpers.scanWhileUTF8(in: state.text, from: &tmpIdx, end: tmpEnd, while: { b in b != 0x3E /*>*/ })
        } else {
            _ = ParsingHelpers.scanWhile(in: state.text, from: &tmpIdx, end: tmpEnd, while: { ch in ch != ">" })
        }
        state.move(to: tmpIdx)
        guard state.current() == ">" else { state.restore(mark); return nil }
        state.advance()
        let html = state.substring(from: mark.index, to: state.currentIndex)
        return .html(html)
    }

    // (legacy OLD_ autolink helpers removed)

    static func parseMention(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        guard state.current() == "@" else { return nil }

        // Reject if preceded by [A-Za-z0-9_-]
        if mark.index > state.text.startIndex {
            let prev = state.text[state.text.index(before: mark.index)]
            if prev.isLetter || prev.isNumber || prev == "_" || prev == "-" { return nil }
        }

        state.advance() // consume '@'

        // Scan username characters
        var idx = state.currentIndex
        let end = state.endIndex
        let scanned: String
        if state.asciiFastPath {
            let range = ParsingHelpers.scanUTF8Range(in: state.text, from: &idx, end: end, while: { b in
                ParsingHelpers.isASCIIAlnum(b) || b == 0x2D /*-*/ || b == 0x5F /*_*/
            })
            scanned = String(state.text[range.range])
        } else {
            scanned = ParsingHelpers.scanWhile(in: state.text, from: &idx, end: end, while: { ch in
                ch.isLetter || ch.isNumber || ch == "-" || ch == "_"
            })
        }
        let username = scanned
        state.moveASCII(to: idx)

        guard !username.isEmpty else { state.restore(mark); return nil }

        // Disambiguate emails: if next is '.' followed by domain-like chars, not a mention
        if let ch = state.current(), ch == "." {
            var idx = state.currentIndex
            var hasDomainChars = false
            if state.asciiFastPath {
                let utf8 = state.text.utf8
                let uStart = idx
                let uEnd = state.endIndex
                var uidx = uStart
                while uidx < uEnd {
                    uidx = utf8.index(after: uidx)
                    if uidx >= uEnd { break }
                    let b = utf8[uidx]
                    if (b >= 0x30 && b <= 0x39) || // 0-9
                       (b >= 0x41 && b <= 0x5A) || // A-Z
                       (b >= 0x61 && b <= 0x7A) || // a-z
                       b == 0x2D || b == 0x2E { // - .
                        hasDomainChars = true
                    } else { break }
                }
            } else {
                while idx < state.endIndex {
                    idx = state.text.index(after: idx)
                    if idx >= state.endIndex { break }
                    let c = state.text[idx]
                    if c.isLetter || c.isNumber || c == "-" || c == "." { hasDomainChars = true }
                    else { break }
                }
            }
            if hasDomainChars { state.restore(mark); return nil }
        }

        return .mention(username: username)
    }

    static func parseIssueReference(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        guard state.current() == "#" else { return nil }
        // Preceded by alnum or '#' => not an issue
        if mark.index > state.text.startIndex {
            let prev = state.text[state.text.index(before: mark.index)]
            if prev.isLetter || prev.isNumber || prev == "#" { return nil }
        }
        state.advance()
        var idxNum = state.currentIndex
        let endNum = state.endIndex
        let number: Int?
        if state.asciiFastPath {
            number = ParsingHelpers.scanASCIIInteger(in: state.text, from: &idxNum, end: endNum).value
        } else {
            let digits = ParsingHelpers.scanWhile(in: state.text, from: &idxNum, end: endNum, while: { ch in ch.isNumber })
            number = Int(digits)
        }
        state.moveASCII(to: idxNum)
        guard let n = number else { state.restore(mark); return nil }
        return .issueReference(number: n)
    }

    static func parseEmojiShortcode(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        guard state.current() == ":" else { return nil }
        state.advance()
        var idxName = state.currentIndex
        let endName = state.endIndex
        let name: String
        if state.asciiFastPath {
            let range = ParsingHelpers.scanUTF8Range(in: state.text, from: &idxName, end: endName, while: { b in
                ParsingHelpers.isASCIIAlnum(b) || b == 0x5F /*_*/ || b == 0x2D /*-*/ || b == 0x2B /*+*/
            })
            state.moveASCII(to: idxName)
            guard state.current() == ":" else { state.restore(mark); return nil }
            state.advance()
            guard range.count > 0 else { state.restore(mark); return nil }

            if let commonEmoji = commonUnicodeEmoji(
                in: state.text,
                range: range.range,
                byteCount: range.count
            ) {
                return .text(commonEmoji)
            }

            name = String(state.text[range.range])
        } else {
            name = ParsingHelpers.scanWhile(in: state.text, from: &idxName, end: endName, while: { ch in
                ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "+"
            })
            state.moveASCII(to: idxName)
            guard state.current() == ":" else { state.restore(mark); return nil }
            state.advance()
            guard !name.isEmpty else { state.restore(mark); return nil }

            if let commonEmoji = commonUnicodeEmoji(for: name) {
                return .text(commonEmoji)
            }
        }

        if let emoji = GitHubEmojis.unicodeEmoji(for: name) {
            if emoji.hasPrefix(":") && emoji.hasSuffix(":") {
                if let imageUrl = GitHubEmojis.emojiURL(for: name), let url = URL(string: imageUrl) {
                    return .image(url: url, alt: ":\(name):", title: nil)
                }
            }
            return .text(emoji)
        }
        if let imageUrl = GitHubEmojis.emojiURL(for: name), let url = URL(string: imageUrl) {
            return .image(url: url, alt: ":\(name):", title: nil)
        }
        state.restore(mark)
        return nil
    }

    private static func commonUnicodeEmoji(
        in text: String,
        range: Range<String.Index>,
        byteCount: Int
    ) -> String? {
        guard let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            return nil
        }

        let utf8 = text.utf8
        switch byteCount {
        case 4:
            var index = start
            guard utf8[index] == 0x74 else { return nil } // t
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x61 else { return nil } // a
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x64 else { return nil } // d
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x61 else { return nil } // a
            return utf8.index(after: index) == end ? "🎉" : nil
        case 6:
            var index = start
            guard utf8[index] == 0x72 else { return nil } // r
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x6F else { return nil } // o
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x63 else { return nil } // c
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x6B else { return nil } // k
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x65 else { return nil } // e
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x74 else { return nil } // t
            return utf8.index(after: index) == end ? "🚀" : nil
        case 8:
            var index = start
            guard utf8[index] == 0x73 else { return nil } // s
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x70 else { return nil } // p
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x61 else { return nil } // a
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x72 else { return nil } // r
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x6B else { return nil } // k
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x6C else { return nil } // l
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x65 else { return nil } // e
            index = utf8.index(after: index)
            guard index < end, utf8[index] == 0x73 else { return nil } // s
            return utf8.index(after: index) == end ? "✨" : nil
        default:
            return nil
        }
    }

    private static func commonUnicodeEmoji(for name: String) -> String? {
        switch name {
        case "rocket":
            return "🚀"
        case "sparkles":
            return "✨"
        case "tada":
            return "🎉"
        default:
            return nil
        }
    }

    static func parseCommitSHA(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        // Start boundary: previous char should not be alphanumeric
        if mark.index > state.text.startIndex {
            let prev = state.text[state.text.index(before: mark.index)]
            if prev.isLetter || prev.isNumber { return nil }
        }
        var idx = state.currentIndex
        let end = state.endIndex
        let sha: String
        let shaLength: Int
        if state.asciiFastPath {
            let range = ParsingHelpers.scanUTF8Range(
                in: state.text,
                from: &idx,
                end: end,
                while: { b in ParsingHelpers.isASCIIHex(b) },
                maxCount: 40
            )
            sha = String(state.text[range.range])
            shaLength = range.count
        } else {
            sha = ParsingHelpers.scanWhile(in: state.text, from: &idx, end: end, while: { ch in ParsingHelpers.isHexChar(ch) }, maxCount: 40)
            shaLength = sha.count
        }
        state.moveASCII(to: idx)
        guard shaLength >= 7 && shaLength <= 40 else { state.restore(mark); return nil }
        if let next = state.current(), (next.isLetter || next.isNumber) { state.restore(mark); return nil }
        let shortSha = String(sha.prefix(7))
        return .commitSHA(sha: sha, short: shortSha)
    }

    private static func parseCommitSHA(
        _ state: inout ParserState,
        candidate: ASCIIInlineCandidate?,
        shouldProbe: Bool
    ) -> MarkdownParser.InlineNode? {
        if case .commitSHA(let shaCandidate) = candidate,
           shaCandidate.range.lowerBound == state.currentIndex,
           shaCandidate.range.upperBound <= state.endIndex {
            let sha = String(state.text[shaCandidate.range])
            state.moveASCII(to: shaCandidate.range.upperBound)
            return .commitSHA(sha: sha, short: String(sha.prefix(7)))
        }

        guard shouldProbe, shouldAttemptCommitSHA(state) else {
            return nil
        }
        return parseCommitSHA(&state)
    }

    private static func shouldAttemptCommitSHA(_ state: ParserState) -> Bool {
        if state.asciiFastPath {
            let utf8 = state.text.utf8
            return containsPotentialCommitSHA(
                in: utf8,
                at: state.currentIndex,
                start: utf8.startIndex,
                end: state.endIndex
            )
        }

        guard let ch = state.current(), ParsingHelpers.isHexChar(ch) else {
            return false
        }

        if state.currentIndex > state.text.startIndex {
            let previous = state.text[state.text.index(before: state.currentIndex)]
            if previous.isLetter || previous.isNumber {
                return false
            }
        }

        var index = state.currentIndex
        var count = 0
        while index < state.endIndex, count < 40, ParsingHelpers.isHexChar(state.text[index]) {
            count += 1
            index = state.text.index(after: index)
        }

        guard count >= 7 else {
            return false
        }

        if index < state.endIndex {
            let next = state.text[index]
            if next.isLetter || next.isNumber {
                return false
            }
        }

        return true
    }

    static func parseRepositoryReference(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        let mark = state.mark()

        // owner
        var idx = state.currentIndex
        let end = state.endIndex
        guard let first = state.current(), first.isLetter else { return nil }
        let owner: String
        if state.asciiFastPath {
            let range = ParsingHelpers.scanUTF8Range(in: state.text, from: &idx, end: end, while: { b in
                ParsingHelpers.isASCIIAlnum(b) || b == 0x2D /*-*/ || b == 0x5F /*_*/
            })
            owner = String(state.text[range.range])
        } else {
            owner = ParsingHelpers.scanWhile(in: state.text, from: &idx, end: end, while: { ch in
                ch.isLetter || ch.isNumber || ch == "-" || ch == "_"
            })
        }
        state.moveASCII(to: idx)
        // /
        guard state.current() == "/" else { state.restore(mark); return nil }
        state.advance()
        // repo
        guard let r0 = state.current(), (r0.isLetter || r0.isNumber) else { state.restore(mark); return nil }
        idx = state.currentIndex
        let repo: String
        if state.asciiFastPath {
            let range = ParsingHelpers.scanUTF8Range(in: state.text, from: &idx, end: end, while: { b in
                ParsingHelpers.isASCIIAlnum(b) || b == 0x2D /*-*/ || b == 0x5F /*_*/ || b == 0x2E /*.*/
            })
            repo = String(state.text[range.range])
        } else {
            repo = ParsingHelpers.scanWhile(in: state.text, from: &idx, end: end, while: { ch in
                ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "."
            })
        }
        state.moveASCII(to: idx)
        guard !owner.isEmpty && !repo.isEmpty else { state.restore(mark); return nil }

        // Optional #number => PR reference
        if state.current() == "#" {
            state.advance()
            var dIdx = state.currentIndex
            let dEnd = state.endIndex
            let number: Int?
            if state.asciiFastPath {
                number = ParsingHelpers.scanASCIIInteger(in: state.text, from: &dIdx, end: dEnd).value
            } else {
                let digits = ParsingHelpers.scanWhile(in: state.text, from: &dIdx, end: dEnd, while: { ch in ch.isNumber })
                number = Int(digits)
            }
            state.moveASCII(to: dIdx)
            if let num = number { return .pullRequestReference(owner: owner, repo: repo, number: num) }
        }

        // Context check: if preceded by @ / : then not a standalone repo ref
        if mark.index > state.text.startIndex {
            let prev = state.text[state.text.index(before: mark.index)]
            if prev == "@" || prev == "/" || prev == ":" { state.restore(mark); return nil }
        }
        return .repositoryReference(owner: owner, repo: repo)
    }

    private static func parseRepositoryReference(
        _ state: inout ParserState,
        candidate: ASCIIInlineCandidate?,
        shouldProbe: Bool
    ) -> MarkdownParser.InlineNode? {
        if case .repositoryReference(let reference) = candidate,
           reference.ownerRange.lowerBound == state.currentIndex,
           reference.repoRange.upperBound <= state.endIndex {
            return parseRepositoryReference(&state, reference: reference)
        }

        guard shouldProbe, shouldAttemptRepositoryReference(state) else {
            return nil
        }
        return parseRepositoryReference(&state)
    }

    private static func parseRepositoryReference(
        _ state: inout ParserState,
        reference: ASCIIInlineCandidate.RepositoryReference
    ) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        guard reference.ownerRange.lowerBound == mark.index,
              reference.ownerRange.upperBound < state.endIndex,
              reference.repoRange.lowerBound < reference.repoRange.upperBound,
              reference.afterRepo == reference.repoRange.upperBound else {
            return nil
        }

        if mark.index > state.text.startIndex {
            let prev = state.text[state.text.index(before: mark.index)]
            if prev == "@" || prev == "/" || prev == ":" {
                state.restore(mark)
                return nil
            }
        }

        let owner = String(state.text[reference.ownerRange])
        let repo = String(state.text[reference.repoRange])
        state.moveASCII(to: reference.afterRepo)

        if state.current() == "#" {
            state.advance()
            var digitIndex = state.currentIndex
            let number = ParsingHelpers.scanASCIIInteger(
                in: state.text,
                from: &digitIndex,
                end: state.endIndex
            ).value
            state.moveASCII(to: digitIndex)
            if let number {
                return .pullRequestReference(owner: owner, repo: repo, number: number)
            }
        }

        return .repositoryReference(owner: owner, repo: repo)
    }

    private static func shouldAttemptRepositoryReference(_ state: ParserState) -> Bool {
        if state.asciiFastPath {
            let utf8 = state.text.utf8
            return shouldAttemptRepositoryReference(
                in: utf8,
                at: state.currentIndex,
                start: utf8.startIndex,
                end: state.endIndex
            )
        }

        guard let first = state.current(), first.isLetter else {
            return false
        }

        if state.currentIndex > state.text.startIndex {
            let previous = state.text[state.text.index(before: state.currentIndex)]
            if previous == "@" || previous == "/" || previous == ":" {
                return false
            }
        }

        var index = state.currentIndex
        while index < state.endIndex {
            let ch = state.text[index]
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                index = state.text.index(after: index)
                continue
            }
            break
        }

        return index < state.endIndex && state.text[index] == "/"
    }

    private static func shouldAttemptRepositoryReference(
        in utf8: String.UTF8View,
        at index: String.UTF8View.Index,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Bool {
        guard index < end, ParsingHelpers.isASCIIAlpha(utf8[index]) else {
            return false
        }

        if index > start {
            let previous = utf8[utf8.index(before: index)]
            if previous == 0x40 || previous == 0x2F || previous == 0x3A { // @ / :
                return false
            }
        }

        var scan = index
        while scan < end {
            let byte = utf8[scan]
            if ParsingHelpers.isASCIIAlnum(byte) || byte == 0x2D || byte == 0x5F { // - _
                scan = utf8.index(after: scan)
                continue
            }
            break
        }

        return scan < end && utf8[scan] == 0x2F // /
    }

    private static func shouldAttemptBareAutolink(_ state: ParserState) -> Bool {
        if state.asciiFastPath {
            let utf8 = state.text.utf8
            return containsPotentialBareAutolink(in: utf8, at: state.currentIndex, end: state.endIndex)
        }

        return hasBareAutolinkPrefix(in: state, at: state.currentIndex)
    }

    private static func containsPotentialBareAutolink(_ state: ParserState) -> Bool {
        if state.asciiFastPath {
            let utf8 = state.text.utf8
            let start = state.currentIndex
            let end = state.endIndex
            var index = start
            while index < end {
                if containsPotentialBareAutolink(in: utf8, at: index, end: end) {
                    return true
                }
                index = utf8.index(after: index)
            }
            return false
        }

        var index = state.currentIndex
        while index < state.endIndex {
            switch state.text[index] {
            case "f", "h", "m", "w":
                if hasBareAutolinkPrefix(in: state, at: index) {
                    return true
                }
            default:
                break
            }
            index = state.text.index(after: index)
        }
        return false
    }

    private static func hasBareAutolinkPrefix(in state: ParserState, at index: String.Index) -> Bool {
        hasPrefix("http://", in: state.text, at: index, end: state.endIndex) ||
        hasPrefix("https://", in: state.text, at: index, end: state.endIndex) ||
        hasPrefix("ftp://", in: state.text, at: index, end: state.endIndex) ||
        hasPrefix("mailto:", in: state.text, at: index, end: state.endIndex) ||
        hasPrefix("www.", in: state.text, at: index, end: state.endIndex)
    }

    private static func hasPrefix(
        _ prefix: String,
        in text: String,
        at start: String.Index,
        end: String.Index
    ) -> Bool {
        var textIndex = start
        for prefixCharacter in prefix {
            guard textIndex < end, text[textIndex] == prefixCharacter else {
                return false
            }
            textIndex = text.index(after: textIndex)
        }
        return true
    }

    // MARK: - Helper Methods

    static func parseUnifiedAutolinkByMovingWithCharactersForTesting(
        _ state: inout ParserState,
        angleBracketMode: Bool
    ) -> MarkdownParser.InlineNode? {
        parseUnifiedAutolink(
            &state,
            angleBracketMode: angleBracketMode,
            useASCIICursorMove: false,
            useASCIISchemeDetection: true
        )
    }

    static func parseUnifiedAutolinkByDetectingSchemeWithCharactersForTesting(
        _ state: inout ParserState,
        angleBracketMode: Bool
    ) -> MarkdownParser.InlineNode? {
        parseUnifiedAutolink(
            &state,
            angleBracketMode: angleBracketMode,
            useASCIICursorMove: true,
            useASCIISchemeDetection: false
        )
    }

    // Unified autolink parser supporting angle-bracket and extended autolinks
    static func parseUnifiedAutolink(_ state: inout ParserState, angleBracketMode: Bool) -> MarkdownParser.InlineNode? {
        parseUnifiedAutolink(
            &state,
            angleBracketMode: angleBracketMode,
            useASCIICursorMove: true,
            useASCIISchemeDetection: true
        )
    }

    private static func parseUnifiedAutolink(
        _ state: inout ParserState,
        angleBracketMode: Bool,
        useASCIICursorMove: Bool,
        useASCIISchemeDetection: Bool
    ) -> MarkdownParser.InlineNode? {
        let startMark = state.mark()
        if angleBracketMode {
            guard state.current() == "<" else { return nil }
            state.advance()
        }
        let startIndex = state.currentIndex

        @inline(__always)
        func hasPrefix(_ prefix: String) -> Bool {
            var idx = startIndex
            for ch in prefix {
                if idx >= state.endIndex || state.text[idx] != ch { return false }
                idx = state.text.index(after: idx)
            }
            return true
        }

        @inline(__always)
        func schemeFromASCIIBytes() -> Scheme? {
            guard startIndex < state.endIndex else { return nil }

            let utf8 = state.text.utf8
            let end = state.endIndex

            @inline(__always)
            func byte(_ index: String.Index) -> UInt8? {
                index < end ? utf8[index] : nil
            }

            @inline(__always)
            func after(_ index: String.Index) -> String.Index {
                utf8.index(after: index)
            }

            switch utf8[startIndex] {
            case 0x66: // ftp://
                var scan = after(startIndex)
                guard byte(scan) == 0x74 else { return nil } // t
                scan = after(scan)
                guard byte(scan) == 0x70 else { return nil } // p
                scan = after(scan)
                guard byte(scan) == 0x3A else { return nil } // :
                scan = after(scan)
                guard byte(scan) == 0x2F else { return nil } // /
                scan = after(scan)
                return byte(scan) == 0x2F ? .httpLike : nil // /
            case 0x68: // http:// or https://
                var scan = after(startIndex)
                guard byte(scan) == 0x74 else { return nil } // t
                scan = after(scan)
                guard byte(scan) == 0x74 else { return nil } // t
                scan = after(scan)
                guard byte(scan) == 0x70 else { return nil } // p
                scan = after(scan)

                if byte(scan) == 0x73 { // s
                    scan = after(scan)
                }

                guard byte(scan) == 0x3A else { return nil } // :
                scan = after(scan)
                guard byte(scan) == 0x2F else { return nil } // /
                scan = after(scan)
                return byte(scan) == 0x2F ? .httpLike : nil // /
            case 0x6D: // mailto:
                var scan = after(startIndex)
                guard byte(scan) == 0x61 else { return nil } // a
                scan = after(scan)
                guard byte(scan) == 0x69 else { return nil } // i
                scan = after(scan)
                guard byte(scan) == 0x6C else { return nil } // l
                scan = after(scan)
                guard byte(scan) == 0x74 else { return nil } // t
                scan = after(scan)
                guard byte(scan) == 0x6F else { return nil } // o
                scan = after(scan)
                return byte(scan) == 0x3A ? .mailto : nil // :
            case 0x77: // www.
                var scan = after(startIndex)
                guard byte(scan) == 0x77 else { return nil } // w
                scan = after(scan)
                guard byte(scan) == 0x77 else { return nil } // w
                scan = after(scan)
                return byte(scan) == 0x2E ? .www : nil // .
            default:
                return nil
            }
        }

        enum Scheme { case httpLike, www, mailto, angle }
        let scheme: Scheme?
        if angleBracketMode {
            scheme = .angle
        } else if useASCIISchemeDetection, state.asciiFastPath {
            scheme = schemeFromASCIIBytes()
        } else if hasPrefix("http://") || hasPrefix("https://") || hasPrefix("ftp://") {
            scheme = .httpLike
        } else if hasPrefix("mailto:") {
            scheme = .mailto
        } else if hasPrefix("www.") {
            scheme = .www
        } else {
            scheme = nil
        }

        guard let schemeType = scheme else { return nil }

        @inline(__always)
        func isLikelyAngleEmail(_ value: String) -> Bool {
            guard !value.contains(":"),
                  let at = value.firstIndex(of: "@"),
                  at > value.startIndex else { return false }
            let domainStart = value.index(after: at)
            guard domainStart < value.endIndex else { return false }
            let domain = value[domainStart...]
            return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
        }

        var idx = startIndex
        var openParens = 0, closeParens = 0
        var openBrackets = 0, closeBrackets = 0
        if state.asciiFastPath {
            let utf8 = state.text.utf8
            let uStart = startIndex
            let uEnd = state.endIndex
            var uidx = uStart
            scanLoopASCII: while uidx < uEnd {
                let b = utf8[uidx]
                switch b {
                case 0x20, 0x0A, 0x09: // space, \n, \t
                    break scanLoopASCII
                case 0x3C, 0x3E: // <, >
                    // Angle bracket breaks regardless
                    break scanLoopASCII
                case 0x28: // (
                    openParens &+= 1; uidx = utf8.index(after: uidx)
                case 0x29: // )
                    closeParens &+= 1; uidx = utf8.index(after: uidx)
                case 0x5B: // [
                    openBrackets &+= 1; uidx = utf8.index(after: uidx)
                case 0x5D: // ]
                    closeBrackets &+= 1; uidx = utf8.index(after: uidx)
                default:
                    uidx = utf8.index(after: uidx)
                }
            }
            idx = uidx
        } else {
            scanLoop: while idx < state.endIndex {
                let ch = state.text[idx]
                switch ch {
                case " ", "\n", "\t":
                    break scanLoop
                case "<", ">":
                    break scanLoop
                case "(": openParens += 1; idx = state.text.index(after: idx)
                case ")": closeParens += 1; idx = state.text.index(after: idx)
                case "[": openBrackets += 1; idx = state.text.index(after: idx)
                case "]": closeBrackets += 1; idx = state.text.index(after: idx)
                default: idx = state.text.index(after: idx)
                }
            }
        }

        var endIndex = idx
        if angleBracketMode {
            if idx >= state.endIndex || state.text[idx] != ">" {
                state.restore(startMark)
                return nil
            }
        }

        while endIndex > startIndex {
            let prev = state.text[state.text.index(before: endIndex)]
            if prev == "." || prev == "," || prev == ";" || prev == ":" || prev == "?" || prev == "!" {
                endIndex = state.text.index(before: endIndex)
            } else { break }
        }
        var extraCloseParens = max(0, closeParens - openParens)
        while extraCloseParens > 0 && endIndex > startIndex && state.text[state.text.index(before: endIndex)] == ")" {
            endIndex = state.text.index(before: endIndex)
            extraCloseParens -= 1
        }
        var extraCloseBrackets = max(0, closeBrackets - openBrackets)
        while extraCloseBrackets > 0 && endIndex > startIndex && state.text[state.text.index(before: endIndex)] == "]" {
            endIndex = state.text.index(before: endIndex)
            extraCloseBrackets -= 1
        }

        if endIndex <= startIndex { state.restore(startMark); return nil }

        let urlText = state.substring(from: startIndex, to: endIndex)
        // Determine autolink type and destination URL
        var linkURL: URL?
        var displayText = urlText
        var linkType: MarkdownParser.AutolinkType = .url
        switch schemeType {
        case .httpLike:
            linkType = .url
            linkURL = URL(string: urlText)
        case .www:
            linkType = .www
            linkURL = URL(string: "http://\(urlText)")
        case .mailto:
            linkType = .email
            // Strip leading mailto: from display
            if urlText.lowercased().hasPrefix("mailto:") {
                displayText = String(urlText.dropFirst("mailto:".count))
            }
            linkURL = URL(string: urlText)
        case .angle:
            // Angle-bracket: decide by content
            if isLikelyAngleEmail(urlText) {
                linkType = .email
                displayText = urlText
                linkURL = URL(string: "mailto:\(urlText)")
            } else {
                guard let colonIndex = urlText.firstIndex(of: ":") else {
                    state.restore(startMark)
                    return nil
                }
                let schemeText = urlText[..<colonIndex]
                guard !schemeText.isEmpty,
                      let first = schemeText.first,
                      first.isLetter,
                      schemeText.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" }) else {
                    state.restore(startMark)
                    return nil
                }
                linkType = .url
                linkURL = URL(string: urlText)
            }
        }
        guard let finalURL = linkURL else { state.restore(startMark); return nil }

        if angleBracketMode {
            let afterAngle = state.text.index(after: idx)
            if useASCIICursorMove {
                state.moveASCII(to: afterAngle)
            } else {
                state.move(to: idx)
                if state.current() == ">" { state.advance() }
            }
        } else {
            if useASCIICursorMove {
                state.moveASCII(to: endIndex)
            } else {
                state.move(to: endIndex)
            }
        }
        return .autolink(finalURL, linkType, originalText: displayText)
    }
}
