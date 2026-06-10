# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Cheer stunt-outcome tracker (counter + dashboard + share cards). SwiftUI,
iOS 17+, iPhone-only, SwiftData. Bundle id `com.ianrichardson.HitRate`.

Athlete-first with a coach mode: `AppMode` (athlete/coach, AppStorage key
`appMode`) changes only language ("skill" vs "group"), identity (athlete name
vs program/team), and card kickers — both modes store buckets as `StuntGroup`.
Nothing is pre-seeded; users create their own skills/groups in onboarding or
the editor.

## Project mechanics

- **xcodegen owns the project AND Info.plist.** Edit `project.yml` (the `info:`
  block holds UIAppFonts, LSApplicationQueriesSchemes, photo-library usage
  string), then `xcodegen generate`. Never edit `HitRate/Info.plist` directly.
- **Bump builds in `project.yml`** (`CURRENT_PROJECT_VERSION`), not in the
  xcodeproj — xcodegen regenerates from project.yml.
- Build + run on simulator:
  ```sh
  xcodegen generate   # only needed after project.yml changes
  xcodebuild -project HitRate.xcodeproj -scheme HitRate \
    -destination 'platform=iOS Simulator,name=<sim>' build
  xcrun simctl install booted <path-to-HitRate.app>   # from DerivedData Build/Products
  xcrun simctl launch booted com.ianrichardson.HitRate
  ```
- No test target, no linter config.

## Design source of truth

`docs/design-handoff/` — the original hifi handoff (HTML prototype +
screenshots + README). Pixel targets live there. Intentional deviations from
the handoff (Copy link → Copy image, foil tilt → ambient shimmer, etc.) are
listed in the repo `README.md` — don't "fix" them back toward the prototype.

Key invariants:

- **Two systems that look alike — do not conflate** (both in `Theme/Theme.swift`):
  - Rate band colors (big numbers, ranked %): ≥75 green / 55–74 amber / <55 red
    → `Theme.rateColor`.
  - Card rarity = milestone **difficulty** (`Milestone.Tier` → `Rarity.of(tier:)`),
    NOT hit rate. Stat cards are deliberately flat (`Rarity.stats`: static navy
    edge, no foil, no stars; flavor text is the only rate-based remnant). The
    old rate-derived rarity (≥90/≥78/≥60) was retired with the milestone deck —
    don't reintroduce a `Rarity.of(rate:)`.
- Outcome enum order is load-bearing: hit, bobble, buildingFall, majorFall —
  `counts` arrays are indexed by `Outcome.rawValue` everywhere.
- Outcome labels are renameable per skill kind (UserDefaults keys
  `outcomeLabel0–3` for stunt, `tumblingOutcomeLabel0–3` for tumbling; blank =
  default), but slots/severity/colors are fixed and shared across kinds.
  `Outcome.label(_:)`/`short(_:)` MUST read through `OutcomeNames.shared`
  (@Observable) — never raw UserDefaults. Raw reads are invisible to SwiftUI
  and shipped stale labels on the Log pad and tape legend; the observable read
  is what re-renders views after a rename.
- `SkillKind` (stunt/tumbling, `StuntGroup.kindRaw`) changes outcome *words
  only* — never slot indexing. Aggregate views (summary legend, tape, team
  card, heatmap headers) use `FloorStats.aggregateKind`: tumbling wording only
  when every bucket with data is tumbling, stunt otherwise. Coach mode is all
  stunt.
- Card set numbers (`001/00N`) are dynamic: groups with data + 1 team card
  (`CardSpec.deck` — team card is id 0, groups follow in ranked order).
