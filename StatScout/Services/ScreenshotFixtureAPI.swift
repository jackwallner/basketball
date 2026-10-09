#if DEBUG
import Foundation

/// Deterministic rows used only by the release screenshot harness. They are real
/// 2025-26 numbers for real players (see `ScreenshotFixtureData`), so a capture
/// shows what the app shows, while keeping a screenshot run independent of
/// network timing, source publication lag, and the shared simulator's cache.
///
/// Two statuses are served, chosen with `-ScreenshotSeasonStatus`:
/// - `pending` (the default, and what the app really reads between October 1 and
///   opening night): 2025-26 is the live season and 2026-27 is a schedule.
/// - `published`: 2025-26 is live with nothing pending after it.
struct ScreenshotFixtureAPI: StatcastProviding {
    static let launchArgument = "-ScreenshotData"
    static let statusArgument = "-ScreenshotSeasonStatus"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    enum Status: String {
        case published
        case pending
    }

    static var status: Status {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: statusArgument), index + 1 < arguments.count else {
            return .pending
        }
        return Status(rawValue: arguments[index + 1]) ?? .pending
    }

    /// Seeds only the local simulator's fan context for a capture. The hook is
    /// called from `StatScoutApp` before `ContentView` is created, which makes
    /// the Following board deterministic without teaching a product view about
    /// test data.
    static func prepareUserDefaults() {
        let defaults = UserDefaults.standard
        // Gilgeous-Alexander, Wembanyama, Jokic.
        defaults.set([4278073, 5104157, 3112335], forKey: "favorites.playerIds")
        defaults.set("NYK", forKey: "favoriteTeam")
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set("standard", forKey: "stats.board")
        defaults.removeObject(forKey: "statcast.dataFreshness")
        defaults.removeObject(forKey: "statcast.displayedDataRevision")
        StatScoutSeason.remember(
            .init(season: season, upcoming: status == .pending ? upcomingSeason : nil),
            defaults: defaults
        )
    }

    static let season = 2026
    static let upcomingSeason = 2027
    private static let priorSeason = season - 1
    /// The last game of the 2025-26 Finals, the coherent capture date.
    private static let asOf = makeDate("2026-06-14T04:00:00Z")

    private static let allPlayers: [Player] = decode(ScreenshotFixtureData.playersJSON)
    private static let allGames: [Game] = decode(ScreenshotFixtureData.gamesJSON)

    private static func decode<T: Decodable>(_ json: String) -> [T] {
        let rows = try? JSONDecoder.statScout.decode([Lenient<T>].self, from: Data(json.utf8))
        return rows?.compactMap(\.value) ?? []
    }

    /// The fixture's player rows, for previews.
    static var players: [Player] { allPlayers }

    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] {
        Self.allPlayers.filter { ($0.season ?? 0) < season }
    }

    func fetchCurrentPlayers(season: Int) async throws -> [Player] {
        Self.allPlayers.filter { $0.season == season }
    }

    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        guard seasonPhase == .regular,
              season == Self.season,
              let player = Self.allPlayers.first(where: { $0.playerId == playerId && $0.season == season })
        else { return [] }
        return Self.makeGameLogs(for: player)
    }

    func fetchPlayerRecentForm(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [RecentForm] {
        guard seasonPhase == .regular,
              season == Self.season,
              let player = Self.allPlayers.first(where: { $0.playerId == playerId && $0.season == season })
        else { return [] }
        return RecentWindow.allCases.compactMap { Self.makeRecentForm(for: player, windowWeeks: $0.rawValue) }
    }

    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm] {
        guard seasonPhase == .regular, season == Self.season else { return [] }
        return Self.allPlayers
            .filter { $0.season == season }
            .compactMap { Self.makeRecentForm(for: $0, windowWeeks: windowWeeks) }
    }

    func fetchDataCoverage(season: Int) async throws -> DataCoverage? {
        guard season == Self.season else { return nil }
        return DataCoverage(asOf: Self.asOf, week: 37, phase: .regular, gamesIncluded: 1316, expectedGames: 1316)
    }

    func fetchDataFreshness() async throws -> DataFreshness? {
        let pending = Self.status == .pending
        return DataFreshness(
            status: pending ? .pending : .ready,
            revision: "screenshot-fixture-v1",
            sourcePublishedAt: nil,
            publishedAt: Self.asOf,
            checkedAt: Self.asOf,
            coverage: DataCoverage(asOf: Self.asOf, week: 37, phase: .regular, gamesIncluded: 1316, expectedGames: 1316),
            message: nil,
            isCached: false,
            shotsStatus: "ready",
            playByPlayStatus: "ready",
            rawStatus: pending ? "source_pending" : "published",
            season: pending ? Self.upcomingSeason : Self.season,
            publishedSeason: Self.season,
            lastErrorCode: pending ? "season_pending" : nil
        )
    }

    func fetchGames(season: Int) async throws -> [Game] {
        Self.allGames.filter { $0.season == season }
    }

    func fetchGameLogs(gameId: String) async throws -> [PlayerGameLog] {
        let logs: [PlayerGameLog] = Self.decode(ScreenshotFixtureData.gameLogsJSON)
        return logs.filter { $0.gameId == gameId }
    }

    func fetchGameIdsWithStats(season: Int) async throws -> Set<String> {
        guard let detail = try await fetchGameDetail(gameId: Self.finalsGameID) else { return [] }
        return season == Self.season ? [detail.gameId] : []
    }

    private static let finalsGameID = "401859967"

    func fetchGameDetail(gameId: String) async throws -> GameDetail? {
        let details: [GameDetail] = Self.decode(ScreenshotFixtureData.gameDetailJSON)
        return details.first { $0.gameId == gameId }
    }

    func fetchPlayerProfiles(season: Int) async throws -> [PlayerProfile] {
        Self.decode(ScreenshotFixtureData.profilesJSON)
    }

    func fetchTeamRatings(season: Int) async throws -> [TeamRating] {
        season == Self.season ? Self.decode(ScreenshotFixtureData.ratingsJSON) : []
    }

    func fetchGameProjections(season: Int) async throws -> [GameProjection] {
        Self.decode(ScreenshotFixtureData.projectionsJSON)
    }
}

