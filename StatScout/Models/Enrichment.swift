import Foundation

/// Who a player is: size, age and how he entered the league, from
/// `public.player_profiles` (see `backend/ingest_enrichment.py`).
///
/// Every field is optional: a source that was late on the last run leaves its
/// columns null, and the screens that read them simply leave that line out. The
/// table also carries contract, snap-count and injury columns inherited from
/// the schema it was forked from; hoopR has no public source for them, so they
/// are always null and the app does not read them.
struct PlayerProfile: Decodable, Hashable, Sendable {
    let playerId: Int
    let season: Int
    var jersey: Int?
    var birthDate: Date?
    var heightInches: Int?
    var weightPounds: Int?
    var yearsExperience: Int?
    var draftYear: Int?
    var draftRound: Int?
    var draftPick: Int?

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case season
        case jersey
        case birthDate = "birth_date"
        case heightInches = "height_in"
        case weightPounds = "weight_lb"
        case yearsExperience = "years_exp"
        case draftYear = "draft_year"
        case draftRound = "draft_round"
        case draftPick = "draft_pick"
    }

    init(playerId: Int, season: Int) {
        self.playerId = playerId
        self.season = season
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(Int.self, forKey: .playerId)
        season = try c.decode(Int.self, forKey: .season)
        jersey = try c.decodeIfPresent(Int.self, forKey: .jersey)
        birthDate = try c.decodeIfPresent(String.self, forKey: .birthDate).flatMap(Self.day)
        heightInches = try c.decodeIfPresent(Int.self, forKey: .heightInches)
        weightPounds = try c.decodeIfPresent(Int.self, forKey: .weightPounds)
        yearsExperience = try c.decodeIfPresent(Int.self, forKey: .yearsExperience)
        draftYear = try c.decodeIfPresent(Int.self, forKey: .draftYear)
        draftRound = try c.decodeIfPresent(Int.self, forKey: .draftRound)
        draftPick = try c.decodeIfPresent(Int.self, forKey: .draftPick)
    }

    private static func day(_ raw: String) -> Date? {
        let bits = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard bits.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: DateComponents(year: bits[0], month: bits[1], day: bits[2]))
    }

    func age(on date: Date = .now) -> Int? {
        guard let birthDate else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.year], from: birthDate, to: date).year
    }

    /// "6-9, 250".
    var sizeLabel: String? {
        guard let heightInches, heightInches > 0 else { return nil }
        let height = "\(heightInches / 12)-\(heightInches % 12)"
        guard let weightPounds, weightPounds > 0 else { return height }
        return "\(height), \(weightPounds)"
    }

    /// "2003 R1 #1", or "Undrafted" for a player who came in without a pick.
    var draftLabel: String? {
        if let draftYear, let draftRound, let draftPick {
            return "\(draftYear) R\(draftRound) #\(draftPick)"
        }
        return yearsExperience != nil ? "Undrafted" : nil
    }
}

/// One team's power rating from `public.team_ratings`: points per 100
/// possessions better or worse than an average team, adjusted for schedule,
/// split into an offense and a defense half (positive is good for both). See
/// `backend/team_ratings.py`.
struct TeamRating: Decodable, Hashable, Sendable, Identifiable {
    let season: Int
    let team: String
    let rank: Int
    let games: Int
    let throughWeek: Int
    let rating: Double
    let offense: Double
    let defense: Double
    let schedule: Double
    let wins: Int
    let losses: Int
    let pointsFor: Int
    let pointsAgainst: Int

    var id: String { team }

    enum CodingKeys: String, CodingKey {
        case season, team, rank, games, rating, offense, defense, schedule, wins, losses
        case throughWeek = "through_week"
        case pointsFor = "points_for"
        case pointsAgainst = "points_against"
    }

    static func signed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "0.0" }
        return String(format: "%+.1f", rounded)
    }
}

/// A projected margin for an unplayed game, from the two power ratings plus
/// home court.
struct GameProjection: Decodable, Hashable, Sendable {
    let gameId: String
    let homeMargin: Double
    let homeWinProbability: Double

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case homeMargin = "home_margin"
        case homeWinProbability = "home_win_prob"
    }

    /// "SAS by 4.5", "Toss-up" under a point.
    func label(home: String, away: String) -> String {
        let margin = abs(homeMargin)
        guard margin >= 1 else { return "Toss-up" }
        let favourite = homeMargin > 0 ? home : away
        return "\(displayTeamAbbr(favourite)) by \(String(format: "%.1f", (margin * 2).rounded() / 2))"
    }

    func winProbability(for team: String, home: String) -> Double {
        normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(home)
            ? homeWinProbability
            : 1 - homeWinProbability
    }
}

/// A team's line in the standings, from posted finals.
struct StandingsRow: Hashable, Sendable, Identifiable {
    let team: String
    var wins = 0
    var losses = 0
    var pointsFor = 0
    var pointsAgainst = 0
    /// "W2", "L1"; nil before a game.
    var streak: String?

    var id: String { team }
    var games: Int { wins + losses }
    var differential: Int { pointsFor - pointsAgainst }
    var winPercentage: Double {
        games == 0 ? 0 : Double(wins) / Double(games)
    }

    var record: String { "\(wins)-\(losses)" }

    /// Regular-season finals only, oldest first so the streak reads off the end.
    static func build(from games: [Game], teams: [String]) -> [String: StandingsRow] {
        var rows = Dictionary(uniqueKeysWithValues: teams.map { ($0, StandingsRow(team: $0)) })
        let finals = games
            .filter { $0.seasonPhase == .regular && $0.isFinal }
            .sorted { ($0.tipoff ?? $0.gameDate) < ($1.tipoff ?? $1.gameDate) }
        var results: [String: [String]] = [:]
        for game in finals {
            for side in [game.homeTeam, game.awayTeam] {
                let team = normalizedTeamAbbreviation(side)
                guard var row = rows[team],
                      let result = game.result(for: side),
                      let mine = game.score(of: side),
                      let theirs = game.score(of: game.opponent(of: side)) else { continue }
                if result == "W" { row.wins += 1 } else { row.losses += 1 }
                row.pointsFor += mine
                row.pointsAgainst += theirs
                rows[team] = row
                results[team, default: []].append(result)
            }
        }
        for (team, list) in results {
            guard let last = list.last else { continue }
            let run = list.reversed().prefix { $0 == last }.count
            rows[team]?.streak = "\(last)\(run)"
        }
        return rows
    }

    /// Win percentage, then point differential, then name: not the NBA's full
    /// tiebreaker ladder, and the Standings screen says so.
    static func ordered(_ rows: [StandingsRow]) -> [StandingsRow] {
        rows.sorted {
            if $0.winPercentage != $1.winPercentage { return $0.winPercentage > $1.winPercentage }
            if $0.differential != $1.differential { return $0.differential > $1.differential }
            return $0.team < $1.team
        }
    }
}
