import XCTest
@testable import Hardwood_StatScout

/// The coverage notes exist so a gap in an old season reads as a limit of the
/// public record rather than as a broken app. These tests pin the boundaries to
/// the same years the pipeline uses (`handoff/NBA_CONTRACT.md`).
final class MetricCoverageTests: XCTestCase {
    func testRecentSeasonHasNoCoverageCaveat() {
        XCTAssertNil(MetricCoverage.note(for: 2026))
        XCTAssertNil(MetricCoverage.note(for: 2026, phase: .playoffs))
        XCTAssertNil(MetricCoverage.note(for: 2026, category: .impact))
    }

    func testShotZonesStartIn2004() {
        XCTAssertNotNil(MetricCoverage.note(for: 2003, category: .shooting))
        XCTAssertNil(MetricCoverage.note(for: 2004, category: .shooting))
        XCTAssertTrue(MetricCoverage.note(for: 2003, category: .shooting)?.contains("2003-04") == true)
    }

    func testPlusMinusStartsIn2009() {
        let note = MetricCoverage.note(for: 2008, category: .impact)
        XCTAssertTrue(note?.contains("2008-09") == true, note ?? "nil")
        XCTAssertFalse(MetricCoverage.isTracked("On-Court +/-", in: 2008))
        XCTAssertTrue(MetricCoverage.isTracked("On-Court +/-", in: 2009))
        XCTAssertFalse(MetricCoverage.isTracked("+/-", in: 2008))
    }

    func testOnOffFollowsThePerSeasonAndPhaseTable() {
        // Regular season: 2013-14, 2014-15, then 2020-21 onward.
        for season in [2014, 2015] + Array(2021...2027) {
            XCTAssertTrue(MetricCoverage.hasOnOff(season: season, phase: .regular), "REG \(season)")
        }
        for season in [2009, 2010, 2011, 2012, 2013, 2016, 2017, 2018, 2019, 2020] {
            XCTAssertFalse(MetricCoverage.hasOnOff(season: season, phase: .regular), "REG \(season)")
        }
        // Postseason: 2009, 2010, 2012-2015, then 2021 onward.
        for season in [2009, 2010, 2012, 2013, 2014, 2015] + Array(2021...2026) {
            XCTAssertTrue(MetricCoverage.hasOnOff(season: season, phase: .playoffs), "POST \(season)")
        }
        for season in [2011, 2016, 2017, 2018, 2019, 2020] {
            XCTAssertFalse(MetricCoverage.hasOnOff(season: season, phase: .playoffs), "POST \(season)")
        }
        // Career On-Off is never published.
        XCTAssertFalse(MetricCoverage.hasOnOff(season: StatScoutSeason.allTime))
    }

    func testImpactNoteNamesAMissingOnOff() {
        XCTAssertNotNil(MetricCoverage.note(for: 2019, category: .impact))
        XCTAssertNil(MetricCoverage.note(for: 2021, category: .impact))
        // 2011 has it for neither phase's bar except where the table says so.
        XCTAssertNotNil(MetricCoverage.note(for: 2011, category: .impact, phase: .playoffs))
        XCTAssertNotNil(MetricCoverage.note(for: 2011, category: .impact, phase: .regular))
        XCTAssertNil(MetricCoverage.note(for: 2012, category: .impact, phase: .playoffs))
    }

    func testEarliestSeasonsCarryTheOldestAndMostSweepingLimit() {
        XCTAssertTrue(MetricCoverage.note(for: 2003)?.contains("2003-04") == true)
        XCTAssertTrue(MetricCoverage.note(for: 2006)?.contains("2008-09") == true)
    }

    func testAllTimeExplainsItSpansEras() {
        let note = MetricCoverage.note(for: StatScoutSeason.allTime)
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("Career") == true)
        XCTAssertTrue(note?.contains("On-Off is not published") == true || note?.contains("not published") == true)
    }

    // MARK: - pendingNote

    func testPendingNotesNameTheFeedThatIsBehind() {
        XCTAssertEqual(
            MetricCoverage.pendingNote(category: .shooting, shotsStatus: "pending", playByPlayStatus: "ready"),
            "Shot-zone numbers for the latest games are still arriving."
        )
        XCTAssertEqual(
            MetricCoverage.pendingNote(category: .impact, shotsStatus: "ready", playByPlayStatus: "pending"),
            "On/off numbers for the latest games are still arriving."
        )
        XCTAssertNil(MetricCoverage.pendingNote(category: .shooting, shotsStatus: "ready", playByPlayStatus: "pending"))
        XCTAssertNil(MetricCoverage.pendingNote(category: .scoring, shotsStatus: "pending", playByPlayStatus: "pending"))
        XCTAssertNil(MetricCoverage.pendingNote(category: nil, shotsStatus: "ready", playByPlayStatus: "not_applicable"))
        // The whole-board form says both when both are behind.
        let both = MetricCoverage.pendingNote(category: nil, shotsStatus: "pending", playByPlayStatus: "degraded")
        XCTAssertTrue(both?.contains("Shot-zone") == true && both?.contains("On/off") == true)
    }

    // MARK: - isTracked

    func testIsTrackedMatchesSourceStartYears() {
        XCTAssertFalse(MetricCoverage.isTracked("Rim FG%", in: 2003))
        XCTAssertTrue(MetricCoverage.isTracked("Rim FG%", in: 2004))
        XCTAssertFalse(MetricCoverage.isTracked("Corner 3%", in: 2003))
        XCTAssertTrue(MetricCoverage.isTracked("Assisted FG%", in: 2004))
        XCTAssertFalse(MetricCoverage.isTracked("On-Off", in: 2020))
        XCTAssertTrue(MetricCoverage.isTracked("On-Off", in: 2021))
    }

    /// Box-score metrics reach every bundled season, and the career rollup has
    /// everything but On-Off.
    func testUnboundedMetricsAreAlwaysTracked() {
        XCTAssertTrue(MetricCoverage.isTracked("TS%", in: StatScoutSeason.earliest))
        XCTAssertTrue(MetricCoverage.isTracked("PPG", in: StatScoutSeason.earliest))
        XCTAssertTrue(MetricCoverage.isTracked("Rim FG%", in: StatScoutSeason.allTime))
        XCTAssertFalse(MetricCoverage.isTracked("On-Off", in: StatScoutSeason.allTime))
    }
}
