# HitRate Coach — free-tier launch checklist (target: before Nov 1, 2026)

Why: Jun–Aug 2026 sales — HitRate sold 11 units at $2.99 while free FormationFlow
pulled 100 downloads and converted 11% to Pro. Paid-up-front is the leak; the
competition season (Nov–Apr) is when coaches actually want hit tracking.

## What's in the code (build 41 / v1.9 — first free App Store build)
- `Store/CoachGrandfatherPolicy.swift` + `Store/CoachEntitlement.swift` —
  StoreKit 2. Grandfathers anyone whose `AppTransaction.originalAppVersion`
  (iOS CFBundleVersion at original install) is **strictly less than 41** — that
  covers every paid-era install, including builds 36–40 that shipped Coach IAPs
  while the app was still $2.99. Sandbox / TestFlight / App Review report
  `"1.0"` here and are never grandfathered. Non-numeric values never qualify.
  Never revokes on an empty `currentEntitlements` (offline); only past
  expiry + 3-day grace.
- `Store/CoachPaywallView.swift` — training-floor register sheet. Yearly
  featured (14-day trial), monthly secondary, restore, EULA + privacy links.
- Gates: share-folder (both buttons in FolderListView), second folder
  (`CoachGate.freeFolderLimit = 1`), homework, CSV backup (DataManagementView).
  Joining a coach's folder by code stays FREE (that's how athletes arrive).
- Rating ask: 2nd and 6th practice ended with reps on the books (HomeView).
- Cross-promo: Manage Data → "More coaching tools" + "HitRate Coach" row.
- `HitRate.storekit` — local test config. In Xcode: scheme → Run → Options →
  StoreKit Configuration → HitRate.storekit.

## App Store Connect (do in this order)
1. Subscriptions → "HitRate Coach". Products:
   - `com.ianrichardson.HitRate.coach.yearly` — $29.99/yr, 14-day free trial
   - `com.ianrichardson.HitRate.coach.monthly` — $4.99/mo, no trial
   Fill review screenshot with the paywall; localize display names as in
   the storekit file.
2. Submit build **41** (v1.9) WITH the two subscriptions attached to the version
   (first-time IAPs must ride a binary). Builds 36–40 already introduced Coach
   IAPs while the app was paid; 41 is the first build users download as free.
3. Only after build 41 is approved: Pricing → change price to Free, same day
   you release. Never go free before the grandfather cutoff build is live or
   new installs on an older build number could get Coach without paying.
4. Release notes: "HitRate is now free for athletes. Coach unlocks sharing,
   unlimited folders, homework and CSV. Already had HitRate? You already
   have Coach — tap Restore if it doesn't show."
5. Update subtitle → "Cheer Stunt Hit Tracker"; keywords add
   `cheerleading,stunt,tumbling,coach,hit rate,team`.

## Verify before ship
- Sandbox tester on a fresh install: second folder → paywall; buy yearly → trial
  starts → share button works; Settings › Subscriptions cancel → still Coach
  until expiry + 3 days.
- Paid-era production device (original install build 36–40): upgrade to 41 after
  price goes free → Coach without subscribing. TestFlight can't mimic this
  (`originalAppVersion` is `"1.0"`); trust unit tests + one real device.
- Airplane mode launch with Coach cached: still Coach.

## Grandfather cutoff rationale
- **Use build number, not marketing version.** Apple documents iOS
  `originalAppVersion` as the original **CFBundleVersion**. HitRate uses numeric
  build numbers (36, 37, … 41), so `Int(build) < firstFreeBuild` is stable.
- **`firstFreeBuild = 41`** is the first binary listed while the app is free.
  Anyone who installed at 40 or below (including $2.99 buyers on 36–38) keeps
  Coach. Installs starting at 41 need a subscription.
- **Risk:** Very old installs before App Store receipts existed may not resolve
  `AppTransaction` until network/StoreKit runs; **Restore** re-runs the check.
  If Apple ever returned a non-numeric production version, those users would not
  auto-grandfather (same as sandbox `"1.0"` handling) — watch support mail.
