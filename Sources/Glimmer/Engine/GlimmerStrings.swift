import Foundation

/// The words Glimmer itself says, from `Resources/Localizable.xcstrings`. Safe off the main actor: the composer reads
/// the checkbox words on the view's worker.
enum GlimmerStrings {
    static let bundle = Bundle.module

    static var code: String {
        String(localized: "Code", bundle: .module, comment: "VoiceOver label for a code block without a language.")
    }

    static func code(language: String) -> String {
        String(localized: "Code, \(language)", bundle: .module, comment: "VoiceOver label for a code block; the argument is its language.")
    }

    static var copyCode: String {
        String(localized: "Copy code", bundle: .module, comment: "VoiceOver label for a code block's Copy button.")
    }

    /// Read before a checked task item; the trailing comma and space separate it from the item's text.
    static var checked: String {
        String(localized: "Checked, ", bundle: .module, comment: "VoiceOver reads this before a checked task-list item.")
    }

    /// Read before an unchecked task item.
    static var unchecked: String {
        String(localized: "Unchecked, ", bundle: .module, comment: "VoiceOver reads this before an unchecked task-list item.")
    }
}
