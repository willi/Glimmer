import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Best-effort mapping from SwiftUI `Font` roles to platform-specific font.
/// This relies on the string description of `Font` which is stable for common roles.
enum FontMapping {
    #if canImport(UIKit)
    static func platformFont(from font: Font) -> UIFont {
        let raw = String(describing: font)

        // Custom named font (e.g. Font.custom("Haffer-Regular", size: 16)). Resolve
        // it directly; otherwise it falls through to the system text-style branch
        // below and the app's brand font is silently dropped in image-bearing
        // blocks (which render through this UIKit path).
        if let name = quotedValue(in: raw, afterKey: "name:"),
           let size = doubleValue(in: raw, afterKey: "size:"),
           size > 0,
           let custom = UIFont(name: name, size: size) {
            return custom
        }

        let desc = raw.lowercased()
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

    /// The first double-quoted substring that follows `key` (e.g. the value of
    /// `name: "Haffer-Regular"` in a `Font` description). Case-preserving.
    static func quotedValue(in source: String, afterKey key: String) -> String? {
        guard let keyRange = source.range(of: key) else { return nil }
        let tail = source[keyRange.upperBound...]
        guard let open = tail.firstIndex(of: "\"") else { return nil }
        let valueStart = tail.index(after: open)
        guard let close = tail[valueStart...].firstIndex(of: "\"") else { return nil }
        let value = String(tail[valueStart..<close])
        return value.isEmpty ? nil : value
    }

    /// The first numeric value that follows `key` (e.g. `size: 16.0`).
    static func doubleValue(in source: String, afterKey key: String) -> Double? {
        guard let keyRange = source.range(of: key) else { return nil }
        let scanner = Scanner(string: String(source[keyRange.upperBound...]))
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        return scanner.scanDouble()
    }
}
