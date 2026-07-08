# QUICK CLINIC / GUEST COACH WORKFLOW DESIGN ANALYSIS

This report outlines the files, variables, and code changes needed to implement the **Quick Clinic / Guest Coach** workflow in the HitRate application.

---

## R1: Zero-Setup Entry & Smart Defaults

### Objective
Provide a frictionless entry point for guest coaches to instantly start a clinic session with default anonymous mats (defaulting to 6) and a target goal, without going through standard onboarding or manual roster creation.

### 1. Files to Create/Modify
- `HitRate/Views/Home/HomeView.swift` (Modify to add the Quick Clinic entry point)
- `HitRate/Views/QuickClinic/QuickClinicSetupSheet.swift` (Create setup modal)

### 2. Implementation Details

#### HomeView Entry Point
In `HomeView.swift`, next to the standard practice CTA, we add a secondary "QUICK CLINIC" button. Tapping it triggers a sheet presenting `QuickClinicSetupSheet`.

```swift
// In HomeView.swift
@State private var clinicSetupOpen = false
@State private var activeClinicSession: PracticeSession?
@State private var clinicContainer: ModelContainer?

// Inside body (safeAreaInset practiceCTA block)
HStack(spacing: 10) {
    practiceCTA
    
    Button {
        clinicSetupOpen = true
        hapticTrigger += 1
    } label: {
        Image(systemName: "wand.and.stars")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1.5))
            )
    }
    .buttonStyle(.plain)
}
.sheet(isPresented: $clinicSetupOpen) {
    QuickClinicSetupSheet(
        onStart: { matCount, goalRate in
            startClinic(matCount: matCount, goalRate: goalRate)
        }
    )
}
.fullScreenCover(item: $activeClinicSession) { s in
    LogView(session: s, isClinic: true, goalRate: goalRate)
        .modelContainer(clinicContainer!)
}
```

#### Smart Default Setup
The `QuickClinicSetupSheet` contains a stepper to select the number of mats (default: 6, range: 1–12) and a picker/slider for target hit rate goal (default: 80%).

```swift
// HitRate/Views/QuickClinic/QuickClinicSetupSheet.swift
import SwiftUI

struct QuickClinicSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var matCount = 6
    @State private var goalRate = 80
    
    var onStart: (Int, Int) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("GUEST COACH CLINIC")
                    .font(Theme.grotesk(10))
                    .tracking(2)
                    .foregroundStyle(Theme.label2)
                
                VStack(spacing: 8) {
                    Text("Zero-Setup Practice")
                        .font(Theme.grotesk(24, .bold))
                        .foregroundStyle(Theme.label)
                    Text("Log reps across multiple mats immediately. Roster resets on exit.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.label3)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)

                // Well for configuration parameters
                VStack(spacing: 16) {
                    Stepper(value: $matCount, in: 1...12) {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading) {
                                Text("\(matCount) Mats")
                                    .font(Theme.barlow(18, .bold))
                                Text("Anonymous logging stations")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.label3)
                            }
                        }
                    }

                    Divider().background(Theme.separator)

                    Stepper(value: $goalRate, in: 50...95, step: 5) {
                        HStack {
                            Image(systemName: "target")
                                .foregroundStyle(Theme.hit)
                            VStack(alignment: .leading) {
                                Text("Goal: \(goalRate)%")
                                    .font(Theme.barlow(18, .bold))
                                Text("Target clean-hit rate")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.label3)
                            }
                        }
                    }
                }
                .padding(16)
                .wellBackground()

                Spacer()

                Button {
                    onStart(matCount, goalRate)
                    dismiss()
                } label: {
                    Text("START CLINIC")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.accent)
                                .shadow(color: Theme.accent.opacity(0.24), radius: 8, y: 3)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(FloorBackdrop().ignoresSafeArea())
        }
    }
}
```

#### Goal Gradient Progress Pill
Inside `LogView.swift` header, if `isClinic` is true, we display the progress pill. The pill changes from red/yellow to green as the current rate approaches the goal:

```swift
// In LogView.swift
var isClinic: Bool = false
var goalRate: Int = 80

// Inside activeView header rollup, replacing static instructions:
if isClinic, let rate = rate {
    let progress = min(1.0, Double(rate) / Double(goalRate))
    HStack(spacing: 8) {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.well)
                Capsule()
                    .fill(LinearGradient(
                        colors: [Theme.rateColor(rate), Theme.hit],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 8)
        Text("\(rate)% / \(goalRate)% GOAL")
            .font(Theme.barlow(11, .bold))
            .foregroundStyle(Theme.rateColor(rate))
    }
    .frame(height: 12)
}
```

---

## R2: Ephemeral Roster Isolation & In-Place Personalization

