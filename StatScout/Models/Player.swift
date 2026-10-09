import Foundation

struct Player: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(playerId)-\(season ?? 0)-\(seasonPhase.rawValue)" }
    let playerId: Int
    let name: String
    let team: String
    let position: String
    let handedness: String
    let updatedAt: Date
    let season: Int?
    let seasonPhase: SeasonPhase
    let playerType: String?
    let source: String?
    let metrics: [Metric]
    let standardStats: [StandardStat]?
    let games: [GameTrend]

    enum CodingKeys: String, CodingKey {
        case playerId = "id"
        case name
        case team
        case position
        case handedness
        case updatedAt = "updated_at"
        case season
        case seasonPhase = "season_type"
        case playerType = "player_type"
        case source
        case metrics
        case standardStats = "standard_stats"
        case games
    }

    init(
        playerId: Int,
        name: String,
        team: String,
        position: String,
        handedness: String,
        updatedAt: Date,
        season: Int? = nil,
        seasonPhase: SeasonPhase = .regular,
        playerType: String? = nil,
        source: String? = nil,
        metrics: [Metric],
        standardStats: [StandardStat]?,
        games: [GameTrend]
    ) {
        self.playerId = playerId
        self.name = name
        self.team = team
        self.position = position
        self.handedness = handedness
        self.updatedAt = updatedAt
        self.season = season
        self.seasonPhase = seasonPhase
        self.playerType = playerType
        self.source = source
        self.metrics = metrics
        self.standardStats = standardStats
        self.games = games
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try container.decode(Int.self, forKey: .playerId)
        name = try container.decode(String.self, forKey: .name)
        team = try container.decode(String.self, forKey: .team)
        position = try container.decode(String.self, forKey: .position)
        handedness = try container.decode(String.self, forKey: .handedness)
        // No headshot field: the app never renders player photos (same as the
        // baseball build), and the league's headshot URLs aren't ours to
        // redistribute. It was also a live decoding hazard - it used to be
        // decoded as `URL`, which only round-trips from a plain string on
        // JSONDecoder. PropertyListDecoder expects URL's keyed
        // {relative, base} form, so it threw typeMismatch on the first row and
        // took the whole `[Player]` array down with it, leaving the bundled
        // current *and* historical datasets unreadable ("Data Error - No
        // players found"). The feed still sends `image_url`; unknown keys are
        // simply ignored.
        updatedAt = try Self.decodeTimestamp(container, forKey: .updatedAt)
        season = try container.decodeIfPresent(Int.self, forKey: .season)
        seasonPhase = try container.decodeIfPresent(SeasonPhase.self, forKey: .seasonPhase) ?? .regular
        playerType = try container.decodeIfPresent(String.self, forKey: .playerType)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        metrics = try container.decode([Metric].self, forKey: .metrics)
        standardStats = try container.decodeIfPresent([StandardStat].self, forKey: .standardStats)
        games = try container.decodeIfPresent([GameTrend].self, forKey: .games) ?? []
    }

    /// A native date, or the ISO string the exporter wrote when it could not
    /// make one. The bundled archive carries 832 rows (all of 2007-08 and
    /// 2010-11) whose `updated_at` is the raw string, and one such row used to
    /// fail the plist decode of the whole array and with it every past season.
    private static func decodeTimestamp(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date {
        if let date = try? container.decode(Date.self, forKey: key) { return date }
        let raw = try container.decode(String.self, forKey: key)
        guard let parsed = DataFreshness.parseDate(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid updated_at: \(raw)"
            )
        }
        return parsed
    }

    /// Explicit mirror of `init(from:)` so the on-disk plist cache is written
    /// in exactly the shape the decoder above reads back. Leaving this
    /// synthesized is what let the encode and decode sides drift apart in the
    /// first place.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(playerId, forKey: .playerId)
        try container.encode(name, forKey: .name)
        try container.encode(team, forKey: .team)
        try container.encode(position, forKey: .position)
        try container.encode(handedness, forKey: .handedness)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(season, forKey: .season)
        try container.encode(seasonPhase, forKey: .seasonPhase)
        try container.encodeIfPresent(playerType, forKey: .playerType)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encode(metrics, forKey: .metrics)
        try container.encodeIfPresent(standardStats, forKey: .standardStats)
        try container.encode(games, forKey: .games)
    }

    /// Metrics that carry a real rank. See `Metric.isUnranked`.
    var rankedMetrics: [Metric] { metrics.filter { !$0.isUnranked } }

    var overallPercentile: Int {
        let metrics = rankedMetrics
        guard !metrics.isEmpty else { return 0 }
        // A rim protector's scoring bars shouldn't drag down his defense: the
        // headline number is the best category average, not the mean of
        // unrelated skills.
        let categories = Set(metrics.map(\.category))
        if categories.count > 1 {
            let categoryAverages = Dictionary(grouping: metrics) { $0.category }
                .values
                .map { group in
                    Double(group.map(\.percentile).reduce(0, +)) / Double(group.count)
                }
            return Int(round(categoryAverages.max() ?? 0))
        }
        let total = metrics.map(\.percentile).reduce(0, +)
        return Int(round(Double(total) / Double(metrics.count)))
    }

    var headlineMetric: Metric? {
        rankedMetrics.sorted { $0.percentile > $1.percentile }.first
    }

    var latestGame: GameTrend? {
        games.sorted { $0.date > $1.date }.first
    }

    var latestPercentileDelta: Int {
        latestGame?.percentileDelta ?? 0
    }

    var weeklyDelta: Int {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return games.filter { $0.date >= cutoff }
            .map(\.percentileDelta)
            .reduce(0, +)
    }

    var shareSummary: String {
        let headline = headlineMetric.map { metric in
            let valueText = metric.value.isEmpty ? "\(metric.percentile.ordinal) percentile" : "\(metric.value), \(metric.percentile.ordinal) percentile"
            return "\(metric.label) \(valueText)"
        } ?? "\(overallPercentile.ordinal) overall percentile"
        return "\(name) · \(team) \(displayPosition)\nOverall: \(overallPercentile.ordinal) percentile\nTop stat: \(headline)\nHardwood StatScout"
    }

    func percentile(for category: MetricCategory) -> Int? {
        let categoryMetrics = rankedMetrics.filter { $0.category == category }
        guard !categoryMetrics.isEmpty else { return nil }
        let total = categoryMetrics.map(\.percentile).reduce(0, +)
        return Int(round(Double(total) / Double(categoryMetrics.count)))
    }
}

