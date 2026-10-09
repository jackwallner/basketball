import Foundation

/// The state users need to understand while a new source release moves
/// through the pipeline. The server may use more specific names, but the app
/// keeps the presentation vocabulary small and stable.
enum DataFreshnessStatus: String, Codable, CaseIterable, Sendable {
    case ready
    case checking
    case pending
    case partial
    case stale
    case offline
    case failed

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "ready", "published", "complete", "completed", "healthy", "unchanged":
            self = .ready
        case "checking", "probing", "building", "retrying":
            self = .checking
        case "pending", "waiting", "waiting_for_source", "source_pending":
            self = .pending
        case "partial", "degraded":
            self = .partial
        case "stale", "regressed":
            self = .stale
        case "offline", "unavailable":
            self = .offline
        case "failed", "error":
            self = .failed
        default:
            self = .ready
        }
    }

    var iconName: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .pending: "clock.badge.exclamationmark"
        case .partial: "circle.lefthalf.filled"
        case .stale: "clock.arrow.circlepath"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var accessibilityName: String {
        switch self {
        case .ready: "Ready"
        case .checking: "Checking"
        case .pending: "Waiting for source data"
        case .partial: "Partial data"
        case .stale: "Stale data"
        case .offline: "Offline"
        case .failed: "Refresh failed"
        }
    }
}

/// Coverage describes the games included in a dataset. It is intentionally
/// separate from the time the database row was written.
struct DataCoverage: Sendable, Equatable, Codable {
    /// Date of the last game included.
    let asOf: Date
    /// Calendar-week number of that game (counted from the season's October
    /// epoch), when the rollup carries one. The app labels coverage by date.
    let week: Int?
    let phase: SeasonPhase
    /// Number of completed games included, when the publisher exposes it.
    let gamesIncluded: Int?
    /// Number of completed games expected for this revision, when known.
    let expectedGames: Int?

    init(
        asOf: Date,
        week: Int?,
        phase: SeasonPhase,
        gamesIncluded: Int? = nil,
        expectedGames: Int? = nil
    ) {
        self.asOf = asOf
        self.week = week
        self.phase = phase
        self.gamesIncluded = gamesIncluded
        self.expectedGames = expectedGames
    }
}

/// The backend contract consumed by the app.
///
/// The preferred endpoint is `GET /rest/v1/data_refresh_status` with one
/// active row for the requested season. The current publisher exposes
/// `refresh_id`, `source_published_at`, `published_at`, `last_checked_at`,
/// `max_week`, `max_game_date`, `observed_games`, `expected_games`, `status`,
/// `season_type`, plus the two season columns that drive the rollover:
/// `season` (the season the calendar names) and `published_season` (the season
/// the live revision covers). Older names and nested coverage are accepted
/// during rollout so the app can ship before every environment has the view.
struct DataFreshness: Codable, Equatable, Sendable {
    let status: DataFreshnessStatus
    let revision: String?
    let sourcePublishedAt: Date?
    let publishedAt: Date?
    let checkedAt: Date?
    let coverage: DataCoverage?
    let message: String?
    let isCached: Bool
    /// Publisher state of the optional enrichment feeds ("ready", "pending").
    /// A complete slate of games can still be waiting on these. The columns keep
    /// the names they had before the NBA: `ngs_status` is the shot feed and
    /// `pfr_status` is the play-by-play feed.
    var shotsStatus: String? = nil
    var playByPlayStatus: String? = nil
    /// The status string as the publisher wrote it ("source_pending",
    /// "published", ...). `status` folds several of these together, and the
    /// season rollover needs to tell `source_pending` from a plain pending.
    var rawStatus: String? = nil
    /// The season the calendar names, which can be ahead of the data.
    var season: Int? = nil
    /// The season the live revision actually covers.
    var publishedSeason: Int? = nil
    var lastErrorCode: String? = nil

    /// The new season has started on the calendar but has no games played yet:
    /// the schedule exists, the box scores do not, and the last published
    /// revision still describes the previous season. Nothing is wrong, so the
    /// app keeps the finished season as the live one and says when the new one
    /// starts.
    var isSeasonPending: Bool {
        guard rawStatus?.lowercased() == "source_pending",
              lastErrorCode?.lowercased() == "season_pending",
              let season, let publishedSeason else { return false }
        return season > publishedSeason
    }

    /// True while the shot or play-by-play feed has not caught up with the
    /// games already published.
    var isAdvancedPending: Bool {
        [shotsStatus, playByPlayStatus].contains { status in
            guard let status = status?.lowercased() else { return false }
            return status != "ready" && status != "not_applicable" && status != "unavailable"
        }
    }

