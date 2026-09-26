import Foundation
import XCTest
import cmark_gfm
import cmark_gfm_extensions

final class CMarkLinkTests: XCTestCase {
    func testCMarkRendersStrongToHTML() throws {
        let markdown = "**hi**"
        let html = try markdown.withCString { pointer -> String in
            let output = try XCTUnwrap(cmark_markdown_to_html(pointer, strlen(pointer), CMARK_OPT_DEFAULT))
            defer { free(output) }
            return String(cString: output)
        }
        XCTAssertEqual(html, "<p><strong>hi</strong></p>\n")
    }

    func testGFMExtensionsRegister() {
        cmark_gfm_core_extensions_ensure_registered()
        for name in ["table", "strikethrough", "autolink", "tasklist"] {
            XCTAssertNotNil(cmark_find_syntax_extension(name), "missing extension \(name)")
        }
    }
}
