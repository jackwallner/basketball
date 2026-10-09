import Foundation

/// A metric the Trends board can rank by.
///
/// Keyed to the rollup column rather than the season metric label, because
/// Trends reads `player_recent_form` directly and never touches the season
/// snapshot. The rollup columns are the season metric ids from the contract.
struct TrendMetric: Identifiable, Hashable, Sendable {
    let key: String
    let label: String
    /// Suffix appended to a value, e.g. "%". Empty for plain numbers.
    let unit: String
    /// Also drives the delta formatting on the row.
    let decimals: Int
    /// True where a falling number is the improvement: turnover rate, fouls.
    let lowerIsBetter: Bool
    /// Whether the value reads with an explicit sign (net ratings, plus/minus).
    var signed = false

    var id: String { key }

    func format(_ value: Double) -> String {
        var text: String
        if decimals == 0 {
            text = Int(value.rounded()).formatted(.number.grouping(.automatic))
        } else {
            text = String(format: "%.\(decimals)f", value)
        }
        if signed, value > 0 { text = "+" + text }
        return text + unit
    }

    /// The metric for a season label, with the formatting the rollup needs.
    private static func make(_ label: String) -> TrendMetric {
        TrendMetric(
            key: RecentMetricKey.key(for: label) ?? label,
            label: label,
            unit: RecentMetricKey.isPercent(label) ? "%" : "",
            decimals: RecentMetricKey.decimals(for: label),
            lowerIsBetter: RecentMetricKey.lowerIsBetter(label),
            signed: RecentMetricKey.isSigned(label)
        )
    }

    // MARK: - Advanced

    /// Every cohort reads the same advanced vocabulary, in the order its
    /// players are judged on: guards on creation, forwards on scoring
    /// efficiency, centers on rim work and the glass.
    static let guardAdvanced: [TrendMetric] = [
        "AST%", "Pts/100", "TS%", "USG%", "TOV%", "AST:TO", "STL%", "On-Off",
    ].map(make)

    static let forwardAdvanced: [TrendMetric] = [
        "Pts/100", "TS%", "USG%", "eFG%", "REB%", "STL%", "BLK%", "On-Off",
    ].map(make)

    static let centerAdvanced: [TrendMetric] = [
        "REB%", "Rim FG%", "BLK%", "TS%", "Pts/100", "USG%", "OREB%", "On-Off",
    ].map(make)

    // MARK: - Standard

    /// The traditional line. Per-game averages over the window answer a
    /// different question from the advanced rates: what he did, not how
    /// efficiently.
    static let standard: [TrendMetric] = [
        "PPG", "RPG", "APG", "SPG", "BPG", "FG%", "3P%", "FT%", "3PM", "TOV/G", "MPG", "+/-",
    ].map(make)

    static func advanced(for side: TrendSide) -> [TrendMetric] {
        switch side {
        case .guard: return guardAdvanced
        case .forward: return forwardAdvanced
        case .center: return centerAdvanced
        }
    }

    static func standard(for side: TrendSide) -> [TrendMetric] { standard }

    static func list(for side: TrendSide, mode: TrendStatMode) -> [TrendMetric] {
        mode == .advanced ? advanced(for: side) : standard(for: side)
    }
}

/// Which vocabulary the Trends board is ranking in: the advanced line or the
/// traditional one. The same split the Stats tab, the player page and the team
/// page all use, so a user who has picked "Standard" once knows what it means
/// everywhere.
enum TrendStatMode: String, CaseIterable, Identifiable, Sendable {
    case advanced
    case standard

    var id: String { rawValue }
    var label: String { self == .advanced ? "Advanced" : "Standard" }
}

/// Which position cohort the Trends board is ranking.
///
/// Mixing cohorts is not an option: the rollup ranks within a position group,
/// and a center's rebound rate is not a guard's.
enum TrendSide: String, CaseIterable, Identifiable, Sendable {
    case `guard` = "g"
    case forward = "f"
    case center = "c"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .guard: return "Guards"
        case .forward: return "Forwards"
        case .center: return "Centers"
        }
    }

    /// Compact label for the equal-width position tabs.
    var shortLabel: String { rawValue.uppercased() }

    /// Matches `player_recent_form.player_type`.
    var playerType: String { rawValue }

    /// The Stats-tab cohort this side corresponds to.
    var group: PlayerPositionGroup {
        switch self {
        case .guard: return .guard
        case .forward: return .forward
        case .center: return .center
        }
    }
}
