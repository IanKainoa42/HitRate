import SwiftUI

struct QuickClinicSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var matCount = 6
    @State private var goalRate = 80 // percentage
    
    var onStart: (Int, Int) -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Intro Header Card
                FeedCard {
                    VStack(alignment: .leading, spacing: 8) {
                        CardHead("GUEST COACH CLINIC")
                        Text("Run a fast clinic setup without polluting your permanent team history. Tracks mats as temporary stunt groups.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.label2)
                    }
                }
                
                // 66% Completed Goal Gradient Progress Pill
                VStack(spacing: 8) {
                    Text("CLINIC PREPARATION STATUS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(Theme.label2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Theme.fill)
                            
                            // 66% filled with gradient
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Theme.accent.opacity(0.8), Theme.accent],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: geo.size.width * 0.66)
                            
                            HStack(spacing: 0) {
                                Spacer()
                                
                                // Step 1: Coach Mode
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Coach Mode")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(Theme.well)
                                
                                Text(" ➔ ")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.well.opacity(0.6))
                                
                                // Step 2: X Mats Ready
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("\(matCount) Mats Ready")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(Theme.well)
                                
                                Text(" ➔ ")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.label3)
                                
                                // Step 3: Tap to Log
                                HStack(spacing: 4) {
                                    Image(systemName: "circle")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Tap to Log")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(Theme.label2)
                                
                                Spacer()
                            }
                        }
                    }
                    .frame(height: 38)
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 4)
                
                // Config Well Card
                FeedCard {
                    VStack(spacing: 16) {
                        CardHead("CLINIC CONFIGURATION")
                        
                        // Mat Count Stepper
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Number of Mats")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.label)
                                    Text("Temporary stunt groups to log reps")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.label2)
                                }
                            } icon: {
                                Image(systemName: "square.grid.2x2")
                                    .foregroundStyle(Theme.accent)
                            }
                            
                            Spacer()
                            
                            Stepper(value: $matCount, in: 1...12) {
                                Text("\(matCount)")
                                    .font(Theme.barlow(20, .bold))
                                    .foregroundStyle(Theme.label)
                                    .padding(.horizontal, 8)
                            }
                        }
                        
                        Divider().background(Theme.separator)
                        
                        // Hit Rate Goal Stepper/Picker
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Hit Rate Goal")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.label)
                                    Text("Target success percentage")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.label2)
                                }
                            } icon: {
                                Image(systemName: "target")
                                    .foregroundStyle(Theme.accent)
                            }
                            
                            Spacer()
                            
                            Stepper(value: $goalRate, in: 50...95, step: 5) {
                                Text("\(goalRate)%")
                                    .font(Theme.barlow(20, .bold))
                                    .foregroundStyle(Theme.label)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Start Button
                Button {
                    onStart(matCount, goalRate)
                    dismiss()
                } label: {
                    HStack(spacing: 9) {
                        BrandSignalDot(size: 9, color: Theme.accentText, shadowOpacity: 0)
                        Text("START CLINIC")
                            .font(.system(size: 14, weight: .heavy))
                            .tracking(1.5)
                    }
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.accent)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white.opacity(0.28), lineWidth: 1))
                            .shadow(color: Theme.accent.opacity(0.24), radius: 8, y: 3)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .background(FloorBackdrop().ignoresSafeArea())
            .navigationTitle("Guest Coach Clinic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.label2)
                }
            }
        }
    }
}