- TWO registers since 2026-06-07 (Ian's design-direction session — "inset
  bento" won; mockups in `.superpowers/brainstorm/`):
  - **App UI = "training floor"**: lifted graphite `FloorBackdrop` (gradient +
    1px diagonal hairline), every module an inset well (`wellBackground()` in
    Components.swift — inner top shadow + bottom catch-light), chalk text,
    ONE green signal accent (`Theme.accent` 0x34D26A; green only ever means
    go/hit/improving). NO glass, NO glow, NO twinkle, NO sparkles — Ian killed
    those as "toy". The only raised element on Home is the practice CTA.
    Numerals set in Barlow Condensed (bundled, PostScript
    `BarlowCondensed-SemiBold/Bold/ExtraBold`, via `Theme.barlow()`); words
    stay SF — condensed face is for numbers only or it reads as costume.
  - **Onboarding + share cards = "court at night"**: navy `CourtBackdrop`,
    coral/electric, Space Grotesk (`Theme.grotesk()`,
    `SpaceGrotesk-Regular/Medium/Bold`). Don't migrate these to graphite or
    vice versa.
  The original handoff's iOS-light app UI stays retired.

## Architecture

- `HitRateApp.swift` — entry; `RootView` shows `OnboardingView` until
  `didOnboard`, then `HomeView` as the ONLY root — the tab bar was retired
  2026-06-06 (practice is occasional; the dashboard is the app). The counter
  is `LogView(session:)` in a fullScreenCover off Home's floating practice
  pill; the pill resumes a live session or creates one (the ONLY place
  sessions are created). "End" returns to Home; an empty session is left live
  and swept in Home's cover `onDismiss` (deleting a model the cover still
  renders crashes mid-dismiss). The stale-session/orphan sweeps hang off
  RootView's root `Group` — keep them attached when touching RootView. NO
  group seeding — first launch goes through the onboarding chooser (athlete
  vs coach) where the user creates their own buckets. Installs that predate
  onboarding (have groups but no `didOnboard`) are migrated to coach mode
  silently.
- `Views/Onboarding/OnboardingView.swift` — brand-register (navy) chooser +
  identity + quick-add first skills/groups. Suggestion chips create buckets;
  they are not pre-made.
- `Models/Models.swift` — SwiftData: Team, StuntGroup, PracticeSession,
  Attempt. An "active" session is `endedAt == nil`; LogView assumes at most
  one. MULTI-TEAM (both modes): every StuntGroup belongs to a `Team`
  (`StuntGroup.team`, optional for lightweight migration; deleting a team
  cascades its roster). The active team is `@AppStorage("currentTeamID")`
  (a `Team.id` UUID string); `[Team].current(id:)` resolves it (fallback:
  first team) and `[StuntGroup].inTeam(_:)` scopes a roster. EVERY view that
  reads groups queries `allGroups` and exposes `groups = allGroups.inTeam(...)`
  so all stats/cups/milestones are team-scoped automatically (they already
  filter attempts by group membership — sessions stay global, untagged).
  The program/org identity stays shared app-wide (AppStorage `orgName`/
  `athleteName`); only the roster + its stats are per-team. RootView folds
  pre-multi-team installs into a default team on launch
  (`migrateGroupsIntoDefaultTeam`).
- `Stats/StatsEngine.swift` — ALL derived numbers (rates, deltas, trend,
  rough patch, skill-report inputs). Pure function of sessions+groups+timeframe.
  Mirrors `buildData()` from the handoff prototype. Delta baseline depends on
  timeframe: today = last prior-day session, week = previous calendar week,
  all-time = first session of the season. Rough patch = worst sliding window
  of 7 attempts with ≥4 misses. **Every number is confined to the passed
  `groups`** (via an `allowed` Set of persistentModelIDs) — trend and the
  latest-session tape filter attempts by group membership, so the stunt-only /
  tumbling-only kind filter can't leak the other kind's reps. `rate` is
  hits/total (a bobble is NOT a hit), i.e. already the *clean-hit* rate; the
  skill-report metrics (`purity` = hits/stand-ups, `upRate` = stand-ups/total)
  build on that. `SkillKindFilter` (all/stunt/tumbling) drives the athlete
  dashboard split; `FloorStats.bestSkill/worstSkill/cleanestSkill/
  mostConsistentSkill` are gated to skills with ≥`insightMinReps` reps.