enum SeasonPhase: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case regular = "REG"
    case playoffs = "POST"

    var id: String { rawValue }

    /// One name, everywhere.
    ///
    /// There used to be a short `label` ("Regular") for controls and a
    /// `fullLabel` ("Regular Season") for prose, and the short one was wrong in
    /// every place it appeared: on its own, "Regular" is an adjective with no
    /// noun, and the nav pill read "2025 · Regular" as though it were describing
    /// the year. The saving was about forty points of width on one capsule,
    /// which the bar has.
    var label: String {
        switch self {
        case .regular: return "Regular Season"
        case .playoffs: return "Playoffs"
        }
    }
}

struct Metric: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let value: String
    let percentile: Int
    let category: MetricCategory
    /// Whether the player clears the (prorated) qualification bar for this
    /// metric. Only the live season ships it, because only the live season ships
    /// players under the bar; nil means the row exists because it qualified.
    var qualified: Bool? = nil
    /// Set false by screens that build a metric from a counting stat outside
    /// the registry (the profile's standard line), so a zero there is unranked
    /// by the same rule as below.
    var rankable: Bool? = nil

    /// A traditional counting stat at zero: 0 blocks, 0 offensive rebounds, 0 3PM.
    ///
    /// The feed ranks these with the midpoint of the tie, so a week into the
    /// season every guard without a block was painted 47th percentile. A player
    /// who has done none of a thing is not a 47th-percentile player at it, and
    /// when most of the league is tied at zero there is no honest rank at all.
    /// The value still shows; the bar, the number and the player's overall
    /// average leave it out.
    var isUnranked: Bool {
        if rankable == false { return true }
        guard let definition = BasketballMetricRegistry.definition(for: label, category: category),
              definition.kind == .traditional,
              BasketballMetricRegistry.aggregation(for: label, category: category) == .sum,
              let number = metricNumericValue(value)
        else { return false }
        return number == 0
    }

    /// Below the prorated playing-time bar for this metric.
    var isSmallSample: Bool { qualified == false }
}

