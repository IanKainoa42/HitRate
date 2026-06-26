import SwiftUI
import SwiftData

/// The app's launch root: every folder (`Team`) the user keeps, each with its
/// own roster and stats. Tap one to drop into its dashboard. Lives in the
/// training-floor register to match Home. Designed so a future cross-folder
/// "skill lives in many folders + umbrella stats" rollup can sit above these
/// rows without reworking the screen.
struct FolderListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Team.orderIndex) private var teams: [Team]
    @Query(sort: \StuntGroup.orderIndex) private var allGroups: [StuntGroup]

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("athleteName") private var athleteName = ""
    @AppStorage("orgName") private var orgName = ""
    @AppStorage("currentTeamID") private var currentTeamID = ""

    /// Open a folder's dashboard. The parent (RootView) wires this to set the
    /// active team and push Home.
    let onOpen: (Team) -> Void

    @State private var addOpen = false
    @State private var newName = ""
    @State private var renaming: Team?
    @State private var renameText = ""

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    private var identityLabel: String {
        mode == .athlete
            ? (athleteName.isEmpty ? "Me" : athleteName)
            : (orgName.isEmpty ? "My program" : orgName)
    }

    private func skills(in t: Team) -> [StuntGroup] { allGroups.inTeam(t) }
    private func reps(in t: Team) -> Int { skills(in: t).reduce(0) { $0 + $1.attempts.count } }

    var body: some View {
        VStack(spacing: 9) {
            header

            ScrollView {
                VStack(spacing: 9) {
                    ForEach(teams.active) { t in
                        folderRow(t)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom) { newFolderCTA }
        }
        .background(FloorBackdrop().ignoresSafeArea())
        .alert("New folder", isPresented: $addOpen) {
            TextField("Folder name", text: $newName)
            Button("Create") { addFolder() }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("Each folder keeps its own skills and stats — a team, an athlete, a private lesson, whatever you track separately.")
        }
        .alert("Rename folder", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } })) {
            TextField("Folder name", text: $renameText)
            Button("Save") {
                let t = renameText.trimmingCharacters(in: .whitespaces)
                if let f = renaming, !t.isEmpty { f.name = t; try? context.save() }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    /// Move a folder (and its skills + reps) to the Trash — kept and restorable
    /// from Data Management. Always keep at least one active folder.
    private func trashFolder(_ t: Team) {
        guard teams.active.count > 1 else { return }
        let wasCurrent = t.id.uuidString == currentTeamID
        t.deletedAt = .now
        try? context.save()
        if wasCurrent, let first = teams.active.first { currentTeamID = first.id.uuidString }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                IconWordmark(size: 17, rateFill: Theme.well, dotSize: 8)
                Text(identityLabel.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.label2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(teams.active.count) FOLDER\(teams.active.count == 1 ? "" : "S")")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.label3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .wellBackground()
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: Folder row

    private func folderRow(_ t: Team) -> some View {
        let count = skills(in: t).count
        let active = t.id.uuidString == currentTeamID
        return Button {
            onOpen(t)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(active ? Theme.accent : Theme.label2)
                    .frame(width: 38, height: 38)
                    .background(Theme.iconTile)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Theme.iconTileEdge.opacity(0.85), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(t.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    Text("\(count) skill\(count == 1 ? "" : "s") · \(reps(in: t)) rep\(reps(in: t) == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.label2)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.label3)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .wellBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = t.name
                renaming = t
            } label: { Label("Rename", systemImage: "pencil") }
            if teams.active.count > 1 {
                Button(role: .destructive) {
                    withAnimation { trashFolder(t) }
                } label: { Label("Move to Trash", systemImage: "trash") }
            }
        }
    }

    // MARK: New folder

    private var newFolderCTA: some View {
        Button {
            addOpen = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .heavy))
                Text("NEW FOLDER")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1.5)
            }
            .foregroundStyle(Theme.accentText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(0.24), radius: 8, y: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(
            LinearGradient(colors: [Theme.appBGBottom.opacity(0), Theme.appBGBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func addFolder() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let t = Team(name: name.isEmpty ? "Folder \(teams.active.count + 1)" : name,
                     orderIndex: teams.count)
        context.insert(t)
        try? context.save()
        currentTeamID = t.id.uuidString
        newName = ""
        onOpen(t)   // drop straight into the new (empty) folder to add skills
    }
}
