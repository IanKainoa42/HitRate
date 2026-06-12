import Foundation
import Observation
import WatchConnectivity

@Observable
final class WatchLogStore: NSObject, WCSessionDelegate {
    var snapshot: WatchRosterSnapshot = .empty
    var statusText = "Connecting to iPhone"
    var isLogging = false

    private var session: WCSession? {
        #if targetEnvironment(simulator)
        // WatchConnectivity has XPC/IPC bugs on simulator (iOS 18/watchOS 11)
        // that cause -[OS_dispatch_mach_msg _setContext:] crashes.
        // Always return nil on simulator to avoid the crash.
        print("⚠️ WatchConnectivity disabled on simulator (known XPC bug)")
        return nil
        #else
        return WCSession.isSupported() ? WCSession.default : nil
        #endif
    }

    /// The skill pulled up on the iPhone — the watch has no picker of its own,
    /// it just mirrors the phone's selection (first group until one syncs).
    var selectedGroup: WatchGroupSnapshot? {
        guard !snapshot.groups.isEmpty else { return nil }
        if let selectedID = snapshot.selectedGroupID,
           let selected = snapshot.groups.first(where: { $0.id == selectedID }) {
            return selected
        }
        return snapshot.groups.first
    }

    override init() {
        super.init()
        // Don't activate here - WCSession delegate must be set on main thread
        // after the run loop is ready. Call activate() from .task or .onAppear
    }

    func activate() {
        print("🔵 Attempting to activate WatchConnectivity...")
        print("🔵 WCSession.isSupported: \(WCSession.isSupported())")
        
        guard let session else {
            print("❌ WCSession not supported on this device")
            #if targetEnvironment(simulator)
            // On simulator, load demo data so UI can be tested
            print("⚠️ Loading demo data for simulator testing")
            DispatchQueue.main.async { [weak self] in
                self?.snapshot = .screenshotDemo
                self?.statusText = "Simulator demo mode"
            }
            #endif
            return
        }
        
        print("🔵 Current activation state: \(session.activationState.rawValue)")
        
        #if targetEnvironment(simulator)
        // Skip WatchConnectivity on simulator to avoid XPC crash
        print("⚠️ Skipping WCSession activation on simulator (XPC issues)")
        print("⚠️ Use physical device for actual Watch Connectivity testing")
        DispatchQueue.main.async { [weak self] in
            self?.snapshot = .screenshotDemo
            self?.statusText = "Simulator: Use device for sync"
        }
        return
        #endif
        
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
                // If delegate is set but not activated, try to activate
                session.activate()
            } else {
                print("✅ Session already activated")
            }
        }
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
            if let error = error {
                self?.statusText = "Sync error: \(error.localizedDescription)"
                print("❌ Watch activation failed: \(error)")
                return
            }
            
            print("✅ Watch activated with state: \(activationState.rawValue)")
            
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
