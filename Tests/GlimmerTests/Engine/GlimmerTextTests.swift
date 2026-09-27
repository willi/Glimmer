import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTextTests: XCTestCase {
    func testMenuHooksReachTheView() throws {
        let text = GlimmerText(
            "Hello [docs](https://example.com)",
            editMenuActions: { _ in [UIAction(title: "Ask") { _ in }] },
            linkMenuActions: { _ in [UIAction(title: "Open in App") { _ in }] }
        )
        let host = UIHostingController(rootView: text.frame(width: 320))
        let window = hostInWindow(host.view, width: 320, height: 400)
        let view = try XCTUnwrap(findSubview(GlimmerView.self, in: host.view))
        XCTAssertNotNil(view.editMenuActions)
        XCTAssertNotNil(view.linkMenuActions)
        _ = window
    }
}
