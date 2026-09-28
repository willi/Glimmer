import Foundation
import XCTest

/// One example from a cmark spec file: markdown input and the reference HTML.
struct SpecExample {
    let file: String
    let number: Int
    let markdown: String
    let html: String
}

enum SpecExamples {
    /// Loads `Fixtures/CommonMark/<name>.txt`, which uses the cmark spec format
    /// (32-backtick "example" fences, `.` between markdown and HTML, `→` for tabs).
    static func load(_ name: String) throws -> [SpecExample] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures/CommonMark"),
            "missing fixture \(name).txt"
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        let fence = String(repeating: "`", count: 32)
        var examples: [SpecExample] = []
        var markdown: [String] = []
        var html: [String] = []
        var state = 0 // 0 outside, 1 reading markdown, 2 reading html
        for line in text.components(separatedBy: "\n") {
            switch state {
            case 0 where line.hasPrefix(fence + " example"):
                state = 1
                markdown = []
                html = []
            case 1 where line == ".":
                state = 2
            case 1:
                markdown.append(line)
            case 2 where line == fence:
                examples.append(SpecExample(
                    file: name,
                    number: examples.count + 1,
                    markdown: markdown.joined(separator: "\n").replacingOccurrences(of: "→", with: "\t") + "\n",
                    html: html.joined(separator: "\n")
                ))
                state = 0
            case 2:
                html.append(line)
            default:
                break
            }
        }
        return examples
    }
}
