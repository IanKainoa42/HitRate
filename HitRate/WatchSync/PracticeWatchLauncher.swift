import Foundation
import HealthKit

/// Opens the HitRate Apple Watch app the moment a practice begins on iPhone.
///
/// There is no generic "launch the watch app" API — the only sanctioned path
/// is to start a workout: `HKHealthStore.startWatchApp(with:)` foregrounds the
/// companion watch app, which then runs its OWN `HKWorkoutSession` to stay
/// alive while you log reps (see `WatchWorkoutManager` on the watch side).
///
/// We only ever touch HealthKit when an installed watch app is actually there,
/// so iPhone-only users never see a Health permission prompt.
enum PracticeWatchLauncher {
    private static let store = HKHealthStore()

    static func launchIfWatchAvailable() {
        guard WatchSessionBridge.shared.isWatchAppAvailable,
              HKHealthStore.isHealthDataAvailable() else { return }

        let share: Set = [HKObjectType.workoutType()]
        store.requestAuthorization(toShare: share, read: []) { granted, _ in
            guard granted else { return }
            let config = HKWorkoutConfiguration()
            config.activityType = .other
            config.locationType = .indoor
            store.startWatchApp(with: config) { _, _ in }
        }
    }
}