struct StandardStat: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let value: String
}

/// Shared meaning for the compact values in `standard_stats`.
///
/// The feed stores field goals, threes and free throws as display-ready
/// made/attempted pairs. Treating the leading component as the numeric value
/// made `612/1,250` rank as 612 instead of a 49.0% shooter in both profile and
/// comparison UI.
enum StandardStatSemantics {
    enum Winner: Equatable {
        case left
        case right
    }

    static func numericValue(label: String, value: String) -> Double? {
        switch label.uppercased() {
        case "FG", "3P", "FT":
            let parts = value.split(separator: "/", maxSplits: 1)
            guard parts.count == 2,
                  let numerator = metricNumericValue(String(parts[0])),
                  let denominator = metricNumericValue(String(parts[1])),
                  denominator > 0 else { return nil }
            return numerator / denominator * 100
        default:
            return metricNumericValue(value)
        }
    }

    /// Turnovers and personal fouls are the two counting lines where less is
    /// better.
    static func higherIsBetter(label: String) -> Bool {
        let key = label.uppercased()
        return key != "TOV" && key != "PF"
    }

    /// Midpoint rank against every peer carrying the same stat. A single
    /// available value is the middle of its one-player cohort, never an absent
    /// percentile. The caller supplies one season and position group.
    static func percentile(label: String, value: String, peerValues: [String]) -> Int {
        guard let currentValue = numericValue(label: label, value: value) else {
            return 50
        }
        var values = peerValues.compactMap {
            numericValue(label: label, value: $0)
        }
        if values.isEmpty { values = [currentValue] }

        let below = values.reduce(0) { $0 + ($1 < currentValue ? 1 : 0) }
        let equal = values.reduce(0) { $0 + ($1 == currentValue ? 1 : 0) }
        let raw = (Double(below) + Double(equal) / 2) / Double(values.count) * 100
        let oriented = higherIsBetter(label: label) ? raw : 100 - raw
        return max(1, min(100, Int(oriented.rounded())))
    }

    static func winner(label: String, left: String?, right: String?) -> Winner? {
        guard let left,
              let right,
              let leftValue = numericValue(label: label, value: left),
              let rightValue = numericValue(label: label, value: right),
              leftValue != rightValue else { return nil }
        let leftWins = higherIsBetter(label: label)
            ? leftValue > rightValue
            : leftValue < rightValue
        return leftWins ? .left : .right
    }
}

/// Pulls the leading number out of a formatted feed value: `"6.2%"` -> 6.2,
/// `"1,502"` -> 1502, `"+2.3"` -> 2.3.
///
/// Lives here, free of any actor, because it is pure string arithmetic that both
/// the view model (main actor) and the model layer need. It used to exist only as
/// `DashboardViewModel.rawNumeric`, which inherited the view model's
/// `@MainActor` isolation and so couldn't be called from a plain model type at
/// all. That method now forwards here, so there is still one implementation.
func metricNumericValue(_ value: String) -> Double? {
    var s = value.trimmingCharacters(in: .whitespaces)
    // Strip thousands separators - season totals ship as "1,502".
    s = s.replacingOccurrences(of: ",", with: "")
    if s.hasPrefix(".") { s = "0" + s }
    if s.hasPrefix("-.") { s = "-0" + s.dropFirst() }
    let scanner = Scanner(string: s)
    scanner.charactersToBeSkipped = nil
    return scanner.scanDouble()
}

