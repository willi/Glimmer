import XCTest
@testable import Glimmer

final class ParserOptimizationEquivalenceTests: XCTestCase {
    func testAdversarialSemanticFixturesStayStable() {
        for fixture in ParserCorrectnessFixtures.semanticFixtures {
            let blocks = MarkdownParser.parse(fixture.markdown, configuration: fixture.configuration)
            let canonical = ParserCanonicalSnapshot.canonicalDescription(for: blocks)
            let hash = ParserCanonicalSnapshot.stableHash(canonical)

            XCTAssertEqual(
                blocks.count,
                fixture.expectedBlockCount,
                "\(fixture.name) block count changed; actual canonical:\n\(canonical)"
            )
            XCTAssertEqual(
                hash,
                fixture.expectedHash,
                "\(fixture.name) semantic hash changed; actual hash: \(hash)\n\(canonical)"
            )
        }
    }

    func testBlockquoteFastPathMatchesRecursiveParserForFixtures() throws {
        for fixture in ParserCorrectnessFixtures.blockquoteEquivalence {
            var recursiveState = ParserState(text: fixture.markdown)
            let recursive = try XCTUnwrap(
                BlockParser.parseBlockquoteByRecursivelyParsingJoinedContentForTesting(
                    &recursiveState,
                    configuration: fixture.configuration
                ),
                fixture.name
            )

            var fastState = ParserState(text: fixture.markdown)
            let fast = try XCTUnwrap(
                BlockParser.parseBlockquote(&fastState, configuration: fixture.configuration),
                fixture.name
            )

            ParserCanonicalSnapshot.assertSemanticallyEqual([fast], [recursive], fixture.name)
        }
    }

    func testListItemFastPathMatchesCopyingParserForFixtures() {
        for fixture in ParserCorrectnessFixtures.listItemContentEquivalence {
            var copyingState = ParserState(text: fixture.markdown)
            let copying = BlockParser.parseListItemContentByCopyingLinesForTesting(
                &copyingState,
                indent: 0,
                marker: "-",
                configuration: fixture.configuration
            )

            var fastState = ParserState(text: fixture.markdown)
            let fast = BlockParser.parseListItemContent(
                &fastState,
                indent: 0,
                marker: "-",
                configuration: fixture.configuration
            )

            XCTAssertEqual(fast.marker, copying.marker, fixture.name)
            XCTAssertEqual(fast.isTask, copying.isTask, fixture.name)
            XCTAssertEqual(fast.isChecked, copying.isChecked, fixture.name)
            ParserCanonicalSnapshot.assertSemanticallyEqual(fast.content, copying.content, fixture.name)
        }
    }

    func testFootnoteFastPathMatchesCopyingParserForFixtures() throws {
        for fixture in ParserCorrectnessFixtures.footnoteDefinitionEquivalence {
            var copyingState = ParserState(text: fixture.markdown)
            let copying = try XCTUnwrap(
                BlockParser.parseFootnoteDefinitionByCopyingLinesForTesting(
                    &copyingState,
                    configuration: fixture.configuration
                ),
                fixture.name
            )

            var fastState = ParserState(text: fixture.markdown)
            let fast = try XCTUnwrap(
                BlockParser.parseFootnoteDefinition(&fastState, configuration: fixture.configuration),
                fixture.name
            )

            ParserCanonicalSnapshot.assertSemanticallyEqual([fast], [copying], fixture.name)
        }
    }

