import SwiftUI

extension View {
    /// A theme role's line spacing for the `Text`s inside, or, for `nil`, whatever spacing the host set.
    ///
    /// `Text` adds `lineSpacing` between its lines only, so a one-line block is as tall with it as without.
    func glimmerLineSpacing(_ spacing: CGFloat?) -> some View {
        transformEnvironment(\.lineSpacing) { value in
            if let spacing { value = spacing }
        }
    }
}
