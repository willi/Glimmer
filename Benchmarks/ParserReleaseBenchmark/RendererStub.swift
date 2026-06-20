import SwiftUI

public struct MarkdownRenderer {
    public init() {}

    public mutating func render(
        blocks: [MarkdownParser.BlockNode],
        configuration: MarkdownConfiguration
    ) -> AttributedString {
        AttributedString("")
    }
}
