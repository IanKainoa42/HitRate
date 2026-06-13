import Foundation
import Observation
import HealthKit

/// Keeps the watch app awake during a practice via an `HKWorkoutSession`.
///
/// When the iPhone starts a practice it foregrounds this app (see
/// `PracticeWatchLauncher`); the running workout session is what then keeps the
/// app alive and reachable while the wrist drops, so logging stays instant.
/// Driven entirely by the snapshot's `isPracticeLive` flag — `sync(live:)`
/// starts the session when practice begins and ends it when it stops.
@Observable
final class WatchWorkoutManager: NSObject, HKWorkoutSessionDelegate {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    var isRunning = false

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()],
                                         read: []) { _, _ in }
    }

    /// Mirror the iPhone's practice state onto a workout session.
    func sync(live: Bool) {
        if live { start() } else { end() }
    }

    private func start() {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            s.delegate = self
            session = s
            s.startActivity(with: .now)
            isRunning = true
        } catch {
            session = nil
            isRunning = false
        }
    }

    private func end() {
        session?.end()
        session = nil
        isRunning = false
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        if toState == .ended || toState == .stopped {
            DispatchQueue.main.async { [weak self] in
                self?.session = nil
                self?.isRunning = false
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.session = nil
            self?.isRunning = false
        }
    }
}
