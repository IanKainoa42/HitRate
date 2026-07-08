# Project: Quick Clinic / Guest Coach Workflow

## Architecture
- **In-Memory SwiftData Context**: Ephemeral `ModelContainer` injected at the top of `LogView` when `isClinic` is true. Isolated completely from the main SQLite DB and the lifetime Milestones calculations.
- **HomeView Quick Clinic Trigger**: A wand-button next to standard Practice CTA presenting a setup sheet.
- **Quick Clinic Setup Sheet**: Stepper configuration for mat count (1-12, default 6) and target hit rate goal (50-95%, default 80%).
- **Interactive LogView**: Ephemeral session matrix (`logGrid`) supporting inline row renames (`RenameField`) and a "Customize Outcome Labels" sheet that replicates custom labels across all mats.
- **Summary Wrap-up Cover**: Renders Canvas session tape, leaderboard mat ranking, holographic share card preview carousel (`HoloCardView` with `isSnapshot: true`), and AirDrop share button.
- **Loss Aversion Warning / Paywall**: Exit warning modal showing exact count of unsaved reps. Link to Pro/Director Cloud subscription paywall.
- **SQLite Database Archival Migration**: Archival routine saving the ephemeral `ModelContainer` data to the default persistent SQLite store on Pro upgrade.

## Code Layout
- `HitRate/Views/Home/HomeView.swift` — Main dashboard & Quick Clinic launcher.
- `HitRate/Views/Log/LogView.swift` — Practice grid/pad view. Includes Inline Renames & Custom Outcome Headers.
- `HitRate/Views/QuickClinic/` — Directory containing setup sheets, warning dialogs, and paywalls:
  - `QuickClinicSetupSheet.swift`
  - `QuickClinicSummaryView.swift`
  - `QuickClinicExitWarningSheet.swift`
  - `PremiumPaywallSheet.swift`
- `HitRate/Models/Models.swift` — Standard model declarations.
- `HitRate/Stats/StatsEngine.swift` — Computation of percentages, rankings, and trends.
- `HitRate/Stats/Milestones.swift` — Milestone dynamic generation.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| 1 | Setup & Exploration | Research codebase structures and draft architecture. | None | DONE |
| 2 | Implementation of E2E Test Suite | Build opaque-box test runner/cases for R1-R4 verification. | M1 | PLANNED |
| 3 | Core Implementation | Add quick clinic setup sheet, LogView integration (in-memory context, inline renames, outcome customization), summary cover, exit warning, paywall, and SQLite archiving logic. | M2 | PLANNED |
| 4 | Verification & Hardening | Run all test cases and perform forensic integrity audit. | M3 | PLANNED |

## Interface Contracts
### `HomeView` ↔ `LogView`
- Ephemeral clinic sessions are launched by injecting a separate `ModelContainer` using `.modelContainer(clinicContainer)` view modifier.
- When `isClinic` is true, the `LogView` accepts `goalRate: Int` to drive the goal progress gradient.

### Ephemeral-to-SQLite Archiving
- Function: `archiveClinicSession(clinicContext: ModelContext, mainContext: ModelContext)`
- Reads Team, Groups, Attempts, and Tallies from clinicContext, inserts equivalents into mainContext, saves, and executes `Milestones.sync(...)`.
