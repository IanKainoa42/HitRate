# Design doc — Flexible containers + United execution drivers

Status: **DRAFT for review** · 2026-06-21 · owner: Ian

Two features, scoped from the design session:

1. **Flexible containers** — separate one set of stats from another, labelled
   freely (athlete / team / folder — the word doesn't matter).
2. **United execution drivers** — keep the locked base 4, but let a skill log
   *which execution driver broke* on a miss, using the United Scoring System
   taxonomy that already lives in CheerCenter / CheerRulesKit.

## Decisions locked (this session)
- Containers: **flat**, no nesting. Reuse `Team` as a relabelable "folder".
- Drivers: **Approach X (flags)** — every rep still carries a base outcome; the
  driver is an attribution tag on misses. Keeps the whole dashboard/cards/
  tournament/watch working.
- Source of truth: the **United Scoring System** taxonomy, sourced from
  **CheerRulesKit** (not hand-rolled). See "Source" below.
- Per-rep driver tagging is **multi-select** (a rep can break on Body Control
  *and* Landings) — Ian to confirm; trivially reversible to single.
- Deduction-weighted score: **deferred** (flags first), but deductions are
  stored so the weighted "execution score" is a fast-follow.

## Hard constraints (do not break)
- The base `Outcome` enum (hit / bobble / buildingFall / majorFall) stays
  **locked**: severity order, colors, `rawValue` indexing are load-bearing
  across stats, cards, tournament, watch. Drivers layer on top.
- Stats stay pure functions of attempts (no stored derived numbers).
- Team-scoping already works app-wide (`allGroups.inTeam(currentTeam)`); reuse.

---

## The United taxonomy (verified against Ian's code)

**Categories** — `SkillCategory` (CheerRulesKit): stunts · pyramid · tosses ·
standing tumbling · running tumbling · jumps.

**Execution drivers per category** — from CheerCenter's
`ExecutionScoreInputView.swift` (weights from `PracticeSession.swift`):

| Category | Execution drivers (max deduction each) |
|---|---|
| Stunts | Bases/Spotters · Top Person · Transitions/Dismounts · Synchronization (0.3) |
| Pyramid | Bases/Spotters · Top Person · Transitions/Dismounts · Synchronization (0.3) |
| Tosses | Top Person · Bases/Spotters · Height |
| Jumps | Leg Placement (0.3) · Arm Placement (0.3) · Synchronization (0.1) |
| Standing Tumbling | Approach · Body Control · Landings · Synchronization (0.3) |
| Running Tumbling | Approach · Body Control · Landings · Synchronization (0.3) |

**Per-rep fault statuses** — `PerformanceStatus` (CheerRulesKit), category-aware
via `applicableSkillTypes`, with deductions:
- Tumbling: Hit · Athlete Fall (0.15) · Major Athlete Fall (0.25)
- Stunting (stunts/pyramids/tosses): Hit · Building Bobble (0.25) · Building
  Fall (0.75) · Major Building Fall (1.25)
- Jumps: Hit · Missed Skill · Not Attempted (no fault tiers in the model)

HitRate's base 4 already mirror the United *building* tiers (Hit / Bobble≈
Building Bobble / Building Fall / Major Fall). Drivers are the *attribution*
layer underneath a miss.

---

## Feature 1 — Flexible containers (small)

`Team` already is the separable stat container (own roster, stats, cups, league,
all scoped by `currentTeamID` + `.inTeam`). The only gap is language. Add:

```swift
@Model final class Team {
    // ...existing...
    /// What this folder's buckets are called: "athlete" / "skill" / "group"…
    /// Empty = fall back to the global AppMode noun. Singular; plural derived.
    var itemNoun: String = ""
}
```
- Editor "Teams" section reads "Folders"; each row gets a small "Tracks: __" noun
  control.
- Centralize bucket-noun reads through `currentTeam?.noun(for: mode)` (Home
  header, empty/no-roster states, editor titles).
- No nesting, no athlete sub-model. A private lesson = a folder with a bucket per
  kid; a tumbling block = a folder of tumbling skills.

---

## Feature 2 — United drivers (the meat)

### Skill gains a category
Replace the binary `SkillKind` (stunt/tumbling) with the 6-way `SkillCategory`.
Migration: `kindRaw "stunt" → .stunts`, `"tumbling" → .standingTumbling`
(lightweight, default-preserving); user can reassign in the editor. The
category determines which execution drivers a skill exposes — no per-skill
driver authoring needed for v1 (the United sets are built in).

