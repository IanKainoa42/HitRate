import SwiftUI
import SwiftData

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
    @Environment(\.modelContext) private var context
    @Query(sort: \StuntGroup.orderIndex) private var groups: [StuntGroup]
    @Query private var sessions: [PracticeSession]
    @Query private var attempts: [Attempt]

    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    private enum Confirm { case clearHistory, eraseAll }
    @State private var confirm: Confirm?

    private var glassRow: Color { Theme.well }
    private var hasReps: Bool { !attempts.isEmpty }
    private var hasAnything: Bool { !groups.isEmpty || !attempts.isEmpty || !sessions.isEmpty }

    var body: some View {
        List {
            Section {
                summaryRow(mode.nounPluralTitle, groups.count)
                summaryRow("Reps", attempts.count)
                summaryRow("Sessions", sessions.count)
            } header: {
                Text("Stored on this device")
            }
            .listRowBackground(glassRow)

            Section {
                let csv = CSVExportItem(sessions: sessions)
                if csv.hasData {
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
                Button(role: .destructive) {
                    confirm = .clearHistory
                } label: {
                    Label("Clear practice history", systemImage: "clock.arrow.circlepath")
                }
                .disabled(!hasReps)
            } footer: {
                Text("Deletes every logged rep and session but keeps your \(mode.nounPlural). Stats reset to zero.")
            }
            .listRowBackground(glassRow)

            Section {
                Button(role: .destructive) {
                    confirm = .eraseAll
                } label: {
                    Label("Erase all data", systemImage: "trash")
                }
                .disabled(!hasAnything)
            } header: {
                Text("Danger zone")
            } footer: {
                Text("Deletes your \(mode.nounPlural), reps, and sessions — a clean slate. Your name and custom outcome labels stay.")
            }
            .listRowBackground(glassRow)
        }
        .scrollContentBackground(.hidden)
        .background(FloorBackdrop().ignoresSafeArea())
        .navigationTitle("Manage Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Clear practice history?",
            isPresented: Binding(
                get: { confirm == .clearHistory },
                set: { if !$0 { confirm = nil } })
        ) {
            Button("Clear history", role: .destructive) { clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All \(attempts.count) reps and \(sessions.count) sessions will be deleted. Your \(mode.nounPlural) stay. This can't be undone.")
        }
        .alert(
            "Erase all data?",
            isPresented: Binding(
                get: { confirm == .eraseAll },
                set: { if !$0 { confirm = nil } })
        ) {
            Button("Erase everything", role: .destructive) { eraseAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your \(groups.count) \(mode.nounPlural), \(attempts.count) reps, and \(sessions.count) sessions will be permanently deleted.")
        }
    }

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

    /// Keep the roster, wipe the record of practice. Deleting the sessions
    /// cascades their attempts; the explicit attempt sweep then catches any
    /// group-linked or orphaned reps left behind.
    private func clearHistory() {
        for s in all(PracticeSession.self) { context.delete(s) }
        for a in all(Attempt.self) { context.delete(a) }
        try? context.save()
    }

    /// Clean slate — skills/groups, reps, and sessions. Identity and custom
    /// outcome labels live in UserDefaults and are intentionally preserved
    /// (settings, not practice data).
    private func eraseAll() {
        for t in all(Team.self) { context.delete(t) }
        for g in all(StuntGroup.self) { context.delete(g) }
        for s in all(PracticeSession.self) { context.delete(s) }
        for a in all(Attempt.self) { context.delete(a) }
        try? context.save()
        didOnboard = false
    }
}
