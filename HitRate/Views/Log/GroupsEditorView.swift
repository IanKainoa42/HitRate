import SwiftUI
import SwiftData
import CheerRulesKit

/// A rename field that types into a LOCAL buffer and only commits the result
/// on blur / return / dismiss — never per keystroke. The old direct binding
/// wrote through `OutcomeNames` (app-wide @Observable) or a SwiftData @Model
/// on every character, so each keystroke re-rendered the editor (and, after
/// the inset-well restyle, re-composited every shadow) mid-edit — the cursor
/// fought the keyboard. Committing on commit keeps the e2-1/e2-2 invariant
/// (labels re-render app-wide once the rename lands, just not per keystroke).
private struct RenameField: View {
    let prompt: String
    let value: String
    let commit: (String) -> Void

    @State private var draft = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(prompt, text: $draft)
                .focused($focused)
                .submitLabel(.done)
                .onAppear {
                    guard !loaded else { return }
                    draft = value
                    loaded = true
                }
                .onChange(of: focused) { _, nowFocused in
                    if !nowFocused { commit(draft) }   // tapped away
                }
                .onSubmit { commit(draft) }
                .onDisappear { commit(draft) }         // sheet dismissed via Done
            // Pencil signals the word is editable (the plain field read as a
            // fixed label before). Hidden while editing.
            if !focused {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.label3)
            }
        }
        // Tapping anywhere on the row — pencil or padding — starts editing.
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

