import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

/// A `[3]` chip that links to a page when rendered as plain text.
private struct LinkedCitations: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            var token = GlimmerInlineToken(range: range, kind: "citation", displayText: label, source: label)
            token.url = URL(string: "https://a.example/cite")
            return token
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? { UILabel() }
}

private struct TappableLinkedCitations: GlimmerExtension {
    private let base = LinkedCitations()
    func scan(_ text: String) -> [GlimmerInlineToken] {
        base.scan(text).map { token in
            var tappable = token
            tappable.isTappable = true
            return tappable
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? { UILabel() }
}

@MainActor
final class GlimmerAttributedStringTests: XCTestCase {
    func testTextKeepsEmphasisAndLinks() throws {
        let text = GlimmerView.attributedString(for: "Hello **world** [x](https://a.example)")
        XCTAssertEqual(String(text.characters), "Hello world x")
        let x = try XCTUnwrap(text.range(of: "x"))
        XCTAssertEqual(text[x].link, URL(string: "https://a.example"))
        let world = try XCTUnwrap(text.range(of: "world"))
        XCTAssertTrue(text[world].uiKit.font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertTrue(text.runs.allSatisfy { $0.swiftUI.font != nil && $0.swiftUI.foregroundColor != nil })
    }

    func testImagesAndTheirSpaceAreDropped() {
        let text = GlimmerView.attributedString(for: "Led by ![Acme](https://a.example/a.png) Acme.")
        XCTAssertEqual(String(text.characters), "Led by Acme.")
    }

    func testAnswerOfOnlyAnImageIsEmpty() {
        XCTAssertEqual(GlimmerView.attributedString(for: "![a](https://a.example/a.png)").characters.count, 0)
    }

    func testACodeBlockBecomesMonospacedText() throws {
        let text = GlimmerView.attributedString(for: "```\nlet x = 1\n```")
        XCTAssertEqual(String(text.characters), "let x = 1")
        let code = try XCTUnwrap(text.range(of: "let x = 1"))
        XCTAssertTrue(text[code].uiKit.font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
        XCTAssertNotNil(text[code].swiftUI.font)
    }

    func testATableBecomesTabbedRows() {
        let text = GlimmerView.attributedString(for: "| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(String(text.characters), "a\tb\n1\t2")
        XCTAssertTrue(text.runs.allSatisfy { $0.uiKit.foregroundColor != nil && $0.swiftUI.foregroundColor != nil })
    }

    func testTableCellsKeepChipsLinksAndStyling() throws {
        var configuration = GlimmerConfiguration()
        configuration.extensions = [LinkedCitations()]
        let text = GlimmerView.attributedString(
            for: "| a | b |\n|---|---|\n| see [3] | **bold** [x](https://a.example) |", configuration: configuration)
        XCTAssertEqual(String(text.characters), "a\tb\nsee [3]\tbold x")
        let chip = try XCTUnwrap(text.range(of: "[3]"))
        XCTAssertEqual(text[chip].link, URL(string: "https://a.example/cite"))
        let link = try XCTUnwrap(text.range(of: "x"))
        XCTAssertEqual(text[link].link, URL(string: "https://a.example"))
        let bold = try XCTUnwrap(text.range(of: "bold"))
        XCTAssertTrue(text[bold].uiKit.font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertTrue(text.runs.allSatisfy { $0.swiftUI.font != nil && $0.swiftUI.foregroundColor != nil })
    }

    func testEveryRunHasFontAndColor() {
        var configuration = GlimmerConfiguration()
        configuration.extensions = [LinkedCitations(), GlimmerMentions()]
        let markdown = "> quoted [3] @grace\n\n```\ncode\n```\n\n- [x] done\n- [ ] todo\n\n| a |\n|---|\n| b |"
        let text = GlimmerView.attributedString(for: markdown, configuration: configuration)
        for run in text.runs {
            let shown = String(text[run.range].characters)
            XCTAssertNotNil(run.uiKit.font, "font: \(shown)")
            XCTAssertNotNil(run.uiKit.foregroundColor, "color: \(shown)")
            XCTAssertNotNil(run.swiftUI.font, "swiftUI font: \(shown)")
            XCTAssertNotNil(run.swiftUI.foregroundColor, "swiftUI color: \(shown)")
        }
    }

    func testTaskCheckboxesBecomeText() {
        let text = String(GlimmerView.attributedString(for: "- [x] done\n- [ ] todo").characters)
        XCTAssertTrue(text.contains("\u{2611}\u{FE0E}"))
        XCTAssertTrue(text.contains("\u{2610}"))
        XCTAssertFalse(text.contains("Checked"))
        XCTAssertFalse(text.contains("\u{FFFC}"))
    }

    func testAThematicBreakIsDropped() {
        let text = GlimmerView.attributedString(for: "One\n\n---\n\nTwo")
        XCTAssertFalse(String(text.characters).contains("\u{FFFC}"))
        XCTAssertTrue(String(text.characters).hasPrefix("One"))
        XCTAssertTrue(String(text.characters).hasSuffix("Two"))
    }

    func testAChipBecomesLinkedText() throws {
        var configuration = GlimmerConfiguration()
        configuration.extensions = [LinkedCitations()]
        let text = GlimmerView.attributedString(for: "Source [3] here", configuration: configuration)
        XCTAssertEqual(String(text.characters), "Source [3] here")
        let chip = try XCTUnwrap(text.range(of: "[3]"))
        XCTAssertEqual(text[chip].link, URL(string: "https://a.example/cite"))
        XCTAssertNotNil(text[chip].swiftUI.font)
    }

    func testATappableChipBecomesLinkedTextWithoutAnAttachmentCharacter() throws {
        var configuration = GlimmerConfiguration()
        configuration.extensions = [TappableLinkedCitations()]
        let text = GlimmerView.attributedString(for: "Source [3] here", configuration: configuration)
        XCTAssertEqual(String(text.characters), "Source [3] here")
        XCTAssertFalse(String(text.characters).contains("\u{FFFC}"))
        let chip = try XCTUnwrap(text.range(of: "[3]"))
        XCTAssertEqual(text[chip].link, URL(string: "https://a.example/cite"))
        for run in text.runs { XCTAssertNotEqual(run.link?.scheme, "glimmer-token") }
    }

    func testATappableTextTokenLosesItsInternalLink() throws {
        var configuration = GlimmerConfiguration()
        configuration.extensions = [GlimmerMentions()]
        let text = GlimmerView.attributedString(for: "Ask @grace now", configuration: configuration)
        XCTAssertEqual(String(text.characters), "Ask @grace now")
        let mention = try XCTUnwrap(text.range(of: "@grace"))
        XCTAssertNil(text[mention].link)
    }

    func testALargerDynamicTypeSizeGivesALargerBodyFont() {
        func bodyFontSize(_ size: DynamicTypeSize) -> CGFloat {
            let text = GlimmerView.attributedString(for: "Body", dynamicTypeSize: size)
            return text.runs.first?.uiKit.font?.pointSize ?? 0
        }
        let small = bodyFontSize(.xSmall)
        XCTAssertGreaterThan(small, 0)
        XCTAssertGreaterThan(bodyFontSize(.accessibility3), small)
    }
}
