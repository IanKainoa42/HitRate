# Per-Athlete Roster Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated Roster screen that ranks every athlete/subject by clean-hit rate (rate-band colored for triage) and drills into the existing per-athlete dashboard filter, plus an athlete column in the CSV export.

**Architecture:** A new `RosterView` full-screen cover (training-floor register, modeled on `TrophyRoomView`) computes one `StatsEngine.compute(subject:)` per subject — no new stats math. `HomeView` gains a header button that opens it; tapping a row sets Home's existing `personFilter` and closes the cover. `CSVExportItem` gains a subject column.

**Tech Stack:** SwiftUI, SwiftData, iOS 17+. xcodegen owns the project; no test target exists (verification = `xcodebuild build` + simulator smoke, matching project practice).

## Global Constraints

- **No new files in the xcodeproj by hand** — xcodegen owns the project, but it globs `HitRate/**`, so a new `.swift` file under `HitRate/Views/Home/` is picked up on the next `xcodegen generate`. Run `xcodegen generate` after adding the file.
- **Design register = training floor** (RosterView is app UI, not a share card): `FloorBackdrop`, `wellBackground()`, chalk text (`Theme.label`/`label2`/`label3`), the single green accent `Theme.accent` only for go/hit signals. NO glass/glow/sparkle. Numerals in `Theme.barlow(size, weight)`; words in SF.
- **Rate bands** are `Theme.rateColor(_ rate: Int, hasData: Bool = true)` — ≥75 green / 55–74 amber / <55 red. This is the ONLY rate coloring; do not hand-roll thresholds.
- **Clean-hit rate** is `FloorStats.rate` (0–100). Matches the dashboard headline, per-skill %, and RATE CUP. Do not substitute a weighted score.
- **Subject wording adapts by mode:** athlete mode → athletes ("Roster"/"athlete"); coach mode → groups ("Groups"/"group"). Mirror the existing `subjectKind` (`mode == .coach ? .group : .person`) and `everyoneLabel` logic.
- **Build command:**
  ```sh
  xcodegen generate
  xcodebuild -project HitRate.xcodeproj -scheme HitRate \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
  ```
- Commit after each task. Do NOT push (Ian pushes on request).

---

## File Structure

- **Create** `HitRate/Views/Home/RosterView.swift` — the roster full-screen cover (header + ranked rows + drill-in callback). One responsibility: present per-subject stats and report a selection.
- **Modify** `HitRate/Views/Home/HomeView.swift` — add `rosterOpen` state, a header button (gated on `!subjects.isEmpty`), and the `.fullScreenCover` that wires drill-in to `personFilter`.
- **Modify** `HitRate/Utilities/CSVExport.swift` — add a subject column to `Row`, header, and body.

Reused, unchanged: `StatsEngine.compute(subject:)`, `Theme.rateColor`/`barlow`, `FloorBackdrop`, `wellBackground()`, `Subject.displayName`, `Timeframe.label`.

---

## Task 1: CSV export — athlete/subject column

**Files:**
- Modify: `HitRate/Utilities/CSVExport.swift`

**Interfaces:**
- Consumes: `Attempt.subject?.name` (String?), `AppMode.current` (`.coach`/`.athlete`).
- Produces: `CSVExportItem.Row.subject: String`; CSV gains a subject column between the bucket noun and outcome.

- [ ] **Step 1: Add the `subject` field to `Row` and populate it**

In `HitRate/Utilities/CSVExport.swift`, change the `Row` struct and the `init` map. Replace lines 10-31 (the `struct Row { … }`, the `noun` property, and the `init`) with:

```swift
    struct Row {
        let timestamp: Date
        let sessionStart: Date
        let group: String
        let subject: String
        let outcome: String
    }

    let rows: [Row]
    let noun: String          // CSV header column for the bucket ("skill"/"group")
    let subjectNoun: String   // CSV header column for the row ("athlete"/"group")

    init(sessions: [PracticeSession]) {
        noun = AppMode.current.noun
        subjectNoun = AppMode.current == .coach ? "group" : "athlete"
        rows = sessions
            .flatMap { s in
                s.sortedAttempts.map {
                    Row(timestamp: $0.timestamp, sessionStart: s.startedAt,
                        group: $0.group?.name ?? "",
                        subject: $0.subject?.name ?? "",
                        outcome: $0.outcome.label($0.group?.kind ?? .stunt))
                }
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
```

- [ ] **Step 2: Emit the column in the header and each row**

In the same file, replace the `write()` header line and row-append block (lines 37-44) with:

```swift
        var csv = ["timestamp", "session_start", noun, subjectNoun, "outcome"].map(Self.csvField).joined(separator: ",") + "\n"
        for r in rows {
            csv += [
                iso.string(from: r.timestamp),
                iso.string(from: r.sessionStart),
                r.group,
                r.subject,
                r.outcome
            ].map(Self.csvField).joined(separator: ",") + "\n"
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```sh
xcodebuild -project HitRate.xcodeproj -scheme HitRate \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```sh
git add HitRate/Utilities/CSVExport.swift
git commit -m "CSV export: add athlete/subject column"
```

