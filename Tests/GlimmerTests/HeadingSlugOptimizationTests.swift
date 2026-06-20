import Foundation
import XCTest
@testable import Glimmer

final class HeadingSlugOptimizationTests: XCTestCase {
    func testRangeSlugificationMatchesPreviousStringSemantics() {
        let cases: [(heading: String, expected: String)] = [
            ("Mixed Heading! Value 42", "mixed-heading-value-42"),
            ("  ---Hello---  ", "hello"),
            ("Tabs\tAnd   Spaces", "tabs-and-spaces"),
            ("Symbols !@#$%^&*() stay out", "symbols-stay-out"),
            ("Über Café 123", "ber-caf-123"),
            ("---", ""),
            ("", "")
        ]

        for testCase in cases {
            let source = "prefix::\(testCase.heading)::suffix"
            let start = source.range(of: "::")!.upperBound
            let end = source.range(of: "::suffix")!.lowerBound
            let range = start..<end

            XCTAssertEqual(previousStringSlug(testCase.heading), testCase.expected, testCase.heading)
            XCTAssertEqual(
                ParsingHelpers.slugifyHeading(in: source, range: range),
                previousStringSlug(String(source[range])),
                testCase.heading
            )
            XCTAssertEqual(ParsingHelpers.slugifyHeading(in: source, range: range), testCase.expected)
        }
    }

    func testParserHeadingIDsStayStableWithRangeSlugification() {
        let atx = MarkdownParser.parse("# Mixed Heading! Value 42 ###")
        guard case .heading(let atxLevel, _, let atxID) = atx.first else {
            return XCTFail("Expected ATX heading")
        }
        XCTAssertEqual(atxLevel, 1)
        XCTAssertEqual(atxID, "mixed-heading-value-42")

        let setext = MarkdownParser.parse(
            """
            Über Café 123
            =============
            """
        )
        guard case .heading(let setextLevel, _, let setextID) = setext.first else {
            return XCTFail("Expected setext heading")
        }
        XCTAssertEqual(setextLevel, 1)
        XCTAssertEqual(setextID, "ber-caf-123")
    }

    func testOptimization64_RangeHeadingSlugificationAvoidsHeadingStringCopy() throws {
        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeHeadingSlugBenchmarkInputs(count: 120_000)

        let copied = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let heading = String(input.source[input.range])
                    checksum &+= previousStringSlug(heading).utf8.count
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= ParsingHelpers.slugifyHeading(in: input.source, range: input.range).utf8.count
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] heading slug copied string: \(formatMilliseconds(copied)) ms " +
            "range-backed: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(copied / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            copied,
            "Heading ID slugification should avoid materializing heading text before slugging."
        )
        #endif
    }

    private struct HeadingSlugBenchmarkInput {
        let source: String
        let range: Range<String.Index>
    }

    private func makeHeadingSlugBenchmarkInputs(count: Int) -> [HeadingSlugBenchmarkInput] {
        var inputs: [HeadingSlugBenchmarkInput] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            let heading: String
            switch index % 5 {
            case 0:
                heading = "Mixed Heading! Value \(index) ###"
            case 1:
                heading = "Tabs\tAnd   Spaces \(index)"
            case 2:
                heading = "---Symbols !@#$%^&*() \(index)---"
            case 3:
                heading = "Über Café \(index)"
            default:
                heading = "Repository apple/swift issue #\(index) with @octocat"
            }

            let source = "prefix \(index)::\(heading)::suffix \(index)"
            let start = source.range(of: "::")!.upperBound
            let end = source.range(of: "::suffix")!.lowerBound
            inputs.append(HeadingSlugBenchmarkInput(source: source, range: start..<end))
        }

        return inputs
    }

    private func previousStringSlug(_ text: String) -> String {
        if text.isEmpty { return "" }
        var out = String()
        out.reserveCapacity(text.count)
        var prevWasHyphen = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39:
                out.unicodeScalars.append(scalar)
                prevWasHyphen = false
            case 0x41...0x5A:
                out.unicodeScalars.append(UnicodeScalar(scalar.value + 0x20)!)
                prevWasHyphen = false
            case 0x61...0x7A:
                out.unicodeScalars.append(scalar)
                prevWasHyphen = false
            case 0x20, 0x09:
                if !prevWasHyphen {
                    out.append("-")
                    prevWasHyphen = true
                }
            case 0x2D:
                if !prevWasHyphen {
                    out.append("-")
                    prevWasHyphen = true
                }
            default:
                continue
            }
        }
        while out.first == "-" { out.removeFirst() }
        while out.last == "-" { out.removeLast() }
        return out
    }

    private func timed(_ block: () -> Void) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return CFAbsoluteTimeGetCurrent() - start
    }

    private func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private func formatMilliseconds(_ value: TimeInterval) -> String {
        String(format: "%.2f", value * 1000)
    }

    private func formatRatio(_ value: TimeInterval) -> String {
        String(format: "%.2f", value)
    }
}
