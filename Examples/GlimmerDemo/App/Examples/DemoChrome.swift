import Glimmer
import SwiftUI

/// The horizontal row of capsules the GFM and Edge Cases screens pick a section with, as in 1.x.
struct DemoChipBar: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                    Button { selection = index } label: {
                        Text(title)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selection == index ? Color.accentColor : Color.gray.opacity(0.2), in: Capsule())
                            .foregroundStyle(selection == index ? Color.white : Color.primary)
                    }
                    .accessibilityIdentifier("chip.\(title)")
                }
            }
            .padding()
        }
    }
}

/// The last link, mention, issue or image the reader tapped, where 1.x printed it to the console.
struct DemoTapBanner: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.footnote.monospaced())
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
                .accessibilityIdentifier("demo.lastTap")
        }
    }
}

extension GlimmerInlineToken {
    /// "Mention @ada" or "Issue #123", for the tap banner.
    var demoDescription: String {
        switch kind {
        case "mention": "Mention @\(payload["username"] ?? "")"
        case "issue": "Issue #\(payload["number"] ?? "")"
        default: "\(kind) \(payload)"
        }
    }
}
