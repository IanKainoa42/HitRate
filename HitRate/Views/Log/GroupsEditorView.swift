import SwiftUI
import SwiftData

/// Manage the roster of stunt groups + team identity.
struct GroupsEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StuntGroup.orderIndex) private var groups: [StuntGroup]

    @AppStorage("orgName") private var orgName = "Cheer Force San Diego"
    @AppStorage("teamName") private var teamName = "Senior Coed"

    var body: some View {
        NavigationStack {
            List {
                Section("Team") {
                    TextField("Program", text: $orgName)
                    TextField("Team", text: $teamName)
                }
                Section("Groups") {
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
                        context.insert(StuntGroup(name: "Group \(next)", number: next, orderIndex: groups.count))
                        try? context.save()
                    } label: {
                        Label("Add group", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Groups")
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
