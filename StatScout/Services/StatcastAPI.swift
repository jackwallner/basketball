import Foundation

/// Returns true when a fetch ended only because its Swift task was superseded.
/// URLSession reports task cancellation as `URLError.cancelled`.
func isTaskCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
}

protocol StatcastProviding: Sendable {
    /// Every season before `season`, plus the career rollup.
    func fetchHistoricalPlayers(before season: Int) async throws -> [Player]
    /// The live season's snapshots.
    func fetchCurrentPlayers(season: Int) async throws -> [Player]
    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog]
    /// One player's rolling windows (1, 2 and 4 weeks) for a season and phase.
    func fetchPlayerRecentForm(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [RecentForm]
    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm]
    func fetchDataCoverage(season: Int) async throws -> DataCoverage?
    /// The publisher's single status row: what the calendar names, what the
    /// live revision covers, and how fresh each feed is.
    func fetchDataFreshness() async throws -> DataFreshness?
    func fetchGames(season: Int) async throws -> [Game]
    func fetchGameLogs(gameId: String) async throws -> [PlayerGameLog]
    func fetchGameIdsWithStats(season: Int) async throws -> Set<String>
    func fetchGameDetail(gameId: String) async throws -> GameDetail?
    func fetchPlayerProfiles(season: Int) async throws -> [PlayerProfile]
    func fetchTeamRatings(season: Int) async throws -> [TeamRating]
    func fetchGameProjections(season: Int) async throws -> [GameProjection]
}

extension StatcastProviding {
    /// Older test and preview providers do not need to know about the optional
    /// status endpoint. A missing implementation is treated as unavailable.
    func fetchDataFreshness() async throws -> DataFreshness? { nil }
    func fetchPlayerRecentForm(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [RecentForm] { [] }
    func fetchGames(season: Int) async throws -> [Game] { [] }
    func fetchGameLogs(gameId: String) async throws -> [PlayerGameLog] { [] }
    func fetchGameIdsWithStats(season: Int) async throws -> Set<String> { [] }
    func fetchGameDetail(gameId: String) async throws -> GameDetail? { nil }
    func fetchPlayerProfiles(season: Int) async throws -> [PlayerProfile] { [] }
    func fetchTeamRatings(season: Int) async throws -> [TeamRating] { [] }
    func fetchGameProjections(season: Int) async throws -> [GameProjection] { [] }
}

struct StatcastAPI: StatcastProviding {
    private let baseURL: URL
    private let apiKey: String

    init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    /// Everything older than the live season, plus the career rollup.
    ///
    /// The rollup is stored under `season = 0`, which is *below* `earliest`, so
    /// a plain `season.gte.2003` range quietly excluded it and All Time came
    /// back empty. Hence the `or`: the sentinel row or the real historical
    /// range. It still sorts into the historical cache partition, since 0 is
    /// less than the live season.
    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] {
        try await fetchPlayers(queryItems: [
            URLQueryItem(
                name: "or",
                value: "(season.eq.\(StatScoutSeason.allTime),"
                    + "and(season.gte.\(StatScoutSeason.earliest),"
                    + "season.lt.\(season)))"
            ),
        ])
    }

    func fetchCurrentPlayers(season: Int) async throws -> [Player] {
        try await fetchPlayers(queryItems: [
            URLQueryItem(name: "season", value: "eq.\(season)"),
        ])
    }

