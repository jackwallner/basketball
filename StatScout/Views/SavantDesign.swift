import SwiftUI

enum HardwoodPalette {
    static let canvas       = Color(red: 0.94, green: 0.93, blue: 0.89)
    static let surface      = Color(red: 0.99, green: 0.98, blue: 0.94)
    static let surfaceAlt   = Color(red: 0.96, green: 0.95, blue: 0.90)
    static let surfaceSunk  = Color(red: 0.90, green: 0.89, blue: 0.84)
    static let hairline     = Color(red: 0.72, green: 0.71, blue: 0.66)
    static let divider      = Color(red: 0.82, green: 0.81, blue: 0.76)
    static let ink          = Color(red: 0.07, green: 0.09, blue: 0.08)
    static let inkSecondary = Color(red: 0.22, green: 0.25, blue: 0.23)
    static let inkTertiary  = Color(red: 0.39, green: 0.41, blue: 0.38)
    static let inkOnDark    = Color(red: 0.99, green: 0.98, blue: 0.94)
    static let midnight     = Color(red: 0.035, green: 0.08, blue: 0.07)
    static let court         = Color(red: 0.08, green: 0.36, blue: 0.20)
    static let leather      = Color(red: 0.48, green: 0.23, blue: 0.10)
    static let gold         = Color(red: 0.84, green: 0.63, blue: 0.19)
    static let linkBlue     = Color(red: 0.05, green: 0.32, blue: 0.45)
    static let performanceHigh = Color(red: 0.02, green: 0.46, blue: 0.20)
    static let performanceMid  = Color(red: 0.40, green: 0.38, blue: 0.31)
    static let performanceLow  = Color(red: 0.70, green: 0.20, blue: 0.08)
    static let up           = performanceHigh
    static let down         = performanceLow
    static let flat         = inkTertiary

    static func color(forPercentile p: Int) -> Color {
        let t = max(0.0, min(1.0, Double(p) / 100.0))
        if t < 0.5 {
            return lerp(coldRGB, midRGB, t * 2.0)
        } else {
            return lerp(midRGB, hotRGB, (t - 0.5) * 2.0)
        }
    }

    /// Percentile colour for *text* on a light surface.
    ///
    /// The fill ramp passes through a pale sand at the 50th percentile, which
    /// is right for a bar sitting on the cream card and unreadable as type: an
    /// average player's number came out the same value as the background. The
    /// endpoints stay recognisably the same green and rust; only the middle is
    /// pulled down to a dark neutral, so every value on the board clears
    /// contrast while the hot/cold reading survives.
    static func textColor(forPercentile p: Int) -> Color {
        let t = max(0.0, min(1.0, Double(p) / 100.0))
        if t < 0.5 {
            return lerp(coldTextRGB, midTextRGB, t * 2.0)
        } else {
            return lerp(midTextRGB, hotTextRGB, (t - 0.5) * 2.0)
        }
    }

    private static let hotRGB: (Double, Double, Double) = (0.02, 0.46, 0.20)
    private static let midRGB: (Double, Double, Double) = (0.40, 0.38, 0.31)
    private static let coldRGB: (Double, Double, Double) = (0.70, 0.20, 0.08)

    private static let hotTextRGB: (Double, Double, Double) = (0.06, 0.36, 0.19)
    private static let midTextRGB: (Double, Double, Double) = (0.24, 0.26, 0.24)
    private static let coldTextRGB: (Double, Double, Double) = (0.55, 0.20, 0.10)

    private static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        let r = a.0 + (b.0 - a.0) * t
        let g = a.1 + (b.1 - a.1) * t
        let bl = a.2 + (b.2 - a.2) * t
        return Color(red: r, green: g, blue: bl)
    }
}

enum HardwoodType {
    // SF Pro is the single language face throughout the app. Semantic styles
    // keep the hierarchy coherent and participate in Dynamic Type.
    //
    // Stock width, deliberately. Build 16 shipped these condensed to buy back
    // the horizontal budget the ported-from-baseball column widths (42pt rank,
    // 44pt team, 48pt value) were measured against in RobotoCondensed, but the
    // condensed face read worse than the mild squeeze it fixed. If a column
    // needs more room, widen that column rather than narrowing every glyph.
    static let playerName   = Font.system(.title2, design: .default, weight: .bold)
    static let pageTitle    = Font.system(.title3, design: .default, weight: .bold)
    static let sectionTitle = Font.system(.caption, design: .default, weight: .bold)
    static let cardTitle    = Font.system(.headline, design: .default, weight: .semibold)
    static let body         = Font.system(.subheadline, design: .default)
    static let bodyBold     = Font.system(.subheadline, design: .default, weight: .semibold)
    static let small        = Font.system(.caption, design: .default)
    static let smallBold    = Font.system(.caption, design: .default, weight: .semibold)
    static let micro        = Font.system(.caption2, design: .default, weight: .semibold)

