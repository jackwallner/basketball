import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let provider: StatcastProviding
    private let cache: PlayerCaching?
    /// Where the resolved live season is remembered between launches.
    private let defaults: UserDefaults

    var players: [Player] = []
    var playerHistories: [Int: [Player]] = [:] {
        didSet {
            rostersBySeason.removeAll()
            sortMetricCache = nil
        }
    }
    /// Season rosters cut from `playerHistories`, rebuilt only when it changes.
    /// Every board reads its roster several times per render, and each cut
    /// walks every season the app holds.
    @ObservationIgnored private var rostersBySeason: [String: [Player]] = [:]
    var searchText = ""
    var selectedConference: NBAConference = .all
    var selectedPosition: PlayerPositionGroup = .all {
        didSet {
            guard oldValue != selectedPosition else { return }
            userSortMetric = nil
            applyDefaultSortDirection()
        }
    }

    private var userSortMetric: String?
    var sortDescending = true
    var selectedSeason: Int
    var selectedPhase: SeasonPhase = .regular

    var sortLabel: String { currentSortMetric ?? "Top Metric" }

    var currentSortMetric: String? {
        if let userSortMetric, availableSortMetrics.contains(userSortMetric) {
            return userSortMetric
        }
        return determineSortMetricLabel()
    }

    var availableSortMetrics: [String] { sortMetricLists.all }

    var availableAdvancedSortMetrics: [String] { sortMetricLists.advanced }

    private struct SortMetricLists {
        let key: String
        let eligible: [Metric]
        let all: [String]
        let advanced: [String]
    }

    /// The metrics the current board can rank by, worked out once per season,
    /// phase and position rather than on every read: the menus, the sort chip
    /// and the qualifier gate all ask several times per render, and each
    /// answer walks every metric of every player in the season.
    @ObservationIgnored private var sortMetricCache: SortMetricLists?

    private var sortMetricLists: SortMetricLists {
        let roster = seasonPlayers
        let position = selectedPosition
        let key = "\(selectedSeason)-\(selectedPhase.rawValue)-\(position.rawValue)"
        if let sortMetricCache, sortMetricCache.key == key { return sortMetricCache }

        let eligible = roster
            .filter { position.includes($0) }
            .flatMap(\.metrics)
            .filter { BasketballMetricRegistry.isSupported($0, by: position) }
        var seenPairs = Set<String>()
        let distinct = eligible.filter { seenPairs.insert("\($0.label)|\($0.category.rawValue)").inserted }
        var seenLabels = Set<String>()
        let all = BasketballMetricRegistry.sorted(distinct)
            .filter { seenLabels.insert($0.label).inserted }
            .map(\.label)
        let advancedLabels = Set(distinct.filter {
            BasketballMetricRegistry.definition(for: $0.label, category: $0.category)?.kind == .advanced
        }.map(\.label))
        let lists = SortMetricLists(
            key: key,
            eligible: eligible,
            all: all,
            advanced: all.filter { advancedLabels.contains($0) }
        )
        sortMetricCache = lists
        return lists
    }

    func setUserSortMetric(_ label: String?) {
        userSortMetric = label
        applyDefaultSortDirection()
    }

    /// Call when the user explicitly flips direction (header tap / menu item)
    /// so the auto-default doesn't stomp their preference until they change
    /// the active metric or category.
    func toggleSortDirection() {
        sortDescending.toggle()
    }

    /// Reset direction to "best first" for the active metric. Triggered by
    /// category changes and by picking a new sort metric - but only when the
    /// user hasn't manually pinned a direction in this session.
    private func applyDefaultSortDirection() {
        guard let label = currentSortMetric,
              let metric = eligibleMetrics.first(where: { $0.label == label }) else {
            sortDescending = true
            return
        }
        sortDescending = BasketballMetricRegistry.definition(for: label, category: metric.category)?.higherIsBetter ?? true
    }
    // Mirrors StoreService.isPro. Set by the view layer so season gating and
    // selectedSeason clamping stay consistent without the VM depending on the store.
    var isPro: Bool = false

    /// The newest season with published data, resolved from the publisher's
    /// status (`StatScoutSeason.resolveLive`). Between October 1 and opening
    /// night this is still the finished season; when the status flips to the new
    /// one every screen follows, with no release.
    private(set) var live: StatScoutSeason.Live {
        // The slate switches schedules when the live season moves.
        didSet { scheduleCache = ScheduleCache() }
    }

    /// The season a free user gets: the live season, whatever has loaded. The
    /// moment a season is live it is the free, default year, and every season
    /// before it is StatScout+.
    var freeSeason: Int { live.season }

    /// A scheduled season with no games played yet (the 2026-27 slate in
    /// October 2026), or nil once it has data or when nothing is pending.
    var upcomingSeason: Int? { live.upcoming }

    /// Whether the live season is over and the next has not started: the cue
    /// for "2025-26 · final" captions and the "starts Oct 20" line.
    var isSeasonPending: Bool { live.isPending }

    /// "2025-26 · final" while the next season is pending, "2025-26" otherwise.
    func liveSeasonCaption() -> String {
        isSeasonPending
            ? "\(SeasonLabel.text(freeSeason)) · final"
            : SeasonLabel.text(freeSeason)
    }

    /// When the pending season's first game is played, "Oct 20", or nil.
    var upcomingSeasonStart: String? {
        guard isSeasonPending,
              let first = upcomingGames.filter({ $0.seasonPhase == .regular }).map(\.gameDate).min()
        else { return nil }
        return first.formatted(DataCoverage.gameDayStyle)
    }

    /// "2026-27 starts Oct 20", the line that sits beside a final season.
    var upcomingSeasonStartsText: String? {
        guard let upcomingSeason, let start = upcomingSeasonStart else { return nil }
        return "\(SeasonLabel.text(upcomingSeason)) starts \(start)"
    }

    func isSeasonLocked(_ season: Int) -> Bool {
        !isPro && season != freeSeason
    }

    /// The season Recent form opens on: the live one.
    var recentFormSeason: Int { freeSeason }

    /// The seasons Recent form is offered for: the live one and the one before it.
    ///
    /// Recent is a rolling last-N-weeks window read off `player_recent_form`,
    /// and that rollup is not kept for all time: a "last 2 weeks" board for
    /// 2011-12 is a historical curiosity nobody opened, and the game logs behind
    /// it were the single biggest thing in the database, so everything older was
    /// purged. Last season survives the cut deliberately. A season does not stop
    /// being worth a form board the moment the next one tips off, and pinning
    /// this to the live season alone left a hole every October: Trends would go
    /// blank for the year you were actually still reading about.
    ///
    /// Newest first, so a menu built from this needs no further sorting. Floored
    /// at `earliestRecentForm`, the oldest season the rollup table has ever
    /// held - without that, while 2025-26 is live "the one before" is a year with
    /// no rows and the menu offers a board that can only come back empty. The
    /// live season here is the one with published rows, so a pending 2026-27 is
    /// never offered before it has any.
    var recentFormSeasons: [Int] {
        [recentFormSeason, recentFormSeason - 1]
            .filter { $0 >= StatScoutSeason.earliestRecentForm }
    }

    /// Whether Recent/Both controls should appear for this season at all.
    /// False hides the control rather than locking it: it is not a Pro upsell,
    /// the data does not exist.
    func supportsRecentForm(_ season: Int) -> Bool { recentFormSeasons.contains(season) }

    /// Switch season, and fetch what that season needs.
    ///
    /// Season history is loaded lazily - the launch path only fetches the live
    /// season, because decoding thirty-three thousand historical rows is the
    /// slowest thing the app does and most sessions never leave the current
    /// year. Nothing was triggering that load from the nav bar, though, so
    /// picking any past season (and All Time most visibly, since it is the
    /// first row of the menu) dropped you on an empty board with no spinner and
    /// no explanation. Whether it recovered came down to whether you had
    /// happened to open the Compare tab earlier in the session, which is the
    /// only place that asked for history.
    ///
    /// Setting the season first and loading second is deliberate: the header
    /// updates on the tap, so the screen acknowledges you immediately and the
    /// board fills in behind it.
    func selectSeason(_ season: Int) {
        selectedSeason = season
        guard !hasLoadedHistorical, season != freeSeason else { return }
        seasonLoadTask = Task { await loadHistoricalIfNeeded() }
    }

    /// Held only so tests can await the load the tap kicked off. Nothing in the
    /// app reads it: the board is driven by `isHistoricalLoading` and the
    /// resulting data, not by the task.
    private(set) var seasonLoadTask: Task<Void, Never>?

    /// Push Pro state in from the view and re-clamp the selected season so a free
    /// user can never land on (and silently render) a locked past season.
    func applyProState(_ pro: Bool) {
        isPro = pro
        clampSelectedSeason()
    }

    private func clampSelectedSeason() {
        guard isSeasonLocked(selectedSeason) else { return }
        let target = availableSeasons.first(where: { !isSeasonLocked($0) }) ?? freeSeason
        if selectedSeason != target { selectedSeason = target }
    }

    // Start true so the very first frame shows a spinner, not a "No data for 2026" empty state
    // before saved players or the network feed resolves.
    var isLoading = true
    var isHistoricalLoading = false
    var hasLoadedHistorical = false
    var loadingMessage = "Starting up…"
    var loadingProgress = 0.05
    var errorMessage: String?
    var lastFetchFailed = false
    /// The last failure was the network, not the data.
    ///
    /// Drives the offline framing on the empty board: "Data Error" beside a
    /// warning triangle is a claim about the stats, and on a first run with no
    /// signal the stats are fine and the phone is not.
    var lastFailureWasConnectivity = false
    private var hasStartedLoading = false
    private var loadTask: Task<Void, Never>?
    private var freshnessCheckTask: Task<FreshnessCheckResult, Never>?
    private var lastForegroundCheckAt: Date?
    private var lastStatusCheckAt: Date?

    /// The latest status returned by the publisher. This is persisted as a
    /// small metadata cache so offline users can still see an honest boundary.
    var dataFreshness: DataFreshness?
    /// Revision actually represented by the player and recent-form data on
    /// screen. It can lag the server revision while a new version is pending.
    private(set) var displayedDataRevision: String?
    private(set) var localLastCheckedAt: Date?

    /// The revision cards should use in their task identity. It changes only
    /// after a validated current dataset has been accepted, so a server probe
    /// cannot make a profile or team card discard good data prematurely.
    var freshnessRevision: String? { displayedDataRevision }

    var freshnessForDisplay: DataFreshness? {
        guard let remote = dataFreshness else { return nil }
        let dataFreshness = remote.replacing(coverage: .some(dataCoverage))
        if lastFetchFailed {
            return dataFreshness.replacing(
                status: .failed,
                message: .some(errorMessage ?? "Showing saved data while the latest refresh is retried."),
                isCached: .some(true)
            )
        }
        guard dataFreshness.status == .ready,
              let serverRevision = dataFreshness.revision,
              let displayedDataRevision,
              serverRevision != displayedDataRevision else {
            return dataFreshness
        }
        return dataFreshness.replacing(
            status: .stale,
            message: .some("New game data is ready, but this screen is still showing the last complete revision."),
            isCached: .some(true)
        )
    }

    var freshnessStatus: DataFreshnessStatus {
        if lastFetchFailed { return .failed }
        return freshnessForDisplay?.status ?? (players.isEmpty && isLoading ? .checking : .ready)
    }

    var lastCheckedAt: Date? { localLastCheckedAt ?? dataFreshness?.checkedAt }

    var isRefreshing: Bool {
        loadTask != nil || freshnessCheckTask != nil
    }

    enum FreshnessCheckResult: Equatable, Sendable {
        case unavailable
        case unchanged
        case updated
        case pending
        case partial
        case stale
        case failed
        case throttled
    }

    var isReady: Bool { !players.isEmpty }

    private var _teamScores: [String: Double] = [:]
    private var _teamsWithData: [String] = []
    private var _teamCacheSeason: Int?
    private var _teamCachePhase: SeasonPhase?

    var teamScores: [String: Double] {
        if _teamCacheSeason != selectedSeason || _teamCachePhase != selectedPhase {
            recomputeTeamCache()
        }
        return _teamScores
    }

    var teamsWithData: [String] {
        if _teamCacheSeason != selectedSeason || _teamCachePhase != selectedPhase {
            recomputeTeamCache()
        }
        return _teamsWithData
    }

    var teamCounts: [String: Int] {
        Dictionary(grouping: seasonPlayers) { normalizedTeamAbbreviation($0.team) }
            .mapValues(\.count)
    }

    var lastUpdated: Date? {
        players.map(\.updatedAt).max()
    }

    /// The last game the data actually covers, as opposed to when the rows were
    /// written. See `DataCoverage`.
    var dataCoverage: DataCoverage?

    var freshnessText: String? {
        guard let lastUpdated else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: lastUpdated))"
    }

    /// Fetch per-game logs for a single player. Powers the Last game and Game log
    /// cards on the profile.
    ///
    /// The phase is a parameter rather than read off `selectedPhase` because a
    /// player page carries its own: opening a 2025-26 playoff profile from a
    /// regular-season board has to fetch that player's playoff games, not the
    /// tab's.
    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        try await provider.fetchGameLogs(
            playerId: playerId,
            season: season,
            seasonPhase: seasonPhase
        )
    }

    // MARK: - Launch prefetch

    /// Network reads started before the first screen is built.
    ///
    /// The app spends its first second or two creating views on the main thread,
    /// and the status row and the live season's players are plain network calls
    /// that do not need it. Starting them from `ContentView.init` lets the
    /// download overlap that work instead of waiting for it. `performLoad` takes
    /// each result exactly once and falls back to a normal fetch for anything
    /// that was not prefetched, or was prefetched for a season that turned out
    /// not to be live.
    private struct Prefetch {
        let season: Int
        var players: Task<[Player], Error>?
        var freshness: Task<DataFreshness?, Error>?
    }

    private var prefetch: Prefetch?

    /// Idempotent. Call once, as early as possible; a no-op once a load has
    /// started or when the screenshot and preview providers are in use.
    func startPrefetch() {
        guard prefetch == nil, !hasStartedLoading else { return }
        let provider = provider
        let season = live.season
        prefetch = Prefetch(
            season: season,
            players: Task.detached { try await provider.fetchCurrentPlayers(season: season) },
            freshness: Task.detached { try await provider.fetchDataFreshness() }
        )
        StartupTrace.mark("prefetch started")
    }

    private func takePrefetchedFreshness() -> Task<DataFreshness?, Error>? {
        defer { prefetch?.freshness = nil }
        return prefetch?.freshness
    }

    /// The live season's players: the prefetched copy when it is for this
    /// season, otherwise a fresh fetch.
    private func fetchLivePlayers(season: Int) async throws -> [Player] {
        if let pending = prefetch {
            prefetch = nil
            if pending.season == season, let task = pending.players {
                return try await task.value
            }
            pending.players?.cancel()
            pending.freshness?.cancel()
        }
        return try await provider.fetchCurrentPlayers(season: season)
    }

    init(
        provider: StatcastProviding,
        cache: PlayerCaching? = nil,
        defaults: UserDefaults = .standard,
        calendarSeason: Int = StatScoutSeason.calendarSeason()
    ) {
        self.provider = provider
        self.cache = cache
        self.defaults = defaults
        let initial = StatScoutSeason.initialLive(defaults: defaults, calendarSeason: calendarSeason)
        self.live = initial
        self.selectedSeason = initial.season
        if cache != nil, let cachedFreshness = DataFreshnessCache.load() {
            self.dataFreshness = cachedFreshness.replacing(isCached: .some(true))
            self.dataCoverage = cachedFreshness.coverage
            self.displayedDataRevision = DataFreshnessCache.loadDisplayedRevision()
            self.localLastCheckedAt = cachedFreshness.checkedAt
        }
    }

    #if DEBUG
    convenience init() {
        self.init(provider: PreviewStatcastAPI())
    }
    #endif

    // Keep the full supported range visible even before historical data loads.
    // Free users can discover older seasons in the menu and see that they are
    // part of StatScout+, rather than seeing a misleading single-year picker.
    var availableSeasons: [Int] {
        // Runs through the live season, which is always offered (and is the
        // default) from the day it has published data.
        var seasons = Set(StatScoutSeason.earliest...max(freeSeason, StatScoutSeason.earliest))
        seasons.formUnion(playerHistories.values.flatMap { $0 }.compactMap(\.season))
        // The career rollup sits under season 0, so a plain descending sort would
        // bury "All Time" underneath 2002-03. It belongs at the top of the menu, as
        // the widest possible frame rather than the narrowest.
        let years = seasons.subtracting([StatScoutSeason.allTime]).sorted(by: >)
        return [StatScoutSeason.allTime] + years
    }

    /// Seasons offered where a career rollup makes no sense.
    ///
    /// Two screens are excluded, for different reasons.
    ///
    /// **Trends** ranks the last 1/2/4 *weeks* against the span before them,
    /// which is a question about one season in progress. There is no such thing
    /// as the last four weeks of all time, and the rolling-window table has no
    /// rows under the sentinel, so offering it there would only ever produce an
    /// empty board.
    ///
    /// **Teams** is the subtler one. A career row carries whichever team the
    /// player *last* played for, because that is what a career aggregate can
    /// know - the rollup has no per-franchise split. So "Boston, All Time"
    /// would list players who happened to finish there, crediting them with
    /// production earned elsewhere, and would file LeBron James's whole career
    /// under whichever team he played for last. That is not franchise all-time
    /// leaders; it just looks enough like it to be believed. Until the pipeline
    /// stores a per-team career split, not offering it is the honest answer.
    var seasonsExcludingAllTime: [Int] {
        availableSeasons.filter { !StatScoutSeason.isAllTime($0) }
    }

    // Players filtered by selected season - pull from histories to get all years.
    // Returns empty when the selected season has no data so callers render an empty state
    // instead of falling back to a stale "latest snapshot" set.
    var seasonPlayers: [Player] {
        players(forSeason: selectedSeason, phase: selectedPhase)
    }

    // MARK: - Games

    /// The live season's schedule and posted finals, from `public.games`.
    private(set) var games: [Game] = [] {
        didSet { scheduleCache = ScheduleCache() }
    }
    /// The next season's schedule while it is pending: scheduled games with no
    /// scores, loaded beside the live season so the Games tab has a front door
    /// in October.
    private(set) var upcomingGames: [Game] = [] {
        didSet { scheduleCache = ScheduleCache() }
    }

    /// Answers derived from the schedule, kept until the next load replaces
    /// it. The Games strip and every team disk on the Teams grid ask for these
    /// on each render, and each answer otherwise walks the whole season.
    private struct ScheduleCache {
        var slateDays: [GameDay]?
        var gamesByDay: [String: [Game]]?
        var records: [String: String?] = [:]
    }
    @ObservationIgnored private var scheduleCache = ScheduleCache()
    /// Games whose advanced breakdown is published, so a final can say whether
    /// its box score is in yet.
    private(set) var gameIdsWithStats: Set<String> = []
    private(set) var isGamesLoading = false
    private(set) var gamesError: String?
    private(set) var gamesLoadedAt: Date?
    private var gamesTask: Task<Void, Never>?

    /// What the Games tab strip is drawn from: the upcoming slate while the next
    /// season is pending, the live season otherwise.
    var slateGames: [Game] { isSeasonPending && !upcomingGames.isEmpty ? upcomingGames : games }

    /// Every day on the slate, in order.
    var slateDays: [GameDay] {
        let slate = slateGames
        if let days = scheduleCache.slateDays { return days }
        let days = GameDay.days(in: slate)
        scheduleCache.slateDays = days
        return days
    }

    var currentGameDay: GameDay? { GameDay.current(among: slateDays) }

    /// The slate's games on one day.
    func slateGames(on day: GameDay) -> [Game] {
        let slate = slateGames
        if scheduleCache.gamesByDay == nil {
            scheduleCache.gamesByDay = Dictionary(grouping: slate) {
                Self.dayKey(GameDay(date: $0.gameDate, phase: $0.seasonPhase))
            }
        }
        return scheduleCache.gamesByDay?[Self.dayKey(day)] ?? []
    }

    private static func dayKey(_ day: GameDay) -> String {
        "\(day.id)|\(day.phase.rawValue)"
    }

    /// The last day of games the live season played, for the "how it ended" card
    /// under the upcoming slate. Empty unless the next season is pending.
    var lastPlayedGames: [Game] {
        guard isSeasonPending else { return [] }
        let finals = games.filter(\.isFinal)
        guard let day = finals.map(\.gameDate).max() else { return [] }
        return Game.slateOrder(finals.filter { $0.gameDate == day })
    }

    // MARK: - Enrichment

    /// Bio and draft history for the live season, keyed by player. Optional
    /// context: empty until `player_profiles` answers, and every screen that
    /// reads it leaves the line out rather than waiting.
    private(set) var profiles: [Int: PlayerProfile] = [:]
    /// Power ratings for the live season, keyed by normalized team.
    private(set) var teamRatings: [String: TeamRating] = [:]
    /// Projected margins for unplayed games, keyed by game id.
    private(set) var projections: [String: GameProjection] = [:]

    func profile(for player: Player) -> PlayerProfile? {
        guard let profile = profiles[player.playerId], profile.season == player.season else { return nil }
        return profile
    }

    func teamRating(_ team: String) -> TeamRating? {
        teamRatings[normalizedTeamAbbreviation(team)]
    }

    func projection(for game: Game) -> GameProjection? {
        game.isFinal ? nil : projections[game.id]
    }

    private func loadProfiles() async {
        guard let loaded = try? await provider.fetchPlayerProfiles(season: freeSeason),
              !loaded.isEmpty else { return }
        profiles = Dictionary(loaded.map { ($0.playerId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// League standings from posted finals, every team present.
    var standings: [String: StandingsRow] {
        StandingsRow.build(from: games, teams: nbaTeamAbbreviations)
    }

    /// Loads the schedule, at most once a minute unless forced. Failures keep
    /// whatever schedule is already on screen.
    func loadGames(force: Bool = false) async {
        if let gamesTask {
            await gamesTask.value
            return
        }
        if !force, let gamesLoadedAt, Date().timeIntervalSince(gamesLoadedAt) < 60 {
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performGamesLoad()
        }
        gamesTask = task
        await task.value
    }

    private func performGamesLoad() async {
        defer { gamesTask = nil }
        isGamesLoading = games.isEmpty && upcomingGames.isEmpty
        let season = freeSeason
        let upcoming = upcomingSeason
        do {
            // Everything the Games tab needs goes out at once. The next season's
            // schedule used to wait for this season's to finish, and the
            // ratings and projections for both, which added up to several
            // sequential round trips.
            async let schedule = provider.fetchGames(season: season)
            async let withStats = provider.fetchGameIdsWithStats(season: season)
            async let nextSchedule = fetchUpcomingGames(upcoming)
            async let ratings = try? provider.fetchTeamRatings(season: season)
            async let projected = try? provider.fetchGameProjections(season: upcoming ?? season)
            let (loadedGames, loadedIds) = try await (schedule, withStats)
            StartupTrace.mark("games fetched (\(loadedGames.count) rows)")
            if !loadedGames.isEmpty || games.isEmpty {
                games = loadedGames
            }
            if upcoming != nil {
                upcomingGames = (await nextSchedule) ?? upcomingGames
            } else {
                upcomingGames = []
            }
            StartupTrace.mark("upcoming games fetched")
            gameIdsWithStats = loadedIds
            gamesError = nil
            gamesLoadedAt = Date()
            // Ratings and projections ride along with the schedule they
            // describe. Optional: a failure keeps whatever was there. The
            // projections belong to the season whose games are still to come.
            if let loadedRatings = await ratings, !loadedRatings.isEmpty {
                teamRatings = Dictionary(
                    loadedRatings.map { (normalizedTeamAbbreviation($0.team), $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
            if let loadedProjections = await projected {
                projections = Dictionary(
                    loadedProjections.map { ($0.gameId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
        } catch {
            if !isTaskCancellation(error) {
                gamesError = "Couldn't load games. Check your connection and try again."
            }
        }
        isGamesLoading = false
    }

    private func fetchUpcomingGames(_ season: Int?) async -> [Game]? {
        guard let season else { return nil }
        return try? await provider.fetchGames(season: season)
    }

    func game(id: String) -> Game? {
        games.first { $0.id == id } ?? upcomingGames.first { $0.id == id }
    }

    /// A team's game on the day the Games tab calls current, or nil on an off
    /// night.
    func currentGame(forTeam team: String) -> Game? {
        guard let day = currentGameDay else { return nil }
        return slateGames(on: day).first { $0.involves(team) }
    }

    /// Regular-season record from posted finals, "52-30". When `through` is
    /// given, only games tipped off up to and including it count. A game from
    /// another season has no record in the live one.
    func record(forTeam team: String, through game: Game? = nil) -> String? {
        if let game, game.season != freeSeason { return nil }
        guard game == nil else { return computeRecord(forTeam: team, through: game) }
        _ = games
        if let cached = scheduleCache.records[team] { return cached }
        let record = computeRecord(forTeam: team, through: nil)
        scheduleCache.records[team] = .some(record)
        return record
    }

    private func computeRecord(forTeam team: String, through game: Game?) -> String? {
        let cutoff = game?.tipoff ?? .distantFuture
        let finals = games.filter {
            $0.seasonPhase == .regular && $0.isFinal && $0.involves(team)
                && ($0.tipoff ?? $0.gameDate) <= cutoff
        }
        guard !finals.isEmpty else { return nil }
        let results = finals.compactMap { $0.result(for: team) }
        let wins = results.filter { $0 == "W" }.count
        let losses = results.filter { $0 == "L" }.count
        return "\(wins)-\(losses)"
    }

    /// Every game on a team's schedule, in tip-off order: the live season, then
    /// the upcoming one while it is pending.
    func schedule(forTeam team: String) -> [Game] {
        (games + upcomingGames).filter { $0.involves(team) }
            .sorted { ($0.tipoff ?? $0.gameDate) < ($1.tipoff ?? $1.gameDate) }
    }

    func hasStats(_ game: Game) -> Bool {
        gameIdsWithStats.contains(game.id)
    }

    func fetchGameDetail(gameId: String) async throws -> GameDetail? {
        try await provider.fetchGameDetail(gameId: gameId)
    }

    func fetchGameLogs(gameId: String) async throws -> [PlayerGameLog] {
        try await provider.fetchGameLogs(gameId: gameId)
    }

    /// The live-season player row for a game-log line, for names and links.
    func player(id: Int, season: Int, phase: SeasonPhase) -> Player? {
        (playerHistories[id] ?? []).first { $0.season == season && $0.seasonPhase == phase }
            ?? (playerHistories[id] ?? []).first { $0.season == season }
    }

    // MARK: - Recent form

    /// Rolling windows keyed by length, cached per season so flipping between
    /// 1 / 2 / 4 weeks doesn't refetch what's already in hand.
    var recentFormByWindow: [Int: [Int: RecentForm]] = [:]
    var recentFormLoadingWindows: Set<Int> = []
    var recentFormError: String?
    private var recentFormContext: String?
    private var recentFormTasks: [Int: Task<Void, Never>] = [:]

    /// The window the Trends board and the trend arrows read from.
    ///
    /// Two weeks (about seven games), so movement exists from the fifth week of
    /// the season. Four left the paid board with nothing to rank through the
    /// first month, which is when the installs happen.
    var recentWindow: TrendWindow = .twoWeeks

    /// True while a board is showing recent form rather than season totals.
    /// Pro-gated at the call site, free users get a blurred teaser.
    var showingRecent = false

    func recentForm(
        for playerId: Int,
        window: TrendWindow? = nil,
        season: Int? = nil,
        phase: SeasonPhase? = nil
    ) -> RecentForm? {
        let targetSeason = season ?? selectedSeason
        let targetPhase = phase ?? selectedPhase
        return recentFormByWindow[(window ?? recentWindow).rawValue]?[playerId]
            .flatMap {
                $0.season == targetSeason && $0.seasonPhase == targetPhase ? $0 : nil
            }
    }

    var isRecentFormLoading: Bool {
        recentFormLoadingWindows.contains(recentWindow.rawValue)
    }

    /// The last game date covered by the loaded window, for honest labelling.
    func recentFormAsOf(
        window: TrendWindow,
        season: Int,
        phase: SeasonPhase
    ) -> Date? {
        recentFormRowsByWindow[window.rawValue]?
            .filter { $0.season == season && $0.seasonPhase == phase }
            .compactMap(\.asOf)
            .max()
    }

    /// Every row for a window in one position cohort. The Trends board ranks
    /// within one cohort, so it needs the rows a per-player dictionary throws
    /// away: a player traded between cohorts' worth of minutes can have a row
    /// per `player_type`.
    func recentFormRows(
        window: TrendWindow,
        playerType: String,
        season: Int,
        phase: SeasonPhase
    ) -> [RecentForm] {
        (recentFormRowsByWindow[window.rawValue] ?? [])
            .filter {
                $0.playerType == playerType
                    && $0.season == season
                    && $0.seasonPhase == phase
            }
    }

    /// The whole league's rows for a window, loading them first if they are not
    /// in hand. The team page's Recent mode needs every team's rows, not just
    /// its own: a team's recent form is ranked against the other teams'.
    func leagueRecentForm(
        window: TrendWindow,
        season: Int,
        phase: SeasonPhase
    ) async -> [RecentForm] {
        await loadRecentFormIfNeeded(window: window, season: season, phase: phase)
        return (recentFormRowsByWindow[window.rawValue] ?? []).filter {
            $0.season == season && $0.seasonPhase == phase
        }
    }

    /// One player's rolling windows (1, 2 and 4 weeks) for the profile's Recent
    /// card. A passthrough for the same reason `fetchGameLogs` is: the card stays
    /// UI-only.
    func fetchPlayerRecentForm(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [RecentForm] {
        try await provider.fetchPlayerRecentForm(
            playerId: playerId,
            season: season,
            seasonPhase: seasonPhase
        )
    }

    private var recentFormRowsByWindow: [Int: [RecentForm]] = [:]

    /// Clears every league recent-form window after a new active data revision
    /// is adopted. In-flight requests are cancelled so an older response cannot
    /// repopulate a newer snapshot.
    func invalidateRecentFormCache() {
        for task in recentFormTasks.values { task.cancel() }
        recentFormTasks.removeAll()
        recentFormLoadingWindows.removeAll()
        recentFormByWindow.removeAll()
        recentFormRowsByWindow.removeAll()
        recentFormContext = nil
        recentFormError = nil
    }

    func reloadRecentForm(
        window: TrendWindow? = nil,
        season: Int? = nil,
        phase: SeasonPhase? = nil
    ) async {
        let target = window ?? recentWindow
        recentFormTasks[target.rawValue]?.cancel()
        recentFormTasks.removeValue(forKey: target.rawValue)
        recentFormByWindow.removeValue(forKey: target.rawValue)
        recentFormRowsByWindow.removeValue(forKey: target.rawValue)
        recentFormError = nil
        await loadRecentFormIfNeeded(window: target, season: season, phase: phase)
    }

    func loadRecentFormIfNeeded(
        window: TrendWindow? = nil,
        season: Int? = nil,
        phase: SeasonPhase? = nil
    ) async {
        let target = window ?? recentWindow
        let targetSeason = season ?? selectedSeason
        let targetPhase = phase ?? selectedPhase
        // Season changed under us, the cache describes a different year.
        let context = "\(targetSeason)-\(targetPhase.rawValue)"
        if recentFormContext != context {
            for task in recentFormTasks.values { task.cancel() }
            recentFormTasks.removeAll()
            recentFormLoadingWindows.removeAll()
            recentFormByWindow.removeAll()
            recentFormRowsByWindow.removeAll()
            recentFormContext = context
        }
        guard recentFormByWindow[target.rawValue] == nil else { return }

        if let inFlight = recentFormTasks[target.rawValue] {
            await inFlight.value
            return
        }

        recentFormLoadingWindows.insert(target.rawValue)
        recentFormError = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.recentFormLoadingWindows.remove(target.rawValue)
                self.recentFormTasks.removeValue(forKey: target.rawValue)
            }
            do {
                let rows = try await self.provider.fetchRecentForm(
                    season: targetSeason,
                    seasonPhase: targetPhase,
                    windowWeeks: target.rawValue
                )
                guard self.recentFormContext == context,
                      rows.allSatisfy({
                          $0.season == targetSeason && $0.seasonPhase == targetPhase
                      }) else { return }
                var byPlayer: [Int: RecentForm] = [:]
                for row in rows {
                    if let existing = byPlayer[row.playerId],
                       existing.plays >= row.plays { continue }
                    byPlayer[row.playerId] = row
                }
                self.recentFormByWindow[target.rawValue] = byPlayer
                self.recentFormRowsByWindow[target.rawValue] = rows
            } catch {
                if !isTaskCancellation(error) {
                    self.recentFormError = "Couldn't load recent form."
                }
            }
        }
        recentFormTasks[target.rawValue] = task
        await task.value
    }

    /// Unique players for an arbitrary season, not just the selected one.
    /// Drill-down leaderboards opened from a player profile need the season
    /// that profile is showing, which can differ from `selectedSeason`.
    func players(forSeason season: Int, phase: SeasonPhase? = nil) -> [Player] {
        let targetPhase = phase ?? selectedPhase
        // Read before the cache so the caller still observes the histories.
        let histories = playerHistories
        let key = "\(season)-\(targetPhase.rawValue)"
        if let cached = rostersBySeason[key] { return cached }
        let all = histories.values.flatMap { $0 }.filter {
            $0.season == season && $0.seasonPhase == targetPhase
        }
        var seen = Set<Int>()
        let roster = all.filter { seen.insert($0.playerId).inserted }
        rostersBySeason[key] = roster
        return roster
    }

    /// Teams whose name or abbreviation matches the current search.
    ///
    /// Searching used to only ever narrow the list of players. Someone typing
    /// "knicks" is usually after New York, so the team itself is now a result:
    /// one tap to the team page, with the roster still filtered underneath if
    /// that's what they wanted.
    var searchedTeams: [String] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return teamsWithData
            .filter {
                selectedConference.contains(team: $0)
                    && (
                        teamFullName($0).localizedCaseInsensitiveContains(query)
                            || $0.localizedCaseInsensitiveContains(query)
                    )
            }
            .sorted { teamFullName($0) < teamFullName($1) }
    }

    private var eligibleMetrics: [Metric] { sortMetricLists.eligible }

    var filteredPlayers: [Player] {
        // Resolved once: it walks every metric in the season.
        let gateLabel = qualifierLevel == .qualified ? currentSortMetricLabelForGate : nil
        return seasonPlayers.filter { player in
            let matchesSearch = searchText.isEmpty
                || player.name.localizedCaseInsensitiveContains(searchText)
                || player.team.localizedCaseInsensitiveContains(searchText)
                || teamFullName(player.team).localizedCaseInsensitiveContains(searchText)
            let matchesPosition = selectedPosition.includes(player)
            let matchesConference = matchesSelectedConference(player)
            let matchingMetrics = player.metrics.filter {
                BasketballMetricRegistry.isSupported($0, by: selectedPosition)
            }
            let qualifies = isQualifiedForBoard(player, metrics: matchingMetrics, sortLabel: gateLabel)
            return matchesSearch
                && matchesPosition
                && matchesConference
                && !matchingMetrics.isEmpty
                && qualifies
        }
    }

    func matchesSelectedConference(_ player: Player) -> Bool {
        selectedConference.contains(team: player.team)
    }

    enum QualifierLevel: String, CaseIterable, Identifiable {
        case all = "All Players"
        case qualified = "Qualified"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .all: return "Small samples dimmed"
            case .qualified: return "Playing-time minimum"
            }
        }
    }

    /// All players by default, with small samples dimmed and sorted below
    /// qualified players. Users can choose Qualified in the View menu to hide
    /// the small samples.
    var qualifierLevel: QualifierLevel = DashboardViewModel.storedQualifierLevel {
        didSet { UserDefaults.standard.set(qualifierLevel.rawValue, forKey: Self.qualifierKey) }
    }

    private static let qualifierKey = "stats.qualifier"

    private static var storedQualifierLevel: QualifierLevel {
        UserDefaults.standard.string(forKey: qualifierKey).flatMap(QualifierLevel.init(rawValue:)) ?? .all
    }

    func isQualified(_ player: Player, for category: MetricCategory?) -> Bool {
        switch qualifierLevel {
        case .all:
            return true
        case .qualified:
            return isPlayerQualified(player, in: category)
        }
    }

    /// Whether a player clears the bar, whatever the filter says: the feed's own
    /// prorated minutes flag.
    func isPlayerQualified(_ player: Player, in category: MetricCategory?) -> Bool {
        Self.hasQualifyingMetric(player, in: category)
    }

    /// Per metric: a shooter over the minutes bar is not thereby qualified for a
    /// Corner 3% board he has not taken 30 corner threes for.
    func isQualified(_ player: Player, metric: Metric) -> Bool {
        metric.qualified != false
    }

    /// The board's gate: qualified for the metric it is ranked by, or for any
    /// of its metrics when it has no sort yet.
    private func isQualifiedForBoard(_ player: Player, metrics: [Metric], sortLabel: String?) -> Bool {
        guard qualifierLevel == .qualified else { return true }
        if let label = sortLabel,
           let metric = metrics.first(where: { $0.label == label }) {
            return isQualified(player, metric: metric)
        }
        return metrics.contains { isQualified(player, metric: $0) }
    }

    /// The sort label without re-entering `filteredPlayers` (which
    /// `currentSortMetric` reads through `eligibleMetrics`).
    private var currentSortMetricLabelForGate: String? {
        userSortMetric ?? determineSortMetricLabel()
    }

    /// The live season flags each metric; past seasons only ever shipped
    /// qualifying rows, so there a metric's presence is the signal.
    static func hasQualifyingMetric(_ player: Player, in category: MetricCategory?) -> Bool {
        player.metrics.contains {
            (category == nil || $0.category == category) && $0.qualified != false
        }
    }

    var leaderboard: [Player] {
        guard let label = currentSortMetric,
              let referenceMetric = eligibleMetrics.first(where: { $0.label == label }) else {
            return filteredPlayers.sorted { $0.name < $1.name }
        }
        let sorted = filteredPlayers.sorted(
            by: Self.metricComparator(
                label: label,
                category: referenceMetric.category,
                descending: sortDescending,
                acrossCohorts: selectedPosition == .all
            )
        )
        // Small samples go below the rest, in the same order, so the top of a
        // board is never a one-target receiver. Only reachable under "All
        // players"; the default filter already leaves them out.
        let isSmall: (Player) -> Bool = { [unowned self] player in
            guard let metric = player.metrics.first(where: {
                $0.label == label && $0.category == referenceMetric.category
            }) else { return false }
            return !self.isQualified(player, metric: metric)
        }
        return sorted.filter { !isSmall($0) } + sorted.filter(isSmall)
    }

    /// Board subtitle volume: "1,820 min".
    func volumeCaption(for player: Player, category: MetricCategory?) -> String? {
        player.volumeCaption(for: category ?? player.primaryCategory)
    }

    /// Rank by the backend's direction-correct percentile, then use the raw
    /// number only to break a tied percentile bucket. Percentile-only metrics
    /// remain rankable instead of being swept below every printable value.
    ///
    /// `acrossCohorts` is for the All board, which mixes guards, forwards and
    /// centers: a percentile is only meaningful against the player's own
    /// cohort, so there the raw number leads and the percentile breaks ties.
    static func metricComparator(
        label: String,
        category: MetricCategory,
        descending: Bool,
        acrossCohorts: Bool = false
    ) -> (Player, Player) -> Bool {
        let percentileDescending = descending != lowerIsBetter(
            label: label,
            category: category
        )
        return { first, second in
            let firstMetric = first.metrics.first {
                $0.label == label && $0.category == category
            }
            let secondMetric = second.metrics.first {
                $0.label == label && $0.category == category
            }

            switch (firstMetric, secondMetric) {
            case (nil, nil):
                return first.name < second.name
            case (nil, _):
                return false
            case (_, nil):
                return true
            default:
                break
            }

            guard let firstMetric, let secondMetric else { return false }
            if acrossCohorts,
               let firstValue = rawNumeric(firstMetric.value),
               let secondValue = rawNumeric(secondMetric.value),
               firstValue != secondValue {
                return descending ? firstValue > secondValue : firstValue < secondValue
            }
            if firstMetric.percentile != secondMetric.percentile {
                return percentileDescending
                    ? firstMetric.percentile > secondMetric.percentile
                    : firstMetric.percentile < secondMetric.percentile
            }
            if let firstValue = rawNumeric(firstMetric.value),
               let secondValue = rawNumeric(secondMetric.value),
               firstValue != secondValue {
                return descending
                    ? firstValue > secondValue
                    : firstValue < secondValue
            }
            return first.name < second.name
        }
    }

    /// Parse a leading numeric value from a metric's display string.
    /// Handles ".345", "8.2%", "98.5 mph", "28.5 ft/s", "25.3°", "-1.2".
    /// Forwards to the actor-free `metricNumericValue` in the model layer, which
    /// is the single implementation. Kept as a static here because a large number
    /// of call sites already spell it this way.
    static func rawNumeric(_ value: String) -> Double? {
        metricNumericValue(value)
    }

    static func lowerIsBetter(label: String, category: MetricCategory) -> Bool {
        guard let definition = BasketballMetricRegistry.definition(for: label, category: category) else { return false }
        return !definition.higherIsBetter
    }

    /// Default sort direction for a metric - descending (highest first) unless
    /// the metric reads better when lower. Used to keep "best player first" as
    /// the initial ordering even after switching to raw-value sorting.
    static func defaultSortDescending(label: String?, category: MetricCategory?) -> Bool {
        guard let label, let category else { return true }
        return !lowerIsBetter(label: label, category: category)
    }

    private func determineSortMetricLabel() -> String? {
        let preferred = selectedPosition.preferredAdvancedMetrics + selectedPosition.preferredTraditionalMetrics
        let available = Set(availableSortMetrics)
        for label in preferred where available.contains(label) {
            return label
        }
        return availableSortMetrics.first
    }

    // Expose the current sort metric for row display. When no category is
    // active the leaderboard sorts by raw xwOBA; surface that label (with
    // nil category) so LeaderboardTableRow matches by label alone and shows
    // each player's xwOBA value instead of a percentile fallback.
    var currentSortMetricForDisplay: (label: String?, category: MetricCategory?) {
        guard let label = currentSortMetric,
              let metric = eligibleMetrics.first(where: { $0.label == label }) else {
            return (nil, nil)
        }
        return (label, metric.category)
    }

    func players(forTeam team: String) -> [Player] {
        // Sort the roster by overall percentile so the standout players surface
        // first regardless of position group.
        let normalized = normalizedTeamAbbreviation(team)
        return seasonPlayers.filter { normalizedTeamAbbreviation($0.team) == normalized }
            .sorted { $0.overallPercentile > $1.overallPercentile }
    }

    func teamScore(_ abbr: String) -> Double {
        _teamScores[normalizedTeamAbbreviation(abbr)] ?? 0
    }

    /// Players who meet the active qualifier for at least one category they appear in.
    /// Used to filter the StatScout leaders and Box Score so unqualified samples don't pollute results.
    var qualifiedSeasonPlayers: [Player] {
        seasonPlayers.filter { player in
            let categories = Set(player.metrics.map(\.category))
            if categories.isEmpty { return isQualified(player, for: nil) }
            return categories.contains { isQualified(player, for: $0) }
        }
    }

    var allMetrics: [(label: String, category: MetricCategory, best: (player: Player, percentile: Int, actualValue: String)?, worst: (player: Player, percentile: Int, actualValue: String)?)] {
        var metricMap: [String: (category: MetricCategory, values: [(player: Player, percentile: Int, actualValue: String)])] = [:]
        for player in seasonPlayers where matchesSelectedConference(player) {
            for metric in player.metrics {
                guard isQualified(player, for: metric.category) else { continue }
                let compositeKey = "\(metric.label)|\(metric.category.rawValue)"
                if metricMap[compositeKey] == nil {
                    metricMap[compositeKey] = (category: metric.category, values: [])
                }
                metricMap[compositeKey]?.values.append((player: player, percentile: metric.percentile, actualValue: metric.value))
            }
        }
        return metricMap.compactMap { (key, data) -> MetricLeaderEntry? in
            let label = key.split(separator: "|").first.map(String.init) ?? key
            // Rank Best/Worst by Hardwood percentile, NOT by parsing the value
            // string. Roughly half of xISO / xOBP / Hard-Hit% (and 100% of
            // Arm Strength / Squared-Up%) ship a valid percentile but a blank
            // value; rawNumeric("") collapsed them all to 0, every player tied,
            // and the sort returned the same player (e.g. Ohtani) for both
            // ends with empty cells. Percentile is Hardwood's normalized
            // goodness - already direction-correct (it inverts for pitchers),
            // so highest = best, lowest = worst with no per-metric polarity
            // table needed.
            let byPercentile = data.values.sorted { $0.percentile < $1.percentile }
            guard let best = byPercentile.last else { return nil }
            let worst = byPercentile.first
            // Single qualifier (or every qualifier tied): the same player can't
            // be both Best and Worst - drop the duplicate so the row reads
            // "Best: X / Only qualifier" instead of "X is also the worst".
            let dedupedWorst = (worst?.player.id == best.player.id) ? nil : worst
            return (
                label: label,
                category: data.category,
                best: best,
                worst: dedupedWorst
            )
        }.sorted { $0.label < $1.label }
    }

    func loadIfNeeded() async {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        await load()
    }

    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    /// Checks the lightweight publisher status when the app returns to the
    /// foreground. A changed ready revision triggers the normal full load;
    /// unchanged or pending status leaves the current screen in place.
    func refreshOnForeground(now: Date = .now) async {
        let interval: TimeInterval = dataFreshness?.status == .pending ? 120 : 300
        if let lastForegroundCheckAt,
           now.timeIntervalSince(lastForegroundCheckAt) < interval {
            return
        }
        lastForegroundCheckAt = now
        if await checkForUpdates(force: false) == .updated {
            await load()
        } else {
            await loadGames()
        }
    }

    @discardableResult
    func checkForUpdates(force: Bool = false) async -> FreshnessCheckResult {
        if let freshnessCheckTask {
            return await freshnessCheckTask.value
        }
        if !force,
           let lastStatusCheckAt,
           Date().timeIntervalSince(lastStatusCheckAt) < (dataFreshness?.status == .pending ? 120 : 300) {
            return .throttled
        }

        let task = Task { @MainActor [weak self] in
            await self?.performFreshnessCheck() ?? .unavailable
        }
        freshnessCheckTask = task
        return await task.value
    }

    private func performFreshnessCheck() async -> FreshnessCheckResult {
        defer { freshnessCheckTask = nil }
        let now = Date()
        lastStatusCheckAt = now
        localLastCheckedAt = now

        do {
            let fetched: DataFreshness?
            if let prefetched = takePrefetchedFreshness() {
                fetched = try await prefetched.value
            } else {
                fetched = try await provider.fetchDataFreshness()
            }
            guard let remote = fetched else {
                // The endpoint is optional while the backend rolls out. The
                // player load remains the source of truth in that case.
                return .unavailable
            }

            // The season rollover rides on this one row: it names the season the
            // published revision covers, which is the live season, however far
            // ahead the calendar is.
            applyLive(StatScoutSeason.resolveLive(from: remote, fallback: live.season))

            // A pending next season is not a problem with the data on screen:
            // the published revision is complete and final, so it reads as
            // ready, and the new season shows up as a schedule instead.
            let status: DataFreshnessStatus = remote.isSeasonPending ? .ready : remote.status
            dataFreshness = remote.replacing(
                status: status == remote.status ? nil : .some(status),
                checkedAt: .some(remote.checkedAt ?? now),
                isCached: .some(false)
            )
            persistFreshness()

            switch status {
            case .ready:
                if let revision = remote.revision,
                   revision != displayedDataRevision {
                    return .updated
                }
                return .unchanged
            case .pending: return .pending
            case .partial:
                if let revision = remote.revision, revision != displayedDataRevision { return .updated }
                return .partial
            case .stale: return .stale
            case .checking: return .unchanged
            case .offline, .failed: return .failed
            }
        } catch is CancellationError {
            return .failed
        } catch {
            if let existing = dataFreshness {
                dataFreshness = existing.replacing(
                    status: .offline,
                    checkedAt: .some(now),
                    message: .some("We couldn't check for new game data."),
                    isCached: .some(true)
                )
                persistFreshness()
            }
            return .failed
        }
    }

    /// Adopts a newly resolved live season. The selected season follows it when
    /// the user was sitting on the old live one, so a rollover moves the app on
    /// by itself; a user browsing history stays where they are.
    private func applyLive(_ resolved: StatScoutSeason.Live) {
        guard resolved != live else { return }
        let old = live
        live = resolved
        StatScoutSeason.remember(resolved, defaults: defaults)
        if selectedSeason == old.season {
            selectedSeason = resolved.season
        }
        clampSelectedSeason()
        // The recent-form windows and team caches describe the old season.
        invalidateRecentFormCache()
    }

    private func performLoad() async {
        defer { loadTask = nil }
        StartupTrace.mark("load begins")
        hasStartedLoading = true
        isLoading = players.isEmpty
        loadingMessage = players.isEmpty ? "Loading saved players…" : "Refreshing player data…"
        loadingProgress = players.isEmpty ? 0.12 : 0.2

        let cached: [Player] = await Task.detached { [cache] in
            if let cache = cache as? TwoTierPlayerCache {
                return (try? cache.loadCurrentPlayers()) ?? []
            }
            return (try? cache?.loadPlayers()) ?? []
        }.value

        StartupTrace.mark("saved players read (\(cached.count) rows)")
        if players.isEmpty, !cached.isEmpty {
            ingestPlayers(cached)
            StartupTrace.mark("saved players on screen")
        }

        loadingMessage = "Checking for updates…"
        loadingProgress = 0.45
        isLoading = players.isEmpty
        errorMessage = nil
        lastFetchFailed = false
        lastFailureWasConnectivity = false

        let freshnessResult = await checkForUpdates(force: true)
        StartupTrace.mark("freshness check done")
        let revisionAtStart = dataFreshness?.revision

        var acceptedCurrent: [Player] = []
        var loadedCurrentData = false
        var playersToIngest: [Player] = []
        var drewLeaderboardEarly = false

        do {
            let liveSeason = live.season
            let current = try await fetchLivePlayers(season: liveSeason)
            StartupTrace.mark("live players fetched and decoded (\(current.count) rows)")
            let fallbackPlayers = cached.isEmpty ? playerHistories.values.flatMap { $0 } : cached
            let hasCompleteFallback = PlayerSnapshotValidator.isCompleteCurrent(fallbackPlayers, season: liveSeason)
            let passesCompleteness = PlayerSnapshotValidator.isCompleteCurrent(current, season: liveSeason)
            acceptedCurrent = passesCompleteness || !hasCompleteFallback
                ? current
                : []
            // Before the status endpoint exists, a source regression can still
            // satisfy the live-season minimum with fewer teams. Retain the
            // complete cached set when a whole team disappears or a large part
            // of the known player set vanishes.
            if !acceptedCurrent.isEmpty,
               (freshnessResult == .unavailable || freshnessResult == .failed),
               hasUnsafeSnapshotRegression(current, against: fallbackPlayers) {
                acceptedCurrent = []
            }
            let allPlayers = acceptedCurrent.isEmpty ? fallbackPlayers : mergePlayers(replacing: acceptedCurrent)

            if allPlayers.isEmpty {
                // No current data (offseason / cold cache / offline). Fall back to
                // the bundled archive so the app is usable instead of trapped on
                // an empty state; season gating still applies via isSeasonLocked.
                await showBundledSeasonIfNothingIsShown()
                if players.isEmpty {
                    errorMessage = "No players found."
                    lastFetchFailed = true
                }
            } else {
                loadingMessage = "Preparing leaderboard…"
                loadingProgress = 0.85
                playersToIngest = allPlayers
                if !acceptedCurrent.isEmpty {
                    loadedCurrentData = true
                } else if !current.isEmpty {
                    errorMessage = "Showing complete saved data while the live feed finishes updating."
                    lastFetchFailed = true
                }
                // Nothing is on screen yet, so draw the leaderboard now rather
                // than after the coverage read and the closing status check
                // below, which are two more round trips of a blank screen. A
                // revision that moves during them is handled as before: the
                // snapshot is simply not saved or adopted, and the next check
                // reloads.
                if players.isEmpty {
                    ingestPlayers(allPlayers)
                    drewLeaderboardEarly = true
                    isLoading = false
                    loadingProgress = 1
                    StartupTrace.mark("live players on screen")
                }
            }

        } catch is DecodingError {
            await showBundledSeasonIfNothingIsShown()
            errorMessage = "Data format changed - app may need an update."
            lastFetchFailed = true
        } catch _ as URLError {
            // A first launch with no connection and nothing saved: the bundled
            // season is the board, not an empty "no data" card under a caption
            // that says saved stats are showing.
            await showBundledSeasonIfNothingIsShown()
            errorMessage = players.isEmpty ? "Can't reach data feed. Check your connection." : "Showing saved data. Pull to refresh when your connection improves."
            lastFetchFailed = true
            lastFailureWasConnectivity = true
        } catch {
            await showBundledSeasonIfNothingIsShown()
            errorMessage = players.isEmpty ? "Something went wrong loading player data." : "Showing saved data. Pull to refresh to try again."
            lastFetchFailed = true
        }
        isLoading = false
        loadingProgress = 1

        // Off the critical path on purpose: a single row that only the About
        // sheet reads, fetched once the leaderboard is already on screen. A
        // failure here leaves the coverage line blank rather than failing the
        // load.
        let candidateCoverage = try? await provider.fetchDataCoverage(season: freeSeason)
        StartupTrace.mark("coverage fetched")

        // The source can publish a new revision while snapshots are being
        // fetched. Bracket the candidate with a second status read so a new
        // status row cannot be paired with older player rows. Keep the prior
        // display and wait for the next check when the bracket moves.
        let endingResult = await checkForUpdates(force: true)
        StartupTrace.mark("closing freshness check done")
        let revisionAtEnd = dataFreshness?.revision
        // Only a revision that actually moved counts. A first status read that
        // failed (nil) and a second that succeeded is not drift; treating it as
        // drift discarded a good load and, on a cold start, left a blank app.
        let revisionDrifted = revisionAtStart != nil
            && revisionAtEnd != nil
            && revisionAtEnd != revisionAtStart
        if revisionDrifted {
            playersToIngest = []
            acceptedCurrent = []
            loadedCurrentData = false
            if let current = dataFreshness {
                dataFreshness = current.replacing(
                    status: .checking,
                    message: .some("A newer game revision arrived while this update was loading."),
                    isCached: .some(true)
                )
            }
        } else if !playersToIngest.isEmpty, !drewLeaderboardEarly {
            ingestPlayers(playersToIngest)
            StartupTrace.mark("live players on screen")
        }
        if loadedCurrentData {
            dataCoverage = dataFreshness?.coverage ?? candidateCoverage
            try? cache?.savePlayers(acceptedCurrent, liveSeason: live.season)
            adoptLoadedRevision(
                players: acceptedCurrent,
                useServerRevision: canUseServerRevision(freshnessResult, endingResult)
            )
        } else if lastFetchFailed, let current = dataFreshness {
            dataFreshness = current.replacing(
                status: .failed,
                message: .some(errorMessage ?? "Showing saved data while the latest refresh is retried."),
                isCached: .some(true)
            )
        }
        persistFreshness()
        StartupTrace.mark("load persisted, profiles and games next")
        await loadProfiles()
        await loadGames(force: true)
        StartupTrace.mark("load finished")
    }

    /// Draws the newest bundled season (no later than the live one) when nothing
    /// else is on screen. Only that one season is decoded, not the archive: it
    /// is the board being shown, and the rest loads when something asks for it.
    private func showBundledSeasonIfNothingIsShown() async {
        guard players.isEmpty else { return }
        let season = live.season
        let rows: [Player] = await Task.detached { [cache] in
            if let cache = cache as? TwoTierPlayerCache {
                return cache.loadNewestBundledSeason(atMost: season)
            }
            return (try? cache?.loadPlayers()) ?? []
        }.value
        guard players.isEmpty, !rows.isEmpty else { return }
        ingestPlayers(rows)
        StartupTrace.mark("bundled season on screen")
    }

    /// Marks a successfully accepted snapshot as the revision shown by every
    /// dependent surface. Recent form is cleared only after this point, so a
    /// failed or partial response cannot erase useful in-memory results.
    private func adoptLoadedRevision(
        players loadedPlayers: [Player],
        useServerRevision: Bool
    ) {
        let candidate: String?
        if useServerRevision,
           (dataFreshness?.status == .ready || dataFreshness?.status == .partial),
           let revision = dataFreshness?.revision {
            candidate = revision
        } else {
            candidate = fallbackRevision(players: loadedPlayers, coverage: dataCoverage)
        }
        guard let candidate else { return }
        let changed = displayedDataRevision != candidate
        displayedDataRevision = candidate
        if changed {
            invalidateRecentFormCache()
        }

        if let current = dataFreshness {
            dataFreshness = current.replacing(
                status: current.status == .checking ? .ready : nil,
                revision: useServerRevision ? nil : .some(candidate),
                coverage: .some(dataCoverage),
                isCached: .some(false)
            )
        } else {
            dataFreshness = DataFreshness(
                status: .ready,
                revision: candidate,
                checkedAt: localLastCheckedAt ?? Date(),
                coverage: dataCoverage
            )
        }
    }

    private func canUseServerRevision(
        _ initial: FreshnessCheckResult,
        _ ending: FreshnessCheckResult
    ) -> Bool {
        let allowed: Set<FreshnessCheckResult> = [.updated, .unchanged, .partial]
        return allowed.contains(initial) && allowed.contains(ending)
    }

    private func fallbackRevision(players: [Player], coverage: DataCoverage?) -> String? {
        guard let latest = players.map(\.updatedAt).max() else { return nil }
        let timestamp = Int(latest.timeIntervalSince1970)
        let week = coverage?.week ?? 0
        let asOf = coverage.map { Int($0.asOf.timeIntervalSince1970) } ?? 0
        return "players-\(timestamp)-week-\(week)-asof-\(asOf)"
    }

    private func hasUnsafeSnapshotRegression(
        _ candidate: [Player],
        against fallback: [Player]
    ) -> Bool {
        let currentSeason = live.season
        let fallbackCurrent = fallback.filter {
            $0.season == currentSeason && $0.seasonPhase == .regular
        }
        let candidateCurrent = candidate.filter {
            $0.season == currentSeason && $0.seasonPhase == .regular
        }
        guard !fallbackCurrent.isEmpty, !candidateCurrent.isEmpty else { return false }

        let fallbackTeams = Set(fallbackCurrent.map { normalizedTeamAbbreviation($0.team) })
        let candidateTeams = Set(candidateCurrent.map { normalizedTeamAbbreviation($0.team) })
        guard fallbackTeams.isSubset(of: candidateTeams) else { return true }

        let fallbackIDs = Set(fallbackCurrent.map(\.playerId))
        let candidateIDs = Set(candidateCurrent.map(\.playerId))
        let missing = fallbackIDs.subtracting(candidateIDs).count
        return Double(missing) / Double(fallbackIDs.count) > 0.20
    }

    private func persistFreshness() {
        guard cache != nil, let dataFreshness else { return }
        DataFreshnessCache.save(
            dataFreshness.replacing(coverage: .some(dataCoverage)),
            displayedRevision: displayedDataRevision
        )
    }

    func loadHistoricalIfNeeded() async {
        guard !hasLoadedHistorical, !isHistoricalLoading else { return }
        isHistoricalLoading = true
        loadingMessage = "Loading past seasons…"
        loadingProgress = 0.12

        // A past season the user is already looking at comes first, on its own:
        // one season decodes in a fraction of a second, where the whole archive
        // takes several, and it is the board they are waiting on. Year-over-year
        // views need every season, and get them next.
        let wanted = selectedSeason
        if wanted != live.season, !hasSeasonLoaded(wanted) {
            let first: [Player] = await Task.detached { [cache] in
                (cache as? TwoTierPlayerCache)?.loadHistoricalSeason(wanted) ?? []
            }.value
            if !first.isEmpty {
                ingestPlayers(mergePlayers(replacing: first))
                StartupTrace.mark("selected past season on screen")
            }
        }

        var historical: [Player] = await Task.detached { [cache] in
            if let cache = cache as? TwoTierPlayerCache {
                return cache.loadHistoricalPlayers()
            }
            return (try? cache?.loadPlayers()) ?? []
        }.value

        // The screenshot fixture and lightweight providers may intentionally
        // disable the disk cache. Fetch their historical tier directly rather
        // than leaving a Pro season menu with no data.
        if historical.isEmpty {
            historical = (try? await provider.fetchHistoricalPlayers(before: live.season)) ?? []
        }

        loadingMessage = "Preparing season history…"
        loadingProgress = 0.78

        if !historical.isEmpty {
            // The archive carries the live season too (2025-26 is both bundled
            // and live until 2026-27 publishes). Server rows already loaded win:
            // archive rows from the live season only fill in what is absent.
            let loadedIDs = Set(playerHistories.values.flatMap { $0 }.map(\.id))
            let liveSeason = live.season
            let archive = historical.filter {
                ($0.season ?? 0) < liveSeason || !loadedIDs.contains($0.id)
            }
            StartupTrace.mark("archive loaded, merging")
            ingestPlayers(mergePlayers(replacing: archive))
            StartupTrace.mark("archive on screen")
            hasLoadedHistorical = true
        }

        isHistoricalLoading = false
        loadingProgress = 1
    }

    private func hasSeasonLoaded(_ season: Int) -> Bool {
        playerHistories.values.contains { $0.contains { $0.season == season } }
    }

    private func ingestPlayers(_ players: [Player]) {
        let grouped = Dictionary(grouping: players, by: \.playerId)
        var latestPlayers: [Player] = []
        var histories: [Int: [Player]] = [:]

        for (playerId, history) in grouped {
            let sortedHistory = history.sorted {
                guard let s1 = $0.season, let s2 = $1.season else {
                    if $0.season == nil && $1.season == nil { return false }
                    return $0.season != nil
                }
                if s1 == s2, $0.seasonPhase != $1.seasonPhase {
                    return $0.seasonPhase == .regular
                }
                return s1 > s2
            }
            histories[playerId] = sortedHistory
            if let latest = sortedHistory.first {
                latestPlayers.append(latest)
            }
        }

        self.playerHistories = histories
        self.players = latestPlayers
        // No auto-jump to an older season when the live one is thin or empty:
        // the live season is the default for everyone, Pro included.

        recomputeTeamCache()
    }

    private func recomputeTeamCache() {
        let allSeasonPlayers = playerHistories.values.flatMap { $0 }.filter {
            $0.season == selectedSeason && $0.seasonPhase == selectedPhase
        }
        var seenIds = Set<Int>()
        let uniquePlayers = allSeasonPlayers.filter { seenIds.insert($0.playerId).inserted }

        var teams = Set<String>()
        var teamScoresAccum: [String: (sum: Int, count: Int)] = [:]

        for player in uniquePlayers {
            let abbr = normalizedTeamAbbreviation(player.team)
            teams.insert(abbr)
            let score = player.overallPercentile
            if score > 0 {
                var entry = teamScoresAccum[abbr] ?? (0, 0)
                entry.sum += score
                entry.count += 1
                teamScoresAccum[abbr] = entry
            }
        }

        _teamsWithData = teams.sorted()
        _teamScores = teamScoresAccum.mapValues { Double($0.sum) / Double($0.count) }
        _teamCacheSeason = selectedSeason
        _teamCachePhase = selectedPhase
    }

    private func mergePlayers(replacing replacements: [Player]) -> [Player] {
        var merged: [String: Player] = [:]
        for player in playerHistories.values.flatMap({ $0 }) {
            merged[player.id] = player
        }
        for player in replacements {
            merged[player.id] = player
        }
        return Array(merged.values)
    }
}
