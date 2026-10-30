import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Backup + destructive data controls, pushed from the editor.
///
/// Erase paths delete IN PLACE and never auto-pop: deleting every `StuntGroup`
/// while the editor's `ForEach(groups)` (and Home's dashboard) animate a pop is
/// the same mid-dismiss crash class the counter and Home already defend against
/// (see LogView:119 "mutating-then-rendering a deleted model mid-animation
/// crashes" and HomeView's delete-on-dismiss). By staying put, the only live
/// surface that mutates is this view's counts (Int → 0, crash-safe); the editor
/// underneath reconciles its roster off-screen with no animation race. The user
/// taps Back when ready, by which point the delete has fully settled.
struct DataManagementView: View {
    /// The folder this screen was opened from — scopes the "this folder only"
    /// actions. Nil only if presented without a current team (shouldn't happen
    /// in practice; the folder-scoped section just hides itself).
    let team: Team?

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthViewModel
    @Query(sort: \StuntGroup.orderIndex) private var groups: [StuntGroup]
    @Query(sort: \Team.orderIndex) private var teams: [Team]
    @Query private var sessions: [PracticeSession]
    @Query private var attempts: [Attempt]
    @Query private var subjects: [Subject]
    @Query private var customTallies: [CustomTally]

    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("replayingIntro") private var replayingIntro = false
    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    private enum Confirm { case clearFolderHistory, clearHistory, eraseAll }
    @State private var confirm: Confirm?
    @State private var paywallOpen = false
    @State private var moreAppsOpen = false
    @State private var importingTumble = false
    @State private var tumbleArchives = TumbleArchive.all()
    @State private var cloudRecordings: [TumbleCloudSync.Recording] = []
    @State private var cloudError: String?
    @State private var loadingTumbles = false
    @State private var tumbleMessage: String?
    @State private var tumbleAthletes = UserDefaults.standard.dictionary(forKey: "tumbleAthleteIDs") as? [String: String] ?? [:]
    @ObservedObject private var coach = CoachEntitlement.shared
    /// Trash-row "Delete permanently" awaiting confirmation (name shown + the
    /// hard-delete to run if the user confirms).
    @State private var pendingPurge: (name: String, action: () -> Void)?

    private var glassRow: Color { Theme.well }
    private var hasReps: Bool { !attempts.isEmpty }
    private var hasAnything: Bool { !groups.isEmpty || !attempts.isEmpty || !sessions.isEmpty }

    private var trashedTeams: [Team] { teams.trashed }
    private var trashedGroups: [StuntGroup] { groups.trashed }
    private var hasTrash: Bool { !trashedTeams.isEmpty || !trashedGroups.isEmpty }

    private var folderName: String { team?.name ?? "this deck" }
    private var folderAttempts: [Attempt] { attempts.filter { $0.group?.team?.id == team?.id } }
    private var hasFolderReps: Bool { !folderAttempts.isEmpty }
    private var cloudKey: String { "\(team?.id.uuidString ?? ""):\(auth.uid ?? "")" }
    private var allTumbleArchives: [TumbleArchive] {
        let cloud = cloudRecordings.map(\.reviewedArchive)
        let cloudIDs = Set(cloud.map(\.recordingID))
        return cloud + tumbleArchives.filter { !cloudIDs.contains($0.recordingID) }
    }
    private var effectiveTumbleAthletes: [String: String] {
        var mapped = cloudRecordings.reduce(into: [String: String]()) { result, recording in
            for (track, athleteID) in recording.athleteIDs {
                result["\(recording.archive.recordingID.uuidString):\(track)"] = athleteID
            }
        }
        mapped.merge(tumbleAthletes) { _, local in local }
        return mapped
    }
    private var tumbleAthleteNames: [String: String] {
        Dictionary(uniqueKeysWithValues: subjects.filter {
            $0.team?.id == team?.id && $0.deletedAt == nil
        }.map { ($0.id.uuidString, $0.name) })
    }

