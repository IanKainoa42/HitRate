import SwiftUI
import SwiftData
import os

/// The app's launch root: every folder (`Team`) the user keeps, each with its
/// own roster and stats. Tap one to drop into its dashboard. Lives in the
/// training-floor register to match Home. Designed so a future cross-folder
/// "skill lives in many folders + umbrella stats" rollup can sit above these
/// rows without reworking the screen.
struct FolderListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Team.orderIndex) private var teams: [Team]
    @Query(sort: \StuntGroup.orderIndex) private var allGroups: [StuntGroup]
    @Query private var allAttempts: [Attempt]

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("athleteName") private var athleteName = ""
    @AppStorage("orgName") private var orgName = ""
    @AppStorage("currentTeamID") private var currentTeamID = ""

    @EnvironmentObject private var auth: AuthViewModel

    /// Open a folder's dashboard. The parent (RootView) wires this to set the
    /// active team and push Home.
    let onOpen: (Team) -> Void

    @State private var addOpen = false
    @State private var newName = ""
    @State private var renaming: Team?
    @State private var renameText = ""
    @State private var sharing: Team?
    @State private var joinOpen = false
    @State private var pendingTrash: Team?
    @State private var accountOpen = false

    private var saveAccountChip: some View {
        Button {
            accountOpen = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                Text("Reps live on this phone only")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                Spacer(minLength: 4)
                Text("SAVE")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.label3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .wellBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    /// You own a folder if it's never been claimed (local-only) or its cloud
    /// owner is you. A folder you JOINED carries someone else's ownerUID.
    private func isOwner(_ t: Team) -> Bool {
        t.ownerUID == nil || t.ownerUID == auth.uid
    }
    private func isShared(_ t: Team) -> Bool {
        !(t.joinCode ?? "").isEmpty || !t.memberIds.isEmpty || !isOwner(t)
    }

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    private var identityLabel: String {
        mode == .athlete
            ? (athleteName.isEmpty ? "Me" : athleteName)
            : (orgName.isEmpty ? "My program" : orgName)
    }

    private var folderSummaries: [String: FolderSummaryIndex.Summary] {
        FolderSummaryIndex.build(
            groups: allGroups.compactMap { group in
                guard let teamID = group.team?.id.uuidString else { return nil }
                return .init(teamID: teamID, isDeleted: group.deletedAt != nil)
            },
            attempts: allAttempts.compactMap { attempt in
                guard let group = attempt.group,
                      let teamID = group.team?.id.uuidString else { return nil }
                return .init(teamID: teamID, isDeleted: group.deletedAt != nil)
            }
        )
    }

    var body: some View {
        let summaries = folderSummaries
        VStack(spacing: 9) {
            header

            // The one always-on reminder that reps are device-bound. Quiet by
            // design — it states the fact and offers the fix in one tap, and it
            // disappears for good the moment the account is saved. Hidden until
            // there's a folder to lose, so a first launch isn't nagged.
            if AccountPromptPolicy.showsFolderListChip(isUpgraded: auth.isUpgraded,
                                                       folderCount: teams.active.count) {
                saveAccountChip
            }

            ScrollView {
                VStack(spacing: 9) {
                    ForEach(teams.active) { t in
                        folderRow(t, summary: summaries[t.id.uuidString] ?? .init())
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
        .sheet(item: $sharing) { t in
            ShareFolderSheet(team: t)
                // Large, not medium — the QR needs room to be scannable at
                // arm's length across a gym floor.
                .presentationDetents([.large])
                .presentationBackground(Theme.appBGBottom)
        }
        .sheet(isPresented: $joinOpen) {
            JoinFolderSheet()
                .presentationDetents([.height(300)])
                .presentationBackground(Theme.appBGBottom)
        }
        .sheet(isPresented: $accountOpen) {
            NavigationStack { AccountView() }
        }
        .alert(
            "Move “\(pendingTrash?.name ?? "")” to Trash?",
            isPresented: Binding(
                get: { pendingTrash != nil },
                set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { t in
            Button("Move to Trash", role: .destructive) {
                withAnimation { trashFolder(t) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { t in
            let s = folderSummaries[t.id.uuidString] ?? .init()
            Text("This folder, its \(s.skillCount) skill\(s.skillCount == 1 ? "" : "s"), and \(s.repCount) rep\(s.repCount == 1 ? "" : "s") move to the Trash. Restore anytime from Data Management.")
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

    private func folderRow(_ t: Team, summary: FolderSummaryIndex.Summary) -> some View {
        let count = summary.skillCount
        let reps = summary.repCount
        let active = t.id.uuidString == currentTeamID
        // Row = a big "open" button + separate trailing controls (a share icon
        // for folders you own, a JOINED chip for ones you joined). Kept as
        // sibling buttons, NOT nested — a Button inside a Button's label doesn't
        // route taps. The open button still fills the row for a fat tap target.
        return HStack(spacing: 8) {
            Button {
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
                        Text("\(count) skill\(count == 1 ? "" : "s") · \(reps) rep\(reps == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.label2)
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOwner(t) {
                // Visible Share affordance. Green once a code exists (= shared),
                // muted before. Tapping opens the code sheet directly.
                Button {
                    sharing = t
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isShared(t) ? Theme.accent : Theme.label2)
                        .frame(width: 34, height: 34)
                        .background(Theme.iconTile)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder((isShared(t) ? Theme.accent : Theme.iconTileEdge)
                                .opacity(isShared(t) ? 0.55 : 0.85), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isShared(t) ? "Sharing code for \(t.name)" : "Share \(t.name)")
            } else if isShared(t) {
                sharedBadge(owner: false)   // a folder you joined — not yours to share
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.label3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .wellBackground()
        .contextMenu {
            Button {
                renameText = t.name
                renaming = t
            } label: { Label("Rename", systemImage: "pencil") }
            if isOwner(t) {
                Button {
                    sharing = t
                } label: { Label(isShared(t) ? "Sharing code" : "Share folder",
                                 systemImage: "person.2.fill") }
            }
            if teams.active.count > 1 {
                Button(role: .destructive) {
                    pendingTrash = t
                } label: { Label("Move to Trash", systemImage: "trash") }
            }
        }
    }

    /// Small chalk chip marking a folder as shared — "SHARED" if you own it,
    /// "JOINED" if you're logging into someone else's.
    private func sharedBadge(owner: Bool) -> some View {
        Text(owner ? "SHARED" : "JOINED")
            .font(.system(size: 8.5, weight: .heavy))
            .tracking(1.1)
            .foregroundStyle(owner ? Theme.accent : Theme.label2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Theme.iconTile)
                    .overlay(Capsule().strokeBorder(
                        (owner ? Theme.accent : Theme.label3).opacity(0.4), lineWidth: 1)))
    }

    // MARK: New folder

    private var newFolderCTA: some View {
        VStack(spacing: 10) {
            Button {
                joinOpen = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Join a folder with a code")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.well)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.iconTileEdge.opacity(0.9), lineWidth: 1)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            newFolderButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(
            LinearGradient(colors: [Theme.appBGBottom.opacity(0), Theme.appBGBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var newFolderButton: some View {
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

// MARK: - Share folder sheet

/// Owner-side: mints (or reuses) the folder's join code and presents it to hand
/// to another coach. The code is generated on appear via SyncEngine, which also
/// publishes the public `joinCodes/{code}` directory entry.
private struct ShareFolderSheet: View {
    let team: Team
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var failedMessage: String?
    @State private var copied = false
    @State private var attempt = 0
    @State private var accountOpen = false
    private let sync = SyncEngine.shared

    var body: some View {
        VStack(spacing: 18) {
            Text("SHARE FOLDER")
                .font(.system(size: 11, weight: .heavy)).tracking(2)
                .foregroundStyle(Theme.label3)
                .padding(.top, 22)

            Text(team.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.label)

            if let code {
                // Hand the folder over on the floor: the other phone's camera
                // scans this and deep-links straight into the join flow, no
                // squinting at six characters across a gym.
                VStack(spacing: 12) {
                    QRCodeView(string: DeepLink.join(code: code).absoluteString)

                    Text("SCAN WITH CAMERA OR ENTER CODE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.label3)

                    Text(code)
                        .font(Theme.barlow(40, .extrabold))
                        .tracking(6)
                        .foregroundStyle(Theme.accent)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .wellBackground()

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = code
                        withAnimation { copied = true }
                    } label: {
                        Label(copied ? "Copied" : "Copy code",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.label)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .wellBackground()
                    }
                    .buttonStyle(.plain)

                    // The link is tappable on the receiving phone (it opens
                    // straight into the join sheet); the code is spelled out for
                    // anyone reading it off a screenshot.
                    ShareLink(item: "Join my HitRate folder “\(team.name)” with code \(code): \(DeepLink.join(code: code).absoluteString)") {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.label)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .wellBackground()
                    }
                }

                Text("Anyone with this code can open “\(team.name)” and log reps into it. You stay the owner — only you can edit the roster.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Sharing is the moment ownership starts to matter, so it's the
                // moment to fix it — not to print directions to a settings
                // screen. If it needs a nav path spelled out, the button is in
                // the wrong place; so this IS the button.
                if !auth.isUpgraded {
                    Button {
                        accountOpen = true
                    } label: {
                        VStack(spacing: 5) {
                            Text("This folder is tied to this phone")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.label2)
                            Label("Save your account", systemImage: "checkmark.shield.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .wellBackground()
                    }
                    .buttonStyle(.plain)
                }
            } else if let failedMessage {
                VStack(spacing: 14) {
                    Text(failedMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.label2)
                        .multilineTextAlignment(.center)

                    Button {
                        self.failedMessage = nil
                        attempt += 1
                    } label: {
                        Text("Try again")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.label)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .wellBackground()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
            } else {
                ProgressView().tint(Theme.accent).padding(.vertical, 30)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FloorBackdrop().ignoresSafeArea())
        .task(id: attempt) {
            if let c = await sync.shareTeam(team) {
                code = c
            } else {
                failedMessage = sync.lastError ?? "Couldn’t create a code. Check your connection and try again."
            }
        }
        .sheet(isPresented: $accountOpen) {
            NavigationStack { AccountView() }
        }
    }
}

// MARK: - Join folder sheet

/// Member-side: enter a 6-char code to join someone else's folder. On success
/// the sheet dismisses and the roster streams in via SyncEngine's listeners.
///
/// `prefilledCode` is how a scanned QR / tapped invite link arrives (RootView
/// hands it over from `onOpenURL`). The code is filled in but NOT auto-
/// submitted — joining someone's folder is the user's call to make, and a link
/// can be opened by accident.
struct JoinFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var busy = false
    @State private var error: String?
    private let sync = SyncEngine.shared

    init(prefilledCode: String = "") {
        _code = State(initialValue: prefilledCode)
    }

    private var trimmed: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("JOIN A FOLDER")
                .font(.system(size: 11, weight: .heavy)).tracking(2)
                .foregroundStyle(Theme.label3)
                .padding(.top, 22)

            TextField("", text: $code, prompt:
                Text("CODE").foregroundStyle(Theme.label3))
                .font(Theme.barlow(34, .bold))
                .tracking(6)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.label)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .wellBackground()
                .onChange(of: code) { _, _ in error = nil }

            if let error {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.majorFall)
                    .multilineTextAlignment(.center)
            }

            Button { join() } label: {
                Group {
                    if busy { ProgressView().tint(Theme.accentText) }
                    else { Text("JOIN").font(.system(size: 14, weight: .heavy)).tracking(1.5) }
                }
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.accent.opacity(trimmed.count < 6 ? 0.35 : 1)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(trimmed.count < 6 || busy)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FloorBackdrop().ignoresSafeArea())
    }

    private func join() {
        busy = true
        error = nil
        Task {
            switch await sync.joinTeam(code: trimmed) {
            case .joined:
                dismiss()
            case .invalidCode:
                error = "No folder found for that code."
            case .notSignedIn:
                error = "Sign-in isn’t ready yet — try again in a moment."
            case .failed(let msg):
                error = "Couldn’t join: \(msg)"
            }
            busy = false
        }
    }
}
