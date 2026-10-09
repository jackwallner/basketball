import Foundation

/// One NBA game from `public.games`, the published hoopR schedule.
///
/// Scores are null until hoopR posts a final. There is no live score feed:
/// a game past tip-off with no score is "in progress", not 0-0.
struct Game: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let season: Int
    let seasonPhase: SeasonPhase
    /// REG or POST.
    let gameType: String
    /// Calendar weeks since the season's October epoch (see
    /// `backend/nbacodes.py::game_week`). Not a league week: the NBA has none.
    let week: Int
    let tipoff: Date?
    let gameDate: Date
    let awayTeam: String
    let homeTeam: String
    let awayScore: Int?
    let homeScore: Int?
    let overtime: Bool
    let stadium: String?

    enum CodingKeys: String, CodingKey {
        case id = "game_id"
        case season
        case seasonPhase = "season_type"
        case gameType = "game_type"
        case week
        case tipoff = "kickoff_at"
        case gameDate = "game_date"
        case awayTeam = "away_team"
        case homeTeam = "home_team"
        case awayScore = "away_score"
        case homeScore = "home_score"
        case overtime
        case stadium
    }

    init(
        id: String,
        season: Int,
        seasonPhase: SeasonPhase = .regular,
        gameType: String = "REG",
        week: Int,
        tipoff: Date?,
        gameDate: Date? = nil,
        awayTeam: String,
        homeTeam: String,
        awayScore: Int? = nil,
        homeScore: Int? = nil,
        overtime: Bool = false,
        stadium: String? = nil
    ) {
        self.id = id
        self.season = season
        self.seasonPhase = seasonPhase
        self.gameType = gameType
        self.week = week
        self.tipoff = tipoff
        self.gameDate = gameDate ?? tipoff ?? .distantPast
        self.awayTeam = awayTeam
        self.homeTeam = homeTeam
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.overtime = overtime
        self.stadium = stadium
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        season = try c.decode(Int.self, forKey: .season)
        seasonPhase = try c.decodeIfPresent(SeasonPhase.self, forKey: .seasonPhase) ?? .regular
        gameType = try c.decodeIfPresent(String.self, forKey: .gameType) ?? "REG"
        week = try c.decode(Int.self, forKey: .week)
        tipoff = try c.decodeIfPresent(String.self, forKey: .tipoff).flatMap(DataFreshness.parseDate)
        let rawDate = try c.decode(String.self, forKey: .gameDate)
        guard let parsed = DataFreshness.parseDate(rawDate) else {
            throw DecodingError.dataCorruptedError(forKey: .gameDate, in: c, debugDescription: "Invalid game_date: \(rawDate)")
        }
        gameDate = parsed
        awayTeam = try c.decode(String.self, forKey: .awayTeam)
        homeTeam = try c.decode(String.self, forKey: .homeTeam)
        awayScore = try c.decodeIfPresent(Int.self, forKey: .awayScore)
        homeScore = try c.decodeIfPresent(Int.self, forKey: .homeScore)
        overtime = try c.decodeIfPresent(Bool.self, forKey: .overtime) ?? false
        stadium = try c.decodeIfPresent(String.self, forKey: .stadium)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(season, forKey: .season)
        try c.encode(seasonPhase, forKey: .seasonPhase)
        try c.encode(gameType, forKey: .gameType)
        try c.encode(week, forKey: .week)
        let iso = ISO8601DateFormatter()
        try c.encodeIfPresent(tipoff.map { iso.string(from: $0) }, forKey: .tipoff)
        try c.encode(iso.string(from: gameDate), forKey: .gameDate)
        try c.encode(awayTeam, forKey: .awayTeam)
        try c.encode(homeTeam, forKey: .homeTeam)
        try c.encodeIfPresent(awayScore, forKey: .awayScore)
        try c.encodeIfPresent(homeScore, forKey: .homeScore)
        try c.encode(overtime, forKey: .overtime)
        try c.encodeIfPresent(stadium, forKey: .stadium)
    }

    var isFinal: Bool { awayScore != nil && homeScore != nil }

    func involves(_ team: String) -> Bool {
        let abbr = normalizedTeamAbbreviation(team)
        return normalizedTeamAbbreviation(awayTeam) == abbr || normalizedTeamAbbreviation(homeTeam) == abbr
    }

    func opponent(of team: String) -> String {
        normalizedTeamAbbreviation(awayTeam) == normalizedTeamAbbreviation(team) ? homeTeam : awayTeam
    }

    func isHome(_ team: String) -> Bool {
        normalizedTeamAbbreviation(homeTeam) == normalizedTeamAbbreviation(team)
    }

    func score(of team: String) -> Int? {
        isHome(team) ? homeScore : awayScore
    }

    /// "W" or "L" for a final, from `team`'s side. Basketball has no ties.
    func result(for team: String) -> String? {
        guard let mine = score(of: team), let theirs = score(of: opponent(of: team)) else { return nil }
        return mine > theirs ? "W" : "L"
    }

    /// "W 118-109", team score first.
    func resultLine(for team: String) -> String? {
        guard let result = result(for: team),
              let mine = score(of: team),
              let theirs = score(of: opponent(of: team)) else { return nil }
        return "\(result) \(mine)-\(theirs)\(overtime ? " OT" : "")"
    }

    /// "vs HOU" at home, "at HOU" away.
    func matchupLabel(for team: String) -> String {
        "\(isHome(team) ? "vs" : "at") \(displayTeamAbbr(opponent(of: team)))"
    }

    func status(now: Date = .now) -> GameStatus {
        if isFinal { return .final }
        guard let tipoff else { return .upcoming }
        if now < tipoff { return .upcoming }
        // No live scores in the feed. Past a normal game length with no posted
        // final, say the score is on its way rather than "in progress" forever.
        return now.timeIntervalSince(tipoff) < 3.5 * 3_600 ? .inProgress : .awaitingScore
    }
}

