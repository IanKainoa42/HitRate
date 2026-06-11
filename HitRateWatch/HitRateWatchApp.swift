import SwiftUI

@main
struct HitRateWatchApp: App {
    @State private var store = WatchLogStore()

    var body: some Scene {
        WindowGroup {
            WatchLogView(store: store)
                .task {
                    // App Store screenshot rig: `--demo-roster` seeds a local
                    // snapshot so captures don't depend on a live WCSession
                    // pairing (flaky between paired simulators).
                    if ProcessInfo.processInfo.arguments.contains("--demo-roster") {
                        store.snapshot = .screenshotDemo
                    }
                }
        }
    }
}
