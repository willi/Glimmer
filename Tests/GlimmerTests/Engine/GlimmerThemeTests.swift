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
    }
}