/// The display shape of a metric value, read back off the feed's own strings.
///
/// The pipeline formats every metric server-side (`"6.2%"`, `"+2.3"`, `"1,502"`,
/// `"0.25"`) and the app only ever passes those through. An aggregate has no
/// such string to pass through, so it has to be rendered here - and rather than
/// keep a second copy of the backend's format table in Swift, where the two
/// would quietly drift the first time a metric changed precision, the format is
/// inferred from the very values being aggregated. A column of `"6.2%"` renders
/// its total as `"6.2%"` by construction.
struct MetricValueFormat: Hashable, Sendable {
    var decimals = 0
    var isPercent = false
    var isSigned = false
    var hasGrouping = false

    static func inferred(from samples: [String]) -> MetricValueFormat {
        var format = MetricValueFormat()
        for sample in samples {
            let trimmed = sample.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("%") { format.isPercent = true }
            if trimmed.hasPrefix("+") { format.isSigned = true }
            if trimmed.contains(",") { format.hasGrouping = true }
            // Max rather than first: a column holding both "0.1" and "0.12"
            // should render its aggregate at the finer precision, not truncate.
            let digits = trimmed
                .drop { $0 != "." }
                .dropFirst()
                .prefix { $0.isNumber }
                .count
            format.decimals = max(format.decimals, digits)
        }
        return format
    }

    func string(_ value: Double) -> String {
        var text: String
        if decimals == 0, hasGrouping {
            text = Int(value.rounded()).formatted(.number.grouping(.automatic))
        } else if decimals == 0 {
            text = String(Int(value.rounded()))
        } else {
            text = String(format: "%.\(decimals)f", value)
        }
        if isSigned, value > 0 { text = "+" + text }
        if isPercent { text += "%" }
        return text
    }
}

enum MetricDirection: String, Codable, Hashable, Sendable {
    case up
    case flat
    case down
}

enum MetricCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case scoring = "Scoring"
    case shooting = "Shooting"
    case playmaking = "Playmaking"
    case rebounding = "Rebounding"
    case defense = "Defense"
    case impact = "Impact"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let category = Self.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(value) == .orderedSame
        }) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown metric category: \(value)"
            )
        }
        self = category
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Registry-driven display order. Advanced metrics lead within each category,
    /// followed by traditional production metrics.
    var metricPriorityOrder: [String] {
        BasketballMetricRegistry.definitions
            .filter { $0.category == self }
            .sorted { $0.priority < $1.priority }
            .map(\.label)
    }

    /// Returns a comparator for sorting metric labels within this category.
    func sortMetrics(_ a: String, _ b: String) -> Bool {
        let order = metricPriorityOrder
        let ia = order.firstIndex(of: a) ?? order.count
        let ib = order.firstIndex(of: b) ?? order.count
        return ia < ib
    }
}

struct TeamRoute: Hashable {
    let abbr: String
    let players: [Player]
}

extension Player {
    /// The category a player is strongest in, by average ranked percentile.
    /// Used where one category has to stand in for the player (a share-card
    /// headline), never to hide the others: every player is eligible for all
    /// six.
    var primaryCategory: MetricCategory {
        let ranked = Dictionary(grouping: rankedMetrics, by: \.category)
        let best = ranked.max { lhs, rhs in
            average(lhs.value) < average(rhs.value)
        }
        return best?.key ?? .scoring
    }

    private func average(_ metrics: [Metric]) -> Double {
        guard !metrics.isEmpty else { return 0 }
        return Double(metrics.map(\.percentile).reduce(0, +)) / Double(metrics.count)
    }

    /// Every player type (g, f, c, unknown) is eligible for every category.
    /// Percentiles are ranked inside the player's own position group, but a
    /// center is still a scorer and a guard still rebounds, so no category is
    /// ever filtered by position.
    func matchesPlayerType(for category: MetricCategory?) -> Bool { true }

    /// Position to surface in the UI. When the snapshot has no position (the
    /// box score left it blank) but the player has metrics, fall back to the
    /// player-type label so we never show a blank next to real stats.
    var displayPosition: String {
        let trimmed = position.trimmingCharacters(in: .whitespaces).uppercased()
        if !trimmed.isEmpty && trimmed != "TBD" && trimmed != "\u{2014}" && trimmed != "-" {
            return position
        }
        guard let type = playerType?.uppercased(), type != "UNKNOWN" else { return "" }
        return type
    }

