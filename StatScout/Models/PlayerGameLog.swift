import Foundation

/// One player's line in one game (one row per player_type). Powers the box
/// score on a game page.
struct PlayerGameLog: Codable, Hashable, Sendable {
    let playerId: Int
    let season: Int
    /// Regular season or playoffs.
    let seasonPhase: SeasonPhase
    /// ESPN game id as text, e.g. "401859967". The join key to `Game`.
    /// Optional because rows ingested before the column existed carry none.
    var gameId: String? = nil
    let gameDate: Date
    let playerType: String
    let team: String?
    let opponent: String?
    /// Possessions used: field goal attempts + 0.44 free throw attempts + turnovers.
    let plays: Int
    /// Minutes played.
    let touches: Int
    let metrics: [String: Double?]

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case season
        case seasonPhase = "season_type"
        case gameId = "game_id"
        case gameDate = "game_date"
        case playerType = "player_type"
        case team
        case opponent
        case plays
        case touches
        case metrics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(Int.self, forKey: .playerId)
        season = try c.decode(Int.self, forKey: .season)
        // Defaulted rather than required: the fixtures in the test suite predate
        // the column, and a row with no phase is a regular-season row.
        seasonPhase = try c.decodeIfPresent(SeasonPhase.self, forKey: .seasonPhase) ?? .regular
        playerType = try c.decode(String.self, forKey: .playerType)
        gameId = try c.decodeIfPresent(String.self, forKey: .gameId)
        team = try c.decodeIfPresent(String.self, forKey: .team)
        opponent = try c.decodeIfPresent(String.self, forKey: .opponent)
        plays = try c.decodeIfPresent(Int.self, forKey: .plays) ?? 0
        touches = try c.decodeIfPresent(Int.self, forKey: .touches) ?? 0

        // game_date arrives as "YYYY-MM-DD" from Supabase (date column, not timestamptz).
        let raw = try c.decode(String.self, forKey: .gameDate)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        guard let parsed = formatter.date(from: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .gameDate, in: c, debugDescription: "Invalid game_date: \(raw)")
        }
        gameDate = parsed

        // metrics is a JSONB object with nullable numeric values.
        if let dict = try? c.decode([String: Double?].self, forKey: .metrics) {
            metrics = dict
        } else {
            metrics = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(season, forKey: .season)
        try c.encode(seasonPhase, forKey: .seasonPhase)
        try c.encode(playerType, forKey: .playerType)
        try c.encodeIfPresent(gameId, forKey: .gameId)
        try c.encodeIfPresent(team, forKey: .team)
        try c.encodeIfPresent(opponent, forKey: .opponent)
        try c.encode(plays, forKey: .plays)
        try c.encode(touches, forKey: .touches)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        try c.encode(formatter.string(from: gameDate), forKey: .gameDate)
        try c.encode(metrics, forKey: .metrics)
    }
}
