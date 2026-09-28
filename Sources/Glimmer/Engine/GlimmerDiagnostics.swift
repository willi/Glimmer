/// Counters for the demo's benchmark. Not API: reach them with `@_spi(Diagnostics) import Glimmer`.
@_spi(Diagnostics)
@MainActor
public enum GlimmerDiagnostics {
    /// Viewport passes every Glimmer text view has run so far. Each pass lays out and renders the band around the screen.
    public static var viewportPasses: Int { GlimmerTextView.allViewportPasses }
}
