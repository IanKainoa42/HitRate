import SwiftUI
import SwiftData

enum QuickClinicArchiveDestination: Equatable {
    case archive
}

enum QuickClinicArchivePolicy {
    static func destination(purchasesAvailable: Bool) -> QuickClinicArchiveDestination {
        .archive
    }
}

struct QuickClinicSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    
    let session: PracticeSession
    let groups: [StuntGroup]
    let goalRate: Int
    
    var onArchive: () -> Void
    var onDiscard: () -> Void
    
    @State private var showShareCards = false
    @State private var showExitWarning = false
    @State private var isArchived = false
    
    private var stats: FloorStats {
        StatsEngine.compute(sessions: [session], groups: groups, timeframe: .all)
    }
    
    var body: some View {
        ZStack {
            CourtBackdrop().ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CLINIC SUMMARY")
                            .font(Theme.grotesk(10))
                            .tracking(1.8)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Guest Coach Clinic")
                            .font(Theme.grotesk(21))
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    Button {
                        handleClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.06))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 12)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Big Overall Hit Rate
                        FeedCard {
                            VStack(spacing: 12) {
                                CardHead("OVERALL PERFORMANCE")
                                
                                HStack(spacing: 24) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(stats.rate)%")
                                            .font(Theme.barlow(64, .extrabold))
                                            .foregroundStyle(Theme.rateColor(stats.rate))
                                            .lineLimit(1)
                                        
                                        Text("GOAL: \(goalRate)%")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(Theme.label2)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 6) {
                                        HStack(spacing: 8) {
                                            Text("\(stats.total)")
                                                .font(Theme.barlow(24, .bold))
                                                .foregroundStyle(Theme.label)
                                            Text("REPS")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Theme.label2)
                                        }
                                        
                                        HStack(spacing: 8) {
                                            Text("\(stats.hits)")
                                                .font(Theme.barlow(24, .bold))
                                                .foregroundStyle(Theme.hit)
                                            Text("HITS")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Theme.label2)
                                        }
                                    }
                                }
                                
                                // Progress bar to goal
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Theme.fill)
                                        Capsule()
                                            .fill(stats.rate >= goalRate ? Theme.hit : Theme.buildingFall)
                                            .frame(width: geo.size.width * CGFloat(min(1.0, Double(stats.rate) / Double(max(1, goalRate)))))
                                    }
                                }
                                .frame(height: 6)
                                .padding(.top, 4)
                            }
                        }
                        
                        // Interactive Session Tape Card
                        if let latestSnapshot = stats.latest {
                            SessionTapeCard(snapshot: latestSnapshot, kind: stats.aggregateKind)
                        }
                        
                        // Mats Leaderboard
                        FeedCard {
                            VStack(spacing: 12) {
                                CardHead("MAT LEADERBOARD")
                                
                                if stats.ranked.isEmpty {
                                    Text("No reps logged yet.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.label2)
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(stats.ranked) { g in
                                        HStack(spacing: 10) {
                                            Text("\(g.number)")
                                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                                .foregroundStyle(.white)
                                                .frame(width: 20, height: 20)
                                                .background(Theme.groupColor((g.number - 1)))
                                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                            
                                            Text(g.name)
                                                .font(Theme.grotesk(14, .medium))
                                                .foregroundStyle(Theme.label)
                                            
                                            Spacer()
                                            
                                            StackedBar(counts: g.counts, total: g.total, height: 8)
                                                .frame(width: 80)
                                            
                                            Text("\(g.rate)%")
                                                .font(Theme.barlow(16, .bold))
                                                .foregroundStyle(Theme.rateColor(g.rate))
                                                .frame(width: 44, alignment: .trailing)
                                        }
                                        if g.id != stats.ranked.last?.id {
                                            Divider().background(Theme.separator)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Action row
                        VStack(spacing: 12) {
                            Button {
                                showShareCards = true
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("EXPORT HOLOGRAPHIC MAT CARDS")
                                        .font(Theme.grotesk(14, .bold))
                                        .tracking(1.0)
                                }
                                .foregroundStyle(Theme.electric)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .wellBackground()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                handleSave()
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: isArchived ? "checkmark.circle.fill" : "arrow.down.doc.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(isArchived ? "SAVED TO PERMANENT ROSTER" : "SAVE TO PERMANENT ROSTER")
                                        .font(Theme.grotesk(14, .bold))
                                        .tracking(1.0)
                                }
                                .foregroundStyle(isArchived ? Theme.label3 : Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .wellBackground()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isArchived)
                        }
                        .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .fullScreenCover(isPresented: $showShareCards) {
            ShareCardsSheet(
                stats: stats,
                milestones: Milestones.evaluate(sessions: [session], groups: groups, mode: .coach),
                teamName: "Guest Clinic",
                orgName: "Guest Coach",
                mode: .coach
            )
        }
        .sheet(isPresented: $showExitWarning) {
            QuickClinicExitWarningSheet(attemptsCount: stats.total) {
                performArchive()
            } onDiscard: {
                showExitWarning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onDiscard()
                    dismiss()
                }
            }
            .presentationDetents([.medium, .fraction(0.5)])
        }
    }
    
    private func handleClose() {
        if stats.total > 0 && !isArchived {
            showExitWarning = true
        } else {
            dismiss()
        }
    }
    
    private func handleSave() {
        switch QuickClinicArchivePolicy.destination(purchasesAvailable: false) {
        case .archive:
            performArchive()
        }
    }
    
    private func performArchive() {
        onArchive()
        withAnimation {
            isArchived = true
        }
    }
}
