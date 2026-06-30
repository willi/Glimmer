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
        if let provider = providerBase(from: font) {
            if let namedFont = namedProviderFont(provider) {
                return namedFont
            }
            if let systemFont = systemProviderFont(provider) {
                return systemFont
            }
            if let textStyleFont = textStyleProviderFont(provider) {
                return textStyleFont
            }
        }

        let raw = String(describing: font)
        let desc = raw.lowercased()
        let base = preferredFont(matching: desc)

        // Handle monospaced hint
        if desc.contains("monospaced") {
            return .monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
        }
        return base
    }

    private static func providerBase(from font: Font) -> Any? {
        let fontMirror = Mirror(reflecting: font)
        guard let provider = fontMirror.children.first(where: { $0.label == "provider" })?.value else {
            return nil
        }
        return Mirror(reflecting: provider).children.first(where: { $0.label == "base" })?.value
    }

    private static func namedProviderFont(_ provider: Any) -> UIFont? {
        guard String(describing: type(of: provider)).contains("NamedProvider"),
              let name = childValue(String.self, named: "name", in: provider),
              let size = childCGFloat(named: "size", in: provider),
              size > 0 else {
            return nil
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }

    private static func systemProviderFont(_ provider: Any) -> UIFont? {
        guard String(describing: type(of: provider)).contains("SystemProvider") else {
            return nil
        }
        if let size = childCGFloat(named: "size", in: provider), size > 0 {
            if String(describing: child(named: "design", in: provider) ?? "").lowercased().contains("monospaced") {
                return .monospacedSystemFont(ofSize: size, weight: .regular)
            }
            return .systemFont(ofSize: size)
        }
        if let style = optionalDescription(named: "textStyle", in: provider) {
            return preferredFont(matching: style)
        }
        return .preferredFont(forTextStyle: .body)
    }

    private static func textStyleProviderFont(_ provider: Any) -> UIFont? {
        guard String(describing: type(of: provider)).contains("TextStyleProvider"),
              let style = child(named: "style", in: provider) else {
            return nil
        }
        return preferredFont(matching: String(describing: style))
    }

    private static func preferredFont(matching description: String) -> UIFont {
        let desc = description.lowercased()
        if desc.contains("largetitle") {
            return .preferredFont(forTextStyle: .largeTitle)
        } else if desc.contains("title3") {
            return .preferredFont(forTextStyle: .title3)
        } else if desc.contains("title2") {
            return .preferredFont(forTextStyle: .title2)
        } else if desc.contains("title") {
            return .preferredFont(forTextStyle: .title1)
        } else if desc.contains("headline") {
            return .preferredFont(forTextStyle: .headline)
        } else if desc.contains("subheadline") {
            return .preferredFont(forTextStyle: .subheadline)
        } else if desc.contains("footnote") {
            return .preferredFont(forTextStyle: .footnote)
        } else if desc.contains("caption2") {
            return .preferredFont(forTextStyle: .caption2)
        } else if desc.contains("caption") {
            return .preferredFont(forTextStyle: .caption1)
        }
        return .preferredFont(forTextStyle: .body)
    }
    #endif

    private static func child(named name: String, in value: Any) -> Any? {
        Mirror(reflecting: value).children.first(where: { $0.label == name })?.value
    }

    private static func childValue<T>(_: T.Type, named name: String, in value: Any) -> T? {
        child(named: name, in: value) as? T
    }

    private static func childCGFloat(named name: String, in value: Any) -> CGFloat? {
        if let cgFloat = child(named: name, in: value) as? CGFloat {
            return cgFloat
        }
        if let double = child(named: name, in: value) as? Double {
            return CGFloat(double)
        }
        return nil
    }

    private static func optionalDescription(named name: String, in value: Any) -> String? {
        guard let optional = child(named: name, in: value) else { return nil }
        let mirror = Mirror(reflecting: optional)
        guard mirror.displayStyle == .optional,
              let wrapped = mirror.children.first?.value else {
            return nil
        }
        return String(describing: wrapped)
    }
}