enum GameStatus: Equatable, Sendable {
    case upcoming
    case inProgress
    case awaitingScore
    case final

    var sortOrder: Int {
        switch self {
        case .inProgress: return 0
        case .awaitingScore: return 1
        case .final: return 2
        case .upcoming: return 3
        }
    }
}

/// A selectable day of the schedule. The NBA plays nearly every night, so the
/// Games tab is a strip of game days rather than league weeks.
struct GameDay: Hashable, Identifiable, Sendable {
    /// Eastern midnight of the game date, the league's calendar.
    let date: Date
    let phase: SeasonPhase
    /// "2026-10-20". Formatted once here: the strip compares ids for every
    /// chip on every render.
    let id: String

    init(date: Date, phase: SeasonPhase) {
        self.date = date
        self.phase = phase
        self.id = Self.dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter
    }()

    /// Chip text: "Oct 20".
    var shortLabel: String { date.formatted(DataCoverage.gameDayStyle) }

    /// "Tue, Oct 20".
    var label: String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return date.formatted(style)
    }

    static func days(in games: [Game]) -> [GameDay] {
        var seen: [String: GameDay] = [:]
        for game in games {
            let day = GameDay(date: game.gameDate, phase: game.seasonPhase)
            seen[day.id] = day
        }
        return seen.values.sorted { $0.date < $1.date }
    }

    /// The day a fan means by "today".
    ///
    /// A day stays current until 8am Eastern the morning after, so last night's
    /// finals are still on screen over breakfast and the next slate takes over
    /// as people start planning for it. Before the season it is the opening
    /// night; after it, the last day played.
    static func current(in games: [Game], now: Date = .now) -> GameDay? {
        current(among: days(in: games), now: now)
    }

    /// `current(in:)` over days already worked out, in date order.
    static func current(among days: [GameDay], now: Date = .now) -> GameDay? {
        days.first { now < $0.date.addingTimeInterval(32 * 3_600) } ?? days.last
    }

    func games(from games: [Game]) -> [Game] {
        games.filter { $0.gameDate == date && $0.seasonPhase == phase }
    }
}

extension Game {
    /// Orders a slate: in progress, then finals, then upcoming, each by tip-off.
    static func slateOrder(_ games: [Game], now: Date = .now) -> [Game] {
        games.sorted {
            let a = $0.status(now: now).sortOrder
            let b = $1.status(now: now).sortOrder
            if a != b { return a < b }
            return ($0.tipoff ?? $0.gameDate, $0.id) < ($1.tipoff ?? $1.gameDate, $1.id)
        }
    }

    /// "Tue 7:30 PM" in the phone's zone.
    var tipoffLabel: String {
        guard let tipoff else { return gameDate.formatted(DataCoverage.gameDayStyle) }
        return tipoff.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "Tue, Oct 20".
    var dayLabel: String {
        guard let tipoff else { return gameDate.formatted(DataCoverage.gameDayStyle) }
        return tipoff.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
