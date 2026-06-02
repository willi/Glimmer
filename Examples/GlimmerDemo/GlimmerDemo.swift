import SwiftUI
import Glimmer

/// GlimmerDemo library - Example views demonstrating Glimmer markdown parsing capabilities
public struct GlimmerDemo {
    public static let version = "1.0.0"
    
    /// Main demo app content view
    public static func mainView() -> some View {
        ContentView()
    }
    
    /// Core demo views
    public static func basicFeaturesDemo() -> some View {
        BasicFeaturesDemo()
    }
    
    public static func advancedDemo() -> some View {
        AdvancedDemo()
    }
    
    public static func linterDemo() -> some View {
        LinterDemoView()
    }
}