    // Values and ranks are SF Pro too, with tabular digits so columns still
    // line up. They used to be SF Mono, which put a second typeface on every
    // row: a name in SF Pro beside a number in Mono, and the few titles that
    // borrowed a stat style ("Full Player Scouting") read as code.
    static let statHero  = Font.system(.title, design: .default, weight: .bold).monospacedDigit()
    static let statLarge = Font.system(.title3, design: .default, weight: .bold).monospacedDigit()
    static let statMed   = Font.system(.subheadline, design: .default, weight: .semibold).monospacedDigit()
    static let statSmall = Font.system(.caption, design: .default, weight: .medium).monospacedDigit()
}

enum HardwoodGeo {
    static let radiusCard: CGFloat = 4
    static let radiusBadge: CGFloat = 2
    static let hairline: CGFloat = 0.5
    static let barTrack: CGFloat = 4
    static let barMarker: CGFloat = 12
    static let padInline: CGFloat = 12
    static let padCard: CGFloat = 16
    static let padPage: CGFloat = 16
    static let padSection: CGFloat = 24
    static let rowHeight: CGFloat = 44
    static let rowHeightHeader: CGFloat = 28
    /// Breathing room between the underlined position tabs and the first row of
    /// inline controls under them. The tabs carry their own underline plus a
    /// hairline, so a control butted straight up against them reads as part of
    /// the tab strip rather than as the board's own filter.
    static let controlRowGap: CGFloat = 10
}

/// NBA team primary colors, keyed by the app's team code. Historical codes
/// (SEA, NJN, NOH, NOK, VAN) carry the colors the franchise wore then.
enum NBATeamColor {
    static let primary: [String: Color] = [
        "ATL": Color(red: 0.88, green: 0.23, blue: 0.19),
        "BKN": Color(red: 0.10, green: 0.10, blue: 0.11),
        "BOS": Color(red: 0.00, green: 0.48, blue: 0.20),
        "CHA": Color(red: 0.00, green: 0.47, blue: 0.55),
        "CHI": Color(red: 0.81, green: 0.07, blue: 0.25),
        "CLE": Color(red: 0.52, green: 0.00, blue: 0.22),
        "DAL": Color(red: 0.00, green: 0.33, blue: 0.55),
        "DEN": Color(red: 0.05, green: 0.13, blue: 0.25),
        "DET": Color(red: 0.11, green: 0.26, blue: 0.73),
        "GSW": Color(red: 0.11, green: 0.26, blue: 0.54),
        "HOU": Color(red: 0.81, green: 0.07, blue: 0.25),
        "IND": Color(red: 0.00, green: 0.18, blue: 0.38),
        "LAC": Color(red: 0.78, green: 0.06, blue: 0.18),
        "LAL": Color(red: 0.33, green: 0.15, blue: 0.51),
        "MEM": Color(red: 0.36, green: 0.46, blue: 0.66),
        "MIA": Color(red: 0.60, green: 0.00, blue: 0.18),
        "MIL": Color(red: 0.00, green: 0.28, blue: 0.11),
        "MIN": Color(red: 0.05, green: 0.14, blue: 0.25),
        "NOP": Color(red: 0.05, green: 0.14, blue: 0.25),
        "NYK": Color(red: 0.00, green: 0.42, blue: 0.71),
        "OKC": Color(red: 0.00, green: 0.48, blue: 0.76),
        "ORL": Color(red: 0.00, green: 0.47, blue: 0.75),
        "PHI": Color(red: 0.00, green: 0.42, blue: 0.71),
        "PHX": Color(red: 0.11, green: 0.07, blue: 0.38),
        "POR": Color(red: 0.88, green: 0.23, blue: 0.19),
        "SAC": Color(red: 0.35, green: 0.18, blue: 0.51),
        "SAS": Color(red: 0.15, green: 0.16, blue: 0.17),
        "TOR": Color(red: 0.81, green: 0.07, blue: 0.25),
        "UTA": Color(red: 0.00, green: 0.17, blue: 0.36),
        "WAS": Color(red: 0.00, green: 0.17, blue: 0.36),
        // Franchises that played under another code in the seasons the app covers.
        "SEA": Color(red: 0.00, green: 0.40, blue: 0.20),
        "NJN": Color(red: 0.00, green: 0.16, blue: 0.38),
        "NOH": Color(red: 0.00, green: 0.47, blue: 0.55),
        "NOK": Color(red: 0.00, green: 0.47, blue: 0.55),
        "VAN": Color(red: 0.00, green: 0.70, blue: 0.66),
    ]
    static func color(_ abbr: String) -> Color { primary[normalizedTeamAbbreviation(abbr)] ?? HardwoodPalette.inkTertiary }
}

