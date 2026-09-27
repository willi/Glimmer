import UIKit
import XCTest
@testable import Glimmer

final class GlimmerThemeTests: XCTestCase {
    func testDefaultHasSixShrinkingHeadingSizes() {
        let sizes = GlimmerTheme.default.headingFonts.map(\.pointSize)
        XCTAssertEqual(sizes.count, 6)
        XCTAssertEqual(sizes, sizes.sorted(by: >))
    }

    func testHeadingLevelIsClamped() {
        let theme = GlimmerTheme.default
        XCTAssertEqual(theme.headingFont(level: 0), theme.headingFonts[0])
        XCTAssertEqual(theme.headingFont(level: 9), theme.headingFonts[5])
    }

    func testScalingFollowsDynamicType() {
        let theme = GlimmerTheme.default
        let large = theme.scaled(for: UITraitCollection(preferredContentSizeCategory: .large))
        let huge = theme.scaled(for: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
        XCTAssertGreaterThan(huge.bodyFont.pointSize, large.bodyFont.pointSize)
        XCTAssertGreaterThan(huge.codeFont.pointSize, large.codeFont.pointSize)
        XCTAssertGreaterThan(huge.headingFonts[0].pointSize, large.headingFonts[0].pointSize)
    }

    func testEachRoleScalesOnItsOwnTextStyleCurve() {
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let base = GlimmerTheme.default
        let scaled = base.scaled(for: traits)
        let titleCurve = UIFontMetrics(forTextStyle: .title1).scaledFont(for: base.headingFonts[0], compatibleWith: traits)
        let bodyCurve = UIFontMetrics(forTextStyle: .body).scaledFont(for: base.headingFonts[0], compatibleWith: traits)
        XCTAssertEqual(scaled.headingFonts[0].pointSize, titleCurve.pointSize, accuracy: 0.01)
        XCTAssertLessThan(scaled.headingFonts[0].pointSize, bodyCurve.pointSize, "headings grow less than body text at accessibility sizes")
        XCTAssertEqual(scaled.bodyFont.pointSize,
                       UIFontMetrics(forTextStyle: .body).scaledFont(for: base.bodyFont, compatibleWith: traits).pointSize, accuracy: 0.01)
    }

    func testSpacingScalesWithDynamicType() {
        let theme = GlimmerTheme.default
        let large = theme.scaled(for: UITraitCollection(preferredContentSizeCategory: .large))
        let huge = theme.scaled(for: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
        XCTAssertGreaterThan(huge.listIndent, large.listIndent)
        XCTAssertGreaterThan(huge.quoteIndent, large.quoteIndent)
        XCTAssertGreaterThan(huge.paragraphSpacing, large.paragraphSpacing)
        XCTAssertGreaterThan(huge.blockSpacing, large.blockSpacing)
        XCTAssertGreaterThan(huge.embedPadding, large.embedPadding)
    }

    func testColorsAdaptToDarkMode() {
        let color = GlimmerTheme.default.textColor
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotEqual(light, dark)
    }

    func testAttributeKeysAreNamespaced() {
        XCTAssertEqual(NSAttributedString.Key.glimmerInlineCode.rawValue, "glimmer.inlineCode")
        XCTAssertEqual(NSAttributedString.Key.glimmerQuoteDepth.rawValue, "glimmer.quoteDepth")
        XCTAssertEqual(NSAttributedString.Key.glimmerListMarker.rawValue, "glimmer.listMarker")
        XCTAssertEqual(NSAttributedString.Key.glimmerSource.rawValue, "glimmer.source")
        XCTAssertEqual(NSAttributedString.Key.glimmerQuoteContinues.rawValue, "glimmer.quoteContinues")
        XCTAssertEqual(NSAttributedString.Key.glimmerMarkdownPrefix.rawValue, "glimmer.markdownPrefix")
        XCTAssertEqual(NSAttributedString.Key.glimmerListTightness.rawValue, "glimmer.listTightness")
        XCTAssertEqual(NSAttributedString.Key.glimmerListOpens.rawValue, "glimmer.listOpens")
        XCTAssertEqual(NSAttributedString.Key.glimmerStrong.rawValue, "glimmer.strong")
        XCTAssertEqual(NSAttributedString.Key.glimmerEmphasis.rawValue, "glimmer.emphasis")
    }

    func testHeadingFontFallsBackToBodyWithoutHeadingFonts() {
        var theme = GlimmerTheme.default
        theme.headingFonts = []
        XCTAssertEqual(theme.headingFont(level: 2), theme.bodyFont)
    }
}
