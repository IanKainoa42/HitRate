# Tumble transfer golden fixture (mirrored)

`v1-golden.json` is one StuntScope tumble export (`TumbleExchange`, `version: 1`), recorded by
FlightFilter's `TumbleExchangeTests.testEncoderMatchesGoldenFixture` with
`JSONEncoder` `[.sortedKeys, .prettyPrinted]`. Fixed IDs and dates; one tagged back handspring
on track 1 with phases, a rating, a full takeoff speed, a stroke and 4 pose frames.

**This file is mirrored byte-for-byte in two repos and must stay identical:**

- FlightFilter: `Fixtures/TumbleTransfer/v1-golden.json` (writer: `FlightFilter/Services/TumbleExchange.swift`)
- HitRate: `Fixtures/TumbleTransfer/v1-golden.json` (reader: `HitRate/Utilities/TumbleArchive.swift`)

Both repos' tests pin its SHA-256:

```
f18af990901ecd9016cbd639412d413dbe7b65c691b1f7389b4f7343a27c29b4
```

## Changing the format

1. Change `TumbleExchange` in FlightFilter. Bump `version` if any field's meaning changes, not only its shape.
2. Delete `v1-golden.json` (or add `v2-golden.json`) and run `TumbleExchangeTests` to re-record it.
3. Copy the file into HitRate, update `TumbleArchive` (and its accepted versions) to match.
4. Update the pinned hash in `FlightFilterTests/Services/TumbleExchangeTests.swift`
   and `HitRateTests/TumbleArchiveTests.swift`, and in this README in both repos.
5. Land both PRs together.

Tracking: IAN-612.
