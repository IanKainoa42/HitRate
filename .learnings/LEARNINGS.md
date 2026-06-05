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
