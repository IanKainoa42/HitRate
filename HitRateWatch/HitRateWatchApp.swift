import SwiftUI

@main
struct HitRateWatchApp: App {
    @State private var store = WatchLogStore()

    var body: some Scene {
        WindowGroup {
            WatchLogView(store: store)
        }
    }
}
