import Foundation
import WatchConnectivity

final class WatchSessionBridge: NSObject, WCSessionDelegate {
    static let shared = WatchSessionBridge()

    private var snapshotProvider: (() -> WatchRosterSnapshot)?
    private var logHandler: ((WatchLogRequest) -> WatchRosterSnapshot?)?
    private var lastSnapshot: WatchRosterSnapshot?

    private override init() {
        super.init()
    }

    var status: WatchConnectionStatus {
        guard WCSession.isSupported() else { return .unsupported }
        let session = WCSession.default
        guard session.activationState == .activated else { return .activating }
        guard session.isPaired else { return .notPaired }
        guard session.isWatchAppInstalled else { return .notInstalled }
        return session.isReachable ? .ready : .installed
    }

    func configure(snapshotProvider: @escaping () -> WatchRosterSnapshot,
                   logHandler: @escaping (WatchLogRequest) -> WatchRosterSnapshot?) {
        self.snapshotProvider = snapshotProvider
        self.logHandler = logHandler

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate !== self {
            session.delegate = self
            session.activate()
        }
        publishSnapshot(snapshotProvider())
    }

    func publishSnapshot(_ snapshot: WatchRosterSnapshot) {
        guard WCSession.isSupported() else { return }
        guard lastSnapshot != snapshot else { return }
        lastSnapshot = snapshot

        let message = WatchPayloadCodec.message(type: WatchPayloadCodec.snapshot,
                                                payload: snapshot)
        try? WCSession.default.updateApplicationContext(message)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error = error {
            print("❌ Watch session activation failed: \(error.localizedDescription)")
        } else {
            print("✅ Watch session activated with state: \(activationState.rawValue)")
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let snapshot = self?.snapshotProvider?() else { return }
            self?.publishSnapshot(snapshot)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message: message, replyHandler: nil)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message: message, replyHandler: replyHandler)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(message: userInfo, replyHandler: nil)
    }

    private func handle(message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let type = message[WatchPayloadCodec.typeKey] as? String

            switch type {
            case WatchPayloadCodec.snapshotRequest:
                guard let snapshot = snapshotProvider?() else {
                    replyHandler?([WatchPayloadCodec.typeKey: WatchPayloadCodec.error])
                    return
                }
                publishSnapshot(snapshot)
                replyHandler?(WatchPayloadCodec.message(type: WatchPayloadCodec.snapshot,
                                                         payload: snapshot))

            case WatchPayloadCodec.logAttempt:
                guard let request = WatchPayloadCodec.decode(WatchLogRequest.self, from: message),
                      let snapshot = logHandler?(request) else {
                    replyHandler?([WatchPayloadCodec.typeKey: WatchPayloadCodec.error])
                    return
                }
                publishSnapshot(snapshot)
                replyHandler?(WatchPayloadCodec.message(type: WatchPayloadCodec.snapshot,
                                                         payload: snapshot))

            default:
                replyHandler?([WatchPayloadCodec.typeKey: WatchPayloadCodec.error])
            }
        }
    }
}

enum WatchConnectionStatus {
    case unsupported
    case activating
    case notPaired
    case notInstalled
    case installed
    case ready

    var title: String {
        switch self {
        case .unsupported: "Watch unavailable"
        case .activating: "Checking watch"
        case .notPaired: "No paired watch"
        case .notInstalled: "Install on watch"
        case .installed: "Watch installed"
        case .ready: "Watch ready"
        }
    }

    var detail: String {
        switch self {
        case .unsupported: "This iPhone cannot use Apple Watch logging."
        case .activating: "Open HitRate on iPhone for a moment."
        case .notPaired: "Pair an Apple Watch with this iPhone."
        case .notInstalled: "Open the Watch app on iPhone and install HitRate."
        case .installed: "Open HitRate on Apple Watch to log reps."
        case .ready: "HitRate is open on Apple Watch."
        }
    }
}
