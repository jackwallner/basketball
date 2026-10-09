import XCTest
@testable import Hardwood_StatScout

/// How the app decides which season is live, and that it rolls over by itself.
final class SeasonResolverTests: XCTestCase {
    private func status(
        raw: String,
        season: Int?,
        published: Int?,
        code: String? = nil
    ) -> DataFreshness {
        DataFreshness(
            status: DataFreshnessStatus(rawValue: raw),
            rawStatus: raw,
            season: season,
            publishedSeason: published,
            lastErrorCode: code
        )
    }

    // MARK: - The calendar rule

    func testCalendarSeasonFollowsTheOctoberRule() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func season(_ iso: String) -> Int {
            StatScoutSeason.calendarSeason(on: ISO8601DateFormatter().date(from: iso)!, calendar: calendar)
        }
        XCTAssertEqual(season("2026-09-30T12:00:00Z"), 2026)
        XCTAssertEqual(season("2026-10-01T12:00:00Z"), 2027)
        XCTAssertEqual(season("2026-10-08T12:00:00Z"), 2027)
        XCTAssertEqual(season("2026-12-31T12:00:00Z"), 2027)
        XCTAssertEqual(season("2027-01-01T12:00:00Z"), 2027)
        XCTAssertEqual(season("2027-06-30T12:00:00Z"), 2027)
        XCTAssertEqual(season("2027-10-01T12:00:00Z"), 2028)
    }

    // MARK: - resolveLive

    /// The state the backend is in today: the calendar says 2026-27, the data is
    /// still 2025-26.
    func testPendingSeasonKeepsThePublishedSeasonLive() {
        let live = StatScoutSeason.resolveLive(
            from: status(raw: "source_pending", season: 2027, published: 2026, code: "season_pending"),
            fallback: 2026
        )
        XCTAssertEqual(live.season, 2026)
        XCTAssertEqual(live.upcoming, 2027)
        XCTAssertTrue(live.isPending)
    }

    /// The moment the publisher flips to a published revision for the new
    /// season, the app follows, with no release in between.
    func testRolloverHappensWhenThePublisherCatchesUp() {
        for raw in ["published", "degraded", "complete"] {
            let live = StatScoutSeason.resolveLive(
                from: status(raw: raw, season: 2027, published: 2027),
                fallback: 2026
            )
            XCTAssertEqual(live.season, 2027, raw)
            XCTAssertNil(live.upcoming, raw)
            XCTAssertFalse(live.isPending, raw)
        }
    }

    func testAMidSeasonStallIsNotAPendingSeason() {
        let live = StatScoutSeason.resolveLive(
            from: status(raw: "source_pending", season: 2027, published: 2027, code: "source_unavailable"),
            fallback: 2026
        )
        XCTAssertEqual(live.season, 2027)
        XCTAssertNil(live.upcoming)
    }

    /// A pending flag with no published season on the row (an older backend)
    /// cannot be proven to be a season gap, so it is not treated as one.
    func testAnOlderRowWithoutPublishedSeasonUsesTheRowsSeason() {
        let live = StatScoutSeason.resolveLive(
            from: status(raw: "source_pending", season: 2026, published: nil, code: "season_pending"),
            fallback: 2025
        )
        XCTAssertEqual(live.season, 2026)
        XCTAssertNil(live.upcoming)
    }

    func testNoStatusFallsBackToTheLastKnownSeason() {
        XCTAssertEqual(StatScoutSeason.resolveLive(from: nil, fallback: 2026), .init(season: 2026, upcoming: nil))
        XCTAssertEqual(
            StatScoutSeason.resolveLive(from: DataFreshness(), fallback: 2026).season,
            2026,
            "a status row with no seasons on it changes nothing"
        )
    }

    /// A failed check is a display state, not a season change.
    func testAFailedCheckDoesNotMoveTheSeason() {
        let failed = status(raw: "failed", season: 2027, published: 2026)
        XCTAssertEqual(StatScoutSeason.resolveLive(from: failed, fallback: 2026).season, 2026)
    }

    // MARK: - Remembered across launches

    func testInitialLiveRemembersTheLastResolution() {
        let name = "resolver-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        // Nothing remembered: the calendar's season, capped at the bundle.
        XCTAssertEqual(StatScoutSeason.initialLive(defaults: defaults, calendarSeason: 2027).season, 2026)
        XCTAssertEqual(StatScoutSeason.initialLive(defaults: defaults, calendarSeason: 2025).season, 2025)

        StatScoutSeason.remember(.init(season: 2026, upcoming: 2027), defaults: defaults)
        let restored = StatScoutSeason.initialLive(defaults: defaults, calendarSeason: 2027)
        XCTAssertEqual(restored, .init(season: 2026, upcoming: 2027))

        StatScoutSeason.remember(.init(season: 2027, upcoming: nil), defaults: defaults)
        XCTAssertEqual(
            StatScoutSeason.initialLive(defaults: defaults, calendarSeason: 2027),
            .init(season: 2027, upcoming: nil)
        )
    }

    // MARK: - Labels

    func testSeasonsReadAsTheYearTheyEndIn() {
        XCTAssertEqual(SeasonLabel.text(2027), "2026-27")
        XCTAssertEqual(SeasonLabel.text(2026), "2025-26")
        XCTAssertEqual(SeasonLabel.text(0), "All Time")
        XCTAssertFalse(SeasonLabel.text(2026).contains("2026"))
    }
}

