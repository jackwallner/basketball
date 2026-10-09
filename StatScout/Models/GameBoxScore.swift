import Foundation

/// A basic box score rebuilt from one game's `player_game_logs` rows.
///
/// Every number is a sum of per-player counts hoopR publishes for the game.
/// Nothing here is a roster average or a percentile. Team totals only add
/// columns that do not double count: a made three is already inside field goals
/// made, so points are never rebuilt from the pieces.
struct GameBoxScore: Sendable {
    struct PlayerLine: Identifiable, Hashable, Sendable {
        let playerId: Int
        let team: String
        let playerType: String
        let metrics: [String: Double]

        var id: String { "\(playerId)-\(playerType)" }

        func value(_ key: String) -> Double { metrics[key] ?? 0 }
        func int(_ key: String) -> Int { Int(value(key).rounded()) }

        var minutes: Int { int("min") }
        var isStarter: Bool { value("starter") > 0 }
        /// A box score lists the players who got on the floor.
        var played: Bool { minutes > 0 }

        /// "7/15" from the made and attempted columns.
        func made(_ made: String, of attempts: String) -> String {
            "\(int(made))/\(int(attempts))"
        }

        /// Signed plus/minus, or "-" before ESPN carries one (nil in the feed).
        var plusMinusText: String {
            guard let value = metrics["plus_minus"] else { return "-" }
            let rounded = Int(value.rounded())
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        }
    }

    struct TeamTotals: Equatable, Sendable {
        var points = 0.0
        var fieldGoalsMade = 0.0
        var fieldGoalsAttempted = 0.0
        var threesMade = 0.0
        var threesAttempted = 0.0
        var freeThrowsMade = 0.0
        var freeThrowsAttempted = 0.0
        var offensiveRebounds = 0.0
        var rebounds = 0.0
        var assists = 0.0
        var steals = 0.0
        var blocks = 0.0
        var turnovers = 0.0
        var fouls = 0.0

        var fieldGoalPercentage: Double? { fieldGoalsAttempted > 0 ? fieldGoalsMade / fieldGoalsAttempted * 100 : nil }
        var threePointPercentage: Double? { threesAttempted > 0 ? threesMade / threesAttempted * 100 : nil }
        var freeThrowPercentage: Double? { freeThrowsAttempted > 0 ? freeThrowsMade / freeThrowsAttempted * 100 : nil }
        /// Effective field goal percentage: a three counts for a point and a half.
        var effectiveFieldGoalPercentage: Double? {
            fieldGoalsAttempted > 0 ? (fieldGoalsMade + 0.5 * threesMade) / fieldGoalsAttempted * 100 : nil
        }
    }

    let lines: [PlayerLine]

    init(logs: [PlayerGameLog]) {
        lines = logs.map { log in
            PlayerLine(
                playerId: log.playerId,
                team: normalizedTeamAbbreviation(log.team ?? ""),
                playerType: log.playerType,
                metrics: log.metrics.compactMapValues { $0 }
            )
        }
    }

    var isEmpty: Bool { lines.isEmpty }

    func lines(for team: String) -> [PlayerLine] {
        let abbr = normalizedTeamAbbreviation(team)
        return lines.filter { $0.team == abbr }
    }

    /// The rotation in box-score order: starters first, then everyone else by
    /// minutes. Players who never got on the floor are left off.
    func rotation(for team: String) -> [PlayerLine] {
        lines(for: team)
            .filter(\.played)
            .sorted {
                if $0.isStarter != $1.isStarter { return $0.isStarter }
                if $0.minutes != $1.minutes { return $0.minutes > $1.minutes }
                return $0.value("pts") > $1.value("pts")
            }
    }

    func totals(for team: String) -> TeamTotals {
        var totals = TeamTotals()
        for line in lines(for: team) {
            totals.points += line.value("pts")
            totals.fieldGoalsMade += line.value("fgm")
            totals.fieldGoalsAttempted += line.value("fga")
            totals.threesMade += line.value("fg3m")
            totals.threesAttempted += line.value("fg3a")
            totals.freeThrowsMade += line.value("ftm")
            totals.freeThrowsAttempted += line.value("fta")
            totals.offensiveRebounds += line.value("oreb")
            totals.rebounds += line.value("reb")
            totals.assists += line.value("ast")
            totals.steals += line.value("stl")
            totals.blocks += line.value("blk")
            totals.turnovers += line.value("tov")
            totals.fouls += line.value("pf")
        }
        return totals
    }

    /// Game leaders across both teams: the top scorer, rebounder and
    /// assist man, with the line that earned the title.
    struct Leader: Identifiable, Hashable, Sendable {
        let title: String
        let line: PlayerLine
        let summary: String
        var id: String { title }
    }

    var leaders: [Leader] {
        var result: [Leader] = []
        if let top = best(by: "pts") {
            result.append(Leader(title: "Points", line: top, summary: Self.scoringSummary(top)))
        }
        if let top = best(by: "reb") {
            result.append(Leader(title: "Rebounds", line: top, summary: Self.reboundingSummary(top)))
        }
        if let top = best(by: "ast") {
            result.append(Leader(title: "Assists", line: top, summary: Self.assistSummary(top)))
        }
        return result
    }

    /// Highest of one column, with points then minutes breaking a tie so the
    /// same game always names the same player.
    private func best(by key: String) -> PlayerLine? {
        lines.filter { $0.value(key) > 0 }.max {
            ($0.value(key), $0.value("pts"), Double($0.minutes))
                < ($1.value(key), $1.value("pts"), Double($1.minutes))
        }
    }

    static func scoringSummary(_ line: PlayerLine) -> String {
        var parts = ["\(line.int("pts")) pts", "\(line.made("fgm", of: "fga")) FG"]
        if line.int("fg3a") > 0 { parts.append("\(line.made("fg3m", of: "fg3a")) 3P") }
        return parts.joined(separator: ", ")
    }

    static func reboundingSummary(_ line: PlayerLine) -> String {
        var parts = ["\(line.int("reb")) reb"]
        if line.int("oreb") > 0 { parts.append("\(line.int("oreb")) off") }
        parts.append("\(line.int("pts")) pts")
        return parts.joined(separator: ", ")
    }

    static func assistSummary(_ line: PlayerLine) -> String {
        "\(line.int("ast")) ast, \(line.int("tov")) tov, \(line.int("pts")) pts"
    }

    /// A player's one-line game summary: "24 pts, 8 reb, 6 ast".
    static func summary(_ line: PlayerLine) -> String {
        var parts = ["\(line.int("pts")) pts"]
        if line.int("reb") > 0 { parts.append("\(line.int("reb")) reb") }
        if line.int("ast") > 0 { parts.append("\(line.int("ast")) ast") }
        if line.int("stl") >= 3 { parts.append("\(line.int("stl")) stl") }
        if line.int("blk") >= 3 { parts.append("\(line.int("blk")) blk") }
        return parts.joined(separator: ", ")
    }
}