- `Stats/WeeklyTournament.swift` — the built-in weekly competition + season
  ranking. Pure function of sessions+groups, ALWAYS scoped to calendar weeks
  and deliberately INDEPENDENT of the Home timeframe filter. THREE GAMES
  rotate weekly (`WeeklyGame`, derived from week-of-epoch mod 3 — pure, no
  stored rotation state): RATE CUP (best clean-hit rate, min 10 reps), GRIND
  CUP (most reps, min 1), STREAK CUP (longest clean-hit run, min 5 reps).
  Rate is the same hits/total as StatsEngine (a bobble is NOT a hit) and a
  bobble BREAKS a streak. Standings score on the live game's metric
  (`WeeklyStanding.score`), qualified-first (tiebreak: rate → reps → fewer
  falls), then provisional entrants by reps; `rank` is 1-based among
  qualified only; `delta` is the same game-metric vs last week. Last week's
  winner (under last week's game) is the `defending` title. The SEASON
  LEAGUE (`SeasonRank`) replays every COMPLETED week under its own game and
  pays placement points (`podiumPoints` 5/3/2, qualifying 1; win also counts
  a cup) — the live week never scores mid-week. `cupHistory` banks each
  COMPLETED week's champion (under its game) as a `WeeklyCup` for the trophy
  room. The league, cups, and `defending` title RESET every season: the
  replay floors at `seasonStart()` (Jun 1 rollover — cheer season ends in
  May — mirroring `seasonString`),
  so last season's points/cups don't carry over. No storage — recomputed from
  attempts every render, like Milestones. THE GHOST (`GhostEntry`, both
  modes): a synthetic entrant pacing every week at the average WINNING score
  of completed in-season weeks replayed under the live game, plus a
  deterministic wobble seeded from the week index (NEVER a live RNG — the
  engine recomputes every render; an unseeded roll would change the ghost
  mid-week). Always "qualified", zero falls (ties go to the ghost — beat it,
  don't match it), CAN take the cup/league points/defending title; each
  replayed week races the ghost it had at the time (ghost of week W only
  knows weeks before W — the first in-season week has none). Views branch on
  `isGhost`: dashed-chalk `GhostBadge` instead of the group color chip, a
  pace line instead of StackedBar, no green accent when the ghost leads.
- `Stats/Milestones.swift` — the unlockable-card engine. Pure function of
  ALL sessions+groups (lifetime — deliberately ignores the Home timeframe);
  milestones have no storage of their own, "earned" is recomputed from the
  attempts every time. Good milestones (volume/streak/session quality/skill
  mastery) + "DUBIOUS HONOR" bad ones (falls, cold streaks). Tier = difficulty.
- `Theme/Theme.swift` — every design token, rate bands, `Rarity` chrome,
  fonts, season string. No colors/fonts hardcoded in views.
- `Views/Home/*` — dashboard cards, all driven by one `StatsEngine.compute`
  call off a `timeframe` @State in HomeView. Bento layout: header well +
  custom timeframe-tabs well fixed, then a 9pt-gutter scroll of `FeedCard`
  wells; the green practice CTA is docked via `safeAreaInset` with a fade
  backstop so scroll content doesn't slide visibly through its corners.
  The dashboard is ANALYTICS ONLY — the weekly game + league live in the
  Trophy Room, deliberately SEPARATE from these stats. The dashboard empty
  branch shows the first-launch empty state, or (once the team has logged
  before, `lifetimeHasData`) a small "No reps logged …" well for a quiet
  timeframe.
  Header hosts the wordmark (HIT + green RATE), a tappable identity subline
  that is the TEAM SWITCHER (a Menu picking `currentTeamID` + "New team"),
  a trophy button (opens `TrophyRoomView`), and the skills/groups editor
  button — the only path to roster + settings outside a live practice. A
  freshly added (empty) team shows a `noRosterState` ("Add <skills/groups>")
  and hides the practice CTA until it has a roster. The editor's Teams
  section adds/renames/deletes/reorders teams and switches the active one;
  new groups attach to the active team.
  `TrophyRoomView` (full-screen cover, training-floor register) is the
  COMPETITION HUB — everything tournament/leaderboard, kept out of Home's
  analytics: the live `WeeklyTournamentCard(weekOnly: true)` (week game with
  NO Week/Season toggle — the room shows the league as its own section), the
  SEASON LEAGUE table (reuses `LeagueRow`), a CUPS WON grid of
  `WeeklyLeague.cupHistory` tiles, and an ACCOLADES shelf of earned milestone
  cards rendered via `HoloCardView(isSnapshot: true)` (court-register cards as
  objects on the graphite shelf). Read-only — sharing stays on the Stunt Cards
  sheet. In athlete mode with BOTH kinds logged (`showsKindSplit`),
  the scroll STACKS three sections — OVERALL, then STUNT, then TUMBLING — each
  introduced by a floor-level `sectionHeader` (icon + label + rep count + a
  hairline rule; NOT a well) over a `dashboardCards(_:)` block (summary / trend
  / groups / skill report). Per-kind scopes come from `kindStats(_:)`, which
  re-runs `StatsEngine.compute` confined to that kind's groups; a section with
  no reps in the current timeframe shows a small "No reps logged …" well. The
  latest-session tape + action row sit ONCE at the bottom, below every section.
  This deliberately replaced the earlier one-at-a-time kind filter — Ian wants
  stunt and tumbling visible together, not behind a toggle.
  `SkillInsightsCard` ("SKILL REPORT") ranks best/worst/cleanest/
  most-consistent skill (de-duped: one row per skill), centered on clean hits;
  it replaced the old floor-narrative Takeaways card on Home (TakeawaysCard.swift
  is retained only because `InsightRow` lives there). `Views/Log/*` — the
  counter; outcome pad buttons are engraved wells (outcome color lives in the
  bottom inner edge + caps label, count in chalk Barlow), NOT colored candy
  buttons. LogView has TWO layouts: **Pad** (pick one group from the horizontal
  scroll, then hammer the 4 outcome wells — per-skill kind labels) and **Grid**
  (`logGrid` — the whole roster as a groups×4-outcomes matrix, every cell a
  tap-to-`+1` button into the session; no group selection — tap "Bobble" on
  Group 1 and it adds a bobble to Group 1). A single header row of outcome
  labels means the Grid is offered ONLY for single-kind rosters (`gridAvailable`
  = all groups one kind); coach is always all-stunt so it always qualifies, a
  single-kind athlete also does, mixed-kind athletes get Pad only (no toggle).
  The `MiniSeg` Grid⇄Pad toggle (persisted in `practiceLayout`) shows whenever
  `gridAvailable`; `useGrid` defaults coach→Grid, athlete→Pad. Cells reuse the
  engraved-well style and `countsFor` per-session counts; column headers/cell
  a11y route outcome words through `OutcomeNames` via `o.short/label(gridKind)`.
  **Editor rename fields use `RenameField`** (local @State buffer,
  commits on blur/submit/disappear) — never bind a TextField directly through
  `OutcomeNames` (@Observable) or a SwiftData @Model, or each keystroke
  re-renders the editor mid-edit and the cursor fights the keyboard.
  `Views/Share/*` — Stunt Cards sheet, `DeckCard` (stats | milestone),
  HoloCardView, PuckView. Deck = flat stat cards, then earned milestones
  (tier desc), then locked teasers (progress desc). Locked cards disable the
  share actions; earned milestones add a "Save cheer puck" action (round
  collectible render).
- Share/save/copy renders `HoloCardView(isSnapshot: true)` through
  ImageRenderer at `scale = 3` — `isSnapshot` freezes the TimelineView foil
  animation; without it renders are nondeterministic. Foil edge/sheen animate
  only on earned holo/legendary milestones — stat cards and locked teasers are
  static by design.
- `Utilities/DemoData.swift` — seeds the handoff's exact BASE dataset
  (74% / 171 reps today, 7 groups) via a seeded RNG — used to visually diff
  against handoff screenshots. Triggered from the empty-state Home button,
  which is shown in coach mode only (the dataset is coach-shaped).

## Gotchas discovered

- Session tape must be a Canvas — 171 bars in an HStack with spacing collapse
  to zero width.
- `figure.cheerleading` SF Symbol doesn't exist; use `figure.gymnastics`.
- Latest-session snapshot must skip attempt-less sessions or an ended empty
  session hides the tape card.