extension ScreenshotFixtureAPI {
    /// A stable value in -1...1 for a name, so the same capture always draws the
    /// same wobble.
    private static func unit(_ text: String) -> Double {
        let hash = text.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1.value)) &* 1_099_511_628_211
        }
        return Double(hash % 2_001) / 1_000 - 1
    }

    private static func perGame(_ player: Player, _ label: String) -> Double? {
        player.standardStats?.first { $0.label == label }.flatMap { metricNumericValue($0.value) }
    }

    /// Six games leading up to the capture date, each a seeded wobble around the
    /// player's season averages.
    static func makeGameLogs(for player: Player) -> [PlayerGameLog] {
        let games = perGame(player, "G") ?? 60
        func pair(_ label: String) -> (made: Double, attempts: Double) {
            let parts = player.standardStats?.first { $0.label == label }?.value
                .split(separator: "/", maxSplits: 1)
                .compactMap { metricNumericValue(String($0)) } ?? []
            return parts.count == 2 ? (parts[0] / games, parts[1] / games) : (0, 0)
        }
        let fg = pair("FG"), three = pair("3P"), ft = pair("FT")
        let opponents = ["PHX", "POR", "DEN", "MEM", "UTA", "SAC"]
        return (0..<6).compactMap { index in
            let u = unit("\(player.playerId)-\(index)")
            let factor = 1 + 0.25 * u
            var metrics: [String: Double?] = [
                "min": (perGame(player, "MPG") ?? 30).rounded(),
                "pts": ((perGame(player, "PPG") ?? 15) * factor).rounded(),
                "reb": ((perGame(player, "RPG") ?? 4) * factor).rounded(),
                "ast": ((perGame(player, "APG") ?? 3) * factor).rounded(),
                "stl": ((perGame(player, "SPG") ?? 1) * (1 + 0.5 * u)).rounded(),
                "blk": ((perGame(player, "BPG") ?? 0.5) * (1 + 0.5 * u)).rounded(),
                "tov": 2,
                "pf": 2,
                "fgm": (fg.made * factor).rounded(),
                "fga": (fg.attempts * (1 + 0.1 * u)).rounded(),
                "fg3m": (three.made * factor).rounded(),
                "fg3a": three.attempts.rounded(),
                "ftm": (ft.made * factor).rounded(),
                "fta": ft.attempts.rounded(),
                "starter": 1,
            ]
            metrics["plus_minus"] = (u * 12).rounded()
            guard let date = Calendar.current.date(byAdding: .day, value: -((5 - index) * 2), to: asOf) else { return nil }
            return PlayerGameLog(
                fixturePlayerId: player.playerId,
                season: player.season ?? season,
                gameDate: date,
                playerType: player.playerType ?? "f",
                team: player.team,
                opponent: opponents[index],
                plays: 18,
                touches: Int((perGame(player, "MPG") ?? 30).rounded()),
                metrics: metrics
            )
        }
    }

    /// A rolling window built from the player's own season metrics: the current
    /// span wobbles a few percent around the season figure and the prior span
    /// sits on the other side of it, so Trends has both risers and fallers.
    static func makeRecentForm(for player: Player, windowWeeks: Int) -> RecentForm? {
        let games = max(1, min(windowWeeks * 3, Int(perGame(player, "G") ?? 3)))
        let seasonGames = perGame(player, "G") ?? 60
        var metrics: [String: Double] = [:]
        var priorMetrics: [String: Double] = [:]
        var delta: [String: Double] = [:]
        for metric in player.metrics {
            guard let key = RecentMetricKey.key(for: metric.label),
                  let value = metricNumericValue(metric.value) else { continue }
            let u = unit("\(player.playerId)-\(key)-\(windowWeeks)")
            let current: Double
            let prior: Double
            if RecentMetricKey.isSeasonTotal(metric.label) {
                current = (value / seasonGames * Double(games) * (1 + 0.15 * u)).rounded()
                prior = (value / seasonGames * Double(games)).rounded()
            } else {
                current = value * (1 + 0.1 * u)
                prior = value * (1 - 0.06 * u)
            }
            metrics[key] = current
            priorMetrics[key] = prior
            delta[key] = current - prior
        }
        let minutes = Int(((perGame(player, "MPG") ?? 30) * Double(games)).rounded())
        let json: [String: Any] = [
            "player_id": player.playerId,
            "season": player.season ?? season,
            "season_type": "REG",
            "player_type": player.playerType ?? "f",
            "window_weeks": windowWeeks,
            "as_of": "2026-04-12",
            "start_week": 28 - windowWeeks + 1,
            "end_week": 28,
            "team": player.team,
            "games": games,
            "plays": games * 18,
            "touches": minutes,
            "metrics": metrics,
            "prior_metrics": priorMetrics,
            "delta": delta,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder.statScout.decode(RecentForm.self, from: data)
    }

    static func makeDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date(timeIntervalSince1970: 1_0)
    }
}

