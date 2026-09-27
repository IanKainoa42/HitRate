# HitRate Coach — free-tier launch checklist (target: before Nov 1, 2026)

Why: Jun–Aug 2026 sales — HitRate sold 11 units at $2.99 while free FormationFlow
pulled 100 downloads and converted 11% to Pro. Paid-up-front is the leak; the
competition season (Nov–Apr) is when coaches actually want hit tracking.

## What's in the code (build 36 / v1.8)
- `Store/CoachEntitlement.swift` — StoreKit 2. Grandfathers anyone whose
  `AppTransaction.originalAppVersion` < 36 (paid-era buyers keep everything).
  Never revokes on an empty `currentEntitlements` (offline); only past
  expiry + 3-day grace.
- `Store/CoachPaywallView.swift` — training-floor register sheet. Yearly
  featured (14-day trial), monthly secondary, restore, EULA + privacy links.
- Gates: share-folder (both buttons in FolderListView), second folder
  (`CoachGate.freeFolderLimit = 1`), CSV backup (DataManagementView).
  Joining a coach's folder by code stays FREE (that's how athletes arrive).
- Rating ask: 2nd and 6th practice ended with reps on the books (HomeView).
- Cross-promo: Manage Data → "More coaching tools" + "HitRate Coach" row.
- `HitRate.storekit` — local test config. In Xcode: scheme → Run → Options →
  StoreKit Configuration → HitRate.storekit.

## App Store Connect (do in this order)
1. Subscriptions → new group "HitRate Coach". Products:
   - `com.ianrichardson.HitRate.coach.yearly` — $29.99/yr, 14-day free trial
   - `com.ianrichardson.HitRate.coach.monthly` — $4.99/mo, no trial
   Fill review screenshot with the paywall; localize display names as in
   the storekit file.
2. Submit build 36 WITH the two subscriptions attached to the version
   (first-time IAPs must ride a binary).
3. Only after build 36 is approved: Pricing → change price to Free, same day
   you release. Never go free before the grandfather build is live or
   paid-era buyers on 35 would lose nothing (fine) but new free installs on
   35 would get Coach for free (build < 36).
4. Release notes: "HitRate is now free for athletes. Coach unlocks sharing,
   unlimited folders, homework and CSV. Bought HitRate before? You already
   have Coach — tap Restore if it doesn't show."
5. Update subtitle → "Cheer Stunt Hit Tracker"; keywords add
   `cheerleading,stunt,tumbling,coach,hit rate,team`.

## Verify before ship
- Sandbox tester on a fresh install: second folder → paywall; buy yearly → trial
  starts → share button works; Settings › Subscriptions cancel → still Coach
  until expiry + 3 days.
- Build 35 install upgraded to 36 (TestFlight can't test this — sandbox
  reports originalAppVersion "1.0"): confirm with a real paid-era device
  after release, or trust the Int parse + `< 36` rule.
- Airplane mode launch with Coach cached: still Coach.
