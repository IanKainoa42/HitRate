import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

@MainActor
class SyncEngine: ObservableObject {
    static let shared = SyncEngine()
    
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    
    var modelContext: ModelContext?
    
    private init() {}
    
    func startSyncing(context: ModelContext) {
        self.modelContext = context
        
        // Only sync if user is authenticated
        guard let currentUser = Auth.auth().currentUser else { return }
        
        // Push local unsynced data
        pushLocalDataToFirestore(userId: currentUser.uid)
        
        // Setup listeners for teams you are a part of
        listenToMyTeams(userId: currentUser.uid)
    }
    
    func stopSyncing() {
        for listener in listeners {
            listener.remove()
        }
        listeners.removeAll()
    }
    
    // MARK: - Push Local Data
    
    private func pushLocalDataToFirestore(userId: String) {
        guard let context = modelContext else { return }
        
        do {
            let teams = try context.fetch(FetchDescriptor<Team>())
            for team in teams {
                push(team: team, ownerId: userId)
            }
            
            let groups = try context.fetch(FetchDescriptor<StuntGroup>())
            for group in groups {
                push(group: group)
            }
            
            let attempts = try context.fetch(FetchDescriptor<Attempt>())
            for attempt in attempts {
                push(attempt: attempt, loggerId: userId)
            }
        } catch {
            print("Error fetching local data for sync: \(error)")
        }
    }
    
    func push(team: Team, ownerId: String) {
        if team.joinCode == nil {
            team.joinCode = String(format: "%06d", Int.random(in: 0...999999))
            try? modelContext?.save()
        }
        
        let fTeam = FTeam(id: team.id.uuidString,
                          name: team.name,
                          ownerId: ownerId,
                          memberIds: nil, // Don't overwrite existing members
                          orderIndex: team.orderIndex,
                          joinCode: team.joinCode)
        
        do {
            try db.collection("teams").document(team.id.uuidString).setData(from: fTeam, merge: true)
        } catch {
            print("Error pushing team: \(error)")
        }
    }
    