---

## Task 2: RosterView screen

**Files:**
- Create: `HitRate/Views/Home/RosterView.swift`

**Interfaces:**
- Consumes: `StatsEngine.compute(sessions:groups:timeframe:subject:) -> FloorStats` (uses `.rate: Int`, `.total: Int`, `.delta: Int?`, `.hasData: Bool`); `Subject` (`.id: UUID`, `.displayName: String`); `SubjectKind` (`.person`/`.group`); `Timeframe.label`; `Theme.rateColor`, `Theme.barlow`, `FloorBackdrop`, `wellBackground()`.
- Produces:
  ```swift
  struct RosterView: View {
      let sessions: [PracticeSession]
      let groups: [StuntGroup]
      let subjects: [Subject]
      let timeframe: Timeframe
      let subjectKind: SubjectKind
      let onSelect: (Subject) -> Void
  }
  ```
  Task 3 constructs it with exactly these labels and passes an `onSelect` closure.

- [ ] **Step 1: Write the file**

Create `HitRate/Views/Home/RosterView.swift`:

```swift
import SwiftUI
import SwiftData

/// The roster — every athlete (coach mode: every group) ranked by clean-hit
/// rate so a coach can triage who's hitting and who needs reps at a glance.
/// Training-floor register (app UI, like the Trophy Room). Read-only: tapping a
/// row hands the subject back to Home, which re-scopes its per-athlete dashboard
/// via the existing person filter. All numbers reuse StatsEngine.compute(subject:).
struct RosterView: View {
    let sessions: [PracticeSession]
    let groups: [StuntGroup]
    let subjects: [Subject]
    let timeframe: Timeframe
    let subjectKind: SubjectKind
    let onSelect: (Subject) -> Void

    @Environment(\.dismiss) private var dismiss

    /// One computed line per subject: with-data lines ranked by rate desc, then
    /// the zero-rep tail (greyed, unranked).
    private struct Line: Identifiable {
        let subject: Subject
        let stats: FloorStats
        var id: UUID { subject.id }
    }

    private var lines: [Line] {
        let computed = subjects.map { s in
            Line(subject: s,
                 stats: StatsEngine.compute(sessions: sessions, groups: groups,
                                            timeframe: timeframe, subject: s))
        }
        let withData = computed.filter { $0.stats.hasData }
            .sorted { $0.stats.rate > $1.stats.rate }
        let empty = computed.filter { !$0.stats.hasData }
        return withData + empty
    }

    private var title: String { subjectKind == .person ? "ROSTER" : "GROUPS" }

    var body: some View {
        VStack(spacing: 9) {
            header
            ScrollView {
                VStack(spacing: 9) {
                    ForEach(lines) { line in
                        row(line)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(FloorBackdrop().ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.system(size: 15, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(Theme.label)
                }
                Text(timeframe.label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.label2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .wellBackground()
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: Row

    @ViewBuilder
    private func row(_ line: Line) -> some View {
        let s = line.stats
        Button { onSelect(line.subject) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.subject.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    if s.hasData {
                        HStack(spacing: 6) {
                            Text("\(s.total) rep\(s.total == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.label3)
                            if let d = s.delta, d != 0 {
                                HStack(spacing: 1) {
                                    Image(systemName: d > 0 ? "arrow.up" : "arrow.down")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("\(abs(d))")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(d > 0 ? Theme.accent : Theme.label2)
                            }
                        }
                    } else {
                        Text("No reps logged")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.label3)
                    }
                }
                Spacer(minLength: 6)
                if s.hasData {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(s.rate)")
                            .font(Theme.barlow(30, .bold))
                        Text("%")
                            .font(Theme.barlow(15, .semibold))
                    }
                    .foregroundStyle(Theme.rateColor(s.rate))
                } else {
                    Text("—")
                        .font(Theme.barlow(30, .bold))
                        .foregroundStyle(Theme.label3)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .wellBackground()
            .opacity(s.hasData ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

Note: `Theme.barlow`'s weight enum is `BarlowWeight` with `.bold`/`.semibold` cases (used elsewhere in the app); if the exact case names differ, match `Theme.barlow(_:_:)`'s signature in `Theme/Theme.swift`.

- [ ] **Step 2: Regenerate the project so xcodegen picks up the new file**

Run:
```sh
xcodegen generate
```
Expected: `Created project at …/HitRate.xcodeproj`

- [ ] **Step 3: Build to verify it compiles**

Run:
```sh
xcodebuild -project HitRate.xcodeproj -scheme HitRate \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. If it fails on `Theme.barlow`'s weight argument, open `HitRate/Theme/Theme.swift` line ~93, read the `BarlowWeight` cases, and correct the call.

