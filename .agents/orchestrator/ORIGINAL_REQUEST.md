# Original User Request

## Initial Request — 2026-07-07T18:55:59Z

Implement the "Quick Clinic / Guest Coach" one-off session workflow in HitRate (iOS SwiftUI/SwiftData) to reduce session setup time from 50 seconds to under 5 seconds using UX psychology principles (Smart Defaults, Goal Gradient, IKEA Effect, Reciprocity, Loss Aversion, and Price Anchoring).

Working directory: /Users/ianrichardson/Projects/HitRate
Integrity mode: development

## Requirements

### R1. Zero-Setup Entry & Smart Defaults (1-Tap Stepper)
Add a "New Clinic Session" action off Home that bypasses persistent folder creation. Launch a lightweight modal with a stepper defaulting to 6 anonymous mats (`Group 1`–`Group 6`) and a 66% completed goal gradient progress pill (`[✓ Coach Mode] -> [✓ 6 Mats Ready] -> [Tap to Log]`). Launching drops the user straight into the existing `logGrid` bento matrix in under 5 seconds.

### R2. Ephemeral Roster Isolation & In-Place Personalization (IKEA Effect)
Keep clinic sessions as in-memory state during live logging; do not write to SwiftData unless the coach explicitly taps "Archive Clinic", ensuring camp falls never pollute the global `Milestones.swift` lifetime engine. In `logGrid`, allow inline row tapping to tag visual descriptors (`"Mat 2 • Guy Base"`) and stamp camp names (`"Woodward '26"`) without opening the full editor.

### R3. Reciprocity Wrap-Up Sheet & Foil Share Cards
Upon ending practice, present a wrap-up sheet displaying the interactive Canvas session tape and generating all 6 dynamic holographic athlete share cards (`HoloCardView`). Allow coaches to AirDrop and share all athlete holographic cards completely free before any auth or upgrade prompt.

### R4. Ethical Loss Aversion & Anchored Pro Monetization
If attempting to exit an unarchived clinic, display an honest loss-framing sheet stating the exact in-memory rep count and share cards at risk of being discarded. Present the Pro Cloud Archive / Director Report upgrade ($49/yr) anchored against the cost of a single private coaching lesson ($4.08/mo).

## Acceptance Criteria

### Verification & Testing
- [ ] Build the project successfully using `xcodegen generate` and `xcodebuild` for iOS Simulator.
- [ ] Launch the app on a booted simulator via `simctl` and verify the new "New Clinic Session" flow from Home.
- [ ] Capture visual proof (simulator screenshots or recordings) demonstrating that the 1-tap stepper drops into `logGrid` pre-seeded with 6 mats in under 5 seconds.
- [ ] Capture visual proof of the wrap-up sheet displaying the session tape and free foil share card preview.

### Functional Guardrails
- [ ] Confirm that logging reps in a Quick Clinic session does not increment lifetime counters or trigger bad/good badges in `Milestones.swift` unless archived.
- [ ] Confirm that AirDrop / sharing of athlete holographic cards is completely unrestricted on the free tier, gating only Cloud Archiving and custom PDF Director Reports.
