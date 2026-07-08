## 2026-07-07T19:10:06Z
Implement the complete "Quick Clinic / Guest Coach" workflow in HitRate, including UI components, database isolation, and migration logic.

Please implement the following:

1. Refactor `RenameField` component:
   - Move `RenameField` (the struct currently private in `HitRate/Views/Log/GroupsEditorView.swift`) to `HitRate/Views/Components/Components.swift`.
   - Remove the `private` keyword so it is internal and accessible across files.
   - Remove the original `private struct RenameField` from `GroupsEditorView.swift` to avoid duplicate symbol errors.

2. Create `HitRate/Views/QuickClinic/QuickClinicSetupSheet.swift`:
   - A modal view that lets the user select:
     - Mat count: stepper with value range 1 to 12 (default: 6).
     - Target hit rate goal: stepper/picker with value range 50% to 95% (default: 80%).
   - Include a 66% completed goal gradient progress pill styled using SwiftUI:
     - Text/icons showing: `[✓ Coach Mode] -> [✓ X Mats Ready] -> [Tap to Log]` (where X is the current mat count).
     - Make it look polished, matching the brand bento style.
   - A "START CLINIC" button that triggers `onStart(matCount: Int, goalRate: Int)` closure.

3. Create `HitRate/Views/QuickClinic/PremiumPaywallSheet.swift`:
   - A paywall modal showcasing the "HitRate Pro Cloud Archive / Director Report" upgrade.
   - Present price-anchored pricing:
     - "HitRate Pro Cloud Archive / Director Report: $49/yr"
     - Anchor subtitle: "Just $4.08/month — less than the cost of a single private coaching lesson!"
   - A button to "Unlock Pro Features" that simulates successful payment, sets an upgrade success state, and triggers `onUpgradeSuccess()` closure.

4. Create `HitRate/Views/QuickClinic/QuickClinicExitWarningSheet.swift`:
   - A detent sheet presented when a clinic coach tries to close/exit an unarchived clinic.
   - Display a gentle warning warning that closing will discard all data forever.
   - Include the exact count of logged attempts/reps at risk of being discarded.
   - Provide buttons: "SAVE TO PERMANENT ROSTER" (opens/redirects to Paywall) and "Erase & Discard" (triggers `onDiscard()` closure).

5. Create `HitRate/Views/QuickClinic/QuickClinicSummaryView.swift`:
   - A wrap-up view that renders:
     - Radial `CourtBackdrop` background.
     - Big overall hit rate % of the session (using rate-band coloring).
     - Interactive `SessionTapeCard` drawing the chronological Canvas session tape.
     - Leaderboard of mats ranked by hit rate.
     - "EXPORT HOLOGRAPHIC MAT CARDS" button presenting the `ShareCardsSheet` (passing the clinic's groups and session).
     - "SAVE TO PERMANENT ROSTER" button triggering the paywall/save flow.
     - Close (X) button presenting the exit warning sheet if the session has reps and is not yet archived.

6. Modify `HitRate/Views/Log/LogView.swift`:
   - Add properties:
     - `var isClinic: Bool = false`
     - `var goalRate: Int = 80`
     - `var onArchive: (() -> Void)? = nil`
   - In the practice session header, if `isClinic` is true and attempts have been logged, display a progress pill:
     - Capsule bar showing progress of current hit rate toward `goalRate`.
     - Text showing `\(rate)% / \(goalRate)% GOAL`.
   - In `logGrid` row labels (around line 377), if `isClinic` is true:
     - Use `RenameField` instead of the static `Text(g.name)` to support inline mat descriptions renaming.
   - In `LogView` header next to the practice/clinic title:
     - If `isClinic` is true, show `RenameField` to edit the clinic camp name (mapping to the `Team.name` of the in-memory context) directly.
   - In the "END" practice button action:
     - If `isClinic` is true, show the `QuickClinicSummaryView` in a sheet/cover instead of immediately calling `dismiss()`.

7. Modify `HitRate/Views/Home/HomeView.swift`:
   - Add a wand button next to the standard practice CTA (as styled in design notes or inline with the CTA).
   - The button presents the `QuickClinicSetupSheet` modal.
   - Implement `startClinic(matCount: Int, goalRate: Int)`:
     - Creates an in-memory SwiftData `ModelContainer` configured with `isStoredInMemoryOnly: true`.
     - Inserts a new `Team` named "Guest Clinic" (or user custom name).
     - Inserts `matCount` groups named "Mat 1" to "Mat N".
     - Inserts an active `PracticeSession`.
     - Saves the context.
     - Sets the `activeClinicSession` and presents `LogView` with the container.
   - Implement `archiveClinicSession(clinicContext: ModelContext, mainContext: ModelContext)`:
     - Copies Team, Groups, Attempts, and CustomOutcomes from clinic store to the persistent store.
     - Commits the persistent store and runs `Milestones.sync(...)` to synchronize achievements.

8. Run `xcodegen generate` and build the project for the simulator destination to verify there are no compilation errors:
   - `xcodebuild -project HitRate.xcodeproj -scheme HitRate -destination 'platform=iOS Simulator,name=iPhone 17' build`

9. Verify that the E2E test suite still passes successfully by running it on the booted simulator:
   - `xcrun simctl install booted /Users/ianrichardson/Library/Developer/Xcode/DerivedData/HitRate-ehzkrjprviksdsfluymjsrngrhku/Build/Products/Debug-iphonesimulator/HitRate.app`
   - `xcrun simctl launch booted com.ianrichardson.HitRate --run-e2e-tests`
   - Confirm `/tmp/hitrate-test-results.json` shows successful execution.
