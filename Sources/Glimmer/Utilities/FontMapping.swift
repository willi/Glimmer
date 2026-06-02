import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Best-effort mapping from SwiftUI `Font` roles to platform-specific font.
/// This relies on the string description of `Font` which is stable for common roles.
enum FontMapping {
    #if canImport(UIKit)
    static func platformFont(from font: Font) -> UIFont {
        let desc = String(describing: font).lowercased()
        let base: UIFont
        if desc.contains("largetitle") {
            base = .preferredFont(forTextStyle: .largeTitle)
        } else if desc.contains("title3") {
            base = .preferredFont(forTextStyle: .title3)
        } else if desc.contains("title2") {
            base = .preferredFont(forTextStyle: .title2)
        } else if desc.contains("title") {
            base = .preferredFont(forTextStyle: .title1)
        } else if desc.contains("headline") {
            base = .preferredFont(forTextStyle: .headline)
        } else if desc.contains("subheadline") {
            base = .preferredFont(forTextStyle: .subheadline)
        } else if desc.contains("footnote") {
            base = .preferredFont(forTextStyle: .footnote)
        } else if desc.contains("caption2") {
            base = .preferredFont(forTextStyle: .caption2)
        } else if desc.contains("caption") {
            base = .preferredFont(forTextStyle: .caption1)
        } else {
            base = .preferredFont(forTextStyle: .body)
        }

        // Handle monospaced hint
        if desc.contains("monospaced") {
            return .monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
        }
        return base
    }
    #endif
}
