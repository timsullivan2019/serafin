import SwiftUI

/// The root of Serafin's interface: the tab bar every screen hangs from.
public struct RootView: View {
    /// Creates the root view.
    public init() {}

    public var body: some View {
        TabView {}
    }
}

#Preview {
    RootView()
}
