import SwiftUI

/// Account-synced stability analyses, separate from logged hit/miss reps.
struct StuntAnalysisCard: View {
    let teamID: String?
    let groups: [StuntGroup]
    let subjects: [Subject]

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var analyses: [StuntCloudSync.Analysis] = []
    @State private var selected: StuntCloudSync.Analysis?
    @State private var frames: StuntCloudSync.FrameArchive?
    @State private var error: String?

    private var syncKey: String { "\(teamID ?? ""):\(auth.uid ?? "")" }
    private func skillName(_ id: String) -> String {
        groups.first { $0.id.uuidString == id }?.name ?? "Stunt"
    }
    private func athleteNames(_ analysis: StuntCloudSync.Analysis) -> String {
        let names = analysis.athleteIDs.compactMap { id in subjects.first { $0.id.uuidString == id }?.name }
        return names.joined(separator: ", ")
    }

    var body: some View {
        if !analyses.isEmpty || error != nil {
            FeedCard {
                CardHead("STUNT STABILITY") {
                    Text("\(analyses.count) shared analysis\(analyses.count == 1 ? "" : "es")")
                        .font(.caption)
                        .foregroundStyle(Theme.label3)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                ForEach(analyses) { analysis in
                    Button {
                        selected = analysis
                        frames = nil
                        Task { await loadFrames(analysis) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(analysis.title).font(.subheadline.weight(.semibold))
                                Text("\(skillName(analysis.skillID)) · \(analysis.onBasePercent)% on base · \(String(format: "%.1f", analysis.holdSeconds))s hold")
                                    .font(.caption).foregroundStyle(Theme.label3)
                                if !athleteNames(analysis).isEmpty {
                                    Text(athleteNames(analysis)).font(.caption).foregroundStyle(Theme.label3)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Text("Video analysis only. These do not count as hit or miss reps.")
                    .font(.caption).foregroundStyle(Theme.label3)
            }
        }
        Color.clear.frame(height: 0)
            .task(id: syncKey) { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
            .sheet(item: $selected) { analysis in
                NavigationStack {
                    List {
                        Section("Stability") {
                            LabeledContent("On base", value: "\(analysis.onBasePercent)%")
                            LabeledContent("Hold", value: String(format: "%.1f s", analysis.holdSeconds))
                            LabeledContent("Wobbles", value: "\(analysis.wobbleCount)")
                            if let worst = analysis.worstWobbleSecond {
                                LabeledContent("Worst wobble", value: String(format: "%.1f s", worst))
                            }
                            if let longest = analysis.flightSeconds.max() {
                                LabeledContent("Longest flight", value: String(format: "%.2f s", longest))
                            }
                        }
                        Section("Shared data") {
                            if let frames {
                                LabeledContent("Judged frames", value: "\(frames.frames.count)")
                                LabeledContent("Frame rate", value: String(format: "%.1f fps", frames.fps))
                            } else if let error {
                                Text(error).foregroundStyle(.red)
                            } else {
                                ProgressView("Loading frame data…")
                            }
                            Text("This analysis does not change HitRate's hit rate.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle(analysis.title)
                    .toolbar { Button("Done") { selected = nil } }
                }
            }
    }

    private func refresh() async {
        guard auth.uid != nil, let teamID else { analyses = []; return }
        do { analyses = try await StuntCloudSync.load(teamID: teamID); error = nil }
        catch { self.error = "Couldn't sync stunt analysis: \(error.localizedDescription)" }
    }

    private func loadFrames(_ analysis: StuntCloudSync.Analysis) async {
        do { frames = try await StuntCloudSync.frames(for: analysis); error = nil }
        catch { self.error = "Couldn't load frame data: \(error.localizedDescription)" }
    }
}