    /// One player's games, filtered to a single season *and phase*.
    ///
    /// The phase filter is not cosmetic. Playoff games are the newest rows a
    /// season has, so without it a date-descending game log for a team that
    /// reached June was mostly playoff basketball no matter which phase the user
    /// had selected.
    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        let endpoint = baseURL
            .appending(path: "rest/v1/player_game_logs")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "player_id", value: "eq.\(playerId)"),
                URLQueryItem(name: "season", value: "eq.\(season)"),
                URLQueryItem(name: "season_type", value: "eq.\(seasonPhase.rawValue)"),
                URLQueryItem(name: "order", value: "game_date.desc"),
            ])
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }

        let rows = try JSONDecoder.statScout.decode([Lenient<PlayerGameLog>].self, from: data)
        return rows.compactMap(\.value)
    }

    /// One player's rolling windows for a season and phase: one row per window
    /// length (and per player_type, for the rare player ranked in two cohorts).
    func fetchPlayerRecentForm(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [RecentForm] {
        let data = try await get("player_recent_form", [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "player_id", value: "eq.\(playerId)"),
            URLQueryItem(name: "season", value: "eq.\(season)"),
            URLQueryItem(name: "season_type", value: "eq.\(seasonPhase.rawValue)"),
        ])
        return try JSONDecoder.statScout.decode([Lenient<RecentForm>].self, from: data).compactMap(\.value)
    }

    /// The whole league's rolling window for one window length, in one paged
    /// fetch. The board ranks by delta, so it needs every qualifying player at
    /// once; there is no useful partial sort.
    ///
    /// Cache-bypassing for the same reason the game-log fetches are: the
    /// refresh rewrites these rows in place, and a stale window is worse than a
    /// slow one. The element decoder is lossy so a single malformed row can't
    /// empty the board.
    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm] {
        var all: [RecentForm] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let endpoint = baseURL
                .appending(path: "rest/v1/player_recent_form")
                .appending(queryItems: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "season", value: "eq.\(season)"),
                    URLQueryItem(name: "season_type", value: "eq.\(seasonPhase.rawValue)"),
                    URLQueryItem(name: "window_weeks", value: "eq.\(windowWeeks)"),
                    URLQueryItem(name: "order", value: "player_id.asc"),
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset)),
                ])
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }

            let rows = try JSONDecoder.statScout.decode([Lenient<RecentForm>].self, from: data)
            all.append(contentsOf: rows.compactMap(\.value))
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return all
    }

    /// One row, read for its coverage columns only.
    ///
    /// Ordered by `end_week` before `as_of` because the week is the answer the
    /// UI wants and a playoff row carries a higher week than any regular-season
    /// one, so the newest row is also the furthest through the season. `as_of`
    /// breaks the tie for the seasons ingested before the week columns existed,
    /// where `end_week` is null throughout.
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? {
        let endpoint = baseURL
            .appending(path: "rest/v1/player_recent_form")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "as_of,end_week,season_type"),
                URLQueryItem(name: "season", value: "eq.\(season)"),
                URLQueryItem(name: "as_of", value: "not.is.null"),
                URLQueryItem(
                    name: "order",
                    value: "end_week.desc.nullslast,as_of.desc"
                ),
                URLQueryItem(name: "limit", value: "1"),
            ])
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        struct Row: Decodable {
            let as_of: String?
            let end_week: Int?
            let season_type: String?
        }
        guard let row = try JSONDecoder().decode([Row].self, from: data).first,
              let raw = row.as_of else { return nil }

        // `as_of` is a Postgres `date`: "YYYY-MM-DD", not ISO8601. Same parse
        // RecentForm does, anchored to Eastern so a west-coast Sunday night
        // game doesn't roll the label onto Monday.
        let bits = raw.split(separator: "-").compactMap { Int($0) }
        guard bits.count == 3 else { return nil }
        var parts = DateComponents()
        parts.year = bits[0]
        parts.month = bits[1]
        parts.day = bits[2]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        guard let date = calendar.date(from: parts) else { return nil }

        return DataCoverage(
            asOf: date,
            week: row.end_week,
            phase: row.season_type.flatMap(SeasonPhase.init(rawValue:)) ?? .regular
        )
    }

    /// Reads the active, validated publisher revision. The backend exposes one
    /// current row through `data_refresh_status`; a missing table is harmless so
    /// app versions can roll out before the status migration reaches production.
    ///
    /// Deliberately not filtered by season: the row carries the season the
    /// calendar names *and* the season the live revision covers, and the app
    /// needs both to know which one to treat as live.
    func fetchDataFreshness() async throws -> DataFreshness? {
        guard let data = try await getOptional("data_refresh_status", [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "published_at.desc.nullslast,last_checked_at.desc"),
            URLQueryItem(name: "limit", value: "1"),
        ]) else { return nil }
        return try JSONDecoder.statScout.decode([DataFreshness].self, from: data).first
    }

    /// The whole season's schedule, regular season and playoffs, about 1,300
    /// rows. PostgREST caps a response at 1,000, so it pages.
    func fetchGames(season: Int) async throws -> [Game] {
        let pages = try await getAllPages("games", [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "season", value: "eq.\(season)"),
            URLQueryItem(name: "order", value: "kickoff_at.asc,game_id.asc"),
        ])
        return try pages.flatMap {
            try JSONDecoder.statScout.decode([Lenient<Game>].self, from: $0).compactMap(\.value)
        }
    }

    /// Every player's line from one game, for its box score.
    func fetchGameLogs(gameId: String) async throws -> [PlayerGameLog] {
        let data = try await get("player_game_logs", [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "game_id", value: "eq.\(gameId)"),
            URLQueryItem(name: "limit", value: "200"),
        ])
        return try JSONDecoder.statScout.decode([Lenient<PlayerGameLog>].self, from: data).compactMap(\.value)
    }

    /// Which games have their box score and advanced page published. The page is
    /// built from the same player rows, so `game_details` answers it for the
    /// whole season at a fraction of the payload of the game logs.
    func fetchGameIdsWithStats(season: Int) async throws -> Set<String> {
        struct Row: Decodable { let game_id: String? }
        let pages = try await getAllPages("game_details", [
            URLQueryItem(name: "select", value: "game_id"),
            URLQueryItem(name: "season", value: "eq.\(season)"),
            URLQueryItem(name: "order", value: "game_id.asc"),
        ])
        return Set(try pages.flatMap {
            try JSONDecoder().decode([Row].self, from: $0).compactMap(\.game_id)
        })
    }

    /// The play-by-play breakdown for one game, or nil before it is built.
    func fetchGameDetail(gameId: String) async throws -> GameDetail? {
        let data = try await get("game_details", [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "game_id", value: "eq.\(gameId)"),
            URLQueryItem(name: "limit", value: "1"),
        ])
        return try JSONDecoder.statScout.decode([GameDetail].self, from: data).first
    }

    /// Size, age and draft history for every player the live season ships,
    /// about 450 rows. Optional context: a missing table (a build newer than
    /// the backend) reads as no profiles, never as a player-data error.
    func fetchPlayerProfiles(season: Int) async throws -> [PlayerProfile] {
        var all: [PlayerProfile] = []
        let pageSize = 1000
        var offset = 0
        while true {
            guard let data = try await getOptional("player_profiles", [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "season", value: "eq.\(season)"),
                URLQueryItem(name: "order", value: "player_id.asc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]) else { return [] }
            let rows = try JSONDecoder.statScout.decode([Lenient<PlayerProfile>].self, from: data)
            all.append(contentsOf: rows.compactMap(\.value))
            if rows.count < pageSize { return all }
            offset += pageSize
        }
    }

    func fetchTeamRatings(season: Int) async throws -> [TeamRating] {
        guard let data = try await getOptional("team_ratings", [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "season", value: "eq.\(season)"),
            URLQueryItem(name: "order", value: "rank.asc"),
        ]) else { return [] }
        return try JSONDecoder.statScout.decode([Lenient<TeamRating>].self, from: data).compactMap(\.value)
    }

    func fetchGameProjections(season: Int) async throws -> [GameProjection] {
        let pages = try await getAllPages("game_projections", [
            URLQueryItem(name: "select", value: "game_id,home_margin,home_win_prob"),
            URLQueryItem(name: "season", value: "eq.\(season)"),
            URLQueryItem(name: "order", value: "game_id.asc"),
        ], optional: true)
        return try pages.flatMap {
            try JSONDecoder.statScout.decode([Lenient<GameProjection>].self, from: $0).compactMap(\.value)
        }
    }

    /// Every page of a table, 1,000 rows at a time (PostgREST's response cap).
    /// `optional` treats a missing table as no rows rather than an error.
    private func getAllPages(
        _ table: String,
        _ queryItems: [URLQueryItem],
        optional: Bool = false
    ) async throws -> [Data] {
        var pages: [Data] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let paged = queryItems + [
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            let data: Data
            if optional {
                guard let found = try await getOptional(table, paged) else { return pages }
                data = found
            } else {
                data = try await get(table, paged)
            }
            pages.append(data)
            // A page shorter than the cap is the last one. The row count is
            // read off the JSON array rather than assumed from the byte size.
            let count = (try? JSONSerialization.jsonObject(with: data) as? [Any])?.count ?? 0
            if count < pageSize { return pages }
            offset += pageSize
        }
    }

    /// `get`, except a missing table (404) is nil rather than an error.
    private func getOptional(_ table: String, _ queryItems: [URLQueryItem]) async throws -> Data? {
        let endpoint = baseURL
            .appending(path: "rest/v1/\(table)")
            .appending(queryItems: queryItems)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 404 { return nil }
        guard 200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func get(_ table: String, _ queryItems: [URLQueryItem]) async throws -> Data {
        let endpoint = baseURL
            .appending(path: "rest/v1/\(table)")
            .appending(queryItems: queryItems)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func fetchPlayers(queryItems filters: [URLQueryItem]) async throws -> [Player] {
        var all: [Player] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let queryItems = [
                URLQueryItem(name: "select", value: "*"),
                // Stable key so offset paging can't skip/duplicate rows when
                // updated_at changes mid-fetch.
                URLQueryItem(
                    name: "order",
                    value: "season.asc,season_type.asc,id.asc"
                ),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ] + filters
            let endpoint = baseURL
                .appending(path: "rest/v1/player_snapshots")
                .appending(queryItems: queryItems)
            // Bypass URLCache so the shared headshot cache can't serve a stale page.
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }

            let rows = try JSONDecoder.statScout.decode([Lenient<Player>].self, from: data)
            let page = rows.compactMap(\.value)
            // A non-empty page that decodes to zero players means the schema
            // changed under us - surface it instead of silently going blank.
            if !rows.isEmpty && page.isEmpty {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "All player rows failed to decode")
                )
            }
            all.append(contentsOf: page)
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return all
    }
}

