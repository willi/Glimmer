import SwiftUI

/// The demo's screens: 2.0's own, then 1.x's examples rebuilt on 2.0 in 1.x's sections.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Glimmer 2.0") {
                    NavigationLink("Gallery", destination: EngineGalleryDemo())
                    NavigationLink("Streaming Lab", destination: StreamingLabDemo())
                    NavigationLink("Long Answer", destination: LongAnswerDemo())
                    NavigationLink("Benchmark", destination: BenchmarkDemo())
                }

                Section("Core") {
                    NavigationLink("Basic Features", destination: BasicFeaturesDemo())
                }
            }
            .navigationTitle("Glimmer")
        }
    }
}
