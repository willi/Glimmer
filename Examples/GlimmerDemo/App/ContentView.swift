import SwiftUI

/// The demo's screens: every element, streaming by hand, a long answer, and the benchmark.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Gallery", destination: EngineGalleryDemo())
                NavigationLink("Streaming Lab", destination: StreamingLabDemo())
                NavigationLink("Long Answer", destination: LongAnswerDemo())
                NavigationLink("Benchmark", destination: BenchmarkDemo())
            }
            .navigationTitle("Glimmer")
        }
    }
}
