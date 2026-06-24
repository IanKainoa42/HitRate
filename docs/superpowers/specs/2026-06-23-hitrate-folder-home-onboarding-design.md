# HitRate 1.1 — Folder-list home, universal "skill" noun, onboarding redesign

**Date:** 2026-06-23
**Status:** Approved design → implementation
**Trigger:** On-device smoke test of build 12 (1.1) surfaced UX problems in the
just-added folder/noun/custom-outcome feature, plus an onboarding-clarity ask.

## Release plan

Build 12 (1.1) is uploaded to ASC but **abandoned** — it ships the half-baked
per-folder-noun UX that the smoke test rejected ("Add athlete" on an athlete
folder). Nothing was submitted to Apple, so this is free. We fold the changes
below into a fresh build (13), re-test on ianPad, then ship 1.1 (build 13).

## In scope

### 1. Folder-list home (new root)

A new landing screen sits above the dashboard.

- Lists every folder (`Team`) with its name and skill count, plus a
  `+ New folder` action.
- Tapping a folder sets `@AppStorage("currentTeamID")` to that team and opens
  its existing `HomeView` dashboard. Back returns to the list.
- Onboarding still creates the first folder, then lands the user on that
  folder's dashboard (not the list) so first-run flows straight into use.
- The folder switcher already in the Home header stays; the list is an
  additional, higher-level entry point.
- **Design for the future:** structure the list so a later "a skill belongs to
  multiple folders + umbrella/aggregate stats" rollup can render above or beside
  the per-folder rows without reworking this screen. Not built now.

This replaces the current behavior where launch drops onto the Home dashboard's
empty "Today" timeframe ("No reps logged"), which reads as a dead landing.

### 2. Remove the per-folder word; "skill" is universal

- Delete the `Team.itemNoun` free-text override and its editor row
  (`GroupsEditorView` "tracks ___"). The model field may remain for migration
  safety but is no longer surfaced or read for wording.
- Inner items are called **"skill" everywhere**, for both athlete and coach
  mode. A coach simply makes a skill per stunt group.
- Fix all roster surfaces to read "skill":
  - Folder empty state: `Lucy has no skills yet` (was "no groups yet").
  - Add button: `Add skill` (was "Add athlete" / "Add group").
  - Editor section headers, practice pad, and "Skill Report" copy stay on
    "skill" (already mostly the case in athlete mode; coach mode's "group"
    wording in these roster-management surfaces switches to "skill").
- Outcome wording is unaffected — it still keys off `SkillKind`
  (stunt/tumbling) via `OutcomeNames`.

### 3. Onboarding redesign

New flow:

1. **Who's counting?** — keep the existing athlete/coach chooser.
2. **Name** — athlete name, or program/team for coach (existing fields).
3. **Headline question** — big, bold **"What skills do you want to track?"** set
   at headline weight in the court register (Space Grotesk), not the current
   faint caption.
4. **Focus picker — 4 areas:** Stunts · Tumbling · Jumps · Tosses. Each maps to
   a CheerRulesKit `SkillCategory` and selects which execution-driver / issue
   set a created skill carries:
   - Stunts → `.stunts` (Bases/Spotters, Top Person, Transitions/Dismounts, Sync)
   - Tumbling → `.standingTumbling` (Approach, Body Control, Landings, Sync) —
     standing/running tumbling share identical drivers, so Tumbling is one area.
   - Jumps → `.jumps` (Leg Placement, Arm Placement, Sync)
   - Tosses → `.tosses` (Top Person, Bases/Spotters, Height)
   - Pyramid folds into Stunts (identical drivers); pyramid + the standing/
     running split are not surfaced as separate first-run areas.
5. **Suggested-skill chips** for the chosen focus, with **"add your own"** as the
   last chip. Tapping a chip creates the skill tagged with that focus's category
   so its drivers are correct from the first rep.
6. **Reassurance** — "You can add more anytime."

Suggestion chip lists (locked):

| Focus | Chips |
|-------|-------|
| Stunts | Prep, Extension, Full up lib, Released inversion |
| Tumbling | Roundoff, Back walkover, Back handspring, Roundoff double HS |
| Jumps | Pencil jump, Toe touch, Left hurdler, Right hurdler, Pike, Double toe touch |
| Tosses | Straight ride, Full twist, Kick full basket, Double basket, Kick double basket |

A created skill's category sets its `hitRateKind` (`.tumbling` for tumbling,
`.stunt` for the rest) so the existing outcome-word system keeps working.

## Deferred to 1.2 (designed-around, not built now)

- **User-definable custom preset / outcome-driver sets** — beyond the per-folder
  custom outcomes that already shipped, let users author their own issue/driver
  sets and presets. New feature; needs its own design pass.
- **Cross-folder skill linking + umbrella stats** — a skill shared across folders
  with rolled-up aggregate stats. The folder-list home is built so this can land
  on top later.

## Fragile-area compliance (from CLAUDE.md / fragile memory)

- Outcome enum order (hit/bobble/buildingFall/majorFall) untouched.
- `Outcome.label(_:)`/`short(_:)` keep reading through `OutcomeNames.shared`
  (@Observable) — no raw UserDefaults reads added.
- No `Rarity.of(rate:)` reintroduced; card rarity stays milestone-difficulty.
- `SkillKind` keeps changing outcome *words only*, never slot indexing; new
  focus areas map onto it via `SkillCategory.hitRateKind`.
