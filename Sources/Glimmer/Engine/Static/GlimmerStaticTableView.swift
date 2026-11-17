import SwiftUI

/// A table as lines of text, one per row, with tabs between the cells.
struct GlimmerStaticTableView: View {
    let rows: [AttributedString]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                Text(rows[index])
            }
        }
    }
}