    var initials: String {
        let parts = name.split(separator: " ")
        guard let first = parts.first else { return "" }
        guard parts.count > 1 else { return String(first.prefix(1)) }

        let last = parts.last!
        let suffix = last.trimmingCharacters(in: .punctuationCharacters).uppercased()
        let hasSuffix = ["JR", "SR", "II", "III", "IV", "V"].contains(suffix)

        if hasSuffix && parts.count > 2 {
            // Use part before suffix as last name (e.g., "Larry Nance Jr." -> "LN")
            let lastName = parts[parts.count - 2]
            return String(first.prefix(1)) + String(lastName.prefix(1))
        }

        // Standard case: first initial + last initial
        return String(first.prefix(1)) + String(last.prefix(1))
    }
}

struct GameTrend: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let date: Date
    let opponent: String
    let summary: String
    let percentileDelta: Int
    let keyMetric: String

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case opponent
        case summary
        case percentileDelta = "percentile_delta"
        case keyMetric = "key_metric"
    }
}

/// The position cohort a board is drawn for. `all` is a view over the whole
/// league; the other three are the cohorts the feed ranks percentiles inside
/// (the Cleaning the Glass convention), so a center's rebounding is judged
/// against centers.
enum PlayerPositionGroup: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all = "All"
    case `guard` = "G"
    case forward = "F"
    case center = "C"

    var id: String { rawValue }

    /// The three real cohorts, without the `all` view.
    static let cohorts: [PlayerPositionGroup] = [.guard, .forward, .center]

    var cohortDescription: String {
        switch self {
        case .all: return "Among every player"
        case .guard: return "Among guards"
        case .forward: return "Among forwards"
        case .center: return "Among centers"
        }
    }

    /// Plural noun for captions: "every guard with a line this season".
    var noun: String {
        switch self {
        case .all: return "player"
        case .guard: return "guard"
        case .forward: return "forward"
        case .center: return "center"
        }
    }

    /// Whether a player belongs on this board.
    func includes(_ player: Player) -> Bool {
        self == .all || player.positionGroup == self
    }

    /// The `player_type` the feed ranks this cohort under.
    var playerType: String? {
        switch self {
        case .all: return nil
        case .guard: return "g"
        case .forward: return "f"
        case .center: return "c"
        }
    }

    var preferredAdvancedMetrics: [String] {
        switch self {
        case .all: return ["Pts/100", "TS%", "USG%", "On-Off"]
        case .guard: return ["AST%", "TS%", "USG%", "On-Off"]
        case .forward: return ["Pts/100", "TS%", "USG%", "On-Off"]
        case .center: return ["REB%", "Rim FG%", "BLK%", "On-Off"]
        }
    }

    var preferredTraditionalMetrics: [String] {
        switch self {
        case .all: return ["PPG", "RPG", "APG"]
        case .guard: return ["APG", "PPG", "SPG"]
        case .forward: return ["PPG", "RPG", "3PM"]
        case .center: return ["RPG", "BPG", "FG%"]
        }
    }
}

enum MetricKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case advanced = "Advanced"
    case traditional = "Traditional"

    var id: String { rawValue }
}

enum MetricFamily: String, CaseIterable, Identifiable, Hashable, Sendable {
    case efficiency = "Efficiency"
    case usage = "Usage"
    case shooting = "Shooting"
    case frequency = "Frequency"
    case accuracy = "Accuracy"
    case playmaking = "Playmaking"
    case turnovers = "Turnovers"
    case rebounding = "Rebounding"
    case rimProtection = "Rim Protection"
    case steals = "Steals"
    case impact = "Impact"
    case playingTime = "Playing Time"
    case production = "Production"

    var id: String { rawValue }
}

struct MetricDefinition: Hashable, Sendable {
    let label: String
    let category: MetricCategory
    let kind: MetricKind
    let family: MetricFamily
    let positions: Set<PlayerPositionGroup>
    let higherIsBetter: Bool
    let priority: Int
    let description: String
}

