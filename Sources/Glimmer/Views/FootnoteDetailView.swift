import SwiftUI

struct FootnoteDetailView: View {
    let label: String
    let content: [MarkdownParser.BlockNode]
    let configuration: MarkdownConfiguration
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Non-interactive content view for footnote content
                MarkdownContentView(
                    blocks: content,
                    configuration: configuration
                )
            }
            .padding()
        }
        .navigationTitle("Footnote [\(label.starts(with: "inline-") ? "*" : label)]")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