private extension PlayerGameLog {
    /// Built through the decoder so the fixture goes through the same code path
    /// as a database row.
    init(
        fixturePlayerId: Int,
        season: Int,
        gameDate: Date,
        playerType: String,
        team: String?,
        opponent: String?,
        plays: Int,
        touches: Int,
        metrics: [String: Double?]
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        var json: [String: Any] = [
            "player_id": fixturePlayerId,
            "season": season,
            "season_type": "REG",
            "game_date": formatter.string(from: gameDate),
            "player_type": playerType,
            "plays": plays,
            "touches": touches,
            "metrics": metrics.compactMapValues { $0 },
        ]
        json["team"] = team
        json["opponent"] = opponent
        // The row shape is fixed above, so the decode cannot fail.
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        self = (try? JSONDecoder().decode(PlayerGameLog.self, from: data))!
    }
}

/// In-memory cache used by the screenshot app hook. The production model loads
/// historical rows lazily from its bundled plist; this cache lets the same
/// lazy path exercise the fixture's prior season without touching disk.
struct ScreenshotFixtureCache: PlayerCaching {
    func loadPlayers() throws -> [Player] {
        ScreenshotFixtureAPI.players
    }

    func savePlayers(_ players: [Player], liveSeason: Int) throws {}
}
#endif