/// Mirrors the metric table in `handoff/NBA_CONTRACT.md` label for label. The
/// backend writes these exact strings into `metrics[].label`; change the
/// contract first, then both sides.
enum BasketballMetricRegistry {
    private static let allCohorts: Set<PlayerPositionGroup> = [.guard, .forward, .center]

    static let definitions: [MetricDefinition] = [
        // Scoring
        definition("Pts/100", .scoring, .advanced, .production, 10, "Points scored per 100 team possessions while he is on the floor."),
        definition("USG%", .scoring, .advanced, .usage, 20, "Share of his team's possessions he ends with a shot, a free throw trip or a turnover while on the floor."),
        definition("TS%", .scoring, .advanced, .efficiency, 30, "Points per shooting possession, counting threes and free throws: points divided by twice his field goal attempts plus 0.44 free throw attempts."),
        definition("eFG%", .scoring, .advanced, .efficiency, 40, "Field goal percentage that gives a three-pointer its extra half a point."),
        definition("FT Rate", .scoring, .advanced, .frequency, 50, "Free throw attempts per field goal attempt."),
        definition("3PT Rate", .scoring, .advanced, .frequency, 60, "Share of his field goal attempts that are three-pointers."),
        definition("PPG", .scoring, .traditional, .production, 110, "Points per game."),
        definition("FG%", .scoring, .traditional, .accuracy, 120, "Field goals made divided by field goals attempted."),
        definition("3P%", .scoring, .traditional, .accuracy, 130, "Three-pointers made divided by attempted. Needs at least 50 attempts (prorated early in a season) to be ranked."),
        definition("FT%", .scoring, .traditional, .accuracy, 140, "Free throws made divided by attempted. Needs at least 50 attempts (prorated early in a season) to be ranked."),
        definition("3PM", .scoring, .traditional, .production, 150, "Total three-pointers made."),

        // Shooting: where the shots come from and how often they go in.
        definition("Rim Freq", .shooting, .advanced, .frequency, 10, "Share of his field goal attempts taken within four feet of the basket."),
        definition("Rim FG%", .shooting, .advanced, .accuracy, 20, "Field goal percentage on shots within four feet of the basket. Needs at least 40 rim attempts."),
        definition("Short Mid Freq", .shooting, .advanced, .frequency, 30, "Share of his field goal attempts from four to fourteen feet that are not threes."),
        definition("Short Mid FG%", .shooting, .advanced, .accuracy, 40, "Field goal percentage on two-point shots from four to fourteen feet. Needs at least 40 attempts."),
        definition("Long Mid Freq", .shooting, .advanced, .frequency, 50, "Share of his field goal attempts from fourteen feet out to the three-point line."),
        definition("Long Mid FG%", .shooting, .advanced, .accuracy, 60, "Field goal percentage on two-point shots from fourteen feet out. Needs at least 40 attempts."),
        definition("Corner 3%", .shooting, .advanced, .accuracy, 70, "Three-point percentage from the corners, the shortest three on the floor. Needs at least 30 attempts."),
        definition("Non-Corner 3%", .shooting, .advanced, .accuracy, 80, "Three-point percentage from the wings and the top of the arc. Needs at least 50 attempts."),
        definition("Assisted FG%", .shooting, .advanced, .shooting, 90, "Share of his made field goals that a teammate assisted. A lower number means more self-created shots."),

        // Playmaking
        definition("AST%", .playmaking, .advanced, .playmaking, 10, "Share of his teammates' made field goals he assisted while on the floor."),
        definition("AST/100", .playmaking, .advanced, .playmaking, 20, "Assists per 100 team possessions while he is on the floor."),
        definition("TOV%", .playmaking, .advanced, .turnovers, 30, "Turnovers per 100 of his shooting and turnover possessions. Lower is better.", higherIsBetter: false),
        definition("AST:TO", .playmaking, .advanced, .playmaking, 40, "Assists for every turnover."),
        definition("AST:USG", .playmaking, .advanced, .playmaking, 50, "Assist percentage divided by usage: how much he creates for others relative to how much he uses."),
        definition("APG", .playmaking, .traditional, .playmaking, 110, "Assists per game."),
        definition("AST", .playmaking, .traditional, .production, 120, "Total assists."),
        definition("TOV/G", .playmaking, .traditional, .turnovers, 130, "Turnovers per game. Lower is better.", higherIsBetter: false),

        // Rebounding
        definition("OREB%", .rebounding, .advanced, .rebounding, 10, "Share of the available offensive rebounds he grabs while on the floor."),
        definition("DREB%", .rebounding, .advanced, .rebounding, 20, "Share of the available defensive rebounds he grabs while on the floor."),
        definition("REB%", .rebounding, .advanced, .rebounding, 30, "Share of all available rebounds he grabs while on the floor."),
        definition("RPG", .rebounding, .traditional, .rebounding, 110, "Rebounds per game."),
        definition("OREB", .rebounding, .traditional, .production, 120, "Total offensive rebounds."),
        definition("DREB", .rebounding, .traditional, .production, 130, "Total defensive rebounds."),

        // Defense
        definition("STL%", .defense, .advanced, .steals, 10, "Share of opponent possessions that end in his steal while he is on the floor."),
        definition("BLK%", .defense, .advanced, .rimProtection, 20, "Share of opponent two-point attempts he blocks while on the floor."),
        definition("Stocks/100", .defense, .advanced, .production, 30, "Steals plus blocks per 100 team possessions while he is on the floor."),
        definition("Fouls/100", .defense, .advanced, .production, 40, "Personal fouls per 100 team possessions while he is on the floor. Lower is better.", higherIsBetter: false),
        definition("SPG", .defense, .traditional, .steals, 110, "Steals per game."),
        definition("BPG", .defense, .traditional, .rimProtection, 120, "Blocks per game."),
        definition("STL", .defense, .traditional, .steals, 130, "Total steals."),
        definition("BLK", .defense, .traditional, .rimProtection, 140, "Total blocks."),

        // Impact
        definition("On-Court +/-", .impact, .advanced, .impact, 10, "Points the team outscores opponents by per 100 possessions while he is on the floor."),
        definition("On-Off", .impact, .advanced, .impact, 20, "The team's net rating with him on the floor minus its net rating with him on the bench, per 100 possessions."),
        definition("Min%", .impact, .advanced, .playingTime, 30, "Share of his team's available minutes he plays."),
        definition("MPG", .impact, .traditional, .playingTime, 110, "Minutes per game."),
        definition("GS", .impact, .traditional, .playingTime, 120, "Games started."),
        definition("+/-", .impact, .traditional, .impact, 130, "Total plus/minus: the team's scoring margin while he is on the floor, summed over the season."),
    ]

