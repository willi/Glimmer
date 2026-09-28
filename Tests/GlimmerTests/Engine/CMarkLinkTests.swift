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

    /// Glimmer's patch: a backslash escape is flagged where it is parsed, and stays its own text node. Punctuation that
    /// only looks like one (one character spanning two columns, as `.` does before trimmed trailing spaces) is not.
    func testOnlyABackslashMarksAnEscape() throws {
        let markdown = "*foo*. \nNot \\@ada or \\:rocket: here."
        let document = try XCTUnwrap(markdown.withCString { cmark_parse_document($0, strlen($0), CMARK_OPT_DEFAULT) })
        defer { cmark_node_free(document) }
        var escaped: [String] = []
        var texts: [String] = []
        let iterator = cmark_iter_new(document)
        defer { cmark_iter_free(iterator) }
        while cmark_iter_next(iterator) != CMARK_EVENT_DONE {
            guard let node = cmark_iter_get_node(iterator), cmark_node_get_type(node) == CMARK_NODE_TEXT,
                  cmark_iter_get_event_type(iterator) == CMARK_EVENT_ENTER else { continue }
            let literal = String(cString: cmark_node_get_literal(node))
            texts.append(literal)
            if cmark_node_is_escaped_text(node) != 0 { escaped.append(literal) }
        }
        XCTAssertEqual(escaped, ["@", ":"], "texts: \(texts)")
        XCTAssertTrue(texts.contains("."))
    }
}
