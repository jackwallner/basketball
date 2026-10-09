import XCTest
@testable import Hardwood_StatScout

@MainActor
final class StatDirectionTests: XCTestCase {
    private func player(
        _ id: Int,
        _ name: String,
        value: String,
        percentile: Int,
        label: String = "TS%",
        category: MetricCategory = .scoring,
        type: String = "g"
    ) -> Player {
        Player(
            playerId: id,
            name: name,
            team: "BOS",
            position: type.uppercased(),
            handedness: "",
            updatedAt: Date(),
            season: 2026,
            playerType: type,
            metrics: [
                Metric(
                    id: "m\(id)",
                    label: label,
                    value: value,
                    percentile: percentile,
                    category: category
                )
            ],
            standardStats: [],
            games: []
        )
    }

    func testBasketballLowerIsBetterMetrics() {
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "TOV%", category: .playmaking))
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "TOV/G", category: .playmaking))
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "Fouls/100", category: .defense))
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "TS%", category: .scoring))
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "BLK%", category: .defense))
        // Assisted FG% is descriptive, ranked higher-is-better like the rest.
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "Assisted FG%", category: .shooting))
    }

    func testLowerIsBetterBoardsOpenBestFirst() {
        XCTAssertFalse(DashboardViewModel.defaultSortDescending(label: "TOV%", category: .playmaking))
        XCTAssertTrue(DashboardViewModel.defaultSortDescending(label: "TS%", category: .scoring))
    }

    func testBlankValuesRankByPercentileInsteadOfLast() {
        let players = [
            player(1, "Printable but poor", value: "48.0%", percentile: 5),
            player(2, "Blank but elite", value: "", percentile: 99),
            player(3, "Blank and poor", value: "", percentile: 2),
        ]
        let ranked = players.sorted(
            by: DashboardViewModel.metricComparator(label: "TS%", category: .scoring, descending: true)
        )
        XCTAssertEqual(ranked.map(\.name), ["Blank but elite", "Printable but poor", "Blank and poor"])
    }

    func testEqualPercentilesBreakTiesOnValue() {
        let players = [
            player(1, "Lower value", value: "58.2%", percentile: 80),
            player(2, "Higher value", value: "59.9%", percentile: 80),
        ]
        let ranked = players.sorted(
            by: DashboardViewModel.metricComparator(label: "TS%", category: .scoring, descending: true)
        )
        XCTAssertEqual(ranked.map(\.name), ["Higher value", "Lower value"])
    }

    /// The All board mixes cohorts, and a percentile only means something
    /// inside one, so there the raw number leads.
    func testAllBoardRanksByTheNumberNotTheCohortPercentile() {
        let players = [
            player(1, "Guard, high percentile", value: "9.0%", percentile: 95, label: "REB%", category: .rebounding, type: "g"),
            player(2, "Center, low percentile", value: "17.0%", percentile: 40, label: "REB%", category: .rebounding, type: "c"),
        ]
        let byPercentile = players.sorted(
            by: DashboardViewModel.metricComparator(label: "REB%", category: .rebounding, descending: true)
        )
        XCTAssertEqual(byPercentile.first?.name, "Guard, high percentile")
        let byValue = players.sorted(
            by: DashboardViewModel.metricComparator(label: "REB%", category: .rebounding, descending: true, acrossCohorts: true)
        )
        XCTAssertEqual(byValue.first?.name, "Center, low percentile")
    }

    func testMissingMetricSortsLastInBothDirections() {
        let hasMetric = player(1, "Has it", value: "58.0%", percentile: 50)
        let lacksMetric = player(2, "Lacks it", value: "31.0", percentile: 40, label: "Pts/100")
        for descending in [true, false] {
            let ranked = [lacksMetric, hasMetric].sorted(
                by: DashboardViewModel.metricComparator(label: "TS%", category: .scoring, descending: descending)
            )
            XCTAssertEqual(ranked.last?.name, "Lacks it")
        }
    }
}
