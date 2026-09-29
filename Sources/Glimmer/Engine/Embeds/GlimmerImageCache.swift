import CryptoKit
import UIKit

/// Shared HTTP responses and prepared images for Glimmer's built-in loader. HTTP freshness is decided by URLSession.
public actor GlimmerImageCache {
    /// The cache used by default by every `GlimmerURLSessionImageLoader`.
    public static let shared = GlimmerImageCache()

    private struct Download: Sendable {
        let data: Data
        let fingerprint: String
        let permitsStorage: Bool
    }

    private let session: URLSession
    private let ownsSession: Bool
    private let images = NSCache<NSString, UIImage>()
    private let preparedImageMemoryCapacity: Int
    private let downloads = GlimmerImageTaskPool<URL, Download>()
    private let preparations = GlimmerImageTaskPool<String, UIImage>()
    private let decoder = GlimmerImageDecoder()
    private(set) var generation = 0
    private var invalidation = 0
    private var clearingTask: Task<Void, Never>?
    private var memoryWarning: NSObjectProtocol?

    /// Creates a cache with byte budgets for prepared images and HTTP responses. Zero disables that storage layer.
    /// `diskDirectory` defaults to Glimmer's directory in the app's caches. Use a distinct directory for isolated caches.
    /// NSCache's prepared-image budget is advisory; images larger than the budget are not retained.
    public init(
        preparedImageMemoryCapacity: Int = 32 * 1024 * 1024,
        responseMemoryCapacity: Int = 16 * 1024 * 1024,
        responseDiskCapacity: Int = 128 * 1024 * 1024,
        diskDirectory: URL? = nil
    ) {
        let configuration = URLSessionConfiguration.default
        let directory = diskDirectory ?? URL.cachesDirectory.appending(path: "Glimmer/Images", directoryHint: .isDirectory)
        configuration.urlCache = URLCache(
            memoryCapacity: max(0, responseMemoryCapacity), diskCapacity: max(0, responseDiskCapacity), directory: directory
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        self.session = URLSession(configuration: configuration)
        ownsSession = true
        self.preparedImageMemoryCapacity = max(0, preparedImageMemoryCapacity)
        images.totalCostLimit = max(0, preparedImageMemoryCapacity)
    }

    /// Creates an isolated prepared-image cache using the supplied session's HTTP cache, credentials and policies.
    /// Clearing this cache also clears that session's URLCache. The session remains owned by the caller.
    public init(session: URLSession, preparedImageMemoryCapacity: Int = 32 * 1024 * 1024) {
        self.session = session
        ownsSession = false
        self.preparedImageMemoryCapacity = max(0, preparedImageMemoryCapacity)
        images.totalCostLimit = max(0, preparedImageMemoryCapacity)
    }

    func image(for request: GlimmerImageRequest) async throws -> UIImage {
        if let clearingTask { await clearingTask.value }
        try Task.checkCancellation()
        observeMemoryWarningsIfNeeded()
        let generation = self.generation
        let invalidation = self.invalidation
        let download = try await downloads.value(for: request.url) { [session] in
            let (data, response) = try await session.data(from: request.url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            try Task.checkCancellation()
            let control = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control") ?? ""
            let noStore = control.split(separator: ",").contains {
                $0.trimmingCharacters(in: .whitespaces).lowercased() == "no-store"
            }
            return Download(data: data, fingerprint: SHA256.hash(data: data).description, permitsStorage: !noStore)
        }
        try Task.checkCancellation()
        guard invalidation == self.invalidation else { throw CancellationError() }
        let size = request.validPixelSize
        let key = "\(download.fingerprint):\(size?.width ?? 0)x\(size?.height ?? 0):\(request.contentMode)"
        // A URL-only memory hit would bypass HTTP revalidation and keep showing a replaced avatar.
        if download.permitsStorage, let image = images.object(forKey: key as NSString) { return image }
        let image = try await preparations.value(for: key) { [weak self, decoder] in
            if download.permitsStorage, let image = await self?.preparedImage(for: key) { return image }
            let image = try await decoder.image(data: download.data, request: request)
            if download.permitsStorage { await self?.store(image, for: key, generation: generation) }
            return image
        }
        try Task.checkCancellation()
        guard invalidation == self.invalidation else { throw CancellationError() }
        return image
    }

    private func preparedImage(for key: String) -> UIImage? { images.object(forKey: key as NSString) }

    private func store(_ image: UIImage, for key: String, generation: Int) {
        if !Task.isCancelled, generation == self.generation, let cgImage = image.cgImage {
            let (cost, overflow) = cgImage.bytesPerRow.multipliedReportingOverflow(by: cgImage.height)
            if !overflow, preparedImageMemoryCapacity > 0, cost <= preparedImageMemoryCapacity {
                images.setObject(image, forKey: key as NSString, cost: cost)
            }
        }
    }

    /// Drops prepared images while keeping HTTP responses. Also prevents pending preparations from repopulating memory.
    public func removePreparedImages() {
        generation += 1
        images.removeAllObjects()
    }

    /// Cancels pending loads and clears prepared images and the session's cached HTTP responses.
    /// Existing image views keep the images they already display.
    public func removeAll() async {
        if let clearingTask { await clearingTask.value; return }
        invalidation += 1
        removePreparedImages()
        let task = Task { [downloads, preparations, session] in
            await downloads.cancelAll()
            await preparations.cancelAll()
            session.configuration.urlCache?.removeAllCachedResponses()
            self.clearingTask = nil
        }
        clearingTask = task
        await task.value
    }

    private func observeMemoryWarningsIfNeeded() {
        guard memoryWarning == nil else { return }
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.removePreparedImages() }
        }
    }

    isolated deinit {
        if let memoryWarning { NotificationCenter.default.removeObserver(memoryWarning) }
        if ownsSession { session.invalidateAndCancel() }
    }
}
