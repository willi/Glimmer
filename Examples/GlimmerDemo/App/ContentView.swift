import SwiftUI

/// The demo's screens: every element, streaming by hand, and a long answer.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Gallery", destination: EngineGalleryDemo())
                NavigationLink("Streaming Lab", destination: StreamingLabDemo())
                NavigationLink("Long Answer", destination: LongAnswerDemo())
            }
            .navigationTitle("Glimmer")
        }
    }
}