- [ ] **Step 4: Commit**

```sh
git add HitRate/Views/Home/RosterView.swift HitRate.xcodeproj/project.pbxproj
git commit -m "Add RosterView: per-subject stats ranked by clean-hit rate"
```

---

## Task 3: Wire RosterView into Home

**Files:**
- Modify: `HitRate/Views/Home/HomeView.swift`

**Interfaces:**
- Consumes: `RosterView(sessions:groups:subjects:timeframe:subjectKind:onSelect:)` from Task 2; existing `HomeView` members `subjects: [Subject]`, `subjectKind: SubjectKind`, `personFilter: Subject?`, `groups`, `sessions`, `timeframe`, `iconButtonBackground`.
- Produces: a reachable roster cover; drill-in sets `personFilter` and closes the cover.

- [ ] **Step 1: Add the cover-state flag**

In `HitRate/Views/Home/HomeView.swift`, after `@State private var watchOpen = false` (line 28), add:

```swift
    @State private var rosterOpen = false
```

- [ ] **Step 2: Add the header button (gated on having subjects)**

In the `header` computed property, immediately after the trophy `Button { … }.buttonStyle(.plain)` block (ends line 454) and before the share `Button { shareOpen = true }` block, insert:

```swift
            // Roster — every athlete/group ranked by clean-hit rate.
            if !subjects.isEmpty {
                Button {
                    rosterOpen = true
                } label: {
                    Image(systemName: "person.2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.label2)
                        .frame(width: 34, height: 34)
                        .background(iconButtonBackground)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
```

- [ ] **Step 3: Present the cover and wire drill-in**

After the trophy `.fullScreenCover(isPresented: $trophyOpen) { … }` block (ends line 212) and before the `.fullScreenCover(item: $logSession …)` block, insert:

```swift
        .fullScreenCover(isPresented: $rosterOpen) {
            RosterView(sessions: sessions, groups: groups, subjects: subjects,
                       timeframe: timeframe, subjectKind: subjectKind) { subject in
                personFilter = subject
                rosterOpen = false
            }
        }
```

- [ ] **Step 4: Build**

Run:
```sh
xcodebuild -project HitRate.xcodeproj -scheme HitRate \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Simulator smoke (no test target — this is the verification)**

Install and launch on the booted sim, then verify by hand/screenshot:
```sh
APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 4 -name 'HitRate.app' -path '*Debug-iphonesimulator*' -print -quit)
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.ianrichardson.HitRate
```
Expected on a team that has logged per-athlete reps (use CaptureView to log a few for 2+ subjects first, or the demo dataset):
1. A `person.2` button appears in the Home header (only when the team has subjects).
2. Tapping it opens the roster full-screen: athletes ranked by rate desc, rate-band colors, rep counts + deltas; zero-rep athletes greyed at the bottom.
3. Tapping an athlete row closes the cover and the Home dashboard is now filtered to that athlete (the person chip shows their name).
4. The header button is ABSENT for a team with no subjects.

- [ ] **Step 6: Commit**

```sh
git add HitRate/Views/Home/HomeView.swift
git commit -m "Wire Roster screen into Home header with drill-in to person filter"
```

---

## Self-Review

**Spec coverage:**
- Entry point / header button / mode-adaptive label → Task 3 (button) + Task 2 (`title`). ✓
- Full-screen cover, floor register → Task 2 (`FloorBackdrop`, `wellBackground`). ✓
- Rows: name + rate% (rate-band) + reps + delta → Task 2 `row(_:)`. ✓
- Ranking by rate desc, zero-rep greyed tail → Task 2 `lines`. ✓
- Per-athlete numbers via `compute(subject:)` → Task 2. ✓
- Timeframe inherited, shown as label → Task 3 passes `timeframe`; Task 2 header shows `timeframe.label`. ✓
- Drill-in reuses person filter → Task 3 `onSelect` sets `personFilter`. ✓
- Hidden when no subjects → Task 3 `if !subjects.isEmpty`. ✓
- Export athlete column → Task 1. ✓
- Out of scope (per-athlete milestones, roster league, own timeframe tabs, logging-path change) → not present. ✓

**Placeholder scan:** No TBD/TODO; all code shown in full. The one conditional note (Barlow weight case names) includes the exact file+line to check and how to correct. ✓

**Type consistency:** `RosterView(sessions:groups:subjects:timeframe:subjectKind:onSelect:)` is defined identically in Task 2 and constructed in Task 3. `FloorStats.rate/total/delta/hasData` match the struct at `StatsEngine.swift:78-108`. `Subject.id/displayName`, `SubjectKind.person`, `Timeframe.label` all verified against source. `Row.subject` added consistently in header + body (Task 1). ✓