```swift
// StuntGroup: keep kindRaw but widen its domain to SkillCategory.rawValue.
var categoryRaw: String = SkillCategory.stunts.rawValue   // migrated from kindRaw
```

### Attempt gains driver attribution
```swift
// Attempt:
var driverIDs: [String] = []   // United driver keys that broke this rep
                               // (empty = clean, or base-only bucket). Additive.
```
- `outcomeRaw` is still set on every rep (base severity) → all existing stats
  keep working.
- On a miss, the logged drivers are stored for the breakdown.

### Source: where the taxonomy comes from
The drivers are **not** in CheerRulesKit yet — they're hardcoded in CheerCenter.
Plan:
1. Add `ExecutionDriver` (keyed by `SkillCategory`, with `key`, `name`,
   `maxDeduction`) to **CheerRulesKit** — its correct home, beside
   `SkillCategory`/`PerformanceStatus`. CheerCenter can later read from it.
2. HitRate depends on CheerRulesKit via a **local package path** in
   `project.yml` (`packages: CheerRulesKit: { path: ../CheerRulesKit }`) — no
   GitHub round-trip during dev. iOS 16+ target is compatible.

This is the single-source-of-truth path Ian delegated.

### Logging UI (LogView, Pad)
```
Full Up  ·  Standing Tumbling
 [   CLEAN   ]                                 ← maps to Hit (green well)
 [ Approach ][ Body Control ][ Landings ][ Synch ]  ← multi-select; each = a
                                                       driver that broke
 (pick a base severity for the miss, or default to Bobble)
```
- Reuses engraved-well style. Clean = the one green well.
- A miss: tap the severity (or default), then tap any drivers that broke.
- Grid layout stays **base-4 only** (variable driver columns can't share one
  header row) — driver skills are Pad-only, mirroring the mixed-kind rule.
- Watch: driver skills fall back to base-4 buttons on the wrist for v1 (4-slot
  payload). Flag in `WatchRosterSnapshot`.

### Editor (GroupsEditorView)
- Each bucket row: a `SkillCategory` picker (replaces the stunt/tumbling menu).
- Read-only preview of that category's drivers (built-in; no authoring in v1).
- Changing a repped skill's category warns (historic `driverIDs` keep their
  display labels; don't delete).

### Stats
- Rate / trend / streak / cards / tournament / watch: **unchanged** (ride
  `outcomeRaw`).
- New `driverBreakdown(group:, timeframe:)`: count `driverIDs` over misses →
  "what's breaking" ranked list. New Home card (only when the scoped roster has
  a driver-category skill) + per-skill stat card breakdown.
- Deduction-weighted "execution score" = sum of mapped deductions — **deferred**;
  data is captured so it's a later add.

---

## Build plan

**Phase 0 — kit:** add `ExecutionDriver` to CheerRulesKit; wire HitRate's
`project.yml` to the local package; `xcodegen generate`; confirm it builds.

**Phase 1 — containers (small):** `Team.itemNoun` + `noun(for:)`; editor
"Folders" relabel + noun control; route bucket-noun reads through the folder.

**Phase 2 — skill category:** migrate `kindRaw`→`categoryRaw` (`SkillCategory`);
editor category picker + driver preview; aggregate-kind wording reads category.

**Phase 3 — driver logging:** `Attempt.driverIDs`; LogView Pad Clean+drivers
layout; commit writes `outcomeRaw` + `driverIDs`; Grid stays base-4.

**Phase 4 — driver stats:** `StatsEngine.driverBreakdown`; Home "What's breaking"
card; per-skill breakdown.

**Phase 5 — regression sweep** (per CLAUDE.md): build clean; fragile-area grep
(`RenameField` intact, base `Outcome` order untouched, `OutcomeNames` reads
preserved); smoke checklist (log base-4 skill, driver skill, switch folders,
rename mid-data, watch sync of a base skill, Catalyst run for any watch/logic
not trustworthy on the iOS sim).

## Explicitly NOT doing (v1)
- No nested folders / athlete-holds-skills hierarchy.
- No variable base-outcome count; base 4 stay locked.
- No per-skill custom driver authoring (United sets are built in).
- No watch UI for driver skills (base-4 fallback on the wrist).
- No deduction-weighted score yet (data captured for the fast-follow).
