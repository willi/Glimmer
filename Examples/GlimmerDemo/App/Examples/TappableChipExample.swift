import Glimmer
import SwiftUI
import UIKit

/// `[1]` citations as tappable chips: a `.chip` token with `isTappable`, drawn by the host's own view. A tap reports the
/// token through `onTokenTap`, and VoiceOver reaches the chip once, as a link.
struct DemoCitations: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            return GlimmerInlineToken(
                range: range, kind: "citation", payload: ["number": String(label.dropFirst().dropLast())], displayText: label,
                source: label, accessibilityLabel: "Source \(label.dropFirst().dropLast())", isTappable: true
            )
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? {
        let label = DemoCitationLabel()
        label.text = token.displayText
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .white
        label.backgroundColor = .systemIndigo
        label.textAlignment = .center
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        return label
    }
}

/// A citation chip with room around its number, so a tap on its body is easy to aim.
private final class DemoCitationLabel: UILabel {
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let text = super.sizeThatFits(size)
        return CGSize(width: max(text.width + 16, 32), height: text.height + 4)
    }
}

/// Tappable chips: a citation chip reports its tap through the banner.
struct TappableChipExample: View {
    @State private var lastTap: String?
    @State private var taps = 0

    private var configuration: GlimmerConfiguration {
        var configuration = GlimmerConfiguration()
        configuration.extensions = [DemoCitations()]
        return configuration
    }

    var body: some View {
        ScrollView {
            GlimmerText(
                "Glimmer lays text out once with TextKit 2 [1] and reveals it phrase by phrase [2].",
                configuration: configuration,
                onTokenTap: {
                    taps += 1
                    lastTap = "Citation \($0.payload["number"] ?? "") x\(taps)"
                }
            )
            .padding()
        }
        .navigationTitle("Tappable Chips")
        .safeAreaInset(edge: .bottom) { DemoTapBanner(text: lastTap) }
    }
}

#Preview {
    NavigationStack { TappableChipExample() }
}
