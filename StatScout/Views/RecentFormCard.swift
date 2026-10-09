import SwiftUI

/// Rolling 1 / 2 / 4 week form for a single player. Pro-gated: free users see a
/// blurred static teaser and an upgrade CTA, with no fetch. Pro users load the
/// player's rolling rows once, then switch windows client-side.
struct RecentFormCard: View {
    @EnvironmentObject private var store: StoreService
    let player: Player
    let season: Int
    /// League pool used to build the value→percentile curve so the recent bar
    /// sits on the same ruler as the season bar. Filtered to the player's
    /// position group at curve-build time.
    let leaguePlayers: [Player]
    /// (playerId, season, phase).
    let fetchRecentForm: ((Int, Int, SeasonPhase) async throws -> [RecentForm])?
    /// Changes after a validated publisher revision, so a retained profile
    /// cannot keep showing the previous game set.
    var freshnessRevision: String? = nil
    var freshnessStatus: DataFreshnessStatus? = nil
    let onUpgradeTap: () -> Void

    @State private var forms: [Int: RecentForm] = [:]
    @State private var loading = false
    @State private var loadError: String?
    @State private var window: RecentWindow = .twoWeeks
    @State private var curves: LeaguePercentileCurves?

    /// The phase the card's games come from - the profile is scoped to
    /// whichever phase the user arrived on, and the player row carries it.
    private var seasonPhase: SeasonPhase { player.seasonPhase }

    /// Smallest sample we'll consider trustworthy. Anything below shows the
    /// numbers but tags them as "small sample".
    private var form: RecentForm? { forms[window.rawValue] }

    /// The recent bars, in the order the categories are read in. Season totals
    /// have no per-week figure on the season's ruler, so they are left out.
    private static let barLabels = [
        "PPG", "TS%", "3P%", "APG", "TOV/G", "RPG", "SPG", "BPG", "MPG",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .task(id: "\(player.playerId)-\(season)-\(seasonPhase.rawValue)-\(freshnessRevision ?? "none")") {
            await load()
        }
        .onAppear { rebuildCurves() }
        .onChange(of: leaguePlayers.count) { _, _ in rebuildCurves() }
    }

    private func rebuildCurves() {
        guard store.isPro else { return }
        let group = player.positionGroup
        curves = LeaguePercentileCurves(
            players: leaguePlayers.filter { $0.positionGroup == group },
            categories: MetricCategory.allCases,
            labels: Self.barLabels
        )
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(HardwoodPalette.court)
                Text("RECENT FORM")
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
                Spacer()
                if !store.isPro {
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
            }
            .padding(.horizontal, HardwoodGeo.padInline)
            .padding(.top, 12)

            windowPicker
                .padding(.horizontal, HardwoodGeo.padInline)
                .padding(.bottom, 10)
        }
        .background(HardwoodPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
            alignment: .bottom
        )
    }

    private var windowPicker: some View {
        HardwoodSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: $window
        )
    }

    @ViewBuilder
    private var content: some View {
        if store.isPro {
            proContent
        } else {
            ZStack(alignment: .bottom) {
                teaserBody
                    .blur(radius: 8)
                    .disabled(true)
                    .allowsHitTesting(false)
                BlurGateUnlock(
                    headline: "See last week, 2 week and 4 week form for any player",
                    trigger: .recentForm
                )
            }
        }
    }

    /// Static, non-fetching preview for free users. No rows are loaded.
    /// These are illustrative bars in the season percentile format so the blur
    /// reads as "real recent-form bars" without paying the network/battery cost.
    private var teaserBody: some View {
        let sample: [Metric] = [
            Metric(id: "t_ppg", label: "PPG", value: "27.4", percentile: 94, category: .scoring),
            Metric(id: "t_ts", label: "TS%", value: "61.8%", percentile: 88, category: .scoring),
            Metric(id: "t_apg", label: "APG", value: "7.1", percentile: 81, category: .playmaking),
            Metric(id: "t_rpg", label: "RPG", value: "5.9", percentile: 76, category: .rebounding),
        ]
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                summaryStat(label: "G", value: "4")
                summaryStat(label: "MIN", value: "138")
                Spacer(minLength: 0)
            }
            .padding(HardwoodGeo.padInline)

            metricBarList(sample)
        }
    }

    @ViewBuilder
    private var proContent: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.75)
                Text("Loading recent form…")
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let err = loadError {
            InlineLoadError(message: err) { await load() }
        } else if let form {
            statsBody(form: form)
        } else {
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
        }
    }

    private var emptyStateText: String {
        switch freshnessStatus {
        case .pending, .partial, .checking:
            return "Recent game data is still arriving"
        case .offline, .failed:
            return "Recent game data is unavailable right now"
        default:
            return "No games in the \(window.prose)"
        }
    }

    private func statsBody(form: RecentForm) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                summaryStat(label: "G", value: "\(form.games)")
                summaryStat(label: "MIN", value: "\(form.minutes)")
                Spacer(minLength: 0)
                if form.isSmallSample {
                    Text("SMALL SAMPLE")
                        .font(HardwoodType.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(HardwoodPalette.inkTertiary)
                        .clipShape(Capsule())
                }
            }
            .padding(HardwoodGeo.padInline)

            metricBarList(recentMetricRows(form: form))
        }
    }

    /// Recent-window metrics rendered with the exact same `MetricBar` row used
    /// on the season percentile card - same label/bar/value layout and the same
    /// alternating row backgrounds - so recent form reads on the identical ruler.
    private func metricBarList(_ rows: [Metric]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                MetricBar(metric: metric)
                    .padding(.horizontal, HardwoodGeo.padCard)
                    .padding(.vertical, 12)
                    .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                    .overlay(
                        Rectangle()
                            .fill(HardwoodPalette.divider)
                            .frame(height: HardwoodGeo.hairline),
                        alignment: .bottom
                    )
            }
        }
    }

    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
            Text(value)
                .font(HardwoodType.bodyBold)
                .foregroundStyle(HardwoodPalette.ink)
        }
    }

    /// Recent-window metrics mapped to `Metric` so they render with the season
    /// `MetricBar`. The percentile is interpolated from the league season curve
    /// (so the recent bar sits on the same ruler as the season card); the value
    /// is the window number. Skips metrics with no window data or no curve so we
    /// never draw a bar we can't place.
    private func recentMetricRows(form: RecentForm) -> [Metric] {
        Self.barLabels.compactMap { label -> Metric? in
            guard let key = RecentMetricKey.key(for: label),
                  let value = form.metrics[key],
                  let pct = curves?.curve(for: label)?.percentile(for: value),
                  let definition = BasketballMetricRegistry.definitions.first(where: { $0.label == label })
            else { return nil }
            return Metric(
                id: "recent-\(key)",
                label: label,
                value: RecentMetricKey.format(value, label: label),
                percentile: pct,
                category: definition.category
            )
        }
    }

    private func load() async {
        // Free users see a static teaser - no fetch, no battery cost.
        guard store.isPro, let fetch = fetchRecentForm else { return }
        loading = true
        loadError = nil
        do {
            let rows = try await fetch(player.playerId, season, seasonPhase)
            var byWindow: [Int: RecentForm] = [:]
            for row in rows where (byWindow[row.windowWeeks]?.touches ?? -1) < row.touches {
                byWindow[row.windowWeeks] = row
            }
            forms = byWindow
        } catch {
            if !isTaskCancellation(error) {
                loadError = "Couldn't load recent form."
            }
        }
        loading = false
    }
}
