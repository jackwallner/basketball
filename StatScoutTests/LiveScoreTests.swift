import XCTest
@testable import Hardwood_StatScout

final class LiveScoreTests: XCTestCase {
    private func payload(_ events: String) -> Data {
        Data("{\"events\":[\(events)]}".utf8)
    }

    private func event(id: String, state: String, detail: String, period: Int, home: String, away: String,
                       clock: String = "0.0", completed: Bool? = nil) -> String {
        let done = completed ?? (state == "post")
        return """
        {"id":"\(id)","status":{"period":\(period),"displayClock":"\(clock)","type":{"state":"\(state)","completed":\(done),"shortDetail":"\(detail)"}},
         "competitions":[{"competitors":[
           {"homeAway":"home","score":"\(home)"},{"homeAway":"away","score":"\(away)"}]}]}
        """
    }

    func testParsesGamesUnderwayAndFinalsButNotScheduled() {
        let data = payload([
            event(id: "1", state: "in", detail: "4:12 - 3rd", period: 3, home: "71", away: "68", clock: "4:12"),
            event(id: "2", state: "post", detail: "Final/OT", period: 5, home: "110", away: "112"),
            event(id: "3", state: "pre", detail: "10/20 - 7:00 PM EDT", period: 0, home: "0", away: "0"),
            event(id: "4", state: "post", detail: "Postponed", period: 0, home: "0", away: "0", completed: false),
        ].joined(separator: ","))
        let scores = Dictionary(uniqueKeysWithValues: LiveScore.parse(data).map { ($0.gameId, $0) })

        XCTAssertEqual(scores.count, 2)
        XCTAssertEqual(scores["1"]?.homeScore, 71)
        XCTAssertEqual(scores["1"]?.awayScore, 68)
        XCTAssertTrue(scores["1"]?.isUnderway == true)
        XCTAssertEqual(scores["1"]?.clockLabel, "Q3 4:12")
        XCTAssertTrue(scores["2"]?.isFinal == true)
        XCTAssertEqual(scores["2"]?.clockLabel, "Final/OT")
        XCTAssertNil(scores["3"])
        XCTAssertNil(scores["4"], "a postponed game is not a 0-0 final")
    }

    func testClockLabelsForBreaks() {
        let half = LiveScore(gameId: "1", awayScore: 50, homeScore: 48, state: "in", detail: "Halftime", period: 2, clock: "0.0")
        let endThird = LiveScore(gameId: "1", awayScore: 70, homeScore: 72, state: "in", detail: "End of 3rd", period: 3, clock: "0.0")
        let overtime = LiveScore(gameId: "1", awayScore: 101, homeScore: 101, state: "in", detail: "1:05 - OT", period: 5, clock: "1:05")
        let lastMinute = LiveScore(gameId: "1", awayScore: 90, homeScore: 88, state: "in", detail: "45.2 - 4th", period: 4, clock: "45.2")
        let doubleOT = LiveScore(gameId: "1", awayScore: 130, homeScore: 128, state: "post", detail: "Final/2OT", period: 6)
        XCTAssertEqual(half.clockLabel, "Half")
        XCTAssertEqual(endThird.clockLabel, "End Q3")
        XCTAssertEqual(overtime.clockLabel, "OT 1:05")
        XCTAssertEqual(lastMinute.clockLabel, "Q4 45.2")
        XCTAssertEqual(doubleOT.clockLabel, "Final/2OT")
    }

    func testBadPayloadIsEmpty() {
        XCTAssertTrue(LiveScore.parse(Data("nope".utf8)).isEmpty)
    }

    func testDateKeyUsesTheEasternDay() throws {
        let date = try XCTUnwrap(DataFreshness.parseDate("2026-10-20"))
        XCTAssertEqual(LiveScoreClient.dateKey(date), "20261020")
    }
}
