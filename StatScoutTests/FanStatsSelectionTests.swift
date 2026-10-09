import XCTest
@testable import Hardwood_StatScout

final class FanStatsSelectionTests: XCTestCase {
    func testFollowingDoesNotSubstitutePriorSeasonOrPostseasonStats() {
        let players = [player(1, season: 2025), player(2), player(1, phase: .playoffs)]
        let selected = FanStatsSelection.players(ids: [1, 2], from: players, season: 2026, phase: .regular)
        XCTAssertEqual(selected.map(\.playerId), [2])
    }

    func testFollowingPreservesPersonalOrderAndDeduplicates() {
        let players = [player(1), player(2), player(2), player(3)]
        let selected = FanStatsSelection.players(ids: [3, 2, 3, 99, 1], from: players, season: 2026, phase: .regular)
        XCTAssertEqual(selected.map(\.playerId), [3, 2, 1])
    }

    func testMissingSummaryStatsAreNotShownAsZero() {
        let selected = player(1, stats: [StandardStat(id: "ppg", label: "PPG", value: "28.4")])
        XCTAssertEqual(FanStatsSelection.summary(for: selected).map(\.label), ["PPG"])
        XCTAssertTrue(FanStatsSelection.summary(for: player(2)).isEmpty)
    }

    func testSummaryIsScoringReboundingAndPlaymakingInThatOrder() {
        let stats = ["APG", "RPG", "PPG", "SPG"].map { StandardStat(id: $0, label: $0, value: "1.0") }
        XCTAssertEqual(FanStatsSelection.summary(for: player(1, stats: stats)).map(\.label), ["PPG", "RPG", "APG"])
    }

    private func player(
        _ id: Int, season: Int = 2026, phase: SeasonPhase = .regular,
        stats: [StandardStat] = []
    ) -> Player {
        Player(
            playerId: id, name: "Player \(id)", team: "SEA", position: "G",
            handedness: "", updatedAt: Date(timeIntervalSince1970: 0), season: season,
            seasonPhase: phase, playerType: "g", metrics: [], standardStats: stats, games: []
        )
    }
}
