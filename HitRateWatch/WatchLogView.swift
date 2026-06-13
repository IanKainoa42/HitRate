import SwiftUI
import WatchKit

struct WatchLogView: View {
    @Bindable var store: WatchLogStore
    @State private var crown: Double = 0
    @FocusState private var crownFocused: Bool

    /// Whole-screen, no-scroll layout: the skill name is the nav title and the
    /// four outcome buttons split all remaining space in a fixed 2×2. The crown
    /// scrolls through the roster; tapping the lock toggle freezes the pick.
    var body: some View {
        NavigationStack {
            Group {
                if store.snapshot.groups.isEmpty {
                    emptyState
                } else {
                    outcomeGrid
                }
            }
            .containerBackground(.black, for: .navigation)
            .navigationTitle(store.selectedGroup?.name ?? "HitRate")
            .navigationBarTitleDisplayMode(.inline)
            // Crown switches the skill while unlocked; ignored once locked so a
            // turn mid-log can't bump the selection.
            .focusable(canSwitch)
            .focused($crownFocused)
            .digitalCrownRotation(
                $crown,
                from: 0,
                through: Double(max(0, store.snapshot.groups.count - 1)),
                by: 1,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true)
            .onChange(of: crown) { _, value in
                guard canSwitch else { return }
                let i = min(max(0, Int(value.rounded())), store.snapshot.groups.count - 1)
                if i != store.selectionIndex { store.selectionIndex = i }
            }
            .onChange(of: store.selectionIndex) { _, i in
                if crown.rounded() != Double(i) { crown = Double(i) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.snapshot.groups.count > 1 {
                        Button {
                            store.locked.toggle()
                            WKInterfaceDevice.current().play(store.locked ? .click : .directionUp)
                            if !store.locked { crownFocused = true }
                        } label: {
                            Image(systemName: store.locked ? "lock.fill" : "lock.open")
                                .foregroundStyle(store.locked ? .green : .secondary)
                        }
                        .accessibilityLabel(store.locked ? "Unlock skill picker" : "Lock skill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.requestSnapshot()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Sync roster")
                }
            }
            .task {
                crown = Double(store.selectionIndex)
                crownFocused = true
                store.requestSnapshot()
            }
        }
    }

    /// Crown is live only when unlocked and there's more than one skill to pick.
    private var canSwitch: Bool {
        !store.locked && store.snapshot.groups.count > 1
    }

    private var emptyState: some View {
        Text("Open HitRate on iPhone to sync your \(store.snapshot.nounPlural), then log from here.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }

    private var outcomeGrid: some View {
        let group = store.selectedGroup
        let outcomes = group?.outcomes ?? []
        return VStack(spacing: 6) {
            ForEach(Array(stride(from: 0, to: outcomes.count, by: 2)), id: \.self) { i in
                HStack(spacing: 6) {
                    outcomeButton(outcomes[i], group: group)
                    if i + 1 < outcomes.count {
                        outcomeButton(outcomes[i + 1], group: group)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func outcomeButton(_ outcome: WatchOutcomeSnapshot,
                               group: WatchGroupSnapshot?) -> some View {
        let count = group?.counts[safe: outcome.rawValue] ?? 0
        return Button {
            store.log(outcome: outcome)
        } label: {
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text(outcome.shortLabel)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(outcomeColor(outcome.rawValue).opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(outcomeColor(outcome.rawValue), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(outcome.label)")
    }

    private func outcomeColor(_ rawValue: Int) -> Color {
        switch rawValue {
        case 0: return .green
        case 1: return .orange
        case 2: return .yellow
        default: return .red
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
