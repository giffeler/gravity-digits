import SwiftUI

@main
struct GravityDigitsApp: App {
    var body: some Scene {
        WindowGroup {
            ClockDisplayView()
                .persistentSystemOverlays(.hidden)
        }
    }
}