    var body: some View {
        List {
            Section {
                summaryRow(mode.nounPluralTitle, groups.active.count)
                summaryRow("Reps", attempts.count)
                summaryRow("Sessions", sessions.count)
            } header: {
                Text("Stored on this device")
            }
            .listRowBackground(glassRow)

            Section {
                let csv = CSVExportItem(sessions: sessions)
                if csv.hasData, !coach.isCoach {
                    Button { paywallOpen = true } label: {
                        Label("Export CSV backup", systemImage: "arrow.down.to.line")
                            .badge(Text("COACH").font(.system(size: 10, weight: .heavy)))
                    }
                } else if csv.hasData {
                    ShareLink(item: csv, preview: SharePreview("HitRate practice data")) {
                        Label("Export CSV backup", systemImage: "arrow.down.to.line")
                    }
                } else {
                    Label("Nothing to export yet", systemImage: "arrow.down.to.line")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Save a spreadsheet of every rep before you delete anything below — these deletes can't be undone.")
            }
            .listRowBackground(glassRow)

            Section {
                if loadingTumbles { ProgressView("Syncing from StuntScope…") }
                Button { Task { await refreshTumbles() } } label: {
                    Label("Refresh tumbling data", systemImage: "arrow.clockwise")
                }
                if let cloudError { Text(cloudError).foregroundStyle(.red) }
                let spreadsheet = TumbleSpreadsheet(archives: allTumbleArchives, athleteIDs: effectiveTumbleAthletes,
                    athleteNamesByID: tumbleAthleteNames)
                let poseSpreadsheet = TumblePoseSpreadsheet(archives: allTumbleArchives, athleteIDs: effectiveTumbleAthletes,
                    athleteNamesByID: tumbleAthleteNames)
                if spreadsheet.hasData {
                    ForEach(allTumbleArchives, id: \.recordingID) { archive in
                        ForEach(Array(Set(archive.blocks.map(\.trackID))).sorted(), id: \.self) { track in
                            tumbleTrackPicker(archive: archive, track: track)
                        }
                        ForEach(Array(archive.blocks.enumerated()), id: \.offset) { item in
                            tumbleBlockRow(archive: archive, block: item.element)
                        }
                    }
                    if coach.isCoach {
                        ShareLink(item: spreadsheet, preview: SharePreview("Tumbling skill blocks")) {
                            Label("Export tumble spreadsheet", systemImage: "tablecells")
                        }
                        if poseSpreadsheet.hasData {
                            ShareLink(item: poseSpreadsheet, preview: SharePreview("Tumbling pose frames")) {
                                Label("Export pose frame spreadsheet", systemImage: "figure.stand")
                            }
                        }
                    } else {
                        Button { paywallOpen = true } label: {
                            Label("Export tumble spreadsheet", systemImage: "tablecells")
                        }
                    }
                    Text("\(cloudRecordings.count) synced video\(cloudRecordings.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                Button { importingTumble = true } label: {
                    Label("Import older tumble file…", systemImage: "square.and.arrow.down")
                }
                if let tumbleMessage { Text(tumbleMessage).foregroundStyle(.secondary) }
            } header: { Text("Tumbling analysis") } footer: {
                Text("StuntScope syncs tracked athletes and skill blocks here through your HitRate account.")
            }
            .listRowBackground(glassRow)

            Section {
                Button {
                    paywallOpen = true
                } label: {
                    Label(coach.isCoach ? "HitRate Coach · active" : "HitRate Coach",
                          systemImage: coach.isCoach ? "checkmark.seal.fill" : "person.2.fill")
                }
                Button {
                    moreAppsOpen = true
                } label: {
                    Label("More coaching tools", systemImage: "square.grid.2x2")
                }
            } header: {
                Text("From the same coach")
            } footer: {
                Text(coach.isCoach ? "Sharing, unlimited decks, homework and CSV are unlocked on this Apple ID."
                                   : "Athletes track free. Coach unlocks sharing by code, unlimited decks, homework and CSV backup.")
            }
            .listRowBackground(glassRow)

            Section {
                Button {
                    // Non-destructive: flips back to first-launch setup. The
                    // flag keeps RootView's pre-onboarding migration from
                    // instantly re-completing it (groups exist).
                    replayingIntro = true
                    didOnboard = false
                } label: {
                    Label("Replay intro", systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text("Runs the first-launch setup again. Nothing is deleted — your \(mode.nounPlural) and reps stay, and anything you add joins your current team.")
            }
            .listRowBackground(glassRow)

            if hasTrash {
                Section {
                    ForEach(trashedTeams) { t in
                        trashRow(name: t.name,
                                 detail: "Deck · \(allActiveSkills(t)) \(mode.nounPlural)",
                                 restore: { restore(team: t) },
                                 purge: { purge(team: t) })
                    }
                    ForEach(trashedGroups) { g in
                        trashRow(name: g.name,
                                 detail: "\(mode.nounTitle) · \(g.attempts.count) reps",
                                 restore: { restore(group: g) },
                                 purge: { purge(group: g) })
                    }
                } header: {
                    Text("Trash")
                } footer: {
                    Text("Swipe right to Restore (brings it back with its reps), or left to Delete permanently — that one can't be undone.")
                }
                .listRowBackground(glassRow)
            }

            if team != nil {
                Section {
                    Button(role: .destructive) {
                        confirm = .clearFolderHistory
                    } label: {
                        Label("Clear history in \(folderName)", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(!hasFolderReps)
                } header: {
                    Text("This deck")
                } footer: {
                    Text("Deletes only \(folderName)'s logged reps and sessions. Its \(mode.nounPlural) stay, and your other decks aren't touched.")
                }
                .listRowBackground(glassRow)
            }

            Section {
                Button(role: .destructive) {
                    confirm = .clearHistory
                } label: {
                    Label("Clear history in every deck", systemImage: "clock.arrow.circlepath")
                }
                .disabled(!hasReps)
            } header: {
                Text("All decks")
            } footer: {
                Text("Deletes every logged rep and session across ALL your decks — not just \(folderName). Your \(mode.nounPlural) stay everywhere. Stats reset to zero.")
            }
            .listRowBackground(glassRow)

            Section {
                Button(role: .destructive) {
                    confirm = .eraseAll
                } label: {
                    Label("Erase every deck", systemImage: "trash")
                }
                .disabled(!hasAnything)
            } header: {
                Text("Danger zone — all decks")
            } footer: {
                Text("Deletes every deck on this device (including \(folderName)), every skill, rep, and session — a clean slate. Your name and custom outcome labels stay.")
            }
            .listRowBackground(glassRow)
        }
        .scrollContentBackground(.hidden)
        .background(FloorBackdrop().ignoresSafeArea())
        .navigationTitle("Manage Data")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: cloudKey) { await refreshTumbles() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshTumbles() } }
        }
        .fileImporter(isPresented: $importingTumble, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let archive = try TumbleArchive.importFile(url)
                tumbleArchives = TumbleArchive.all()
                tumbleMessage = "Imported \(archive.blocks.count) tagged blocks from \(archive.recordingTitle). Assign athlete names before comparing tracks across videos."
            } catch {
                tumbleMessage = "Import failed: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $paywallOpen) {
            CoachPaywallView(reason: coach.isCoach ? .general : .csv)
        }
        .sheet(isPresented: $moreAppsOpen) {
            MoreCoachingAppsView()
        }
        .alert(
            "Clear history in \(folderName)?",
            isPresented: Binding(
                get: { confirm == .clearFolderHistory },
                set: { if !$0 { confirm = nil } })
        ) {
            Button("Clear history", role: .destructive) { clearFolderHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(folderAttempts.count) rep\(folderAttempts.count == 1 ? "" : "s") in \(folderName) will be deleted. Its \(mode.nounPlural) stay, and your other decks aren't touched. This can't be undone.")
        }
        .alert(
            "Clear history in every deck?",
            isPresented: Binding(
                get: { confirm == .clearHistory },
                set: { if !$0 { confirm = nil } })
        ) {
            Button("Clear history", role: .destructive) { clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All \(attempts.count) reps and \(sessions.count) sessions across every deck — not just \(folderName) — will be deleted. Your \(mode.nounPlural) stay. This can't be undone.")
        }
        .alert(
            "Erase every deck?",
            isPresented: Binding(
                get: { confirm == .eraseAll },
                set: { if !$0 { confirm = nil } })
        ) {
            Button("Erase everything", role: .destructive) { eraseAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every deck on this device (including \(folderName)) — \(groups.count) \(mode.nounPlural), \(attempts.count) reps, and \(sessions.count) sessions — will be permanently deleted.")
        }
        .alert(
            "Delete \(pendingPurge?.name ?? "") permanently?",
            isPresented: Binding(
                get: { pendingPurge != nil },
                set: { if !$0 { pendingPurge = nil } })
        ) {
            Button("Delete permanently", role: .destructive) { pendingPurge?.action() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private func refreshTumbles() async {
        guard auth.uid != nil, let team else { return }
        loadingTumbles = true
        defer { loadingTumbles = false }
        do {
            cloudRecordings = try await TumbleCloudSync.load(teamID: team.id.uuidString)
            cloudError = nil
        } catch {
            cloudError = "Couldn't sync tumbling: \(error.localizedDescription)"
        }
    }

    private func tumbleTrackPicker(archive: TumbleArchive, track: Int) -> some View {
        let key = "\(archive.recordingID.uuidString):\(track)"
        let selection = Binding<String>(
            get: { effectiveTumbleAthletes[key] ?? "" },
            set: { value in
                if value.isEmpty { tumbleAthletes.removeValue(forKey: key) }
                else { tumbleAthletes[key] = value }
                UserDefaults.standard.set(tumbleAthletes, forKey: "tumbleAthleteIDs")
            })
        return Picker("\(archive.recordingTitle) · track \(track)", selection: selection) {
            Text("Assign athlete").tag("")
            ForEach(subjects.filter { $0.team?.id == team?.id && $0.deletedAt == nil }) { subject in
                Text(subject.name).tag(subject.id.uuidString)
            }
        }
    }

    private func tumbleBlockRow(archive: TumbleArchive, block: TumbleArchive.Block) -> some View {
        let key = "\(archive.recordingID.uuidString):\(block.trackID)"
        let athlete = effectiveTumbleAthletes[key].flatMap { tumbleAthleteNames[$0] }
            ?? "Track \(block.trackID)"
        return TumbleBlockRow(block: block, athlete: athlete)
    }

    private func allActiveSkills(_ t: Team) -> Int {
        groups.filter { $0.team?.id == t.id && $0.deletedAt == nil }.count
    }

    private func trashRow(name: String, detail: String,
                          restore: @escaping () -> Void,
                          purge: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 15, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") { withAnimation { restore() } }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Restore") { withAnimation { restore() } }.tint(Theme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete permanently", role: .destructive) {
                pendingPurge = (name, { withAnimation { purge() } })
            }
        }
    }

    // MARK: Trash actions

    private func restore(team t: Team) { t.deletedAt = nil; try? context.save() }
    private func restore(group g: StuntGroup) { g.deletedAt = nil; try? context.save() }

    /// The only hard delete that touches reps — explicit, from the Trash.
    private func purge(team t: Team) { context.delete(t); try? context.save() }
    private func purge(group g: StuntGroup) { context.delete(g); try? context.save() }

    private func summaryRow(_ label: String, _ count: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: Deletes

    /// Fetch-and-loop (not `context.delete(model:)`) so every `@Query` in the
    /// app — these counts, the editor roster, Home's dashboard — refreshes
    /// predictably and cascade rules fire. Datasets are tiny (a personal
    /// tracker), so the loop cost is irrelevant.
    private func all<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    /// Scoped version of `clearHistory()` — only this folder's reps (and any
    /// custom-outcome tallies tied to its skills) are deleted. A touched
    /// session is only removed once nothing from any folder remains in it, so
    /// a session that also holds another folder's reps survives.
    private func clearFolderHistory() {
        guard let team else { return }
        let scoped = folderAttempts
        let touchedSessionIDs = Set(scoped.compactMap { $0.session?.cloudID }.filter { !$0.isEmpty })
        for a in scoped {
            SyncEngine.shared.queueDeletion(of: a, in: context)
            context.delete(a)
        }
        for t in customTallies where t.group?.team?.id == team.id {
            context.delete(t)
        }
        for s in sessions where touchedSessionIDs.contains(s.cloudID)
            && s.attempts.isEmpty && s.customTallies.isEmpty {
            context.delete(s)
        }
        try? context.save()
    }

    /// Keep the roster, wipe the record of practice. Deleting the sessions
    /// cascades their attempts; the explicit attempt sweep then catches any
    /// group-linked or orphaned reps left behind.
    private func clearHistory() {
        for a in all(Attempt.self) {
            SyncEngine.shared.queueDeletion(of: a, in: context)
            context.delete(a)
        }
        for s in all(PracticeSession.self) { context.delete(s) }
        try? context.save()
    }

    /// Clean slate — skills/groups, reps, and sessions. Identity and custom
    /// outcome labels live in UserDefaults and are intentionally preserved
    /// (settings, not practice data).
    private func eraseAll() {
        // Queue remote tombstones while every attempt can still resolve its
        // folder. Deleting teams/groups first can sever those relationships.
        for a in all(Attempt.self) {
            SyncEngine.shared.queueDeletion(of: a, in: context)
            context.delete(a)
        }
        for s in all(PracticeSession.self) { context.delete(s) }
        for g in all(StuntGroup.self) { context.delete(g) }
        for t in all(Team.self) { context.delete(t) }
        try? context.save()
        didOnboard = false
    }
}
