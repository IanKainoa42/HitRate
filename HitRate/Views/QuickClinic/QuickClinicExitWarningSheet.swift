import SwiftUI

struct QuickClinicExitWarningSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let attemptsCount: Int
    var onSave: () -> Void
    var onDiscard: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header kicker
            Text("UNSAVED CLINIC SESSION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(Theme.majorFall)
                .padding(.top, 16)
            
            // Warning block
            FeedCard {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.majorFall)
                    
                    Text("Discard Clinic Data?")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.label)
                    
                    Text("This clinic session was created in temporary memory. Closing it now without saving will permanently erase all data forever.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.label2)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)
            }
            
            // Rep count highlights
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("\(attemptsCount)")
                        .font(Theme.barlow(36, .extrabold))
                        .foregroundStyle(Theme.majorFall)
                    Text("REPS AT RISK")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.label2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .wellBackground()
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 10) {
                // Save to permanent roster
                Button {
                    dismiss()
                    onSave()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("SAVE TO PERMANENT ROSTER")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1.2)
                    }
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.accent)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                
                // Erase & Discard
                Button {
                    dismiss()
                    onDiscard()
                } label: {
                    Text("Erase & Discard")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.majorFall)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.well)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.majorFall.opacity(0.4), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                
                // Cancel / Keep Logging
                Button {
                    dismiss()
                } label: {
                    Text("Keep Logging")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.label2)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
        .background(FloorBackdrop().ignoresSafeArea())
    }
}
