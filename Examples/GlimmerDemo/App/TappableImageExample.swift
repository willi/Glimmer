import SwiftUI
import Glimmer

struct TappableImageExample: View {
    @State private var selectedImageURL: URL?
    @State private var showingImageViewer = false
    
    init() {
    }
    
    let markdown = """
    # Tappable Images Example
    
    This example demonstrates how to make inline images tappable in Glimmer.
    
    ## Regular Image
    ![SwiftUI Logo](https://developer.apple.com/assets/elements/icons/swiftui/swiftui-96x96_2x.png)
    
    ## Inline Images in Text
    Here's an inline image ![icon](https://github.githubassets.com/images/icons/emoji/octocat.png) within text content.
    
    ## Multiple Images
    ![Swift](https://developer.apple.com/assets/elements/icons/swift/swift-96x96_2x.png) ![Xcode](https://developer.apple.com/assets/elements/icons/xcode-12/xcode-12-96x96_2x.png)
    
    ## Long Text with Multiple Inline Images
    
    Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Here's a beautiful Swift logo ![swift](https://developer.apple.com/assets/elements/icons/swift/swift-48x48_2x.png) that captures the essence of nature. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodi consequat. The AppKit icon ![appkit](https://developer.apple.com/assets/elements/icons/appkit/appkit-96x96_2x.png) shows modern architecture at its finest. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.
    
    Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollitia animi, id est laborum et dolorum fuga. Look at this UIKit icon ![uikit](https://developer.apple.com/assets/elements/icons/uikit/uikit-96x96_2x.png) which represents modern creativity. Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo. A WebKit icon ![webkit](https://developer.apple.com/assets/elements/icons/webkit/webkit-96x96_2x.png) brings peace to mind.
    
    Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt. This SpriteKit icon ![spritekit](https://developer.apple.com/assets/elements/icons/spritekit/spritekit-96x96_2x.png) adds vibrancy to our discussion. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit, sed quia non numquam eius modi tempora incidunt ut labore et dolore magnam aliquam quaerat voluptatem. The SceneKit icon ![scenekit](https://developer.apple.com/assets/elements/icons/scenekit/scenekit-96x96_2x.png) reminds us of 3D power.
    
    Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur? Notice this Metal icon ![metal](https://developer.apple.com/assets/elements/icons/metal/metal-96x96_2x.png) showcasing mathematical beauty. Quis autem vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur, vel illum qui dolorem eum fugiat quo voluptas nulla pariatur? Finally, here's a RealityKit icon ![realitykit](https://developer.apple.com/assets/elements/icons/realitykit/realitykit-96x96_2x.png) to end our visual journey.
    
    At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis praesentium voluptatum deleniti atque corrupti quos dolores et quas molestias excepturi sint occaecati cupiditate non provident. A small GitHub icon ![github](https://github.githubassets.com/images/icons/emoji/octocat.png) can make a big difference. Similique sunt in culpa qui officia deserunt mollitia animi, id est laborum et dolorum fuga. And another TestFlight icon ![testflight](https://developer.apple.com/assets/elements/icons/testflight/testflight-64x64_2x.png) for good measure. Et harum quidem rerum facilis est et expedita distinctio.
    
    Tap any image to see the URL!
    """
    
    var body: some View {
        NavigationStack {
            ScrollView {
                MarkdownView(
                    markdown: markdown,
                    configuration: MarkdownConfiguration(
                        onImageTap: { @Sendable url, alt in
                            Task { @MainActor in
                                selectedImageURL = url
                                showingImageViewer = true
                            }
                        }
                    )
                )
                .padding()
            }
            .navigationTitle("Tappable Images")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .alert("Image Tapped", isPresented: $showingImageViewer) {
                Button("OK", role: .cancel) {
                    selectedImageURL = nil
                }
            } message: {
                if let url = selectedImageURL {
                    Text("URL: \(url.absoluteString)")
                }
            }
        }
    }
}

#Preview {
    TappableImageExample()
}