### Objective
Log attempts into an in-memory session isolated from SQLite/SwiftData storage, ensuring no milestone badges are prematurely unlocked. Allow in-place editing of mat identifiers and outcome classifications directly from the logging matrix (`logGrid`).

### 1. Files to Create/Modify
- `HitRate/Views/Log/LogView.swift` (Modify to support environment container injection, inline rename, and custom clinic outcome headers)
- `HitRate/Models/Models.swift` (No modification required, leverages in-memory container)

### 2. Implementation Details

#### In-Memory Container Isolation
When starting the clinic in `HomeView.swift`, we initialize an ephemeral `ModelContainer`. This encapsulates all writes and isolates the clinic roster:

```swift
private func startClinic(matCount: Int, goalRate: Int) {
    do {
        let schema = Schema([Team.self, StuntGroup.self, PracticeSession.self, Attempt.self, UnlockedMilestone.self, CustomOutcome.self, CustomTally.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        
        let context = container.mainContext
        
        // Seed clinic team & groups
        let clinicTeam = Team(name: "Guest Clinic", orderIndex: 0)
        context.insert(clinicTeam)
        
        for i in 1...matCount {
            let mat = StuntGroup(name: "Mat \(i)", number: i, orderIndex: i - 1, kind: .stunt)
            mat.team = clinicTeam
            context.insert(mat)
        }
        
        let clinicSession = PracticeSession()
        context.insert(clinicSession)
        
        try context.save()
        
        self.clinicContainer = container
        self.activeClinicSession = clinicSession
    } catch {
        print("Failed to spin up ephemeral clinic store: \(error)")
    }
}
```
*Note*: Standard SwiftData queries on the home dashboard will read from the default on-disk SQLite container, keeping the clinic attempts completely isolated.

#### In-Place Personalization in `logGrid`
In `LogView.swift`, we update `logGrid` to show an inline text editor for mat labels when `isClinic` is active:

```swift
// Inside logGrid Row Label (LogView.swift lines 367-389)
HStack(spacing: 6) {
    Text("\(g.number)")
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .frame(width: 22, height: 22)
        .background(g.color)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    
    if isClinic {
        // Direct, non-laggy inline rename field
        RenameField(prompt: "Mat \(g.number)", value: g.name) { newName in
            g.name = newName.trimmingCharacters(in: .whitespaces)
            try? context.save()
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(Theme.label)
        .frame(width: 80)
    } else {
        Text(g.name)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.label)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
    
    flameBadge(streakN)
}
```

#### Columns / Outcomes Personalization
Coaches want to rename outcomes (e.g. rename bobble to "Step Out") for the entire floor at once. We can add a "Customize Outcomes" button in the matrix header:

```swift
// In LogView.swift under matrix headers (line 356)
if isClinic {
    Button {
        // Edit first mat's outcomes, then copy definitions to all other mats on completion
        showOutcomesSheet = true
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "pencil.circle")
            Text("Customize Outcome Labels")
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Theme.accent)
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $showOutcomesSheet) {
        if let firstMat = groups.first {
            SkillOutcomesEditor(group: firstMat) {
                // Copy definitions to all mats
                for mat in groups {
                    mat.setOutcomeDefs(firstMat.outcomeDefs)
                }
                try? context.save()
            }
        }
    }
}
```

---

## R3: Reciprocity Wrap-Up Sheet & Foil Share Cards

### Objective
Present the guest coach with a styled, comprehensive wrap-up dashboard at the end of the session containing the Canvas timeline tape and a horizontal carousel of 6 holographic mat cards. Allow completely free exports to drive organic network sharing.

### 1. Files to Create/Modify
- `HitRate/Views/QuickClinic/QuickClinicSummaryView.swift` (Create wrap-up summary page)
- `HitRate/Views/Share/ShareCardsSheet.swift` (Adapt/reuse card deck carousel for clinic mats)

### 2. Implementation Details

#### QuickClinicSummaryView Setup
When the user ends the practice, we show the wrap-up summary sheet in a cover.

```swift
// In LogView.swift, inside the "END" action:
if isClinic {
    // Navigate to Summary instead of immediate dismissal
    showSummaryCover = true
} else {
    // Normal SQLite Practice Session End
}
```

The summary view leverages existing views (`SessionTapeCard` and `HoloCardView`):

