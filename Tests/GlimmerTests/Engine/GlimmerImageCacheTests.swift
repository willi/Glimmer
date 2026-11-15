import UIKit
import XCTest
@testable import Glimmer

/// Loads images whose URL has one of the given paths and hides the rest.
private struct AllowPaths: GlimmerImagePolicy {
    var paths: Set<String>
    func decision(for image: GlimmerImageCandidate) -> GlimmerImageDecision {
        paths.contains(image.url.path()) ? .load : .hide
    }
}

@MainActor
final class GlimmerImageCacheTests: XCTestCase {
    private func png(color: UIColor = .red, size: CGSize = CGSize(width: 40, height: 20)) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.pngData())
    }

    func testDefaultLoadersSharePreparedImages() async throws {
        let server = try ImageTestServer(reply: .init(data: png()))
        defer { server.stop() }
        let url = try await server.start()
        let first = try await GlimmerURLSessionImageLoader().loadImage(from: url)
        let second = try await GlimmerURLSessionImageLoader().loadImage(from: url)
        XCTAssertTrue(first === second, "separate default loaders reuse the same prepared UIImage")
        XCTAssertEqual(server.requestCount, 1, "the fresh HTTP response is reused")
    }

    private func isolatedCache(memory: Int = 32 * 1024 * 1024) -> GlimmerImageCache {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)
        return GlimmerImageCache(session: URLSession(configuration: configuration), preparedImageMemoryCapacity: memory)
    }

    func testConcurrentConsumersShareDownloadAndPreparation() async throws {
        let server = try ImageTestServer(reply: .init(data: png(), delay: 0.2))
        defer { server.stop() }
        let url = try await server.start()
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        let images = try await withThrowingTaskGroup(of: UIImage.self) { group in
            for _ in 0..<12 { group.addTask { try await loader.loadImage(from: url) } }
            var images: [UIImage] = []
            for try await image in group { images.append(image) }
            return images
        }
        let first = try XCTUnwrap(images.first)
        XCTAssertTrue(images.allSatisfy { $0 === first })
        XCTAssertEqual(server.requestCount, 1)
    }

    func testCancellingOneConsumerKeepsTheOtherLoadAlive() async throws {
        let server = try ImageTestServer(reply: .init(data: png(), delay: 0.3))
        defer { server.stop() }
        let url = try await server.start()
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        let first = Task { try await loader.loadImage(from: url) }
        let second = Task { try await loader.loadImage(from: url) }
        let started = await waitUntil { server.requestCount == 1 }
        XCTAssertTrue(started)
        first.cancel()
        do { _ = try await first.value; XCTFail("cancelled consumer must fail") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let image = try await second.value
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertEqual(server.requestCount, 1)
    }

    func testCancellingAllConsumersAllowsAFreshRequest() async throws {
        let server = try ImageTestServer(reply: .init(data: png(), headers: ["Cache-Control": "no-store"], delay: 0.3))
        defer { server.stop() }
        let url = try await server.start()
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        let first = Task { try await loader.loadImage(from: url) }
        let started = await waitUntil { server.requestCount == 1 }
        XCTAssertTrue(started)
        first.cancel()
        do { _ = try await first.value; XCTFail("expected cancellation") } catch {}
        _ = try await loader.loadImage(from: url)
        XCTAssertEqual(server.requestCount, 2)
    }

    func testChangedHTTPResponseReplacesThePreparedImage() async throws {
        let server = try ImageTestServer(reply: .init(data: png(), headers: ["Cache-Control": "no-cache", "ETag": "\"red\""]))
        defer { server.stop() }
        let url = try await server.start()
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        let first = try await loader.loadImage(from: url)
        server.setReply(.init(data: try png(color: .blue, size: CGSize(width: 30, height: 10))))
        let second = try await loader.loadImage(from: url)
        XCTAssertEqual(server.requestCount, 2)
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.size, CGSize(width: 30, height: 10))
    }

    func testHTTPRevalidationReusesPreparedImageForUnchangedBytes() async throws {
        let headers = ["Cache-Control": "no-cache", "ETag": "\"same\""]
        let server = try ImageTestServer(reply: .init(data: png(), headers: headers))
        defer { server.stop() }
        let url = try await server.start()
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        let first = try await loader.loadImage(from: url)
        server.setReply(.init(data: Data(), headers: headers, status: 304))
        let second = try await loader.loadImage(from: url)
        XCTAssertEqual(server.requestCount, 2)
        XCTAssertTrue(server.receivedRequests.last?.lowercased().contains("if-none-match: \"same\"") == true)
        XCTAssertTrue(first === second)
    }

    func testNoStoreResponsesAreNotRetainedInEitherCache() async throws {
        let server = try ImageTestServer(reply: .init(data: png(), headers: ["Cache-Control": "no-store"]))
        defer { server.stop() }
        let url = try await server.start()
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        let first = try await loader.loadImage(from: url)
        let second = try await loader.loadImage(from: url)
        XCTAssertEqual(server.requestCount, 2)
        XCTAssertFalse(first === second)
    }

    func testClearMemoryKeepsHTTPDataAndClearAllRemovesIt() async throws {
        let server = try ImageTestServer(reply: .init(data: png()))
        defer { server.stop() }
        let url = try await server.start()
        let cache = isolatedCache()
        let loader = GlimmerURLSessionImageLoader(cache: cache)
        let first = try await loader.loadImage(from: url)
        await cache.removePreparedImages()
        let second = try await loader.loadImage(from: url)
        XCTAssertFalse(first === second)
        XCTAssertEqual(server.requestCount, 1)
        await cache.removeAll()
        let third = try await loader.loadImage(from: url)
        XCTAssertFalse(second === third)
        XCTAssertEqual(server.requestCount, 2)
    }

    func testMemoryWarningDropsPreparedImages() async throws {
        let server = try ImageTestServer(reply: .init(data: png()))
        defer { server.stop() }
        let url = try await server.start()
        let cache = isolatedCache()
        let loader = GlimmerURLSessionImageLoader(cache: cache)
        let first = try await loader.loadImage(from: url)
        let generation = await cache.generation
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        for _ in 0..<100 {
            if await cache.generation > generation { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let currentGeneration = await cache.generation
        XCTAssertGreaterThan(currentGeneration, generation)
        let second = try await loader.loadImage(from: url)
        XCTAssertFalse(first === second)
        XCTAssertEqual(server.requestCount, 1)
    }

    func testClearAllCancelsPendingLoads() async throws {
        let server = try ImageTestServer(reply: .init(data: png(), delay: 0.3))
        defer { server.stop() }
        let url = try await server.start()
        let cache = isolatedCache()
        let loader = GlimmerURLSessionImageLoader(cache: cache)
        let load = Task { try await loader.loadImage(from: url) }
        let started = await waitUntil { server.requestCount == 1 }
        XCTAssertTrue(started)
        await cache.removeAll()
        do { _ = try await load.value; XCTFail("clearing must cancel active consumers") } catch {}
        _ = try await loader.loadImage(from: url)
        XCTAssertEqual(server.requestCount, 2)
    }

    func testSmallMemoryBudgetDoesNotRetainOversizedImages() async throws {
        let server = try ImageTestServer(reply: .init(data: png()))
        defer { server.stop() }
        let url = try await server.start()
        for capacity in [0, 1] {
            let loader = GlimmerURLSessionImageLoader(cache: isolatedCache(memory: capacity))
            let first = try await loader.loadImage(from: url)
            let second = try await loader.loadImage(from: url)
            XCTAssertFalse(first === second)
        }
    }

    func testTargetSizeSeparatesVariantsAndNeverUpscales() async throws {
        let server = try ImageTestServer(reply: .init(data: png(size: CGSize(width: 400, height: 200))))
        defer { server.stop() }
        let url = try await server.start()
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        let fitRequest = GlimmerImageRequest(url: url, targetPixelSize: CGSize(width: 40, height: 40))
        let fit = try await loader.loadImage(for: fitRequest)
        let fill = try await loader.loadImage(for: .init(url: url, targetPixelSize: CGSize(width: 40, height: 40), contentMode: .aspectFill))
        let original = try await loader.loadImage(for: .init(url: url, targetPixelSize: CGSize(width: 1000, height: 1000)))
        let repeatedFit = try await loader.loadImage(for: fitRequest)
        XCTAssertEqual(fit.size, CGSize(width: 40, height: 20))
        XCTAssertEqual(fill.size, CGSize(width: 80, height: 40))
        XCTAssertEqual(original.size, CGSize(width: 400, height: 200))
        XCTAssertTrue(fit === repeatedFit)
        XCTAssertEqual(server.requestCount, 1)
    }

    func testHTTPAndDecodeFailuresCanBeRetried() async throws {
        let server = try ImageTestServer(reply: .init(data: png(), headers: ["Cache-Control": "no-store"], status: 500))
        defer { server.stop() }
        let url = try await server.start()
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        do { _ = try await loader.loadImage(from: url); XCTFail("HTTP error must fail") } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
        server.setReply(.init(data: Data("not an image".utf8), headers: ["Cache-Control": "no-store"]))
        do { _ = try await loader.loadImage(from: url); XCTFail("invalid image must fail") } catch {
            XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData)
        }
        server.setReply(.init(data: try png()))
        _ = try await loader.loadImage(from: url)
        XCTAssertEqual(server.requestCount, 3)
    }

    func testCustomBuiltInLoadersDoNotShareDocumentCacheEntries() throws {
        let firstCache = isolatedCache()
        let secondCache = isolatedCache()
        let first = GlimmerView(configuration: .init(imageLoader: GlimmerURLSessionImageLoader(cache: firstCache)))
        let second = GlimmerView(configuration: .init(imageLoader: GlimmerURLSessionImageLoader(cache: secondCache)))
        let markdown = "![Photo](https://example.com/custom-cache.png)"
        first.update(markdown: markdown)
        second.update(markdown: markdown)
        let attachment = try XCTUnwrap(blockAttachments(in: second.textView.textStorage).first)
        let loader = try XCTUnwrap(attachment.imageLoader as? GlimmerURLSessionImageLoader)
        XCTAssertTrue(loader.cache === secondCache)
    }

    func testLargeSourceIsPreparedAsASmallImageWithoutMainThreadDecoding() async throws {
        let data = try png(size: CGSize(width: 4096, height: 2048))
        let server = try ImageTestServer(reply: .init(data: data))
        defer { server.stop() }
        let url = try await server.start()
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        let start = threadCPUTime()
        let image = try await loader.loadImage(for: .init(
            url: url, targetPixelSize: CGSize(width: 72, height: 72), contentMode: .aspectFill
        ))
        let mainCPU = threadCPUTime() - start
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(image.size, CGSize(width: 144, height: 72))
        XCTAssertLessThan(cgImage.bytesPerRow * cgImage.height, 128 * 1024)
        XCTAssertLessThan(mainCPU, .milliseconds(20), "main-thread CPU while downloading and preparing a large source")
        print("IMAGE_CACHE_LARGE_SOURCE mainCPU=\(mainCPU) preparedBytes=\(cgImage.bytesPerRow * cgImage.height)")
    }

    func testDiskCacheSurvivesRecreatingTheSessionAndImageCache() async throws {
        let server = try ImageTestServer(reply: .init(data: png(size: CGSize(width: 100, height: 100))))
        defer { server.stop() }
        let url = try await server.start()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        func session() -> URLSession {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 16 * 1024 * 1024, directory: directory)
            return URLSession(configuration: configuration)
        }
        let firstSession = session()
        let first = GlimmerURLSessionImageLoader(cache: GlimmerImageCache(session: firstSession))
        _ = try await first.loadImage(from: url)
        let stored = await waitUntil(timeout: 8) { (firstSession.configuration.urlCache?.currentDiskUsage ?? 0) > 0 }
        XCTAssertTrue(stored, "URLSession must write the cacheable response to disk")
        firstSession.finishTasksAndInvalidate()
        let secondSession = session()
        defer { secondSession.invalidateAndCancel() }
        let second = GlimmerURLSessionImageLoader(cache: GlimmerImageCache(session: secondSession))
        _ = try await second.loadImage(from: url)
        XCTAssertEqual(server.requestCount, 1, "the new session reads the persisted response")
    }

    // MARK: - Redirects under an image policy

    private func request(_ url: URL, policy: (any GlimmerImagePolicy)?) -> GlimmerImageRequest {
        var request = GlimmerImageRequest(url: url)
        request.gate = policy.map {
            GlimmerImageGate(policy: $0, candidate: GlimmerImageCandidate(url: url, alt: "", origin: .markdown))
        }
        return request
    }

    /// `/image.png` redirects to `/hop.png`, which redirects to `/moved.png`, which is the image.
    private func redirectingServer(delay: TimeInterval = 0) async throws -> (ImageTestServer, URL) {
        let server = try ImageTestServer(reply: .init(data: png()))
        server.setReply(.init(data: Data(), headers: ["Location": "/hop.png"], status: 302, delay: delay), forPath: "/image.png")
        server.setReply(.init(data: Data(), headers: ["Location": "/moved.png"], status: 302), forPath: "/hop.png")
        return (server, try await server.start())
    }

    private func requests(for path: String, on server: ImageTestServer) -> Int {
        server.receivedRequests.count { $0.hasPrefix("GET \(path) ") }
    }

    func testARefusedRedirectIsNeverRequested() async throws {
        let (server, url) = try await redirectingServer()
        defer { server.stop() }
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        do {
            _ = try await loader.loadImage(for: request(url, policy: AllowPaths(paths: ["/image.png", "/hop.png"])))
            XCTFail("a refused redirect fails the load")
        } catch {}
        XCTAssertEqual(requests(for: "/hop.png", on: server), 1, "the permitted hop is followed")
        XCTAssertEqual(requests(for: "/moved.png", on: server), 0, "the refused hop is never requested")
    }

    func testAPermittedRedirectLoads() async throws {
        let (server, url) = try await redirectingServer()
        defer { server.stop() }
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        let image = try await loader.loadImage(
            for: request(url, policy: AllowPaths(paths: ["/image.png", "/hop.png", "/moved.png"]))
        )
        XCTAssertEqual(image.size, CGSize(width: 40, height: 20))
        XCTAssertEqual(requests(for: "/moved.png", on: server), 1)
    }

    func testWithNoPolicyARedirectIsFollowed() async throws {
        let (server, url) = try await redirectingServer()
        defer { server.stop() }
        let image = try await GlimmerURLSessionImageLoader(cache: isolatedCache()).loadImage(for: request(url, policy: nil))
        XCTAssertEqual(image.size, CGSize(width: 40, height: 20))
        XCTAssertEqual(requests(for: "/moved.png", on: server), 1)
    }

    func testAPolicedRequestDoesNotRideOnAnUnpolicedDownload() async throws {
        let (server, url) = try await redirectingServer(delay: 0.3)
        defer { server.stop() }
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        let open = request(url, policy: nil)
        let unpoliced = Task { try await loader.loadImage(for: open) }
        let started = await waitUntil { server.requestCount == 1 }
        XCTAssertTrue(started)
        do {
            _ = try await loader.loadImage(for: request(url, policy: AllowPaths(paths: ["/image.png"])))
            XCTFail("a policed load never receives an image fetched through a redirect its policy refuses")
        } catch {}
        let image = try await unpoliced.value
        XCTAssertEqual(image.size, CGSize(width: 40, height: 20))
    }

    func testACachedRedirectIsStillPutToThePolicy() async throws {
        // The redirect may be cached; its target may not, so a second trip to it would show on the server.
        let server = try ImageTestServer(reply: .init(data: png(), headers: ["Cache-Control": "no-store"]))
        server.setReply(
            .init(data: Data(), headers: ["Location": "/moved.png", "Cache-Control": "max-age=3600"], status: 301),
            forPath: "/image.png"
        )
        defer { server.stop() }
        let url = try await server.start()
        let loader = GlimmerURLSessionImageLoader(cache: isolatedCache())
        _ = try await loader.loadImage(for: request(url, policy: nil))
        XCTAssertEqual(requests(for: "/moved.png", on: server), 1)
        do {
            _ = try await loader.loadImage(for: request(url, policy: AllowPaths(paths: ["/image.png"])))
            XCTFail("a refused redirect fails the load, cached or not")
        } catch {}
        XCTAssertEqual(requests(for: "/moved.png", on: server), 1, "the refused target is not requested again")
        XCTAssertEqual(requests(for: "/image.png", on: server), 1, "the second redirect came from the cache")
    }
}
