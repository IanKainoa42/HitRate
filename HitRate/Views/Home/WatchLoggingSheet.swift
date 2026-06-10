import SwiftUI

struct WatchLoggingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let status: WatchConnectionStatus
    let groups: [StuntGroup]
    let activeSessionReps: Int
    let mode: AppMode

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                FeedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "applewatch")
                                .font(.system(size: 23, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 42, height: 42)
                                .background(iconTile)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(status.title.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundStyle(Theme.label2)
                                Text(status.detail)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.label)
                            }
                        }

                        Divider().overlay(Theme.separator)

                        HStack {
                            watchStat("\(groups.count)", label: mode.nounPlural.uppercased())
                            watchStat("\(activeSessionReps)", label: "LIVE REPS")
                        }
                    }
                }

                FeedCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Watch logs use this roster", systemImage: "list.bullet.rectangle")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.label)
                        ForEach(groups.prefix(6)) { group in
                            HStack(spacing: 8) {
                                Text("\(group.number)")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(group.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(group.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.label)
                                Spacer()
                                Text(group.kind.label.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1.1)
                                    .foregroundStyle(Theme.label3)
                            }
                        }
                        if groups.count > 6 {
                            Text("+ \(groups.count - 6) more")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.label3)
                        }
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(FloorBackdrop().ignoresSafeArea())
            .navigationTitle("Apple Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.iconTile)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.iconTileEdge.opacity(0.85), lineWidth: 1))
    }

    private func watchStat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.barlow(28, .extrabold))
                .foregroundStyle(Theme.label)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Theme.label3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
