## 2026-06-07 — xcodegen hardcodes Info.plist version "1"/"1.0" — wire it to build settings

- **Category:** correction
- **What happened:** Bumped `CURRENT_PROJECT_VERSION` 1→2 in project.yml +
  `xcodegen generate` (pbxproj showed 2), but `fastlane ship_upload` failed:
  altool `ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE` "bundle version must be
  higher than previously uploaded version: '1'." The archive's CFBundleVersion
  was still 1 — xcodegen's generated `HitRate/Info.plist` hardcoded
  `CFBundleVersion = 1` because the `info.properties` block never set it. The
  documented "just bump CURRENT_PROJECT_VERSION" silently did nothing to the
  binary; build 1 only worked because it matched xcodegen's default.
- **Rule:** In `project.yml` `targets.HitRate.info.properties`, set
  `CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"` and
  `CFBundleShortVersionString: "$(MARKETING_VERSION)"` so the plist resolves
  from build settings at build time (Xcode substitutes `$(...)` during the
  build). Now fixed + committed. After any version bump, verify the ARCHIVE:
  `plutil -extract CFBundleVersion raw /tmp/HitRate_ship/HitRate.xcarchive/Products/Applications/HitRate.app/Info.plist`
  must equal the new number before trusting the upload. TestFlight-only upload
  lane = `fastlane ship_upload` (build+upload, no submit); build must be >
  every prior uploaded build (`fastlane asc_build_status` to check).

## 2026-06-07 — When Ian recalls a past UI, confirm by describing — don't force multiple-choice

- **Category:** correction
- **What happened:** Ian asked what happened to "the grid view during practice"
  — a layout he remembered. I checked git/handoff (it was never committed), then
  fired an AskUserQuestion with A/B/C interaction-model options. He rejected the
  tool ("the user wants to clarify"), then plainly described it himself: the
  practice recorder laid out like the stats/home heatmap (groups×outcomes), each
  cell tap-to-`+1`.
- **Rule:** When Ian references a feature from memory, reflect my understanding
  back in one sentence for confirmation, or ask him to describe it — do NOT box
  him into multiple-choice options that may all miss his mental model. Multiple
  choice is for forks I genuinely can't resolve, not for "what did you mean."

## 2026-06-07 — Coach practice recorder: tap-to-log matrix (groups×outcomes)

- **Category:** best_practice
- **What happened:** Built `logGrid` in LogView — the whole roster as a
  groups×4-outcomes matrix, each cell a tap-to-`+1` button (no group selection).
  A single outcome-label header row means it's gated to single-kind rosters
  (`gridAvailable`); coach (all-stunt) defaults to Grid, mixed-kind athletes
  stay on the Pad. Grid⇄Pad `MiniSeg` persisted in `practiceLayout`.
- **Rule:** Verify increments via the accessibility tree, not screenshots — each
  cell exposes `accessibilityLabel "Log <Outcome> for <Group>"` + value = count,
  so a single tap → value 0→1 is checkable. Sims kept auto-shutting between
  steps this session (`code 405: ... Shutdown`); re-`boot`+`bootstatus` before
  each install. iPhone flipped to `unavailable` mid-session → device build fails
  with "Unable to find a destination" until it's reconnected/unlocked.

## 2026-06-05 — UserDefaults reads inside model computed properties ship stale UI

- **Category:** knowledge_gap
- **What happened:** Made `Outcome.label/short` read UserDefaults directly for
  renameable outcome names, and declared (but never read) @AppStorage props in
  HomeView/LogView assuming they'd force invalidation. QA found the Log pad and
  the LATEST SESSION tape legend stale after a rename, while the heatmap header
  on the same screen updated — child views with "unchanged" inputs skip body,
  and @AppStorage invalidation is read-based on iOS 17 (declared-but-unread
  props do nothing).
- **Rule:** Renameable/user-editable strings rendered across many views go in an
  `@Observable` singleton (persisting to UserDefaults in `didSet`), and model
  accessors read through it. Reads inside body then register tracked
  dependencies automatically — no per-view @AppStorage juggling. Never read raw
  UserDefaults in anything a SwiftUI body renders.

## 2026-06-05 — First-submission ASC pipeline gotchas (HitRate 1.0)

