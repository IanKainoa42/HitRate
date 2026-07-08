# Handoff Report — Quick Clinic / Guest Coach Workflow Investigation

## 1. Observation
- **Practice session entry**: In `HitRate/Views/Home/HomeView.swift` (lines 209-257), standard practice is initialized by inserting a `PracticeSession` directly into the SQLite model context (`context.insert(s)` and `try? context.save()`).
- **Roster data binding**: In `HitRate/Views/Log/LogView.swift` (lines 21-22), the groups array is queried using `@Query`:
  ```swift
  @Query(sort: \StuntGroup.orderIndex) private var allGroups: [StuntGroup]
  ```
- **Milestone evaluation**: `HitRate/Stats/Milestones.swift` (lines 39-302) performs purely dynamic calculations of milestones on-the-fly, reading from the passed arrays of `sessions` and `groups`.
- **Canvas session tape**: In `HitRate/Views/Home/SessionTapeCard.swift` (lines 22-35), attempts are drawn chronologically using a `Canvas` view.
- **Card Snapshot rendering**: In `HitRate/Views/Share/ShareCardsSheet.swift` (lines 268-275), cards are captured dynamically at `scale = 3` using `ImageRenderer` with `HoloCardView(..., isSnapshot: true)`.
- **Outcome labeling**: In `HitRate/Models/Models.swift` (lines 243-265), outcome labels and abbreviations are evaluated through `OutcomeNames.shared` and `Outcome.label(_:)`/`short(_:)`.

## 2. Logic Chain
- By wrapping the presented `LogView` in a custom `modelContainer(...)` view modifier populated with an in-memory `ModelContainer` configured with `isStoredInMemoryOnly: true`, the `@Query` property wrapper in `LogView` will target the ephemeral store instead of the persistent SQLite store.
- This creates absolute database isolation, meaning attempts logged during the clinic are stored only in memory and won't pollute standard queries.
- Consequently, the dynamic calculations in `Milestones.swift` and `StatsEngine.swift` will remain unaffected in standard views because they pull from the SQLite store.
- Upon purchasing the Pro version, we can fetch all rows from the in-memory database and copy them to the main SQLite database by re-inserting them, ensuring that the practice session is archived permanently.

## 3. Caveats
- Watch remote sync: Tapping a mat in Quick Clinic updates the watch snapshot. The `RootView`'s snapshot publisher should verify if watch syncing should be suspended or adapted for guest clinics to avoid synchronization crashes with SQLite databases.
- Multi-staging mode: Staged reps in Grid mode are held in a local `@State` dictionary. We must make sure that exiting or ending the clinic commits or properly drops them.

## 4. Conclusion
The Quick Clinic design is fully feasible and non-intrusive to the existing codebase structure. Roster isolation is achieved clean and safe via SwiftData's architecture. In-place Mat/descriptor renames can be solved inline using `RenameField` on grid rows. The wrap-up summary sheet will render the session's Canvas tape and a carousel of 6 holographic mat cards. If the user exits, an ethical loss-aversion prompt offers to either discard the clinic or save the report to the roster by unlocking Coach Pro / Director Cloud via a price-anchored subscription paywall.

## 5. Verification Method
1. Start the Catalyst or Simulator build.
2. Launch a Quick Clinic and log attempts. Exit the session and verify that the main dashboard remains at 0 reps (isolation works).
3. Open a new Quick Clinic, log attempts, complete the mock Pro upgrade, and verify that the session is correctly copied to the SQLite DB and stats update successfully.
