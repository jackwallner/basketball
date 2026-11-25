import SwiftUI
import UIKit
import XCTest
@testable import Hardwood_StatScout

// Regression tests for the 2026-11-24 state machine audit
// (project-docs/audits/state-machines-2026-11-24.md). Each claim test failed on
// 0bb6057 and passes with its fix; each has a passing control.

// MARK: - Provider fake

/// Serves a different live-season feed on each call, so one view model can be
/// refreshed through an overnight prune.
final class FeedSequenceProvider: StatcastProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var feeds: [[Player]]
    private let historical: [Player]
    private var _calls = 0

    init(feeds: [[Player]], historical: [Player] = []) {
        self.feeds = feeds
        self.historical = historical
    }

    var calls: Int { lock.withLock { _calls } }

    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] { historical }

    func fetchCurrentPlayers(season: Int) async throws -> [Player] {
        lock.withLock {
            defer { _calls += 1 }
            return feeds[min(_calls, feeds.count - 1)]
        }
    }

    func fetchDataFreshness() async throws -> DataFreshness? { nil }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
}

/// Thirty teams, three players each (one per cohort), with the metrics the
/// completeness check asks for: a feed the app accepts as a full refresh.
func completeLiveFeed(season: Int) -> [Player] {
    let types = ["g", "f", "c"]
    return nbaTeamAbbreviations.enumerated().flatMap { index, abbr in
        types.enumerated().map { offset, type in
            Player(
                playerId: 20_000 + index * 3 + offset,
                name: "Feed \(abbr) \(type)",
                team: abbr,
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

// MARK: - B2: a refresh drops live-season rows the publisher pruned

@MainActor
final class PrunedFeedRegressionTests: XCTestCase {
    /// The publisher deletes every live-season snapshot it no longer builds
    /// (backend/ingest.py `_prune_orphans`); an open app's refresh follows.
    func testRefreshDropsAPlayerThePublisherPruned() async {
        let full = completeLiveFeed(season: testLiveSeason)
        let pruned = full.first!
        let provider = FeedSequenceProvider(feeds: [full, Array(full.dropFirst())])
        let vm = makeViewModel(provider: provider)

        await vm.load()
        XCTAssertEqual(vm.seasonPlayers.count, full.count, "precondition: first load shows the full feed")
        XCTAssertTrue(vm.seasonPlayers.contains { $0.playerId == pruned.playerId })

        await vm.load()
        XCTAssertEqual(provider.calls, 2, "precondition: the refresh asked for the feed again")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.lastFetchFailed, "precondition: the refresh succeeded")

        XCTAssertFalse(vm.seasonPlayers.contains { $0.playerId == pruned.playerId },
                       "the publisher pruned this player, but the board still ranks him")
        XCTAssertEqual(vm.seasonPlayers.count, full.count - 1)
    }

    /// Upgrade path: a cache written by 1.0.1 still holds the pruned row. The
    /// first launch shows the feed, and the rewritten cache drops it too.
    func testColdLaunchFromAnExistingCacheDropsThePrunedRow() async {
        let full = completeLiveFeed(season: testLiveSeason)
        let pruned = full.first!
        let cache = InMemoryPlayerCache(seed: full)
        let vm = makeViewModel(provider: FeedSequenceProvider(feeds: [Array(full.dropFirst())]), cache: cache)

        await vm.load()
        XCTAssertFalse(vm.lastFetchFailed, "precondition: the feed was accepted")
        XCTAssertFalse(vm.seasonPlayers.contains { $0.playerId == pruned.playerId })
        XCTAssertEqual(vm.seasonPlayers.count, full.count - 1)
        XCTAssertFalse(cache.savedPlayers.contains { $0.playerId == pruned.playerId })
    }

    /// Control: a row still in the feed takes its newer values.
    func testRefreshStillReplacesARowThatIsInTheFeed() async {
        let before = completeLiveFeed(season: testLiveSeason)
        let renamedID = before.first!.playerId
        let after = before.map { player -> Player in
            guard player.playerId == renamedID else { return player }
            return Player(
                playerId: player.playerId, name: "Renamed", team: player.team, position: player.position,
                handedness: "", updatedAt: Date(), season: player.season, playerType: player.playerType,
                metrics: player.metrics, standardStats: player.standardStats, games: []
            )
        }
        let vm = makeViewModel(provider: FeedSequenceProvider(feeds: [before, after]))
        await vm.load()
        await vm.load()
        XCTAssertEqual(vm.seasonPlayers.first { $0.playerId == renamedID }?.name, "Renamed")
        XCTAssertEqual(vm.seasonPlayers.count, before.count)
    }

    /// Control: past seasons are not the live feed's to prune.
    func testRefreshKeepsPastSeasonRows() async {
        let full = completeLiveFeed(season: testLiveSeason)
        let past = completeLiveFeed(season: testLiveSeason - 1)
        let provider = FeedSequenceProvider(feeds: [full, Array(full.dropFirst())], historical: past)
        let vm = makeViewModel(provider: provider)
        vm.isPro = true

        await vm.load()
        await vm.loadHistoricalIfNeeded()
        XCTAssertEqual(vm.players(forSeason: testLiveSeason - 1).count, past.count, "precondition: past season loaded")

        await vm.load()
        XCTAssertEqual(provider.calls, 2)
        XCTAssertEqual(vm.players(forSeason: testLiveSeason - 1).count, past.count)
        XCTAssertEqual(vm.players(forSeason: testLiveSeason).count, full.count - 1)
    }
}
