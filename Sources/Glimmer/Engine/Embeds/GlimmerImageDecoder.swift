import ImageIO
import UIKit

/// Serializes image preparation off the main thread so concurrent downloads do not create a decoding memory spike.
actor GlimmerImageDecoder {
    func image(data: Data, request: GlimmerImageRequest) throws -> UIImage {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw URLError(.cannotDecodeContentData)
        }
        var sourceSize = CGSize(width: width.doubleValue, height: height.doubleValue)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            sourceSize = CGSize(width: sourceSize.height, height: sourceSize.width)
        }
        guard sourceSize.width > 0, sourceSize.height > 0 else { throw URLError(.cannotDecodeContentData) }
        var ratio: CGFloat = 1
        if let target = request.validPixelSize {
            let x = target.width / sourceSize.width
            let y = target.height / sourceSize.height
            ratio = min(1, request.contentMode == .aspectFill ? max(x, y) : min(x, y))
        }
        let maxPixels = max(1, ceil(max(sourceSize.width, sourceSize.height) * ratio))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw URLError(.cannotDecodeContentData)
        }
        try Task.checkCancellation()
        return UIImage(cgImage: image)
    }
}
