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
- ONE visual register since 2026-06-06: the whole app lives in the brand
  "court at night" navy (locked via `.preferredColorScheme(.dark)` in
  `HitRateApp`; `CourtBackdrop` in Components.swift is the shared backdrop;
  Theme app tokens are glass-on-navy). Space Grotesk = display font (bundled,
  PostScript names `SpaceGrotesk-Regular/Medium/Bold`, via `Theme.grotesk()`).
  The original handoff's iOS-light app UI was retired deliberately — don't
  reintroduce it.

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
- `Models/Models.swift` — SwiftData: StuntGroup, PracticeSession, Attempt.
  An "active" session is `endedAt == nil`; LogView assumes at most one.
- `Stats/StatsEngine.swift` — ALL derived numbers (rates, deltas, trend,
  rough patch, takeaways inputs). Pure function of sessions+groups+timeframe.
  Mirrors `buildData()` from the handoff prototype. Delta baseline depends on
  timeframe: today = last prior-day session, week = previous calendar week,
  all-time = first session of the season. Rough patch = worst sliding window
  of 7 attempts with ≥4 misses.
- `Stats/Milestones.swift` — the unlockable-card engine. Pure function of
  ALL sessions+groups (lifetime — deliberately ignores the Home timeframe);
  milestones have no storage of their own, "earned" is recomputed from the
  attempts every time. Good milestones (volume/streak/session quality/skill
  mastery) + "DUBIOUS HONOR" bad ones (falls, cold streaks). Tier = difficulty.
- `Theme/Theme.swift` — every design token, rate bands, `Rarity` chrome,
  fonts, season string. No colors/fonts hardcoded in views.
- `Views/Home/*` — dashboard cards, all driven by one `StatsEngine.compute`
  call off a `timeframe` @State in HomeView. Glow guides the eye to the data:
  `FeedCard(glow:)` lights ONLY the hero cards (SummaryCard = rate-band color,
  TrendCard = accent + neon line/last-point halo); everything else stays flat
  glass — don't spread glow to every card. `CourtBackdrop(twinkle: true)` is
  Home-only (ambient star field, top-weighted toward the charts, Reduce
  Motion-aware) — the counter, onboarding, and share snapshot paths stay
  twinkle-free on purpose. Header also hosts the skills/groups editor button —
  the only path to roster + settings outside a live practice.
  `Views/Log/*` — the counter.
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
