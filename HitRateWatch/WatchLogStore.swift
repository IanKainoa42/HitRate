import Foundation
import Observation
import WatchConnectivity

@Observable
final class WatchLogStore: NSObject, WCSessionDelegate {
    var snapshot: WatchRosterSnapshot = .empty
    var statusText = "Connecting to iPhone"
    var isLogging = false

    /// Crown-driven selection. The watch now owns which skill is "up" — the
    /// crown scrolls `selectionIndex` through the roster and a tap toggles
    /// `locked` so an accidental turn mid-log can't bump the group. Seeded once
    /// from the iPhone's selection, then the wrist drives it.
    var selectionIndex = 0
    var locked = false
    private var didSeedSelection = false

    /// Runs an HKWorkoutSession whenever the phone has a live practice so the
    /// app stays foregrounded/reachable while logging from the wrist.
    let workout = WatchWorkoutManager()

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// The skill the wrist currently has up (crown selection, clamped).
    var selectedGroup: WatchGroupSnapshot? {
        guard !snapshot.groups.isEmpty else { return nil }
        let i = min(max(0, selectionIndex), snapshot.groups.count - 1)
        return snapshot.groups[i]
    }

    override init() {
        super.init()
        // Requesting HealthKit auth is safe in init (no WCSession run-loop
        // dependency). Do NOT activate() here — WCSession's delegate must be
        // set on the main thread once the run loop is ready, so activation is
        // deferred to HitRateWatchApp's .onAppear (avoids the XPC/IPC crash).
        workout.requestAuthorization()
    }

    func activate() {
        print("🔵 Attempting to activate WatchConnectivity...")
        print("🔵 WCSession.isSupported: \(WCSession.isSupported())")

        guard let session else {
            print("❌ WCSession not supported on this device")
            #if targetEnvironment(simulator)
            if snapshot.groups.isEmpty {
                snapshot = .screenshotDemo
                statusText = "Simulator demo mode"
            }
            #endif
            return
        }

        print("🔵 Current activation state: \(session.activationState.rawValue)")

        // CRITICAL: WCSession.delegate must be set on main thread
        // Use async after to ensure run loop is fully ready
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            print("🔵 Setting delegate on main thread...")

            // Only set delegate if not already set (avoid re-activation issues)
            if session.delegate == nil {
                print("🔵 Delegate is nil, setting and activating...")
                session.delegate = self
                session.activate()
            } else if session.activationState != .activated {
                print("🔵 Delegate exists but not activated, attempting activation...")
                session.activate()
            } else {
                print("✅ Session already activated")
            }
        }
    }

    func requestSnapshot() {
        guard let session else {
            #if targetEnvironment(simulator)
            if snapshot.groups.isEmpty {
                snapshot = .screenshotDemo
                statusText = "Simulator demo mode"
            }
            #endif
            return
        }
        let message = [WatchPayloadCodec.typeKey: WatchPayloadCodec.snapshotRequest]
        if session.isReachable {
            session.sendMessage(message) { [weak self] reply in
                DispatchQueue.main.async { self?.receive(message: reply) }
            } errorHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.statusText = "Open HitRate on iPhone"
                }
            }
        } else {
            statusText = snapshot.groups.isEmpty ? "Open HitRate on iPhone" : "Using last roster"
        }
    }

    func log(outcome: WatchOutcomeSnapshot) {
        guard let group = selectedGroup else { return }

        // Optimistically increment local count for instant wrist feedback
        incrementLocalCount(groupID: group.id, outcomeRaw: outcome.rawValue)

        guard let session else {
            isLogging = false
            return
        }

        isLogging = true

        let request = WatchLogRequest(id: UUID(),
                                      groupID: group.id,
                                      outcomeRaw: outcome.rawValue,
                                      timestamp: .now)
        let message = WatchPayloadCodec.message(type: WatchPayloadCodec.logAttempt,
                                                payload: request)

        if session.isReachable {
            session.sendMessage(message) { [weak self] reply in
                DispatchQueue.main.async {
                    self?.isLogging = false
                    self?.receive(message: reply)
                }
            } errorHandler: { [weak self] _ in
                session.transferUserInfo(message)
                DispatchQueue.main.async {
                    self?.isLogging = false
                    self?.statusText = "Queued for iPhone"
                }
            }
        } else {
            session.transferUserInfo(message)
            isLogging = false
            statusText = "Queued for iPhone"
        }
    }

    private func incrementLocalCount(groupID: UUID, outcomeRaw: Int) {
        guard let groupIdx = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
        var group = snapshot.groups[groupIdx]
        if outcomeRaw >= 0 && outcomeRaw < group.counts.count {
            group.counts[outcomeRaw] += 1
            snapshot.groups[groupIdx] = group
            snapshot.activeSessionReps += 1
            statusText = "\(snapshot.activeSessionReps) reps live"
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                self?.statusText = "Sync error: \(error.localizedDescription)"
                print("❌ Watch activation failed: \(error)")
                #if targetEnvironment(simulator)
                if self?.snapshot.groups.isEmpty == true {
                    self?.snapshot = .screenshotDemo
                    self?.statusText = "Simulator demo mode"
                }
                #endif
                return
            }

            print("✅ Watch activated with state: \(activationState.rawValue)")

            if !session.receivedApplicationContext.isEmpty {
                self?.receive(message: session.receivedApplicationContext)
            }
            self?.requestSnapshot()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if session.isReachable {
                self.requestSnapshot()
            } else {
                if self.snapshot.groups.isEmpty {
                    self.statusText = "Open HitRate on iPhone"
                } else {
                    self.statusText = "Using last roster"
                }
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receiveOnMain(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receiveOnMain(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        receiveOnMain(userInfo)
    }

    private func receiveOnMain(_ message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.receive(message: message)
        }
    }

    private func receive(message: [String: Any]) {
        guard (message[WatchPayloadCodec.typeKey] as? String) == WatchPayloadCodec.snapshot,
              let snapshot = WatchPayloadCodec.decode(WatchRosterSnapshot.self, from: message) else {
            statusText = "Could not sync"
            return
        }

        self.snapshot = snapshot

        // Seed the crown selection from the phone's pulled-up skill on first
        // sync; afterwards the wrist owns it. Always clamp in case the roster
        // shrank under us.
        if !didSeedSelection, !snapshot.groups.isEmpty {
            if let target = snapshot.selectedGroupID,
               let idx = snapshot.groups.firstIndex(where: { $0.id == target }) {
                selectionIndex = idx
            }
            didSeedSelection = true
        }
        if !snapshot.groups.isEmpty {
            selectionIndex = min(max(0, selectionIndex), snapshot.groups.count - 1)
        }

        // Mirror the phone's live-practice state onto the workout session.
        workout.sync(live: snapshot.isPracticeLive)

        statusText = snapshot.groups.isEmpty
            ? "Add \(snapshot.nounPlural) on iPhone"
            : "\(snapshot.activeSessionReps) reps live"
    }
}
