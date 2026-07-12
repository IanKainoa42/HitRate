
## 2026-07-11 — device-watch grep matched 'available' inside 'unavailable'

- **What happened:** A device-availability poller used `grep -oE 'available|connected'` on `devicectl list devices`. The state string "unavailable" CONTAINS "available", so the poller false-positived on an offline phone, then ran xcodebuild against a phantom destination (exit 70).
- **Rule:** When matching a device/state word that is a substring of its own negation, anchor with word boundaries AND exclude the negation: `grep -oE '(available|connected)' | grep -v unavailable`.
