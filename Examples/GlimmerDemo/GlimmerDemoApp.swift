import SwiftUI

@main
struct GlimmerDemoApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--streaming-lab") {
                NavigationStack { StreamingLabDemo() }
            } else if ProcessInfo.processInfo.arguments.contains("--engine-gallery") {
                NavigationStack { EngineGalleryDemo() }
            } else if ProcessInfo.processInfo.arguments.contains("--reveal-demo") {
                NavigationStack { StreamingRevealDemo() }
                    .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--reveal-dark") ? .dark : nil)
                    .transformEnvironment(\.dynamicTypeSize) { size in
                        if ProcessInfo.processInfo.arguments.contains("--reveal-large-text") { size = .accessibility1 }
                    }
            } else {
                ContentView()
            }
        }
    }
}