/// The two-tier cache while the bundled archive and the live season overlap.
final class TwoTierCacheTests: XCTestCase {
    private func players(season: Int, name: String, count: Int = 24) -> [Player] {
        (0..<count).map { index in
            Player(
                playerId: 100 + index, name: "\(name) \(index)",
                team: ["BOS", "NYK"][index % 2], position: "G",
                handedness: "", updatedAt: Date(timeIntervalSince1970: 0), season: season,
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

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    func testCompleteOpeningNightIsCacheableBeforeFullSlate() {
        XCTAssertTrue(PlayerSnapshotValidator.isCompleteCurrent(players(season: 2027, name: "A"), season: 2027))
    }

    func testCurrentSnapshotNeedsTwoTeamsAllCohortsAndTheCoreMetrics() {
        let oneTeam = players(season: 2027, name: "A").map {
            Player(playerId: $0.playerId, name: $0.name, team: "BOS", position: $0.position, handedness: "",
                   updatedAt: $0.updatedAt, season: 2027, playerType: $0.playerType,
                   metrics: $0.metrics, standardStats: [], games: [])
        }
        XCTAssertFalse(PlayerSnapshotValidator.isCompleteCurrent(oneTeam, season: 2027))
        XCTAssertFalse(PlayerSnapshotValidator.isCompleteCurrent(
            players(season: 2027, name: "A").filter { $0.playerType != "c" }, season: 2027))
        XCTAssertFalse(PlayerSnapshotValidator.isCompleteCurrent(
            players(season: 2027, name: "A").map {
                Player(playerId: $0.playerId, name: $0.name, team: $0.team, position: $0.position, handedness: "",
                       updatedAt: $0.updatedAt, season: 2027, playerType: $0.playerType,
                       metrics: [Metric(id: "x", label: "TS%", value: "1", percentile: 1, category: .scoring)],
                       standardStats: [], games: [])
            }, season: 2027))
    }

    /// Last season's rows are not the live season's, whichever season is asked.
    func testASnapshotOfAnotherSeasonIsNotCurrentData() {
        XCTAssertFalse(PlayerSnapshotValidator.isCompleteCurrent(players(season: 2026, name: "A"), season: 2027))
        XCTAssertTrue(PlayerSnapshotValidator.isCompleteCurrent(players(season: 2026, name: "A"), season: 2026))
        // With no season named, the newest regular season present is judged.
        XCTAssertTrue(PlayerSnapshotValidator.isCompleteCurrent(players(season: 2026, name: "A")))
    }

    func testSavedServerSnapshotIsKeptWhateverItsAge() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = TwoTierPlayerCache(directory: dir)
        try cache.savePlayers(players(season: 2026, name: "Server"), liveSeason: 2026)
        let file = dir.appending(path: "players-current.json")
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: weekAgo], ofItemAtPath: file.path)

        XCTAssertEqual(try cache.loadCurrentPlayers().count, 24)
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        XCTAssertEqual(modified?.timeIntervalSince1970 ?? 0, weekAgo.timeIntervalSince1970, accuracy: 1)
    }

