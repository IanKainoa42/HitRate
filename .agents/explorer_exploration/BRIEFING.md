# BRIEFING — 2026-07-07T12:15:00-07:00

## Mission
Investigate HitRate codebase to recommend a design for the Quick Clinic / Guest Coach workflow.

## 🔒 My Identity
- Archetype: Teamwork explorer
- Roles: Read-only investigator
- Working directory: /Users/ianrichardson/Projects/HitRate/.agents/explorer_exploration/
- Original parent: 8f09f16e-9156-4a81-92ae-f4e114204583
- Milestone: Quick Clinic Design Completed

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Run no build or test commands yourself; just analyze the code and report.

## Current Parent
- Conversation ID: 8f09f16e-9156-4a81-92ae-f4e114204583
- Updated: 2026-07-07T12:15:00-07:00

## Investigation State
- **Explored paths**: HomeView.swift, OnboardingView.swift, LogView.swift, Models.swift, Milestones.swift, SessionTapeCard.swift, StatsEngine.swift, HoloCardView.swift, ShareCardsSheet.swift, GroupsEditorView.swift, project.yml
- **Key findings**: SwiftData `@Query` automatically binds to the environment container, which allows complete roster/session isolation via an in-memory `ModelContainer`.
- **Unexplored areas**: None.

## Key Decisions Made
- Ephemeral container design: Using in-memory `ModelContainer` for roster isolation.
- Inline editing: Using `RenameField` from `GroupsEditorView` directly in the `logGrid` layout.
- Reciprocity: Showing summary sheet + card carousel, and copying data to standard SQLite context upon premium upgrade.

## Artifact Index
- /Users/ianrichardson/Projects/HitRate/.agents/explorer_exploration/ORIGINAL_REQUEST.md — Original user request log
- /Users/ianrichardson/Projects/HitRate/.agents/explorer_exploration/analysis.md — Design analysis report