    static func definition(for label: String, category: MetricCategory) -> MetricDefinition? {
        definitions.first { $0.label == label && $0.category == category }
    }

    /// How a metric combines when several players are pooled into one number -
    /// the roster aggregate the team comparison draws.
    ///
    /// Kept as its own table rather than a field on `MetricDefinition` because
    /// it answers a different question from the rest of the registry (how to
    /// *display* one player's metric vs how to *combine* many), and because the
    /// weights below are the honest part: a rate cannot be averaged across
    /// players without weighting it by the volume it was computed over. A
    /// 12-minute reserve at 70% TS and a 2,400-minute star at 58% do not
    /// average to 64%.
    ///
    /// Weighting a per-possession rate by minutes is a close approximation of
    /// the true team rate rather than an identity, since we hold each player's
    /// rate and his minutes but not his possessions. Per-game averages weight
    /// by games, and counting stats simply add up.
    static func aggregation(for label: String, category: MetricCategory) -> MetricAggregation {
        switch (category, label) {
        // Counting stats and per-game lines add up: a roster's PPG is the
        // team's scoring, and it is the interesting number.
        case (.scoring, "PPG"), (.scoring, "3PM"),
             (.playmaking, "APG"), (.playmaking, "AST"), (.playmaking, "TOV/G"),
             (.rebounding, "RPG"), (.rebounding, "OREB"), (.rebounding, "DREB"),
             (.defense, "SPG"), (.defense, "BPG"), (.defense, "STL"), (.defense, "BLK"),
             (.impact, "GS"), (.impact, "+/-"):
            return .sum
        // Minutes per game is a per-player average; weight it by games played.
        case (.impact, "MPG"):
            return .weighted(.games)
        // Every other metric is a rate over the minutes he was on the floor.
        default:
            return .weighted(.minutes)
        }
    }

