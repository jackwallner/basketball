import Foundation

/// One player's league-anchored weekly window, as stored in
/// `public.player_recent_form`.
///
/// Mirrors the rolling-leaderboard shape the baseball app uses: the current
/// window, the equal-length window immediately before it, and the change
/// between them. The delta is the interesting column, a 38% three-point mark
/// means more when you can see it was 31% over the two weeks before that.
///
/// MLB uses calendar days. The NBA plays on most nights, so windows are 1, 2
/// and 4 calendar weeks anchored on the league's latest game date, which keeps
/// a player who has not appeared recently off a current Trends board.
struct RecentForm: Codable, Hashable, Sendable, Identifiable {
    let playerId: Int
    let season: Int
    let seasonPhase: SeasonPhase
    let playerType: String
    let windowWeeks: Int
    /// Date of the last game in the window. Lets the UI say "through Feb 8"
    /// rather than implying the window runs to today.
    let asOf: Date?
    /// Calendar-week numbers (counted from the season's October epoch) of the
    /// first and last game in the window. Kept for ordering; the app labels a
    /// window by its length and its end date.
    let startWeek: Int?
    let endWeek: Int?
    let team: String?
    let games: Int
    /// Possessions used in the window: field goal attempts + 0.44 free throw
    /// attempts + turnovers.
    let plays: Int
    /// Minutes played in the window.
    let touches: Int
    let metrics: [String: Double]
    let priorMetrics: [String: Double]
    let delta: [String: Double]

    var id: String {
        "\(playerId)-\(seasonPhase.rawValue)-\(playerType)-\(windowWeeks)"
    }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case season
        case seasonPhase = "season_type"
        case playerType = "player_type"
        case windowWeeks = "window_weeks"
        case legacyWindowGames = "window_games"
        case asOf = "as_of"
        case startWeek = "start_week"
        case endWeek = "end_week"
        case team
        case games
        case plays
        case touches
        case metrics
        case priorMetrics = "prior_metrics"
        case delta
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(Int.self, forKey: .playerId)
        season = try c.decode(Int.self, forKey: .season)
        seasonPhase = try c.decodeIfPresent(SeasonPhase.self, forKey: .seasonPhase) ?? .regular
        playerType = try c.decode(String.self, forKey: .playerType)
        windowWeeks = try c.decodeIfPresent(Int.self, forKey: .windowWeeks)
            ?? c.decode(Int.self, forKey: .legacyWindowGames)
        team = try c.decodeIfPresent(String.self, forKey: .team)
        games = try c.decodeIfPresent(Int.self, forKey: .games) ?? 0
        plays = try c.decodeIfPresent(Int.self, forKey: .plays) ?? 0
        touches = try c.decodeIfPresent(Int.self, forKey: .touches) ?? 0
        startWeek = try c.decodeIfPresent(Int.self, forKey: .startWeek)
        endWeek = try c.decodeIfPresent(Int.self, forKey: .endWeek)

        // as_of is a Postgres `date`, so it arrives as "YYYY-MM-DD" and won't
        // parse with the ISO8601 strategy the rest of the payload uses.
        if let raw = try c.decodeIfPresent(String.self, forKey: .asOf) {
            var parts = DateComponents()
            let bits = raw.split(separator: "-").compactMap { Int($0) }
            if bits.count == 3 {
                parts.year = bits[0]; parts.month = bits[1]; parts.day = bits[2]
                asOf = Calendar.current.date(from: parts)
            } else {
                asOf = nil
            }
        } else {
            asOf = nil
        }

        // Null metric values mean "no data in this window" (see the rollup's
        // omit-rather-than-zero rule), so they're dropped rather than coerced.
        func numbers(_ key: CodingKeys) -> [String: Double] {
            guard let raw = try? c.decodeIfPresent([String: Double?].self, forKey: key) else { return [:] }
            return raw.compactMapValues { $0 }
        }
        metrics = numbers(.metrics)
        priorMetrics = numbers(.priorMetrics)
        delta = numbers(.delta)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(season, forKey: .season)
        try c.encode(seasonPhase, forKey: .seasonPhase)
        try c.encode(playerType, forKey: .playerType)
        try c.encode(windowWeeks, forKey: .windowWeeks)
        try c.encodeIfPresent(team, forKey: .team)
        try c.encode(games, forKey: .games)
        try c.encode(plays, forKey: .plays)
        try c.encode(touches, forKey: .touches)
        try c.encodeIfPresent(startWeek, forKey: .startWeek)
        try c.encodeIfPresent(endWeek, forKey: .endWeek)
        try c.encode(metrics, forKey: .metrics)
        try c.encode(priorMetrics, forKey: .priorMetrics)
        try c.encode(delta, forKey: .delta)
    }

    /// Minutes played in the window.
    var minutes: Int { touches }

    /// "1 wk", "2 wk" or "4 wk", the length of the window.
    var windowLabel: String {
        RecentWindow(rawValue: windowWeeks)?.segmentLabel ?? "\(windowWeeks) wk"
    }

    /// Small samples make wild deltas: two games and a hot shooting night
    /// swing a percentage by twenty points. The floor is games and minutes, the
    /// two things every role shares.
    var isSmallSample: Bool { isSmallSample(minimumGames: 2) }

    /// The same volume floor with a different game minimum. The early-season
    /// board ranks a single window, so it asks for one game rather than two.
    func isSmallSample(minimumGames: Int) -> Bool {
        games < minimumGames || touches < Self.minimumMinutes
    }

    /// About two full games of floor time.
    static let minimumMinutes = 60
}

