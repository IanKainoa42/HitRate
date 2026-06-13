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

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    /// The skill the wrist currently has up (crown selection, clamped).
    var selectedGroup: WatchGroupSnapshot? {
        guard !snapshot.groups.isEmpty else { return nil }
        let i = min(max(0, selectionIndex), snapshot.groups.count - 1)
        return snapshot.groups[i]
    }

    override init() {
        super.init()
        workout.requestAuthorization()
        activate()
    }

    func activate() {
        guard let session else {
            statusText = "Watch sync unavailable"
            return
        }
        session.delegate = self
        session.activate()
    }

    func requestSnapshot() {
        guard let session else { return }
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
        guard let group = selectedGroup, let session else { return }
        isLogging = true
        statusText = "Logging"

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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if !session.receivedApplicationContext.isEmpty {
                self?.receive(message: session.receivedApplicationContext)
            }
            self?.requestSnapshot()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receiveOnMain(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receiveOnMain(message)
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
