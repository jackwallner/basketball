import XCTest
@testable import Hardwood_StatScout

final class DataFreshnessTests: XCTestCase {
    func testProductionStatusDecodesCoverageAndPendingEnrichment() throws {
        let json = """
        {"status":"degraded","refresh_id":"v2","source_published_at":null,
         "published_at":"2026-10-22T12:05:00Z","last_checked_at":"2026-10-22T12:10:00Z",
         "max_game_date":"2026-10-21","max_week":3,"observed_games":10,"expected_games":10,"season_type":"REG",
         "season":2027,"published_season":2027,"ngs_status":"pending","pfr_status":"ready"}
        """
        let status = try JSONDecoder.statScout.decode(DataFreshness.self, from: Data(json.utf8))
        XCTAssertEqual(status.status, .partial)
        XCTAssertEqual(status.revision, "v2")
        XCTAssertEqual(status.coverage?.gamesIncluded, 10)
        XCTAssertEqual(status.publishedSeason, 2027)
        XCTAssertEqual(status.shotsStatus, "pending")
        XCTAssertNil(status.sourcePublishedAt)
        XCTAssertFalse(status.isSeasonPending)
    }

    /// The row the publisher really wrote on 2026-10-08, trimmed to the columns
    /// the app reads.
    func testTheRealPendingRowDecodes() throws {
        let json = """
        {"status":"source_pending","refresh_id":"ec7f98cf","source_published_at":null,
         "published_at":"2026-10-08T21:43:06.835518+00:00","last_checked_at":"2026-10-08T22:14:07.504338+00:00",
         "season":2027,"season_type":"POST,REG","max_week":37,"max_game_date":"2026-06-13",
         "expected_games":1316,"observed_games":1316,"coverage_status":"complete",
         "ngs_status":"ready","pfr_status":"ready","last_error_code":"season_pending","published_season":2026}
        """
        let status = try JSONDecoder.statScout.decode(DataFreshness.self, from: Data(json.utf8))
        XCTAssertTrue(status.isSeasonPending)
        XCTAssertEqual(status.status, .pending)
        XCTAssertEqual(status.season, 2027)
        XCTAssertEqual(status.publishedSeason, 2026)
        XCTAssertEqual(status.lastErrorCode, "season_pending")
        // A "POST,REG" season_type is not a phase; the coverage defaults to regular.
        XCTAssertEqual(status.coverage?.phase, .regular)
        XCTAssertEqual(status.coverage?.gamesIncluded, 1316)
        XCTAssertFalse(status.isAdvancedPending)
    }

    func testPendingNeedsAllThreeConditions() {
        func status(raw: String, season: Int?, published: Int?, code: String?) -> DataFreshness {
            DataFreshness(rawStatus: raw, season: season, publishedSeason: published, lastErrorCode: code)
        }
        XCTAssertTrue(status(raw: "source_pending", season: 2027, published: 2026, code: "season_pending").isSeasonPending)
        // An ordinary stall in the middle of a season is not a pending season.
        XCTAssertFalse(status(raw: "source_pending", season: 2027, published: 2027, code: "season_pending").isSeasonPending)
        XCTAssertFalse(status(raw: "source_pending", season: 2027, published: 2026, code: nil).isSeasonPending)
        XCTAssertFalse(status(raw: "published", season: 2027, published: 2026, code: "season_pending").isSeasonPending)
        XCTAssertFalse(status(raw: "source_pending", season: nil, published: 2026, code: "season_pending").isSeasonPending)
    }

    func testStatusSurvivesTheLocalCache() throws {
        let pending = DataFreshness(
            status: .pending, revision: "r", rawStatus: "source_pending",
            season: 2027, publishedSeason: 2026, lastErrorCode: "season_pending"
        )
        let back = try JSONDecoder.statScout.decode(
            DataFreshness.self,
            from: JSONEncoder.statScout.encode(pending)
        )
        XCTAssertTrue(back.isSeasonPending)
        // A local display override is no longer what the publisher said.
        XCTAssertFalse(pending.replacing(status: .offline).isSeasonPending)
        XCTAssertEqual(pending.replacing(isCached: true).publishedSeason, 2026)
    }

