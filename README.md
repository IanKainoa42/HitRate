# HitRate

Stunt-outcome tracker for cheer athletes — with a coach mode. Log every stunt
rep at practice (Hit / Bobble / Building fall / Major fall) against the skills
you created, and HitRate rolls it up into a performance dashboard plus
Pokémon-style holographic "Stunt Cards" built for posting to Instagram.
Athletes track their own skills under their own name; coach mode tracks
multiple stunt groups under a program/team identity.

Built from the `design_handoff_ckil_home` design handoff (originally codenamed
"Ckil"). iPhone-only, SwiftUI, iOS 17+, SwiftData.

## Features

- **Onboarding** — first launch asks who's counting ("Just me" vs "I coach a
  team"); you create your own skills/groups — nothing is pre-seeded. Mode is
  switchable later in the editor.
- **Log** — the counter. Start a practice, pick a skill/group, hammer one of
  four big outcome buttons per rep. Haptics, undo, live session hit-rate,
  recent tape. Outcome names are renameable (severity order/colors fixed).
- **Home** — floor dashboard: hit-rate summary with animated counter +
  distribution bar, trend line chart, group leaderboard ⇄ heatmap, takeaways,
  latest-session tape with rough-patch detection. Global timeframe filter
  (Today / This week / All-time).
- **Stunt Cards** — a swipeable trading-card deck: flat stat cards (team +
  per-skill) up front, then **milestone cards** you earn — lifetime volume,
  hit streaks, session quality, skill mastery, plus "dubious honor" cards for
  the falls. Rarity = how hard the milestone is (COMMON → LEGENDARY, animated
  foil on the top tiers); locked milestones show as progress teasers. Share to
  Instagram / save / copy, and earned milestones save as round "cheer pucks".
- **CSV export** of every logged attempt.

## Build

```sh
xcodegen generate          # project.yml is the source of truth (incl. Info.plist keys)
xcodebuild -project HitRate.xcodeproj -scheme HitRate \
  -destination 'platform=iOS Simulator,name=<sim>' build
```

Empty-state Home (coach mode only) has a **Load demo data** button that seeds
the exact dataset from the design handoff (74% / 171 reps / 7 groups) for
visual diffing against `docs/design-handoff/screenshots/`.

## Notes / deviations from the handoff

- **Athlete-first pivot**: the handoff is coach-shaped (groups, program/team
  header, "FULL FLOOR" card). The shipped app defaults to athlete mode —
  self-created skills, athlete name on cards, "ALL SKILLS" kicker. Coach mode
  reproduces the handoff. No pre-seeded "Group N" roster in either mode.
- "Copy link" → **"Copy image"** (no backend/URLs exist; copies the card PNG).
- Pointer foil-tilt doesn't port to touch (the prototype disables it on touch
  too); cards keep the ambient foil shimmer instead, gated on Reduce Motion.
- Counter style variants (Odometer/Flip/Pop) collapse to SwiftUI
  `.contentTransition(.numericText())`.
- Card display font: bundled Space Grotesk (OFL). Inter body text substituted
  with the system font.
- **No session timer**: the prototype's live elapsed clock in the Log header
  was dropped (unnecessary at practice); the rep count is the headline there
  instead.
- **"Training floor" app register** (2026-06-07 design session): the handoff's
  iOS-light app UI and the interim navy-glass app UI are both retired. The app
  lives on a lifted graphite floor (tight diagonal hairline texture) with
  every module recessed into it as an inset well — one material, no glass, no
  glow. Single green signal accent (green only ever means go/hit/improving);
  numerals in Barlow Condensed, words in SF. Share cards + onboarding keep
  the navy "court at night" brand register.
- **Stunt vs tumbling skills** (athlete mode, not in the handoff): each skill
  has a kind that picks the outcome wording — stunt: Hit / Bobble / Building
  fall / Major fall; tumbling: Stuck / Stepped out / Touched down / Major fall.
  Both renameable per kind; severity slots and colors are shared. When an
  athlete has logged both kinds, the dashboard **stacks** three sections —
  OVERALL, then STUNT, then TUMBLING (each a floor-level divider over its own
  summary / trend / leaderboard / skill report) — so the two are visible at
  once, not behind a one-at-a-time toggle. Every section recomputes confined
  to its kind; the latest-session tape and actions sit once at the bottom.
- **Skill Report** (not in the handoff): best / worst (improve) / cleanest /
  most-consistent skill, centered on *clean* hits (no bobble) — `purity` =
  clean hits among stand-ups, `upRate` = share that stayed off the mat. Ranks
  only skills with ≥6 reps; replaced the floor-narrative Takeaways card.
- **No tab bar**: the handoff implies a Home/Log split; the shipped app makes
  the dashboard the whole app. The counter is a full-screen practice session
  entered from a floating "Start practice" pill and exited with "End" (back
  to Home). Practice is occasional — the data is the product.
- App icon: brand-register "98 ring" (`HitRate/Assets.xcassets`).