    init(
        status: DataFreshnessStatus = .ready,
        revision: String? = nil,
        sourcePublishedAt: Date? = nil,
        publishedAt: Date? = nil,
        checkedAt: Date? = nil,
        coverage: DataCoverage? = nil,
        message: String? = nil,
        isCached: Bool = false,
        shotsStatus: String? = nil,
        playByPlayStatus: String? = nil,
        rawStatus: String? = nil,
        season: Int? = nil,
        publishedSeason: Int? = nil,
        lastErrorCode: String? = nil
    ) {
        self.status = status
        self.revision = revision
        self.sourcePublishedAt = sourcePublishedAt
        self.publishedAt = publishedAt
        self.checkedAt = checkedAt
        self.coverage = coverage
        self.message = message
        self.isCached = isCached
        self.shotsStatus = shotsStatus
        self.playByPlayStatus = playByPlayStatus
        self.rawStatus = rawStatus
        self.season = season
        self.publishedSeason = publishedSeason
        self.lastErrorCode = lastErrorCode
    }

    /// Returns a copy with local display state changed without altering the
    /// server timestamps or revision.
    func replacing(
        status: DataFreshnessStatus? = nil,
        revision: String?? = nil,
        checkedAt: Date?? = nil,
        coverage: DataCoverage?? = nil,
        message: String?? = nil,
        isCached: Bool? = nil
    ) -> DataFreshness {
        DataFreshness(
            status: status ?? self.status,
            revision: revision ?? self.revision,
            sourcePublishedAt: sourcePublishedAt,
            publishedAt: publishedAt,
            checkedAt: checkedAt ?? self.checkedAt,
            coverage: coverage ?? self.coverage,
            message: message ?? self.message,
            isCached: isCached ?? self.isCached,
            shotsStatus: shotsStatus,
            playByPlayStatus: playByPlayStatus,
            // A local display override (offline, failed) is no longer what the
            // publisher said, so the raw string goes with it.
            rawStatus: status == nil ? rawStatus : nil,
            season: season,
            publishedSeason: publishedSeason,
            lastErrorCode: lastErrorCode
        )
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case revision
        case refreshID = "refresh_id"
        case sourceFingerprint = "source_fingerprint"
        case sourcePublishedAt = "source_published_at"
        case publishedAt = "published_at"
        case checkedAt = "checked_at"
        case lastCheckedAt = "last_checked_at"
        case asOf = "as_of"
        case maxGameDate = "max_game_date"
        case week
        case endWeek = "end_week"
        case maxWeek = "max_week"
        case seasonType = "season_type"
        case gamesIncluded = "games_included"
        case gamesThrough = "games_through"
        case observedGames = "observed_games"
        case expectedGames = "expected_games"
        case coverage
        case message
        case errorMessage = "error_message"
        case cached = "is_cached"
        case ngsStatus = "ngs_status"
        case pfrStatus = "pfr_status"
        case season
        case publishedSeason = "published_season"
        case lastErrorCode = "last_error_code"
    }

    private struct CoveragePayload: Decodable {
        let asOf: String?
        let week: Int?
        let endWeek: Int?
        let seasonType: String?
        let gamesIncluded: Int?
        let gamesThrough: Int?
        let expectedGames: Int?

        private enum CodingKeys: String, CodingKey {
            case asOf = "as_of"
            case week
            case endWeek = "end_week"
            case seasonType = "season_type"
            case gamesIncluded = "games_included"
            case gamesThrough = "games_through"
            case expectedGames = "expected_games"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let rawStatus = try c.decodeIfPresent(String.self, forKey: .status) ?? "ready"
        status = DataFreshnessStatus(rawValue: rawStatus)
        self.rawStatus = rawStatus
        season = try c.decodeIfPresent(Int.self, forKey: .season)
        publishedSeason = try c.decodeIfPresent(Int.self, forKey: .publishedSeason)
        lastErrorCode = try c.decodeIfPresent(String.self, forKey: .lastErrorCode)
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
            ?? c.decodeIfPresent(String.self, forKey: .refreshID)
            ?? c.decodeIfPresent(String.self, forKey: .sourceFingerprint)
        sourcePublishedAt = Self.decodeDate(c, key: .sourcePublishedAt)
        publishedAt = Self.decodeDate(c, key: .publishedAt)
        checkedAt = Self.decodeDate(c, key: .checkedAt)
            ?? Self.decodeDate(c, key: .lastCheckedAt)
        message = try c.decodeIfPresent(String.self, forKey: .message)
            ?? c.decodeIfPresent(String.self, forKey: .errorMessage)
        isCached = try c.decodeIfPresent(Bool.self, forKey: .cached) ?? false
        shotsStatus = try c.decodeIfPresent(String.self, forKey: .ngsStatus)
        playByPlayStatus = try c.decodeIfPresent(String.self, forKey: .pfrStatus)

