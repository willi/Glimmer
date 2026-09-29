import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTextTests: XCTestCase {
    func testMenuHooksDeliverSelectionsAndLinksAndUpdateInPlace() throws {
        let markdown = "Hello [docs](https://example.com)"
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        var selected: (owner: String, selection: GlimmerSelection)?
        var linked: (owner: String, url: URL)?

        func text(owner: String) -> GlimmerText {
            GlimmerText(
                markdown,
                editMenuActions: { selection in
                    selected = (owner, selection)
                    return [UIAction(title: "\(owner) selection") { _ in }]
                },
                linkMenuActions: { url in
                    linked = (owner, url)
                    return [UIAction(title: "\(owner) link") { _ in }]
                }
            )
        }

        let host = UIHostingController(rootView: text(owner: "Original").frame(width: 320))
        let window = hostInWindow(host.view, width: 320, height: 400)
        let view = try XCTUnwrap(findSubview(GlimmerView.self, in: host.view))

        for owner in ["Original", "Replacement"] {
            if owner == "Replacement" {
                host.rootView = text(owner: owner).frame(width: 320)
                settle(host.view)
                XCTAssertTrue(findSubview(GlimmerView.self, in: host.view) === view, "updates reuse the existing renderer")
            }
            selected = nil
            linked = nil
            let range = NSRange(location: 6, length: 4)
            let menu = try XCTUnwrap(view.textView(view.textView, editMenuForTextIn: range, suggestedActions: []))
            XCTAssertEqual(menu.children.compactMap { ($0 as? UIAction)?.title }, ["\(owner) selection"])
            XCTAssertEqual(selected?.owner, owner)
            XCTAssertEqual(selected?.selection.range, range)
            XCTAssertEqual(selected?.selection.plainText, "docs")
            XCTAssertEqual(selected?.selection.markdown, "[docs](https://example.com)")

            let linkMenu = view.linkMenu(for: url, defaultMenu: UIMenu(children: []))
            XCTAssertEqual(linkMenu.children.compactMap { ($0 as? UIAction)?.title }, ["\(owner) link"])
            XCTAssertEqual(linked?.owner, owner)
            XCTAssertEqual(linked?.url, url)
        }

        host.rootView = GlimmerText(markdown).frame(width: 320)
        settle(host.view)
        XCTAssertTrue(findSubview(GlimmerView.self, in: host.view) === view)
        selected = nil
        linked = nil
        XCTAssertNil(view.textView(view.textView, editMenuForTextIn: NSRange(location: 6, length: 4), suggestedActions: []))
        XCTAssertTrue(view.linkMenu(for: url, defaultMenu: UIMenu(children: [])).children.isEmpty)
        XCTAssertNil(selected)
        XCTAssertNil(linked)
        _ = window
    }
}
