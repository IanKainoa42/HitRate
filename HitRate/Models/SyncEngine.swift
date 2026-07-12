import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Cloud sync coordinator (Firebase Firestore) for multi-user team sharing.
///
/// PHASE 1 (this file): wiring only — holds the model context and the Firestore
/// handle, starts/stops with the auth session, and exposes the surface the app
/// calls into. The actual document mirroring (push local → Firestore, listen
/// Firestore → local) is intentionally deferred to Phase 2, where it's written
/// against the CURRENT SwiftData schema (Team, Subject, StuntGroup with its full
/// field set, OutcomeTemplate, Attempt incl. execution + waveID, CustomOutcome/
/// CustomTally) — NOT the stale pre-subjects shape Codex's first draft targeted.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var modelContext: ModelContext?
    private var isRunning = false

    private init() {}

    /// Begin syncing for the signed-in user. Idempotent — safe to call on every
    /// launch / auth change.
    func startSyncing(context: ModelContext) {
        modelContext = context
        guard Auth.auth().currentUser != nil else { return }
        guard !isRunning else { return }
        isRunning = true
        // Phase 2: pushLocalData() + attach team/roster/attempt listeners here.
    }

    /// Tear down all listeners (called on sign-out).
    func stopSyncing() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        isRunning = false
    }
}
