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

    // Outcome rename slots (blank = standard name) — observable store so the
    // rest of the app re-renders on rename.
    @State private var outcomeNames = OutcomeNames.shared

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    var body: some View {
        NavigationStack {
            List {
                if mode == .athlete {
                    Section("You") {
                        TextField("Your name", text: $athleteName)
                    }
                } else {
                    Section("Team") {
                        TextField("Program", text: $orgName)
                        TextField("Team", text: $teamName)
                    }
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
                        }
                    }
                    .onDelete { idx in
                        for i in idx { context.delete(groups[i]) }
                        renumber()
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

                Section {
                    ForEach(Outcome.allCases) { o in
                        HStack(spacing: 10) {
                            Circle().fill(o.color).frame(width: 12, height: 12)
                            TextField(o.defaultLabel, text: Binding(
                                get: { outcomeNames.custom[o.rawValue] },
                                set: { outcomeNames.custom[o.rawValue] = $0 }))
                        }
                    }
                } header: {
                    Text("Outcomes")
                } footer: {
                    Text("Rename outcomes to match how your gym calls them. Leave blank for the standard name. Severity order and colors stay fixed.")
                }

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
            }
            .navigationTitle(mode == .athlete ? "My Skills" : "Groups")
            .navigationBarTitleDisplayMode(.inline)
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

    private func renumber() {
        for (i, g) in groups.enumerated() { g.orderIndex = i }
        try? context.save()
    }
}
