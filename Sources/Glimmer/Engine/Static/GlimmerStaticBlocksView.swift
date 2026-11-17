import SwiftUI

/// A stack of blocks, each below the one before by its `spacingAbove`.
struct GlimmerStaticBlocksView: View {
    let blocks: [GlimmerStaticBlock]
    let theme: GlimmerTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
                let block: GlimmerStaticBlock = blocks[index]
                GlimmerStaticBlockView(block: block, theme: theme)
                    .padding(.top, block.spacingAbove)
            }
        }
    }
}
