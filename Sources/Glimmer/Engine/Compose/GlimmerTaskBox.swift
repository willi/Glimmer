/// The characters that stand for a task item's box in plain text, where the engine's box image can't go.
enum GlimmerTaskBox {
    /// ☑︎, in text presentation so it takes the text's colour rather than an emoji's.
    static let checked = "\u{2611}\u{FE0E}"
    /// ☐.
    static let unchecked = "\u{2610}"

    static func character(isChecked: Bool) -> String { isChecked ? checked : unchecked }
}
