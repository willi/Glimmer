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
            // `--dark` and `--large-text` apply to every screen, for screenshots. Only when passed: an app-wide color
            // scheme, even nil, would override a screen's own Dark toggle.
            .modifier(LaunchAppearance(isDark: arguments.contains("--dark"), isLargeText: arguments.contains("--large-text")))
        }
    }
}

/// The appearance launch arguments ask for, applied only when asked.
private struct LaunchAppearance: ViewModifier {
    let isDark: Bool
    let isLargeText: Bool

    func body(content: Content) -> some View {
        if isDark {
            styled(content).preferredColorScheme(.dark)
        } else {
            styled(content)
        }
    }

    @ViewBuilder
    private func styled(_ content: Content) -> some View {
        if isLargeText {
            content.dynamicTypeSize(.accessibility1)
        } else {
            content
        }
    }
}