/// Season metric label to the rolling rollup's column for it, plus the one
/// formatter for a window value.
///
/// The leaderboard, the team roster and the team cards all need to ask "what is
/// this player's TS% over the last two weeks"; each had grown its own private
/// copy of the mapping, which is how a metric ends up trending on one screen
/// and blank on the next.
///
/// The rollup keys are the season metric ids from the contract, so this table is
/// just label to id. Every registry metric has one; a label outside the registry
/// (a standard-stat line) returns nil and simply gets no recent bar.
enum RecentMetricKey {
    private static let keys: [String: String] = [
        // Scoring
        "Pts/100": "pts_per_100", "USG%": "usg_pct", "TS%": "ts_pct", "eFG%": "efg_pct",
        "FT Rate": "ftr", "3PT Rate": "three_par", "PPG": "ppg", "FG%": "fg_pct",
        "3P%": "three_pct", "FT%": "ft_pct", "3PM": "three_pm",
        // Shooting
        "Rim Freq": "rim_freq", "Rim FG%": "rim_fg", "Short Mid Freq": "short_mid_freq",
        "Short Mid FG%": "short_mid_fg", "Long Mid Freq": "long_mid_freq",
        "Long Mid FG%": "long_mid_fg", "Corner 3%": "corner3_fg",
        "Non-Corner 3%": "nc3_fg", "Assisted FG%": "ast_fg_pct",
        // Playmaking
        "AST%": "ast_pct", "AST/100": "ast_per_100", "TOV%": "tov_pct", "AST:TO": "ast_to",
        "AST:USG": "ast_usg", "APG": "apg", "AST": "ast", "TOV/G": "tov_pg",
        // Rebounding
        "OREB%": "oreb_pct", "DREB%": "dreb_pct", "REB%": "reb_pct", "RPG": "rpg",
        "OREB": "oreb", "DREB": "dreb",
        // Defense
        "STL%": "stl_pct", "BLK%": "blk_pct", "Stocks/100": "stocks_per_100",
        "Fouls/100": "foul_per_100", "SPG": "spg", "BPG": "bpg", "STL": "stl", "BLK": "blk",
        // Impact
        "On-Court +/-": "on_net", "On-Off": "on_off", "Min%": "min_pct", "MPG": "mpg",
        "GS": "gs", "+/-": "plus_minus",
    ]

    static func key(for label: String) -> String? { keys[label] }

    /// True where a falling number is the improvement.
    static func lowerIsBetter(_ label: String) -> Bool {
        ["TOV%", "TOV/G", "Fouls/100"].contains(label)
    }

    /// Counting stats are whole numbers; ratios with a small range keep two
    /// places; everything else is tenths.
    static func decimals(for label: String) -> Int {
        switch label {
        case "3PM", "AST", "OREB", "DREB", "STL", "BLK", "GS", "+/-": return 0
        case "FT Rate", "AST:USG": return 2
        default: return 1
        }
    }

    /// Season totals have no per-week figure on the season's ruler: a two-week
    /// block of 3PM or STL placed against full-season totals reads as a 1st
    /// percentile no matter how well he played. They get no recent bar.
    static func isSeasonTotal(_ label: String) -> Bool {
        ["3PM", "AST", "OREB", "DREB", "STL", "BLK", "GS", "+/-"].contains(label)
    }

    /// True for metrics whose rollup value is already a percentage (28.0 is
    /// 28.0%).
    static func isPercent(_ label: String) -> Bool {
        label.hasSuffix("%") || label.hasSuffix("Freq") || label == "3PT Rate"
    }

    /// True for metrics that read with an explicit sign.
    static func isSigned(_ label: String) -> Bool {
        ["On-Court +/-", "On-Off", "+/-"].contains(label)
    }

    /// Matches the player page's conventions: a percentage carries its sign, a
    /// rate its decimals, and a total its thousands separator.
    static func format(_ value: Double, label: String) -> String {
        let places = decimals(for: label)
        var text: String
        if places == 0 {
            text = Int(value.rounded()).formatted(.number.grouping(.automatic))
        } else {
            text = String(format: "%.\(places)f", value)
        }
        if isSigned(label), value > 0 { text = "+" + text }
        return isPercent(label) ? text + "%" : text
    }
}

/// Windows measured in calendar weeks: 1, 2 and 4.
///
/// One definition for every surface that offers a rolling window: the player
/// card, the team card and the league Trends board used to declare 3 / 5 / 8
/// three times with three different spellings. Controls say "1 wk", "2 wk",
/// "4 wk"; prose says "last week", "2 weeks", "4 weeks".
enum RecentWindow: Int, CaseIterable, Identifiable, Sendable {
    case week = 1
    case twoWeeks = 2
    case fourWeeks = 4

    var id: Int { rawValue }

    /// Control label.
    var segmentLabel: String { "\(rawValue) wk" }
    var shortLabel: String { segmentLabel }

    /// "last week", "last 2 weeks": used mid-sentence.
    var prose: String { self == .week ? "last week" : "last \(rawValue) weeks" }

    /// "Last week", "Last 2 weeks": used on its own line.
    var label: String { self == .week ? "Last week" : "Last \(rawValue) weeks" }

    /// Days in the window.
    var days: Int { rawValue * 7 }
}

/// League-anchored windows used by Trends. The same three lengths as the
/// per-player and per-team windows, so "2 wk" means one thing on every screen.
typealias TrendWindow = RecentWindow