    func joinTeam(code: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let snapshot = try await db.collection("teams").whereField("joinCode", isEqualTo: code).getDocuments()
        guard let doc = snapshot.documents.first else {
            throw NSError(domain: "SyncEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "Invalid join code."])
        }
        
        try await doc.reference.updateData([
            "memberIds": FieldValue.arrayUnion([userId])
        ])
    }
    
    func push(group: StuntGroup) {
        guard let teamId = group.team?.id.uuidString else { return }
        let fGroup = FStuntGroup(id: group.id.uuidString,
                                 teamId: teamId,
                                 name: group.name,
                                 number: group.number,
                                 orderIndex: group.orderIndex,
                                 kindRaw: group.kindRaw,
                                 deletedAt: group.deletedAt)
        do {
            try db.collection("groups").document(group.id.uuidString).setData(from: fGroup)
        } catch {
            print("Error pushing group: \(error)")
        }
    }
    
    func push(attempt: Attempt, loggerId: String) {
        guard let groupId = attempt.group?.id.uuidString,
              let teamId = attempt.group?.team?.id.uuidString else { return }
        let fAttempt = FAttempt(id: attempt.id.uuidString,
                                groupId: groupId,
                                teamId: teamId,
                                outcomeRaw: attempt.outcomeRaw,
                                timestamp: attempt.timestamp,
                                loggerId: loggerId)
        do {
            try db.collection("attempts").document(attempt.id.uuidString).setData(from: fAttempt)
        } catch {
            print("Error pushing attempt: \(error)")
        }
    }
    
    func delete(attempt: Attempt) {
        db.collection("attempts").document(attempt.id.uuidString).delete { error in
            if let error = error {
                print("Error deleting attempt: \(error)")
            }
        }
    }
    
    // MARK: - Listen to Remote Data
    
    private func listenToMyTeams(userId: String) {
        // Listen to teams I own
        let ownerQuery = db.collection("teams").whereField("ownerId", isEqualTo: userId)
        let ownerListener = ownerQuery.addSnapshotListener { [weak self] snapshot, error in
            self?.handleTeamsSnapshot(snapshot: snapshot, error: error)
        }
        listeners.append(ownerListener)
        
        // Listen to teams I am a member of
        let memberQuery = db.collection("teams").whereField("memberIds", arrayContains: userId)
        let memberListener = memberQuery.addSnapshotListener { [weak self] snapshot, error in
            self?.handleTeamsSnapshot(snapshot: snapshot, error: error)
        }
        listeners.append(memberListener)
    }
    
    private func handleTeamsSnapshot(snapshot: QuerySnapshot?, error: Error?) {
        guard let documents = snapshot?.documents, let context = modelContext else { return }
        
        for doc in documents {
            guard let fTeam = try? doc.data(as: FTeam.self), let id = UUID(uuidString: doc.documentID) else { continue }
            
            // Check if team exists locally
            let fetchDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == id })
            if let existingTeam = try? context.fetch(fetchDescriptor).first {
                existingTeam.name = fTeam.name
                existingTeam.orderIndex = fTeam.orderIndex
                existingTeam.joinCode = fTeam.joinCode
            } else {
                let newTeam = Team(name: fTeam.name, orderIndex: fTeam.orderIndex)
                newTeam.id = id
                newTeam.joinCode = fTeam.joinCode
                context.insert(newTeam)
            }
            
            // Also listen to groups and attempts for this team
            listenToGroupsAndAttempts(for: doc.documentID)
        }
        try? context.save()
    }
    
    private func listenToGroupsAndAttempts(for teamId: String) {
        let groupsListener = db.collection("groups").whereField("teamId", isEqualTo: teamId).addSnapshotListener { [weak self] snapshot, _ in
            self?.handleGroupsSnapshot(snapshot: snapshot)
        }
        listeners.append(groupsListener)
        
        let attemptsListener = db.collection("attempts").whereField("teamId", isEqualTo: teamId).addSnapshotListener { [weak self] snapshot, _ in
            self?.handleAttemptsSnapshot(snapshot: snapshot)
        }
        listeners.append(attemptsListener)
    }
    
    private func handleGroupsSnapshot(snapshot: QuerySnapshot?) {
        guard let documents = snapshot?.documents, let context = modelContext else { return }
        for change in snapshot.documentChanges {
            let doc = change.document
            guard let fGroup = try? doc.data(as: FStuntGroup.self),
                  let id = UUID(uuidString: doc.documentID),
                  let teamUUID = UUID(uuidString: fGroup.teamId) else { continue }
            
            let fetchDescriptor = FetchDescriptor<StuntGroup>(predicate: #Predicate { $0.id == id })
            if let existingGroup = try? context.fetch(fetchDescriptor).first {
                existingGroup.name = fGroup.name
                existingGroup.number = fGroup.number
                existingGroup.orderIndex = fGroup.orderIndex
                existingGroup.kindRaw = fGroup.kindRaw
                existingGroup.deletedAt = fGroup.deletedAt
            } else if fGroup.deletedAt == nil {
                // Find team
                let teamFetch = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamUUID })
                if let team = try? context.fetch(teamFetch).first {
                    let newGroup = StuntGroup(name: fGroup.name, number: fGroup.number, orderIndex: fGroup.orderIndex)
                    newGroup.id = id
                    newGroup.kindRaw = fGroup.kindRaw
                    newGroup.team = team
                    context.insert(newGroup)
                }
            }
        }
        try? context.save()
    }
    
    private func handleAttemptsSnapshot(snapshot: QuerySnapshot?) {
        guard let documents = snapshot?.documents, let context = modelContext else { return }
        for change in snapshot.documentChanges {
            let doc = change.document
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            
            if change.type == .removed {
                let fetchDescriptor = FetchDescriptor<Attempt>(predicate: #Predicate { $0.id == id })
                if let existing = try? context.fetch(fetchDescriptor).first {
                    context.delete(existing)
                }
                continue
            }
            
            guard let fAttempt = try? doc.data(as: FAttempt.self),
                  let groupUUID = UUID(uuidString: fAttempt.groupId),
                  let outcome = Outcome(rawValue: fAttempt.outcomeRaw) else { continue }
            
            let fetchDescriptor = FetchDescriptor<Attempt>(predicate: #Predicate { $0.id == id })
            if let _ = try? context.fetch(fetchDescriptor).first {
                // Ignore existing
            } else {
                let groupFetch = FetchDescriptor<StuntGroup>(predicate: #Predicate { $0.id == groupUUID })
                if let group = try? context.fetch(groupFetch).first {
                    // Create session if needed or just use active
                    // For simplicity, find session around that time or create a generic one
                    let sessionFetch = FetchDescriptor<PracticeSession>()
                    let sessions = (try? context.fetch(sessionFetch)) ?? []
                    let session = sessions.first { abs($0.startedAt.timeIntervalSince(fAttempt.timestamp)) < 3600 } ?? PracticeSession(startedAt: fAttempt.timestamp)
                    if session.modelContext == nil {
                        context.insert(session)
                    }
                    
                    let newAttempt = Attempt(outcome: outcome, group: group, session: session, timestamp: fAttempt.timestamp)
                    newAttempt.id = id
                    context.insert(newAttempt)
                }
            }
        }
        try? context.save()
    }
}
