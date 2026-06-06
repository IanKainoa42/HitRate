import SwiftUI
import SwiftData

/// Manage the roster of skills/groups, identity, outcome names, and mode.
struct GroupsEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StuntGroup.orderIndex) private var groups: [StuntGroup]

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("athleteName") private var athleteName = ""
    @AppStorage("orgName") private var orgName = ""
    @AppStorage("teamName") private var teamName = ""
    @AppStorage(Sounds.defaultsKey) private var soundsOn = true

    // Outcome rename slots (blank = standard name) — observable store so the
    // rest of the app re-renders on rename.
    @State private var outcomeNames = OutcomeNames.shared

    // Swipe-deleted group awaiting confirmation (only when it has logged reps).
    @State private var pendingDelete: StuntGroup?

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    var body: some View {
        NavigationStack {
            List {
                if mode == .athlete {
                    Section("You") {
                        TextField("Your name", text: $athleteName)
                    }
                    .listRowBackground(glassRow)
                } else {
                    Section("Team") {
                        TextField("Program", text: $orgName)
                        TextField("Team", text: $teamName)
                    }
                    .listRowBackground(glassRow)
                }

                Section(mode.nounPluralTitle) {
                    ForEach(groups) { g in
                        HStack(spacing: 10) {
                            Text("\(g.number)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(g.color)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            TextField("Name", text: Binding(
                                get: { g.name },
                                set: { g.name = $0 }))
                            if mode == .athlete {
                                // Stunt vs tumbling — picks the outcome wording
                                // on the pad for this skill.
                                Menu {
                                    ForEach(SkillKind.allCases) { k in
                                        Button {
                                            g.kind = k
                                            try? context.save()
                                        } label: {
                                            Label(k.label, systemImage: k.icon)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: g.kind.icon)
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(g.kind.label)
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Theme.fill)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .onDelete { idx in
                        guard let i = idx.first else { return }
                        let g = groups[i]
                        if g.attempts.isEmpty {
                            context.delete(g)
                            renumber()
                        } else {
                            // Deleting cascades its logged reps — confirm first.
                            pendingDelete = g
                        }
                    }
                    .onMove { from, to in
                        var arr = groups
                        arr.move(fromOffsets: from, toOffset: to)
                        for (i, g) in arr.enumerated() { g.orderIndex = i }
                        try? context.save()
                    }

                    Button {
                        let next = (groups.map(\.number).max() ?? 0) + 1
                        context.insert(StuntGroup(name: "\(mode.nounTitle) \(next)",
                                                  number: next, orderIndex: groups.count))
                        try? context.save()
                    } label: {
                        Label("Add \(mode.noun)", systemImage: "plus")
                    }
                }
                .listRowBackground(glassRow)

                Section {
                    ForEach(Outcome.allCases) { o in
                        HStack(spacing: 10) {
                            Circle().fill(o.color).frame(width: 12, height: 12)
                            TextField(o.defaultLabel(.stunt), text: Binding(
                                get: { outcomeNames.stunt[o.rawValue] },
                                set: { outcomeNames.stunt[o.rawValue] = $0 }))
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
                                TextField(o.defaultLabel(.tumbling), text: Binding(
                                    get: { outcomeNames.tumbling[o.rawValue] },
                                    set: { outcomeNames.tumbling[o.rawValue] = $0 }))
                            }
                        }
                    } header: {
                        Text("Tumbling outcomes")
                    } footer: {
                        Text("Rename outcomes to match how your gym calls them. Leave blank for the standard name. Severity order and colors stay fixed across both.")
                    }
                    .listRowBackground(glassRow)
                }

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
                } footer: {
                    Text("HitRate \(appVersion)")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.appBG)
            .navigationTitle(mode == .athlete ? "My Skills" : "Groups")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Delete \(pendingDelete?.name ?? "")?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { g in
                Button("Delete \(mode.noun) & reps", role: .destructive) {
                    context.delete(g)
                    renumber()
                }
                Button("Cancel", role: .cancel) {}
            } message: { g in
                Text("Its \(g.attempts.count) logged reps will be deleted too. This can't be undone.")
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

    /// Glass row surface — solid-ish so separators/swipe actions stay readable.
    private var glassRow: Color { Color(hex: 0x161D30) }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func renumber() {
        for (i, g) in groups.enumerated() { g.orderIndex = i }
        try? context.save()
    }
}
