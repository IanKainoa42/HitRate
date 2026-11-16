# Stunt analysis golden fixtures (IAN-618)

The StuntScope -> HitRate stats-only contract, pinned in one place per repo:

- `v1-golden-doc.json` — the `teams/{teamId}/stuntAnalyses/{id}` Firestore doc (`HRStuntDocument`,
  FlightFilter `FlipForm/Sync/HitRateModels.swift`). `updatedAt` is ISO-8601 here, a Firestore timestamp on the wire.
- `v1-golden-frames.json` — `frames.json` (`StuntFrameExport`, `FlipForm/Sync/StuntFrameExport.swift`), sortedKeys.

HitRate asserts both fixtures in three places, so a rename or type change fails a test, not a user:
`HitRateTests/StuntCloudSyncTests.swift` (reader), and `FirestoreRulesTests/firestore.rules.test.mjs`
(the rules accept this exact doc).

Provenance: hand-built from the writer's Codable definitions; FlightFilter's `StuntContractGoldenTests` (branch `ian-618-stunt-golden`)
re-encodes the writer types and asserts byte/field equality against its identical copy.

```
56f21f247a86ff342a0473beba21e1c9375bc51afeb37204f9f29658919f5b89  v1-golden-doc.json
62699d997a83adb7c16c53ed6afee0ae854c89dac1d2925e3b11525f5da5503a  v1-golden-frames.json
```

Changing the format: change the writer, bump `version` if meaning changes, re-record, update
`FrameArchive`, `stuntAnalysisFieldsValid` in `firestore.rules`, and both hashes in both repos.
