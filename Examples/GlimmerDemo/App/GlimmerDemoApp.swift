import SwiftUI

@main
struct GlimmerDemoApp: App {
    private let arguments = ProcessInfo.processInfo.arguments

    var body: some Scene {
        WindowGroup {
            Group {
                if arguments.contains("--streaming-lab") {
                    NavigationStack { StreamingLabDemo() }
                } else if arguments.contains("--benchmark") {
                    NavigationStack { BenchmarkDemo() }
                } else if arguments.contains("--engine-gallery") {
                    NavigationStack { EngineGalleryDemo() }
                } else if let example = DemoExample.launchExample {
                    NavigationStack { example.destination }
                } else {
                    ContentView()
                }
            }
            // `--dark` and `--large-text` apply to every screen, for screenshots.
            .preferredColorScheme(arguments.contains("--dark") ? .dark : nil)
            .transformEnvironment(\.dynamicTypeSize) { size in
                if arguments.contains("--large-text") { size = .accessibility1 }
            }
        }
    }
}