```swift
// HitRate/Views/QuickClinic/QuickClinicSummaryView.swift
import SwiftUI
import SwiftData

struct QuickClinicSummaryView: View {
    let session: PracticeSession
    let mats: [StuntGroup]
    let goalRate: Int
    var onDismiss: () -> Void
    var onSave: () -> Void // Triggers premium copy
    
    @State private var activeIndex: Int? = 0
    @State private var shareOpen = false
    
    private var stats: FloorStats {
        StatsEngine.compute(sessions: [session], groups: mats, timeframe: .all)
    }

    var body: some View {
        ZStack {
            CourtBackdrop().ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("CLINIC WRAP-UP")
                        .font(Theme.grotesk(14, .bold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Button {
                        onDismiss() // Triggers loss aversion sheet
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.label2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                ScrollView {
                    VStack(spacing: 16) {
                        // Summary Stats
                        VStack(spacing: 8) {
                            Text("\(stats.rate)%")
                                .font(Theme.grotesk(48, .bold))
                                .foregroundStyle(Theme.rateColor(stats.rate))
                            Text("OVERALL CLEAN HITS")
                                .font(Theme.grotesk(10))
                                .foregroundStyle(Theme.label2)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .wellBackground()

                        // Session Tape
                        if let snapshot = stats.latest {
                            SessionTapeCard(snapshot: snapshot, kind: .stunt)
                        }

                        // Mat Leaderboard list
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MAT COMPARISON")
                                .font(Theme.grotesk(10))
                                .foregroundStyle(Theme.label3)
                            
                            ForEach(stats.ranked) { g in
                                HStack {
                                    Text(g.name).font(.system(size: 14, weight: .bold))
                                    Spacer()
                                    Text("\(g.rate)%").font(Theme.barlow(16, .semibold))
                                        .foregroundStyle(Theme.rateColor(g.rate))
                                }
                            }
                        }
                        .padding(16)
                        .wellBackground()

                        // Card Preview Carousel Launcher
                        Button {
                            shareOpen = true
                        } label: {
                            Text("EXPORT HOLOGRAPHIC MAT CARDS")
                                .font(Theme.grotesk(14, .bold))
                                .foregroundStyle(Theme.accentText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }

                // CTA to save permanently
                Button(action: onSave) {
                    Text("SAVE TO PERMANENT ROSTER")
                        .font(Theme.grotesk(16, .bold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [Theme.electric, Theme.accent], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .fullScreenCover(isPresented: $shareOpen) {
            ShareCardsSheet(
                stats: stats,
                milestones: [], // Milestones are omitted for temporary sessions
                teamName: "Clinic Summary",
                orgName: "Guest Clinic",
                mode: .coach
            )
        }
    }
}
```

---

## R4: Ethical Loss Aversion & Anchored Pro Monetization

### Objective
Gently warn the user when trying to discard the clinic session ("loss aversion"). Present a beautifully structured premium paywall featuring price anchoring options, and cleanly handle the migration of the ephemeral in-memory session to SQLite upon payment.

### 1. Files to Create/Modify
- `HitRate/Views/QuickClinic/QuickClinicExitWarningSheet.swift` (Exit dialog sheet)
- `HitRate/Views/QuickClinic/PremiumPaywallSheet.swift` (Paywall sheet with price anchoring)
- `HitRate/Views/QuickClinic/QuickClinicSummaryView.swift` (Hook dismiss warning and save buttons)

### 2. Implementation Details

#### Exit Loss-Framing Sheet
If the user taps the dismiss button in the Wrap-up Summary, we present a warning emphasizing the value that will be lost:

```swift
// HitRate/Views/QuickClinic/QuickClinicExitWarningSheet.swift
import SwiftUI

struct QuickClinicExitWarningSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onDiscard: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.majorFall)
            
            Text("Discard Clinic Session?")
                .font(Theme.grotesk(20, .bold))
            
            Text("If you close this clinic summary now, all Mat cards, counts, and performance tape configurations will be deleted forever.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                Button {
                    onSave()
                    dismiss()
                } label: {
                    Text("SAVE TO PERMANENT ROSTER")
                        .font(Theme.grotesk(14, .bold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    onDiscard()
                    dismiss()
                } label: {
                    Text("Erase & Discard")
                        .font(Theme.grotesk(13))
                        .foregroundStyle(Theme.majorFall)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .padding(24)
        .wellBackground()
        .presentationDetents([.fraction(0.4)])
    }
}
```

#### Price-Anchoring Paywall View
Coaches are shown a subscription screen with a strong visual tier anchor:
- **Director Cloud (Recommended)**: $99.99/year ($8.33/mo)
- **Coach Pro**: $9.99/month