        let nestedCoverage: CoveragePayload?
        do {
            nestedCoverage = try c.decodeIfPresent(CoveragePayload.self, forKey: .coverage)
        } catch {
            nestedCoverage = nil
        }
        let rawAsOf = try c.decodeIfPresent(String.self, forKey: .asOf)
            ?? c.decodeIfPresent(String.self, forKey: .maxGameDate)
            ?? nestedCoverage?.asOf
        let rawWeek = try c.decodeIfPresent(Int.self, forKey: .week)
            ?? c.decodeIfPresent(Int.self, forKey: .endWeek)
            ?? c.decodeIfPresent(Int.self, forKey: .maxWeek)
            ?? nestedCoverage?.week
            ?? nestedCoverage?.endWeek
        let rawPhase = try c.decodeIfPresent(String.self, forKey: .seasonType)
            ?? nestedCoverage?.seasonType
        let asOf = rawAsOf.flatMap(Self.parseDate)
        let phase = rawPhase.flatMap(SeasonPhase.init(rawValue:)) ?? .regular
        let gamesIncluded = try c.decodeIfPresent(Int.self, forKey: .gamesIncluded)
            ?? c.decodeIfPresent(Int.self, forKey: .gamesThrough)
            ?? c.decodeIfPresent(Int.self, forKey: .observedGames)
            ?? nestedCoverage?.gamesIncluded
            ?? nestedCoverage?.gamesThrough
        let expectedGames = try c.decodeIfPresent(Int.self, forKey: .expectedGames)
            ?? nestedCoverage?.expectedGames

        if let asOf {
            coverage = DataCoverage(
                asOf: asOf,
                week: rawWeek,
                phase: phase,
                gamesIncluded: gamesIncluded,
                expectedGames: expectedGames
            )
        } else {
            coverage = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rawStatus ?? status.rawValue, forKey: .status)
        try c.encodeIfPresent(revision, forKey: .revision)
        try c.encodeIfPresent(Self.formatDate(sourcePublishedAt), forKey: .sourcePublishedAt)
        try c.encodeIfPresent(Self.formatDate(publishedAt), forKey: .publishedAt)
        try c.encodeIfPresent(Self.formatDate(checkedAt), forKey: .checkedAt)
        try c.encodeIfPresent(Self.formatDate(coverage?.asOf), forKey: .asOf)
        try c.encodeIfPresent(coverage?.week, forKey: .week)
        try c.encodeIfPresent(coverage?.phase.rawValue, forKey: .seasonType)
        try c.encodeIfPresent(coverage?.gamesIncluded, forKey: .gamesIncluded)
        try c.encodeIfPresent(coverage?.expectedGames, forKey: .expectedGames)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encode(isCached, forKey: .cached)
        try c.encodeIfPresent(shotsStatus, forKey: .ngsStatus)
        try c.encodeIfPresent(playByPlayStatus, forKey: .pfrStatus)
        try c.encodeIfPresent(season, forKey: .season)
        try c.encodeIfPresent(publishedSeason, forKey: .publishedSeason)
        try c.encodeIfPresent(lastErrorCode, forKey: .lastErrorCode)
    }

    private static func decodeDate(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Date? {
        guard let raw = try? container.decode(String.self, forKey: key) else { return nil }
        return parseDate(raw)
    }

    private static func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // Formatters are expensive to build and this runs once per schedule row
    // (twice a game), so they are made once. Reading from them is thread-safe.
    nonisolated(unsafe) private static let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let easternDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter
    }()

    static func parseDate(_ raw: String) -> Date? {
        if let date = fractionalISO.date(from: raw) { return date }
        if let date = plainISO.date(from: raw) { return date }
        if let date = easternDay.date(from: raw) { return date }
        // Postgres writes a variable-length fraction ("...38.20338+00:00"), which
        // the fractional formatter only accepts at exactly three digits. Drop it:
        // the second is precise enough for every date the app shows.
        if let dot = raw.range(of: #"\.\d+"#, options: .regularExpression) {
            var stripped = raw
            stripped.removeSubrange(dot)
            return plainISO.date(from: stripped)
        }
        return nil
    }
}

extension DataCoverage {
    /// Game dates arrive without a time and are parsed as Eastern midnight, the
    /// league's calendar. Formatting them in the phone's zone showed the day
    /// before anywhere west of New York (Oct 21 games read "Oct 20" in Seattle).
    static var gameDayStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return style
    }
}

/// Small persistence layer for the last known-good status. This is separate
/// from the player cache so a failed status check cannot replace useful data.
enum DataFreshnessCache {
    private static let key = "statcast.dataFreshness"
    private static let displayedRevisionKey = "statcast.displayedDataRevision"

    static func load(defaults: UserDefaults = .standard) -> DataFreshness? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.statScout.decode(DataFreshness.self, from: data)
    }

    static func save(
        _ freshness: DataFreshness,
        displayedRevision: String?,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder.statScout.encode(freshness) else { return }
        defaults.set(data, forKey: key)
        defaults.set(displayedRevision, forKey: displayedRevisionKey)
    }

    static func loadDisplayedRevision(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: displayedRevisionKey)
    }
}
