import Foundation

/// A number with its percentile among this season's team games or qualifying
/// player games. Counts are stored plain and decode with no percentile.
struct RatedValue: Decodable, Hashable, Sendable {
    let value: Double
    let percentile: Int?

    init(value: Double, percentile: Int? = nil) {
        self.value = value
        self.percentile = percentile
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case percentile = "pct"
    }

    init(from decoder: Decoder) throws {
        if let number = try? decoder.singleValueContainer().decode(Double.self) {
            value = number
            percentile = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(Double.self, forKey: .value)
        percentile = try c.decodeIfPresent(Int.self, forKey: .percentile)
    }
}

/// The advanced breakdown for one game, from `public.game_details`: the team
/// four factors and ratings, the score margin through the game, the plays that
/// decided it, and a line for every player with percentiles against the season.
struct GameDetail: Decodable, Sendable {
    struct PlayerLine: Decodable, Identifiable, Hashable, Sendable {
        let playerId: Int
        let name: String?
        let team: String
        let starter: Bool
        /// Minutes played. A plain count, never ranked.
        let minutes: Int?
        let points: RatedValue?
        let rebounds: RatedValue?
        let assists: RatedValue?
        let trueShooting: RatedValue?
        let usage: RatedValue?
        let plusMinus: RatedValue?

        var id: Int { playerId }

        enum CodingKeys: String, CodingKey {
            case playerId = "player_id"
            case name, team, starter
            case minutes = "min"
            case points = "pts"
            case rebounds = "reb"
            case assists = "ast"
            case trueShooting = "ts_pct"
            case usage = "usg_pct"
            case plusMinus = "plus_minus"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            playerId = try c.decode(Int.self, forKey: .playerId)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            team = try c.decode(String.self, forKey: .team)
            starter = try c.decodeIfPresent(Bool.self, forKey: .starter) ?? false
            minutes = try c.decodeIfPresent(Int.self, forKey: .minutes)
            // Each stat is rated independently: one malformed cell must not
            // drop the line.
            points = try? c.decodeIfPresent(RatedValue.self, forKey: .points)
            rebounds = try? c.decodeIfPresent(RatedValue.self, forKey: .rebounds)
            assists = try? c.decodeIfPresent(RatedValue.self, forKey: .assists)
            trueShooting = try? c.decodeIfPresent(RatedValue.self, forKey: .trueShooting)
            usage = try? c.decodeIfPresent(RatedValue.self, forKey: .usage)
            plusMinus = try? c.decodeIfPresent(RatedValue.self, forKey: .plusMinus)
        }

        init(
            playerId: Int,
            name: String? = nil,
            team: String,
            starter: Bool = false,
            minutes: Int? = nil,
            points: RatedValue? = nil,
            rebounds: RatedValue? = nil,
            assists: RatedValue? = nil,
            trueShooting: RatedValue? = nil,
            usage: RatedValue? = nil,
            plusMinus: RatedValue? = nil
        ) {
            self.playerId = playerId
            self.name = name
            self.team = team
            self.starter = starter
            self.minutes = minutes
            self.points = points
            self.rebounds = rebounds
            self.assists = assists
            self.trueShooting = trueShooting
            self.usage = usage
            self.plusMinus = plusMinus
        }
    }

    struct BigPlay: Decodable, Identifiable, Hashable, Sendable {
        enum Kind: String, Decodable, Sendable {
            /// A scoring play in the last five minutes of the fourth quarter or
            /// overtime with the margin inside five afterwards.
            case lateScore = "late_score"
            /// The play worth the most points that changed the lead.
            case leadChange = "lead_change"
        }

        let qtr: Int
        let clock: String
        let team: String
        let description: String
        let points: Int
        /// Home score minus away score after the play.
        let homeMargin: Int
        let kind: Kind?

        var id: String { "\(qtr)-\(clock)-\(description.prefix(24))" }

        enum CodingKeys: String, CodingKey {
            case qtr, clock, team, description, points, kind
            case homeMargin = "home_margin"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            qtr = try c.decode(Int.self, forKey: .qtr)
            clock = try c.decode(String.self, forKey: .clock)
            team = try c.decode(String.self, forKey: .team)
            description = try c.decode(String.self, forKey: .description)
            points = try c.decodeIfPresent(Int.self, forKey: .points) ?? 0
            homeMargin = try c.decodeIfPresent(Int.self, forKey: .homeMargin) ?? 0
            kind = try? c.decodeIfPresent(Kind.self, forKey: .kind)
        }

