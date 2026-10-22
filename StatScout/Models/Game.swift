import Foundation

/// One NBA game from `public.games`, the published hoopR schedule.
///
/// Scores are null until hoopR posts a final. There is no live score feed:
/// a game past tip-off with no score is "in progress", not 0-0.
struct Game: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let season: Int
    let seasonPhase: SeasonPhase
    /// `REG`; `CUP` for the NBA Cup final (outside the standings and season
    /// stats); `PPD` for a postponed game, whose makeup is its own row; a
    /// playoff round `R1`, `R2`, `CF`, `FIN` (or plain `POST`).
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

    /// Postponed or cancelled. Its makeup is a separate game, so this row is
    /// never shown.
    var isPostponed: Bool { gameType == "PPD" }

    var isCupFinal: Bool { gameType == "CUP" }

    /// Counts toward a team's record: a regular-season game that isn't the
    /// NBA Cup final.
    var countsInStandings: Bool { seasonPhase == .regular && !isCupFinal && !isPostponed }

    /// "West 1st Round", "East Finals", "NBA Finals"; nil outside the playoffs
    /// or for a round the feed didn't name.
    var playoffRoundName: String? {
        let conference = NBAConference.east.contains(team: homeTeam) ? "East" : "West"
        switch gameType {
        case "R1": return "\(conference) 1st Round"
        case "R2": return "\(conference) Semifinals"
        case "CF": return "\(conference) Finals"
        case "FIN": return "NBA Finals"
        default: return nil
        }
    }

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
        let formatter = DataFreshness.makeEasternDayFormatter()
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
        days.first { now < $0.handover } ?? days.last
    }

    /// 8 AM Eastern the morning after the game date. Counted on the Eastern
    /// calendar rather than as 32 hours after Eastern midnight, which is an
    /// hour early on the fall-back night and an hour late on the spring-forward
    /// one.
    var handover: Date {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let nextMidnight = eastern.date(byAdding: .day, value: 1, to: date)
            ?? date.addingTimeInterval(24 * 3_600)
        return eastern.date(bySettingHour: 8, minute: 0, second: 0, of: nextMidnight)
            ?? nextMidnight.addingTimeInterval(8 * 3_600)
    }

    func games(from games: [Game]) -> [Game] {
        games.filter { $0.gameDate == date && $0.seasonPhase == phase }
    }
}

/// Where a playoff series stood after one of its games.
struct SeriesStatus: Hashable, Sendable {
    let round: String
    let gameNumber: Int
    /// Wins through this game, keyed by normalized team.
    let wins: [String: Int]

    /// "NBA Finals · Game 5".
    var gameLabel: String { "\(round) · Game \(gameNumber)" }

    /// "NYK wins 4-1", "NYK leads 3-2", "Series tied 2-2"; "Series tied 0-0"
    /// reads as nothing, so a first game says nothing.
    var standingLabel: String? {
        let sorted = wins.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard let leader = sorted.first, sorted.count == 2, leader.value > 0 else { return nil }
        let trailer = sorted[1]
        if leader.value == trailer.value { return "Series tied \(leader.value)-\(trailer.value)" }
        let verb = leader.value == 4 ? "wins" : "leads"
        return "\(displayTeamAbbr(leader.key)) \(verb) \(leader.value)-\(trailer.value)"
    }

    /// The series a playoff game belongs to, from every game of the season.
    /// Nil for anything but a named playoff round.
    static func of(_ game: Game, in games: [Game]) -> SeriesStatus? {
        guard let round = game.playoffRoundName else { return nil }
        let pair = Set([normalizedTeamAbbreviation(game.homeTeam), normalizedTeamAbbreviation(game.awayTeam)])
        let series = games
            .filter {
                $0.season == game.season && $0.gameType == game.gameType
                    && Set([normalizedTeamAbbreviation($0.homeTeam), normalizedTeamAbbreviation($0.awayTeam)]) == pair
            }
            .sorted { ($0.tipoff ?? $0.gameDate, $0.id) < ($1.tipoff ?? $1.gameDate, $1.id) }
        guard let index = series.firstIndex(where: { $0.id == game.id }) else { return nil }
        var wins = Dictionary(uniqueKeysWithValues: pair.map { ($0, 0) })
        for played in series[...index] {
            guard let winner = [played.homeTeam, played.awayTeam].first(where: { played.result(for: $0) == "W" }) else { continue }
            wins[normalizedTeamAbbreviation(winner), default: 0] += 1
        }
        return SeriesStatus(round: round, gameNumber: index + 1, wins: wins)
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

    /// What makes the game more than a date: "NBA Finals · Game 5 · NYK wins
    /// 4-1", "NBA Cup Final". Nil for an ordinary regular-season game.
    func contextLine(series: SeriesStatus?) -> String? {
        if isCupFinal { return "NBA Cup Final" }
        guard let series else { return nil }
        return ([series.gameLabel] + [series.standingLabel].compactMap { $0 }).joined(separator: " · ")
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
