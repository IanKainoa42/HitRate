# Handoff: Ckil — Home Dashboard + Pokémon-style Share Cards

## Overview
**Ckil** is a cheer stunt-outcome tracker for **Cheer Force San Diego (CFSD)**. A coach
logs the result of every stunt attempt during practice (Hit / Bobble / Building fall /
Major fall) across the team's groups, and Ckil rolls those up into a floor performance
dashboard.

This handoff covers two pieces:

1. **The Home screen** — an analytics dashboard that is the *first* thing a coach sees
   when opening the app (not a post-session "review" screen). It shows the team's floor
   hit-rate, trend, per-group leaderboard/heatmap, takeaways, and a session timeline.
2. **The Share Cards sheet** — a swipeable set of **holographic "Stunt Cards"** (one per
   group + a team card) styled like Pokémon trading cards, built so a coach can screenshot
   one and post it to Instagram.

The single design file is a self-contained React-in-HTML prototype:
`Ckil Home.html`.

## About the Design Files
The file in this bundle is a **design reference created in HTML + inline React (Babel)** —
a working prototype that demonstrates the intended look, motion, and behavior. **It is not
production code to copy directly.** The task is to **recreate these designs in the target
codebase using its established patterns and libraries.**

> ⚠️ **Platform note:** Ckil's sibling product (FormationFlow, whose design system this
> reuses) is a **native iOS / iPadOS app (SwiftUI, iOS 17+)**. If you are implementing in
> that native codebase, treat the HTML as a visual+behavioral spec and build with SwiftUI
> (system colors, SF Pro, SF Symbols, `.ultraThinMaterial`, `Canvas`, `withAnimation`).
> If you are implementing on web, use React/Vue/etc. with your existing component library.
> Either way: **match the spec, use the codebase's idioms — don't ship the HTML.**

The prototype substitutes a few things that a real build should swap back:
- **SF Symbols → Lucide-style inline SVGs.** On native iOS use the real SF Symbols
  (mappings in the Design Tokens → Icons section below).
- **SF Pro / SF Pro Rounded → `-apple-system` / `ui-rounded` stacks.** Real on Apple
  devices; provide the actual families on web if pixel-exact rendering matters.
- **Share actions are mocked** (they fire a toast). See *Interactions → Share actions*
  for what to actually wire.

## Fidelity
**High-fidelity (hifi).** Final colors, typography, spacing, radii, and interactions are
all specified here and in the prototype. Recreate the UI pixel-accurately using the
codebase's existing libraries. The two visual registers are deliberate (see Design Tokens):
the **app UI** is light/iOS-native; the **share cards** use the **brand "court-at-night"**
register (dark navy, neon accents, Space Grotesk).

---

## Screens / Views

### 1. Home (App UI register)
Vertical scroll inside a phone frame. Fixed top region (header + timeframe filter), then a
scrolling feed of cards.

**Layout**
- Screen base: `#F2F2F7` (`--app-bg`). Content max width = phone width (design target
  **402 pt**). Feed is a single vertical `flex` column, `gap: 12`, horizontal padding `16`.
- **Fixed header** (does not scroll): `flex` row, `align-items: center`, `gap: 11`,
  padding `2px 16px 12px`.
  - **Team crest** — 40×40, `border-radius: 13`, fill
    `linear-gradient(150deg, #FF4757, #FF6B7A)`, white text "SC", `font: 800 15px`
    Space Grotesk, `box-shadow: 0 4px 14px rgba(255,71,87,.4)`.
  - **Identity block** (flex:1): eyebrow "CHEER FORCE SAN DIEGO" (`700 9px` Space Grotesk,
    `letter-spacing: .14em`, color `--app-label-2`) over title "Senior Coed"
    (`700 22px`, `letter-spacing: -.02em`, color `--app-label`).
  - **Share button** — 36×36 circle, fill `--fill` (`rgba(120,120,128,.12)`), accent share
    glyph. **Opens the Share Cards sheet.**
