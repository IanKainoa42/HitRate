# HitRate — Product Brief

## 1. What it does

HitRate is a one-tap stunt-outcome counter for cheerleading that turns reps into a performance dashboard and shareable trading cards. During practice you start a session, pick the skill or stunt group you're working, and hammer one of four big outcome buttons per rep — Hit / Bobble / Building fall / Major fall (or, for tumbling skills, Stuck / Stepped out / Touched down / Major fall) — with haptics and instant undo. From those taps the app builds a "court at night" dashboard: an animated hit-rate number with a distribution bar, a trend line across recent sessions, a skills/groups leaderboard that flips to an outcome heatmap, auto-written takeaways, and a "session tape" of every rep in the latest practice with automatic rough-patch detection. It then converts your numbers into a swipeable deck of holographic, Pokémon-style "Stunt Cards" — flat stat cards plus unlockable milestone cards — sized to save or post to Instagram. Everything is local to the phone (SwiftData), iPhone-only, iOS 17+.

## 2. Target user

The headline user is the **cheer athlete tracking their own stunting** — the app defaults to athlete mode, puts the athlete's name on the cards, uses a "MY HIT RATE" / "ALL SKILLS" voice, and lets the user build their own skill list (lib, stretch, full up, rewind, toss hands, plus tumbling skills like back handspring, tuck, layout, full). This is the **athlete-first pivot**: the original design handoff (codenamed "Ckil") was built coach-shaped for a specific program (Cheer Force San Diego — "FULL FLOOR," group leaderboards, program/team header), and the shipped app inverts that default to the individual athlete.

**Coach mode** is the second register, switchable in onboarding or the editor. It reproduces the handoff: a coach tracks **multiple stunt groups across the floor**, the dashboard reads "FLOOR HIT RATE" / "FULL FLOOR," takeaways say "led the floor" and "spot it next," and the identity becomes a program + team name. Coach mode is all-stunt; athlete mode is the only place tumbling skills appear.

Positioning skews **allstar / competitive gym** (stunt-group vocabulary, "your gym's language," the CFSD lineage) but the framing is gym-agnostic and works for school/rec too. Nothing is pre-seeded in either mode — every athlete and every coach creates their own buckets at first launch.

## 3. Feature inventory by job-to-be-done

**Logging the rep (the counter)** — `Views/Log/LogView.swift`
- Full-screen practice session entered from a floating "Start practice" pill; one session active at a time.
- Four large outcome buttons in a 2×2 grid with full-surface tap targets, per-rep medium-impact haptics, and per-outcome sounds.
- Horizontal skill/group picker to switch which bucket each rep lands in.
- Live in-session rep count and hit-rate readout in the header.
- One-tap **Undo** of the last rep; a "RECENT" tape of the last 12 reps with timestamps.
- **Resume** support: a live session survives the app being killed mid-practice; the pill becomes "Resume practice · N reps."

