# HitRate — Brand Foundation

*Status: pre-launch. Positioning: general-purpose skill/trick outcome tracker, cheer-validated → skate-led. All claims checked against `marketing/research/product-brief.md` §6 do-not-promise list.*

---

## 1. Positioning statement

**Primary (general altitude):**

> For anyone grinding reps on a skill — skaters, climbers, gymnasts, cheerleaders, anyone chasing consistency — who wants to know if they're *actually* getting better and not just guessing, **HitRate** is a one-tap attempt tracker that turns every rep into a success-rate dashboard and a deck of collectible cards. Unlike tally counters (no meaning) and per-sport logbooks (locked to one taxonomy), HitRate's outcomes are graded *and* renameable, so it speaks your sport's language while computing the one number every sport shares: how often you make it.

The brand lives at general altitude. Cheer is the **go-to-market sequence**, not the positioning core — the launch beachhead (lowest CAC, founder's home turf), with skate as the growth wedge. The primary statement is written for everyone; verticals flex *down* from it, never the reverse.

**How it flexes per vertical** (same product, the renameable-outcomes feature carries the idiom in-app — the brand layer stays neutral):

*Outcome names below: cheer (Hit/Bobble/Building fall/Major fall) and tumbling (Stuck/Stepped out/Touched down/Major fall) are the app's shipped defaults; skate and climbing names are illustrative examples of the renameable feature (user-set), not built-in presets.*

| Vertical | Flexed line | Native outcome names (user sets these in-app) |
|---|---|---|
| **Cheer** (beachhead) | "Know your hit rate before competition does." | Hit / Bobble / Building fall / Major fall |
| **Skate** (growth wedge) | "Stop guessing if you've got the trick. Count the lands." | Landed / Sketchy / Bail / Slam |
| **Climbing** | "Every attempt on the project, logged." | Sent / Slipped / Off / Whip |
| **Gymnastics / tumbling** | "Every pass, every practice — the consistency, not just the meet." | Stuck / Stepped out / Touched down / Major fall |

The flex is real product behavior, not marketing spin: severity slots and colors are fixed; the *words* are the user's. That is what lets one brand cover four vernaculars without faking it.

---

## 2. One-liner (≤10 words)

**Count every attempt. Know if you're actually getting better.**

---

## 3. Elevator pitch (2 sentences)

HitRate is a one-tap counter for anyone grinding a skill: tap an outcome each rep — landed, sketchy, bail, slam (rename them to your sport) — and it builds a success-rate dashboard that tells you, in plain words, what's working and what to fix. Then it turns your numbers into holographic collectible cards you can save and share, all on-device, no account, no ads.

---

## 4. Voice / tone

Solo-founder honest. Athlete-native. Reads like a teammate who keeps the count, not a SaaS dashboard or a hype brand.

**Direct**
- **Do:** "Tap once per rep. Watch the number move." Short verbs, real outcomes, the actual metric.
- **Don't:** "Unlock data-driven performance insights to maximize your athletic potential." No engagement-funnel language.

**Athlete-native**
- **Do:** Talk in reps, attempts, and the sport's own words — "you landed 6 of 10," "tighten the bobbles." Let the renameable outcomes do the dialect.
- **Don't:** Force one sport's idiom on everyone ("hit rate on your kickflips"). A skater doesn't "hit"; a flyer doesn't "land." Neutral at the brand layer, native in-app.

**Honest**
- **Do:** Say exactly what it is and where it stops — "on your phone, nothing leaves it," "save the card, then share it." Bad-stat cards are part of the deal and we say so ("survived 25 falls").
- **Don't:** Inflate. No "auto-posts to your story," no "syncs across devices," no "AI coaching." If it doesn't ship, it doesn't get said.

---

## 5. Tagline candidates (ranked)

Tested against four readers — a skater, a flyer (cheer), a climber, a parent in the stands. The cross-vertical filter: any line built on **one** sport's outcome verb ("land," "hit," "send," "stick") fails the other three, so the winners are built from the neutral register (attempt / rep / try / make it / consistency).

1. **"Every attempt counts."**
   Double meaning (each one is logged *and* each one matters). Works verbatim for all four — a skater's attempt, a flyer's attempt, a climber's attempt, the rep a parent is watching. Neutral, short, true to the core mechanic. **Top pick.**

2. **"Count every try. See if it's working."**
   States the product literally (count) and the payoff (success-rate trend) without naming any sport's verb. Reads to a parent as plainly as to an athlete. Slightly long but maximally clear.

3. **"Are you actually getting better?"**
   The question every grinder asks and no tally counter answers. Vertical-agnostic by construction; great social/ad hook. Ranks below 1–2 only because it's a question, not a claim, so it works better as a hook than a lockup tagline.

4. **"Reps in. Rate out."**
   Tight, mechanical, athlete-shaped — the whole loop in four words. Neutral. Loses a notch because "rate" leans slightly analytical and brushes the baseball-stat connotation the name already carries (§7).

5. **"Know your number."**
   Confident and universal — every sport computes one rate. Flexes per vertical ("your hit rate," "your land rate"). Ranks last only because it's abstract on its own; strongest as a sign-off line under the logo rather than the lead tagline.

*Rejected on the cross-vertical test (kept here so we don't relitigate): "Land more, log it all" (skate-only), "Hit the routine" (cheer-only), "Send it, track it" (climb-only). All fail three of four readers.*

---

## 6. Icon + color direction

**Palette — code-verified from `HitRate/Theme/Theme.swift` (these are what the app actually renders; do not invent others):**

| Role | Hex | Token |
|---|---|---|
| Court-at-night base (app + cards) | `#0A0F1E` | `Theme.navy` / `appBG` |
| Electric blue (team/holo accent) | `#00D4FF` | `Theme.electric` |
| Gold (legendary / #1 rank) | `#FFD43B` | `Theme.gold` |
| Coral (warm brand accent) | `#FF4757` | `Theme.coral` |
| Brand green | `#51CF66` | `Theme.brandGreen` |
| iOS accent | `#007AFF` | `Theme.accent` |

**Rate-band system (semantic — owns the "are you good?" read; reuse consistently in marketing charts):**
- Green `#34C759` (≥75%) · Amber `#FF9500` (55–74%) · Red `#FF3B30` (<55%)
- Outcome colors are the same family: Hit/Landed `#34C759`, Bobble/Sketchy `#FFCC00`, Building fall/Bail `#FF9500`, Major fall/Slam `#FF3B30` — a fixed severity gradient green→red that holds regardless of what the user renames the buttons.

**Foil chrome (cards) — real edge palettes:** Legendary = warm gold sweep (`#FFB02E → #FFF3B0 → #FFD43B`); Holo = full-spectrum (`#00D4FF #9775FA #FF4D6D #FFD43B #51FF9F`). The holographic card is the most distinctive image the app makes and the social wedge — lead with it.

**Type:** Space Grotesk (bundled, the display face). Keep it as the brand wordmark font — geometric, sporty, not corporate.

**Motif options (court-at-night is the through-line; keep it across all verticals):**
- **A — Rate gauge / ring (current direction, recommended).** A circular progress ring is the universal "success rate" symbol — it reads to a skater, a climber, and a parent identically, and carries zero cheer iconography. This is exactly the "step outside the family's cheer visual language" the general pivot needs.
- **B — Tap pulse.** A single neon tap-ripple on navy — speaks to the one-tap core action, sport-neutral.
- **C — Ascending bar/trend spark.** "Getting better over time" — but reads more analytics-app than athlete, weakest of the three.

**What to avoid:** any cheer-specific iconography (megaphone, pom, bow, stunt silhouette) — it would brick the general positioning and three of four verticals. No literal sport props (skateboard, carabiner, beam) — pinning to one vertical kills the others. No light/white background — the entire product is court-at-night; a light icon breaks continuity with every screenshot and the cards.

**Verdict on the current "98 ring" icon:** The *gauge/ring motif is right and should stay* — it's sport-neutral, on-brand navy+neon, and already aligned with the general pivot (note: founder calls it the "brand-register 98 ring," so the motif has attachment equity worth keeping). **The literal "98" is the problem.** It over-pins the brand to a single high percentage, implies "be at 98%" (off-message for an honest tool that ships bad-stat cards too), and competes with the holo card as the hero image. **Recommendation: keep the neon ring on navy, drop or abstract the literal number** — either an empty/animated ring, a generic "%" mark, or a partially-filled arc that reads as "a rate" without claiming a specific one. Cheap pre-launch change, preserves the equity, removes the over-pin. (Note: a ring reads as a *rate*, which keeps it coherent with the HitRate name — see §7. Do not pair this gauge with a "Landed"-style rename, which would imply count/streak, not a rate.)

**Family cohesion — kept vs. dropped:** *Kept* — the dark, neon, premium register (FormationFlow/CoachCard share a serious-tool tone) and Space Grotesk-grade display type. *Dropped, deliberately* — all cheer visual vocabulary. HitRate is the first family app addressing athletes beyond cheer, so it earns its own court-at-night identity rather than inheriting the cheer-utility look. Cohesion = tone and craft, not motif.

---

## 7. Naming verdict

**Keep "HitRate" as the brand. Carry the meaning with the subtitle. Do not rename.**

The research (§5) spends a lot of words on "'hit rate' reads as baseball/sales outside cheer" and notes rename is near-free pre-launch — together these tempt a rename to "Landed." That's a trap, and here's the reasoning that breaks the tie:

- **Renaming to "Landed" doesn't remove the vertical-lock — it relocates it.** "Landed" is skate-native and equally foreign to the other three: a flyer *hits* a stunt, a climber *sends* a route, a gymnast *sticks* a pass — none of them "land." So "Landed" fails the exact same flyer/climber test that disqualifies "HitRate" for skaters, *and* it abandons the launch beachhead's own idiom. That's a lateral move that breaks the thing we launch on. No single-sport verb travels — which is precisely why the brand layer must stay neutral and let the renameable-outcomes feature carry vernacular in-app.
- **The name literally describes the universal mechanic.** Every vertical computes a *hit rate* (lands/attempts, sends/attempts, sticks/passes). The name is accurate even where "hit" isn't the outcome word — it names the metric, not the verb.
- **Beachhead-native + founder-aligned + already built.** "We hit the routine" is cheer-native; cheer is launch. Founder attachment is real and the product/repo/icon already carry the name. Brand names ride meaning through a subtitle all the time (KAYA, Chalk, Strava).

**The honest cost (stated, not hidden):** "hit rate" is *not* neutral-opaque like "Strava" — it mis-cues to baseball/sales for a cold audience. We fix that with the subtitle, not the name.

**Subtitle strategy (this corrects a real conflict):** the current App Store subtitle `name.txt` → "HitRate: Skill Tracker" anchors on **"skill tracker," which `market-general.md` §3 flags as diluted/risky — do not anchor there.** §3's winnable terms are **"trick tracker," "landed tracker," "[sport] trick tracker."** So:

- **App name:** `HitRate` (drop the ": Skill Tracker" suffix from the name field).
- **Subtitle (30-char ASO field):** lead with the winnable, meaning-carrying keyword. Primary recommendation: **"Trick & Rep Outcome Tracker"** (27 chars) — sport-neutral, on the §3 keyword, and tells a cold user what the metric is. Strong alternates: **"Trick Tracker · Landed & More"** (catches the "landed tracker" term) or, if leaning cheer for the beachhead launch window, **"Stunt & Trick Hit Tracker."**
- The subtitle is where the name's meaning gap closes. Revisit it per launch phase (cheer-leaning at beachhead, trick/skate-leaning as the wedge opens) — the *name* stays fixed, the subtitle is the tunable surface.

*Copy correction to make regardless:* `description.txt` line 19 ("rarity tiers from COMMON to LEGENDARY based on your hit rate") is **stale and wrong** — rarity = milestone *difficulty*, a locked invariant. No marketing copy may tie rarity to hit rate.

---

## 8. Spectator story

The phone doesn't care whose hands tap the buttons. A parent in the stands makes a bucket called "Maya — tumbling," and every pass down the floor is one tap — stuck, stepped out, touched down — building the same dashboard and the same shareable card the athlete would build herself, except it's the proud parent holding the deck at the end of the season. A friend at the skatepark does the same: they film their own clips on their camera app and log the lands and bails between takes in HitRate, then hand over a holo card that says *landed 7 of 20 on the kickflip today* to post next to those clips. There's no separate "spectator mode" to learn and nothing to set up — it's the same one-tap counter, pointed at someone you're watching instead of yourself. (Built for the sideline: big tap targets, fast hands, on-device, no account — log right there from the bleachers without looking away for long.)
</content>
</invoke>
