# HitRate

Stunt-outcome tracker for cheer coaches. Log every stunt rep at practice
(Hit / Bobble / Building fall / Major fall) per group, and HitRate rolls it up
into a floor performance dashboard plus Pokémon-style holographic "Stunt Cards"
built for posting to Instagram.

Built from the `design_handoff_ckil_home` design handoff (originally codenamed
"Ckil"). iPhone-only, SwiftUI, iOS 17+, SwiftData.

## Features

- **Log** — the counter. Start a practice, pick a group, hammer one of four big
  outcome buttons per rep. Haptics, undo, live session hit-rate, recent tape.
- **Home** — floor dashboard: hit-rate summary with animated counter +
  distribution bar, trend line chart, group leaderboard ⇄ heatmap, takeaways,
  latest-session tape with rough-patch detection. Global timeframe filter
  (Today / This week / All-time).
- **Stunt Cards** — swipeable holographic trading cards (one per group + team
  card) with rarity tiers by hit rate (LEGENDARY ≥90 / HOLO RARE ≥78 / RARE ≥60
  / COMMON), animated foil edges, share to Instagram / save / copy as image.
- **CSV export** of every logged attempt.

## Build

```sh
xcodegen generate          # project.yml is the source of truth (incl. Info.plist keys)
xcodebuild -project HitRate.xcodeproj -scheme HitRate \
  -destination 'platform=iOS Simulator,name=<sim>' build
```

Empty-state Home has a **Load demo data** button that seeds the exact dataset
from the design handoff (74% / 171 reps / 7 groups) for visual diffing against
`docs/design-handoff/screenshots/`.

## Notes / deviations from the handoff

- "Copy link" → **"Copy image"** (no backend/URLs exist; copies the card PNG).
- Pointer foil-tilt doesn't port to touch (the prototype disables it on touch
  too); cards keep the ambient foil shimmer instead, gated on Reduce Motion.
- Counter style variants (Odometer/Flip/Pop) collapse to SwiftUI
  `.contentTransition(.numericText())`.
- Card display font: bundled Space Grotesk (OFL). Inter body text substituted
  with the system font.
- App icon TBD.
