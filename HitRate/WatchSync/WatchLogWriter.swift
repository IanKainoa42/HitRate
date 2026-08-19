import Foundation
import SwiftData

/// Persists wrist taps with at-least-once delivery semantics. WatchConnectivity
/// may deliver the same request through both `sendMessage` and queued user info,
/// so the request UUID is also the attempt's durable identity.
@MainActor
struct WatchLogWriter {
    let context: ModelContext

    func log(_ request: WatchLogRequest,
             groups: [StuntGroup],
             subject: Subject?,
             loggerID: String) -> Bool {
        guard let group = groups.first(where: { $0.id == request.groupID }),
              let outcome = Outcome(rawValue: request.outcomeRaw) else {
            return false
        }

        let requestCloudID = "watch-\(request.id.uuidString)"
        let duplicate = FetchDescriptor<Attempt>(
            predicate: #Predicate { $0.cloudID == requestCloudID }
        )
        do {
            if try context.fetch(duplicate).first != nil { return true }
        } catch {
            print("❌ Could not check Watch log identity: \(error.localizedDescription)")
            return false
        }

        let liveSessions = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let session: PracticeSession
        let createdSession: Bool
        do {
            if let live = try context.fetch(liveSessions).first {
                session = live
                createdSession = false
            } else {
                session = PracticeSession(startedAt: request.timestamp)
                context.insert(session)
                createdSession = true
            }
        } catch {
            print("❌ Could not resolve a session for Watch log: \(error.localizedDescription)")
            return false
        }

        let attempt = Attempt(outcome: outcome,
                              group: group,
                              session: session,
                              subject: subject,
                              timestamp: request.timestamp)
        attempt.cloudID = requestCloudID
        attempt.loggerID = loggerID
        context.insert(attempt)

        do {
            try context.save()
            return true
        } catch {
            context.delete(attempt)
            if createdSession { context.delete(session) }
            print("❌ Could not save Watch log: \(error.localizedDescription)")
            return false
        }
    }
}
