import SwiftUI
import UIKit

/// DEBUG REVIEW HARNESS — renders every share-card variant (stat cards across
/// flavor bands, all 13 milestones earned+locked, pucks) to Documents/card-catalog/
/// when the app is launched with `--render-cards`. Not wired to any UI.
@MainActor
enum CardCatalogRenderer {

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--render-cards") else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("card-catalog", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        renderAll(to: dir)
        print("CARD_CATALOG_DONE \(dir.path)")
    }

    // MARK: Catalog

    private static var statCards: [(slug: String, spec: CardSpec)] {
        [
            // 99 band — "Untouchable"
            ("stat-team-athlete-99", CardSpec(
                id: 0, kicker: "ALL SKILLS", name: "Kainoa", badge: "★",
                color: Theme.electric, rate: 99, counts: [99, 1, 0, 0],
                total: 100, delta: 4, flavorNoun: "skill", kind: .stunt)),
            // 95 band — "Locked in"
            ("stat-team-coach-96", CardSpec(
                id: 0, kicker: "FULL FLOOR", name: "CheerForce Black", badge: "★",
                color: Theme.electric, rate: 96, counts: [115, 3, 1, 1],
                total: 120, delta: -1, flavorNoun: "group", kind: .stunt)),
            // 90 band — "not the problem / PS"
            ("stat-skill-92", CardSpec(
                id: 1, kicker: "SKILL 1", name: "Lib Heel Stretch", badge: "1",
                color: Theme.groupColor(0), rate: 92, counts: [23, 1, 1, 0],
                total: 25, delta: 2, flavorNoun: "skill", kind: .stunt)),
            // 80 band, even seed — "stay up / lost points"
            ("stat-group-84-stayup", CardSpec(
                id: 2, kicker: "GROUP 1", name: "Group 1", badge: "1",
                color: Theme.groupColor(1), rate: 84, counts: [21, 2, 1, 1],
                total: 25, delta: 6, flavorNoun: "group", kind: .stunt)),
            // 80 band, odd seed — "could still do better"
            ("stat-group-84-better", CardSpec(
                id: 3, kicker: "GROUP 2", name: "Group 2", badge: "2",
                color: Theme.groupColor(2), rate: 84, counts: [21, 2, 1, 1],
                total: 25, delta: nil, flavorNoun: "group", kind: .stunt)),
            // 60 band — "so close / breakthrough"
            ("stat-skill-tumbling-67", CardSpec(
                id: 4, kicker: "SKILL 3", name: "Full", badge: "3",
                color: Theme.groupColor(3), rate: 67, counts: [12, 3, 2, 1],
                total: 18, delta: nil, flavorNoun: "skill", kind: .tumbling)),
            // floor band, stunt + even seed — flyer line
            ("stat-group-48-flyer", CardSpec(
                id: 5, kicker: "GROUP 5", name: "Group 5", badge: "5",
                color: Theme.groupColor(4), rate: 48, counts: [10, 4, 4, 3],
                total: 21, delta: -9, flavorNoun: "group", kind: .stunt)),
            // floor band, stunt + odd seed — pouting line
            ("stat-group-52-pouting", CardSpec(
                id: 6, kicker: "GROUP 4", name: "Group 4", badge: "4",
                color: Theme.groupColor(5), rate: 52, counts: [11, 4, 3, 3],
                total: 21, delta: -2, flavorNoun: "group", kind: .stunt)),
            // floor band, tumbling + odd seed — pouting line
            ("stat-skill-tumbling-40-pouting", CardSpec(
                id: 7, kicker: "SKILL 6", name: "Standing Full", badge: "6",
                color: Theme.groupColor(6), rate: 40, counts: [6, 4, 3, 2],
                total: 15, delta: nil, flavorNoun: "skill", kind: .tumbling)),
            // floor band, tumbling + even seed — tryouts line
            ("stat-skill-tumbling-45-tryouts", CardSpec(
                id: 8, kicker: "SKILL 7", name: "Back Tuck", badge: "7",
                color: Theme.groupColor(7), rate: 45, counts: [9, 5, 4, 2],
                total: 20, delta: -4, flavorNoun: "skill", kind: .tumbling)),
        ]
    }

    /// Every milestone type with engine-accurate copy, in earned and locked form.
    private static var milestones: [(slug: String, m: Milestone)] {
        [
            ("ms-reps10-first-ten", Milestone(
                id: "reps10", kicker: "MILESTONE", name: "First Ten",
                icon: "checkmark.seal.fill", tier: .common,
                flavor: "Okay. You just downloaded the app.",
                earned: true, progress: 1, detail: "12 reps logged")),
            ("ms-reps10-first-ten-locked", Milestone(
                id: "reps10", kicker: "MILESTONE", name: "First Ten",
                icon: "checkmark.seal.fill", tier: .common,
                flavor: "Okay. You just downloaded the app.",
                earned: false, progress: 0.7, detail: "7 / 10 reps")),
            ("ms-reps100-century-club", Milestone(
                id: "reps100", kicker: "MILESTONE", name: "Century Club",
                icon: "rosette", tier: .rare,
                flavor: "Getting pretty serious.",
                earned: true, progress: 1, detail: "171 reps logged")),
            ("ms-reps100-century-club-locked", Milestone(
                id: "reps100", kicker: "MILESTONE", name: "Century Club",
                icon: "rosette", tier: .rare,
                flavor: "Getting pretty serious.",
                earned: false, progress: 0.88, detail: "88 / 100 reps")),
            ("ms-reps500-grinder", Milestone(
                id: "reps500", kicker: "MILESTONE", name: "Grinder",
                icon: "flame.fill", tier: .holo,
                flavor: "Cheerleading must be your hobby.",
                earned: true, progress: 1, detail: "523 reps logged")),
            ("ms-reps500-grinder-locked", Milestone(
                id: "reps500", kicker: "MILESTONE", name: "Grinder",
                icon: "flame.fill", tier: .holo,
                flavor: "Cheerleading must be your hobby.",
                earned: false, progress: 0.824, detail: "412 / 500 reps")),
            ("ms-reps1000-four-digits", Milestone(
                id: "reps1000", kicker: "MILESTONE", name: "Four Digits",
                icon: "crown.fill", tier: .legendary,
                flavor: "Thank you for your sacrifice.",
                earned: true, progress: 1, detail: "1042 reps logged")),
            ("ms-reps1000-four-digits-locked", Milestone(
                id: "reps1000", kicker: "MILESTONE", name: "Four Digits",
                icon: "crown.fill", tier: .legendary,
                flavor: "Thank you for your sacrifice.",
                earned: false, progress: 0.523, detail: "523 / 1000 reps")),
            ("ms-streak5-high-five", Milestone(
                id: "streak5", kicker: "MILESTONE", name: "High Five",
                icon: "hand.raised.fill", tier: .common,
                flavor: "Five in a row. Don't let it go to your head.",
                earned: true, progress: 1, detail: "7 hits in a row")),
            ("ms-streak5-high-five-locked", Milestone(
                id: "streak5", kicker: "MILESTONE", name: "High Five",
                icon: "hand.raised.fill", tier: .common,
                flavor: "Five in a row. Don't let it go to your head.",
                earned: false, progress: 0.6, detail: "best streak 3 / 5")),
            ("ms-streak10-hot-hand-coach", Milestone(
                id: "streak10", kicker: "MILESTONE", name: "Hot Hand",
                icon: "bolt.fill", tier: .rare,
                flavor: "Pure luck. If you're a coach, this doesn't count.",
                earned: true, progress: 1, detail: "12 hits in a row")),
            ("ms-streak25-untouchable-alt", Milestone(
                id: "streak25", kicker: "MILESTONE", name: "Untouchable",
                icon: "sparkles", tier: .legendary,
                flavor: "You should probably start working on other skills.",
                earned: true, progress: 1, detail: "26 hits in a row")),
            ("ms-streak10-hot-hand", Milestone(
                id: "streak10", kicker: "MILESTONE", name: "Hot Hand",
                icon: "bolt.fill", tier: .rare,
                flavor: "Pure luck. The owner is getting something wrong.",
                earned: true, progress: 1, detail: "12 hits in a row")),
            ("ms-streak10-hot-hand-locked", Milestone(
                id: "streak10", kicker: "MILESTONE", name: "Hot Hand",
                icon: "bolt.fill", tier: .rare,
                flavor: "Pure luck. The owner is getting something wrong.",
                earned: false, progress: 0.6, detail: "best streak 6 / 10")),
            ("ms-streak25-untouchable", Milestone(
                id: "streak25", kicker: "MILESTONE", name: "Untouchable",
                icon: "sparkles", tier: .legendary,
                flavor: "Twenty-five in a row. Nobody's touching that.",
                earned: true, progress: 1, detail: "26 hits in a row")),
            ("ms-streak25-untouchable-locked", Milestone(
                id: "streak25", kicker: "MILESTONE", name: "Untouchable",
                icon: "sparkles", tier: .legendary,
                flavor: "Twenty-five in a row. Nobody's touching that.",
                earned: false, progress: 0.48, detail: "best streak 12 / 25")),
            ("ms-session90-dialed-in", Milestone(
                id: "session90", kicker: "MILESTONE", name: "Dialed In",
                icon: "scope", tier: .holo,
                flavor: "90+ on real volume. That's not luck twice.",
                earned: true, progress: 1, detail: "93% · 24 reps")),
            ("ms-session90-dialed-in-locked", Milestone(
                id: "session90", kicker: "MILESTONE", name: "Dialed In",
                icon: "scope", tier: .holo,
                flavor: "90+ on real volume. That's not luck twice.",
                earned: false, progress: 0.91, detail: "best 20-rep session: 82%")),
            ("ms-perfect-practice", Milestone(
                id: "perfect", kicker: "MILESTONE", name: "Perfect Practice",
                icon: "trophy.fill", tier: .legendary,
                flavor: "Not one miss all practice. Frame this one.",
                earned: true, progress: 1, detail: "100% · 18 reps")),
            ("ms-perfect-practice-locked", Milestone(
                id: "perfect", kicker: "MILESTONE", name: "Perfect Practice",
                icon: "trophy.fill", tier: .legendary,
                flavor: "Not one miss all practice. Frame this one.",
                earned: false, progress: 0.94, detail: "best 15-rep session: 94%")),
            ("ms-mastery-earned", Milestone(
                id: "mastery-1", kicker: "MILESTONE", name: "Mastered: Lib Heel Stretch",
                icon: "star.circle.fill", tier: .legendary,
                flavor: "50+ reps at 90+. This skill is automatic now.",
                earned: true, progress: 1, detail: "61 reps @ 92%")),
            ("ms-mastery-teaser-locked", Milestone(
                id: "mastery-teaser", kicker: "MILESTONE", name: "Mastery",
                icon: "star.circle.fill", tier: .legendary,
                flavor: "Own one skill: 50 reps at 90 percent.",
                earned: false, progress: 0.665, detail: "Lib Heel Stretch: 34/50 reps @ 88%")),
            ("ms-falls25-gravity-check", Milestone(
                id: "falls25", kicker: "DUBIOUS HONOR", name: "Gravity Check",
                icon: "arrow.down.circle.fill", tier: .common,
                flavor: "Twenty-five falls survived. The mat knows your name.",
                earned: true, progress: 1, detail: "31 falls survived")),
            ("ms-falls25-gravity-check-locked", Milestone(
                id: "falls25", kicker: "DUBIOUS HONOR", name: "Gravity Check",
                icon: "arrow.down.circle.fill", tier: .common,
                flavor: "Twenty-five falls survived. The mat knows your name.",
                earned: false, progress: 0.56, detail: "14 / 25 falls")),
            ("ms-coldstreak", Milestone(
                id: "coldstreak", kicker: "DUBIOUS HONOR", name: "Cold Streak",
                icon: "snowflake", tier: .rare,
                flavor: "Five misses in a row. Somebody check the thermostat.",
                earned: true, progress: 1, detail: "6 misses in a row")),
            ("ms-coldstreak-locked", Milestone(
                id: "coldstreak", kicker: "DUBIOUS HONOR", name: "Cold Streak",
                icon: "snowflake", tier: .rare,
                flavor: "Five misses in a row. Somebody check the thermostat.",
                earned: false, progress: 0.6, detail: "worst run 3 / 5 misses")),
            ("ms-demolition-day", Milestone(
                id: "demolition", kicker: "DUBIOUS HONOR", name: "Demolition Day",
                icon: "hammer.fill", tier: .holo,
                flavor: "Eight falls in one practice. Total demolition.",
                earned: true, progress: 1, detail: "9 falls in one session")),
            ("ms-demolition-day-locked", Milestone(
                id: "demolition", kicker: "DUBIOUS HONOR", name: "Demolition Day",
                icon: "hammer.fill", tier: .holo,
                flavor: "Eight falls in one practice. Total demolition.",
                earned: false, progress: 0.625, detail: "worst session: 5 / 8 falls")),
        ]
    }

    // MARK: Render

    private static func renderAll(to dir: URL) {
        let org = "CheerForce San Diego"
        let stats = statCards
        let stones = milestones
        let count = stats.count + stones.count

        var index = 0
        for (slug, spec) in stats {
            let card = DeckCard(id: index, content: .stats(spec))
            write(cardImage(card, index: index, count: count, org: org),
                  to: dir, name: String(format: "%02d_%@", index, slug))
            index += 1
        }
        for (slug, m) in stones {
            let card = DeckCard(id: index, content: .milestone(m))
            write(cardImage(card, index: index, count: count, org: org),
                  to: dir, name: String(format: "%02d_%@", index, slug))
            index += 1
        }
        // Pucks — one per earned milestone type
        for (slug, m) in stones where m.earned {
            write(puckImage(m, org: org), to: dir, name: "puck_\(slug)")
        }
    }

    private static func cardImage(_ card: DeckCard, index: Int, count: Int,
                                  org: String) -> UIImage? {
        let renderer = ImageRenderer(
            content: HoloCardView(card: card, index: index, count: count,
                                  orgName: org, isSnapshot: true)
                .frame(width: 290, height: 430))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 290, height: 430)
        return renderer.uiImage
    }

    private static func puckImage(_ m: Milestone, org: String) -> UIImage? {
        let renderer = ImageRenderer(
            content: PuckView(milestone: m, orgName: org)
                .frame(width: 240, height: 240))
        renderer.scale = 3
        renderer.isOpaque = false
        renderer.proposedSize = ProposedViewSize(width: 240, height: 240)
        return renderer.uiImage
    }

    private static func write(_ image: UIImage?, to dir: URL, name: String) {
        guard let data = image?.pngData() else {
            print("CARD_CATALOG_FAIL \(name)")
            return
        }
        try? data.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