**Dashboard / insight (Home)** — `Views/Home/*`, `Stats/StatsEngine.swift`
- Global timeframe filter (Today / This week / All-time) that rescales every number, plus a timeframe-aware delta vs. the prior baseline.
- Summary card: big animated hit-rate %, rate-band color (≥75 green / 55–74 amber / <55 red), distribution stacked bar, and a 2-column outcome legend with counts and percentages.
- Trend line chart of hit rate across recent sessions (appears after two sessions), with an emphasized "you are here" last point.
- Skills/Groups card: ranked leaderboard (rate-sorted, #1 in gold, per-row mini bars and deltas) that toggles in place to an **outcome heatmap** (intensity = misses vs. column max).
- **Auto-written takeaways**: three plain-English story sentences naming the best bucket, the worst-falls bucket, and the top miss ("most fixable error").
- **Session tape** of the latest practice: one bar per rep by outcome, with an automatically detected **rough-patch** bracket (worst sliding window of 7 reps with ≥4 misses) and an interpolated timestamp.

**Sharing / motivation (Stunt Cards)** — `Views/Share/*`, `Stats/Milestones.swift`
- Swipeable carousel of trading-card-proportioned (290×430) holographic cards: flat stat cards (team/season card + one per skill/group with data) up front, then milestone cards.
- **Unlockable milestone deck** earned from lifetime history: volume (First Ten → Century Club → Grinder → Four Digits), hit streaks (Hot Hand, Untouchable), session quality (Dialed In, Perfect Practice), per-skill mastery, and "DUBIOUS HONOR" cards for the falls (Gravity Check, Cold Streak, Demolition Day). Locked milestones show as progress teasers ("412 / 500 reps").
- Share actions per card: Share to Instagram (saves the PNG, then deep-links into the app), Save image to Photos, Copy image to clipboard; earned milestones also offer "Save cheer puck" (a round transparent collectible sticker render).
- All renders go through ImageRenderer at 3× with foil animation frozen for deterministic output.

**Data ownership** — `Utilities/CSVExport.swift`
- CSV export of every logged attempt (timestamp, session start, skill/group, outcome) via the system share sheet.
- All data is on-device only (SwiftData) — no accounts, no cloud, no tracking.

## 4. Top 3 differentiators

1. **The milestone Stunt Card deck — rarity is achievement difficulty, not score.** Generic counters give you a number; HitRate turns lifetime history into a collectible deck of holographic cards. The card's rarity tier (COMMON → RARE → HOLO → LEGENDARY, with animated foil sweep + sheen reserved for earned holo/legendary) is set by **how hard the milestone is to earn** — 1,000 logged reps, 25 hits in a row, a perfect 15-rep session, 50+ reps at 90%+ on one skill — recomputed fresh from the attempts every time, so cards never need their own storage. It even gives the bad stats cards ("DUBIOUS HONOR": 25 falls survived, 5 misses in a row, 8 falls in one practice), which is both funny and genuinely motivating. (Note for copy: this is an explicit, locked design decision — rarity is **not** derived from hit rate; that older rate-based model was retired. See do-not-promise list.)

2. **Auto-written, gym-literate takeaways + rough-patch detection.** Instead of leaving the user to read a chart, the app writes the story for them — "[Skill] led the way at 84% — cleanest skill of the week," "[Skill] owns 6 of 11 falls — tighten it next," "Bobble is your top miss — most fixable error" — and the session tape automatically brackets the worst stretch of the practice with a timestamp. That insight-narration is well beyond what a tally app does.

3. **Renameable, kind-aware outcomes that speak the gym's language.** The four outcome buttons are renameable per skill kind (stunt vs. tumbling) so a gym's own vocabulary shows up live across the whole app — the log pad, the legends, the heatmap headers, the tape — while severity slots and colors stay fixed. Stunt skills and tumbling skills carry different default wording (Hit/Bobble/Building fall/Major fall vs. Stuck/Stepped out/Touched down/Major fall), and aggregate views automatically choose tumbling wording only when every bucket with data is tumbling. Combined with the athlete-first/coach dual-mode framing, it fits how cheerleaders actually talk.

## 5. Screenshots-worthy moments

The repo already ships a 7-shot demo set at `fastlane/screenshots/en-US/` — align marketing to these:

- **Athlete Home dashboard** (`1_athlete-dashboard.png`) — the hero: animated hit-rate number with rate-band halo, distribution bar, neon trend line with the glowing last-point beacon, ranked skills, auto-takeaways, and the session tape with the rough-patch bracket, all on the navy "court at night" backdrop with its ambient star field.
- **Log counter mid-session** (`2_log-counter.png`) — the four big color-coded outcome buttons with live counts, the skill picker, rep count + live hit % header, and the RECENT tape. Demos the "fast hands at practice" promise.
- **An athlete Stunt Card** (`3_athlete-card.png`) — a flat stat card: circular hit-rate gauge in the skill's identity color, power bar, four energy chips, flavor line.
- **A LEGENDARY milestone card** (`4_legendary-card.png`) — the showpiece: gold foil edge + sheen, ★★★, lock-free icon, the earning stat ("1,000 reps logged"), set number "00N/00N". This is the most distinctive single image the app produces.
- **Coach Home dashboard** (`5_coach-dashboard.png`) — "FLOOR HIT RATE," 7-group leaderboard / heatmap, program + team header. This is the shot the demo dataset is built for.
- **Onboarding chooser** (`6_onboarding.png`) — "Who's counting?" with the "Just me" vs "I coach a team" cards; communicates the dual-mode product instantly.
- **Team / FULL FLOOR card** (`7_team-card.png`) — the electric-blue team aggregate stat card.

**Seeding visuals:** coach mode's empty-state Home has a **"Load demo data" button** that seeds the exact handoff dataset — **74% floor rate, 171 reps, 7 groups**, with prior sessions trending to a populated curve and a built-in rough patch — ideal for the coach dashboard, heatmap, and team-card shots. Important: this demo button is **coach-mode only** (the dataset is coach-shaped). Athlete-mode shots (the default/headline experience) have no one-tap seed and must be staged by logging reps manually or via demo data created another way.

## 6. Do-not-promise list

- **Rarity is NOT based on hit rate.** Card rarity = milestone difficulty, a locked design invariant; the rate-derived tier model was deliberately retired. The **current live `description.txt` is stale** on this point ("rarity tiers from COMMON to LEGENDARY based on your hit rate") — that's a copy correction to make, not just a guardrail. New copy must describe rarity as how hard the achievement is to earn.
- **No accounts, no cloud sync, no backend.** Data lives only on the phone. Don't imply login, multi-device sync, team rosters in the cloud, or web access.
- **No share links / shareable URLs.** The handoff's "Copy link" became **"Copy image"** because no backend or URLs exist. Don't promise link sharing or public card pages.
- **Instagram "share" is save-then-open, not an API post.** It saves the card PNG to Photos and deep-links into the Instagram app if installed (otherwise just "saved to Photos"). Don't escalate to "auto-post to your story," "post directly," or a one-tap publish.
- **Foil is ambient shimmer, not interactive.** The prototype's pointer/gyro tilt does not port to touch; cards keep an ambient foil shimmer, gated off under Reduce Motion and frozen in saved/shared images. Don't promise tilt-to-shine or motion-reactive holo.
- **iPhone only — no iPad, no Android, no Mac, no Apple Watch.** `TARGETED_DEVICE_FAMILY` is iPhone; iOS 17+.
- **Offline only — nothing leaves the phone.** This is a feature to lean into ("no ads, no tracking"), but don't pair it with any claim implying remote backup or recovery if the phone is lost.
- **No live session timer.** The counter shows rep count, not elapsed practice time — don't market a stopwatch/duration feature.
- **No pre-seeded skills or rosters.** Onboarding suggestion chips create buckets but nothing ships pre-made; don't imply a built-in skill library or template teams.
- **Counter "styles" (Odometer/Flip/Pop) from the handoff don't exist as options** — there's one numeric-text animation. Don't advertise selectable counter styles.
- **Not yet on the App Store.** Pre-launch; no ratings, reviews, or "downloaded by" claims.

---

*Grounding note for the caller: two premises in the original task are stale against the repo. (1) The app DOES have an app icon — `AppIcon-1024.png`, a green "98 ring" on navy, documented in README line 78. (2) A 7-shot screenshot set already exists in `fastlane/screenshots/en-US/`. The most important finding is the rarity discrepancy in §6 — the shipped store description contradicts the code's locked rarity model and should be corrected before launch.*
