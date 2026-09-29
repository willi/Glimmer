import Foundation

/// The shape of images inside text, including images supplied by extensions. Standalone images use the theme.
public enum GlimmerInlineImageShape: Hashable, Sendable {
    /// Crops the image to fill a circle as tall as the surrounding line.
    case circle
    /// Fits the entire image inside a line-height square with the given corner radius in points. Use zero for square corners.
    case roundedRectangle(cornerRadius: CGFloat)
}
