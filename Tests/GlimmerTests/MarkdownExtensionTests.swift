import XCTest
@testable import Glimmer

final class MarkdownExtensionTests: XCTestCase {
    func testInlineExtensionParsesCustomToken() {
        let extensionDefinition = MarkdownExtension(
            id: "example.badges",
            version: 1,
            parseInline: { context in
                guard context.remaining.hasPrefix("::vip::") else { return nil }
                return MarkdownExtensionInlineMatch(
                    name: "badge",
                    literal: "::vip::",
                    fields: ["kind": "vip"],
                    endIndex: context.index(offsetBy: 7)
                )
            }
        )

        let configuration = MarkdownConfiguration.default.addingExtension(extensionDefinition)
        let blocks = MarkdownParser.parse("hello ::vip:: user", configuration: configuration)

        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected a paragraph")
        }

        XCTAssertEqual(inlines, [
            .text("hello "),
            .extensionInline(
                MarkdownParser.ExtensionNode(
                    namespace: "example.badges",
                    name: "badge",
                    literal: "::vip::",
                    fields: ["kind": "vip"]
                )
            ),
            .text(" user")
        ])
    }

    func testExtensionRendererCanOverrideInlineFallback() {
        let extensionDefinition = MarkdownExtension(
            id: "example.badges",
            version: 1,
            parseInline: { context in
                guard context.remaining.hasPrefix("::vip::") else { return nil }
                return MarkdownExtensionInlineMatch(
                    name: "badge",
                    literal: "::vip::",
                    fields: ["kind": "vip"],
                    endIndex: context.index(offsetBy: 7)
                )
            },
            renderInline: { node in
                guard node.name == "badge", let kind = node.fields["kind"] else { return nil }
                return AttributedString("[\(kind)]")
            }
        )

        let configuration = MarkdownConfiguration.default.addingExtension(extensionDefinition)
        let rendered = MarkdownParser.parseToAttributedString("hello ::vip::", configuration: configuration)

        XCTAssertEqual(String(rendered.characters), "hello [vip]")
    }

    func testInlineExtensionFallsBackToLiteralWhenNoRendererIsProvided() {
        let extensionDefinition = MarkdownExtension(
            id: "example.badges",
            version: 1,
            parseInline: { context in
                guard context.remaining.hasPrefix("::vip::") else { return nil }
                return MarkdownExtensionInlineMatch(
                    name: "badge",
                    literal: "::vip::",
                    fields: [:],
                    endIndex: context.index(offsetBy: 7)
                )
            }
        )

        let configuration = MarkdownConfiguration.default.addingExtension(extensionDefinition)
        let rendered = MarkdownParser.parseToAttributedString("hello ::vip::", configuration: configuration)

        XCTAssertEqual(String(rendered.characters), "hello ::vip::")
    }

    func testInlineExtensionDoesNotParseInsideCodeSpans() {
        let extensionDefinition = MarkdownExtension(
            id: "example.badges",
            version: 1,
            parseInline: { context in
                guard context.remaining.hasPrefix("::vip::") else { return nil }
                return MarkdownExtensionInlineMatch(
                    name: "badge",
                    literal: "::vip::",
                    fields: [:],
                    endIndex: context.index(offsetBy: 7)
                )
            }
        )

        let configuration = MarkdownConfiguration.default.addingExtension(extensionDefinition)
        let blocks = MarkdownParser.parse("show `::vip::`", configuration: configuration)

        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected a paragraph")
        }

        XCTAssertEqual(inlines, [
            .text("show "),
            .code("::vip::")
        ])
    }

    func testExtensionPreprocessorRunsBeforeParsing() {
        let extensionDefinition = MarkdownExtension(
            id: "example.preprocess",
            version: 1,
            preprocess: { source in
                source.replacingOccurrences(of: "{break}", with: "\n\n")
            }
        )

        let configuration = MarkdownConfiguration.default.addingExtension(extensionDefinition)
        let blocks = MarkdownParser.parse("first{break}second", configuration: configuration)

        XCTAssertEqual(blocks.count, 2)
        guard case .paragraph(let firstInlines) = blocks[0],
              case .paragraph(let secondInlines) = blocks[1] else {
            return XCTFail("Expected two paragraphs")
        }
        XCTAssertEqual(firstInlines, [.text("first")])
        XCTAssertEqual(secondInlines, [.text("second")])
    }
}
