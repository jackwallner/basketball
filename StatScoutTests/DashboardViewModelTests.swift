import XCTest
@testable import Hardwood_StatScout

/// The season the tests treat as live: the newest the bundle carries, which is
/// also what a fresh install resolves to before the server has been heard from.
let testLiveSeason = StatScoutSeason.bundledNewest

/// A view model with its own defaults suite, so the persisted live season of one
/// test never leaks into the next.
@MainActor
func makeViewModel(
    provider: StatcastProviding,
    cache: PlayerCaching? = nil,
    calendarSeason: Int = testLiveSeason
) -> DashboardViewModel {
    let name = "statscout-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return DashboardViewModel(
        provider: provider,
        cache: cache,
        defaults: defaults,
        calendarSeason: calendarSeason
    )
}

final class DashboardViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "stats.qualifier")
    }

    @MainActor
    func testAllMetricsKeyCollision() async throws {
        let players: [Player] = [
            Player(
                playerId: 1, name: "A", team: "BOS", position: "G", handedness: "",
                updatedAt: Date(), season: testLiveSeason, playerType: "g",
                metrics: [
                    Metric(id: "m1", label: "AST", value: "448", percentile: 90, category: .playmaking)
                ],
                standardStats: [],
                games: []
            ),
            Player(
                playerId: 2, name: "B", team: "DEN", position: "C", handedness: "",
                updatedAt: Date(), season: testLiveSeason, playerType: "c",
                metrics: [
                    Metric(id: "m2", label: "AST", value: "420", percentile: 85, category: .playmaking),
                    Metric(id: "m3", label: "AST", value: "9", percentile: 85, category: .defense),
                ],
                standardStats: [],
                games: []
            )
        ]
        let vm = makeViewModel(provider: MockProvider(players: players))
        await vm.load()
        XCTAssertEqual(vm.allMetrics.count, 2, "Same label in different categories should produce 2 entries")
    }

    @MainActor
    func testLoadDistinguishesErrors() async {
        let vm1 = makeViewModel(provider: MockProvider(error: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))))
        await vm1.load()
        XCTAssertTrue(vm1.errorMessage?.contains("format changed") == true)

        let vm2 = makeViewModel(provider: MockProvider(error: URLError(.notConnectedToInternet)))
        await vm2.load()
        XCTAssertTrue(vm2.errorMessage?.contains("connection") == true)
    }

    @MainActor
    func testLastUpdatedReturnsNilWhenEmpty() {
        XCTAssertNil(makeViewModel(provider: MockProvider(players: [])).lastUpdated)
    }

    func testTeamNamesAndCodes() {
        XCTAssertEqual(teamFullName("BOS"), "Boston Celtics")
        XCTAssertEqual(teamFullName("GSW"), "Golden State Warriors")
        XCTAssertEqual(teamFullName("PHI"), "Philadelphia 76ers")
        XCTAssertEqual(teamFullName("SEA"), "Seattle SuperSonics")
        XCTAssertEqual(teamFullName("Unknown"), "Unknown")
        XCTAssertEqual(nbaTeamAbbreviations.count, 30)
        XCTAssertEqual(Set(nbaTeamAbbreviations).count, 30)
        XCTAssertTrue(nbaTeamAbbreviations.allSatisfy { teamFullName($0) != $0 })
        // ESPN's short forms and old spellings land on the app's codes.
        for (raw, code) in [("GS", "GSW"), ("NY", "NYK"), ("SA", "SAS"), ("UTAH", "UTA"), ("WSH", "WAS"),
                            ("NO", "NOP"), ("BRK", "BKN"), ("PHO", "PHX"), ("Boston Celtics", "BOS")] {
            XCTAssertEqual(normalizedTeamAbbreviation(raw), code, raw)
        }
        // Every team has a color of its own.
        XCTAssertTrue(nbaTeamAbbreviations.allSatisfy { NBATeamColor.primary[$0] != nil })
    }

    @MainActor
    func testPlayersForTeamMatchesAliases() async {
        let players = [
            Player(playerId: 1, name: "A", team: "Boston Celtics", position: "G", handedness: "",
                   updatedAt: Date(), season: testLiveSeason, metrics: [], standardStats: [], games: []),
            Player(playerId: 2, name: "B", team: "BRK", position: "F", handedness: "",
                   updatedAt: Date(), season: testLiveSeason, metrics: [], standardStats: [], games: []),
        ]
        let vm = makeViewModel(provider: MockProvider(players: players))
        await vm.load()

        XCTAssertEqual(vm.players(forTeam: "BOS").map(\.playerId), [1])
        XCTAssertEqual(vm.players(forTeam: "BKN").map(\.playerId), [2])
    }

    @MainActor
    func testConferenceFilterScopesPlayersTeamsAndMetrics() async {
        let players = [
            Player(
                playerId: 1, name: "East Player", team: "BOS", position: "G", handedness: "",
                updatedAt: Date(), season: testLiveSeason, playerType: "g",
                metrics: [Metric(id: "east", label: "PPG", value: "28.1", percentile: 90, category: .scoring)],
                standardStats: [], games: []
            ),
            Player(
                playerId: 2, name: "West Player", team: "DEN", position: "C", handedness: "",
                updatedAt: Date(), season: testLiveSeason, playerType: "c",
                metrics: [Metric(id: "west", label: "RPG", value: "12.1", percentile: 80, category: .rebounding)],
                standardStats: [], games: []
            ),
        ]
        let vm = makeViewModel(provider: MockProvider(players: players))
        await vm.load()

        vm.selectedConference = .east
        vm.searchText = "Boston"
        XCTAssertEqual(vm.filteredPlayers.map(\.name), ["East Player"])
        XCTAssertEqual(vm.searchedTeams, ["BOS"])
        XCTAssertEqual(vm.allMetrics.map(\.label), ["PPG"])

        vm.selectedConference = .west
        vm.searchText = "Denver"
        XCTAssertEqual(vm.filteredPlayers.map(\.name), ["West Player"])
        XCTAssertEqual(vm.searchedTeams, ["DEN"])
        XCTAssertEqual(vm.allMetrics.map(\.label), ["RPG"])
    }

    func testEveryTeamIsInExactlyOneConference() {
        for team in nbaTeamAbbreviations {
            XCTAssertNotEqual(NBAConference.east.contains(team: team), NBAConference.west.contains(team: team), team)
        }
        XCTAssertEqual(nbaTeamAbbreviations.filter { NBAConference.east.contains(team: $0) }.count, 15)
    }

    @MainActor
    func testTeamCountsPopulatedAfterLoad() async {
        let players = [
            Player(playerId: 1, name: "A", team: "BOS", position: "G", handedness: "", updatedAt: Date(), season: testLiveSeason, metrics: [], standardStats: [], games: []),
            Player(playerId: 2, name: "B", team: "BOS", position: "F", handedness: "", updatedAt: Date(), season: testLiveSeason, metrics: [], standardStats: [], games: []),
            Player(playerId: 3, name: "C", team: "DEN", position: "C", handedness: "", updatedAt: Date(), season: testLiveSeason, metrics: [], standardStats: [], games: [])
        ]
        let vm = makeViewModel(provider: MockProvider(players: players))
        await vm.load()
        XCTAssertEqual(vm.teamCounts["BOS"], 2)
        XCTAssertEqual(vm.teamCounts["DEN"], 1)
    }

    @MainActor
    func testPartialRefreshPreservesCompleteCache() async {
        let cached = makeCompleteCurrentPlayers()
        let partial = Array(cached.prefix(5))
        let cache = InMemoryPlayerCache(seed: cached)
        let vm = makeViewModel(provider: MockProvider(players: partial), cache: cache)

        await vm.load()

        XCTAssertEqual(vm.seasonPlayers.count, cached.count)
        XCTAssertEqual(vm.teamsWithData.count, 30)
        XCTAssertTrue(vm.lastFetchFailed)
        XCTAssertEqual(cache.savedPlayers.count, cached.count)
    }

    @MainActor
    func testCompleteRefreshReplacesCurrentCache() async {
        let refreshed = makeCompleteCurrentPlayers(namePrefix: "Fresh")
        let cache = InMemoryPlayerCache(seed: makeCompleteCurrentPlayers())
        let vm = makeViewModel(provider: MockProvider(players: refreshed), cache: cache)

        await vm.load()

        XCTAssertEqual(vm.seasonPlayers.count, refreshed.count)
        XCTAssertTrue(vm.seasonPlayers.allSatisfy { $0.name.hasPrefix("Fresh") })
        XCTAssertEqual(cache.savedPlayers.count, refreshed.count)
    }

    @MainActor
    func testCacheHydratesPlayersBeforeFetch() async {
        let cached = [
            Player(playerId: 99, name: "Cached", team: "BOS", position: "G", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        ]
        let cache = InMemoryPlayerCache(seed: cached)
        let vm = makeViewModel(provider: MockProvider(error: URLError(.notConnectedToInternet)), cache: cache)
        await vm.load()
        XCTAssertEqual(vm.players.map(\.id), ["99-0-REG"], "Cached players should be shown even when refresh fails")
    }

    // MARK: - Board defaults

    private func boardPlayer(
        _ id: Int,
        type: String,
        _ metrics: [(String, MetricCategory, String, Int)]
    ) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: "BOS", position: type.uppercased(), handedness: "",
            updatedAt: Date(), season: testLiveSeason, playerType: type, source: "hoopR",
            metrics: metrics.enumerated().map { index, m in
                Metric(id: "m\(id)-\(index)", label: m.0, value: m.2, percentile: m.3, category: m.1)
            },
            standardStats: [], games: []
        )
    }

    /// Every cohort has the same menu of metrics; what differs is which one its
    /// board opens on, from the contract's per-position defaults.
    @MainActor
    func testEachPositionBoardOpensOnItsOwnDefaultMetric() async {
        let everything: [(String, MetricCategory, String, Int)] = [
            ("Pts/100", .scoring, "30.1", 80), ("TS%", .scoring, "58.0%", 70), ("PPG", .scoring, "20.0", 75),
            ("AST%", .playmaking, "25.0%", 85), ("APG", .playmaking, "6.1", 80),
            ("REB%", .rebounding, "14.0%", 60), ("RPG", .rebounding, "9.0", 62),
        ]
        let players = [
            boardPlayer(1, type: "g", everything),
            boardPlayer(2, type: "f", everything),
            boardPlayer(3, type: "c", everything),
        ]
        let vm = makeViewModel(provider: MockProvider(players: players))
        await vm.load()

        XCTAssertEqual(vm.selectedPosition, .all)
        XCTAssertEqual(vm.sortLabel, "Pts/100")
        vm.selectedPosition = .guard
        XCTAssertEqual(vm.sortLabel, "AST%")
        vm.selectedPosition = .forward
        XCTAssertEqual(vm.sortLabel, "Pts/100")
        vm.selectedPosition = .center
        XCTAssertEqual(vm.sortLabel, "REB%")
    }

    @MainActor
    func testBoardFallsBackToTheFirstAvailableMetricAndThenToTheDefaultLabel() async {
        let onlyRebounds = boardPlayer(1, type: "c", [("OREB", .rebounding, "120", 70)])
        let vm = makeViewModel(provider: MockProvider(players: [onlyRebounds]))
        await vm.load()
        vm.selectedPosition = .center
        XCTAssertEqual(vm.sortLabel, "OREB")
        XCTAssertEqual(vm.filteredPlayers.count, 1)
        // A cohort with nobody in it has no metric to sort by.
        vm.selectedPosition = .guard
        XCTAssertEqual(vm.sortLabel, "Top Metric")
        XCTAssertTrue(vm.leaderboard.isEmpty)
    }

    @MainActor
    func testAllBoardMixesCohortsAndRanksByTheNumber() async {
        let guardPlayer = boardPlayer(1, type: "g", [("REB%", .rebounding, "9.0%", 95)])
        let center = boardPlayer(2, type: "c", [("REB%", .rebounding, "17.0%", 40)])
        let vm = makeViewModel(provider: MockProvider(players: [guardPlayer, center]))
        await vm.load()

        XCTAssertEqual(vm.leaderboard.map(\.playerId), [2, 1])
        vm.selectedPosition = .guard
        XCTAssertEqual(vm.leaderboard.map(\.playerId), [1])
    }

    @MainActor
    func testHistoricalArchiveRequiresEverySupportedSeason() async {
        let complete = makeCompleteHistoricalPlayers()
        XCTAssertTrue(PlayerSnapshotValidator.isCompleteHistorical(complete, through: testLiveSeason - 1))

        let missingFirst = complete.filter { $0.season != StatScoutSeason.earliest }
        XCTAssertFalse(PlayerSnapshotValidator.isCompleteHistorical(missingFirst, through: testLiveSeason - 1))
    }

    /// The career rollup leads the menu, then real seasons newest-first. It sits
    /// at the top rather than sorting into place because its sentinel is 0, which
    /// would otherwise bury "All Time" below 2002-03.
    private var expectedSeasons: [Int] {
        [StatScoutSeason.allTime]
            + Array(StatScoutSeason.earliest...testLiveSeason).reversed()
    }

    @MainActor
    func testAvailableSeasonsRunFromTheEarliestThroughLivePlusAllTime() async {
        let players = makeCompleteHistoricalPlayers() + makeCompleteCurrentPlayers()
        let vm = makeViewModel(provider: MockProvider(players: players))
        vm.isPro = true

        await vm.load()

        XCTAssertEqual(vm.availableSeasons, expectedSeasons)
        XCTAssertEqual(vm.availableSeasons.first, StatScoutSeason.allTime)
        XCTAssertEqual(StatScoutSeason.earliest, 2003)
    }

    @MainActor
    func testAvailableSeasonsIncludesLockedHistoryBeforeHistoryLoads() async {
        let vm = makeViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))

        await vm.load()

        XCTAssertEqual(vm.availableSeasons, expectedSeasons)
        XCTAssertTrue(vm.isSeasonLocked(testLiveSeason - 1))
    }

    /// All Time is Pro, like every season other than the live one.
    @MainActor
    func testAllTimeIsLockedForFreeUsers() async {
        let vm = makeViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))
        vm.isPro = false
        XCTAssertTrue(vm.isSeasonLocked(StatScoutSeason.allTime))
        vm.isPro = true
        XCTAssertFalse(vm.isSeasonLocked(StatScoutSeason.allTime))
    }

    /// A thin live season (opening night: two teams have played) is still the
    /// default, for Pro too, and its thin board is what shows.
    @MainActor
    func testAThinLiveSeasonIsStillTheDefault() async {
        let lastSeason = makeCompleteSeasonPlayers(season: testLiveSeason - 1, namePrefix: "LastYear")
        let opener = makeCompleteCurrentPlayers(namePrefix: "Opener").filter { ["BOS", "NYK"].contains($0.team) }
        let vm = makeViewModel(provider: MockProvider(players: lastSeason + opener))
        vm.isPro = true

        await vm.load()

        XCTAssertEqual(vm.selectedSeason, testLiveSeason)
        XCTAssertFalse(vm.isSeasonLocked(testLiveSeason))
        XCTAssertTrue(vm.players.contains { $0.season == testLiveSeason })
    }

    /// The live season ships players under the bar. All Players (the default)
    /// keeps them dimmed below qualified players; Qualified hides them.
    @MainActor
    func testQualifiedFilterHonoursTheLiveSeasonFlag() async {
        UserDefaults.standard.removeObject(forKey: "stats.qualifier")
        defer { UserDefaults.standard.removeObject(forKey: "stats.qualifier") }
        let starter = Player(
            playerId: 1, name: "Starter", team: "BOS", position: "G", handedness: "",
            updatedAt: Date(), season: testLiveSeason, playerType: "g",
            metrics: [Metric(id: "s", label: "TS%", value: "58.0%", percentile: 60, category: .scoring, qualified: true)],
            standardStats: [], games: []
        )
        let reserve = Player(
            playerId: 2, name: "Reserve", team: "DEN", position: "G", handedness: "",
            updatedAt: Date(), season: testLiveSeason, playerType: "g",
            metrics: [Metric(id: "b", label: "TS%", value: "79.0%", percentile: 99, category: .scoring, qualified: false)],
            standardStats: [], games: []
        )
        let vm = makeViewModel(provider: MockProvider(players: [starter, reserve]))
        await vm.load()

        XCTAssertEqual(vm.qualifierLevel, .all)
        // The reserve's 99th percentile outranks the starter, but a small
        // sample never tops a board.
        XCTAssertEqual(vm.leaderboard.map(\.name), ["Starter", "Reserve"])
        vm.qualifierLevel = .qualified
        XCTAssertEqual(vm.leaderboard.map(\.name), ["Starter"])
        XCTAssertEqual(makeViewModel(provider: MockProvider(players: [])).qualifierLevel, .qualified, "the choice persists")
    }

    func testMetricDecodesWithAndWithoutTheQualifiedFlag() throws {
        let json = #"""
        [{"id":"a","label":"TS%","value":"58.0%","percentile":50,"category":"Scoring","qualified":false},
         {"id":"b","label":"TS%","value":"60.0%","percentile":60,"category":"Scoring"}]
        """#
        let metrics = try JSONDecoder().decode([Metric].self, from: Data(json.utf8))
        XCTAssertEqual(metrics.map(\.qualified), [false, nil])
    }

    /// Recent form covers the live season and the one before it, as far back as
    /// the rollup table has ever held rows.
    @MainActor
    func testRecentFormCoversTheLiveSeasonAndTheOneBeforeWhereItExists() async {
        let vm = makeViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))

        await vm.load()

        XCTAssertEqual(vm.recentFormSeason, testLiveSeason)
        XCTAssertEqual(vm.recentFormSeasons.first, vm.freeSeason, "Newest first")
        XCTAssertLessThanOrEqual(vm.recentFormSeasons.count, 2)
        XCTAssertEqual(vm.recentFormSeasons, vm.recentFormSeasons.sorted(by: >))
        for season in vm.recentFormSeasons {
            XCTAssertTrue(vm.supportsRecentForm(season))
        }
        XCTAssertFalse(vm.supportsRecentForm(StatScoutSeason.allTime))
    }

    /// While 2025-26 is the live season, 2024-25 has no rolling rows, so Trends
    /// must not offer it.
    @MainActor
    func testTrendsDoesNotOfferASeasonWithNoRecentFormRows() async {
        let vm = makeViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))
        await vm.load()

        XCTAssertEqual(vm.recentFormSeasons, [2026])
        XCTAssertFalse(vm.supportsRecentForm(2025))
        for season in vm.recentFormSeasons {
            XCTAssertGreaterThanOrEqual(season, StatScoutSeason.earliestRecentForm)
        }
    }

    /// The floor is a fact about the database, not a preference.
    ///
    /// Verified against the live Basketball project on 2026-10-08:
    /// `player_game_logs` and `player_recent_form` hold 2026 and nothing else.
    /// `player_snapshots` carries 2003 on, which is why season boards reach
    /// further than form boards do. Moving this constant down without
    /// re-ingesting the per-game tables first puts an empty year in the Trends
    /// menu.
    func testRecentFormFloorMatchesTheSeasonsTheRollupHolds() {
        XCTAssertEqual(StatScoutSeason.earliestRecentForm, 2026)
        XCTAssertLessThanOrEqual(StatScoutSeason.earliestRecentForm, testLiveSeason)
    }

    /// Tip-off, end to end: once the new season's rows land and the status names
    /// it, it is the free season, last season is Pro, and Trends offers both.
    @MainActor
    func testTheAppMovesToTheNewSeasonTheDayItsDataLands() async {
        let lastSeasonRows = makeCompleteSeasonPlayers(season: 2026, namePrefix: "LastYear")
        let newSeasonRows = makeCompleteSeasonPlayers(season: 2027, namePrefix: "NewYear")
        let published = DataFreshness(
            status: .ready, revision: "r27", rawStatus: "published",
            season: 2027, publishedSeason: 2027
        )
        let vm = makeViewModel(
            provider: MockProvider(players: lastSeasonRows + newSeasonRows, freshness: published),
            calendarSeason: 2027
        )
        await vm.load()

        XCTAssertEqual(vm.freeSeason, 2027)
        XCTAssertEqual(vm.selectedSeason, 2027, "the board follows the rollover by itself")
        XCTAssertFalse(vm.isSeasonLocked(2027))
        XCTAssertTrue(vm.isSeasonLocked(2026), "last season becomes Pro, not gone")
        XCTAssertTrue(vm.availableSeasons.contains(2026))
        XCTAssertEqual(vm.recentFormSeasons, [2027, 2026])
        XCTAssertFalse(vm.isSeasonPending)
    }

    /// Between the October rollover and opening night the live season is still
    /// 2025-26, free and labelled final, with 2026-27 shown only as a schedule.
    @MainActor
    func testAPendingSeasonKeepsThePublishedSeasonLive() async {
        let rows = makeCompleteSeasonPlayers(season: 2026, namePrefix: "Final")
        let pending = DataFreshness(
            status: .pending, revision: "r26", rawStatus: "source_pending",
            season: 2027, publishedSeason: 2026, lastErrorCode: "season_pending"
        )
        let vm = makeViewModel(
            provider: MockProvider(players: rows, freshness: pending),
            calendarSeason: 2027
        )
        await vm.load()

        XCTAssertEqual(vm.freeSeason, 2026)
        XCTAssertEqual(vm.selectedSeason, 2026)
        XCTAssertEqual(vm.upcomingSeason, 2027)
        XCTAssertTrue(vm.isSeasonPending)
        XCTAssertEqual(vm.liveSeasonCaption(), "2025-26 · final")
        XCTAssertFalse(vm.isSeasonLocked(2026))
        XCTAssertTrue(vm.isSeasonLocked(2025))
        // Trends offers only what has rows: 2026 now, not an empty 2027.
        XCTAssertEqual(vm.recentFormSeasons, [2026])
        // A pending season is not a problem with the data on screen.
        XCTAssertEqual(vm.freshnessStatus, .ready)
        XCTAssertEqual(vm.players.filter { $0.season == 2026 }.count, rows.count)
    }

    /// The resolved live season is remembered, so the next cold start opens on
    /// it before the first status check lands.
    @MainActor
    func testResolvedLiveSeasonSurvivesARelaunch() async {
        let name = "statscout-relaunch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let pending = DataFreshness(
            status: .pending, rawStatus: "source_pending",
            season: 2027, publishedSeason: 2026, lastErrorCode: "season_pending"
        )
        let first = DashboardViewModel(
            provider: MockProvider(players: makeCompleteSeasonPlayers(season: 2026, namePrefix: "A"), freshness: pending),
            defaults: defaults,
            calendarSeason: 2027
        )
        await first.load()

        let second = DashboardViewModel(provider: OfflineStatcastAPI(), defaults: defaults, calendarSeason: 2027)
        XCTAssertEqual(second.freeSeason, 2026)
        XCTAssertEqual(second.upcomingSeason, 2027)
        XCTAssertEqual(second.selectedSeason, 2026)
    }

    /// With nothing remembered and no connection, the calendar's 2026-27 would
    /// be an empty board; the app opens on the newest season it can draw.
    @MainActor
    func testAColdOfflineStartOpensOnTheNewestBundledSeason() {
        let vm = makeViewModel(provider: OfflineStatcastAPI(), calendarSeason: 2027)
        XCTAssertEqual(vm.freeSeason, StatScoutSeason.bundledNewest)
        XCTAssertNil(vm.upcomingSeason)
    }

    /// Picking a past season fetches that season.
    @MainActor
    func testSelectingAPastSeasonLoadsTheHistoryItNeeds() async {
        let vm = makeViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))
        vm.isPro = true
        await vm.load()
        XCTAssertFalse(vm.hasLoadedHistorical, "History should still be unfetched after a plain load")

        vm.selectSeason(StatScoutSeason.allTime)

        // The header moves on the tap; the rows arrive behind it.
        XCTAssertEqual(vm.selectedSeason, StatScoutSeason.allTime)
        XCTAssertNotNil(vm.seasonLoadTask, "Choosing a past season should start the history load")
        await vm.seasonLoadTask?.value
    }

    /// The live season needs no extra fetch, so it must not start one.
    @MainActor
    func testSelectingTheFreeSeasonDoesNotRefetchHistory() async {
        let vm = makeViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))
        await vm.load()

        vm.selectSeason(vm.freeSeason)

        XCTAssertNil(vm.seasonLoadTask)
    }

    /// Trends ranks rolling week windows, so a career has nothing to rank.
    @MainActor
    func testTrendsSeasonListExcludesAllTime() async {
        let vm = makeViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))

        await vm.load()

        XCTAssertFalse(vm.seasonsExcludingAllTime.contains(StatScoutSeason.allTime))
        XCTAssertEqual(vm.seasonsExcludingAllTime.count, vm.availableSeasons.count - 1)
    }

    /// The sentinel must never reach the UI as "0", and a hoopR integer must
    /// never reach it bare: it names the year a season ends.
    func testSeasonLabelRendersTheNbaConvention() {
        XCTAssertEqual(SeasonLabel.text(StatScoutSeason.allTime), "All Time")
        XCTAssertEqual(SeasonLabel.text(2026), "2025-26")
        XCTAssertEqual(SeasonLabel.text(2027), "2026-27")
        XCTAssertEqual(SeasonLabel.text(2010), "2009-10")
        XCTAssertEqual(SeasonLabel.text(2000), "1999-00")
        XCTAssertEqual(SeasonLabel.text(2003), "2002-03")
        XCTAssertEqual(
            SeasonLabel.text(StatScoutSeason.allTime, phase: .regular),
            "All Time · Regular Season"
        )
        XCTAssertEqual(SeasonLabel.text(2026, phase: .playoffs), "2025-26 Playoffs")
    }

    /// One name for the phase everywhere. The nav pill used to get a bare
    /// "Regular", which reads as an adjective describing the year beside it.
    func testSeasonPhaseAlwaysReadsAsAFullName() {
        XCTAssertEqual(SeasonPhase.regular.label, "Regular Season")
        XCTAssertEqual(SeasonPhase.playoffs.label, "Playoffs")
    }

    @MainActor
    func testSeasonPlayersReturnsPlayersForSelectedSeason() async {
        let player2026 = Player(
            playerId: 1, name: "Player 2026", team: "NYK", position: "G", handedness: "",
            updatedAt: Date(), season: 2026, metrics: [], standardStats: [], games: []
        )
        let player2025 = Player(
            playerId: 2, name: "Player 2025", team: "BOS", position: "F", handedness: "",
            updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []
        )

        let vm = makeViewModel(provider: MockProvider(players: [player2026, player2025]))
        await vm.load()

        vm.selectedSeason = 2026
        XCTAssertEqual(vm.seasonPlayers.map(\.playerId), [1])

        vm.selectedSeason = 2025
        XCTAssertEqual(vm.seasonPlayers.map(\.playerId), [2])
    }

    @MainActor
    func testSeasonPlayersIsEmptyWhenSeasonHasNoData() async {
        let player2026 = Player(
            playerId: 1, name: "Player 2026", team: "NYK", position: "G", handedness: "",
            updatedAt: Date(), season: 2026, metrics: [], standardStats: [], games: []
        )

        let vm = makeViewModel(provider: MockProvider(players: [player2026]))
        await vm.load()

        // A season with no data reports empty (no stale fallback).
        vm.selectedSeason = 2024
        XCTAssertTrue(vm.seasonPlayers.isEmpty)
    }

    @MainActor
    func testLoadNeverSnapsAwayFromTheLiveSeason() async {
        let lastSeason = Player(
            playerId: 1, name: "Last Season", team: "BOS", position: "G", handedness: "",
            updatedAt: Date(), season: testLiveSeason - 1, metrics: [], standardStats: [], games: []
        )
        let vm = makeViewModel(provider: MockProvider(players: [lastSeason]))
        vm.isPro = true
        await vm.load()
        XCTAssertEqual(vm.selectedSeason, testLiveSeason)
    }

    // MARK: - Fixtures

    private func makeCompleteHistoricalPlayers() -> [Player] {
        (StatScoutSeason.earliest..<testLiveSeason).flatMap { season in
            makeCompleteSeasonPlayers(season: season, namePrefix: "Historical")
        }
    }

    private func makeCompleteCurrentPlayers(namePrefix: String = "Cached") -> [Player] {
        makeCompleteSeasonPlayers(season: testLiveSeason, namePrefix: namePrefix)
    }

    private func makeCompleteSeasonPlayers(season: Int, namePrefix: String) -> [Player] {
        let types = ["g", "f", "c"]
        return nbaTeamAbbreviations.enumerated().flatMap { index, team in
            // Three players a team, one per cohort, so every cohort is present.
            types.enumerated().map { offset, type in
                Player(
                    playerId: 10_000 + index * 3 + offset,
                    name: "\(namePrefix) \(team) \(type)",
                    team: team,
                    position: type.uppercased(),
                    handedness: "",
                    updatedAt: Date(),
                    season: season,
                    playerType: type,
                    metrics: [
                        Metric(id: "pts-\(index)-\(offset)", label: "Pts/100", value: "25.0", percentile: 50, category: .scoring),
                        Metric(id: "ast-\(index)-\(offset)", label: "AST%", value: "15.0%", percentile: 50, category: .playmaking),
                        Metric(id: "reb-\(index)-\(offset)", label: "REB%", value: "10.0%", percentile: 50, category: .rebounding),
                    ],
                    standardStats: [StandardStat(id: "games-\(index)", label: "G", value: "60")],
                    games: []
                )
            }
        }
    }
}

final class InMemoryPlayerCache: PlayerCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Player]
    init(seed: [Player] = []) { self.stored = seed }
    var savedPlayers: [Player] { lock.withLock { stored } }
    func loadPlayers() throws -> [Player] { lock.withLock { stored } }
    func savePlayers(_ players: [Player], liveSeason: Int) throws { lock.withLock { stored = players } }
}

struct MockProvider: StatcastProviding, @unchecked Sendable {
    let players: [Player]?
    let error: Error?
    let freshness: DataFreshness?

    init(players: [Player]? = nil, error: Error? = nil, freshness: DataFreshness? = nil) {
        self.players = players
        self.error = error
        self.freshness = freshness
    }

    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] {
        if let error { throw error }
        return (players ?? []).filter { ($0.season ?? 0) < season }
    }

    func fetchCurrentPlayers(season: Int) async throws -> [Player] {
        if let error { throw error }
        return players ?? []
    }

    func fetchDataFreshness() async throws -> DataFreshness? {
        if let error { throw error }
        return freshness
    }

    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        if let error { throw error }
        return []
    }

    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm] {
        if let error { throw error }
        return []
    }

    func fetchDataCoverage(season: Int) async throws -> DataCoverage? {
        if let error { throw error }
        return nil
    }
}