    func testPlainMultilineContainerParagraphFastPathMatchesJoinedFallback() throws {
        let blockquoteInputs = [
            """
            > first plain line
            > second plain line with café
            > third plain line
            """,
            """
            > first **bold starts
            > and closes here**
            """,
            """
            > plain line
            lazy continuation line
            """
        ]

        for input in blockquoteInputs {
            var joinedState = ParserState(text: input)
            let joined = try XCTUnwrap(
                BlockParser.parseBlockquoteByJoiningSingleParagraphsForTesting(
                    &joinedState,
                    configuration: .default
                ),
                input
            )

            var fastState = ParserState(text: input)
            let fast = try XCTUnwrap(BlockParser.parseBlockquote(&fastState, configuration: .default), input)

            ParserCanonicalSnapshot.assertSemanticallyEqual([fast], [joined], input)
        }

        let listInputs = [
            """
            first plain item line
              second plain item line
              third plain item line
            """,
            """
            first **bold starts
              and closes here**
            """,
            """
            first plain item line
              [link](https://example.com)
            """
        ]

        for input in listInputs {
            var joinedState = ParserState(text: input)
            let joined = BlockParser.parseListItemContentByJoiningSingleParagraphForTesting(
                &joinedState,
                indent: 0,
                marker: "-",
                configuration: .default
            )

            var fastState = ParserState(text: input)
            let fast = BlockParser.parseListItemContent(
                &fastState,
                indent: 0,
                marker: "-",
                configuration: .default
            )

            XCTAssertEqual(fast.marker, joined.marker, input)
            XCTAssertEqual(fast.isTask, joined.isTask, input)
            XCTAssertEqual(fast.isChecked, joined.isChecked, input)
            ParserCanonicalSnapshot.assertSemanticallyEqual(fast.content, joined.content, input)
        }

        let footnoteInputs = [
            """
            [^plain]: first plain footnote line
                second plain footnote line
                third plain footnote line
            """,
            """
            [^styled]: first **bold starts
                and closes here**
            """,
            """
            [^link]: first plain footnote line
                [link](https://example.com)
            """
        ]

        for input in footnoteInputs {
            var joinedState = ParserState(text: input)
            let joined = try XCTUnwrap(
                BlockParser.parseFootnoteDefinitionByJoiningSingleParagraphForTesting(
                    &joinedState,
                    configuration: .default
                ),
                input
            )

            var fastState = ParserState(text: input)
            let fast = try XCTUnwrap(
                BlockParser.parseFootnoteDefinition(&fastState, configuration: .default),
                input
            )

            ParserCanonicalSnapshot.assertSemanticallyEqual([fast], [joined], input)
        }
    }

    func testNonBlankPlainParagraphHelperMatchesGenericHelper() {
        let inputs = [
            """
            first plain line
            second plain line
            third plain line
            """,
            "  leading first line\nmiddle line\ntrailing last line   \n",
            """
            first **bold starts
            and closes here**
            """,
            """
            first plain line
            [link](https://example.com)
            """
        ]

        for input in inputs {
            let ranges = nonBlankLineRanges(in: input)
            let reservedUTF8Count = reservedUTF8Count(for: ranges, in: input)
            let generic = BlockParser.plainTextParagraphInlinesFromSourceRangesForTesting(
                from: ranges,
                in: input,
                reservedUTF8Count: reservedUTF8Count,
                configuration: .default
            )
            let nonBlank = BlockParser.plainTextParagraphInlinesFromNonBlankSourceRangesForTesting(
                from: ranges,
                in: input,
                reservedUTF8Count: reservedUTF8Count,
                configuration: .default
            )

            XCTAssertEqual(nonBlank, generic, input)
        }
    }

    func testContentLineFastPathClassifierMatchesSeparateScans() {
        let inputs = [
            "",
            "   ",
            "    indented code",
            "plain paragraph",
            "   plain paragraph after spaces",
            "# heading",
            "> quote",
            "```swift",
            "~~~",
            "| table |",
            "- list",
            "* list",
            "+ list",
            "123. ordered",
            "123) ordered",
            "plain = text",
            "= setext continuation",
            "\t- tab is not a leading-space list marker here",
            "  \t# tab after spaces stays paragraph content",
            "\u{000B}",
            "\u{000B}plain after vertical tab",
            "\u{00A0}",
            "\u{00A0}# unicode whitespace heading",
            "\u{0661}. unicode digit"
        ]

        for input in inputs {
            let range = input.startIndex..<input.endIndex
            for isFirstLine in [true, false] {
                XCTAssertEqual(
                    BlockParser.contentLineCanUseParagraphFastPathForTesting(
                        in: input,
                        range: range,
                        isFirstLine: isFirstLine
                    ),
                    BlockParser.contentLineCanUseParagraphFastPathBySeparateScansForTesting(
                        in: input,
                        range: range,
                        isFirstLine: isFirstLine
                    ),
                    "\(input), firstLine=\(isFirstLine)"
                )
            }
        }
    }

