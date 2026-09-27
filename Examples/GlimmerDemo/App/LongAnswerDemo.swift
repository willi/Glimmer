import Glimmer
import SwiftUI

/// About 5,000 words in one GlimmerText, to check scrolling a long answer by eye: no blank bands, no stutter.
struct LongAnswerDemo: View {
    private static let answer = Array(repeating: EngineGalleryDemo.sample, count: 20).joined(separator: "\n\n---\n\n")

    var body: some View {
        ScrollView {
            GlimmerText(Self.answer)
                .padding(16)
        }
        .navigationTitle("Long Answer")
    }
}
