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
