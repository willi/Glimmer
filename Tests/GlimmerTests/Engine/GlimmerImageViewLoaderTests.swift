import UIKit
import XCTest
@testable import Glimmer

private actor SizedImageLoader: GlimmerImageLoader {
    private(set) var requests: [GlimmerImageRequest] = []
    let image: UIImage
    init(image: UIImage) { self.image = image }
    func loadImage(from url: URL) async throws -> UIImage { throw URLError(.unsupportedURL) }
    func loadImage(for request: GlimmerImageRequest) async throws -> UIImage {
        requests.append(request)
        return image
    }
}

private actor ControlledImageLoader: GlimmerImageLoader {
    private(set) var pending: [CheckedContinuation<UIImage, Never>] = []
    func loadImage(from url: URL) async throws -> UIImage {
        await withCheckedContinuation { pending.append($0) }
    }
    func finish(_ index: Int, image: UIImage) { pending[index].resume(returning: image) }
}

@MainActor
final class GlimmerImageViewLoaderTests: XCTestCase {
    private let url = URL(string: "https://example.com/image.png")!

    private func image(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func waitForPending(_ count: Int, in loader: ControlledImageLoader) async throws {
        for _ in 0..<100 {
            if await loader.pending.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw URLError(.timedOut)
    }

    func testInlineImagesRequestPixelsForTheirShapeAndDisplayScale() async throws {
        for shape in [GlimmerInlineImageShape.circle, .roundedRectangle(cornerRadius: 3)] {
            let loader = SizedImageLoader(image: image(.red))
            let view = GlimmerInlineImageView(source: url, alt: "", theme: .default, loader: loader, shape: shape)
            view.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
            view.layoutIfNeeded()
            let loaded = await waitUntil { view.image != nil }
            XCTAssertTrue(loaded)
            let requests = await loader.requests
            XCTAssertEqual(requests.count, 1)
            let side = 24 * view.traitCollection.displayScale
            XCTAssertEqual(requests.first?.targetPixelSize, CGSize(width: side, height: side))
            XCTAssertEqual(requests.first?.contentMode, shape == .circle ? .aspectFill : .aspectFit)
        }
    }

    func testStandaloneImageRequestsPixelsForItsReservedBox() async throws {
        let loader = SizedImageLoader(image: image(.red))
        let view = GlimmerImageEmbedView(source: url, alt: "", theme: .default, loader: loader)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 160)
        view.layoutIfNeeded()
        let loaded = await waitUntil { view.imageView.image != nil }
        XCTAssertTrue(loaded)
        let requests = await loader.requests
        let scale = view.traitCollection.displayScale
        XCTAssertEqual(requests.first?.targetPixelSize, CGSize(width: 300 * scale, height: 160 * scale))
        XCTAssertEqual(requests.first?.contentMode, .aspectFit)
    }

    func testGrowingReloadsButRepeatedLayoutAndShrinkingKeepTheImage() async throws {
        let loader = SizedImageLoader(image: image(.red))
        let view = GlimmerInlineImageView(source: url, alt: "", theme: .default, loader: loader)
        view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        view.layoutIfNeeded()
        let loaded = await waitUntil { view.image != nil }
        XCTAssertTrue(loaded)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.frame.size = CGSize(width: 10, height: 10)
        view.layoutIfNeeded()
        view.frame.size = CGSize(width: 40, height: 40)
        view.layoutIfNeeded()
        for _ in 0..<100 {
            if await loader.requests.count == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let requests = await loader.requests
        XCTAssertEqual(requests.count, 2)
        let side = 40 * view.traitCollection.displayScale
        XCTAssertEqual(requests.last?.targetPixelSize, CGSize(width: side, height: side))
    }

    func testCancelledOlderSizeCannotOverwriteTheNewImage() async throws {
        let loader = ControlledImageLoader()
        let coordinator = GlimmerImageViewLoader(source: url, loader: loader, contentMode: .aspectFit)
        var displayed: UIImage?
        coordinator.load(size: CGSize(width: 20, height: 20), scale: 1) { displayed = try? $0.get() }
        try await waitForPending(1, in: loader)
        coordinator.load(size: CGSize(width: 40, height: 40), scale: 1) { displayed = try? $0.get() }
        try await waitForPending(2, in: loader)
        let latest = image(.blue)
        await loader.finish(1, image: latest)
        let loaded = await waitUntil { displayed === latest }
        XCTAssertTrue(loaded)
        await loader.finish(0, image: image(.red))
        // Allow the old custom loader, which deliberately ignores cancellation, to return its image.
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(displayed === latest)
    }
}
