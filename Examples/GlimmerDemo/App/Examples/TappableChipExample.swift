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
        let label = UILabel()
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

/// Tappable chips: a citation chip reports its tap through the banner.
struct TappableChipExample: View {
    @State private var lastTap: String?

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
                onTokenTap: { lastTap = "Citation \($0.payload["number"] ?? "")" }
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
