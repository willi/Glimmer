import Glimmer
import UIKit

/// Loads web images with URLSession, and serves a bare name such as `![Dog](dog)` from the app's assets or, failing
/// that, the SF Symbol of that name, standing in for a host's own asset provider.
struct DemoImageLoader: GlimmerImageLoader {
    struct NotFound: Error {}

    func loadImage(for request: GlimmerImageRequest) async throws -> UIImage {
        guard request.url.scheme == nil else { return try await GlimmerURLSessionImageLoader().loadImage(for: request) }
        return try await loadImage(from: request.url)
    }

    func loadImage(from url: URL) async throws -> UIImage {
        guard url.scheme == nil else { return try await GlimmerURLSessionImageLoader().loadImage(from: url) }
        let name = url.relativeString
        let image = await MainActor.run {
            UIImage(named: name) ?? UIImage(systemName: name + ".fill") ?? UIImage(systemName: name)
        }
        guard let image else { throw NotFound() }
        return image
    }
}
