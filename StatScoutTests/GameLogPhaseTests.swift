import XCTest
@testable import Hardwood_StatScout

/// Regular-season and playoff rows must never be read as one phase.
///
/// `player_game_logs` carries `season_type`, and the box score, the game log and
/// the Last game card all fetch one phase at a time. Playoff games are the
/// newest rows a season has, so a date-descending list that ignored the phase
/// would put June at the top of a Regular Season heading.
final class GameLogPhaseTests: XCTestCase {
    private func log(
        date: String,
        seasonType: String?,
        points: Double
    ) throws -> PlayerGameLog {
        var payload: [String: Any] = [
            "player_id": 7,
            "season": 2026,
            "game_date": date,
            "game_id": "401859967",
            "player_type": "g",
            "plays": 25,
            "touches": 34,
            "metrics": ["pts": points, "min": 34, "plus_minus": NSNull()],
        ]
        if let seasonType { payload["season_type"] = seasonType }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(PlayerGameLog.self, from: data)
    }

    func testSeasonPhaseIsDecodedFromSeasonType() throws {
        XCTAssertEqual(try log(date: "2026-04-12", seasonType: "REG", points: 20).seasonPhase, .regular)
        XCTAssertEqual(try log(date: "2026-06-13", seasonType: "POST", points: 30).seasonPhase, .playoffs)
    }

    /// A row with no phase is a regular-season row, so the fixtures that predate
    /// the column keep decoding.
    func testMissingSeasonTypeDefaultsToRegular() throws {
        XCTAssertEqual(try log(date: "2025-12-07", seasonType: nil, points: 25).seasonPhase, .regular)
    }

    func testNullMetricsDecodeAsAbsentNotZero() throws {
        let row = try log(date: "2026-04-12", seasonType: "REG", points: 20)
        XCTAssertEqual(row.metrics["pts"] ?? nil, 20)
        XCTAssertNil(row.metrics["plus_minus"] ?? nil)
        // The box score drops the null, so plus/minus shows "-" rather than 0.
        let line = GameBoxScore(logs: [row]).lines[0]
        XCTAssertEqual(line.plusMinusText, "-")
        XCTAssertEqual(line.minutes, 34)
    }

    func testBoxScoreOrdersStartersFirstThenMinutes() throws {
        func row(_ id: Int, minutes: Double, starter: Double) throws -> PlayerGameLog {
            let payload: [String: Any] = [
                "player_id": id, "season": 2026, "game_date": "2026-04-12", "season_type": "REG",
                "player_type": "g", "team": "BOS", "plays": 1, "touches": 1,
                "metrics": ["min": minutes, "starter": starter, "pts": 10],
            ]
            return try JSONDecoder().decode(
                PlayerGameLog.self,
                from: JSONSerialization.data(withJSONObject: payload)
            )
        }
        let box = GameBoxScore(logs: [
            try row(1, minutes: 12, starter: 0),
            try row(2, minutes: 30, starter: 1),
            try row(3, minutes: 22, starter: 0),
            try row(4, minutes: 0, starter: 0),
        ])
        XCTAssertEqual(box.rotation(for: "BOS").map(\.playerId), [2, 3, 1])
        XCTAssertEqual(box.totals(for: "BOS").points, 40)
    }
}
