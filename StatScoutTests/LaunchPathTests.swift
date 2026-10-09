import XCTest
@testable import Hardwood_StatScout

/// The first screen has to appear without waiting on anything it does not need:
/// the downloads start before the views are built, the leaderboard is drawn as
/// soon as the players arrive (not after the follow-up reads), and an offline
/// first launch decodes one bundled season rather than the whole archive.
@MainActor
final class LaunchPathTests: XCTestCase {
    private func livePlayers(count: Int = 24) -> [Player] {
        (0..<count).map { index in
            Player(
                playerId: 100 + index, name: "Live \(index)",
                team: ["BOS", "NYK"][index % 2], position: "G", handedness: "",
                updatedAt: Date(timeIntervalSince1970: 0), season: testLiveSeason,
                playerType: ["g", "f", "c"][index % 3],
                metrics: [
                    Metric(id: "p", label: "Pts/100", value: "25.0", percentile: 50, category: .scoring),
                    Metric(id: "a", label: "AST%", value: "15.0%", percentile: 50, category: .playmaking),
                    Metric(id: "r", label: "REB%", value: "10.0%", percentile: 50, category: .rebounding),
                ],
                standardStats: [], games: []
            )
        }
    }

    func testPrefetchedDownloadsAreUsedOnceAndNotRepeated() async {
        let provider = CountingProvider(players: livePlayers())
        let vm = makeViewModel(provider: provider)
        vm.startPrefetch()
        vm.startPrefetch()
        await vm.load()

        XCTAssertEqual(vm.players.count, 24)
        XCTAssertEqual(provider.playerFetches, 1, "the prefetch is the load's fetch, not a second one")
        // One prefetched status read plus the closing check at the end of the load.
        XCTAssertEqual(provider.freshnessFetches, 2)
    }

    func testPrefetchForAnotherSeasonIsDiscardedAndRefetched() async {
        let provider = CountingProvider(players: livePlayers())
        // The status row names 2027 as live, so a prefetch for 2026 is wrong.
        provider.freshness = DataFreshness(
            status: .ready, revision: "r1", publishedAt: Date(),
            season: 2027, publishedSeason: 2027
        )
        let vm = makeViewModel(provider: provider)
        vm.startPrefetch()
        await vm.load()

        XCTAssertEqual(provider.seasonsRequested.first, testLiveSeason, "the prefetch asked for the remembered season")
        XCTAssertEqual(provider.seasonsRequested.last, 2027, "and the load asked again once the status row said 2027")
    }

    func testTheLeaderboardIsOnScreenBeforeTheFollowUpReadsFinish() async {
        let provider = CountingProvider(players: livePlayers())
        provider.coverageDelay = 1_500_000_000
        let vm = makeViewModel(provider: provider)
        let load = Task { await vm.load() }

        let deadline = Date().addingTimeInterval(1.0)
        while vm.players.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(vm.players.count, 24, "players are drawn before the slow coverage read returns")
        XCTAssertFalse(vm.isLoading)
        load.cancel()
        await load.value
    }

    /// An offline first launch with nothing saved shows the newest bundled
    /// season, and leaves the rest of the archive for when something asks.
    func testOfflineColdStartDecodesOnlyTheNewestBundledSeason() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TwoTierPlayerCache(directory: directory, bundle: Bundle(for: DashboardViewModel.self))
        let vm = makeViewModel(
            provider: MockProvider(error: URLError(.notConnectedToInternet)),
            cache: cache
        )
        await vm.load()

        XCTAssertFalse(vm.players.isEmpty, "a cold offline start still has a board")
        XCTAssertTrue(vm.lastFetchFailed, "and still says the refresh failed")
        XCTAssertEqual(Set(vm.players.compactMap(\.season)), [testLiveSeason])
        XCTAssertFalse(vm.hasLoadedHistorical, "the other seasons are not decoded until asked for")
    }

    /// Picking a past season decodes that season first and the rest after, so
    /// the board the user is waiting on does not wait for the whole archive.
    func testSelectingAPastSeasonLoadsItAndThenTheRestOfTheArchive() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TwoTierPlayerCache(directory: directory, bundle: Bundle(for: DashboardViewModel.self))
        let vm = makeViewModel(provider: MockProvider(players: livePlayers()), cache: cache)
        vm.isPro = true
        await vm.load()

        vm.selectSeason(2010)
        await vm.seasonLoadTask?.value

        XCTAssertFalse(vm.players(forSeason: 2010).isEmpty)
        XCTAssertTrue(vm.hasLoadedHistorical)
        XCTAssertFalse(vm.players(forSeason: 2003).isEmpty, "the rest of the archive follows")
        let network = vm.players(forSeason: testLiveSeason).filter { $0.name.hasPrefix("Live ") }
        XCTAssertEqual(network.count, 24, "the network rows are untouched by the archive")
    }
}

/// Counts what the view model asks the network for.
private final class CountingProvider: StatcastProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _playerFetches = 0
    private var _freshnessFetches = 0
    private var _seasons: [Int] = []
    private let players: [Player]
    var freshness: DataFreshness?
    var coverageDelay: UInt64 = 0

    init(players: [Player]) { self.players = players }

    var playerFetches: Int { lock.lock(); defer { lock.unlock() }; return _playerFetches }
    var freshnessFetches: Int { lock.lock(); defer { lock.unlock() }; return _freshnessFetches }
    var seasonsRequested: [Int] { lock.lock(); defer { lock.unlock() }; return _seasons }

    private func recordPlayerFetch(_ season: Int) {
        lock.lock(); defer { lock.unlock() }
        _playerFetches += 1
        _seasons.append(season)
    }

    private func recordFreshnessFetch() {
        lock.lock(); defer { lock.unlock() }
        _freshnessFetches += 1
    }

    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] { [] }

    func fetchCurrentPlayers(season: Int) async throws -> [Player] {
        recordPlayerFetch(season)
        return players.map { player in
            Player(
                playerId: player.playerId, name: player.name, team: player.team, position: player.position,
                handedness: player.handedness, updatedAt: player.updatedAt, season: season,
                playerType: player.playerType, metrics: player.metrics,
                standardStats: player.standardStats, games: player.games
            )
        }
    }

    func fetchDataFreshness() async throws -> DataFreshness? {
        recordFreshnessFetch()
        return freshness
    }

    func fetchDataCoverage(season: Int) async throws -> DataCoverage? {
        if coverageDelay > 0 { try await Task.sleep(nanoseconds: coverageDelay) }
        return nil
    }

    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
    func fetchGames(season: Int) async throws -> [Game] { [] }
    func fetchGameLogs(gameId: String) async throws -> [PlayerGameLog] { [] }
    func fetchGameIdsWithStats(season: Int) async throws -> Set<String> { [] }
    func fetchGameDetail(gameId: String) async throws -> GameDetail? { nil }
    func fetchPlayerProfiles(season: Int) async throws -> [PlayerProfile] { [] }
    func fetchTeamRatings(season: Int) async throws -> [TeamRating] { [] }
    func fetchGameProjections(season: Int) async throws -> [GameProjection] { [] }
}
