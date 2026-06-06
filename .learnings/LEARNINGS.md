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
