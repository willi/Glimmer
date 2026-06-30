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
}
#endif
