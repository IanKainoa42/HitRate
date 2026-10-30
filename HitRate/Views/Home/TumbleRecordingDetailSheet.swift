import SwiftUI

/// Shows every raw skill block and the coach's review without mutating the
/// original StuntScope analysis. Excluded blocks remain here for restoration.
struct TumbleRecordingDetailSheet: View {
    let recording: TumbleCloudSync.Recording
    let teamID: String
    let ownerUID: String?
    let athleteNames: [String: String]

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var review: TumbleReview
    @State private var skillDrafts: [String: String]
    @State private var saving = false
    @State private var error: String?

    init(recording: TumbleCloudSync.Recording, teamID: String, ownerUID: String?,
         athleteNames: [String: String]) {
        self.recording = recording
        self.teamID = teamID
        self.ownerUID = ownerUID
        self.athleteNames = athleteNames
        _review = State(initialValue: recording.review)
        _skillDrafts = State(initialValue: recording.archive.blocks.reduce(into: [:]) { drafts, block in
            drafts[block.reviewKey] = recording.review.skillOverrides[block.reviewKey] ?? block.skill
        })
    }

    private var canEdit: Bool {
        auth.uid == recording.loggerID || (ownerUID != nil && auth.uid == ownerUID)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Skill blocks", value: "\(recording.archive.blocks.count)")
                    LabeledContent("Pose frames", value: "\(recording.archive.poses.count)")
                    LabeledContent("Frame rate", value: String(format: "%.1f fps", recording.archive.framesPerSecond))
                    if review.hiddenRecording {
                        Text("Hidden from dashboard stats and spreadsheets. You can restore it below.")
                            .foregroundStyle(.secondary)
                    }
                    if canEdit {
                        Button(review.hiddenRecording ? "Restore recording" : "Hide entire recording",
                               systemImage: review.hiddenRecording ? "arrow.uturn.backward" : "eye.slash") {
                            var changed = review
                            changed.hiddenRecording.toggle()
                            save(changed)
                        }
                        .disabled(saving)
                    }
                } header: { Text("Recording") } footer: {
                    Text("Measurements are linked to this video and its tracked athletes. Review changes sync with your HitRate folder.")
                }

                if let error { Text(error).foregroundStyle(.red) }

