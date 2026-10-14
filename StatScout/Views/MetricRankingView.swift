import SwiftUI

/// One metric's league leaderboard, reached from a percentile bar. Carries
/// the Stats board's controls (position tabs, stat picker, sort arrow,
/// search) so a drill-down reads like the board it came from.
struct MetricRankingView: View {
    let players: [Player]
    let season: Int?
    /// Supplies qualification and volume; nil in previews.
    var viewModel: DashboardViewModel? = nil
    @State private var metricLabel: String
    @State private var metricCategory: MetricCategory
    @State private var position: PlayerPositionGroup
    @State private var sortDescending: Bool
    @State private var isSearching = false
    @State private var searchText = ""

    init(
        metricLabel: String,
        metricCategory: MetricCategory,
        players: [Player],
        season: Int?,
        position: PlayerPositionGroup = .all,
        viewModel: DashboardViewModel? = nil
    ) {
        self.players = players
        self.season = season
        self.viewModel = viewModel
        _metricLabel = State(initialValue: metricLabel)
        _metricCategory = State(initialValue: metricCategory)
        _position = State(initialValue: position)
        // Best first for the active metric (descending for higher-is-better,
        // ascending for TOV% and Fouls/100).
        _sortDescending = State(initialValue: DashboardViewModel.defaultSortDescending(label: metricLabel, category: metricCategory))
    }

    /// Every metric this cohort carries, one per label, in registry order.
    private var cohortMetrics: [Metric] {
        var seen = Set<String>()
        let present = players
            .filter { position.includes($0) }
            .flatMap(\.metrics)
            .filter { BasketballMetricRegistry.isSupported($0, by: position) }
        return BasketballMetricRegistry.sorted(present).filter { seen.insert($0.label).inserted }
    }

    private func pickerOptions(_ kind: MetricKind) -> [StatPickerMenu.Option] {
        let labels = cohortMetrics
            .filter { BasketballMetricRegistry.definition(for: $0.label, category: $0.category)?.kind == kind }
            .map(\.label)
        return kind == .advanced
            ? StatPickerMenu.Option.categorized(labels, selected: metricLabel)
            : labels.map { .init(id: $0, label: $0, isSelected: $0 == metricLabel) }
    }

    private func select(_ option: StatPickerMenu.Option) {
        guard let metric = cohortMetrics.first(where: { $0.label == option.id }) else { return }
        metricLabel = metric.label
        metricCategory = metric.category
        sortDescending = DashboardViewModel.defaultSortDescending(label: metric.label, category: metric.category)
    }

    private var rankedPlayers: [Player] {
        let sorted = players
            .filter { player in
                position.includes(player)
                    && player.metrics.contains { $0.label == metricLabel && $0.category == metricCategory }
            }
            .sorted(
                by: DashboardViewModel.metricComparator(
                    label: metricLabel,
                    category: metricCategory,
                    descending: sortDescending,
                    acrossCohorts: position == .all
                )
            )
        // Same rule as the Stats board: small samples stay listed, below.
        return sorted.filter { !isSmallSample($0) } + sorted.filter(isSmallSample)
    }

    private func isSmallSample(_ player: Player) -> Bool {
        guard let metric = player.metrics.first(where: { $0.label == metricLabel && $0.category == metricCategory })
        else { return false }
        return viewModel.map { !$0.isQualified(player, metric: metric) } ?? metric.isSmallSample
    }

    var body: some View {
        VStack(spacing: 0) {
            HardwoodTabs(
                tabs: PlayerPositionGroup.allCases.map(\.rawValue),
                selected: Binding(
                    get: { position.rawValue },
                    set: { raw in
                        if let next = PlayerPositionGroup.allCases.first(where: { $0.rawValue == raw }) {
                            position = next
                        }
                    }
                )
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Position")
            .padding(.top, 8)

            controlRow
            if isSearching {
                HStack(spacing: 8) {
                    SearchField(text: $searchText, focusOnAppear: true)
                    Button("Cancel") {
                        isSearching = false
                        searchText = ""
                    }
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.court)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            ScrollView {
                list
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                Color.clear.frame(height: 88)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(HardwoodPalette.canvas.ignoresSafeArea())
        .navigationTitle([metricLabel, season.map { SeasonLabel.text($0) }].compactMap { $0 }.joined(separator: " · "))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            StatPickerMenu(
                advanced: pickerOptions(.advanced),
                standard: pickerOptions(.traditional),
                activeLabel: metricLabel,
                onSelectAdvanced: select,
                onSelectStandard: select
            )
            SortDirectionButton(descending: sortDescending, statLabel: metricLabel) {
                sortDescending.toggle()
            }
            Spacer(minLength: 0)
            Button {
                isSearching.toggle()
                if !isSearching { searchText = "" }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HardwoodChip(systemImage: "magnifyingglass", isActive: isSearching)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search players or teams")
        }
        .padding(.horizontal, 12)
        .frame(height: HardwoodControl.height + 2)
        .padding(.top, HardwoodGeo.controlRowGap)
    }

    private var list: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ranked = Array(rankedPlayers.enumerated()).filter { query.isEmpty || $0.element.matchesSearch(query) }
        return LazyVStack(spacing: 0) {
            if rankedPlayers.isEmpty {
                ContentUnavailableView {
                    Label("No rankings found", systemImage: "chart.bar")
                } description: {
                    Text("No \(position == .all ? "" : position.noun + " ")players have \(metricLabel) for this season.")
                }
                .padding(.vertical, 24)
            } else {
                Button {
                    sortDescending.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    LeaderboardTableHeader(sortDescending: sortDescending, sortLabel: metricLabel)
                }
                .buttonStyle(.plain)
                if ranked.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.vertical, 24)
                }
                ForEach(ranked, id: \.element.id) { index, player in
                    NavigationLink(value: player) {
                        LeaderboardTableRow(
                            rank: index + 1,
                            player: player,
                            metricLabel: metricLabel,
                            metricCategory: metricCategory,
                            volume: viewModel?.volumeCaption(for: player, category: metricCategory)
                                ?? player.volumeCaption(for: metricCategory),
                            isSmallSample: isSmallSample(player)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        MetricRankingView(metricLabel: "PPG", metricCategory: .scoring, players: SampleData.players, season: 2026)
    }
}
#endif
