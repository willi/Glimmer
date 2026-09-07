import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTrailTextViewPixelTests: XCTestCase {
    func testLastWordActuallyDrawsAtFullOpacityAfterProducerStops() async throws {
        var time = 0.0
        let view = GlimmerTrailTextView(now: { time })
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
        view.backgroundColor = .white
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.addSubview(view)
        defer { window.isHidden = true }
        let source = NSAttributedString(string: "steady.", attributes: [
            .font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black
        ])
        view.update(attributedText: source, isStreaming: false)
        try await Task.sleep(for: .milliseconds(100))
        let initialInk = try ink(in: snapshot(view))

        time = RevealSmoothTrail.duration / 4
        view.advance(at: time)
        try await Task.sleep(for: .milliseconds(100))
        let fadingInk = try ink(in: snapshot(view))
        XCTAssertGreaterThan(fadingInk, initialInk + 10, "The pixels must brighten without another text update.")

        time = RevealSmoothTrail.duration + 0.01
        view.advance(at: time)
        try await Task.sleep(for: .milliseconds(100))
        let completed = snapshot(view)
        let completedInk = try ink(in: completed)
        XCTAssertFalse(view.isRevealing)
        XCTAssertNil(view.layer.mask, "Completed text must have no remaining opacity mask.")
        XCTAssertGreaterThan(completedInk, fadingInk + 10)

        // Compare the actual completed pixels with a fresh fully visible render.
        view.reset()
        view.update(attributedText: source, isStreaming: false)
        view.finishImmediately()
        try await Task.sleep(for: .milliseconds(100))
        let referenceInk = try ink(in: snapshot(view))
        XCTAssertGreaterThan(referenceInk, 100)
        XCTAssertEqual(completedInk, referenceInk, accuracy: referenceInk * 0.005)
    }

    func testPausedStreamingWordAlsoLosesItsMask() {
        var time = 0.0
        let view = GlimmerTrailTextView(now: { time })
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
        view.update(attributedText: NSAttributedString(string: "pause"), isStreaming: true)
        time = RevealSmoothTrail.duration + 0.01
        view.advance(at: time)
        XCTAssertTrue(view.isStreaming)
        XCTAssertFalse(view.isRevealing)
        XCTAssertNil(view.layer.mask)
    }

    private func snapshot(_ view: UIView) -> UIImage {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        CATransaction.flush()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(view.bounds)
            view.layer.render(in: context.cgContext)
        }
    }

    private func ink(in image: UIImage) throws -> Double {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: bytes.count, by: 4).reduce(0) { $0 + Double(255 - bytes[$1]) }
    }
}
