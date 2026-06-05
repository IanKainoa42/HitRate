import SwiftUI

// MARK: - Design tokens (from design handoff)

enum Theme {
    // App UI register (iOS light)
    static let appBG = Color(hex: 0xF2F2F7)
    static let surface = Color.white
    static let surface2 = Color(hex: 0xF4F4F8)
    static let label = Color.black
    static let label2 = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.6)
    static let label3 = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3)
    static let separator = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.16)
    static let fill = Color(red: 120/255, green: 120/255, blue: 128/255).opacity(0.12)
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

// MARK: - Rarity tiers (share cards; cutoffs 90 / 78 / 60)

struct Rarity {
    enum Foil { case legendary, holo, none }

    let tier: String
    let stars: Int
    let tag: Color
    let edgeColors: [Color]
    let foil: Foil
    let flavor: String

    static func of(rate: Int, noun: String = "group") -> Rarity {
        if rate >= 90 {
            return Rarity(
                tier: "LEGENDARY", stars: 3, tag: Theme.gold,
                edgeColors: [0xFFB02E, 0xFFF3B0, 0xFFD43B, 0xFF9F1C, 0xFFF6C8, 0xFFD43B, 0xFFB02E].map { Color(hex: $0) },
                foil: .legendary,
                flavor: "Untouchable. Cleanest \(noun) on the floor.")
        }
        if rate >= 78 {
            return Rarity(
                tier: "HOLO RARE", stars: 2, tag: Theme.electric,
                edgeColors: [0x00D4FF, 0x9775FA, 0xFF4D6D, 0xFFD43B, 0x51FF9F, 0x00D4FF].map { Color(hex: $0) },
                foil: .holo,
                flavor: "Locked in — hits land with room to spare.")
        }
        if rate >= 60 {
            return Rarity(
                tier: "RARE", stars: 1, tag: Color(hex: 0x5AC8FA),
                edgeColors: [0x22344E, 0x4A6A93, 0x22344E, 0x33506F, 0x22344E].map { Color(hex: $0) },
                foil: .none,
                flavor: "Solid base — a few bobbles to tighten.")
        }
        return Rarity(
            tier: "COMMON", stars: 0, tag: Theme.coralLight,
            edgeColors: [0x3A2026, 0x6A2F38, 0x3A2026].map { Color(hex: $0) },
            foil: .none,
            flavor: "Work in progress — spot the falls.")
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