    func testNoSavedSnapshotServesNoCurrentPlayers() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(try TwoTierPlayerCache(directory: dir).loadCurrentPlayers().isEmpty)
    }

    /// The live season splits from history at the season the server is
    /// writing, which is 2026 while 2026-27 is pending.
    func testSaveSplitsHistoryFromTheLiveSeasonAtTheLiveSeason() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = TwoTierPlayerCache(directory: dir)
        try cache.savePlayers(players(season: 2026, name: "Live"), liveSeason: 2026)
        XCTAssertEqual(try cache.loadCurrentPlayers().count, 24)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "players-current.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "players-historical.plist").path),
                       "a live-season save writes no history")
    }

    // MARK: - The real bundle

    private func bundledPlayers() throws -> [Player] {
        // The archive is a resource of the app, which hosts these tests.
        let bundle = Bundle(for: DashboardViewModel.self)
        let url = try XCTUnwrap(bundle.url(forResource: "players-historical", withExtension: "plist"))
        return try PropertyListDecoder.statScout.decode([Player].self, from: Data(contentsOf: url))
    }

    /// The bundled archive carries 2025-26 too, which is why the network copy
    /// has to win while 2026 is live. A real row has to decode end to end.
    func testARealBundledRowFrom2026Decodes() throws {
        let all = try bundledPlayers()
        let row = try XCTUnwrap(all.first {
            $0.name == "Shai Gilgeous-Alexander" && $0.season == 2026 && $0.seasonPhase == .regular
        })
        XCTAssertEqual(row.playerId, 4278073)
        XCTAssertEqual(row.team, "OKC")
        XCTAssertEqual(row.playerType, "g")
        XCTAssertEqual(row.positionGroup, .guard)
        XCTAssertEqual(row.metrics.count, 47)
        XCTAssertEqual(Set(row.metrics.map(\.category)), Set(MetricCategory.allCases), "all six categories")
        let ppg = try XCTUnwrap(row.metrics.first { $0.label == "PPG" })
        XCTAssertEqual(ppg.value, "31.1")
        XCTAssertEqual(ppg.category, .scoring)
        // Every label the backend wrote is one the registry knows.
        for metric in row.metrics {
            XCTAssertNotNil(
                BasketballMetricRegistry.definition(for: metric.label, category: metric.category),
                "\(metric.label) / \(metric.category)"
            )
        }
        // The standard line, in the contract's order, with made/attempted pairs.
        XCTAssertEqual(
            row.standardStats?.map(\.label),
            ["G", "GS", "MPG", "PPG", "RPG", "APG", "SPG", "BPG", "FG", "3P", "FT", "TOV", "PF", "+/-", "MIN"]
        )
        XCTAssertEqual(row.standardStats?.first { $0.label == "FG" }?.value, "731/1,321")
        XCTAssertEqual(
            StandardStatSemantics.numericValue(label: "FG", value: "731/1,321")!,
            731.0 / 1321.0 * 100,
            accuracy: 0.001
        )
    }

    /// 832 bundled rows (all of 2007-08 and 2010-11) carry `updated_at` as the
    /// raw string the exporter could not turn into a date, with five fractional
    /// digits. One of them used to fail the decode of every past season at once.
    func testBundledRowsWithAStringTimestampDecode() throws {
        let all = try bundledPlayers()
        XCTAssertGreaterThan(all.count, 11_000)
        let row = try XCTUnwrap(all.first { $0.season == 2008 && $0.seasonPhase == .regular })
        XCTAssertGreaterThan(row.updatedAt.timeIntervalSince1970, 1_700_000_000)
        XCTAssertNotNil(DataFreshness.parseDate("2026-10-08T21:38:26.20338+00:00"))
        XCTAssertNotNil(DataFreshness.parseDate("2026-10-08T21:38:26+00:00"))
        XCTAssertNotNil(DataFreshness.parseDate("2026-10-08"))
        XCTAssertNil(DataFreshness.parseDate("not a date"))
    }

    func testTheBundleCarriesEverySeasonFrom2003ThroughTheLastCompleted() throws {
        let all = try bundledPlayers()
        XCTAssertTrue(PlayerSnapshotValidator.isCompleteHistorical(all))
        let seasons = Set(all.compactMap(\.season))
        XCTAssertEqual(seasons.max(), StatScoutSeason.bundledNewest)
        XCTAssertEqual(seasons.subtracting([StatScoutSeason.allTime]).min(), StatScoutSeason.earliest)
        XCTAssertTrue(seasons.contains(StatScoutSeason.allTime), "the career rollup")
    }

    /// While 2026 is live and the network copy is present, it replaces the
    /// bundled one rather than the other way round.
    func testServerRowsWinOverTheBundledArchive() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = TwoTierPlayerCache(directory: dir)
        let bundled = try bundledPlayers().first { $0.season == 2026 && $0.seasonPhase == .regular }
        let template = try XCTUnwrap(bundled)
        let fresh = (0..<24).map { index in
            Player(
                playerId: index == 0 ? template.playerId : 900 + index,
                name: index == 0 ? "Fresh From Server" : "Server \(index)",
                team: ["OKC", "NYK"][index % 2], position: "G", handedness: "",
                updatedAt: Date(), season: 2026, playerType: ["g", "f", "c"][index % 3],
                metrics: template.metrics, standardStats: template.standardStats, games: []
            )
        }
        try cache.savePlayers(fresh, liveSeason: 2026)

        let merged = try cache.loadPlayers()
        let rows = merged.filter { $0.playerId == template.playerId && $0.season == 2026 && $0.seasonPhase == .regular }
        XCTAssertEqual(rows.count, 1, "one row per player and season")
        XCTAssertEqual(rows.first?.name, "Fresh From Server")
        // History is still there underneath.
        XCTAssertTrue(merged.contains { $0.season == 2003 })
    }

    /// The same rule through the view model: archive rows for the live season
    /// fill in what the network has not delivered and never overwrite it.
    @MainActor
    func testLoadingHistoryNeverOverwritesTheLiveSeasonFromTheNetwork() async {
        let live = players(season: 2026, name: "Network")
        let archive = players(season: 2026, name: "Archive") + players(season: 2025, name: "Past")
        let vm = makeViewModel(provider: MockProvider(players: live, freshness: nil), cache: ArchiveCache(archive))
        vm.isPro = true
        await vm.load()
        await vm.loadHistoricalIfNeeded()

        let liveRows = vm.players(forSeason: 2026)
        XCTAssertEqual(liveRows.count, 24)
        XCTAssertTrue(liveRows.allSatisfy { $0.name.hasPrefix("Network") })
        XCTAssertEqual(vm.players(forSeason: 2025).count, 24)
    }
}

/// A cache whose archive overlaps the live season, as the real bundle does.
private final class ArchiveCache: PlayerCaching, @unchecked Sendable {
    let archive: [Player]
    init(_ archive: [Player]) { self.archive = archive }
    func loadPlayers() throws -> [Player] { archive }
    func savePlayers(_ players: [Player], liveSeason: Int) throws {}
}
