import SwiftUI

@main
struct GlimmerDemoApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--streaming-lab") {
                NavigationStack { StreamingLabDemo() }
            } else if ProcessInfo.processInfo.arguments.contains("--benchmark") {
                NavigationStack { BenchmarkDemo() }
            } else if ProcessInfo.processInfo.arguments.contains("--engine-gallery") {
                NavigationStack { EngineGalleryDemo() }
            } else {
                ContentView()
            }
        }
    }
}
