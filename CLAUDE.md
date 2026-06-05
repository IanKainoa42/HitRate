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

- **Two threshold systems — do not conflate** (both live in `Theme/Theme.swift`):
  - Rate band colors (big numbers, ranked %): ≥75 green / 55–74 amber / <55 red
    → `Theme.rateColor`.
  - Card rarity tiers: ≥90 LEGENDARY / ≥78 HOLO RARE / ≥60 RARE / <60 COMMON
    → `Rarity.of(rate:)`.
- Outcome enum order is load-bearing: hit, bobble, buildingFall, majorFall —
  `counts` arrays are indexed by `Outcome.rawValue` everywhere.
- Outcome labels are renameable (UserDefaults keys `outcomeLabel0–3`, blank =
  default), but slots/severity/colors are fixed. `Outcome.label`/`short` MUST
  read through `OutcomeNames.shared` (@Observable) — never raw UserDefaults.
  Raw reads are invisible to SwiftUI and shipped stale labels on the Log pad
  and tape legend; the observable read is what re-renders views after a rename.
- Card set numbers (`001/00N`) are dynamic: groups with data + 1 team card
  (`CardSpec.deck` — team card is id 0, groups follow in ranked order).
- Two visual registers: app UI = iOS light (locked via `.preferredColorScheme`
  in `HitRateApp`); share cards = "court at night" navy + Space Grotesk
  (bundled fonts, PostScript names `SpaceGrotesk-Regular/Medium/Bold`,
  accessed via `Theme.grotesk()`).

## Architecture

- `HitRateApp.swift` — entry; `RootView` shows `OnboardingView` until
  `didOnboard`, then a two-tab TabView (Home/Log). NO group seeding — first
  launch goes through the onboarding chooser (athlete vs coach) where the user
  creates their own buckets. Installs that predate onboarding (have groups but
  no `didOnboard`) are migrated to coach mode silently.
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
- `Theme/Theme.swift` — every design token (both registers), rate bands,
  `Rarity`, fonts, season string. No colors/fonts hardcoded in views.
- `Views/Home/*` — dashboard cards, all driven by one `StatsEngine.compute`
  call off a `timeframe` @State in HomeView. `Views/Log/*` — the counter.
  `Views/Share/*` — Stunt Cards sheet + HoloCardView.
- Share/save/copy renders `HoloCardView(isSnapshot: true)` through
  ImageRenderer at `scale = 3` — `isSnapshot` freezes the TimelineView foil
  animation; without it renders are nondeterministic.
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