/// The 30 current NBA teams in the app's team codes. Shared by the Teams grid
/// and switcher.
let nbaTeamAbbreviations: [String] = [
    "ATL", "BKN", "BOS", "CHA", "CHI", "CLE", "DAL", "DEN", "DET", "GSW",
    "HOU", "IND", "LAC", "LAL", "MEM", "MIA", "MIL", "MIN", "NOP", "NYK",
    "OKC", "ORL", "PHI", "PHX", "POR", "SAC", "SAS", "TOR", "UTA", "WAS",
]

enum NBAConference: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all = "All"
    case east = "East"
    case west = "West"

    var id: String { rawValue }

    func contains(team: String) -> Bool {
        let abbr = normalizedTeamAbbreviation(team)
        switch self {
        case .all:
            return true
        case .east:
            return Self.eastTeams.contains(abbr)
        case .west:
            return Self.westTeams.contains(abbr)
        }
    }

    private static let eastTeams: Set<String> = [
        "ATL", "BKN", "BOS", "CHA", "CHI", "CLE", "DET", "IND",
        "MIA", "MIL", "NYK", "ORL", "PHI", "TOR", "WAS", "NJN",
    ]

    private static let westTeams: Set<String> = [
        "DAL", "DEN", "GSW", "HOU", "LAC", "LAL", "MEM", "MIN",
        "NOP", "OKC", "PHX", "POR", "SAC", "SAS", "UTA",
        "SEA", "NOH", "NOK", "VAN",
    ]
}

private let teamNames: [String: String] = [
    "ATL": "Atlanta Hawks", "BKN": "Brooklyn Nets", "BOS": "Boston Celtics",
    "CHA": "Charlotte Hornets", "CHI": "Chicago Bulls", "CLE": "Cleveland Cavaliers",
    "DAL": "Dallas Mavericks", "DEN": "Denver Nuggets", "DET": "Detroit Pistons",
    "GSW": "Golden State Warriors", "HOU": "Houston Rockets", "IND": "Indiana Pacers",
    "LAC": "Los Angeles Clippers", "LAL": "Los Angeles Lakers", "MEM": "Memphis Grizzlies",
    "MIA": "Miami Heat", "MIL": "Milwaukee Bucks", "MIN": "Minnesota Timberwolves",
    "NOP": "New Orleans Pelicans", "NYK": "New York Knicks", "OKC": "Oklahoma City Thunder",
    "ORL": "Orlando Magic", "PHI": "Philadelphia 76ers", "PHX": "Phoenix Suns",
    "POR": "Portland Trail Blazers", "SAC": "Sacramento Kings", "SAS": "San Antonio Spurs",
    "TOR": "Toronto Raptors", "UTA": "Utah Jazz", "WAS": "Washington Wizards",
    // Historical franchises.
    "SEA": "Seattle SuperSonics", "NJN": "New Jersey Nets", "NOH": "New Orleans Hornets",
    "NOK": "New Orleans/Oklahoma City Hornets", "VAN": "Vancouver Grizzlies",
]

private let teamCodesByName: [String: String] = Dictionary(
    uniqueKeysWithValues: teamNames.map { ($0.value.uppercased(), $0.key) }
)

func normalizedTeamAbbreviation(_ team: String) -> String {
    let key = team.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let aliases: [String: String] = [
        // ESPN's short forms and the usual fan variants map to the app's codes.
        "GS": "GSW", "NO": "NOP", "NY": "NYK", "SA": "SAS", "UTAH": "UTA",
        "WSH": "WAS", "NJ": "NJN", "BRK": "BKN", "PHO": "PHX", "CHO": "CHA",
    ]
    if let alias = aliases[key] { return alias }
    // Full names → abbreviation.
    return teamCodesByName[key] ?? key
}

func teamFullName(_ abbr: String) -> String {
    let normalized = normalizedTeamAbbreviation(abbr)
    return teamNames[normalized] ?? abbr
}

struct StatScoutTheme {
    static let background = LinearGradient(colors: [HardwoodPalette.canvas, HardwoodPalette.canvas], startPoint: .top, endPoint: .bottom)
    static let card       = HardwoodPalette.surface
    static let stroke     = HardwoodPalette.hairline
    static let accent     = HardwoodPalette.court
    static let hot        = HardwoodPalette.performanceHigh
    static let performanceLow = HardwoodPalette.performanceLow
    static let court      = HardwoodPalette.court
    static let leather    = HardwoodPalette.leather
    static let sky        = Color(red: 0.30, green: 0.55, blue: 0.85)

    static func percentileColor(_ percentile: Int) -> Color {
        HardwoodPalette.color(forPercentile: percentile)
    }
}