/// Manage the roster of skills/groups, identity, outcome names, and mode.
struct GroupsEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StuntGroup.orderIndex) private var allGroups: [StuntGroup]
    @Query(sort: \Team.orderIndex) private var teams: [Team]

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("athleteName") private var athleteName = ""
    @AppStorage("orgName") private var orgName = ""
    @AppStorage("currentTeamID") private var currentTeamID = ""
    @AppStorage(Sounds.defaultsKey) private var soundsOn = true

    // Outcome rename slots (blank = standard name) — observable store so the
    // rest of the app re-renders on rename.
    @State private var outcomeNames = OutcomeNames.shared

    // Swipe-deleted group/team awaiting confirmation (only when it has reps).
    @State private var pendingDelete: StuntGroup?
    @State private var pendingTeamDelete: Team?

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    /// The active team and its roster — the editor edits this team.
    private var currentTeam: Team? { teams.current(id: currentTeamID) }
    private var groups: [StuntGroup] { allGroups.inTeam(currentTeam) }

    /// The active folder's user-created outcomes, in display order.
    private var customOutcomes: [CustomOutcome] {
        (currentTeam?.customOutcomes ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    // Bucket wording for the active folder (its `itemNoun` override, else the
    // AppMode default). Views read these, never `mode.noun` directly.
    private var noun: String { currentTeam.noun(for: mode) }
    private var nounTitle: String { currentTeam.nounTitle(for: mode) }
    private var nounPlural: String { currentTeam.nounPlural(for: mode) }
    private var nounPluralTitle: String { currentTeam.nounPluralTitle(for: mode) }

    var body: some View {
        NavigationStack {
            List {
                if mode == .athlete {
                    Section("You") {
                        TextField("Your name", text: $athleteName)
                    }
                    .listRowBackground(glassRow)
                } else {
                    Section("Program") {
                        TextField("Program", text: $orgName)
                    }
                    .listRowBackground(glassRow)
                }

                teamsSection

                Section("\(nounPluralTitle) · \(currentTeam?.name ?? "")") {
                    ForEach(groups) { g in
                        HStack(spacing: 10) {
                            Text("\(g.number)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(g.color)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            RenameField(prompt: "Name", value: g.name) { new in
                                g.name = new
                                try? context.save()
                            }
                            // United category — carries the execution drivers
                            // and (via category→kind) the outcome wording.
                            Menu {
                                ForEach(SkillCategory.allCases, id: \.self) { c in
                                    Button {
                                        g.category = c
                                        try? context.save()
                                    } label: {
                                        Label(c.displayName, systemImage: c.icon)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: g.category.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(g.category.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Theme.fill)
                                .clipShape(Capsule())
                            }
                        }
                        // Custom swipe action, deliberately NOT role: .destructive:
                        // a destructive swipe makes iOS animate the row away
                        // immediately, but a repped skill isn't deleted yet (it
                        // goes through the confirm alert) — the row snapped back
                        // and the delete felt like it needed two presses. The
                        // plain red button skips the eager removal animation;
                        // the row only leaves when the model actually deletes.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete") { requestDelete(g) }.tint(.red)
                        }
                    }
                    .onDelete { idx in   // edit-mode minus button path
                        guard let i = idx.first else { return }
                        requestDelete(groups[i])
                    }
                    .onMove { from, to in
                        var arr = groups
                        arr.move(fromOffsets: from, toOffset: to)
                        for (i, g) in arr.enumerated() { g.orderIndex = i }
                        try? context.save()
                    }

                    Button {
                        let next = (groups.map(\.number).max() ?? 0) + 1
                        let g = StuntGroup(name: "\(nounTitle) \(next)",
                                           number: next, orderIndex: groups.count)
                        g.team = currentTeam
                        context.insert(g)
                        try? context.save()
                    } label: {
                        Label("Add \(noun)", systemImage: "plus")
                    }
                }
                .listRowBackground(glassRow)

                Section {
                    ForEach(Outcome.allCases) { o in
                        HStack(spacing: 10) {
                            Circle().fill(o.color).frame(width: 12, height: 12)
                            RenameField(prompt: o.defaultLabel(.stunt),
                                        value: outcomeNames.stunt[o.rawValue]) { new in
                                outcomeNames.stunt[o.rawValue] = new
                            }
                        }
                    }
                } header: {
                    Text(mode == .athlete ? "Stunt outcomes" : "Outcomes")
                } footer: {
                    if mode == .coach {
                        Text("Rename outcomes to match how your gym calls them. Leave blank for the standard name. Severity order and colors stay fixed.")
                    }
                }
                .listRowBackground(glassRow)

                if mode == .athlete {
                    Section {
                        ForEach(Outcome.allCases) { o in
                            HStack(spacing: 10) {
                                Circle().fill(o.color).frame(width: 12, height: 12)
                                RenameField(prompt: o.defaultLabel(.tumbling),
                                            value: outcomeNames.tumbling[o.rawValue]) { new in
                                    outcomeNames.tumbling[o.rawValue] = new
                                }
                            }
                        }
                    } header: {
                        Text("Tumbling outcomes")
                    } footer: {
                        Text("Rename outcomes to match how your gym calls them. Leave blank for the standard name. Severity order and colors stay fixed across both.")
                    }
                    .listRowBackground(glassRow)
                }

                customOutcomesSection

                Section {
                    Toggle("Tap sounds", isOn: $soundsOn)
                } footer: {
                    Text("Pops on the counter pad. Like keyboard clicks, they follow the ring/silent switch.")
                }
                .listRowBackground(glassRow)

                Section {
                    Picker("Mode", selection: $appModeRaw) {
                        Text("Just me").tag(AppMode.athlete.rawValue)
                        Text("Coach").tag(AppMode.coach.rawValue)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Mode")
                } footer: {
                    Text("Coach mode tracks multiple stunt groups and puts your program on the share cards. Your logged reps carry over either way.")
                }
                .listRowBackground(glassRow)

                Section {
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        Label("Manage data", systemImage: "externaldrive")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export a backup, clear history, or erase everything.")
                }
                .listRowBackground(glassRow)

                Section {
                } footer: {
                    Text("HitRate \(appVersion)")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FloorBackdrop().ignoresSafeArea())
            .navigationTitle(mode == .athlete ? "My Skills" : "Groups")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Delete \(pendingDelete?.name ?? "")?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { g in
                Button("Move to Trash", role: .destructive) {
                    withAnimation { softDelete(g) }
                    renumber()
                }
                Button("Cancel", role: .cancel) {}
            } message: { g in
                Text("This \(noun) and its \(g.attempts.count) logged reps move to the Trash. Restore them anytime from Data Management.")
            }
            .alert(
                "Delete \(pendingTeamDelete?.name ?? "")?",
                isPresented: Binding(
                    get: { pendingTeamDelete != nil },
                    set: { if !$0 { pendingTeamDelete = nil } }),
                presenting: pendingTeamDelete
            ) { t in
                Button("Move to Trash", role: .destructive) { withAnimation { removeTeam(t) } }
                Button("Cancel", role: .cancel) {}
            } message: { t in
                Text("This folder, its \(groupCount(t)) \(t.nounPlural(for: mode)), and all their reps move to the Trash. Restore anytime from Data Management.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        try? context.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    /// Well row surface — solid so separators/swipe actions stay readable.
    private var glassRow: Color { Theme.well }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func renumber() {
        for (i, g) in groups.enumerated() { g.orderIndex = i }
        try? context.save()
    }

    /// Shared by the swipe action and the edit-mode minus: empty skills delete
    /// on the spot; repped skills confirm the cascade first.
    private func requestDelete(_ g: StuntGroup) {
        if g.attempts.isEmpty {
            withAnimation {
                softDelete(g)
                renumber()
            }
        } else {
            pendingDelete = g   // has reps — confirm before trashing
        }
    }

    /// Soft-delete: the skill + its reps move to the Trash, kept and restorable.
    private func softDelete(_ g: StuntGroup) {
        g.deletedAt = .now
        try? context.save()
    }

    // MARK: Custom outcomes (per folder)

    @ViewBuilder
    private var customOutcomesSection: some View {
        Section {
            ForEach(customOutcomes) { o in
                HStack(spacing: 10) {
                    // Single-pick color menu (closes after one — fine for a
                    // one-shot choice; the hated close-after-each was multi-select).
                    Menu {
                        ForEach(0..<Theme.groupRainbow.count, id: \.self) { i in
                            Button {
                                o.colorIndex = i
                                try? context.save()
                            } label: {
                                Label("Color \(i + 1)",
                                      systemImage: o.colorIndex == i ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    } label: {
                        Circle().fill(o.color).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                    }
                    RenameField(prompt: "Name", value: o.name) { new in
                        let t = new.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        o.name = t
                        try? context.save()
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete") { deleteCustomOutcome(o) }.tint(.red)
                }
            }
            .onDelete { idx in if let i = idx.first { deleteCustomOutcome(customOutcomes[i]) } }
            .onMove { from, to in
                var arr = customOutcomes
                arr.move(fromOffsets: from, toOffset: to)
                for (i, o) in arr.enumerated() { o.orderIndex = i }
                try? context.save()
            }

            Button {
                addCustomOutcome()
            } label: {
                Label("Add issue", systemImage: "plus")
            }
        } header: {
            Text("Issues · \(currentTeam?.name ?? "")")
        } footer: {
            Text("Issues this folder tracks — anything that comes up that you want to count (e.g. timing off, wrong count, dropped). They appear as their own tap buttons in practice and tally separately, so they never change your hit-rate.")
        }
        .listRowBackground(glassRow)
    }

    private func addCustomOutcome() {
        let outs = customOutcomes
        let next = (outs.map(\.orderIndex).max() ?? -1) + 1
        let co = CustomOutcome(name: "Issue \(outs.count + 1)",
                               colorIndex: outs.count % Theme.groupRainbow.count,
                               orderIndex: next)
        co.team = currentTeam
        context.insert(co)
        try? context.save()
    }

    private func deleteCustomOutcome(_ o: CustomOutcome) {
        withAnimation {
            context.delete(o)   // cascades its tallies
            for (i, x) in customOutcomes.enumerated() { x.orderIndex = i }
            try? context.save()
        }
    }

    // MARK: Teams

    @ViewBuilder
    private var teamsSection: some View {
        Section {
            ForEach(teams.active) { t in
                HStack(spacing: 10) {
                    Button {
                        currentTeamID = t.id.uuidString
                    } label: {
                        Image(systemName: t.id == currentTeam?.id ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(t.id == currentTeam?.id ? Theme.accent : Theme.label3)
                    }
                    .buttonStyle(.plain)
                    RenameField(prompt: "Folder name", value: t.name) { new in
                        let trimmed = new.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        t.name = trimmed
                        try? context.save()
                    }
                    Spacer(minLength: 6)
                    Text("\(groupCount(t))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                // Same no-snap-back treatment as the skills rows — see there.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if teams.active.count > 1 {
                        Button("Delete") { requestTeamDelete(t) }.tint(.red)
                    }
                }
                // The only folder can't be deleted (reps need a home). Disable
                // the edit-mode minus too, or it animates the row away and then
                // pops back when the guard blocks the delete.
                .deleteDisabled(teams.active.count <= 1)
            }
            .onDelete { idx in   // edit-mode minus button path
                guard let i = idx.first else { return }
                requestTeamDelete(teams.active[i])
            }
            .onMove(perform: moveTeams)

            Button {
                addTeam()
            } label: {
                Label("Add folder", systemImage: "plus")
            }
        } header: {
            Text("Folders")
        } footer: {
            Text("Each folder keeps its own roster and stats — call it a team, an athlete, a private lesson, whatever you track separately. Switch the active folder with the circle here or from the Home header.")
        }
        .listRowBackground(glassRow)
    }

    private func groupCount(_ t: Team) -> Int {
        allGroups.filter { $0.team?.id == t.id && $0.deletedAt == nil }.count
    }

    private func addTeam() {
        let t = Team(name: "Folder \(teams.active.count + 1)", orderIndex: teams.count)
        context.insert(t)
        try? context.save()
        currentTeamID = t.id.uuidString
    }

    private func requestTeamDelete(_ t: Team) {
        // Always keep at least one active folder — reps need a live home.
        guard teams.active.count > 1 else { return }
        if allGroups.contains(where: { $0.team?.id == t.id && $0.deletedAt == nil && !$0.attempts.isEmpty }) {
            pendingTeamDelete = t   // has logged reps — confirm before trashing
        } else {
            withAnimation { removeTeam(t) }
        }
    }

    /// Soft-delete: the folder (and its skills + reps) move to the Trash, kept
    /// and restorable. Nothing is hard-deleted here.
    private func removeTeam(_ t: Team) {
        let wasCurrent = t.id == currentTeam?.id
        t.deletedAt = .now
        let remaining = teams.active.filter { $0.id != t.id }.sorted { $0.orderIndex < $1.orderIndex }
        for (i, team) in remaining.enumerated() { team.orderIndex = i }
        try? context.save()
        if wasCurrent, let first = remaining.first {
            currentTeamID = first.id.uuidString
        }
    }

    private func moveTeams(_ from: IndexSet, _ to: Int) {
        var arr = teams
        arr.move(fromOffsets: from, toOffset: to)
        for (i, t) in arr.enumerated() { t.orderIndex = i }
        try? context.save()
    }
}
