import UIKit

/// Loads images for markdown attachments. Plug in your app's image pipeline here.
public protocol GlimmerImageLoader: Sendable {
    /// Loads the image at its original size.
    func loadImage(from url: URL) async throws -> UIImage
    /// Loads an image sized for display. Existing loaders may implement only `loadImage(from:)`.
    func loadImage(for request: GlimmerImageRequest) async throws -> UIImage
}

extension GlimmerImageLoader {
    /// Preserves existing loaders by forwarding size-aware requests to their original URL method.
    public func loadImage(for request: GlimmerImageRequest) async throws -> UIImage {
        try await loadImage(from: request.url)
    }
}

/// The default loader: shared HTTP caching, image preparation and cancellation-aware request coalescing.
public struct GlimmerURLSessionImageLoader: GlimmerImageLoader {
    let cache: GlimmerImageCache

    /// Uses the shared cache by default. Pass a separate cache to customize budgets or isolate a session.
    public init(cache: GlimmerImageCache = .shared) {
        self.cache = cache
    }

    /// Loads a prepared image at its original size, respecting HTTP freshness.
    public func loadImage(from url: URL) async throws -> UIImage {
        try await loadImage(for: GlimmerImageRequest(url: url))
    }

    /// Loads a prepared image with enough pixels for the requested display size, without upscaling.
    public func loadImage(for request: GlimmerImageRequest) async throws -> UIImage {
        try await cache.image(for: request)
    }
}
