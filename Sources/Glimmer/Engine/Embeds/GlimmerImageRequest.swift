import Foundation

/// An image URL and the pixel dimensions needed for display. Clipping is applied by the image view.
public struct GlimmerImageRequest: Sendable {
    /// How much of the source must be prepared to cover the requested size.
    public enum ContentMode: Hashable, Sendable {
        /// Prepares an image that fits entirely inside the requested size.
        case aspectFit
        /// Prepares enough pixels to fill the requested size, preserving the source's aspect ratio.
        case aspectFill
    }

    /// The original URL, including any query parameters.
    public var url: URL
    /// Display size in pixels, not points. `nil` requests the original size. Images are never upscaled.
    public var targetPixelSize: CGSize?
    /// Whether the image will fit inside or fill the requested size.
    public var contentMode: ContentMode

    /// Creates a request. Invalid or empty dimensions are treated as an original-size request.
    public init(url: URL, targetPixelSize: CGSize? = nil, contentMode: ContentMode = .aspectFit) {
        self.url = url
        self.targetPixelSize = targetPixelSize
        self.contentMode = contentMode
    }

    var validPixelSize: CGSize? {
        guard let size = targetPixelSize, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}
