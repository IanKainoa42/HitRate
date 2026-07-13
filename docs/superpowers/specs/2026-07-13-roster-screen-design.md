# Roster screen — per-athlete overview

**Date:** 2026-07-13
**Status:** Approved (design)

## Problem

For a cheer coach collecting stats, the athlete should be a first-class analytics
unit. Investigation showed most of the engine already exists:

- `CaptureView` (the subjects-as-rows logger) is now the **primary** practice
  counter and tags every `Attempt` with its `Subject`. `LogView` (Pad/Grid) is
  only used for QuickClinic drills now, which log subject-less by design.
- `StatsEngine.compute(subject:)` already fully supports a cross-cutting person
  filter — rate, trend, deltas, and the latest-session tape all honor
  `subjectMatch`.
- `HomeView` already has a person filter chip (`personFilter`/`activePerson`)
  that re-scopes the entire dashboard to one athlete.

So "pull up one athlete and see their stats" already works via the filter. Two
gaps remain:

1. **No roster-at-a-glance comparison.** The filter shows one athlete at a time.
   A coach can't see every athlete ranked by their number to triage "who's
   hitting, who needs work."
2. **Export drops the athlete.** `CSVExport` writes only date/group/outcome — the
   raw data can't answer "whose rep is this."

## Goal

A dedicated **Roster screen** that lists every subject ranked by clean-hit rate,
plus an athlete/subject column in the CSV export. Reuse the existing
`StatsEngine.compute(subject:)` — no new stats math.

## Design

### Entry point

- A new **roster button** in the Home header, alongside the existing trophy +
  editor buttons. Icon: `person.2` (athlete) — reuse the mode-appropriate glyph.
- Opens a **full-screen cover** in the training-floor register (matches
  `TrophyRoomView`: `FloorBackdrop`, inset wells, chalk text, one green accent).
- Label adapts via existing `subjectKind` (`mode == .coach ? .group : .person`):
  **"Roster"** (athletes) / **"Groups"** (coach mode).
- Button + screen hidden when the active team has **no subjects** yet
  (`subjects.isEmpty`), mirroring `showsFilterBar`'s subject gate.

### Screen layout

- Header well (title + inherited-timeframe label + close).
- A 9pt-gutter scroll of **subject rows**, each an inset `wellBackground()` well.
- Each row shows:
  - **Name** — chalk (`Subject.displayName`).
  - **Clean-hit rate %** — Barlow numeral (`Theme.barlow()`), rate-band colored
    via `Theme.rateColor` (≥75 green / 55–74 amber / <55 red). This is the triage
    signal.
  - **Rep count** + **delta arrow** (▲/▼ vs timeframe baseline) — both already on
    `FloorStats`.
  - Full row is tappable (`.contentShape(Rectangle())`).

### Ranking

- Subjects with reps in the timeframe: sorted by **clean-hit rate descending**
  (worst sink to the bottom, red).
- Subjects with **zero reps** in the current timeframe: greyed tail, "No reps
  logged" — not ranked.

### Per-athlete numbers

- One `StatsEngine.compute(sessions:groups:timeframe:subject:)` call per subject,
  scoped to the active team's `groups` and the inherited timeframe. Pure /
  recomputed each render like Milestones; fine for realistic roster sizes.
- `rate` = the clean-hit rate already used everywhere (matches the per-skill %,
  the RATE CUP, and the dashboard headline).

### Timeframe

- **Inherits Home's current `timeframe`** (passed into the screen), displayed as a
  read-only label. No separate control in v1.
- Follow-up (out of scope): the roster's own timeframe tabs for week-vs-all-time
  comparison inside the screen.

### Drill-in

- Tapping a row **dismisses the roster and sets Home's `personFilter`** to that
  subject, reusing the already-shipped per-athlete filtered dashboard. No
  duplicate detail screen.

### Export column

- Add an **athlete/subject column** to `CSVExport` — snapshot `subject?.name ?? ""`.
- Header noun adapts to mode ("athlete" / "group"), consistent with the existing
  bucket `noun`.

## Out of scope (v1)

- Per-athlete milestones / share cards.
- Roster-scoped weekly league / tournament.
- The roster screen's own timeframe tabs.
- Any change to coach-mode subject semantics beyond what the filter already does.
- Changing the logging path — subjects are already tagged by the primary
  `CaptureView` counter.

## Reused building blocks

- `StatsEngine.compute(subject:)` — per-subject stats (already built).
- `Theme.rateColor`, `Theme.barlow()`, `FloorBackdrop`, `wellBackground()` — floor
  register chrome.
- `HomeView.personFilter` / `activePerson` / `subjects` / `subjectKind` — the
  existing filter plumbing the drill-in and labels ride on.
- `CSVExport` — extend the row snapshot.
