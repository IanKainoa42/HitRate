import SwiftUI

/// Entry point for account-synced StuntScope recordings. A recording stays visible
/// even when hidden, so a coach can restore it after a mistaken review.
struct TumblingVideoCard: View {
    let teamID: String?
    let ownerUID: String?
    let subjects: [Subject]

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var recordings: [TumbleCloudSync.Recording] = []
    @State private var selected: Selection?
    @State private var error: String?

    private struct Selection: Identifiable {
        let recording: TumbleCloudSync.Recording
        var id: UUID { recording.archive.recordingID }
    }

    private var syncKey: String { "\(teamID ?? ""):\(auth.uid ?? "")" }
    private var athleteNames: [String: String] {
        Dictionary(uniqueKeysWithValues: subjects.map { ($0.id.uuidString, $0.name) })
    }

    var body: some View {
        if !recordings.isEmpty || error != nil {
            FeedCard {
                CardHead("TUMBLING VIDEO") {
                    Text("\(recordings.count) synced video\(recordings.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.label3)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                ForEach(recordings, id: \.archive.recordingID) { recording in
                    Button { selected = Selection(recording: recording) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(recording.archive.recordingTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(summary(for: recording))
                                    .font(.caption)
                                    .foregroundStyle(Theme.label3)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.label3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open skill measurements and review false detections")
                }
            }
        }
        Color.clear.frame(height: 0)
            .task(id: syncKey) { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
            .sheet(item: $selected, onDismiss: { Task { await refresh() } }) { selection in
                TumbleRecordingDetailSheet(recording: selection.recording,
                    teamID: teamID ?? "", ownerUID: ownerUID, athleteNames: athleteNames)
            }
    }

    private func summary(for recording: TumbleCloudSync.Recording) -> String {
        if recording.review.hiddenRecording { return "Hidden from stats · Tap to restore" }
        let blocks = recording.reviewedArchive.blocks
        let excluded = recording.review.excludedBlockKeys.count
        let athletes = Set(blocks.compactMap { recording.athleteIDs[String($0.trackID)] })
        let athleteText = athletes.count == 1 ? "1 athlete" : "\(athletes.count) athletes"
        return "\(blocks.count) skill block\(blocks.count == 1 ? "" : "s") · \(athleteText)" +
            (excluded > 0 ? " · \(excluded) excluded" : "")
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
