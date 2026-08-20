import SwiftUI
import SwiftData

/// Set (or change) a weekly rep target on one skill for some of the roster.
/// Owner-only — the coach's side of the homework feature.
///
/// Everything here is deliberately coarse: a skill, a number, some names, a
/// note. There is no schedule, no per-day breakdown, no due time. Offseason
/// homework is "get this many reps in before we meet again", and every extra
/// field would be one more thing to maintain for a coach already juggling a
/// season's worth of squads.
struct AssignmentEditorSheet: View {
    /// Nil = creating; non-nil = editing that assignment in place.
    var existing: Assignment?
    let team: Team?
    let skills: [StuntGroup]
    let roster: [Subject]
    let createdByUID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Selected by id, not by model reference — a SwiftData object makes a
    /// fragile `Picker` tag, and the id is what we persist anyway.
    @State private var skillID: UUID?
    @State private var target = 50
    @State private var note = ""
    /// Empty = everyone (including athletes added later).
    @State private var chosen: Set<UUID> = []
    @State private var loaded = false

    /// Quick targets — the numbers a coach actually says out loud.
    private let presets = [25, 50, 75, 100, 150]

    private var skill: StuntGroup? { skills.first { $0.id == skillID } }
    private var canSave: Bool { skill != nil && target > 0 }
    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            // `List` + `Theme.well` rows, matching GroupsEditorView — the app's
            // other editor sheet. A stock grouped `Form` reads as a different app.
            List {
                skillSection
                targetSection
                athleteSection
                noteSection
            }
            .scrollContentBackground(.hidden)
            .background(FloorBackdrop().ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit homework" : "Assign homework")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: load)
    }

    // MARK: Sections

    private var skillSection: some View {
        Section {
            Picker("Skill", selection: $skillID) {
                Text("Choose a skill").tag(UUID?.none)
                ForEach(skills) { s in
                    Text(s.displayName).tag(UUID?.some(s.id))
                }
            }
        } header: {
            Text("What they're working")
        }
        .listRowBackground(Theme.well)
    }

    private var targetSection: some View {
        Section {
            HStack {
                Text("Reps per week")
                Spacer()
                Text("\(target)")
                    .font(Theme.barlow(22, .bold))
                    .foregroundStyle(Theme.accent)
            }
            Stepper("Adjust", value: $target, in: 1...2000, step: 5)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { p in
                    Button {
                        target = p
                    } label: {
                        Text("\(p)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(target == p ? Theme.accentText : Theme.label)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(target == p ? Theme.accent : Theme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("How much")
        } footer: {
            Text("Any rep counts toward the target — the point is volume. Hit rate on those reps is reported next to it, so quality still shows.")
        }
        .listRowBackground(Theme.well)
    }

    private var athleteSection: some View {
        Section {
            Button {
                chosen.removeAll()
            } label: {
                HStack {
                    Text("Everyone")
                        .foregroundStyle(Theme.label)
                    Spacer()
                    if chosen.isEmpty {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(roster) { subject in
                Button {
                    toggle(subject)
                } label: {
                    HStack {
                        Circle()
                            .fill(Theme.groupColor(subject.orderIndex % Theme.groupRainbow.count))
                            .frame(width: 8, height: 8)
                        Text(subject.displayName)
                            .foregroundStyle(Theme.label)
                        Spacer()
                        if chosen.contains(subject.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Who")
        } footer: {
            Text(chosen.isEmpty
                 ? "Assigned to the whole roster, including anyone you add later."
                 : "Assigned to \(chosen.count) \(chosen.count == 1 ? "athlete" : "athletes").")
        }
        .listRowBackground(Theme.well)
    }

    private var noteSection: some View {
        Section {
            TextField("e.g. chest up out of the set", text: $note, axis: .vertical)
                .lineLimit(1...4)
        } header: {
            Text("Note (optional)")
        }
        .listRowBackground(Theme.well)
    }

    // MARK: Actions

    private func toggle(_ subject: Subject) {
        if chosen.contains(subject.id) {
            chosen.remove(subject.id)
        } else {
            chosen.insert(subject.id)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            skillID = existing.group?.id
            target = existing.targetReps
            note = existing.note
            chosen = Set(existing.subjectIDs)
        } else {
            skillID = skills.first?.id
        }
    }

    private func save() {
        guard let skill else { return }
        let ids = Array(chosen)
        if let existing {
            existing.link(skill)
            existing.targetReps = target
            existing.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.subjectIDs = ids
        } else {
            let assignment = Assignment(
                group: skill, targetReps: target, subjectIDs: ids,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                createdByUID: createdByUID
            )
            assignment.team = team
            context.insert(assignment)
        }
        try? context.save()
        dismiss()
    }
}