    func testSetextProbeScannedHeadingRangeMatchesTrimRescan() {
        let inputs = [
            "Heading\n===",
            "Heading\n---\nnext",
            " Heading with spaces \n---   \nnext",
            "\tTabbed heading\t\n---",
            "Unicode café\n---",
            "\u{00A0}Unicode whitespace\u{00A0}\n---",
            "Heading **bold** with [link](https://example.com)\n---",
            "Heading\r\n---",
            "Heading\n---x",
            "Single line"
        ]

        for input in inputs {
            var scannedState = ParserState(text: input)
            let scanned = BlockParser.parseSetextHeadingUsingProbeForTesting(
                &scannedState,
                configuration: .github
            )

            var rescannedState = ParserState(text: input)
            let rescanned = BlockParser.parseSetextHeadingUsingProbeWithTrimRescanForTesting(
                &rescannedState,
                configuration: .github
            )

            let scannedSignature = parseSignature(block: scanned, state: scannedState, in: input)
            let rescannedSignature = parseSignature(block: rescanned, state: rescannedState, in: input)
            XCTAssertEqual(scannedSignature, rescannedSignature, input)
        }
    }

    func testTableRowLineScanMatchesSeparatePipeScan() {
        let inputs = [
            "| A | B |\n| - | - |\n| 1 | 2 |\nnot a row",
            "A | B\n--- | ---\nrow | cell\nplain continuation",
            "| A |\n|-|",
            "| A | B |\n| - | - |\nrow without pipe",
            "| A | B |\n| - | - |\nemoji 😀 | value\nnext paragraph",
            "| A | B |\n| - | - |\ncafe\u{301} | value\nplain",
            "| A | B |\n| - | - |\ntabs\t|\tvalue\nplain"
        ]

        for input in inputs {
            var combinedState = ParserState(text: input)
            let combined = BlockParser.parseTableUsingStartProbeForTesting(
                &combinedState,
                configuration: .github
            )

            var separateState = ParserState(text: input)
            let separate = BlockParser.parseTableBySeparateRowLineAndPipeScansForTesting(
                &separateState,
                configuration: .github
            )

            let combinedSignature = parseSignature(block: combined, state: combinedState, in: input)
            let separateSignature = parseSignature(block: separate, state: separateState, in: input)
            XCTAssertEqual(combinedSignature, separateSignature, input)
        }
    }

    func testInlineDirectScanMatchesPlainTextPrescanForFixtures() {
        for fixture in ParserCorrectnessFixtures.inlineEquivalence {
            var prescanState = ParserState(text: fixture.markdown)
            let prescan = InlineParser.parseInlineElementsByPrescanningPlainTextForTesting(
                &prescanState,
                configuration: fixture.configuration
            )

            var directState = ParserState(text: fixture.markdown)
            let direct = InlineParser.parseInlineElements(&directState, configuration: fixture.configuration)

            ParserCanonicalSnapshot.assertSemanticallyEqual(
                [.paragraph(children: direct)],
                [.paragraph(children: prescan)],
                fixture.name
            )
        }
    }

    func testInlineDeferredLiteralRunsMatchCopyingBufferForFixtures() {
        let fixtures = ParserCorrectnessFixtures.inlineEquivalence + [
            .init(
                name: "mixedDefaultMarkers",
                markdown: "Intro text before **bold** then [link](https://example.com) and `code` after",
                configuration: .default
            ),
            .init(
                name: "failedMarkersStayText",
                markdown: "Intro * not emphasis and [not a link] plus escaped \\*marker\\* tail",
                configuration: .default
            ),
            .init(
                name: "gfmCandidates",
                markdown: "Before @octocat fixed #42 in owner/repo with deadbeef and https://example.com/path after",
                configuration: .github
            ),
            .init(
                name: "unicodeFallback",
                markdown: "Before café **bold** and 世界 [link](https://example.com/café) after",
                configuration: .default
            )
        ]

        for fixture in fixtures {
            var copyingState = ParserState(text: fixture.markdown)
            let copying = InlineParser.parseInlineElementsByCopyingLiteralRunsForTesting(
                &copyingState,
                configuration: fixture.configuration
            )

            var deferredState = ParserState(text: fixture.markdown)
            let deferred = InlineParser.parseInlineElements(&deferredState, configuration: fixture.configuration)

            ParserCanonicalSnapshot.assertSemanticallyEqual(
                [.paragraph(children: deferred)],
                [.paragraph(children: copying)],
                fixture.name
            )
        }
    }