- **Category:** knowledge_gap
- **What happened:** Three traps hit while staging a brand-new app record via API:
  1. `deliver` crashes with `Models.parse: No data` on a NEW app version — it fetches
     the appStoreReviewDetail before creating it. Fix: pre-create the review detail via
     `Spaceship::ConnectAPI.post_app_store_review_detail` (clone contact info from a
     shipped app's version via `fetch_app_store_review_detail`).
  2. `deliver --price_tier 0` is dead — it PATCHes `apps` with removed attributes
     (`availableInNewTerritories`, `prices` relationships). Fix: POST `appPriceSchedules`
     directly (raw Net::HTTP + token bearer): find the `0.0` appPricePoint for USA via
     `GET apps/<id>/appPricePoints?filter[territory]=USA`, then POST schedule with
     baseTerritory USA + included `${price1}` appPrice. NOTE: `tunes_request_client.get`
     404s on that path — use raw HTTP.
  3. `upload_to_app_store` in the upload lane needs `run_precheck_before_submit: false`
     too (not just the submit lane) — precheck fires post-upload and fails on IAP checks
     with API-key auth, exiting 1 AFTER a successful binary upload.
- **Rule:** For first submissions: create app record → post review detail → deliver
  metadata/screenshots → raw-API price schedule → web UI for Age Rating + App Privacy
  (API still can't do those; browser automation through logged-in Chrome works fine).

## 2026-06-05 — GitHub Pages on free plan = public repos only

- **Category:** knowledge_gap
- **What happened:** Tried to enable Pages on private HitRate repo → 422 "plan does not
  support". CoachCard/CheerPracticePlayer have Pages because they're public.
- **Rule:** Privacy-policy hosting pattern requires the repo public. Serve from an orphan
  `gh-pages` branch (site files only) so docs/design handoffs and scratch dirs aren't
  published even though the source is.

## 2026-06-05 — File I/O in SwiftUI body via eager ShareLink payloads

- **Category:** best_practice
- **What happened:** `actionRow` called `CSVExport.write(sessions:)` (full CSV
  string build + temp-file write) inside body so ShareLink could take a URL —
  rewriting the file on every Home render (every timeframe flip, every rep).
- **Rule:** ShareLink payloads that cost anything get a lazy `Transferable`
  (`FileRepresentation`/`DataRepresentation` export closure). Snapshot plain
  value rows at body time if needed; build strings/files only when the share
  fires. Never write files during body evaluation.

## 2026-06-05 — Fixed-width stat columns must fit the max value

- **Category:** correction
- **What happened:** RankedRow's rate column (`.frame(width: 44)`) fit "92%"
  from the handoff dataset but real data hit 100% and "100%" wrapped to two
  lines ("10"/"0%") — found by screenshotting a live install, not by the scan.
- **Rule:** Any fixed-width numeric column gets sized for its maximum rendering
  ("100%") plus `.lineLimit(1)` + `.minimumScaleFactor`. Handoff datasets
  don't exercise extremes; perfect rates are common for athletes logging few
  reps.

## 2026-06-05 — UIImageWriteToSavedPhotosAlbum fire-and-forget lies on denial

- **Category:** knowledge_gap
- **What happened:** Save-card toast said "Saved to Photos" unconditionally;
  with Photos add-access denied the call fails silently (nil completion
  target) and the toast lied.
- **Rule:** Always pass an NSObject completion target with
  `image(_:didFinishSavingWithError:contextInfo:)` and branch the user-facing
  confirmation on the error. Applies to every share/save surface.

## 2026-06-06 — UIImageWriteToSavedPhotosAlbum flattens PNG alpha to JPG

- **Category:** knowledge_gap
- **What happened:** Cheer-puck renders (ImageRenderer, isOpaque=false, transparent corners) saved via UIImageWriteToSavedPhotosAlbum landed in the sim photo library as 720×720 JPGs with black corners — the alpha channel doesn't survive the save path.
- **Rule:** If transparency must survive into Photos, use PHAssetCreationRequest with PNG data instead. If the flattened look is acceptable (dark art on black), UIImageWriteToSavedPhotosAlbum is fine and keeps the simple completion-target pattern.

## 2026-06-06 — Custom segmented/dark List styling on iOS 17

- **Category:** best_practice
- **What happened:** Re-skinning the grouped List (GroupsEditorView) to the navy register: `.scrollContentBackground(.hidden)` + `.background(navy)` swaps the canvas, but rows stay system dark-gray unless `.listRowBackground(...)` is applied — and it must go on each Section (it applies to all rows within).
- **Rule:** Dark-brand a SwiftUI List with: scrollContentBackground(.hidden) + background color + per-Section listRowBackground. Use a solid-ish row color (not low-alpha white) so swipe actions/separators stay readable.

## 2026-06-06 — Synthesized UI tap sounds: recipe that avoids the "cheap click"

- **Category:** best_practice
- **What happened:** Built fidget sounds for the Log pad by synthesizing WAVs in pure Python (wave module, no deps): water-drop pops = downward pitch glide + exponential decay, pitched by outcome severity, 3 variants ±7% per event. Played via AudioServicesCreateSystemSoundID (register once at init, play per tap — lowest latency, respects silent switch, mixes over music).
- **Rule:** Synthesized UI sounds MUST fade in ~2ms and force-fade to true zero at the end (assert first/last samples ≈ 0 in the generator) — non-zero endpoints produce a hard click on every play and that's inaudible to an agent. For organic feel: multiple pitch variants + never repeat the same variant twice in a row. Generator: /tmp/gen_sounds.py pattern (HitRate).

## 2026-06-06 — Button sounds: Ian wants native-subtle, not designed

- **Category:** correction
- **What happened:** Button-sound iteration went synthesized pops → cinematic SFX pack (Singularity) → Ian: "im thinking just like regular subtle clicks." Final: system keyboard-click family (IDs 1104/1103/1105) rotated with no-repeat — zero assets.
- **Rule:** For HitRate UI feedback, default to native/system-subtle (keyboard-click register) rather than designed/cinematic sounds. Severity theatrics belong on the share cards, not the counter. Known-good system click IDs: 1104 tock, 1103 tick, 1105 modifier tock.

## 2026-06-06 — Don't delete a SwiftData model a fullScreenCover is still rendering

- **Category:** best_practice
- **What happened:** Killing the tab bar made LogView a `fullScreenCover(item:)` holding a `PracticeSession`. "End" on an empty session originally deleted the model, but the cover keeps rendering it during the dismiss animation — deleted-model property access crashes.
- **Rule:** Inside the cover, only mutate live models (`endedAt = .now`); defer deletes to the presenter's `onDismiss` (Home sweeps empty live sessions there). Same family as the existing "validate selection membership before insert" rule in LogView.

## 2026-06-07 — Inset-well recipe + design-dial iteration

- **Category:** best_practice
- **What happened:** The training-floor restyle needed recessed "embedded" modules. SwiftUI recipe that matches the approved mockup: `RoundedRectangle.fill(color.shadow(.inner(color:.black.opacity(0.6),radius:4,y:2)).shadow(.inner(color:.white.opacity(0.05),radius:0.5,y:-1))).shadow(color:.white.opacity(0.05),radius:0,y:1)` — inner top shadow + bottom inner catch-light + 1px outer bottom edge. A second inner shadow in an accent color (radius 1, y:-2) makes the engraved colored bottom edge on the Log pad. Also: content scrolling under a `safeAreaInset` CTA pokes through the button's corner gaps — back it with a clear→bg vertical gradient.
- **Rule:** For embedded/inset surfaces use stacked `.shadow(.inner())` on the fill's ShapeStyle, not overlays; always give floating safeAreaInset buttons a fade backstop. When iterating design with Ian, isolate one dial per round (skeleton → texture → font → accent) in clickable browser mockups — see memory `ian-visual-design-taste`.

## 2026-06-07 — TextField↔@Observable feedback loop = laggy keyboard (PracticeMix-class)

- **Category:** best_practice
- **What happened:** Renaming a skill/outcome in GroupsEditorView lagged + dropped/fought keystrokes. Cause: the TextField bound via `Binding(get:{observed},set:{observed=$0})` to `OutcomeNames` (app-wide @Observable) and to a SwiftData @Model (`g.name`). Each keystroke mutated observed state the editing view reads → re-rendered the editor mid-edit (worsened by the inset-well shadow recompositing after the restyle) → cursor fought the keyboard. Same class as the PracticeMix typing fix (don't do heavy work / observable round-trips on the keystroke setter).
- **Rule:** For rename fields, type into a LOCAL `@State` buffer and commit to the observable/model only on blur (`onChange(of: focused)`), `.onSubmit`, and `.onDisappear` — see `RenameField` in GroupsEditorView.swift. Preserves the e2-1/e2-2 invariant (labels still re-render app-wide once the rename commits, just not per keystroke). Note: MCP/sim taps can't reproduce typing-throughput lag (each tap is a network hop) — you can catch dropped *characters* (typed vs field value) but smooth-but-slow must be judged by the user on-device.

## 2026-06-07 — Confine StatsEngine to the passed groups before any subset feature

- **Category:** correction
- **What happened:** Adding the athlete stunt/tumbling split (filter the `groups` array → recompute) would have silently leaked the other kind into the trend and latest-session tape: `trendSeries`/`latestSnapshot` counted ALL session attempts, ignoring the passed `groups`. (advisor-caught before build.)
- **Rule:** When a pure stats function takes a `groups` subset, EVERY derived series must honor it. Build `let allowed = Set(groups.map(\.persistentModelID))` once and filter `attempt.group` membership in trend/tape/rough-patch — not just the per-group rollup. Verified: stunt(109) + tumbling(124) = all(233); tumbling-only flips the legend wording via aggregateKind for free.

## 2026-06-10 — Concurrent session edits HitRate mid-task

- **Category:** best_practice
- **What happened:** While building the ghost-competitor feature, another agent session was editing the same repo: it duplicated a `ghostChallengeNote` view into WeeklyTournamentCard.swift mid-edit (would not compile), modified DataManagementView/OnboardingView, added a commit, and switched the checkout from the feature branch to main.
- **Rule:** In HitRate (and any repo with multiple live agents): before committing, run `git status` + `git log -1` and stage ONLY the files you touched by name — never `git add -A`. If an Edit fails with "file modified since read", re-read and check for foreign duplicate declarations before re-applying.