    @MainActor
    func testPublishedCoreRevisionIsAdoptedWithAdvancedMetricsPending() async {
        let provider = RevisionProvider(revisions: ["v1", "v1"], status: .partial)
        let model = makeViewModel(provider: provider)
        await model.load()
        XCTAssertEqual(model.freshnessRevision, "v1")
        XCTAssertEqual(model.freshnessStatus, .partial)
        XCTAssertEqual(model.dataCoverage?.gamesIncluded, 2)
    }

    @MainActor
    func testRevisionChangeDuringFetchDoesNotAdoptMixedData() async {
        let provider = RevisionProvider(revisions: ["v1", "v2"])
        let model = makeViewModel(provider: provider)
        await model.load()
        // A cold start draws the players it fetched rather than a blank
        // screen, but a revision that moved under the fetch is never adopted
        // or paired with the newer status: no revision, no coverage, and the
        // next check (which sees a revision it has not displayed) reloads.
        XCTAssertFalse(model.players.isEmpty)
        XCTAssertNil(model.freshnessRevision)
        XCTAssertNil(model.freshnessForDisplay?.coverage)
        XCTAssertEqual(model.freshnessStatus, .checking)
    }

    @MainActor
    func testFailedFirstStatusReadStillShowsPlayers() async {
        let provider = RevisionProvider(revisions: ["v1", "v1"], failFirstCheck: true)
        let model = makeViewModel(provider: provider)
        await model.load()
        XCTAssertFalse(model.players.isEmpty)
    }

    @MainActor
    func testEquivalentRefreshRequestsShareOnePlayerFetch() async {
        let provider = RevisionProvider(revisions: ["v1", "v1"])
        let model = makeViewModel(provider: provider)
        async let first: Void = model.load()
        async let second: Void = model.load()
        _ = await (first, second)
        let count = await provider.playerFetches
        XCTAssertEqual(count, 1)
    }
}

private actor RevisionProvider: StatcastProviding {
    let revisions: [String]
    let status: DataFreshnessStatus
    var checks = 0
    private(set) var playerFetches = 0
    let failFirstCheck: Bool
    init(revisions: [String], status: DataFreshnessStatus = .ready, failFirstCheck: Bool = false) {
        self.revisions = revisions
        self.status = status
        self.failFirstCheck = failFirstCheck
    }
    func fetchDataFreshness() async throws -> DataFreshness? {
        if failFirstCheck, checks == 0 {
            checks += 1
            throw URLError(.notConnectedToInternet)
        }
        let revision = revisions[min(checks, revisions.count - 1)]
        checks += 1
        return DataFreshness(status: status, revision: revision,
            coverage: DataCoverage(asOf: Date(timeIntervalSince1970: 1000), week: 1,
                phase: .regular, gamesIncluded: 2, expectedGames: 2),
            season: testLiveSeason, publishedSeason: testLiveSeason)
    }
    func fetchCurrentPlayers(season: Int) async throws -> [Player] {
        playerFetches += 1
        try await Task.sleep(for: .milliseconds(20))
        return [Player(playerId: 1, name: "Fixture", team: "BOS", position: "G", handedness: "",
            updatedAt: Date(timeIntervalSince1970: 1000), season: testLiveSeason,
            playerType: "g", metrics: [], standardStats: [], games: [])]
    }
    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
}

final class DataFreshnessCaptionTests: XCTestCase {
    func testShortAgeStaysCompact() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(DataFreshnessView.shortAge(of: now.addingTimeInterval(5), now: now), "just now")
        XCTAssertEqual(DataFreshnessView.shortAge(of: now.addingTimeInterval(-59), now: now), "just now")
        XCTAssertEqual(DataFreshnessView.shortAge(of: now.addingTimeInterval(-600), now: now), "10m ago")
        XCTAssertEqual(DataFreshnessView.shortAge(of: now.addingTimeInterval(-7_200), now: now), "2h ago")
    }
}