    func testInlineLiteralRunByteCountsMatchRecountingPath() {
        let fixtures = ParserCorrectnessFixtures.inlineEquivalence + [
            .init(
                name: "longPlainASCII",
                markdown: String(repeating: "plain ascii words before marker ", count: 80) + "**bold** tail",
                configuration: .default
            ),
            .init(
                name: "defaultMarkers",
                markdown: "Prefix before [link](https://example.com) then `code` and *italic* after",
                configuration: .default
            ),
            .init(
                name: "githubRepositoryCandidate",
                markdown: "Prefix before apple/swift repository reference and trailing text",
                configuration: .github
            ),
            .init(
                name: "githubAutolinkCandidate",
                markdown: "Prefix before https://example.com/path?q=1 and trailing text",
                configuration: .github
            ),
            .init(
                name: "githubCommitCandidate",
                markdown: "Prefix before deadbeefdeadbeefdeadbeefdeadbeefdeadbeef and trailing text",
                configuration: .github
            ),
            .init(
                name: "newlineDispatch",
                markdown: "Line one before soft break\nline two with **bold**",
                configuration: .default
            ),
            .init(
                name: "unicodeFallback",
                markdown: "Unicode café before **bold** and 世界 after",
                configuration: .default
            )
        ]

        for fixture in fixtures {
            var recountingState = ParserState(text: fixture.markdown)
            let recounting = InlineParser.parseInlineElementsByRecountingLiteralRunBytesForTesting(
                &recountingState,
                configuration: fixture.configuration
            )

            var countedState = ParserState(text: fixture.markdown)
            let counted = InlineParser.parseInlineElements(&countedState, configuration: fixture.configuration)

            ParserCanonicalSnapshot.assertSemanticallyEqual(
                [.paragraph(children: counted)],
                [.paragraph(children: recounting)],
                fixture.name
            )
            XCTAssertEqual(
                inlineParsePositionSignature(countedState, in: fixture.markdown),
                inlineParsePositionSignature(recountingState, in: fixture.markdown),
                fixture.name
            )
        }
    }

    func testInlineFastPathsMatchBaselineParsersForFixtures() throws {
        for fixture in ParserCorrectnessFixtures.linkEquivalence {
            var copyingState = ParserState(text: fixture.markdown)
            copyingState.enableASCIIFastPathIfPossible()
            let copying = try XCTUnwrap(
                InlineParser.parseLinkByCopyingTextAndDestinationForTesting(
                    &copyingState,
                    configuration: fixture.configuration
                ),
                fixture.name
            )

            var rangeState = ParserState(text: fixture.markdown)
            rangeState.enableASCIIFastPathIfPossible()
            let rangeBacked = try XCTUnwrap(
                InlineParser.parseLink(&rangeState, configuration: fixture.configuration),
                fixture.name
            )
            XCTAssertEqual(rangeBacked, copying, fixture.name)

            var characterMoveState = ParserState(text: fixture.markdown)
            characterMoveState.enableASCIIFastPathIfPossible()
            let characterMove = try XCTUnwrap(
                InlineParser.parseLinkByMovingResourceWithCharactersForTesting(
                    &characterMoveState,
                    configuration: fixture.configuration
                ),
                fixture.name
            )
            XCTAssertEqual(rangeBacked, characterMove, fixture.name)
        }
    }

    func testInlineResourceFastPathMatchesBalancedScanForFixtures() throws {
        for resource in ParserCorrectnessFixtures.inlineLinkResources {
            let fast = try XCTUnwrap(
                InlineParser.parseInlineLinkResourceForTesting(
                    in: resource,
                    from: resource.startIndex,
                    to: resource.endIndex
                ),
                resource
            )
            let balanced = try XCTUnwrap(
                InlineParser.parseInlineLinkResourceWithBalancedScanForTesting(
                    in: resource,
                    from: resource.startIndex,
                    to: resource.endIndex
                ),
                resource
            )

            XCTAssertEqual(fast.destination, balanced.destination, resource)
            XCTAssertEqual(fast.title, balanced.title, resource)
            XCTAssertEqual(
                resource.distance(from: resource.startIndex, to: fast.after),
                resource.distance(from: resource.startIndex, to: balanced.after),
                resource
            )
        }
    }