                ForEach(Array(recording.archive.blocks.enumerated()), id: \.offset) { item in
                    let block = item.element
                    Section {
                        DisclosureGroup {
                            blockDetails(block)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(athlete(for: block)) · \(review.skillOverrides[block.reviewKey] ?? block.skill)")
                                    .font(.headline)
                                Text("\(seconds(block.firstFrame))–\(seconds(block.lastFrame)) s · Track \(block.trackID)" +
                                     (review.excludedBlockKeys.contains(block.reviewKey) ? " · Excluded" : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Text("In/Out: body lean from the feet toward the centre of mass at ground contact and takeoff. Launch: centre-of-mass travel angle at takeoff. Flip/Twist: rotations per second at takeoff. A dash means StuntScope did not measure that value.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Phase marks and pose frames come from the tracked video. These measurements do not count as HitRate hit/miss reps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: { Text("What these stats mean") }
            }
            .navigationTitle(recording.archive.recordingTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .overlay { if saving { ProgressView("Saving review…").padding().background(.regularMaterial) } }
        }
    }

    @ViewBuilder private func blockDetails(_ block: TumbleArchive.Block) -> some View {
        if canEdit {
            HStack {
                TextField("Skill name", text: Binding(
                    get: { skillDrafts[block.reviewKey] ?? block.skill },
                    set: { skillDrafts[block.reviewKey] = $0 }))
                    .textInputAutocapitalization(.words)
                Button("Save name") {
                    let name = (skillDrafts[block.reviewKey] ?? block.skill).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { error = "Enter a skill name first."; return }
                    var changed = review
                    if name == block.skill { changed.skillOverrides.removeValue(forKey: block.reviewKey) }
                    else { changed.skillOverrides[block.reviewKey] = name }
                    save(changed)
                }
                .disabled(saving)
            }
            Button(review.excludedBlockKeys.contains(block.reviewKey) ? "Restore this block" : "Exclude false block",
                   systemImage: review.excludedBlockKeys.contains(block.reviewKey) ? "arrow.uturn.backward" : "minus.circle") {
                var changed = review
                if changed.excludedBlockKeys.contains(block.reviewKey) { changed.excludedBlockKeys.remove(block.reviewKey) }
                else { changed.excludedBlockKeys.insert(block.reviewKey) }
                save(changed)
            }
            .disabled(saving)
        }
        if review.excludedBlockKeys.contains(block.reviewKey) {
            Text("Excluded from dashboard counts and both spreadsheets.")
                .font(.caption).foregroundStyle(.secondary)
        }

        metric("In angle", block.inOutStroke?.inDegrees, unit: "°")
        metric("Out angle", block.inOutStroke?.outDegrees, unit: "°")
        LabeledContent("Contact frames", value: block.inOutStroke.map { String($0.paintedFrames) } ?? "—")
        metric("Launch angle", block.launchDegrees, unit: "°")

        if block.takeoffSpeeds.isEmpty && block.takeoffRatings.isEmpty {
            LabeledContent("Flip rate", value: "—")
            LabeledContent("Twist rate", value: "—")
        }
        ForEach(Array(block.takeoffSpeeds.enumerated()), id: \.offset) { item in
            let speed = item.element
            Text("Takeoff at \(seconds(speed.frameIndex)) s")
                .font(.subheadline.weight(.semibold))
            metric("Flip rate", speed.flip, unit: " rps")
            metric("Twist rate", speed.twist, unit: " rps")
            if let airtime = speed.airtimeSeconds { metric("Airtime", airtime, unit: " s") }
            if speed.flipIsKeyed == true || speed.twistIsMarked == true {
                Text("Flip: \(speed.flipIsKeyed == true ? "keyed" : "estimated") · Twist: \(speed.twistIsMarked == true ? "marked" : "estimated")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if speed.flagged == true {
                Text("A noisy speed sample was dropped from this fit.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        ForEach(Array(block.takeoffRatings.enumerated()), id: \.offset) { item in
            let rating = item.element
            Text("Coach rating at \(seconds(rating.takeoffFrame)) s")
                .font(.subheadline.weight(.semibold))
            LabeledContent("Flip", value: rating.flip ?? "Not rated")
            LabeledContent("Twist", value: rating.twist ?? "Not rated")
        }
        if let marks = block.phases?.marks, !marks.isEmpty {
            Text("Phase marks").font(.subheadline.weight(.semibold))
            ForEach(Array(marks.enumerated()), id: \.offset) { item in
                let mark = item.element
                LabeledContent(mark.boundary.replacingOccurrences(of: "_", with: " ").capitalized,
                    value: "\(mark.frameIndex.map { seconds($0) + " s" } ?? "—") · \(mark.status)")
                if let note = mark.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        } else {
            LabeledContent("Phase marks", value: "None")
        }
        let poseCount = recording.archive.poses.filter {
            $0.trackID == block.trackID && $0.frameIndex >= block.firstFrame && $0.frameIndex <= block.lastFrame
        }.count
        LabeledContent("Tracked pose frames", value: "\(poseCount)")
    }

    private func metric(_ title: String, _ value: Double?, unit: String) -> some View {
        LabeledContent(title, value: value.map { String(format: "%.2f", $0) + unit } ?? "—")
    }

    private func seconds(_ frame: Int) -> String {
        recording.archive.framesPerSecond > 0
            ? String(format: "%.2f", Double(frame) / recording.archive.framesPerSecond)
            : "?"
    }

    private func athlete(for block: TumbleArchive.Block) -> String {
        recording.athleteIDs[String(block.trackID)].flatMap { athleteNames[$0] } ?? "Track \(block.trackID)"
    }

    private func save(_ changed: TumbleReview) {
        guard !saving else { return }
        saving = true
        error = nil
        Task {
            do {
                try await TumbleCloudSync.saveReview(teamID: teamID,
                    recordingID: recording.archive.recordingID, review: changed)
                review = changed
            } catch {
                self.error = "Couldn't save review: \(error.localizedDescription)"
            }
            saving = false
        }
    }
}
