import XCTest
@testable import Hardwood_StatScout

/// Time budgets for the paths a Pro user hits on open and while scrolling,
/// against a worst-case history built in code: every season since 2003, about
/// 520 regular-season and 87 playoff players each, plus the career rollup.
/// That is every player who logged a minute, so a pass here is a pass on the
/// real archive with room to spare.
///
/// Guards the full-history board stutter football fixed in e440e69 / 965da18
/// (every read rescanned every row of every season), which this app shares by
/// construction. Budgets are about five times the time measured on the
/// simulator, so a loaded machine does not trip them but an accidental rescan
/// per read does.
final class PerformanceBudgetTests: XCTestCase {
    private static let teams = [
        "ATL", "BOS", "BKN", "CHA", "CHI", "CLE", "DAL", "DEN", "DET", "GS", "HOU", "IND", "LAC", "LAL", "MEM",
        "MIA", "MIL", "MIN", "NO", "NY", "OKC", "ORL", "PHI", "PHX", "POR", "SAC", "SA", "TOR", "UTA", "WSH",
    ]
    private static let firstNames = ["Josh", "Joe", "Jordan", "Justin", "Jared", "Jalen", "Mike", "Tom", "Dak", "Patrick"]
    private static let lastNames = (0..<60).map { "Surname\($0)" }

    /// Players per season and phase, by position: every player who logged a
    /// minute in a season, about 520, with a sixth of them in the playoffs.
    private static let regularCounts: [(PlayerPositionGroup, String, Int)] = [
        (.guard, "g", 200), (.forward, "f", 220), (.center, "c", 100),
    ]
    private static let playoffShare = 6

    /// A handful of distinct metric lists per position, shared between
    /// players, so building 50,000 rows stays well under the 2 s fixture limit.
    private static func metricVariants(for position: PlayerPositionGroup) -> [[Metric]] {
        let definitions = BasketballMetricRegistry.definitions.filter { $0.positions.contains(position) }
        return (0..<32).map { variant in
            definitions.enumerated().map { index, definition in
                let percentile = (variant * 7 + index * 13) % 100
                return Metric(
                    id: "\(definition.label)-\(variant)",
                    label: definition.label,
                    value: String(format: "%.1f", Double(percentile) / 3),
                    percentile: percentile,
                    category: definition.category,
                    qualified: variant % 5 != 0
                )
            }
        }
    }

    static func buildHistory(throughSeason last: Int) -> [Player] {
        let variants = Dictionary(uniqueKeysWithValues: PlayerPositionGroup.cohorts.map { ($0, metricVariants(for: $0)) })
        let stats = (0..<6).map { StandardStat(id: "s\($0)", label: "Stat \($0)", value: "\($0 * 11)") }
        let updated = Date(timeIntervalSince1970: 1_700_000_000)
        var players: [Player] = []
        players.reserveCapacity(60_000)
        var seasons = Array(StatScoutSeason.earliest...last)
        seasons.append(StatScoutSeason.allTime)
        for season in seasons {
            for phase in SeasonPhase.allCases {
                var base = 0
                for (group, type, count) in regularCounts {
                    let slots = phase == .regular ? count : count / playoffShare
                    for slot in 0..<slots {
                        // Spread careers: the same id recurs across seasons.
                        let id = base * 100_000 + (slot + season * 3) % (count + 40)
                        players.append(Player(
                            playerId: id,
                            name: "\(firstNames[id % firstNames.count]) \(lastNames[(id / 7) % lastNames.count])",
                            team: teams[(id + season) % teams.count],
                            position: group.rawValue,
                            handedness: "",
                            updatedAt: updated,
                            season: season,
                            seasonPhase: phase,
                            playerType: type,
                            metrics: variants[group]![(slot + season) % 32],
                            standardStats: stats,
                            games: []
                        ))
                    }
                    base += 1
                }
            }
        }
        return players
    }

    private static let fixture: [Player] = buildHistory(throughSeason: testLiveSeason - 1)

    @MainActor
    private func openedViewModel() async -> DashboardViewModel {
        let vm = makeViewModel(provider: MockProvider(players: Self.fixture))
        vm.isPro = true
        await vm.loadHistoricalIfNeeded()
        return vm
    }

