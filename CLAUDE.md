# HitRate — agent notes

Cheer stunt-outcome tracker (counter + dashboard + share cards). SwiftUI,
iOS 17+, iPhone-only, SwiftData. Bundle id `com.ianrichardson.HitRate`.

## Project mechanics

- **xcodegen owns the project AND Info.plist.** Edit `project.yml` (the `info:`
  block holds UIAppFonts, LSApplicationQueriesSchemes, photo-library usage
  string), then `xcodegen generate`. Never edit `HitRate/Info.plist` directly.
- **Bump builds in `project.yml`** (`CURRENT_PROJECT_VERSION`), not in the
  xcodeproj — xcodegen regenerates from project.yml.
- Sim build:
  `xcodebuild -project HitRate.xcodeproj -scheme HitRate -destination 'platform=iOS Simulator,name=<sim>' build`
- No test target yet.

## Design source of truth

`docs/design-handoff/` — the original hifi handoff (HTML prototype +
screenshots + README). Pixel targets live there. Key invariants:

- **Two threshold systems — do not conflate:**
  - Rate band colors (big numbers, ranked %): ≥75 green / 55–74 amber / <55 red
    → `Theme.rateColor`.
  - Card rarity tiers: ≥90 LEGENDARY / ≥78 HOLO RARE / ≥60 RARE / <60 COMMON
    → `Rarity.of(rate:)`.
- Outcome enum order is load-bearing: hit, bobble, buildingFall, majorFall —
  `counts` arrays are indexed by `Outcome.rawValue` everywhere.
- Card set numbers (`001/00N`) are dynamic: groups with data + 1 team card.
- Two visual registers: app UI = iOS light (locked light mode); share cards =
  "court at night" navy + Space Grotesk (bundled fonts, PostScript names
  `SpaceGrotesk-Regular/Medium/Bold`).

## Architecture

- `Models/Models.swift` — SwiftData: StuntGroup, PracticeSession, Attempt.
- `Stats/StatsEngine.swift` — ALL derived numbers (rates, deltas, trend,
  rough patch, takeaways inputs). Pure function of sessions+groups+timeframe.
  Mirrors `buildData()` from the handoff prototype.
- `Views/Home/*` — dashboard cards. `Views/Log/*` — the counter.
  `Views/Share/*` — Stunt Cards sheet + HoloCardView (also rendered by
  ImageRenderer at 3x for share/save/copy).
- `Utilities/DemoData.swift` — seeds the handoff's exact BASE dataset
  (74% / 171 reps today) — used to visually diff against handoff screenshots.

## Gotchas discovered

- Session tape must be a Canvas — 171 bars in an HStack with spacing collapse
  to zero width.
- `figure.cheerleading` SF Symbol doesn't exist; use `figure.gymnastics`.
- Latest-session snapshot must skip attempt-less sessions or an ended empty
  session hides the tape card.
