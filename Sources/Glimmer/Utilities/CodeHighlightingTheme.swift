
import SwiftUI

public struct CodeHighlightingTheme: Hashable, Sendable {
    public let comment: Color
    public let string: Color
    public let number: Color
    public let keyword: Color
    public let type: Color
    public let background: Color

    public init(comment: Color, string: Color, number: Color, keyword: Color, type: Color, background: Color) {
        self.comment = comment
        self.string = string
        self.number = number
        self.keyword = keyword
        self.type = type
        self.background = background
    }

    // Xcode 16 Light Theme
    public static let light = CodeHighlightingTheme(
        comment: Color(hex: "#5D6C79"),
        string: Color(hex: "#D12F1B"),
        number: Color(hex: "#1C00CF"),
        keyword: Color(hex: "#AD3DA4"),
        type: Color(hex: "#0B4F79"),
        background: Color(hex: "#FFFFFF")
    )

    // Xcode 16 Dark Theme
    public static let dark = CodeHighlightingTheme(
        comment: Color(hex: "#6C7986"),
        string: Color(hex: "#FC6A5D"),
        number: Color(hex: "#D0BF69"),
        keyword: Color(hex: "#FC5FA3"),
        type: Color(hex: "#5DD8FF"),
        background: Color(hex: "#1F1F24")
    )
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}