- Editor rename fields stay on `RenameField` (local buffer), not direct
  `OutcomeNames`/@Model bindings.
- Build number bumped in `project.yml` for both targets, then `xcodegen
  generate`; ship via fastlane `ship_upload`.

## Addendum 2026-06-24 — device test findings + expanded scope

On-device test of the rebuilt 1.1 surfaced a **data-loss class of bug** plus a
gap in the outcome model. Scope expanded (user: "fold it in now"). The build
becomes a proper multi-stage cycle, NOT a same-day ship.

### Forensic finding (data loss — confirmed via on-device store)

Pulled `default.store` off ianPad and read SwiftData's persistent history:
- Store is healthy (3 folders, 16 skills, 17 reps) — NOT a global wipe or
  in-memory fallback.
- Lucy's missing skill = `StuntGroup` PK 25, **deleted 2026-06-23 17:59:11**;
  the same transaction cascade-deleted its 37 logged reps.
- A separate transaction at 17:55:48 deleted **1,738 attempts** at once.
- Root cause is a class of **destructive delete paths**: skill delete cascades
  its reps; `sweepOrphanedAttempts` hard-deletes orphaned reps on launch with no
  prompt; staged practice reps drop if the session ends before Submit.
- Deleted rows are unrecoverable (history stores only row IDs, not data).

### Stage A — Data-integrity gate (build + device-verify FIRST)

1. **Soft-delete / Trash.** Add `deletedAt: Date?` to `StuntGroup` and `Team`.
   Deleting sets `deletedAt` instead of removing; the row and its reps are kept.
   Every roster query filters `deletedAt == nil`. A Trash section (in Data
   Management) lists soft-deleted skills/folders with Restore and an explicit
   "Delete permanently." No auto-purge in v1 — nothing is hard-deleted without
   an explicit permanent-delete tap.
2. **No launch-time hard delete.** `sweepOrphanedAttempts` stops deleting;
   orphaned attempts are re-homed (or left), never destroyed on launch.
3. **Confirm before skill delete** when the skill has reps, showing the count.
4. **Auto-commit staged reps on End** — ending a practice commits staged reps
   instead of dropping them; plus a larger/clearer Submit affordance.

### Stage B — Per-category outcomes + grid

Today `SkillCategory.hitRateKind` collapses jumps/tosses into the *stunt*
outcome words, and the grid renders ONE outcome-header row keyed to a single
kind — so jumps/tosses have no outcomes of their own and the grid can't show
per-skill outcomes. Stage B gives each category its own taggable
outcome/issue set (surfacing the CheerRulesKit execution drivers) WITHOUT
disturbing the load-bearing 4 severity slots / hit-rate spine, and reworks the
grid to show each skill's own outcomes. Detailed design TBD before building
(its own design pass — touches the Outcome/OutcomeNames/grid fragile areas).

### Stage B — design (locked 2026-06-24)

**Model: Hit + swappable issues.** The 4 severity slots stay (rawValue-indexed
spine intact). Slot 0 is always the clean outcome → hit rate / cards /
tournament keep working. Slots 1–3 are per-skill swappable issue words, seeded
from the skill's `SkillCategory` (drivers for jumps/tosses; established severity
words for stunts/tumbling).

Category default outcome words (slot 0 = clean):

| Category | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| stunts / pyramid | Hit | Bobble | Building fall | Major fall |
| standing/running tumbling | Stuck | Stepped out | Touched down | Major fall |
| jumps | Hit | Legs | Arms | Sync |
| tosses | Hit | Top | Bases | Height |

Implementation:
- `SkillCategory.defaultOutcomeWords: [String]` (4) — new source of truth for
  defaults, replaces the kind-only `defaultLabel`. Existing stunt/tumbling words
  preserved.
- **Per-skill override:** `StuntGroup.outcomeOverridesRaw` (newline-joined 4;
  blank slot = category default). Additive field → lightweight migration.
- Resolution: `Outcome.label(for: StuntGroup)` / `short(for:)` =
  skill override ?? category default. The PAD, GRID, and a skill's own tape use
  per-skill words; aggregate legends/cards stay on the category/kind default
  (mixed rosters can't share one custom set).
- `OutcomeNames.shared` stays for the stunt/tumbling per-kind custom renames
  (back-compat) and remains @Observable so renames re-render.
- **Editor:** per-skill outcome editor — edit slots 1–3 (and slot 0 word),
  seeded from category, quick-pick from the category's drivers.
- **Grid rework:** each skill row renders its OWN outcome labels, lifting the
  single-kind `gridAvailable` restriction (a tumbling row shows tumbling words,
  a jump row shows jump words). Per-row mini-labels instead of one shared header.

Fragile-area care: slot order + rawValue indexing unchanged; `OutcomeNames`
reads stay observable; no `Rarity.of(rate:)`.

### Stage C — Navigation

- A "Skills" button replacing the small header dropdown.
- Opening the editor while already inside a folder must NOT show the
  folder-picker ("Choose your folder") — you're already in it; switching folders
  happens by exiting to the folder-list home.

## Testing

No test target exists (project mechanics note). Verification is the on-device
ianPad re-test against the smoke checklist, extended with: folder-list home
navigation, "skill" wording on an athlete folder, and the new onboarding focus
→ suggested-skill → driver-set path.
