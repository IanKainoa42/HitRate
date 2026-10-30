import SwiftUI

/// Account-synced video measurements, beside the existing stunt stability card.
/// These are measured skill blocks, not logged outcomes, so they do not change hit rate.
struct TumblingVideoCard: View {
    let teamID: String?
    let subjects: [Subject]

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var recordings: [TumbleCloudSync.Recording] = []
    @State private var error: String?

    private var syncKey: String { "\(teamID ?? ""):\(auth.uid ?? "")" }

    private struct Row: Identifiable {
        let id: String
        let recordingTitle: String
        let block: TumbleArchive.Block
        let athlete: String
    }

    private var rows: [Row] {
        let names = Dictionary(uniqueKeysWithValues: subjects.map { ($0.id.uuidString, $0.name) })
        var result: [Row] = []
        for recording in recordings {
            for block in recording.archive.blocks {
                let athleteID = recording.athleteIDs[String(block.trackID)]
                let athlete = athleteID.flatMap { names[$0] } ?? "Track \(block.trackID)"
                result.append(Row(id: "\(recording.archive.recordingID):\(block.tagID)",
                    recordingTitle: recording.archive.recordingTitle,
                    block: block, athlete: athlete))
            }
        }
        return Array(result.prefix(8))
    }

    var body: some View {
        if !rows.isEmpty || error != nil {
            FeedCard {
                CardHead("TUMBLING VIDEO") {
                    Text("\(recordings.count) synced video\(recordings.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.label3)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        TumbleBlockRow(block: row.block, athlete: row.athlete)
                        Text(row.recordingTitle)
                            .font(.caption2)
                            .foregroundStyle(Theme.label3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        Color.clear.frame(height: 0)
            .task(id: syncKey) { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
    }

    private func refresh() async {
        guard auth.uid != nil, let teamID else { recordings = []; return }
        do {
            recordings = try await TumbleCloudSync.load(teamID: teamID)
            error = nil
        } catch {
            self.error = "Couldn't sync tumbling: \(error.localizedDescription)"
        }
    }
}
