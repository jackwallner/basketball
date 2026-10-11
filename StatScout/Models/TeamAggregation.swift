import Foundation

/// Rolls a roster up into one team number, and ranks that number against the
/// other teams.
///
/// A team has no percentile of its own in the feed, so the team cards build one:
/// pool every rostered player's metric by the registry's aggregation rule, do the
/// same for the other twenty-nine rosters, and rank the team among them. The
/// ruler is the league's thirty teams, not its several hundred players: a team's
/// 114 offensive rating means nothing against individual players' spread and
/// everything against the other teams'.
enum TeamAggregation {
    /// One season metric pooled across a roster by `BasketballMetricRegistry.aggregation`:
    /// counts add up, rates are weighted by the volume they were measured over.
    static func value(label: String, category: MetricCategory, roster: [Player]) -> Double? {
        guard let scale = teamScale(label) else { return nil }
        let rule = BasketballMetricRegistry.aggregation(for: label, category: category)
        let values = roster.compactMap { player -> (value: Double, weight: Double)? in
            guard let metric = player.metrics.first(where: {
                $0.label == label && $0.category == category
            }), let value = metricNumericValue(metric.value) else { return nil }

            switch rule {
            case .sum:
                return (value, 1)
            case .weighted(let weight):
                // No volume means no rate to trust: drop the player rather than
                // let an unweighted value slide in as if it were weight 1.
                guard let w = weight.value(for: player) else { return nil }
                return (value, w)
            }
        }
        guard !values.isEmpty else { return nil }

        switch rule {
        case .sum:
            return values.reduce(0) { $0 + $1.value }
        case .weighted:
            let totalWeight = values.reduce(0) { $0 + $1.weight }
            guard totalWeight > 0 else { return nil }
            return values.reduce(0) { $0 + $1.value * $1.weight } / totalWeight * scale
        }
    }

    /// What a minutes-weighted player rate is worth as a team number.
    ///
    /// A player's share of what happened while he was on the floor is a fifth of
    /// the team's: weighting his Pts/100 by minutes gives the team's points per
    /// 100 possessions over five (a 23.0 that should read 115), and the same
    /// holds for the rebound, steal, block, assist and foul shares and rates.
    /// Those are multiplied back up. Usage and minutes share average to the
    /// same 20% for every team, and On-Off to about zero, so they have no team
    /// figure (nil). Everything else (shooting, turnover rate, On-Court +/-,
    /// which weights up to the team's net rating) passes through.
    static func teamScale(_ label: String) -> Double? {
        if teamless.contains(label) { return nil }
        return fifths.contains(label) ? 5 : 1
    }

    private static let fifths: Set<String> = [
        "Pts/100", "AST/100", "Stocks/100", "Fouls/100",
        "OREB%", "DREB%", "REB%", "STL%", "BLK%",
    ]

    private static let teamless: Set<String> = [
        "USG%", "Min%", "AST%", "AST:USG", "On-Off", "MPG", "GS",
    ]

    /// A rolling-window metric pooled across a team's rows, weighted by the
    /// minutes each player played in the window. Nil when no row carries it.
    static func recentValue(key: String, rows: [RecentForm], label: String? = nil) -> Double? {
        let scale = label.map(teamScale) ?? 1
        guard let scale else { return nil }
        let pairs = rows.compactMap { row -> (value: Double, weight: Double)? in
            guard let value = row.metrics[key], row.touches > 0 else { return nil }
            return (value, Double(row.touches))
        }
        let totalWeight = pairs.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return pairs.reduce(0) { $0 + $1.value * $1.weight } / totalWeight * scale
    }

    /// Midpoint rank of `value` among `values`, 1 to 100, flipped when a lower
    /// number is the better one. A lone value is the middle of its one-team
    /// cohort, never an absent percentile.
    static func percentile(_ value: Double, among values: [Double], higherIsBetter: Bool = true) -> Int {
        var pool = values
        if pool.isEmpty { pool = [value] }
        let below = pool.reduce(0) { $0 + ($1 < value ? 1 : 0) }
        let equal = pool.reduce(0) { $0 + ($1 == value ? 1 : 0) }
        let raw = (Double(below) + Double(equal) / 2) / Double(pool.count) * 100
        let oriented = higherIsBetter ? raw : 100 - raw
        return max(1, min(100, Int(oriented.rounded())))
    }

    /// Players grouped by team code.
    static func rosters(from players: [Player]) -> [String: [Player]] {
        Dictionary(grouping: players) { normalizedTeamAbbreviation($0.team) }
    }

    /// Window rows grouped by team code.
    static func recentRosters(from rows: [RecentForm]) -> [String: [RecentForm]] {
        Dictionary(grouping: rows) { normalizedTeamAbbreviation($0.team ?? "") }
    }
}
