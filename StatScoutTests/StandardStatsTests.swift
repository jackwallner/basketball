import XCTest
@testable import Hardwood_StatScout

final class StandardStatsTests: XCTestCase {
    func testPositionCatalogLeadsWithWhatEachCohortIsReadOn() {
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .all), "PPG")
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .guard), "APG")
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .forward), "PPG")
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .center), "RPG")
        // Same fifteen stat lines for everyone, in the order the feed ships them
        // after the lead.
        for position in PlayerPositionGroup.allCases {
            XCTAssertEqual(
                Set(StandardStatCatalog.stats(for: position)),
                ["G", "GS", "MPG", "PPG", "RPG", "APG", "SPG", "BPG", "FG", "3P", "FT", "TOV", "PF", "+/-", "MIN"]
            )
        }
    }

    func testWalkingThePositionTabsRanksEachPositionByItsOwnDefault() {
        var stat = StandardStatCatalog.defaultStat(for: .all)
        var position = PlayerPositionGroup.all
        for next in [PlayerPositionGroup.guard, .forward, .center, .all] {
            stat = StandardStatCatalog.stat(keeping: stat, from: position, to: next)
            position = next
            XCTAssertEqual(stat, StandardStatCatalog.defaultStat(for: next))
        }
    }

    func testDeliberatelyChosenStatFollowsAcrossPositions() {
        XCTAssertEqual(StandardStatCatalog.stat(keeping: "BPG", from: .all, to: .center), "BPG")
        XCTAssertEqual(StandardStatCatalog.stat(keeping: "BPG", from: .center, to: .guard), "BPG")
        // A default is not a choice: it does not follow.
        XCTAssertEqual(StandardStatCatalog.stat(keeping: "APG", from: .guard, to: .center), "RPG")
    }

    func testTurnoversAndFoulsDefaultLowestFirst() {
        XCTAssertFalse(StandardStatCatalog.defaultDescending(for: "TOV", position: .guard))
        XCTAssertFalse(StandardStatCatalog.defaultDescending(for: "PF", position: .center))
        XCTAssertTrue(StandardStatCatalog.defaultDescending(for: "PPG", position: .all))
        XCTAssertTrue(StandardStatCatalog.defaultDescending(for: "+/-", position: .all))
    }

    func testMetricCategoryDecodesCaseInsensitively() throws {
        for rawValue in ["scoring", "SCORING", "Scoring"] {
            let json = """
            {"id":"m","label":"Pts/100","value":"31.2","percentile":88,"category":"\(rawValue)"}
            """.data(using: .utf8)!
            let metric = try JSONDecoder().decode(Metric.self, from: json)
            XCTAssertEqual(metric.category, .scoring)
        }
    }

    func testMadeAttemptedLinesRankByPercentage() {
        // 612/1,250 is 49.0%, and the comma has to survive the parse.
        XCTAssertEqual(StandardStatSemantics.numericValue(label: "FG", value: "612/1,250")!, 48.96, accuracy: 0.001)
        XCTAssertEqual(StandardStatSemantics.numericValue(label: "3P", value: "115/298")!, 38.59, accuracy: 0.01)
        XCTAssertEqual(StandardStatSemantics.numericValue(label: "FT", value: "540/614")!, 87.95, accuracy: 0.01)
        // A pair with no attempts has no percentage.
        XCTAssertNil(StandardStatSemantics.numericValue(label: "3P", value: "0/0"))
        // The other lines are plain numbers, signs and commas included.
        XCTAssertEqual(StandardStatSemantics.numericValue(label: "+/-", value: "+788")!, 788)
        XCTAssertEqual(StandardStatSemantics.numericValue(label: "MIN", value: "2,262")!, 2262)
    }

    func testStandardComparisonRespectsDirectionAndRates() {
        // More makes at a worse percentage loses.
        XCTAssertEqual(StandardStatSemantics.winner(label: "FG", left: "400/900", right: "300/600"), .right)
        // Fewer turnovers and fouls win.
        XCTAssertEqual(StandardStatSemantics.winner(label: "TOV", left: "120", right: "151"), .left)
        XCTAssertEqual(StandardStatSemantics.winner(label: "PF", left: "200", right: "139"), .right)
        XCTAssertNil(StandardStatSemantics.winner(label: "G", left: "60", right: "60"))
    }

    func testPairPercentilesRankPeersByPercentage() {
        // 8/11 is 72.7%; against 5/9 (55.6%) and 10/10 (100%) it is the middle.
        XCTAssertEqual(
            StandardStatSemantics.percentile(label: "FT", value: "8/11", peerValues: ["8/11", "5/9", "10/10"]),
            50
        )
        // 3P: 40.0% beats a 33.3% and a 25.0% shooter, whatever their makes.
        XCTAssertEqual(
            StandardStatSemantics.percentile(label: "3P", value: "100/250", peerValues: ["100/250", "150/450", "50/200"]),
            Int(((2.0 + 0.5) / 3.0 * 100).rounded())
        )
    }

    func testEveryExistingStandardStatGetsAPercentile() {
        XCTAssertEqual(StandardStatSemantics.percentile(label: "G", value: "1", peerValues: []), 50)
    }

    func testPercentileRanksAgainstWhicheverPeersHaveTheStat() {
        XCTAssertEqual(StandardStatSemantics.percentile(label: "PPG", value: "24.0", peerValues: ["24.0", "9.0"]), 75)
        XCTAssertEqual(StandardStatSemantics.percentile(label: "PPG", value: "24.0", peerValues: ["24.0"]), 50)
        // Direction still applies with a thin pool: fewer turnovers is better.
        XCTAssertGreaterThan(
            StandardStatSemantics.percentile(label: "TOV", value: "90", peerValues: ["90", "180"]),
            StandardStatSemantics.percentile(label: "TOV", value: "180", peerValues: ["90", "180"])
        )
    }

    func testPercentileIsNeverZeroForAnExistingValue() {
        // The floor the profile, the team card and the boards all rely on: a
        // stat that exists always lands on a drawable 1-100 bar.
        for value in ["0", "1", "250", "0.0"] {
            let pct = StandardStatSemantics.percentile(
                label: "PPG",
                value: value,
                peerValues: ["0", "1", "250", "999"]
            )
            XCTAssertGreaterThanOrEqual(pct, 1, "\(value) produced \(pct)")
            XCTAssertLessThanOrEqual(pct, 100, "\(value) produced \(pct)")
        }
    }

    func testLeagueCurveInterpolatesFromTwoPoints() {
        let curve = LeaguePercentileCurve(points: [(100, 20), (300, 80)])
        XCTAssertNotNil(curve)
        XCTAssertEqual(curve?.percentile(for: 200), 50)
        XCTAssertEqual(curve?.percentile(for: 50), 20)
        XCTAssertEqual(curve?.percentile(for: 400), 80)
        XCTAssertNil(LeaguePercentileCurve(points: [(100, 20)]))
    }
}
