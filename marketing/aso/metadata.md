# HitRate — App Store Metadata (ASO)

> **STATUS: v2 DRAFTS — DO NOT APPLY YET.** Ian chose cheer-first for v1
> (2026-06-06, see docs/roadmap.md §0). v1 ships the existing cheer metadata
> (rarity line corrected in place). Apply this general-positioning metadata
> only with the v2 product pass (sport-neutral onboarding, multi-sport
> screenshots, Skill Cards rename).

*Positioning: general-purpose skill/trick outcome tracker. Cheer = launch beachhead, skate = growth wedge. Pivot directive 2026-06-06.*

---

## 1. Name (limit 30)

**OPTION 1 (recommended) — `HitRate: Trick & Stunt Tracker`  (30/30)**
Both "trick tracker" and "stunt tracker" are documented-winnable terms (general §3 + cheer §2). Puts two on-intent phrases in the highest-weight field instead of the diluted "skill tracker." "Stunt" also serves the cheer beachhead and frees the word from the keyword field.

**OPTION 2 — `HitRate: Trick Tracker`  (22/30)**
Tightest possible anchor on research's #1 general term, "trick tracker," and deliberately keeps the diluted "skill tracker" pattern out of the highest-weight field. Leaves 8 chars unused — fine, because the only words worth adding ("skill") are the ones research says not to anchor on.

> On the anti-"skill tracker" caution: words in the name still rank, so "skill" wouldn't be wasted — but it competes in a pool diluted by habit/HR/10,000-hours apps for weak marginal return. Both options spend the high-weight name slots on winnable terms instead. Current name "HitRate: Skill Tracker" (22) anchors on exactly the diluted term and should be retired.

---

## 2. Subtitle (limit 30)

**OPTION 1 (paired with Name 1) — `Landed, sketchy, bail or slam`  (29/30)**
Names the 4-level severity ladder (the core differentiator) and plants "landed" — research's #2 winnable general term — in the high-weight subtitle field. Sport-neutral; reads to skate/general.

**OPTION 2 (paired with Name 2) — `Log every rep. Any skill.`  (25/30)**
States the one-tap promise plus the "any skill / any vertical" pivot in five words. "Any skill" carries the generalization the name leaves out.

> Current subtitle "Count every hit, bobble, fall" (29) is cheer-only ladder wording — replaced.

---

## 3. Keywords (limit 100, comma-separated, no spaces, no name/subtitle words, no trademarks)

**OPTION 1 field (pairs with Name 1 + Subtitle 1)  — 95/100**
```
cheer,counter,skate,gymnastics,climbing,parkour,tumbling,reps,practice,progress,stats,coach,bmx
```
Excludes words already in Name 1 (trick, stunt, tracker) and Subtitle 1 (landed, sketchy, bail, slam, or) and the brand (hit, rate). Covers cheer ("cheer counter," "stunt tracker" via name), skate/board sports (skate, bmx), gym/climb/parkour verticals, and the winnable long-tail "progress" ("trick progress" / "progress tracker").

**OPTION 2 field (pairs with Name 2 + Subtitle 2)  — 97/100**
```
cheer,stunt,counter,landed,skate,gymnastics,climbing,parkour,tumbling,bmx,practice,progress,stats
```
Excludes Name 2 words (trick, tracker), Subtitle 2 words (log, every, rep, any, skill), and brand. Since Subtitle 2 doesn't carry "landed," this field is its only home — keyword "landed" + name "tracker"/"counter" forms the winnable "landed tracker"/"landed counter." "stunt" lives here because Name 2 doesn't include it. Used singular-friendly forms; "coach" dropped to fit the higher-value "progress."

---

## 4. Promotional text (limit 170)

**`Land it or bail it, log it in one tap — skate, cheer, climb, gym, any skill. Watch your rate climb, then turn it into a holographic card. Offline. No accounts.`  (159/170)**

Generalizes the old cheer-only promo ("Log hits, bobbles, and falls…"). Leads with the universal land/bail action, names four verticals, and keeps the card + offline hooks. Avoids any auto-post/share-link claim.

---

## 5. Description (limit 4000) — 2419/4000

First 3 lines (above the fold) sell the general concept and list the verticals before "...more."