/// Decodes an element if possible, otherwise yields nil instead of throwing,
/// so one malformed row cannot fail the entire page.
struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct OfflineStatcastAPI: StatcastProviding {
    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] { [] }
    func fetchCurrentPlayers(season: Int) async throws -> [Player] { [] }
    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
}

#if DEBUG
struct PreviewStatcastAPI: StatcastProviding {
    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] {
        SampleData.players.filter { ($0.season ?? 0) < season }
    }

    func fetchCurrentPlayers(season: Int) async throws -> [Player] {
        SampleData.players.filter { ($0.season ?? 0) >= season }
    }

    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        []
    }

    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm] {
        []
    }

    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
}
#endif

extension JSONDecoder {
    static var statScout: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: dateString) {
                return date
            }

            // Postgres/PostgREST emits variable-length fractional seconds
            // (e.g. "…40.95411+00:00"). ISO8601DateFormatter's
            // .withFractionalSeconds only accepts exactly 3 fractional digits
            // on some iOS versions, and the plain formatter rejects any
            // fractional part at all - so a 5-digit fraction fails BOTH above
            // and every row's required updated_at drops, surfacing as a bogus
            // "Data format changed" error. Strip the fraction and retry.
            if let dotRange = dateString.range(of: #"\.\d+"#, options: .regularExpression) {
                var stripped = dateString
                stripped.removeSubrange(dotRange)
                if let date = fallback.date(from: stripped) {
                    return date
                }
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        return decoder
    }
}
