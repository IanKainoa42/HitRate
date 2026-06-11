import SwiftUI

// MARK: - Design tokens (from design handoff)

enum Theme {
    // App UI register — "training floor" (2026-06-07): lifted graphite with a
    // tight diagonal hairline, inset wells, chalk text, ONE green signal
    // accent. Replaces the court-at-night glass app UI (which lives on for
    // onboarding + share cards). Views still consume only these tokens.
    static let appBG = Color(hex: 0x141820)             // graphite/navy floor (FloorBackdrop adds gradient + hairline)
    static let appBGTop = Color(hex: 0x1A202A)
    static let appBGBottom = Color(hex: 0x090D15)
    static let iconTile = Color(hex: 0x101621)          // app-icon badge face
    static let iconTileEdge = Color(hex: 0x2A3445)      // app-icon bevel outline
    static let well = Color(hex: 0x0C1119)              // recessed module surface
    static let surface = Color(hex: 0x101114)           // legacy alias — wells
    static let surface2 = Color(hex: 0x18202B)          // raised chip on a well
    static let label = Color(hex: 0xF3F4F1)             // chalk / icon white
    static let label2 = Color(hex: 0x8D8B86)            // warm gray
    static let label3 = Color(hex: 0x5C5B57)
    static let separator = Color(hex: 0x26303D)         // hairline inside a well
    static let fill = Color(hex: 0x151B24)              // track behind bars
    static let accent = Color(hex: 0x29F06D)            // the green signal — go/hit/improving
    static let accentText = Color(hex: 0x0E1511)        // dark ink on green chips/CTA

    // Outcomes (severity hues tuned to the graphite register)
    static let hit = Color(hex: 0x34D26A)
    static let bobble = Color(hex: 0xE8C94B)
    static let buildingFall = Color(hex: 0xFF9A3D)
    static let majorFall = Color(hex: 0xFF6B57)

    // Brand register ("court at night")
    static let navy = Color(hex: 0x0A0F1E)
    static let coral = Color(hex: 0xFF4757)
    static let coralLight = Color(hex: 0xFF6B7A)
    static let electric = Color(hex: 0x00D4FF)
    static let gold = Color(hex: 0xFFD43B)
    static let brandGreen = Color(hex: 0x51CF66)

    // Hot-streak indicator (LogView heating-up / on-fire) — warm only, never
    // the green accent; fire is a streak signal, not a "go" signal.
    static let fireWarm = Color(hex: 0xFFB02E)   // ember at 2 straight hits
    static let fireHot = Color(hex: 0xFF6B35)    // flame at 3+

    // Group identity rainbow (cycled) — desaturated athletic tones; the candy
    // iOS-system hues read as toy against the graphite floor.
    static let groupRainbow: [Color] = [
        Color(hex: 0x6B9BD8), Color(hex: 0x5FBF77), Color(hex: 0xE0A458),
        Color(hex: 0xA98BD4), Color(hex: 0xD97B85), Color(hex: 0x6FC3C9),
        Color(hex: 0xC9B458),
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

    // MARK: Brand display font (Space Grotesk; bundled) — share-card register

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

    // MARK: Stat numerals (Barlow Condensed; bundled) — app register

    /// Every big number in the app UI sets in this: tall, athletic, planted.
    /// Words stay SF — the condensed face is reserved for numerals so it
    /// reads as scoreboard, not costume.
    static func barlow(_ size: CGFloat, _ weight: BarlowWeight = .bold) -> Font {
        Font.custom(weight.postScriptName, size: size)
    }

    enum BarlowWeight {
        case semibold, bold, extrabold
        var postScriptName: String {
            switch self {
            case .semibold: "BarlowCondensed-SemiBold"
            case .bold: "BarlowCondensed-Bold"
            case .extrabold: "BarlowCondensed-ExtraBold"
            }
        }
    }

    /// Engraved section label ("HIT RATE", "OUTCOMES") — the kicker style
    /// every well leads with.
    static func kicker(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.8)
            .foregroundStyle(Theme.label2)
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
    /// `seed` picks between voice variants in bands that have more than one
    /// line — derived from the card name (stable), NEVER a live RNG: snapshots
    /// re-render and the line must not change between the sheet and the export.
    static func stats(rate: Int, noun: String = "group", stunt: Bool = true,
                      seed: Int = 0) -> Rarity {
        Rarity(tier: "STATS", stars: 0, tag: Color.white.opacity(0.55),
               edgeColors: navyEdge, foil: .none,
               flavor: statFlavor(rate: rate, noun: noun, stunt: stunt, seed: seed))
    }

    /// The stat-card narrative ladder (Ian's voice — sarcastic by default).
    /// Bands: 99 / 95 / 90 / 80 / 60 / floor. (78 was a leftover from the
    /// retired rate-derived rarity bands; rounded to 80 on 2026-06-11.)
    private static func statFlavor(rate: Int, noun: String, stunt: Bool,
                                   seed: Int) -> String {
        if rate >= 99 {
            return "You actually know what you're doing, and I respect that… or you're a liar and I hate you."
        }
        if rate >= 95 { return "Wow. You want a cookie?" }
        if rate >= 90 {
            return "You're probably not the problem — spread good energy to the rest of the team. PS: you're not perfect."
        }
        if rate >= 80 {
            return seed.isMultiple(of: 2)
                ? "Just because you can stay up doesn't mean you didn't lose any points."
                : "You could still do better."
        }
        if rate >= 60 {
            return "You are so close. Keep pushing — you've almost had your breakthrough. You almost understand what you're doing."
        }
        // Kind-specific call-outs rotate with the universal pouting line.
        if seed.isMultiple(of: 2) {
            return stunt
                ? "If you're blaming the flyer, it's probably you that's the problem."
                : "And you threw this at tryouts? Did you land it?"
        }
        return "Pouting never helped nobody."
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

/// "’25–’26" style season string. The cheer season ends in May, so it rolls
/// over on June 1.
func seasonString(for date: Date = .now) -> String {
    let cal = Calendar.current
    let y = cal.component(.year, from: date)
    let m = cal.component(.month, from: date)
    let start = m >= 6 ? y : y - 1
    let a = String(String(start).suffix(2))
    let b = String(String(start + 1).suffix(2))
    return "’\(a)–’\(b)"
}

/// Midnight on Jun 1 of the current season's start year — the cutoff the
/// season league and cup history reset to (mirrors `seasonString`'s rollover;
/// the cheer season ends in May).
func seasonStart(for date: Date = .now) -> Date {
    let cal = Calendar.current
    let y = cal.component(.year, from: date)
    let m = cal.component(.month, from: date)
    let startYear = m >= 6 ? y : y - 1
    return cal.date(from: DateComponents(year: startYear, month: 6, day: 1)) ?? date
}

/// Initials for a name ("Cheer Force San Diego" → "CFSD", "Senior Coed" → "SC").
func initials(of name: String, max: Int = 4) -> String {
    name.split(separator: " ").prefix(max).compactMap { $0.first.map(String.init) }.joined().uppercased()
}
