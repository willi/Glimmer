import UIKit

/// Starts once TextKit supplies display bounds, and requests more pixels only when the attachment grows.
@MainActor
final class GlimmerImageViewLoader {
    private let source: URL
    private let loader: any GlimmerImageLoader
    private let contentMode: GlimmerImageRequest.ContentMode
    private var requestedSize: CGSize?
    private var loadTask: Task<Void, Never>?

    init(source: URL, loader: any GlimmerImageLoader, contentMode: GlimmerImageRequest.ContentMode) {
        self.source = source
        self.loader = loader
        self.contentMode = contentMode
    }

    func load(size: CGSize, scale: CGFloat, completion: @escaping @MainActor (Result<UIImage, Error>) -> Void) {
        guard size.width.isFinite, size.height.isFinite, scale.isFinite,
              size.width > 0, size.height > 0, scale > 0 else { return }
        let pixels = CGSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
        if let requestedSize, requestedSize.width >= pixels.width, requestedSize.height >= pixels.height { return }
        requestedSize = pixels
        loadTask?.cancel()
        let request = GlimmerImageRequest(url: source, targetPixelSize: pixels, contentMode: contentMode)
        loadTask = Task { [loader] in
            do {
                let image = try await loader.loadImage(for: request)
                try Task.checkCancellation()
                completion(.success(image))
            } catch {
                // An old request must never replace the result of a newer size, even if a custom loader ignores cancellation.
                guard !Task.isCancelled else { return }
                completion(.failure(error))
            }
        }
    }

    isolated deinit { loadTask?.cancel() }
}
