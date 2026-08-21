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
- **Two targets, one project.yml**: `HitRate` (iOS app) embeds `HitRateWatch`
  (watchOS app); bump `CURRENT_PROJECT_VERSION` in BOTH target blocks together.
  The watch target compiles `HitRate/WatchSync/WatchPayloads.swift` directly
  into itself (shared wire format — keep that file dependency-free of iOS-only
  imports). Both targets carry the HealthKit entitlement + Health usage strings.
- **Catalyst is the verify lane for anything you can't trust on the iOS
  simulator** (`SUPPORTS_MACCATALYST: YES`) — append
  `-destination 'platform=macOS,variant=Mac Catalyst'`. WatchConnectivity and
  workout sessions can't be exercised on the iOS simulator at all (see Gotchas).
- **Shipping is fastlane, not Xcode export** (`fastlane/Fastfile`): `/usr/bin/rsync`
  is openrsync (no `-E`), so Xcode's `-exportArchive` fails ("Copy failed"). The
  lane archives normally then hand-assembles + re-signs the IPA. Build number
  lives in `project.yml` (no `increment_build_number`); `/ship` bumps it and
  re-runs `xcodegen generate`. ASC API key is a raw `.p8` via `key_filepath`
  (Ruby 4 / OpenSSL 3 breaks `key_content`).
- Test target: `HitRateTests` (sync policies, stats, milestones) — run with
  `xcodebuild … test`. No linter config.

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
    NOT hit rate. The old rate-derived rarity (≥90/≥78/≥60) stays retired —
    don't reintroduce a `Rarity.of(rate:)`.
  - **THE CARD LADDER** (2026-08-19, `Stats/CardStage.swift` + `Rarity.staged`)
    replaced the "stat cards are deliberately flat" law: a stat card's chrome
    now levels with WORK and ACHIEVEMENTS — never rate. Stage from lifetime
    reps + badges: MINTED (0 reps, dashed inner rule, "—" number) → INKED
    (number GREY under 10 reps, then `Theme.rateColor` band) → PROVEN (50+
    reps: `provenEdge`, flavor voice unlocks — under 50 it's a "warming up"
    line) → DECORATED (≥1 badge) → FOIL (a holo/legendary badge foils the
    whole card). Badges (`CardBadge`, pips above the flavor line) = highest
    volume rung (100/500/1000 on THIS card), best hit run (10/25), the
    group's mastery milestone, and cups it won (`WeeklyCup.winnerGroupID`,
    nil for SPIRIT weeks — the ghost never decorates). Team card collects
    team-wide milestones; TOUGH LOVE never decorates. Pure recompute
    (`CardStandings.compute`), no storage; a nil `CardSpec.standing` renders
    the legacy flat card (render harness). The share deck is computed with
    timeframe `.all` (cards are the season record, not the Home filter) and
    now INCLUDES zero-rep skills as minted cards. Tests: `CardStageTests`.
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
  is `CaptureView(session:)` in a fullScreenCover off Home's floating practice
  pill; the pill resumes a live session or creates one (the ONLY place
  sessions are created). "End" returns to Home; an empty session is left live
  and swept in Home's cover `onDismiss` (deleting a model the cover still
  renders crashes mid-dismiss). The stale-session/orphan sweeps hang off
  RootView's root `Group` — keep them attached when touching RootView. NO
  group seeding — first launch goes through the onboarding chooser (athlete
  vs coach) where the user creates their own buckets. Installs that predate
  onboarding (have groups but no `didOnboard`) are migrated to coach mode
  silently — UNLESS `replayingIntro` (AppStorage) is set: Manage Data →
  "Replay intro" flips `didOnboard` off to re-run the setup, and the flag
  keeps this migration from instantly re-completing it.
- `Views/Onboarding/OnboardingView.swift` — brand-register (navy) DECK-COVER
  flow (2026-08-19; replaced the chooser+identity screens): step 1 is one
  screen — name your deck (live deck-box preview; the name becomes the Team
  name), a "My team's deck / Just mine" pill pair that quietly sets `AppMode`
  (`pendingMode`, committed on advance), and ONE contextual identity field
  (athlete name / program). Step 2 is the MINT screen (focus picker +
  suggestion chips + custom field — chips mint cards, nothing pre-made).
  The account/restore step 0 and the first-rep practice preview are
  unchanged and MUST stay (restore is the only path that recovers folders).
  On an intro REPLAY, `startCounting()` reuses the existing current team
  (new cards top up the roster, numbering offset past it) — never forks a
  duplicate team; the cover pre-fills the deck name and a retitle RENAMES
  the folder; chips hide names already rostered.
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
  tumbling-only kind filter can't leak the other kind's reps. `rate` is the
  CLEAN-HIT rate (`cleanRate`: hits/total, a bobble is NOT a hit) — the plain
  "did you stick it" number, so it matches the per-skill %, the weekly RATE CUP,
  and the "Hit N · X%" breakdown. Credits 67/33 still exist but ONLY drive
  streaks via `isLandingRep` (≥50% = a landing) — they no longer weight the
  headline (the brief weighted-score headline was reverted 2026-07-11, IAN-514).
  The skill-report metrics (`purity` = hits/stand-ups, `upRate` = stand-ups/total)
  build on the same clean-hit base. `SkillKindFilter` (all/stunt/tumbling) drives the athlete
  dashboard split; `FloorStats.bestSkill/worstSkill/cleanestSkill/
  mostConsistentSkill` are gated to skills with ≥`insightMinReps` reps.
