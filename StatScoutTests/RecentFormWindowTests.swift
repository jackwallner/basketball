import XCTest
@testable import Hardwood_StatScout

/// The rolling windows are 1, 2 and 4 calendar weeks, and say so the same way
/// on every screen.
final class RecentFormWindowTests: XCTestCase {
    func testWindowsAreOneTwoAndFourWeeks() {
        XCTAssertEqual(RecentWindow.allCases.map(\.rawValue), [1, 2, 4])
        XCTAssertEqual(TrendWindow.allCases, RecentWindow.allCases)
    }

    func testControlLabelsAreShortWeeks() {
        XCTAssertEqual(RecentWindow.allCases.map(\.segmentLabel), ["1 wk", "2 wk", "4 wk"])
    }

    func testProseNamesTheSpan() {
        XCTAssertEqual(RecentWindow.week.prose, "last week")
        XCTAssertEqual(RecentWindow.twoWeeks.prose, "last 2 weeks")
        XCTAssertEqual(RecentWindow.fourWeeks.prose, "last 4 weeks")
        XCTAssertEqual(RecentWindow.week.label, "Last week")
        XCTAssertEqual(RecentWindow.fourWeeks.label, "Last 4 weeks")
        XCTAssertEqual(RecentWindow.fourWeeks.days, 28)
    }

    func testRecentFormRowLabelsItsOwnWindow() throws {
        let json = """
        {"player_id":1966,"season":2026,"season_type":"REG","player_type":"f","as_of":"2026-04-12",
         "start_week":28,"end_week":28,"team":"LAL","games":3,"plays":66,"touches":81,"window_weeks":2,
         "metrics":{"ppg":24.0,"ts_pct":64.4},"prior_metrics":{"ppg":19.5,"ts_pct":59.3},
         "delta":{"ppg":4.5,"ts_pct":5.1}}
        """
        let form = try JSONDecoder.statScout.decode(RecentForm.self, from: Data(json.utf8))
        XCTAssertEqual(form.windowLabel, "2 wk")
        XCTAssertEqual(form.minutes, 81)
        XCTAssertEqual(form.delta["ppg"], 4.5)
        XCTAssertFalse(form.isSmallSample)
    }

    func testSmallSampleIsGamesAndMinutes() throws {
        func form(games: Int, minutes: Int) throws -> RecentForm {
            let json = """
            {"player_id":1,"season":2026,"player_type":"g","window_weeks":1,"games":\(games),
             "plays":10,"touches":\(minutes),"metrics":{},"prior_metrics":{},"delta":{}}
            """
            return try JSONDecoder.statScout.decode(RecentForm.self, from: Data(json.utf8))
        }
        XCTAssertTrue(try form(games: 1, minutes: 90).isSmallSample)
        XCTAssertTrue(try form(games: 3, minutes: 40).isSmallSample)
        XCTAssertFalse(try form(games: 2, minutes: 60).isSmallSample)
        XCTAssertFalse(try form(games: 1, minutes: 60).isSmallSample(minimumGames: 1))
    }

    /// The rollup keys are the season metric ids, so every registry metric maps.
    func testEveryRegistryMetricHasARollupKey() {
        for definition in BasketballMetricRegistry.definitions {
            XCTAssertNotNil(RecentMetricKey.key(for: definition.label), definition.label)
        }
        XCTAssertEqual(RecentMetricKey.key(for: "Pts/100"), "pts_per_100")
        XCTAssertEqual(RecentMetricKey.key(for: "On-Court +/-"), "on_net")
        XCTAssertEqual(RecentMetricKey.key(for: "Non-Corner 3%"), "nc3_fg")
        XCTAssertEqual(RecentMetricKey.key(for: "FT Rate"), "ftr")
    }

    func testFormattingFollowsTheMetricKind() {
        XCTAssertEqual(RecentMetricKey.format(61.24, label: "TS%"), "61.2%")
        XCTAssertEqual(RecentMetricKey.format(28.0, label: "Rim Freq"), "28.0%")
        XCTAssertEqual(RecentMetricKey.format(0.38, label: "FT Rate"), "0.38")
        XCTAssertEqual(RecentMetricKey.format(31.34, label: "On-Off"), "+31.3")
        XCTAssertEqual(RecentMetricKey.format(-7, label: "+/-"), "-7")
        XCTAssertEqual(RecentMetricKey.format(1_502, label: "3PM"), "1,502")
        XCTAssertTrue(RecentMetricKey.lowerIsBetter("TOV%"))
        XCTAssertFalse(RecentMetricKey.lowerIsBetter("TS%"))
    }

    func testTrendBoardsCoverAllThreeCohortsWithoutAnEmptyList() {
        for side in TrendSide.allCases {
            XCTAssertFalse(TrendMetric.advanced(for: side).isEmpty)
            XCTAssertFalse(TrendMetric.standard(for: side).isEmpty)
            XCTAssertEqual(side.playerType, side.rawValue)
        }
        XCTAssertEqual(TrendSide.allCases.map(\.shortLabel), ["G", "F", "C"])
        let turnovers = TrendMetric.advanced(for: .guard).first { $0.label == "TOV%" }
        XCTAssertEqual(turnovers?.lowerIsBetter, true)
        XCTAssertEqual(turnovers?.format(12.34), "12.3%")
    }
}
