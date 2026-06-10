import SwiftUI

struct WatchLogView: View {
    @Bindable var store: WatchLogStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    if store.snapshot.groups.isEmpty {
                        emptyState
                    } else {
                        groupPicker
                        outcomeGrid
                    }
                }
                .padding(.horizontal, 4)
            }
            .containerBackground(.black, for: .navigation)
            .navigationTitle("HitRate")
            .toolbar {
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
                store.requestSnapshot()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.snapshot.teamName.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(store.statusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(store.isLogging ? .green : .primary)
        }
    }

    private var emptyState: some View {
        Text("Open HitRate on iPhone to sync your \(store.snapshot.nounPlural), then log from here.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
    }

    private var groupPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.snapshot.groups) { group in
                    let selected = store.selectedGroup?.id == group.id
                    Button {
                        store.selectedGroupID = group.id
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(group.number)")
                                .font(.system(size: 12, weight: .heavy))
                            Text(group.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: 56, height: 42)
                        .foregroundStyle(selected ? .black : .white)
                        .background(selected ? Color.green : Color.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var outcomeGrid: some View {
        let group = store.selectedGroup
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
            ForEach(group?.outcomes ?? []) { outcome in
                let count = group?.counts[safe: outcome.rawValue] ?? 0
                Button {
                    store.log(outcome: outcome)
                } label: {
                    VStack(spacing: 2) {
                        Text("\(count)")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Text(outcome.shortLabel)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
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
        }
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
