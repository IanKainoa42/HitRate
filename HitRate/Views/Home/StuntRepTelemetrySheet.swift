import SwiftUI

/// Detailed biomechanical inspection sheet for an individual stunt attempt scored by StuntScope.
/// Renders in the "training floor" register (graphite backdrop, inset wells, Barlow numerals,
/// rate band coloring, green signal accent).
struct StuntRepTelemetrySheet: View {
    let attempt: Attempt
    let subjects: [Subject]
    @Environment(\.dismiss) private var dismiss

    private var onBase: Int { attempt.onBasePercent ?? 0 }
    private var hold: Double { attempt.holdSeconds ?? 0 }
    private var wobbles: Int { attempt.wobbleCount ?? 0 }
    private var worstWobble: Double? { attempt.worstWobbleSecond }
    private var flights: [Double] { attempt.flightSeconds }

    private var isRockSolid: Bool {
        attempt.isHitRep && onBase >= 75 && wobbles == 0
    }

    private var athleteLookup: [UUID: String] {
        Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0.name) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    headerCard
                    comboStatusBanner
                    telemetryGrid
                    if !attempt.roles.isEmpty || !attempt.athleteIDs.isEmpty {
                        rolesCard
                    }
                    scopeFootnote
                }
                .padding(16)
            }
            .background(FloorBackdrop().ignoresSafeArea())
            .navigationTitle("StuntScope Telemetry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        FeedCard {
            HStack(alignment: .top, spacing: 12) {
                if let group = attempt.group {
                    Text("\(group.number)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.groupColor((group.number - 1) % Theme.groupRainbow.count))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(attempt.group?.name ?? "Stunt Attempt")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.label)

                    HStack(spacing: 6) {
                        Text(attempt.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.label3)
                        Text("·")
                            .foregroundStyle(Theme.label3)
                        Text("StuntScope verified")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(attempt.outcome.color)
                        .frame(width: 8, height: 8)
                    Text(attempt.outcome.label(.stunt))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.label)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .wellBackground(cornerRadius: 6)
            }
        }
    }

    // MARK: - Combo Banner

    private var comboStatusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: isRockSolid ? "bolt.badge.checkmark.fill" : "video.badge.waveform.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isRockSolid ? Theme.accent : (wobbles > 0 ? Theme.buildingFall : Theme.label2))

            VStack(alignment: .leading, spacing: 2) {
                Text(isRockSolid ? "ROCK SOLID COMBO" : (attempt.isHitRep ? "CLEAN HIT · VIDEO SCORED" : "TELEMETRY CAPTURED"))
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(isRockSolid ? Theme.accent : Theme.label)

                Text(comboSubline)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.label2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .wellBackground(cornerRadius: 10)
    }

    private var comboSubline: String {
        if isRockSolid {
            return "Held over bases with zero wobbles. The ultimate execution mark."
        } else if wobbles > 0 {
            return "Completed with \(wobbles) stability excursion\(wobbles == 1 ? "" : "s"). Bases saved the line."
        } else {
            return "Center of mass and base support span tracked at high-speed."
        }
    }

    // MARK: - Telemetry Grid

    private var telemetryGrid: some View {
        VStack(spacing: 10) {
            // Stability Gauge Well
            FeedCard {
                CardHead("ON-BASE STABILITY") {
                    Text("\(onBase)% of hold")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.rateColor(onBase))
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(onBase)")
                        .font(Theme.barlow(48, .extrabold))
                        .foregroundStyle(Theme.rateColor(onBase))
                    Text("%")
                        .font(Theme.barlow(22, .bold))
                        .foregroundStyle(Theme.label2)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(stabilityLevelText)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.rateColor(onBase))
                        Text("Center of mass inside base span")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Theme.label3)
                    }
                }
                .padding(.bottom, 6)

                // Visual COM Balance Track
                GeometryReader { geo in
                    let w = geo.size.width
                    let fillW = max(0, min(w, w * CGFloat(onBase) / 100))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Theme.rateColor(onBase))
                            .frame(width: fillW)
                    }
                }
                .frame(height: 6)
                .padding(.bottom, 4)
            }

            // Hold & Wobble & Flight Bento
            HStack(spacing: 10) {
                // Hold Duration
                VStack(alignment: .leading, spacing: 4) {
                    Text("HOLD DURATION")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Theme.label3)

                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", hold))
                            .font(Theme.barlow(28, .extrabold))
                            .foregroundStyle(Theme.label)
                        Text("s")
                            .font(Theme.barlow(14, .bold))
                            .foregroundStyle(Theme.label2)
                    }

                    Text("Active base support")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.label3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wellBackground(cornerRadius: 10)

                // Wobbles
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXCURSIONS")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Theme.label3)

                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(wobbles)")
                            .font(Theme.barlow(28, .extrabold))
                            .foregroundStyle(wobbles == 0 ? Theme.accent : Theme.buildingFall)
                        Text(wobbles == 1 ? "wobble" : "wobbles")
                            .font(Theme.barlow(14, .bold))
                            .foregroundStyle(Theme.label2)
                    }

                    if let worst = worstWobble {
                        Text("Worst at \(String(format: "%.1f", worst))s")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.label3)
                    } else {
                        Text("Rock solid hold")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.label3)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wellBackground(cornerRadius: 10)
            }

            // Flight Airtime (if toss / basket occurred)
            if let maxFlight = flights.max(), maxFlight > 0 {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.and.line.horizontal.and.arrow.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TOSS RELEASE HANGTIME")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(Theme.label3)

                        Text(flights.count == 1
                             ? "\(String(format: "%.2f", maxFlight))s airborne"
                             : "\(flights.count) releases · Longest \(String(format: "%.2f", maxFlight))s")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.label)
                    }

                    Spacer()

                    Text("\(String(format: "%.2f", maxFlight))s")
                        .font(Theme.barlow(22, .extrabold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(12)
                .wellBackground(cornerRadius: 10)
            }
        }
    }

    private var stabilityLevelText: String {
        if onBase >= 85 { return "Rock Solid" }
        if onBase >= 70 { return "Steady Hold" }
        if onBase >= 55 { return "Moderate Sway" }
        return "Severe Excursion"
    }

    // MARK: - Roles Bento

    private var rolesCard: some View {
        FeedCard {
            CardHead("STUNT GROUP ROSTER") {
                Text("4-position tag")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.label3)
            }

            VStack(spacing: 8) {
                ForEach(StuntRole.allCases) { role in
                    HStack(spacing: 10) {
                        Text(role.label.uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(Theme.label3)
                            .frame(width: 80, alignment: .leading)

                        if let athleteID = attempt.roles[role], let name = athleteLookup[athleteID] {
                            Text(name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.label)
                        } else {
                            Text("—")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.label3)
                        }

                        Spacer()
                    }
                    if role != StuntRole.allCases.last {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: - Footnote

    private var scopeFootnote: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
            Text("Computed by StuntScope motion engine. Synchronized across HitRate shared storage.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.label3)
        }
        .padding(.vertical, 8)
    }
}
