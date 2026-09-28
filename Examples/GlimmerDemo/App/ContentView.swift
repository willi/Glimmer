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

                ForEach(DemoExample.Section.allCases, id: \.self) { section in
                    Section(section.rawValue) {
                        ForEach(DemoExample.allCases.filter { $0.section == section }) { example in
                            NavigationLink(example.title) { example.destination }
                                .accessibilityIdentifier("example.\(example.id)")
                        }
                    }
                }
            }
            .navigationTitle("Glimmer")
        }
    }
}
