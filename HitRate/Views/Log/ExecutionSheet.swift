import SwiftUI
import SwiftData
import CheerRulesKit

/// The optional EXECUTION read for a single rep (Feature B). Binary held/lost
/// tags — NEVER point math. You start with every driver HELD and only tap the
/// ones that slipped. Committing writes `executionScored = true`; that's the
/// only path that records execution data, so a rep you never open stays "not
/// scored" and can't inflate the breakdown (the non-inflating rule).
///
/// Training-floor register: recessed wells, chalk text, the green accent means
/// "held / clean". A slipped driver reads coral — the miss hue — never green.
struct ExecutionSheet: View {
    let attempt: Attempt

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Driver keys the coach has marked as slipped this session on the sheet.
    @State private var lost: Set<String> = []
    @State private var hapticTrigger = 0

    private var drivers: [ExecutionDriver] { attempt.group?.executionDrivers ?? [] }
    private var skillName: String { attempt.group?.displayName ?? "Skill" }
    private var outcomeWord: String { attempt.outcomeDef?.label ?? "—" }
    private var heldCount: Int { drivers.count - lost.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    driverList
                    note
                }
                .padding(16)
            }
            .background(Theme.well.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.label2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save read") { save() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .onAppear {
            // Preload an existing read; a fresh rep starts all-held (empty).
            if attempt.executionScored { lost = Set(attempt.lostDrivers) }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.selection, trigger: hapticTrigger)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXECUTION READ")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(Theme.label2)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(skillName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                Circle().fill(attempt.outcomeDef?.color ?? Theme.label3).frame(width: 7, height: 7)
                Text(outcomeWord)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.label2)
            }
            HStack(spacing: 6) {
                Text("\(heldCount)/\(drivers.count) held")
                    .font(Theme.barlow(15, .bold))
                    .foregroundStyle(heldCount == drivers.count ? Theme.accent : Theme.buildingFall)
                Text("· tap what slipped")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var driverList: some View {
        VStack(spacing: 8) {
            ForEach(drivers) { d in
                let slipped = lost.contains(d.key)
                Button {
                    if slipped { lost.remove(d.key) } else { lost.insert(d.key) }
                    hapticTrigger += 1
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: slipped ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(slipped ? Theme.majorFall : Theme.accent)
                        Text(d.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.label)
                        Spacer(minLength: 0)
                        Text(slipped ? "SLIPPED" : "HELD")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(slipped ? Theme.majorFall : Theme.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.surface2)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(slipped ? Theme.majorFall.opacity(0.5) : Color.clear, lineWidth: 1))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Execution is a separate read — it never changes the hit rate. Reps you don't score here record no execution data (they're not counted as clean).")
                .font(.system(size: 12))
                .foregroundStyle(Theme.label3)
                .fixedSize(horizontal: false, vertical: true)
            if attempt.executionScored {
                Button(role: .destructive) { clear() } label: {
                    Label("Clear this read", systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.majorFall)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Actions

    private func save() {
        attempt.scoreExecution(lost: drivers.map(\.key).filter { lost.contains($0) })
        try? context.save()
        dismiss()
    }

    private func clear() {
        attempt.clearExecution()
        try? context.save()
        dismiss()
    }
}