    private func measure(_ label: String, _ body: () -> Void) -> TimeInterval {
        let start = Date()
        body()
        let elapsed = Date().timeIntervalSince(start)
        print("PERF \(label): \(Int(elapsed * 1000)) ms")
        return elapsed
    }

    func testFixtureBuildsQuickly() {
        let start = Date()
        let rows = Self.buildHistory(throughSeason: testLiveSeason - 1)
        let elapsed = Date().timeIntervalSince(start)
        print("PERF fixture build (\(rows.count) rows): \(Int(elapsed * 1000)) ms")
        XCTAssertGreaterThan(rows.count, 10_000)
        XCTAssertLessThan(elapsed, 2.0)
    }

    /// Opening a past season: group, sort and index every row, then derive
    /// the team table. The main-actor part of what the Pro user waits on.
    @MainActor
    func testIngestingFullHistoryStaysWithinBudget() async {
        let vm = makeViewModel(provider: MockProvider(players: Self.fixture))
        vm.isPro = true
        let start = Date()
        await vm.loadHistoricalIfNeeded()
        let elapsed = Date().timeIntervalSince(start)
        // Budgets below are about 5x the simulator time measured, floored at 0.5 s.
        print("PERF ingest full history: \(Int(elapsed * 1000)) ms")
        XCTAssertTrue(vm.hasLoadedHistorical)
        XCTAssertGreaterThan(vm.playerHistories.count, 500)
        XCTAssertLessThan(elapsed, 1.5)  // ingest, measured 314 ms
    }

    /// Flipping through every season on every position tab, reading what one
    /// render reads. This is the "scroll through the season menu" path.
    @MainActor
    func testSeasonAndPositionSwitchingStaysWithinBudget() async {
        let vm = await openedViewModel()
        let seasons = vm.availableSeasons
        XCTAssertGreaterThan(seasons.count, 24)
        let elapsed = measure("switch \(seasons.count) seasons x 3 positions") {
            for season in seasons {
                vm.selectSeason(season)
                for position in PlayerPositionGroup.cohorts {
                    vm.selectedPosition = position
                    _ = vm.currentSortMetric
                    _ = vm.availableAdvancedSortMetrics
                    for _ in 0..<3 { _ = vm.leaderboard }
                    _ = vm.teamsWithData
                }
            }
        }
        XCTAssertFalse(vm.leaderboard.isEmpty)
        XCTAssertLessThan(elapsed, 35.0)  // 25 seasons x 3 positions, measured 6.8 s (37 s before the board memoization)
    }

    /// Typing in search on the busiest board, then Best/Worst and the
    /// qualified list on the career rollup, the widest season there is.
    @MainActor
    func testSearchAndLeaderBoardsOnTheCareerRollupStayWithinBudget() async {
        let vm = await openedViewModel()
        vm.selectSeason(StatScoutSeason.allTime)
        vm.selectedPosition = .guard
        let typing = measure("search typing, career defense") {
            for query in ["", "j", "jo", "jos", "josh", "jos", "jo", "j", "", "surname1", ""] {
                vm.searchText = query
                _ = vm.leaderboard
                _ = vm.searchedTeams
            }
        }
        XCTAssertLessThan(typing, 2.0)  // typing, measured 395 ms (1.4 s before the memoization)

        vm.searchText = ""
        let boards = measure("best/worst + qualified, career") {
            for _ in 0..<10 {
                _ = vm.allMetrics
                _ = vm.qualifiedSeasonPlayers
            }
        }
        XCTAssertFalse(vm.allMetrics.isEmpty)
        XCTAssertLessThan(boards, 4.5)  // best/worst, measured 919 ms (7.1 s before the memoization)
    }

    /// Team pages and profiles resolve players by team and by id for every
    /// club, every time they open.
    @MainActor
    func testTeamAndProfileLookupsStayWithinBudget() async {
        let vm = await openedViewModel()
        vm.selectSeason(testLiveSeason - 1)
        let ids = Array(vm.playerHistories.keys.prefix(400))
        let elapsed = measure("32 team rosters + 400 profile lookups") {
            for team in Self.teams {
                _ = vm.players(forTeam: team)
                _ = vm.teamScore(team)
            }
            for id in ids {
                _ = vm.player(id: id, season: testLiveSeason - 1, phase: .regular)
            }
        }
        XCTAssertLessThan(elapsed, 2.5)  // lookups, measured 463 ms (1.1 s before the registry index)
    }
}
