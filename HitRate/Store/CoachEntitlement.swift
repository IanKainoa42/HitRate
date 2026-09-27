import Foundation
import StoreKit
import SwiftUI
import os

/// HitRate Coach — the paid tier, introduced when the app went free (build 36,
/// Oct 2026). Athletes log, see their dashboard, earn cards and use the watch
/// for free. Coaches pay for the TEAM features: more than one folder, sharing a
/// folder by join code, and the CSV backup.
///
/// Anyone who BOUGHT HitRate while it was a $2.99 paid app is grandfathered
/// into Coach for life — they paid for everything once and keep everything.
///
/// Rules carried over from FormationFlow's EntitlementManager (IAN-517/544):
/// - never revoke because `Transaction.currentEntitlements` came back empty —
///   it does that offline; only revoke past a known expiry + grace;
/// - the cached decision lives in UserDefaults but is only ever DOWNGRADED by
///   a verified, dated expiry, so a forged default buys at most a few days.
@MainActor
final class CoachEntitlement: ObservableObject {
    static let shared = CoachEntitlement()

    static let yearlyID  = "com.ianrichardson.HitRate.coach.yearly"
    static let monthlyID = "com.ianrichardson.HitRate.coach.monthly"
    static let productIDs: Set<String> = [yearlyID, monthlyID]

    /// First CFBundleVersion shipped with price = Free. `AppTransaction.
    /// originalAppVersion` is the build number on iOS; anything below this was
    /// a $2.99 purchase. Keep in lockstep with project.yml when shipping.
    static let firstFreeBuild = 36

    /// Days past a subscription's expiry before we actually lock team features.
    /// Covers billing retry + a weekend without signal at a competition venue.
    static let graceDays = 3

    @Published private(set) var isCoach: Bool
    @Published private(set) var isGrandfathered: Bool
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var lastError: String?

    private let defaults = UserDefaults.standard
    private let cachedKey = "coach.entitled"
    private let expiryKey = "coach.expiresAt"
    private let grandfatherKey = "coach.grandfathered"
    private var updatesTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.ianrichardson.HitRate", category: "CoachEntitlement")

    private init() {
        let grandfathered = UserDefaults.standard.bool(forKey: "coach.grandfathered")
        isGrandfathered = grandfathered
        isCoach = grandfathered || UserDefaults.standard.bool(forKey: "coach.entitled")
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let t) = result {
                    await t.finish()
                    await self.refresh()
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: Launch

    /// Call once from the root. Cheap, offline-safe, never blocks UI.
    func start() async {
        await checkGrandfather()
        await refresh()
    }

    /// Paid-era buyers keep everything. Runs once and caches — the receipt's
    /// original version never changes.
    private func checkGrandfather() async {
        guard !isGrandfathered else { return }
        guard case .verified(let tx) = try? await AppTransaction.shared else { return }
        // Sandbox/TestFlight receipts report "1.0" here; treat non-numeric as
        // "not grandfathered" so testers exercise the real paywall.
        if let build = Int(tx.originalAppVersion), build < Self.firstFreeBuild {
            log.info("Grandfathered: original build \(build) < \(Self.firstFreeBuild)")
            setGrandfathered()
        }
    }

    // MARK: Entitlement

    func refresh() async {
        if isGrandfathered { return }
        var latestExpiry: Date?
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result,
                  Self.productIDs.contains(t.productID),
                  t.revocationDate == nil else { continue }
            active = true
            if let exp = t.expirationDate { latestExpiry = max(latestExpiry ?? .distantPast, exp) }
        }
        if active {
            grant(expiry: latestExpiry)
            return
        }
        // Nothing came back. Offline, that's meaningless — hold the cached
        // state unless we're provably past expiry + grace.
        if let exp = defaults.object(forKey: expiryKey) as? Date {
            let cutoff = Calendar.current.date(byAdding: .day, value: Self.graceDays, to: exp) ?? exp
            if Date() > cutoff { revoke() }
        }
    }

    // MARK: Store

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // Yearly first — it's the one we lead with.
            products = loaded.sorted { $0.id == Self.yearlyID && $1.id != Self.yearlyID }
            lastError = nil
        } catch {
            lastError = "Couldn't reach the App Store. Check your connection and try again."
            log.error("Product load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    enum PurchaseOutcome { case purchased, pending, cancelled, failed(String) }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let t) = verification else {
                    return .failed("The App Store couldn't verify that purchase.")
                }
                await t.finish()
                grant(expiry: t.expirationDate)
                return .purchased
            case .pending:   return .pending
            case .userCancelled: return .cancelled
            @unknown default: return .failed("Unknown purchase result.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async -> Bool {
        try? await AppStore.sync()
        await checkGrandfather()
        await refresh()
        return isCoach
    }

    // MARK: State

    private func grant(expiry: Date?) {
        defaults.set(true, forKey: cachedKey)
        if let expiry { defaults.set(expiry, forKey: expiryKey) } else { defaults.removeObject(forKey: expiryKey) }
        if !isCoach { isCoach = true }
    }

    private func revoke() {
        defaults.set(false, forKey: cachedKey)
        defaults.removeObject(forKey: expiryKey)
        if isCoach { isCoach = false }
        log.info("Coach entitlement lapsed past grace")
    }

    private func setGrandfathered() {
        defaults.set(true, forKey: grandfatherKey)
        isGrandfathered = true
        isCoach = true
    }

    #if DEBUG
    func debugSetCoach(_ on: Bool) {
        defaults.set(on, forKey: cachedKey)
        defaults.removeObject(forKey: expiryKey)
        isCoach = on
    }
    #endif
}

// MARK: - Gate helper

/// The single question every team feature asks. Reads through the shared
/// entitlement so views don't each cache a copy.
enum CoachGate {
    /// Folders beyond the first are a Coach feature.
    static let freeFolderLimit = 1

    @MainActor
    static func allowsNewFolder(existingCount: Int) -> Bool {
        CoachEntitlement.shared.isCoach || existingCount < freeFolderLimit
    }
}
