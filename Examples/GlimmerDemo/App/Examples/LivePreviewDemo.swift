import Glimmer
import SwiftUI

/// Type markdown and watch it render. 1.x debounced and re-parsed the whole document; `GlimmerText` recomposes on
/// each keystroke, and a document it has shown before comes from its cache.
struct LivePreviewDemoScreen: View {
    @State private var text: String = "# Live Preview\n\nType to see updates."

    var body: some View {
        VStack {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(height: 140)
                .border(Color.secondary)
                .padding()
                .accessibilityIdentifier("livePreview.editor")
            Divider()
            ScrollView {
                GlimmerText(text, configuration: .demoGitHub)
                    .padding(.horizontal)
            }
        }
        .navigationTitle("Live Preview")
    }
}

#Preview {
    NavigationStack { LivePreviewDemoScreen() }
}