    static func kind(for metric: Metric) -> MetricKind {
        definition(for: metric.label, category: metric.category)?.kind ?? .advanced
    }

    static func isSupported(_ metric: Metric, by position: PlayerPositionGroup) -> Bool {
        position == .all
            || (definition(for: metric.label, category: metric.category)?.positions.contains(position) ?? true)
    }

    static func sorted(_ metrics: [Metric]) -> [Metric] {
        metrics.sorted { lhs, rhs in
            let left = definition(for: lhs.label, category: lhs.category)?.priority ?? Int.max
            let right = definition(for: rhs.label, category: rhs.category)?.priority ?? Int.max
            if left == right { return lhs.label < rhs.label }
            return left < right
        }
    }

    private static func definition(
        _ label: String,
        _ category: MetricCategory,
        _ kind: MetricKind,
        _ family: MetricFamily,
        _ priority: Int,
        _ description: String,
        higherIsBetter: Bool = true
    ) -> MetricDefinition {
        MetricDefinition(
            label: label,
            category: category,
            kind: kind,
            family: family,
            positions: allCohorts,
            higherIsBetter: higherIsBetter,
            priority: priority,
            description: description
        )
    }
}

/// How several players' values for one metric collapse into a single number.
enum MetricAggregation: Hashable, Sendable {
    /// Counting stats and totals: add them up.
    case sum
    /// Rates: mean weighted by the volume each player's rate was measured over.
    case weighted(MetricWeight)
}

/// The denominator a rate was computed against, so it can be weighted by it.
/// Each case resolves to a number already present in the player's standard
/// stats, so no extra feed columns are needed.
enum MetricWeight: Hashable, Sendable {
    case minutes
    case games

    /// Pulls the weight out of a player's standard-stat line. Returns nil when
    /// the player has no volume for it, which correctly drops them from the
    /// weighted mean instead of contributing a zero.
    func value(for player: Player) -> Double? {
        switch self {
        case .minutes: return Self.plain("MIN", in: player)
        case .games: return Self.plain("G", in: player)
        }
    }

    private static func plain(_ label: String, in player: Player) -> Double? {
        guard let raw = player.standardStats?.first(where: { $0.label == label })?.value,
              let value = metricNumericValue(raw),
              value > 0
        else { return nil }
        return value
    }
}

extension Player {
    /// The cohort the feed ranked this player in. A handful of box scores
    /// carry no position (`player_type` "unknown"); those fold into forwards,
    /// the largest of the cohorts a role-less player is likeliest to belong to.
    var positionGroup: PlayerPositionGroup {
        switch playerType?.lowercased() {
        case "g": return .guard
        case "f": return .forward
        case "c": return .center
        default:
            switch displayPosition.uppercased() {
            case "G", "PG", "SG": return .guard
            case "C": return .center
            default: return .forward
            }
        }
    }

    /// The volume a category's rates were measured over, for a board subtitle:
    /// "1,820 min". Nil when the line has none.
    func volumeCaption(for category: MetricCategory) -> String? {
        MetricWeight.minutes.value(for: self).map { "\(Int($0).formatted(.number.grouping(.automatic))) min" }
    }

    func metrics(kind: MetricKind) -> [Metric] {
        BasketballMetricRegistry.sorted(metrics.filter { BasketballMetricRegistry.kind(for: $0) == kind })
    }

    func preferredHeadlineMetric(kind: MetricKind) -> Metric? {
        let candidates = metrics(kind: kind)
        let preferred = kind == .advanced
            ? positionGroup.preferredAdvancedMetrics
            : positionGroup.preferredTraditionalMetrics
        for label in preferred {
            if let metric = candidates.first(where: { $0.label == label }) { return metric }
        }
        return candidates.first
    }
}
