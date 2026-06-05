import SwiftUI
import SwiftData

/// The counter. Built for the floor: pick a group once, then hammer one of
/// four giant outcome buttons per rep. Full-surface tap targets, haptics, undo.
struct LogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StuntGroup.orderIndex) private var groups: [StuntGroup]
    @Query private var sessions: [PracticeSession]

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue

    @State private var selectedGroup: StuntGroup?
    @State private var hapticTrigger = 0
    @State private var showGroupsEditor = false

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    private var activeSession: PracticeSession? {
        sessions.filter(\.isActive).max { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = activeSession {
                    activeView(session)
                } else {
                    idleView
                }
            }
            .background(Theme.appBG)
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(mode.nounPluralTitle) { showGroupsEditor = true }
                }
            }
            .sheet(isPresented: $showGroupsEditor) {
                GroupsEditorView()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    // MARK: Idle (no active session)

    private var idleView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "figure.gymnastics")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("Ready to count")
                .font(.system(size: 22, weight: .bold))
            Text("Start a practice, pick a \(mode.noun), and log every stunt rep as it lands.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()

            Button {
                let s = PracticeSession()
                context.insert(s)
                try? context.save()
                selectedGroup = groups.first
                hapticTrigger += 1
            } label: {
                Text("Start practice")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: Active session

    private func activeView(_ session: PracticeSession) -> some View {
        let attempts = session.sortedAttempts
        let hits = attempts.filter { $0.outcome.isHit }.count
        let rate = attempts.isEmpty ? nil : Int((Double(hits) / Double(attempts.count) * 100).rounded())

        return VStack(spacing: 12) {
            // Session header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(elapsed(since: session.startedAt))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    Text("\(attempts.count) reps\(rate.map { " · \($0)% hit" } ?? "")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.label2)
                }
                Spacer()
                Button {
                    session.endedAt = .now
                    try? context.save()
                    hapticTrigger += 1
                } label: {
                    Text("End")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.majorFall)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Theme.majorFall.opacity(0.12))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Group picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groups) { g in
                        let on = selectedGroup === g
                        Button {
                            selectedGroup = g
                            hapticTrigger += 1
                        } label: {
                            HStack(spacing: 7) {
                                Text("\(g.number)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(g.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(g.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(on ? .white : Theme.label)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(on ? Color.black : Theme.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(on ? .clear : Theme.separator, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Outcome pad
            if let group = selectedGroup ?? groups.first {
                let groupCounts = countsFor(group: group, in: attempts)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                          spacing: 10) {
                    ForEach(Outcome.allCases) { o in
                        Button {
                            context.insert(Attempt(outcome: o, group: group, session: session))
                            try? context.save()
                            selectedGroup = group
                            hapticTrigger += 1
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(groupCounts[o.rawValue])")
                                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.label)
                                    .contentTransition(.numericText(value: Double(groupCounts[o.rawValue])))
                                    .animation(.spring(duration: 0.3), value: groupCounts[o.rawValue])
                                Text(o.label)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(o == .bobble ? Color(hex: 0xA88A00) : o.color)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 92)
                            .background(o.color.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(o.color.opacity(0.4), lineWidth: 1.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            } else {
                Text("Add a \(mode.noun) first (\(mode.nounPluralTitle), top right).")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label2)
                    .padding(.top, 30)
            }

            // Recent + undo
            HStack {
                Text("RECENT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.88)
                    .foregroundStyle(Theme.label2)
                Spacer()
                Button {
                    if let last = attempts.last {
                        context.delete(last)
                        try? context.save()
                        hapticTrigger += 1
                    }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(attempts.isEmpty ? Theme.label3 : Theme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(attempts.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(attempts.suffix(12).reversed().enumerated()), id: \.offset) { _, a in
                        HStack(spacing: 10) {
                            Circle().fill(a.outcome.color).frame(width: 9, height: 9)
                            Text(a.group?.name ?? "—")
                                .font(.system(size: 14, weight: .medium))
                            Text(a.outcome.label)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.label2)
                            Spacer()
                            Text(a.timestamp.tapeTime)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.label3)
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func countsFor(group: StuntGroup, in attempts: [Attempt]) -> [Int] {
        var counts = [0, 0, 0, 0]
        for a in attempts where a.group === group {
            counts[a.outcomeRaw] += 1
        }
        return counts
    }

    private func elapsed(since start: Date) -> String {
        let s = Int(Date.now.timeIntervalSince(start))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
