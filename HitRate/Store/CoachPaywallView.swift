import SwiftUI
import StoreKit

/// The HitRate Coach paywall. Training-floor register: graphite floor, inset
/// wells, chalk text, Barlow numerals, ONE green CTA. Presented as a sheet from
/// any gated team action (second folder, share code, CSV) — never at launch.
struct CoachPaywallView: View {
    /// What the coach was trying to do; shapes the headline so the ask reads
    /// as "finish what you started", not "please pay".
    enum Reason: Identifiable {
        case share, secondFolder, csv, general
        var id: Self { self }

        var headline: String {
            switch self {
            case .share:        return "Share this deck with your team"
            case .secondFolder: return "Track more than one deck"
            case .csv:          return "Take your season with you"
            case .general:      return "HitRate Coach"
            }
        }
    }

    let reason: Reason
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = CoachEntitlement.shared
    @State private var busyID: String?
    @State private var restoring = false
    @State private var message: String?

    private let privacyURL = URL(string: "https://iankainoa42.github.io/HitRate/privacy-policy.html")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                featureWell
                if store.isCoach {
                    unlockedWell
                } else {
                    productWells
                }
                legal
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(FloorBackdrop().ignoresSafeArea())
        .task { await store.loadProducts() }
        .onChange(of: store.isCoach) { _, now in
            if now { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() } }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    BrandSignalDot(size: 8)
                    Text("COACH")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.label2)
                        .frame(width: 32, height: 32)
                        .wellBackground(cornerRadius: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text(reason.headline)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.label)
            Text("Athletes track for free. Coach unlocks the team side of HitRate.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.label2)
        }
    }

    private var featureWell: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow("person.2.fill", "Share any deck by code",
                       "Athletes join from their own phones. Every rep they log lands on your dashboard.")
            featureRow("rectangle.stack.fill.badge.plus", "Unlimited decks",
                       "A deck per team, per stunt group, per private lesson. Stats stay separate.")
            featureRow("list.clipboard.fill", "Homework",
                       "Assign skills between practices and see who did the reps.")
            featureRow("arrow.down.doc.fill", "CSV backup",
                       "Every attempt, every session, in a spreadsheet you own.")
            featureRow("applewatch", "Everything athletes get",
                       "Watch logging, trend lines, weekly cups, holographic cards.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellBackground(cornerRadius: 14)
    }

    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.label)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.label2)
            }
        }
    }

    @ViewBuilder
    private var productWells: some View {
        if store.products.isEmpty {
            HStack {
                if store.isLoadingProducts { ProgressView().tint(Theme.accent) }
                Text(store.lastError ?? "Loading plans…")
                    .font(.system(size: 13)).foregroundStyle(Theme.label2)
            }
            .frame(maxWidth: .infinity).padding(18).wellBackground()
        } else {
            VStack(spacing: 10) {
                ForEach(store.products, id: \.id) { product in
                    productRow(product, featured: product.id == CoachEntitlement.yearlyID)
                }
            }
            if let message {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.majorFall)
            }
            Button {
                Task {
                    restoring = true
                    let ok = await store.restore()
                    restoring = false
                    if !ok { message = "No Coach purchase found on this Apple ID." }
                }
            } label: {
                Text(restoring ? "Restoring…" : "Restore purchase")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(restoring)
            .padding(.top, 2)
        }
    }

    private func productRow(_ product: Product, featured: Bool) -> some View {
        let period = product.subscription?.subscriptionPeriod
        let perLabel: String = {
            switch period?.unit {
            case .year:  return "per year"
            case .month: return "per month"
            default:     return ""
            }
        }()
        let trial = product.subscription?.introductoryOffer
        return Button {
            Task {
                busyID = product.id
                let outcome = await store.purchase(product)
                busyID = nil
                switch outcome {
                case .purchased, .cancelled: break
                case .pending: message = "Waiting for approval (Ask to Buy)."
                case .failed(let why): message = why
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(featured ? "YEARLY" : "MONTHLY")
                            .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                            .foregroundStyle(featured ? Theme.accentText : Theme.label2)
                        if featured, let trial, trial.paymentMode == .freeTrial {
                            Text("\(trialLabel(trial.period)) FREE")
                                .font(.system(size: 10, weight: .heavy)).tracking(1)
                                .foregroundStyle(Theme.accentText)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accentText.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(featured ? "About the price of one comp-day coffee run." : "Cancel any time.")
                        .font(.system(size: 12))
                        .foregroundStyle(featured ? Theme.accentText.opacity(0.8) : Theme.label2)
                }
                Spacer()
                if busyID == product.id {
                    ProgressView().tint(featured ? Theme.accentText : Theme.accent)
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(product.displayPrice)
                            .font(Theme.barlow(26, .bold))
                            .foregroundStyle(featured ? Theme.accentText : Theme.label)
                        Text(perLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(featured ? Theme.accentText.opacity(0.75) : Theme.label3)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background {
                if featured {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent)
                }
            }
            .modifier(WellUnlessFeatured(featured: featured))
        }
        .buttonStyle(.plain)
        .disabled(busyID != nil)
        .accessibilityLabel("\(featured ? "Yearly" : "Monthly"), \(product.displayPrice) \(perLabel)")
    }

    private var unlockedWell: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent)
            Text(store.isGrandfathered ? "You bought HitRate before it went free. Coach is yours for good."
                                       : "Coach is active on this Apple ID.")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.label)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).wellBackground()
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subscriptions renew automatically until cancelled in Settings › Apple ID › Subscriptions. A free trial converts to the paid plan unless cancelled at least 24 hours before it ends.")
            HStack(spacing: 14) {
                Button("Privacy Policy") { openURL(privacyURL) }
                Button("Terms of Use") { openURL(termsURL) }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.label2)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.label3)
        .padding(.top, 4)
    }

    private func trialLabel(_ p: Product.SubscriptionPeriod) -> String {
        switch p.unit {
        case .day:   return "\(p.value) DAYS"
        case .week:  return "\(p.value * 7) DAYS"
        case .month: return p.value == 1 ? "1 MONTH" : "\(p.value) MONTHS"
        case .year:  return "1 YEAR"
        @unknown default: return "TRIAL"
        }
    }
}

/// Featured row is the raised green CTA (the one raised element rule); the
/// other plan sits in a normal well.
private struct WellUnlessFeatured: ViewModifier {
    let featured: Bool
    func body(content: Content) -> some View {
        if featured {
            content.shadow(color: Theme.accent.opacity(0.28), radius: 12, y: 6)
        } else {
            content.wellBackground(cornerRadius: 14)
        }
    }
}
