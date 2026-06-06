import SwiftUI

// MARK: - Design tokens (from design handoff)

enum Theme {
    // App UI register — court-at-night, same world as onboarding and the
    // share cards (the original iOS-light register was retired 2026-06-06;
    // views still consume only these tokens).
    static let appBG = Color(hex: 0x0A0F1E)
    static let surface = Color.white.opacity(0.06)      // glass card on navy
    static let surface2 = Color.white.opacity(0.12)
    static let label = Color.white
    static let label2 = Color.white.opacity(0.60)
    static let label3 = Color.white.opacity(0.35)
    static let separator = Color.white.opacity(0.14)
    static let fill = Color.white.opacity(0.08)
    static let accent = Color(hex: 0x007AFF)

    // Outcomes
    static let hit = Color(hex: 0x34C759)
    static let bobble = Color(hex: 0xFFCC00)
    static let buildingFall = Color(hex: 0xFF9500)
    static let majorFall = Color(hex: 0xFF3B30)

    // Brand register ("court at night")
    static let navy = Color(hex: 0x0A0F1E)
    static let coral = Color(hex: 0xFF4757)
    static let coralLight = Color(hex: 0xFF6B7A)
    static let electric = Color(hex: 0x00D4FF)
    static let gold = Color(hex: 0xFFD43B)
    static let brandGreen = Color(hex: 0x51CF66)

    // Group identity rainbow (cycled)
    static let groupRainbow: [Color] = [
        Color(hex: 0x007AFF), Color(hex: 0x34C759), Color(hex: 0xFF9500),
        Color(hex: 0xAF52DE), Color(hex: 0xFF2D55), Color(hex: 0x5AC8FA),
        Color(hex: 0xFFCC00),
    ]

    static func groupColor(_ index: Int) -> Color {
        groupRainbow[((index % groupRainbow.count) + groupRainbow.count) % groupRainbow.count]
    }

    /// Hit-rate band coloring: >=75 green · 55–74 amber · <55 red.
    /// (Distinct from rarity tiers — do not conflate.)
    static func rateColor(_ rate: Int, hasData: Bool = true) -> Color {
        guard hasData else { return label3 }
        if rate >= 75 { return hit }
        if rate >= 55 { return buildingFall }
        return majorFall
    }

    // MARK: Brand display font (Space Grotesk; bundled)

    static func grotesk(_ size: CGFloat, _ weight: GroteskWeight = .bold) -> Font {
        Font.custom(weight.postScriptName, size: size)
    }

    enum GroteskWeight {
        case regular, medium, bold
        var postScriptName: String {
            switch self {
            case .regular: "SpaceGrotesk-Regular"
            case .medium: "SpaceGrotesk-Medium"
            case .bold: "SpaceGrotesk-Bold"
            }
        }
    }
}

// MARK: - Rarity chrome (card foil/edge/tag visuals)

/// Card chrome. Since the milestone deck, rarity is set by milestone
/// *difficulty* (`Milestone.Tier`), not by hit rate — stat cards are
/// deliberately flat (`.stats`). The old rate-based tiers (90/78/60) survive
/// only as flavor text on stat cards.
struct Rarity {
    enum Foil { case legendary, holo, none }

    let tier: String
    let stars: Int
    let tag: Color
    let edgeColors: [Color]
    let foil: Foil
    let flavor: String

    static let legendaryEdge = [0xFFB02E, 0xFFF3B0, 0xFFD43B, 0xFF9F1C, 0xFFF6C8, 0xFFD43B, 0xFFB02E].map { Color(hex: $0) }
    static let holoEdge = [0x00D4FF, 0x9775FA, 0xFF4D6D, 0xFFD43B, 0x51FF9F, 0x00D4FF].map { Color(hex: $0) }
    static let navyEdge = [0x22344E, 0x4A6A93, 0x22344E, 0x33506F, 0x22344E].map { Color(hex: $0) }
    static let commonEdge = [0x3A2026, 0x6A2F38, 0x3A2026].map { Color(hex: $0) }

    /// Milestone chrome by difficulty tier (flavor lives on the milestone).
    static func of(tier: Milestone.Tier) -> Rarity {
        switch tier {
        case .legendary:
            Rarity(tier: "LEGENDARY", stars: 3, tag: Theme.gold,
                   edgeColors: legendaryEdge, foil: .legendary, flavor: "")
        case .holo:
            Rarity(tier: "HOLO RARE", stars: 2, tag: Theme.electric,
                   edgeColors: holoEdge, foil: .holo, flavor: "")
        case .rare:
            Rarity(tier: "RARE", stars: 1, tag: Color(hex: 0x5AC8FA),
                   edgeColors: navyEdge, foil: .none, flavor: "")
        case .common:
            Rarity(tier: "COMMON", stars: 0, tag: Theme.coralLight,
                   edgeColors: commonEdge, foil: .none, flavor: "")
        }
    }

    /// Flat chrome for stat cards: static navy edge, no foil, no stars — the
    /// holographic treatment is reserved for earned milestones.
    static func stats(rate: Int, noun: String = "group") -> Rarity {
        Rarity(tier: "STATS", stars: 0, tag: Color.white.opacity(0.55),
               edgeColors: navyEdge, foil: .none,
               flavor: statFlavor(rate: rate, noun: noun))
    }

    private static func statFlavor(rate: Int, noun: String) -> String {
        if rate >= 90 { return "Untouchable. Cleanest \(noun) on the floor." }
        if rate >= 78 { return "Locked in — hits land with room to spare." }
        if rate >= 60 { return "Solid base — a few bobbles to tighten." }
        return "Work in progress — spot the falls."
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

extension Date {
    /// "6:41p" style timestamp used on the session tape.
    var tapeTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        let hour = Calendar.current.component(.hour, from: self)
        return f.string(from: self) + (hour < 12 ? "a" : "p")
    }

    /// "Jun 4"
    var cardDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: self)
    }
}

/// "’25–’26" style season string (season rolls over in August).
func seasonString(for date: Date = .now) -> String {
    let cal = Calendar.current
    let y = cal.component(.year, from: date)
    let m = cal.component(.month, from: date)
    let start = m >= 8 ? y : y - 1
    let a = String(String(start).suffix(2))
    let b = String(String(start + 1).suffix(2))
    return "’\(a)–’\(b)"
}

/// Initials for a name ("Cheer Force San Diego" → "CFSD", "Senior Coed" → "SC").
func initials(of name: String, max: Int = 4) -> String {
    name.split(separator: " ").prefix(max).compactMap { $0.first.map(String.init) }.joined().uppercased()
}
