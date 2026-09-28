import UIKit

/// Loads images for markdown image embeds. Plug in your app's image cache here.
public protocol GlimmerImageLoader: Sendable {
    func loadImage(from url: URL) async throws -> UIImage
}

/// The default loader: a plain `URLSession.shared` fetch with no caching beyond URLSession's own.
public struct GlimmerURLSessionImageLoader: GlimmerImageLoader {
    public init() {}

    public func loadImage(from url: URL) async throws -> UIImage {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        return image
    }
}