```swift
// HitRate/Views/QuickClinic/PremiumPaywallSheet.swift
import SwiftUI

struct PremiumPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onUpgradeSuccess: () -> Void

    var body: some View {
        ZStack {
            CourtBackdrop().ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("UPGRADE TO HITRATE PRO")
                    .font(Theme.grotesk(11))
                    .tracking(2)
                    .foregroundStyle(Theme.accent)

                Text("Save Your Clinic Analytics")
                    .font(Theme.grotesk(24, .bold))
                    .multilineTextAlignment(.center)

                // Comparison Anchor Grid
                VStack(spacing: 12) {
                    // Anchor Choice 1: Director Cloud
                    pricingTierCard(
                        title: "DIRECTOR CLOUD",
                        price: "$99.99 / year",
                        monthlyEquivalent: "$8.33 / month equivalent",
                        features: ["Unlimited Teams", "Multi-Coach Cloud Synced Roster", "Export Custom Mats to HTML/PDF", "CSV Data backups"],
                        badge: "BEST VALUE (SAVE 30%)",
                        color: Theme.electric,
                        isSelected: true
                    )
                    
                    // Anchor Choice 2: Coach Pro
                    pricingTierCard(
                        title: "COACH PRO",
                        price: "$9.99 / month",
                        monthlyEquivalent: "$9.99 / month",
                        features: ["Up to 3 Active Teams", "Mat Summary Cards Export"],
                        badge: nil,
                        color: Theme.well,
                        isSelected: false
                    )
                }
                .padding(.horizontal, 16)

                Spacer()

                Button {
                    // Simulate payment success
                    onUpgradeSuccess()
                    dismiss()
                } label: {
                    Text("UNLOCK PRO FEATURES")
                        .font(Theme.grotesk(16, .bold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                
                Button("Restore Purchase") {
                    // Restore action
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.label3)
                .padding(.bottom, 12)
            }
            .padding(.top, 24)
        }
    }
}
```

#### Archival logic (In-Memory -> SQLite SQLite Migration)
When upgrading, we copy the data from the ephemeral context to the main app context.

```swift
func archiveClinicSession(clinicContext: ModelContext, mainContext: ModelContext) {
    // 1. Fetch ephemeral Team, Groups, Attempts, and Tallies from clinic store
    let teamFetch = FetchDescriptor<Team>()
    guard let clinicTeam = try? clinicContext.fetch(teamFetch).first else { return }
    
    // 2. Create the Team in the SQLite main context
    let mainTeam = Team(name: clinicTeam.name + " (Saved)", orderIndex: 0)
    mainContext.insert(mainTeam)
    
    // 3. Map Groups from Clinic to Main Context
    var groupMapping: [PersistentIdentifier: StuntGroup] = [:]
    
    for clinicGroup in clinicTeam.groups {
        let mainGroup = StuntGroup(
            name: clinicGroup.name,
            number: clinicGroup.number,
            orderIndex: clinicGroup.orderIndex,
            kind: clinicGroup.kind
        )
        mainGroup.team = mainTeam
        mainGroup.category = clinicGroup.category
        mainGroup.setOutcomeDefs(clinicGroup.outcomeDefs)
        mainContext.insert(mainGroup)
        
        groupMapping[clinicGroup.persistentModelID] = mainGroup
    }
    
    // 4. Migrate Sessions and Attempts
    let sessionFetch = FetchDescriptor<PracticeSession>()
    if let clinicSessions = try? clinicContext.fetch(sessionFetch) {
        for clinicSession in clinicSessions {
            let mainSession = PracticeSession(startedAt: clinicSession.startedAt)
            mainSession.endedAt = clinicSession.endedAt
            mainContext.insert(mainSession)
            
            for clinicAttempt in clinicSession.attempts {
                guard let newGroup = groupMapping[clinicAttempt.group?.persistentModelID ?? clinicAttempt.persistentModelID] else { continue }
                
                let mainAttempt = Attempt(
                    slot: clinicAttempt.outcomeRaw,
                    group: newGroup,
                    session: mainSession,
                    timestamp: clinicAttempt.timestamp,
                    waveID: clinicAttempt.waveID
                )
                mainContext.insert(mainAttempt)
            }
        }
    }
    
    // 5. Commit SQLite changes & sync lifetime milestones
    try? mainContext.save()
    
    // Trigger milestone evaluation on standard container
    let mainGroups = try? mainContext.fetch(FetchDescriptor<StuntGroup>())
    let mainSessions = try? mainContext.fetch(FetchDescriptor<PracticeSession>())
    let mainUnlocked = try? mainContext.fetch(FetchDescriptor<UnlockedMilestone>())
    
    if let mainSessions, let mainGroups, let mainUnlocked {
        Milestones.sync(
            sessions: mainSessions,
            groups: mainGroups,
            mode: .coach,
            unlocked: mainUnlocked,
            context: mainContext
        )
    }
}
```

---

## 3. Verification Method

To verify the integration, perform the following validation protocol:
1. Verify database queries stay scoped by starting a Quick Clinic, logging several attempts, and returning to standard HomeView (overall metrics should read `0 reps` with zero side-effects in standard views).
2. Trigger the exit modal and select **Erase & Discard**. Verify the in-memory `ModelContainer` is deallocated and data does not persist in the next clinic launch.
3. Select **Save to Roster & Reports**, simulate the Pro purchase, and verify the team and clinic practice session appear on the Home dashboard with correct Canvas tape outcomes and calculated Milestones cards.
