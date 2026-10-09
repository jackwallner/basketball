import XCTest
@testable import Hardwood_StatScout

/// Covers the roster-pooling rules the team comparison relies on. The important
/// property is that a rate is weighted by the volume it was measured over: an
/// unweighted mean lets a ten-minute cameo outrank a 2,000-minute season, which
/// is the failure mode these tests exist to prevent.
final class MetricAggregationTests: XCTestCase {
    private func player(
        id: Int,
        metrics: [Metric],
        standard: [StandardStat]
    ) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: "BOS", position: "G",
            handedness: "", updatedAt: Date(), season: 2026,
            metrics: metrics, standardStats: standard, games: []
        )
    }

    private func std(_ label: String, _ value: String) -> StandardStat {
        StandardStat(id: "std-\(label)", label: label, value: value)
    }

    // MARK: - Aggregation rules

    func testAdvancedRatesWeightByMinutes() {
        for (label, category) in [("TS%", MetricCategory.scoring), ("AST%", .playmaking), ("REB%", .rebounding),
                                  ("BLK%", .defense), ("On-Off", .impact), ("Rim FG%", .shooting), ("FG%", .scoring)] {
            XCTAssertEqual(
                BasketballMetricRegistry.aggregation(for: label, category: category),
                .weighted(.minutes),
                label
            )
        }
    }

    func testCountsAndPerGameLinesAddUp() {
        for (label, category) in [("PPG", MetricCategory.scoring), ("3PM", .scoring), ("APG", .playmaking),
                                  ("AST", .playmaking), ("RPG", .rebounding), ("BLK", .defense), ("+/-", .impact), ("GS", .impact)] {
            XCTAssertEqual(BasketballMetricRegistry.aggregation(for: label, category: category), .sum, label)
        }
    }

    func testMinutesPerGameWeightsByGames() {
        XCTAssertEqual(BasketballMetricRegistry.aggregation(for: "MPG", category: .impact), .weighted(.games))
    }

    func testEveryRegistryMetricHasAnAggregationRule() {
        for definition in BasketballMetricRegistry.definitions {
            switch BasketballMetricRegistry.aggregation(for: definition.label, category: definition.category) {
            case .sum, .weighted: break
            }
        }
    }

    // MARK: - Weight extraction

    func testMinuteWeightReadsTotalMinutesWithItsGrouping() {
        let p = player(id: 1, metrics: [], standard: [std("MIN", "2,262")])
        XCTAssertEqual(MetricWeight.minutes.value(for: p), 2262)
    }

    func testGameWeightReadsPlainColumn() {
        let p = player(id: 1, metrics: [], standard: [std("G", "68")])
        XCTAssertEqual(MetricWeight.games.value(for: p), 68)
    }

    /// A player with no volume must drop out of the weighted mean rather than
    /// enter it at weight 1 - that is what would let a cameo swing a team rate.
    func testMissingWeightIsNilNotZero() {
        let p = player(id: 1, metrics: [], standard: [std("PPG", "17.0")])
        XCTAssertNil(MetricWeight.minutes.value(for: p))
        XCTAssertNil(MetricWeight.games.value(for: p))
    }

    func testZeroVolumeIsTreatedAsMissing() {
        let p = player(id: 1, metrics: [], standard: [std("MIN", "0")])
        XCTAssertNil(MetricWeight.minutes.value(for: p))
    }

    // MARK: - Value formatting

    func testPercentFormatIsPreserved() {
        let format = MetricValueFormat.inferred(from: ["6.2%", "4.8%"])
        XCTAssertTrue(format.isPercent)
        XCTAssertEqual(format.decimals, 1)
        XCTAssertEqual(format.string(5.5), "5.5%")
    }

    func testSignedFormatKeepsLeadingPlus() {
        let format = MetricValueFormat.inferred(from: ["+2.3", "-1.1"])
        XCTAssertTrue(format.isSigned)
        XCTAssertEqual(format.string(1.4), "+1.4")
        XCTAssertEqual(format.string(-1.4), "-1.4")
    }

    func testGroupedIntegerFormat() {
        let format = MetricValueFormat.inferred(from: ["1,502", "1,004"])
        XCTAssertTrue(format.hasGrouping)
        XCTAssertEqual(format.decimals, 0)
        XCTAssertEqual(format.string(2918), "2,918")
    }

    /// Mixed precision in one column should render at the finer of the two, not
    /// silently truncate the aggregate.
    func testDecimalsTakeTheMaximumSeen() {
        let format = MetricValueFormat.inferred(from: ["0.1", "0.12"])
        XCTAssertEqual(format.decimals, 2)
        XCTAssertEqual(format.string(0.155), "0.15")
    }

    func testTwoDecimalRateFormat() {
        let format = MetricValueFormat.inferred(from: ["0.25", "0.18"])
        XCTAssertFalse(format.isPercent)
        XCTAssertEqual(format.string(0.2), "0.20")
    }

    // MARK: - Parsing

    func testNumericParsingHandlesFeedShapes() {
        XCTAssertEqual(metricNumericValue("1,502"), 1502)
        XCTAssertEqual(metricNumericValue("6.2%"), 6.2)
        XCTAssertEqual(metricNumericValue("+2.3"), 2.3)
        XCTAssertEqual(metricNumericValue("-1.4"), -1.4)
        XCTAssertEqual(metricNumericValue(".5"), 0.5)
        XCTAssertNil(metricNumericValue("-"))
    }
}
