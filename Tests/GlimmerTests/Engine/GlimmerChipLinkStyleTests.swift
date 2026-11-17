import XCTest
@testable import Glimmer

private struct TappableChip: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            return GlimmerInlineToken(
                range: range, kind: "chip", payload: [:], displayText: label, source: label, isTappable: true
            )
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? {
        let box = UIView()
        box.frame = CGRect(x: 0, y: 0, width: 60, height: 20)
        return box
    }
}

/// A tappable chip's glyph carries `.link`, so the text view's link attributes (set while data detectors are on) reach it.
@MainActor
final class GlimmerChipLinkStyleTests: XCTestCase {
    private var windows: [UIWindow] = []

    private func render(underlinesLinks: Bool) -> [UInt8] {
        var configuration = GlimmerConfiguration(extensions: [TappableChip()], imageLoader: nil, reveal: .none)
        configuration.dataDetectors = [.phoneNumber]
        configuration.theme.underlinesLinks = underlinesLinks
        let view = GlimmerView(configuration: configuration)
        view.update(markdown: "[1]")
        windows.append(hostInWindow(view, width: 200, height: 40))
        settle(view)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 40))
        let image = renderer.image { view.layer.render(in: $0.cgContext) }
        guard let data = image.cgImage?.dataProvider?.data else { return [] }
        return Array(UnsafeBufferPointer(start: CFDataGetBytePtr(data), count: CFDataGetLength(data)))
    }

    func testUnderliningLinksDoesNotUnderlineATappableChip() {
        let plain = render(underlinesLinks: false)
        XCTAssertEqual(plain, render(underlinesLinks: false), "rendering must be repeatable for the comparison to mean anything")
        let underlined = render(underlinesLinks: true)
        XCTAssertFalse(plain.isEmpty)
        XCTAssertEqual(plain, underlined, "link underlining must not draw under a chip")
    }
}