- **Timeframe segmented control** (fixed, below header): inset pill, bg `--fill`,
  `border-radius: 9`, padding `2`. Options **Today / This week / All-time**. Selected
  segment = white fill, `box-shadow: 0 1px 2px rgba(0,0,0,.13)`. This is the global filter —
  every number on the screen scales to it.

**Feed cards** (white `--surface`, `border-radius: 16`, `box-shadow: 0 1px 3px rgba(0,0,0,.06)`,
padding `14`). Card section labels are `700 11px`, `letter-spacing: .08em`, color
`--app-label-2`. In order:

1. **Summary card**
   - Big hit-rate number (left) using an animated **odometer/flip/pop counter** (52px,
     SF Pro Rounded `800`), colored by rate band: ≥75 green `#34C759`, 55–74 amber
     `#FF9500`, <55 red `#FF3B30`. Trailing `%`.
   - Delta chip (right): up/down arrow + signed value in green/red, with caption
     ("vs last session" etc.).
   - Row: "FLOOR HIT RATE" label + "{N} reps · {N} groups".
   - **Stacked distribution bar** (height 14, fully rounded) — segments in outcome colors,
     widths = each outcome's share of total.
   - 2-column legend: each outcome = color dot + label + count + percentage.

2. **Trend card** — "HIT RATE OVER TIME" + range note. An SVG **line chart** (area fill at
   8% accent opacity, 2.5px accent stroke, dashed gridlines, last point emphasized + value
   label).

3. **Groups card** — header label "GROUPS" + a small **Ranked / Grid** toggle.
   - **Ranked**: rows sorted by rate. Each row = rank number (gold `#FF9500` for #1) ·
     group color chip with number · group name · mini stacked bar · delta (up/down arrow +
     value) · big rate % (rate-band colored).
   - **Grid (heatmap)**: a `26px + 4×1fr` grid. Columns = the 4 outcomes (color dot + short
     code HIT/BOB/BF/MF). Cells tinted by outcome color, opacity ∝ count vs column max;
     count in mono. Legend "fewer … more misses".

4. **Takeaways card** — 3 insight rows, each = rounded icon badge (outcome-tinted) + a
   one-sentence takeaway with bolded names/numbers (best group, worst-falls group, top miss).

5. **Latest session card** — "LATEST SESSION" + time range. A **tape/timeline**: thin
   vertical bars (one per attempt) at heights/colors by outcome, with a bracket marking a
   "rough patch", timestamps, and an outcome legend.

6. **Action row** — primary blue button **"Create share cards"** (opens the Share sheet) +
   secondary **"CSV"** button.

### 2. Share Cards sheet (Brand register — "court at night")
Full-screen overlay over the phone, slides/fades in (opacity 0→1, `.32s`). Covers the whole
device frame (re-draws the dynamic island so the notch persists).

**Layout** (flex column, `padding-top: 54`):
- **Backdrop**: radial navy gradient `radial-gradient(120% 70% at 50% -8%, #1b2335, #0c1120 46%, #06080f)`,
  plus a faint **court grid** overlay (white lines ~5% opacity, 30px cells, radially masked)
  and two color glows (coral top-left, electric bottom-right).
- **Header row**: eyebrow "SHARE" + title "Stunt Cards" (Space Grotesk `700 21px`) on the
  left; a 34×34 close (✕) button on the right.
- **Card rail** (flex:1, centered): horizontal **scroll-snap** carousel.
  `overflow-x: auto`, `scroll-snap-type: x mandatory`, `gap: 18`, `padding: 0 56px`
  (so each card centers with neighbors peeking). **Must set `width: 100%` + `box-sizing:
  border-box` on the rail** or it sizes to content and won't scroll. Each slide:
  `scroll-snap-align: center`. **One card per group + one team card.**
- **Dots indicator**: active dot widens to 18px and takes the active card's color.
- **Action buttons**: primary **"Share to Instagram"** (Instagram brand gradient
  `linear-gradient(95deg, #515BD4, #8134AF 28%, #DD2A7B 60%, #F58529)`), then a row of
  **"Save image"** + **"Copy link"** (glass outline buttons). A toast confirms each.

#### The Stunt Card (the hero component)
A trading-card-proportioned frame, **290 × 430 px** (≈ 5:7), with a 3D foil tilt on
pointer-move.

Structure (outer → inner):
- **`.holo-shell`** — `perspective: 900px`, 290×430.
- **`.holo-card`** — `transform-style: preserve-3d`; on hover it rotates
  `rotateX((0.5−y)*15deg) rotateY((x−0.5)*15deg)` where x/y are normalized cursor coords.
  Resets to flat on leave. (Guard: skip on `pointerType === 'touch'` so it doesn't fight
  vertical scroll.)
- **`.holo-frame`** — the metallic **border** (`padding: 8`), filled with a per-rarity
  gradient and animated (`background-size: 300%`, `@keyframes foilEdge` shifts position over
  7s). `box-shadow: 0 22px 60px rgba(0,0,0,.55)`.
- **`.holo-inner`** — `border-radius: 13`, dark fill
  `linear-gradient(160deg, #141a2b, #0d1322 55%, #0a0f1e)`, plus a faint masked court grid.
  Card content lives here (flex column):
  - **Delta stamp** (abs top-right): rounded pill, green `rgba(81,207,102,…)` if ≥0 else
    coral `rgba(255,71,87,…)`, "▲/▼ N".
  - **Header**: group color chip (30×30, glowing) + kicker ("FULL FLOOR" or "GROUP N",
    `700 9px` Space Grotesk `.16em`) over the card name (`700 19px`). Right padding `52` to
    clear the delta stamp.
  - **Gauge**: SVG circular progress (`r=44`, 9px stroke, rounded cap, `feGaussianBlur` glow),
    stroked in the **card's identity color**; center shows the rate number (`800 35px` Space
    Grotesk) over "HIT RATE". A radial color-glow disc sits behind it. Rendered ~116px.
  - **Power bar**: 7px stacked outcome distribution.
  - **Energy chips**: 4 equal chips (one per outcome) — big count (`800 16px`) over short
    code (HIT/BOB/BF/MF), tinted `outcomeColor + 1a` bg / `+40` border.
  - **Rarity tag**: small pill (`700 8px` `.14em`), colored by tier (see below).
  - **Flavor**: one italic line of "scouting" copy (tier-specific).
  - **Footer** (top hairline): left = "CFSD" mark over "{date} · {season}"; right =
    **rarity stars** (★ filled per tier) over the **set number** "001/008".
