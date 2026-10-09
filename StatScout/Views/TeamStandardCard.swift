import SwiftUI

/// The traditional line for a whole team, percentile-mapped against the other
/// 29.
///
/// The percentile card next to it answers "how good is this team's scoring and
/// rebounding"; this answers "what actually happened". The app already does this
/// on a player page, so a team not having it was the gap.
///
/// The ruler here is the league's thirty teams, not its several hundred
/// players: a team's 46% from the field means nothing against individual
/// shooters' spread, and everything against the other teams'.
struct TeamStandardCard: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let season: Int
    /// See `TeamRankingsCard.seasonPhase`.
    var seasonPhase: SeasonPhase = .regular
    let players: [Player]
    /// Every player in the season, used to build the thirty team lines.
    let leaguePlayers: [Player]
    /// The league's rows for one rolling window, loaded on demand.
    let loadRecent: ((RecentWindow) async -> [RecentForm])?
    /// False on a historical season: the rolling windows are only kept for the
    /// newest two seasons, so the control is hidden rather than offered and left
    /// to come back empty.
    var supportsRecent: Bool = true
    let onUpgradeTap: () -> Void

    @State private var showingRecent = false
    @State private var window: RecentWindow = .twoWeeks
    @State private var leagueRowsByWindow: [Int: [RecentForm]] = [:]
    @State private var loading = false

    // MARK: - Stat vocabulary

    /// Shooting lines, ranked by percentage. Made and attempted are summed across
    /// the roster before dividing: averaging its players' percentages would
    /// weight a 2-for-3 cameo like a starter's season.
    private static let shootingLabels = ["FG%", "3P%", "FT%"]

    /// Per-game lines, in reading order.
    private static let perGameLabels = ["PPG", "RPG", "APG", "SPG", "BPG", "TOV", "PF"]

    /// Lower is better.
    private static let lowerIsBetterLabels: Set<String> = ["TOV", "PF"]

    /// The rolling-window column behind each per-game line. PF has no per-game
    /// column in the rollup, so it stays a season line.
    private static let recentKeys: [String: String] = [
        "PPG": "ppg", "RPG": "rpg", "APG": "apg", "SPG": "spg", "BPG": "bpg", "TOV": "tov_pg",
    ]

    private var leagueRows: [RecentForm] { leagueRowsByWindow[window.rawValue] ?? [] }

    /// What the card actually renders. The toggle survives a season change (it
    /// is view state, the season is a parameter), so a user who turned Recent on
    /// for the live season and then walked back to 2018-19 would otherwise sit in
    /// front of a permanently empty window.
    private var isRecent: Bool { showingRecent && supportsRecent }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: "TEAM STANDARD STATS")

            if supportsRecent {
                HardwoodSegmented(
                    segments: [
                        .init(value: false, label: "Season"),
                        .init(value: true, label: "Recent", isLocked: !store.isPro),
                    ],
                    selection: $showingRecent,
                    onLockedTap: { _ in onUpgradeTap() }
                )
                .padding(.horizontal, HardwoodGeo.padInline)
                .padding(.vertical, 8)
                .background(HardwoodPalette.surfaceAlt)
            }

            if isRecent {
                HardwoodSegmented(
                    segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
                    selection: $window
                )
                .padding(.horizontal, HardwoodGeo.padInline)
                .padding(.bottom, 8)
                .background(HardwoodPalette.surfaceAlt)
            }

            if isRecent {
                recentContent
            } else {
                seasonContent
            }
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .task(id: "\(team)-\(season)-\(seasonPhase.rawValue)-\(isRecent)-\(window.rawValue)-\(store.isPro)") {
            if isRecent, store.isPro { await load() }
        }
    }

    // MARK: - Season

    @ViewBuilder
    private var seasonContent: some View {
        let line = teamLine(for: players)
        if line.isEmpty {
            emptyState("No standard stats for this roster")
        } else {
            let league = leagueLines()
            barGroup(title: "SHOOTING", labels: Self.shootingLabels, line: line, league: league, startIndex: 0)
            barGroup(
                title: "PER GAME",
                labels: Self.perGameLabels,
                line: line,
                league: league,
                startIndex: Self.shootingLabels.count
            )
            Text("Totals add up the current roster's season lines, so a player traded at the deadline brings his whole year with him. Ranked among the 30 teams.")
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .padding(.horizontal, HardwoodGeo.padCard)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func barGroup(
        title: String,
        labels: [String],
        line: [String: Double],
        league: [[String: Double]],
        startIndex: Int
    ) -> some View {
        let present = labels.filter { line[$0] != nil }
        return Group {
            if !present.isEmpty {
                HardwoodSubSectionBar(title: title)
                ForEach(Array(present.enumerated()), id: \.element) { offset, label in
                    let value = line[label] ?? 0
                    MetricBar(
                        metric: Metric(
                            id: "team-std-\(label)",
                            label: label,
                            value: format(label, value),
                            percentile: TeamAggregation.percentile(
                                value,
                                among: league.compactMap { $0[label] },
                                higherIsBetter: !Self.lowerIsBetterLabels.contains(label)
                            ),
                            category: category(for: label)
                        )
                    )
                    .padding(.horizontal, HardwoodGeo.padCard)
                    .padding(.vertical, 12)
                    .background((startIndex + offset) % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                        alignment: .bottom
                    )
                }
            }
        }
    }

    // MARK: - Recent

    @ViewBuilder
    private var recentContent: some View {
        if !store.isPro {
            ZStack(alignment: .bottom) {
                teaser
                    .blur(radius: 8)
                    .allowsHitTesting(false)
                BlurGateUnlock(
                    headline: "See every team's last week, 2 week and 4 week form",
                    trigger: .teamView
                )
            }
        } else if loading {
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.75)
                Text("Loading recent form…")
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            let rows = teamRecentRows()
            if rows.isEmpty {
                emptyState("No games in the \(window.prose)")
            } else {
                let seasonLine = teamLine(for: players)

                // Season to window, not a percentile bar. Two weeks of team
                // rebounds sits outside the whole spread of thirty *season*
                // figures more often than not, so a bar drawn on that ruler pins
                // to 1 or 100 and says nothing. The move against the team's own
                // season number is the real information, and it's the same
                // framing the Trends board uses.
                HardwoodSubSectionBar(title: "PER GAME · \(window.label.uppercased())")
                ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                    let label = row.0
                    let now = row.1
                    let then = seasonLine[label]
                    HStack(spacing: 10) {
                        Text(label)
                            .font(HardwoodType.bodyBold)
                            .foregroundStyle(HardwoodPalette.ink)
                            .frame(width: 68, alignment: .leading)
                        if let then {
                            Text("\(format(label, then)) → \(format(label, now))")
                                .font(HardwoodType.small)
                                .monospacedDigit()
                                .foregroundStyle(HardwoodPalette.inkSecondary)
                        } else {
                            Text(format(label, now))
                                .font(HardwoodType.small)
                                .monospacedDigit()
                                .foregroundStyle(HardwoodPalette.inkSecondary)
                        }
                        Spacer(minLength: 0)
                        if let then {
                            TrendArrow(
                                delta: now - then,
                                decimals: 1,
                                lowerIsBetter: Self.lowerIsBetterLabels.contains(label)
                            )
                        }
                    }
                    .padding(.horizontal, HardwoodGeo.padCard)
                    .frame(height: HardwoodGeo.rowHeight)
                    .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                        alignment: .bottom
                    )
                }
                Text("Compared with the same team's season line.")
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .padding(.horizontal, HardwoodGeo.padCard)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Invented numbers in the real layout, so a free user can see what the
    /// window actually reports rather than a padlock. It tracks the window
    /// picker, because a preview that ignores the control above it looks broken.
    private var teaser: some View {
        let rows = teaserRows
        return VStack(spacing: 0) {
            HardwoodSubSectionBar(title: "PER GAME · \(window.label.uppercased())")
            ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(HardwoodType.bodyBold)
                        .foregroundStyle(HardwoodPalette.ink)
                        .frame(width: 68, alignment: .leading)
                    Text("\(format(row.0, row.1)) → \(format(row.0, row.2))")
                        .font(HardwoodType.small)
                        .monospacedDigit()
                        .foregroundStyle(HardwoodPalette.inkSecondary)
                    Spacer(minLength: 0)
                    TrendArrow(delta: row.2 - row.1, decimals: 1)
                }
                .padding(.horizontal, HardwoodGeo.padCard)
                .frame(height: HardwoodGeo.rowHeight)
                .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
            }
        }
    }

    /// Season line to an invented window, per window length. Built from *this*
    /// team's real season rates so the preview is the team the user is looking
    /// at, and so moving the window picker visibly redraws it. Only the window
    /// column is fictional, and it stays behind the blur.
    private var teaserRows: [(String, Double, Double)] {
        let seasonLine = teamLine(for: players)
        let fallback: [(String, Double)] = [("PPG", 114.2), ("RPG", 44.3), ("APG", 26.1), ("SPG", 7.4)]
        let base: [(String, Double)] = seasonLine.isEmpty
            ? fallback
            : ["PPG", "RPG", "APG", "SPG"].compactMap { label in seasonLine[label].map { (label, $0) } }

        return base.map { label, season in
            let seed = Self.stableSeed("\(label)-\(window.rawValue)-\(team)")
            // Plus or minus 6% of the season figure, the size of a real
            // two-week swing.
            let swing = season * Double(seed % 13 - 6) / 100
            return (label, season, season + swing)
        }
    }

    /// Deterministic across launches, unlike `hashValue`.
    private static func stableSeed(_ text: String) -> Int {
        abs(text.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 100_003 })
    }

    // MARK: - Aggregation

    private func category(for label: String) -> MetricCategory {
        switch label {
        case "FG%", "3P%", "FT%", "PPG": return .scoring
        case "APG", "TOV": return .playmaking
        case "RPG": return .rebounding
        default: return .defense
        }
    }

    /// One team's standard line: shooting rebuilt from summed makes and attempts,
    /// per-game lines rebuilt from season totals over the team's own game count.
    ///
    /// Points come from the makes (2 x FGM + 3PM + FTM), so the scoring line is
    /// exact; the other per-game lines multiply each player's average by his
    /// games and divide by the team's. That is the same "numerators and
    /// denominators, never pre-divided rates" rule the backend rollup follows.
    private func teamLine(for roster: [Player]) -> [String: Double] {
        guard !roster.isEmpty else { return [:] }

        var pairs: [String: (made: Double, attempts: Double)] = [:]
        var totals: [String: Double] = [:]
        var teamGames = 0.0

        for player in roster {
            let stats = Dictionary(
                (player.standardStats ?? []).map { ($0.label.uppercased(), $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
            let games = stats["G"].flatMap(metricNumericValue) ?? 0
            // Games played is per player, so summing it across a roster is
            // meaningless. The maximum is the team's own count.
            teamGames = max(teamGames, games)
            for label in ["FG", "3P", "FT"] {
                guard let raw = stats[label] else { continue }
                let parts = raw.split(separator: "/", maxSplits: 1).compactMap { metricNumericValue(String($0)) }
                guard parts.count == 2 else { continue }
                pairs[label, default: (0, 0)].made += parts[0]
                pairs[label, default: (0, 0)].attempts += parts[1]
            }
            for (label, key) in [("RPG", "RPG"), ("APG", "APG"), ("SPG", "SPG"), ("BPG", "BPG")] {
                if let perGame = stats[key].flatMap(metricNumericValue) {
                    totals[label, default: 0] += perGame * games
                }
            }
            for label in ["TOV", "PF"] {
                if let total = stats[label].flatMap(metricNumericValue) {
                    totals[label, default: 0] += total
                }
            }
        }

        guard teamGames > 0 else { return [:] }
        var line: [String: Double] = [:]
        for (label, pair) in [("FG%", pairs["FG"]), ("3P%", pairs["3P"]), ("FT%", pairs["FT"])] {
            if let pair, pair.attempts > 0 { line[label] = pair.made / pair.attempts * 100 }
        }
        if let fg = pairs["FG"], let three = pairs["3P"], let ft = pairs["FT"] {
            line["PPG"] = (2 * fg.made + three.made + ft.made) / teamGames
        }
        for (label, total) in totals { line[label] = total / teamGames }
        return line
    }

    /// The other twenty-nine, plus this one: the distribution a bar is drawn
    /// against.
    private func leagueLines() -> [[String: Double]] {
        TeamAggregation.rosters(from: leaguePlayers)
            .values
            .map { teamLine(for: $0) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Window

    /// This team's per-game lines over the window, rebuilt from its players'
    /// rolling rows: each player's average times his games, over the team's
    /// games in the window.
    private func teamRecentRows() -> [(String, Double)] {
        let rows = TeamAggregation.recentRosters(from: leagueRows)[normalizedTeamAbbreviation(team)] ?? []
        let teamGames = Double(rows.map(\.games).max() ?? 0)
        guard teamGames > 0 else { return [] }
        return Self.perGameLabels.compactMap { label in
            guard let key = Self.recentKeys[label] else { return nil }
            let total = rows.reduce(0.0) { sum, row in
                sum + (row.metrics[key] ?? 0) * Double(row.games)
            }
            guard rows.contains(where: { $0.metrics[key] != nil }) else { return nil }
            return (label, total / teamGames)
        }
    }

    private func load() async {
        guard store.isPro, let loadRecent else { return }
        let target = window
        loading = leagueRowsByWindow[target.rawValue] == nil
        leagueRowsByWindow[target.rawValue] = await loadRecent(target)
        loading = false
    }

    // MARK: - Formatting

    private func format(_ label: String, _ value: Double) -> String {
        switch label {
        case "FG%", "3P%", "FT%":
            return String(format: "%.1f%%", value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(HardwoodPalette.inkTertiary)
            Text(message)
                .font(HardwoodType.small)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