- `Stats/WeeklyTournament.swift` — the built-in weekly competition + season
  ranking. Pure function of sessions+groups, ALWAYS scoped to calendar weeks
  and deliberately INDEPENDENT of the Home timeframe filter. THREE GAMES
  rotate weekly (`WeeklyGame`, derived from week-of-epoch mod 3 — pure, no
  stored rotation state): RATE CUP (best clean-hit rate, min 10 reps), GRIND
  CUP (most reps, min 1), STREAK CUP (longest run of LANDINGS, min 5 reps).
  Rate is the credit-weighted score from StatsEngine (`weightedRate`). A STREAK
  counts LANDINGS, not clean hits: a rep with credit ≥50%
  (`OutcomeCredit.landingThreshold`, via `Attempt.isLandingRep`) keeps the run —
  so a landed-but-not-clean rep (decent/67) does NOT break it; a fall/miss/balk
  (<50%) does. Same rule drives the capture hot-streak flame. Standings score on the live game's metric
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
  modes — user-facing name is "THE SPIRIT", the cheer word; code keeps
  ghost/`isGhost` naming): a synthetic entrant pacing every week at the average WINNING score
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
- **EXECUTION drivers ("Feature B")** — an OPTIONAL, advanced, per-rep layer of
  BINARY held/lost tags. NEVER point math (the kit's `ExecutionDriver.maxDeduction`
  is deliberately ignored). Drivers come from the United `SkillCategory`
  (`CheerRulesKit.ExecutionDriver`: stunts/pyramid/standing/running tumbling = 4,
  tosses/jumps = 3); custom / "Other" types carry NONE — `StuntGroup.scoresExecution`
  gates the whole feature. Stored on `Attempt` as two additive fields
  (`executionScored: Bool`, `lostDriversRaw: String`; lightweight migration — NOT a
  UUID default, so the id-backfill gotcha doesn't apply). The NON-INFLATING rule is
  load-bearing: a rep is only counted once a coach COMMITS a read
  (`scoreExecution(lost:)`); a rep nobody opens stays `executionScored == false` and
  contributes ZERO — it is never assumed clean. So execution NEVER touches the hit
  rate / streak / cards / tournament — it's a separate breakdown only.
  `ExecutionSheet` (per-rep, opened by TAPPING a recent chip on a United-category
  skill; all drivers start HELD, tap to mark SLIPPED, Save commits) is the input;
  scored chips show a shield (green = all held, amber = something slipped).
  `StatsEngine.executionBreakdown` → `FloorStats.execution` (denominator =
  scored-reps-only, so an untracked practice can't inflate a driver to 100%);
  `ExecutionCard` renders it BELOW the analytics cards, hidden unless
  `stats.hasExecution`.
- **HOMEWORK (coach-assigned rep targets)** — `Assignment` (@Model) +
  `Stats/HomeworkEngine.swift` + `Views/Home/HomeworkCard.swift` /
  `HomeworkDetailSheet.swift` / `AssignmentEditorSheet.swift`. A coach sets a
  WEEKLY rep target on one skill for some (or all) of the roster; pro squads
  don't train together year-round, so this is how the work between practices
  gets seen. Like Milestones and the tournament it stores NO PROGRESS —
  completion is recomputed from attempts every render, so a late-syncing or
  deleted rep is always reflected. Reps are bucketed by the ATTEMPT's own
  timestamp (never its session's `startedAt`, which mis-buckets a practice
  spanning midnight) into `Calendar.current` weeks — the same boundary
  `WeeklyLeague` uses. VOLUME counts (any outcome advances the bar; clean rate
  rides alongside) and VERIFICATION IS RECEIPTS, not proof: per-day rep counts,
  last-rep time, and the self-vs-coach logger split (`Attempt.isCoachLogged`,
  passed a nil ownerUID on a solo folder so the owner's own reps don't all read
  as "coach"). `subjectIDsRaw` empty = the whole roster, including athletes
  added later; ids resolve against LIVE subjects so a trashed athlete drops off.
  The card sits in Home's scroll OUTSIDE `dashboardCards(_:)` (which renders 3×
  under the kind split) and outside the `hasData` branch (the athlete who hasn't
  started is exactly who needs the target), and ignores the timeframe filter.
  Owner-authoritative in sync: `teams/{id}/assignments` — coach writes, folder
  reads. Two sync invariants: (1) its listener is deliberately NOT in
  `requiredServerCollections`, which gates ATTEMPT pushes — adding a
  never-marked name there silently stops every rep in the app from syncing; and
  (2) assignments and groups are SIBLING listeners with no delivery order, and
  Firestore delivers a doc as `.added` exactly once per listener lifetime, so an
  assignment arriving before its skill is stored UNLINKED (`groupIDRaw`, always
  set via `Assignment.link(_:)`) and adopted later by `applyGroup`. Dropping it
  instead would lose that homework permanently on a fresh join — and would still
  pass a relaunch test, since the group is local by then.
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
  that OPENS THE EDITOR (`editorOpen`) — NOT a team switcher; switching/creating
  teams now lives at the FOLDER-LIST home (`FolderListView`, reached via the
  header back arrow / `onExit`), which is the launch root. A
  trophy button (opens `TrophyRoomView`), and the skills/groups editor
  button — a path to roster + settings outside a live practice. A
  freshly added (empty) team shows a `noRosterState` ("Add <skills/groups>")
  and hides the practice CTA until it has a roster. Team (folder) CRUD +
  switching now lives on `FolderListView` (the "NEW FOLDER" home), NOT an
  editor Teams section; new groups attach to the active team.
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
  is retained only because `InsightRow` lives there).
  `Views/Log/CaptureView.swift` is the PRIMARY logger (replaced the old
  Pad/Grid split for normal practice; opened from Home's floating practice
  pill). An attempt is subject × skill × outcome: outcomes are ALWAYS the tap
  columns, a PIN toggle (`pivot`: skill/subject) decides what's pinned at the
  top vs. what varies row-by-row (pin a skill → rows are subjects; pin a
  subject → rows are skills). Subjects/skills can be added unnamed
  (capture-first, name-later via suggestion chips or inline `RenameField`).
  **Logging is 1-TAP DIRECT AUTO-SAVE** (`logDirect` + a 3.5s undo toast) —
  the wave-staging/Submit system was retired 2026-08-11 (7e20dde,
  "Streamline capture"); nothing currently writes a non-nil `Attempt.waveID`,
  though the model/sync round-trip for it survives. `logDirect` clears the
  active team's `isDemo` flag so real usage resumes sync off a demo team —
  EVERY logging path must do the same. Cells are gesture views, not Buttons
  (a Button fires its action on release even after a hold). The custom
  "issues" pad (skill pivot only, user-created outcomes) is an immediate
  tap-to-add-one/hold-to-remove-one tally.
  `CaptureView` and `PageRunView` are the only loggers — the old
  `Views/Log/LogView.swift` (Pad / Grid layouts) went out with the Quick
  Clinic feature on 2026-08-19.
  `Views/Log/PageRunView.swift` + `Views/Log/PracticePages.swift` — the
  NINE-POCKET PAGES feature (2026-08-19): `PracticePage` (@Model, local-only,
  soft-delete, slots stored as newline-joined `StuntGroup.id` uuidStrings —
  NEVER persistentModelIDs; dangling/trashed slots drop at resolve). The
  practice pill branches: live session → resume into CaptureView; no pages →
  freeform directly (zero friction preserved); pages exist →
  `PracticeStartSheet` (freeform / run a page / build-edit pages via
  `PageBuilderView`). The pill's CONTEXT MENU ("Run or build a page") is the
  only way to create the FIRST page — a plain tap with zero pages goes
  straight to freeform by design. A page run shares Home's ONE
  fullScreenCover (`pendingPage` decides the content) and the same session
  lifecycle — `endOfPractice` sweeps, `startSession()` carries all four side
  effects (insert+save, start sound, watch wake, haptic); the delayed
  sheet→cover handoff guards against re-opened presentations. `PageRunView`
  logs DIRECT with an ARMED severity: category presets log the armed SLOT
  (0–3 legacy-aligned); custom-type skills have NO slot contract (built-in
  "Other" is [Hit, Miss]) so they resolve by CREDIT TIER instead, and a tier
  the skill lacks no-ops at 40% opacity. Page reps are UNATTRIBUTED
  (`subject: nil`) — they count in team totals but under no athlete, so the
  person filter and roster overview won't see them (known v1 gap). Undo
  pairs `SyncEngine.queueDeletion` with delete. New @Models must be added to
  BOTH `Schema([...])` lists in HitRateApp.swift.
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
- `HitRate/WatchSync/*` + `HitRateWatch/*` — the Apple Watch companion. The
  iPhone is the source of truth; the watch is a thin remote logger. `HitRateApp`
  builds a `WatchRosterSnapshot` (active team's roster, per-group counts, the
  pad's selected skill, `isPracticeLive`) and pushes it through
  `WatchSessionBridge` (a `WCSession` singleton) on every roster/session change.
  The watch (`WatchLogStore`) renders that snapshot, sends back `WatchLogRequest`
  messages, and the bridge's `logHandler` writes the Attempt into SwiftData on
  the phone. Wire format = `WatchPayloads.swift` (JSON `Codable`, the ONLY file
  shared across both targets) — every field is optional-decodable so old
  snapshots survive a schema bump. The wrist owns its OWN skill selection
  (Digital Crown scrolls + tap-to-lock; can't intercept the crown, hence the
  lock), seeded once from the phone. Launching the watch app has no public API:
  `PracticeWatchLauncher` starts an `HKWorkoutSession` via
  `HKHealthStore.startWatchApp(with:)` when practice begins — that's the only
  sanctioned foreground path — and the watch's `WatchWorkoutManager` keeps its
  own workout running (driven purely by `isPracticeLive`) so the app stays
  reachable as the wrist drops. HealthKit is touched ONLY when an installed
  paired watch exists (`isWatchAppAvailable`) so iPhone-only users never see a
  Health prompt.
- `Auth/*` — anonymous-first identity. `AuthViewModel` (env object from
  HitRateApp) owns `uid` (team ownership + rep attribution) and signs in
  anonymously on launch. `AccountView` (editor → Account section) is the
  optional "Save your account" upgrade: LINKS the anonymous user to
  Apple/Google (same uid — folders/reps/shared rosters carry over; collision
  falls back to plain sign-in) and, once saved, hosts account deletion
  (App Review 5.1.1(v)): `SyncEngine.deleteCloudFootprint` removes every
  cloud doc the rules allow (owner's teams/roster/join codes + own
  sessions/attempts; other members' reps become unreachable when the team
  doc dies), then `user.delete()` (reauth retry on stale login), then
  `resetLocalCloudLinkage` detaches local records from the dead uid so the
  next anonymous session re-adopts OWNED folders only (nil-ing a joined
  team's ownerUID would push someone else's roster as ours). NO sign-out by
  design — it would strand the user on a fresh anonymous orphan account.
- `Views/Share/InteractiveCardView.swift` — wraps `HoloCardView` in a live
  `rotation3DEffect` drag (pitch/yaw + `interactiveTilt` feeding the foil) for
  on-screen "holding" of a card; the static `isSnapshot: true` render path
  (save/share) is unaffected and stays deterministic.

## Gotchas discovered

- Adding a `var id: UUID = UUID()` property to an @Model with existing stores
  backfills EVERY pre-existing row with the SAME UUID (the default is
  evaluated once during lightweight migration, not per row). Duplicate ids
  collapse every `ForEach` keyed on Identifiable — the practice grid rendered
  one group on all rows and "logged a hit for everybody". RootView's
  `dedupeSyncIDs()` heals affected stores on launch; keep it if more synced-id
  properties are ever added.
- Session tape must be a Canvas — 171 bars in an HStack with spacing collapse
  to zero width.
- `figure.cheerleading` SF Symbol doesn't exist; use `figure.gymnastics`.
- Latest-session snapshot must skip attempt-less sessions or an ended empty
  session hides the tape card.
- Firestore rules tests (`npm run test:firestore-rules`) need a JVM the
  emulator can find. `openjdk@21` is installed but keg-only, so plain `npm run`
  fails with "Unable to locate a Java Runtime" — run it as
  `PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" npm run test:firestore-rules`.
- WatchConnectivity is force-disabled on the simulator (`WatchLogStore.session`
  returns nil under `targetEnvironment(simulator)`) — `WCSession` has an XPC/IPC
  bug on iOS 18 / watchOS 11 paired simulators that crashes in
  `-[OS_dispatch_mach_msg _setContext:]`. Watch sync therefore can only be
  verified on real paired hardware; the `--demo-roster` launch arg seeds a local
  snapshot so the watch can still be screenshotted without a live pairing.