```
Land it or bail it — log every attempt in one tap. Skate, cheer, climbing, gymnastics, parkour: if you can attempt it, you can track it.

HitRate turns reps into a performance dashboard and a deck of holographic cards. Pick the trick, tap once per try, and HitRate sorts each attempt into a four-level ladder — clean, a little sketchy, a small bail, or a full slam — building your hit rate as you go.

YOUR TRICKS, YOUR WORDS
Nothing comes pre-loaded. Build your own list — kickflip, back handspring, full up, a V6 problem, a kong vault — whatever you're working. Rename the four outcome buttons to match how you actually talk: Landed / Sketchy / Bail / Slam, or Hit / Bobble / Building fall / Major fall. The severity ladder stays fixed; the words are yours.

FOR ATHLETES
Track the skills you're chasing and watch your rate climb session over session. See your cleanest skill, your roughest one, and the single mistake that's most worth fixing — written out in plain English, no chart-reading required.

FOR COACHES & SPECTATORS
Coaching a group or just watching from the stands? Switch modes and log someone else's attempts as fast as they throw them. A parent in the bleachers, a coach across the floor — one tap per rep, no setup.

THE DASHBOARD
• Hit rate at a glance — today, this week, or all-time
• Trend line across your recent sessions
• Skills ranked by rate, with movement vs last session
• A heatmap of where the misses pile up
• Auto-written takeaways: what led the way, what to tighten next
• Session tape: every rep of your latest practice on one strip, with rough patches flagged automatically

THE CARD DECK
Turn your numbers into holographic, trading-card-style collectibles with an ambient foil shimmer. Stat cards up front, then a deck of unlockable milestones — and rarity is set by how hard the achievement is to earn, not by your hit rate. Grind 1,000 reps, stack 25 clean in a row, or nail a flawless session to pull a LEGENDARY. There are DUBIOUS HONOR cards too, for the falls you walked away from. Save a card to Photos, copy it, or open it in Instagram.

BUILT FOR THE SESSION
• One-tap logging with big targets — made for fast hands at the park or on the floor
• Instant undo for mis-taps
• Rename every outcome to your own language
• CSV export of every attempt you've logged
• Works completely offline — your data never leaves your phone

No accounts. No ads. No tracking. Just counts.
```

---

## 6. What's-new template (reusable skeleton)

```
What's new in this version:
• [New: feature or sport vertical added]
• [Improved: what got faster or clearer]
• [Fixed: bug squashed]

Log every rep, any skill, fully offline. No accounts, no ads, no tracking.
```
*(Closing line is evergreen — reinforces positioning + privacy on every release. Swap the three bullets per version.)*

---

## 7. Flags

**Copy bug FIXED in this rewrite (not just a guardrail):** the live `description.txt` said rarity tiers are "based on your hit rate" — wrong per the locked design invariant. New description states rarity "is set by how hard the achievement is to earn, **not by your hit rate**." This is the single most important correction in the pass.

**Do-not-promise compliance — verified clean:**
- No Apple Watch, accounts, cloud, or sync claims anywhere.
- No share links / URLs — sharing copy is "Save to Photos, copy it, or open it in Instagram" (save-then-open, never "auto-post"/"post to story").
- Foil described as "ambient foil shimmer" only — no tilt/gyro/motion-reactive language.
- No iPad/Android/Mac, no session timer/stopwatch, no pre-seeded libraries ("Nothing comes pre-loaded").
- DUBIOUS HONOR cards and CSV export included; offline/no-ads/no-tracking leaned into without any backup/recovery claim.

**Watch this word (low risk, noted):** promo + description use the idiom "watch your rate climb" / "watching from the stands." These are the verb, not the device. Kept because they read naturally; flagging in case legal/ASC prefers zero "watch" tokens given Apple Watch is a roadmap-only feature.

**Keyword char-math:**
- OPT1: 95/100. Excludes name words (trick, stunt, tracker), subtitle words (landed, sketchy, bail, slam, or), brand (hit, rate). 5 chars slack.
- OPT2: 97/100. Excludes name words (trick, tracker), subtitle words (log, every, rep, any, skill), brand (hit, rate). 3 chars slack.
- Stemming checked: no keyword stems collide with its paired name/subtitle (e.g., OPT1 omits "landed" because the subtitle carries it; OPT2 keeps "landed" because its subtitle doesn't).
- No competitor trademarks used (avoided "Cheer Trainer," "Chalk," "KAYA," "Ollee," etc.); only generic category words.

**Recommendation:** ship **Option 1** (name + subtitle + keyword field) — two winnable phrases in the name, the ladder + "landed" in the subtitle, and the broadest winnable keyword spread. Option 2 is the fallback if a tighter, skate-first name is preferred.