    func testEmphasisAndStrikethroughFastPathsMatchFallbackParsersForFixtures() throws {
        let emphasisInputs = [
            "*italic*",
            "**bold**",
            "***bold***",
            "***foo**",
            "**foo***",
            "*foo **bar** baz*"
        ]

        for input in emphasisInputs {
            var fallbackState = ParserState(text: input)
            fallbackState.enableASCIIFastPathIfPossible()
            let fallback = try XCTUnwrap(
                InlineParser.parseEmphasisByRetryingDelimiterCountsForTesting(
                    &fallbackState,
                    delimiter: input.first ?? "*",
                    configuration: .default
                ),
                input
            )

            var fastState = ParserState(text: input)
            fastState.enableASCIIFastPathIfPossible()
            let fast = try XCTUnwrap(
                InlineParser.parseEmphasis(
                    &fastState,
                    delimiter: input.first ?? "*",
                    configuration: .default
                ),
                input
            )
            XCTAssertEqual(fast, fallback, input)
        }

        let strikeInputs = [
            "~~struck~~",
            "~~with **bold** inside~~",
            "~~code `let x = 1` inside~~"
        ]

        for input in strikeInputs {
            var fallbackState = ParserState(text: input)
            fallbackState.enableASCIIFastPathIfPossible()
            let fallback = try XCTUnwrap(
                InlineParser.parseStrikethroughByCharacterScanningForTesting(
                    &fallbackState,
                    configuration: .default
                ),
                input
            )

            var fastState = ParserState(text: input)
            fastState.enableASCIIFastPathIfPossible()
            let fast = try XCTUnwrap(
                InlineParser.parseStrikethrough(&fastState, configuration: .default),
                input
            )
            XCTAssertEqual(fast, fallback, input)
        }
    }

    func testParallelParsingMatchesSerialForCorrectnessFixtures() {
        let markdowns = ParserCorrectnessFixtures.semanticFixtures.map {
            ($0.name, $0.markdown, $0.configuration)
        } + [
            (
                "expandedBoundaryCorpus",
                ParserBoundaryCorpus.parallelChunkBoundary(repetitions: 12),
                MarkdownConfiguration.github
            )
        ]

        for (name, markdown, configuration) in markdowns {
            let serial = MarkdownParser.parse(markdown, configuration: configuration)
            for chunkSize in [16, 48, 257] {
                let parser = ParallelMarkdownParser(
                    parallelConfig: .init(
                        concurrency: 3,
                        minimumSizeThreshold: 0,
                        chunkSize: chunkSize,
                        preserveOrder: true
                    ),
                    markdownConfig: configuration
                )
                let parallel = parser.parse(markdown)
                ParserCanonicalSnapshot.assertSemanticallyEqual(
                    parallel,
                    serial,
                    "\(name), chunkSize \(chunkSize)"
                )
            }
        }
    }

    private func nonBlankLineRanges(in input: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var lineStart = input.startIndex
        var index = input.startIndex

        while index < input.endIndex {
            if input[index] == "\n" {
                if lineStart < index {
                    ranges.append(lineStart..<index)
                }
                lineStart = input.index(after: index)
            }
            index = input.index(after: index)
        }

        if lineStart < input.endIndex {
            ranges.append(lineStart..<input.endIndex)
        }

        return ranges
    }

    private func reservedUTF8Count(for ranges: [Range<String.Index>], in input: String) -> Int {
        ranges.reduce(0) { partial, range in
            guard let lower = range.lowerBound.samePosition(in: input.utf8),
                  let upper = range.upperBound.samePosition(in: input.utf8) else {
                return partial + input[range].utf8.count
            }
            return partial + input.utf8.distance(from: lower, to: upper)
        }
    }

    private func parseSignature(
        block: MarkdownParser.BlockNode?,
        state: ParserState,
        in input: String
    ) -> String {
        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil"
        let offset = input.distance(from: input.startIndex, to: state.currentIndex)
        return "\(canonical)|line:\(state.line)|column:\(state.column)|offset:\(offset)"
    }

    private func inlineParsePositionSignature(_ state: ParserState, in input: String) -> String {
        let offset = input.distance(from: input.startIndex, to: state.currentIndex)
        return "line:\(state.line)|column:\(state.column)|offset:\(offset)"
    }
}
