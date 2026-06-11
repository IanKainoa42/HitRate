import Foundation
import Observation
import WatchConnectivity

@Observable
final class WatchLogStore: NSObject, WCSessionDelegate {
    var snapshot: WatchRosterSnapshot = .empty
    var statusText = "Connecting to iPhone"
    var isLogging = false

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    /// The skill pulled up on the iPhone — the watch has no picker of its own,
    /// it just mirrors the phone's selection (first group until one syncs).
    var selectedGroup: WatchGroupSnapshot? {
        snapshot.groups.first { $0.id == snapshot.selectedGroupID }
            ?? snapshot.groups.first
    }

    override init() {
        super.init()
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
        statusText = snapshot.groups.isEmpty
            ? "Add \(snapshot.nounPlural) on iPhone"
            : "\(snapshot.activeSessionReps) reps live"
    }
}
