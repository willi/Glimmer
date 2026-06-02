import SwiftUI

/// Shared utilities for formatting list markers and styles
public struct ListFormatting {
    
    /// Generates a roman numeral string for the given number
    public static func romanNumeral(_ number: Int) -> String {
        let values = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
                      (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
                      (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var result = ""
        var num = number
        
        for (value, numeral) in values {
            let count = num / value
            if count > 0 {
                result += String(repeating: numeral, count: count)
                num -= count * value
            }
        }
        
        return result.lowercased()
    }
    
    /// Generates the appropriate list marker for ordered and unordered lists
    public static func listMarker(ordered: Bool, index: Int, depth: Int) -> String {
        if ordered {
            switch depth % 4 {
            case 0:
                return "\(index + 1)."
            case 1:
                return "\(Character(UnicodeScalar(97 + index)!))."
            case 2:
                return "\(romanNumeral(index + 1))."
            case 3:
                return "\(index + 1))"
            default:
                return "\(index + 1)."
            }
        } else {
            switch depth % 4 {
            case 0:
                return "•"
            case 1:
                return "◦"
            case 2:
                return "▪"
            case 3:
                return "▫"
            default:
                return "•"
            }
        }
    }
    
    /// Returns the appropriate font for list markers based on list type and depth
    public static func listMarkerFont(ordered: Bool, depth: Int, baseFont: Font) -> Font {
        // For unordered lists, make bullets larger for levels 1, 2, 5, and 6
        if !ordered && (depth == 0 || depth == 1 || depth == 4 || depth == 5) {
            // Levels 1 and 2 (depth 0 and 1) get bigger bullets
            // Levels 5 and 6 (depth 4 and 5) get slightly bigger bullets
            if depth <= 1 {
                return .system(size: 22, weight: .medium)
            } else {
                return .system(size: 20, weight: .medium)
            }
        }
        return baseFont
    }
}