import SwiftUI

/// Team "percentile rankings" card - the team-level analogue of the player
/// profile's percentile card. Pools the roster into one number per metric and
/// ranks it against the other twenty-nine teams, with a Season / Recent toggle
/// that mirrors the player page:
///
/// - **Season**: the roster's minutes-weighted rate for each advanced metric in
///   the chosen category, ranked among the thirty teams. Tapping a bar opens
///   that metric's leaderboard.
/// - **Recent**: the same pooling over the last 1 / 2 / 4 weeks of the league's
///   rolling windows. Pro-gated with the standard blur + CTA, identical to the
///   player card.
///
/// This replaces the old split between a season "team average" card and a
/// separate "team recent form" card, which read as two disconnected modules.
struct TeamRankingsCard: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    let season: Int
    /// Which half of the year the roster's numbers come from. The rolling windows
    /// are anchored per phase, so they have to be read from the same phase the
    /// season bars are showing.
    var seasonPhase: SeasonPhase = .regular
    /// The roster for this team/season.
    let players: [Player]
    /// Every player in the season, used to build the thirty team lines the
    /// roster is ranked against.
    let leaguePlayers: [Player]
    /// The league's rows for one rolling window, loaded on demand.
    let loadRecent: ((RecentWindow) async -> [RecentForm])?
    /// Changes after a validated publisher revision, so a retained team page
    /// cannot keep showing rows from the previous game set.
    var freshnessRevision: String? = nil
    var freshnessStatus: DataFreshnessStatus? = nil
    /// False on a historical season: the rolling windows are only kept for the
    /// newest two seasons, so Recent/Both are hidden rather than offered and
    /// left to come back empty.
    var supportsRecent: Bool = true
    let onUpgradeTap: () -> Void

    @State private var category: MetricCategory = .scoring
    @State private var mode: Mode = .season
    @State private var window: RecentWindow = .twoWeeks
    /// The league's rows by window length, so flipping between windows reads the
    /// right one while the next is in flight.
    @State private var leagueRowsByWindow: [Int: [RecentForm]] = [:]
    @State private var loading = false

    private var leagueRows: [RecentForm] { leagueRowsByWindow[window.rawValue] ?? [] }

    enum Mode: String, CaseIterable, Identifiable {
        case season = "Season", recent = "Recent", both = "Both"
        var id: String { rawValue }
        var usesRecent: Bool { self != .season }
    }

    /// The mode actually rendered. `mode` is view state and the season is a
    /// parameter, so a user who picked Recent on the live season and then walked
    /// back to 2018-19 would otherwise sit in front of a permanently empty
    /// window.
    private var effectiveMode: Mode { supportsRecent ? mode : .season }

    var body: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(
                title: "TEAM ADVANCED STATS",
                trailing: store.isPro ? nil : AnyView(proBadge)
            )

            HardwoodTabs(
                tabs: MetricCategory.allCases.map(\.rawValue),
                selected: Binding(
                    get: { category.rawValue },
                    set: { raw in
                        category = MetricCategory.allCases.first { $0.rawValue == raw } ?? category
                    }
                )
            )
            .padding(.horizontal, HardwoodGeo.padInline)
            .background(HardwoodPalette.surfaceAlt)

            if supportsRecent {
                modePicker
                    .padding(.horizontal, HardwoodGeo.padInline)
                    .padding(.vertical, 8)
                    .background(HardwoodPalette.surfaceAlt)
            }

            if effectiveMode.usesRecent {
                windowPicker
            }

            switch effectiveMode {
            case .season: seasonBars
            case .recent: recentSection
            case .both: bothSection
            }
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .task(id: "\(team)-\(season)-\(seasonPhase.rawValue)-\(effectiveMode.rawValue)-\(window.rawValue)-\(store.isPro)-\(freshnessRevision ?? "none")") {
            if effectiveMode.usesRecent, store.isPro { await load() }
        }
    }

    private var proBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(.system(size: 9, weight: .bold))
            Text("STATSCOUT+")
                .font(HardwoodType.micro)
                .fontWeight(.bold)
        }
        .foregroundStyle(HardwoodPalette.midnight)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.yellow)
        .clipShape(Capsule())
    }

    // MARK: - Pickers

    private var modePicker: some View {
        HardwoodSegmented(
            segments: Mode.allCases.map {
                .init(
                    value: $0,
                    label: $0.rawValue,
                    isLocked: !store.isPro && $0 != .season
                )
            },
            selection: $mode,
            onLockedTap: { _ in onUpgradeTap() }
        )
    }

    private var windowPicker: some View {
        HardwoodSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: $window
        )
        .padding(.horizontal, HardwoodGeo.padInline)
        .padding(.bottom, 8)
        .background(HardwoodPalette.surfaceAlt)
    }

    // MARK: - Season

    /// The advanced metrics this category has, in the registry's display order.
    private var labels: [String] {
        BasketballMetricRegistry.definitions
            .filter { $0.category == category && $0.kind == .advanced }
            .sorted { $0.priority < $1.priority }
            .map(\.label)
    }

    @ViewBuilder
    private var seasonBars: some View {
        let rows = seasonRows()
        if rows.isEmpty {
            emptyAggregate
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                    NavigationLink(value: MetricRoute(label: metric.label, category: metric.category)) {
                        MetricBar(metric: metric)
                            .padding(.horizontal, HardwoodGeo.padCard)
                            .padding(.vertical, 12)
                            .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                            .overlay(
                                Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                                alignment: .bottom
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("See the league leaderboard for \(metric.label)")
                }
            }

            weightedCaption
        }
    }

    /// One bar per metric: the roster's pooled value, ranked among the teams.
    private func seasonRows() -> [Metric] {
        guard !players.isEmpty else { return [] }
        let league = TeamAggregation.rosters(from: leaguePlayers)
        return labels.compactMap { label -> Metric? in
            guard let own = TeamAggregation.value(label: label, category: category, roster: players)
            else { return nil }
            let others = league.values.compactMap {
                TeamAggregation.value(label: label, category: category, roster: $0)
            }
            let format = MetricValueFormat.inferred(
                from: players.compactMap { player in
                    player.metrics.first { $0.label == label && $0.category == category }?.value
                }
            )
            return Metric(
                id: "teamavg-\(label)",
                label: label,
                value: format.string(own),
                percentile: TeamAggregation.percentile(
                    own,
                    among: others,
                    higherIsBetter: BasketballMetricRegistry.definition(for: label, category: category)?.higherIsBetter ?? true
                ),
                category: category
            )
        }
    }

    // MARK: - Recent

    private var teamRows: [RecentForm] {
        TeamAggregation.recentRosters(from: leagueRows)[normalizedTeamAbbreviation(team)] ?? []
    }

    /// The recent bar for a metric label, or nil when the window has no figure
    /// for it. Season totals have no per-week equivalent and are skipped.
    private func recentMetric(label: String) -> Metric? {
        guard let key = RecentMetricKey.key(for: label),
              !RecentMetricKey.isSeasonTotal(label),
              let own = TeamAggregation.recentValue(key: key, rows: teamRows) else { return nil }
        let others = TeamAggregation.recentRosters(from: leagueRows).values.compactMap {
            TeamAggregation.recentValue(key: key, rows: $0)
        }
        return Metric(
            id: "team-recent-\(key)",
            label: label,
            value: RecentMetricKey.format(own, label: label),
            percentile: TeamAggregation.percentile(
                own,
                among: others,
                higherIsBetter: !RecentMetricKey.lowerIsBetter(label)
            ),
            category: category
        )
    }

    @ViewBuilder
    private var recentSection: some View {
        if store.isPro {
            recentBars
        } else {
            ZStack(alignment: .bottom) {
                recentTeaser
                    .blur(radius: 8)
                    .disabled(true)
                    .allowsHitTesting(false)
                BlurGateUnlock(
                    headline: "See every team's last week, 2 week and 4 week form",
                    trigger: .teamView
                )
            }
        }
    }

    private var bothSection: some View {
        let seasonRows = seasonRows()
        return VStack(spacing: 0) {
            if !store.isPro {
                recentSection
            } else if loading {
                loadingRow
            } else {
                ForEach(Array(seasonRows.enumerated()), id: \.element.id) { index, metric in
                    DualMetricBar(
                        season: metric,
                        recent: recentMetric(label: metric.label),
                        recentCaption: window.segmentLabel
                    )
                    .padding(.horizontal, HardwoodGeo.padCard)
                    .padding(.vertical, 10)
                    .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                        alignment: .bottom
                    )
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.75)
            Text("Loading recent form…")
                .font(HardwoodType.small)
                .foregroundStyle(HardwoodPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Static, non-fetching preview for free users - illustrative team bars in
    /// the recent-form layout. No rows are fetched (no network/battery cost) and
    /// no real team data is shown, so the blur can't be read through to leak the
    /// actual recent numbers.
    private var recentTeaser: some View {
        let sample: [Metric] = [
            Metric(id: "tt_ortg", label: "Pts/100", value: "121.4", percentile: 84, category: .scoring),
            Metric(id: "tt_ts", label: "TS%", value: "60.1%", percentile: 77, category: .scoring),
            Metric(id: "tt_ast", label: "AST%", value: "61.2%", percentile: 71, category: .playmaking),
            Metric(id: "tt_reb", label: "REB%", value: "52.8%", percentile: 66, category: .rebounding),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(sample.enumerated()), id: \.element.id) { index, metric in
                MetricBar(metric: metric)
                    .padding(.horizontal, HardwoodGeo.padCard)
                    .padding(.vertical, 12)
                    .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                    .overlay(
                        Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                        alignment: .bottom
                    )
            }
        }
    }

    @ViewBuilder
    private var recentBars: some View {
        if loading {
            loadingRow
        } else if teamRows.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                Text(emptyStateText)
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        } else {
            let rows = labels.compactMap(recentMetric(label:))
            // Season totals leave some categories (Shooting counts, say) with
            // nothing to draw; say so rather than showing a bare header.
            if rows.isEmpty {
                emptyAggregate
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                    MetricBar(metric: metric)
                        .padding(.horizontal, HardwoodGeo.padCard)
                        .padding(.vertical, 12)
                        .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                        .overlay(
                            Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                            alignment: .bottom
                        )
                }
                recentCaption
            }
        }
    }

    private var emptyStateText: String {
        switch freshnessStatus {
        case .pending, .partial, .checking:
            return "Recent team data is still arriving"
        case .offline, .failed:
            return "Recent team data is unavailable right now"
        default:
            return "No games in the \(window.prose)"
        }
    }

    private var recentCaption: some View {
        let games = teamRows.map(\.games).max() ?? 0
        return Text("\(window.label) · \(games == 1 ? "1 game" : "\(games) games"), ranked among the 30 teams")
            .font(HardwoodType.micro)
            .foregroundStyle(HardwoodPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HardwoodGeo.padCard)
            .padding(.vertical, 10)
    }

    private func load() async {
        // Free users see a static teaser - never fetch real team rows.
        guard store.isPro, let loadRecent else { return }
        let target = window
        loading = leagueRowsByWindow[target.rawValue] == nil
        leagueRowsByWindow[target.rawValue] = await loadRecent(target)
        loading = false
    }

    // MARK: - Shared bits

    private var emptyAggregate: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22))
                .foregroundStyle(HardwoodPalette.inkTertiary)
            Text(players.isEmpty
                 ? "No games played yet this season"
                 : "No \(category.rawValue.lowercased()) numbers to rank for this roster")
                .font(HardwoodType.small)
                .foregroundStyle(HardwoodPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var weightedCaption: some View {
        Text("Season to date, the roster's rates weighted by minutes and ranked among the 30 teams")
            .font(HardwoodType.micro)
            .foregroundStyle(HardwoodPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HardwoodGeo.padCard)
            .padding(.vertical, 10)
    }
}
