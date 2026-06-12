import SwiftUI

@main
struct HitRateWatchApp: App {
    @State private var store = WatchLogStore()

    var body: some Scene {
        WindowGroup {
            WatchLogView(store: store)
                .onAppear {
                    // Delay activation slightly to ensure the run loop is ready
                    // This helps prevent XPC/IPC issues with WatchConnectivity
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        store.activate()
                    }
                }
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