        init(qtr: Int, clock: String, team: String, description: String, points: Int, homeMargin: Int, kind: Kind?) {
            self.qtr = qtr
            self.clock = clock
            self.team = team
            self.description = description
            self.points = points
            self.homeMargin = homeMargin
            self.kind = kind
        }
    }

    /// One step of the score margin: seconds elapsed in the game and home score
    /// minus away score. Positive is the home team ahead.
    struct MarginPoint: Hashable, Sendable, Identifiable {
        let elapsed: Double
        let homeMargin: Double
        var id: Double { elapsed }
    }

    let gameId: String
    let awayTeam: String
    let homeTeam: String
    let away: [String: RatedValue]
    let home: [String: RatedValue]
    let players: [PlayerLine]
    let margin: [MarginPoint]
    let bigPlays: [BigPlay]

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case awayTeam = "away_team"
        case homeTeam = "home_team"
        case teamStats = "team_stats"
        case players
        // The column keeps the name it had before the NBA; it holds the margin series.
        case margin = "win_probability"
        case bigPlays = "big_plays"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gameId = try c.decode(String.self, forKey: .gameId)
        awayTeam = try c.decode(String.self, forKey: .awayTeam)
        homeTeam = try c.decode(String.self, forKey: .homeTeam)
        let sides = try c.decodeIfPresent(LossyDictionarySides.self, forKey: .teamStats)
        away = sides?.away ?? [:]
        home = sides?.home ?? [:]
        players = (try? c.decodeIfPresent([Lossy<PlayerLine>].self, forKey: .players))?.compactMap(\.value) ?? []
        let raw = (try? c.decodeIfPresent([[Double]].self, forKey: .margin)) ?? []
        margin = raw.compactMap { pair in
            pair.count == 2 ? MarginPoint(elapsed: pair[0], homeMargin: pair[1]) : nil
        }
        bigPlays = (try? c.decodeIfPresent([Lossy<BigPlay>].self, forKey: .bigPlays))?.compactMap(\.value) ?? []
    }

    init(
        gameId: String,
        awayTeam: String,
        homeTeam: String,
        away: [String: RatedValue] = [:],
        home: [String: RatedValue] = [:],
        players: [PlayerLine] = [],
        margin: [MarginPoint] = [],
        bigPlays: [BigPlay] = []
    ) {
        self.gameId = gameId
        self.awayTeam = awayTeam
        self.homeTeam = homeTeam
        self.away = away
        self.home = home
        self.players = players
        self.margin = margin
        self.bigPlays = bigPlays
    }

    func stats(for team: String) -> [String: RatedValue] {
        normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(homeTeam) ? home : away
    }

    /// A team's player lines, starters first and then by minutes.
    func players(for team: String) -> [PlayerLine] {
        let abbr = normalizedTeamAbbreviation(team)
        return players
            .filter { normalizedTeamAbbreviation($0.team) == abbr }
            .sorted {
                if $0.starter != $1.starter { return $0.starter }
                return ($0.minutes ?? 0) > ($1.minutes ?? 0)
            }
    }

    /// The largest lead either side held, in points, from the margin series.
    var largestLeads: (away: Int, home: Int) {
        let margins = margin.map(\.homeMargin)
        return (Int(max(0, -(margins.min() ?? 0))), Int(max(0, margins.max() ?? 0)))
    }
}

/// Team stats mix rated metrics with plain counts and the occasional null.
/// Decode each side key by key so one odd value can't drop the whole side.
private struct LossyDictionarySides: Decodable {
    let away: [String: RatedValue]
    let home: [String: RatedValue]

    private enum CodingKeys: String, CodingKey { case away, home }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        away = Self.side(c, .away)
        home = Self.side(c, .home)
    }

    private static func side(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String: RatedValue] {
        guard let raw = try? c.decode([String: Lossy<RatedValue>].self, forKey: key) else { return [:] }
        return raw.compactMapValues(\.value)
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
