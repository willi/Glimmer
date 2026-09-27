import SwiftUI
import Glimmer

// Quick example view for individual demos
struct QuickExampleView: View {
    let title: String
    let markdown: String
    
    var body: some View {
        ScrollView {
            MarkdownView(
                markdown: markdown,
                configuration: .github,
                onLinkTap: { url in
                    print("🔗 Link tapped: \(url)")
                },
                onMentionTap: { username in
                    print("👤 Mention tapped: @\(username)")
                },
                onIssueTap: { issue in
                    print("🐛 Issue tapped: #\(issue)")
                }
            )
            .padding()
        }
        .navigationTitle(title)
    }
}
