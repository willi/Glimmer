import SwiftUI
import XCTest
@testable import Glimmer

#if canImport(UIKit)
import UIKit

final class FontMappingTests: XCTestCase {
    func testNamedProviderUsesConfiguredPointSize() {
        let font = Font.custom("Missing-Test-Font", size: 16)

        let platformFont = FontMapping.platformFont(from: font)

        XCTAssertEqual(platformFont.pointSize, 16, accuracy: 0.01)
    }

    func testSystemProviderUsesConfiguredPointSize() {
        let font = Font.system(size: 14)

        let platformFont = FontMapping.platformFont(from: font)

        XCTAssertEqual(platformFont.pointSize, 14, accuracy: 0.01)
    }

    func testTextStyleProviderStillUsesPreferredTextStyle() {
        let font = Font.body

        let platformFont = FontMapping.platformFont(from: font)

        XCTAssertEqual(
            platformFont.pointSize,
            UIFont.preferredFont(forTextStyle: .body).pointSize,
            accuracy: 0.01
        )
    }

    @MainActor
    func testInlineImageRendererAppliesZeroKernToTextRuns() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/avatar.png"))
        let renderer = InlineImageRenderer(configuration: .default, baseFont: Font.custom("Missing-Test-Font", size: 16))
        let rendered = renderer.render([
            .text("For growth, talk to "),
            .image(url: url, alt: "avatar", title: nil),
            .text(" Casey Winters")
        ])

        var textRunCount = 0
        rendered.enumerateAttributes(in: NSRange(location: 0, length: rendered.length), options: []) { attributes, _, _ in
            if attributes[.attachment] == nil {
                textRunCount += 1
                let kern = attributes[.kern] as? NSNumber
                XCTAssertNotNil(kern)
                XCTAssertEqual(kern?.doubleValue ?? .nan, 0, accuracy: 0.01)
            } else {
                XCTAssertNil(attributes[.kern])
            }
        }

        XCTAssertGreaterThanOrEqual(textRunCount, 2)
    }
}
#endif
