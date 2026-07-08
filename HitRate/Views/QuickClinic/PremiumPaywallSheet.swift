import SwiftUI

struct PremiumPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var isPurchasing = false
    @State private var purchaseSuccess = false
    
    var onUpgradeSuccess: () -> Void
    
    var body: some View {
        ZStack {
            CourtBackdrop().ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.label2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                Spacer()
                
                // Header
                VStack(spacing: 8) {
                    Text("HITRATE PRO")
                        .font(Theme.grotesk(32, .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.electric, Theme.coral],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .tracking(2)
                    
                    Text("Cloud Archive / Director Report")
                        .font(Theme.grotesk(18, .medium))
                        .foregroundStyle(Theme.label)
                        .multilineTextAlignment(.center)
                }
                
                // Feature list
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "archivebox.fill", title: "Permanent Cloud Archive", subtitle: "Save temporary clinic sessions directly into your permanent roster history.")
                    FeatureRow(icon: "doc.plaintext.fill", title: "PDF Director Report", subtitle: "Export professional analytics reports for camp directors and gym owners.")
                    FeatureRow(icon: "sparkles", title: "Holographic Rarity Cards", subtitle: "Unlock legendary card styles for mats and athletes to share with the team.")
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Pricing Anchor
                VStack(spacing: 6) {
                    Text("$49/yr")
                        .font(Theme.grotesk(36, .bold))
                        .foregroundStyle(Theme.label)
                    
                    Text("Just $4.08/month — less than the cost of a single private coaching lesson!")
                        .font(Theme.grotesk(13, .regular))
                        .foregroundStyle(Theme.label2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Action Button
                if purchaseSuccess {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.brandGreen)
                        Text("Upgrade Successful!")
                            .font(Theme.grotesk(16, .bold))
                            .foregroundStyle(Theme.label)
                    }
                    .transition(.scale.combined(with: .opacity))
                    .padding(.vertical, 12)
                } else {
                    Button {
                        purchasePro()
                    } label: {
                        HStack(spacing: 8) {
                            if isPurchasing {
                                ProgressView()
                                    .tint(Theme.navy)
                            } else {
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text(isPurchasing ? "PROCESSING..." : "UNLOCK PRO FEATURES")
                                .font(Theme.grotesk(14, .bold))
                                .tracking(1.5)
                        }
                        .foregroundStyle(Theme.navy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Theme.electric, Theme.brandGreen],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .shadow(color: Theme.electric.opacity(0.35), radius: 10, y: 4)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)
                    .padding(.horizontal, 16)
                }
                
                Spacer()
            }
        }
    }
    
    private func purchasePro() {
        isPurchasing = true
        // Simulate payment validation latency
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isPurchasing = false
            withAnimation(.spring()) {
                purchaseSuccess = true
            }
            
            // Set AppStorage or other state to mark user as upgraded success
            UserDefaults.standard.set(true, forKey: "isHitRatePro")
            
            // Fire callback after a brief success animation delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onUpgradeSuccess()
                dismiss()
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Theme.electric)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.grotesk(15, .medium))
                    .foregroundStyle(Theme.label)
                Text(subtitle)
                    .font(Theme.grotesk(12, .regular))
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