- **Foil overlays** (above content, pointer-events none):
  - `.holo-foil` — diagonal sheen, `mix-blend-mode: color-dodge`, opacity scales with cursor
    proximity (`--foil`), gradient position tracks cursor (`--mx`/`--my`). Holo tier uses a
    `conic-gradient` rainbow; legendary uses a warm gold sweep.
  - `.holo-glare` — radial white highlight at cursor, `mix-blend-mode: screen`.
  - `.holo-sparkle` — fine dotted texture, `mix-blend-mode: overlay`, masked to a diagonal band.

**Rarity tiers** (derived from the card's hit-rate):

| Rate | Tier | Stars | Foil / edge | Tag color | Flavor |
|---|---|---|---|---|---|
| ≥ 90 | LEGENDARY | ★★★ | warm **gold** sweep | `#FFD43B` | "Untouchable. Cleanest group on the floor." |
| 78–89 | HOLO RARE | ★★ | **conic rainbow** | `#00D4FF` | "Locked in — hits land with room to spare." |
| 60–77 | RARE | ★ | steel blue | `#5AC8FA` | "Solid base — a few bobbles to tighten." |
| < 60 | COMMON | — | ember/coral | `#FF6B7A` | "Work in progress — spot the falls." |

The **team card** ("FULL FLOOR") uses identity color electric `#00D4FF`; **group cards** use
the formation rainbow color for that group index.

---

## Interactions & Behavior
- **Timeframe filter** (Today / This week / All-time): re-derives every number on Home
  (counts scale by a per-timeframe factor; trend series and delta swap). Drives an animated
  re-count on the big number (odometer reels / flip / pop).
- **Groups Ranked⇄Grid** toggle: swaps the leaderboard for the heatmap in place.
- **Open Share sheet**: from the header share icon **or** the "Create share cards" button.
- **Card carousel**: native horizontal scroll-snap; active index = `round(scrollLeft /
  (cardWidth + gap))` on scroll → updates dots. Cards peek on both sides.
- **Foil tilt**: pointer-move over a card tilts it in 3D and intensifies the foil/glare at the
  cursor; resets on leave. Ambient `foilEdge` shimmer runs continuously (good for touch).
- **Share actions** (currently mocked with a toast — **implement for real**):
  - *Share to Instagram* / *Save image*: render the centered card to an image and hand it to
    the platform share sheet / save to Photos. On native iOS, render the card view to a
    `UIImage` (e.g. `ImageRenderer`) and present `UIActivityViewController`; the recommended
    flow is **save the card image, then deep-link to Instagram** for a Story/Feed post.
    On web, rasterize the card node (e.g. canvas/`html-to-image`) and use the Web Share API
    with the file.
  - *Copy link*: copy a shareable URL for the card/session.
- **Motion**: respect Reduce Motion — disable the `foilEdge` animation and the counter
  reels (fall back to static values). Counters and bars animate with `cubic-bezier(.2,.8,.25,1)`.

## State Management
- `timeframe`: `'today' | 'week' | 'all'` — global Home filter.
- `groupView`: `'Ranked' | 'Grid'`.
- `counterStyle`: `'Odometer' | 'Flip' | 'Pop'` (display preference for the big number).
- `accent`: app accent hex (defaults to system blue `#007AFF`).
- `shareOpen`: boolean — Share sheet visibility.
- `activeCard`: index of the centered card in the carousel (derived from scroll).
- **Data**: a session/roll dataset of per-group outcome counts. Derived values needed:
  per-group total, hit-rate, rank, delta-vs-previous; team totals; top miss; worst-falls
  group; best group; trend series per timeframe. (The prototype computes all of this from a
  single mock `BASE` array in `buildData(timeframe)` — mirror that shape from your real data
  source.)

## Design Tokens

### Two registers
- **App UI** (Home): iOS light. Base `#F2F2F7`, surfaces white, single accent **system blue
  `#007AFF`**. SF Pro / SF Pro Rounded / SF Mono.
- **Brand** (Share cards): navy "court at night". Space Grotesk display + Inter body.

### Colors
| Token | Hex | Use |
|---|---|---|
| `--app-bg` | `#F2F2F7` | Home screen base |
| `--surface` | `#FFFFFF` | Cards |
| `--app-label` | `#000000` | Primary text |
| `--app-label-2` | `rgba(60,60,67,.6)` | Secondary text |
| `--app-label-3` | `rgba(60,60,67,.3)` | Tertiary / disclosure |
| `--sep` | `rgba(60,60,67,.16)` | Hairlines |
| `--fill` | `rgba(120,120,128,.12)` | Inset controls |
| accent | `#007AFF` | App accent (links, primary button, FAB) |
| success | `#34C759` | Hit / good / positive delta |
| warning | `#FF9500` | Building-fall / rank #1 / mid band |
| destructive | `#FF3B30` | Major fall / negative |
| bobble | `#FFCC00` | Bobble outcome |
| **Group rainbow** | `#007AFF #34C759 #FF9500 #AF52DE #FF2D55 #5AC8FA #FFCC00` | per-group identity color (cycled) |
| `--navy` | `#0A0F1E` | Brand canvas |
| `--coral` | `#FF4757` | Brand energy / crest |
| `--electric` | `#00D4FF` | Brand precision / team card |
| `--gold` | `#FFD43B` | Legendary / timing |
| `--brand-green` | `#51CF66` | Positive delta on cards |
| brand grid line | `rgba(255,255,255,.07)` | court-grid overlay |

**Outcomes** (the core domain enum): `Hit` (green `#34C759`, *isHit*), `Bobble`
(`#FFCC00`), `Building fall` (`#FF9500`), `Major fall` (`#FF3B30`). Short codes: HIT / BOB /
BF / MF.

**Hit-rate band coloring**: ≥75 green · 55–74 amber · <55 red.

### Typography
- **App**: SF Pro system stack. Large title 34/700, Title 22/700, Headline 17/600,
  Body 17/400, Caption 12. **SF Pro Rounded** for the big stat numbers; **SF Mono** for
  counts/coords. Section labels: `700 11px`, `letter-spacing .08em`, uppercase.
- **Brand (cards)**: **Space Grotesk** display (400–700; uppercase eyebrows at `.12–.18em`),
  **Inter** body. Loaded from Google Fonts.

### Spacing & radii
- Spacing rhythm: 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40.
- Radii: control 6–9 · card 14–16 · energy chip 9 · card inner 13 · card frame 20 ·
  sheet/overlay 22 · phone frame 48.
- Shadows: card `0 1px 3px rgba(0,0,0,.06)`; floating `0 8px 24px rgba(0,0,0,.16)`; card
  frame `0 22px 60px rgba(0,0,0,.55)`. Brand art uses **glow** (blurred same-color halo)
  rather than hard shadows.

### Icons (SF Symbols → Lucide substitute in the prototype)
On native iOS use the real SF Symbols. Mappings used here:
`square.and.arrow.up` (share) · `arrow.down.to.line` / download (CSV, save) ·
`chevron.left/right` · `arrow.up`/`arrow.down` (deltas) · `trophy` ·
`exclamationmark.triangle.fill` (alert) · `flame` · `link` (copy) · `xmark` (close) ·
`star.fill` (rarity). The Instagram glyph on the share button is a custom rounded-square +
ring SVG.

## Assets
- **No bitmap assets are required.** All iconography is SF Symbols (native) or inline SVG
  (web). The team crest is a CSS gradient tile with "SC" text. The gauge, charts, tape,
  heatmap, and foil are all drawn in SVG/CSS.
- Fonts: **Space Grotesk** + **Inter** via Google Fonts (cards). App text uses the system
  font stack.
- If your codebase has a brand/app icon system, use it instead of the CSS crest.

## Files
- `Ckil Home.html` — the complete prototype. Inline React (Babel) split into labeled blocks:
  - `ios-frame.jsx` — phone bezel/status bar (starter scaffold; replace with your real frame
    or none on native).
  - `tweaks-panel.jsx` — in-prototype tweak controls (design-tool scaffold; **not part of the
    product** — ignore for the build).
  - `ckil-review-core.jsx` — animated number counters, stacked bar, icons, and the mock
    dataset + `buildData(timeframe)` derivations. **This is the data-shape reference.**
  - `ckil-share-cards.jsx` — the Stunt Cards: `rarityOf(rate)`, the SVG `Gauge`, `Stars`,
    `HoloCard` (foil tilt), and `ShareCardSheet` (carousel + actions). **This is the
    card-spec reference.**
  - `ckil-review-app.jsx` — the Home screen composition (header, timeframe, all feed cards,
    and wiring to open the Share sheet).

> The `tweaks-panel` and `ios-frame` blocks are prototyping scaffolds, not product code —
> they only exist to present the design. Build from `ckil-review-app`, `ckil-review-core`,
> and `ckil-share-cards`.

## Screenshots
In `screenshots/` (the phone bezel is the prototype frame — not part of the product):
- `01-home.png` — Home dashboard (header, Today/Week/All-time filter, Summary, Trend,
  Groups ranked).
- `02-share-team.png` — Share sheet, **team card** ("FULL FLOOR", RARE tier, electric gauge),
  with neighbor cards peeking and the share actions.
- `03-share-legendary.png` — Share sheet, **legendary card** (Group 1, 92%) showing the gold
  holo edge, LEGENDARY tag, ★★★, and flavor line.
