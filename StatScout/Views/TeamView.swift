import SwiftUI

struct TeamView: View {
    @EnvironmentObject private var store: StoreService
    let team: String
    /// Seed roster for previews and tests, used only when there is no view
    /// model. The live roster is derived, see `players`.
    var seedPlayers: [Player] = []
    /// Seed season for previews and tests, used only when there is no view
    /// model. See `displaySeason`.
    var seedSeason: Int? = nil
    var viewModel: DashboardViewModel? = nil
    @State private var selectedTab: TeamTab = .advanced
    @State private var searchText = ""
    @State private var isSearching = false
    // The roster opens on On-Off, the same all-in-one number the Stats board
    // opens on, and offers the same controls: position tabs, the stat picker,
    // the sort arrow, search and the View menu.
    @State private var rosterStat = "On-Off"
    @State private var rosterPosition: PlayerPositionGroup = .all
    @State private var sortDescending = true
    @State private var lastDefaultedSortKey: String? = nil
    @State private var showingTrial = false
    @State private var trialTrigger: PaywallTrigger?
    /// Without a view model (previews, tests) the roster keeps its own.
    @State private var localQualifierLevel: DashboardViewModel.QualifierLevel = .all
    @State private var rosterMode: RosterMode = .season
    @State private var rosterWindow: RecentWindow = .twoWeeks

    enum TeamTab: String, CaseIterable {
        case advanced = "Advanced"
        case standard = "Standard"
        case roster = "Roster"
    }

    enum RosterMode: String, CaseIterable, Identifiable {
        case season = "Season"
        case recent = "Recent"

        var id: String { rawValue }
    }

    /// The roster for the season and phase that are selected *right now*.
    ///
    /// This was a one-time array captured when the page was pushed. The nav-bar
    /// picker here moves `viewModel.selectedSeason`, and `leaguePlayers`
    /// followed it, but the rows, cards, category filters and sort metrics all
    /// kept reading the array from arrival: you picked 2024, the picker said
    /// 2024, the league context was 2024, and the roster underneath was still
    /// whichever season you happened to open the page in.
    private var players: [Player] {
        guard let viewModel else { return seedPlayers }
        return viewModel.players(forTeam: team)
    }

    private var displaySeason: Int {
        viewModel?.selectedSeason
            ?? seedSeason
            ?? seedPlayers.compactMap(\.season).max()
            ?? StatScoutSeason.bundledNewest
    }

    private var leaguePlayers: [Player] {
        viewModel?.seasonPlayers ?? []
    }

    /// The phase the whole page is reading. Every roster number already comes
    /// from `seasonPlayers`, which is filtered by it; the cards need it too so
    /// their rolling windows come from the same half of the year.
    private var displayPhase: SeasonPhase {
        viewModel?.selectedPhase ?? .regular
    }

    /// Every metric the roster carries, one per label, in the registry's
    /// order: the list the Stats board's picker draws from, for this team.
    private var rosterMetrics: [Metric] {
        var seen = Set<String>()
        let present = players
            .filter { rosterPosition.includes($0) }
            .flatMap(\.metrics)
            .filter { BasketballMetricRegistry.isSupported($0, by: rosterPosition) }
        return BasketballMetricRegistry.sorted(present).filter { seen.insert($0.label).inserted }
    }

    private func rosterLabels(_ kind: MetricKind) -> [String] {
        rosterMetrics
            .filter { BasketballMetricRegistry.definition(for: $0.label, category: $0.category)?.kind == kind }
            .map(\.label)
    }

    private var sortMetric: (label: String, category: MetricCategory)? {
        let metrics = rosterMetrics
        let pick = metrics.first { $0.label == rosterStat }
            ?? metrics.first { $0.label == "On-Off" }
            ?? metrics.first
        return pick.map { ($0.label, $0.category) }
    }

    private var sortLabel: String {
        sortMetric?.label ?? "Overall"
    }

    private var rowDisplayMetric: (label: String?, category: MetricCategory?) {
        if let m = sortMetric { return (m.label, m.category) }
        // "All" is the whole roster at once, every category together, so there
        // is no one metric that means the same thing down the column. Each row
        // shows its own overall percentile instead.
        return (nil, nil)
    }

    private func rawValue(_ player: Player) -> Double? {
        guard let m = sortMetric,
              let metric = player.metrics.first(where: { $0.label == m.label && $0.category == m.category })
        else { return nil }
        return DashboardViewModel.rawNumeric(metric.value)
    }

    private func fallbackPercentile(_ player: Player) -> Int {
        player.overallPercentile
    }

    private func recentForm(_ player: Player) -> RecentForm? {
        viewModel?.recentForm(for: player.playerId, window: rosterWindow)
    }

    private func recentKey() -> String? {
        guard let label = sortMetric?.label else { return nil }
        return RecentMetricKey.key(for: label)
    }

    private func recentValue(_ player: Player) -> Double? {
        guard let key = recentKey() else { return nil }
        return recentForm(player)?.metrics[key]
    }

    private func recentDelta(_ player: Player) -> Double? {
        guard let key = recentKey() else { return nil }
        return recentForm(player)?.delta[key]
    }

    private func recentValueText(_ player: Player) -> String {
        guard let label = sortMetric?.label, let value = recentValue(player) else {
            return "-"
        }
        return RecentMetricKey.format(value, label: label)
    }

    private var hasRecentData: Bool {
        viewModel?.recentFormByWindow[rosterWindow.rawValue] != nil
    }

    private var isRosterRecent: Bool {
        rosterMode == .recent && store.isPro && supportsRecent
    }

    /// Recent form exists for the newest two seasons only: the rolling windows
    /// are no longer kept for older ones, so every Recent control on this screen
    /// is hidden (not locked) on a historical one. Falls back to the bundled
    /// season when there is no view model, which is the previews-and-tests path.
    private var supportsRecent: Bool {
        viewModel.map { $0.supportsRecentForm(displaySeason) }
            ?? (displaySeason == StatScoutSeason.bundledNewest)
    }

    private var filteredPlayers: [Player] { rosterBoard(search: searchText) }

    /// Each player's place on the unsearched roster while a search narrows
    /// it, the Stats board's rule. Nil when nothing is being searched.
    private var rosterRanks: [Player.ID: Int]? {
        guard !searchText.isEmpty else { return nil }
        return Dictionary(rosterBoard(search: "").enumerated().map { ($1.id, $0 + 1) },
                          uniquingKeysWith: { first, _ in first })
    }

    private func rosterBoard(search searchText: String) -> [Player] {
        let bySearch = searchText.isEmpty ? players : players.filter {
            $0.matchesSearch(searchText, includingTeam: false)
                || $0.displayPosition.localizedCaseInsensitiveContains(searchText)
        }
        let byPosition = bySearch.filter { rosterPosition.includes($0) }
        let byQualifier = byPosition.filter { isQualified($0) }
        if isRosterRecent, sortMetric != nil {
            return byQualifier.filter { recentValue($0) != nil }.sorted {
                let first = recentValue($0) ?? 0
                let second = recentValue($1) ?? 0
                return sortDescending ? first > second : first < second
            }
        }
        guard let sortMetric else {
            return byQualifier.sorted {
                sortDescending ? fallbackPercentile($0) > fallbackPercentile($1) : fallbackPercentile($0) < fallbackPercentile($1)
            }
        }
        // A roster mixes guards, forwards and centers, whose percentiles come
        // from different pools: order by the value itself. Small samples sit
        // below the rest, the Stats board's rule, so a cameo never leads.
        let sorted = byQualifier.sorted(by: DashboardViewModel.metricComparator(
            label: sortMetric.label,
            category: sortMetric.category,
            descending: sortDescending,
            acrossCohorts: true
        ))
        return sorted.filter { !isSmallSample($0) } + sorted.filter(isSmallSample)
    }

    /// The Stats board's qualifier, shared so the two never disagree.
    private var qualifierLevel: DashboardViewModel.QualifierLevel {
        get { viewModel?.qualifierLevel ?? localQualifierLevel }
        nonmutating set {
            if let viewModel { viewModel.qualifierLevel = newValue } else { localQualifierLevel = newValue }
        }
    }

    /// Under the playing-time bar for the ranked metric.
    private func isSmallSample(_ player: Player) -> Bool {
        guard let sortMetric,
              let metric = player.metrics.first(where: { $0.label == sortMetric.label && $0.category == sortMetric.category })
        else { return false }
        return viewModel.map { !$0.isQualified(player, metric: metric) } ?? metric.isSmallSample
    }

    private func isQualified(_ player: Player) -> Bool {
        switch qualifierLevel {
        case .all:
            return true
        case .qualified:
            return DashboardViewModel.hasQualifyingMetric(player, in: sortMetric?.category)
        }
    }

    /// "56-26 · 2nd in the East · Power +5.3, 2nd": where the team stands,
    /// the first thing a fan wants from a team page.
    private func seasonSummary(_ viewModel: DashboardViewModel) -> String? {
        let abbr = normalizedTeamAbbreviation(team)
        let table = viewModel.standings
        guard let row = table[abbr], row.games > 0 else { return nil }
        var parts = [row.record]
        if let conference = TeamsView.conferences.first(where: { $0.teams.contains(abbr) }),
           let seed = StandingsRow.ordered(conference.teams.compactMap { table[$0] }).firstIndex(where: { $0.team == abbr }) {
            parts.append("\((seed + 1).ordinalString) in the \(conference.name.hasPrefix("East") ? "East" : "West")")
        }
        if let rating = viewModel.teamRating(abbr) {
            parts.append("Power \(TeamRating.signed(rating.rating)), \(rating.rank.ordinalString)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let viewModel {
                    DataFreshnessView(
                        viewModel: viewModel,
                        season: displaySeason,
                        phase: displayPhase
                    )
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    if displaySeason == viewModel.freeSeason, let summary = seasonSummary(viewModel) {
                        Text(summary)
                            .font(HardwoodType.bodyBold)
                            .foregroundStyle(HardwoodPalette.ink)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }
                    if displaySeason == viewModel.freeSeason {
                        TeamGameCard(viewModel: viewModel, team: team)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                        if displayPhase == .regular {
                            TeamSeasonGlance(viewModel: viewModel, team: team)
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                        }
                    }
                }
                tabSelector
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                switch selectedTab {
                case .advanced:
                    advancedContent
                case .standard:
                    standardContent
                case .roster:
                    rosterContent
                }

                StatGlossaryLink()
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                // Lets content scroll under the floating tab bar so the last
                // rows aren't trapped behind it - matches Dashboard.
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(HardwoodPalette.canvas.ignoresSafeArea())
        .refreshable {
            await viewModel?.load()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { teamSwitcherMenu }
            if let viewModel {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        navSeasonMenu(viewModel: viewModel)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        navSeasonMenu(viewModel: viewModel)
                    }
                }
            }
        }
        .onAppear { applyDefaultDirectionIfMetricChanged() }
        .onChange(of: rosterStat) { _, _ in
            applyDefaultDirectionIfMetricChanged()
        }
        .onChange(of: rosterPosition) { _, _ in
            applyDefaultDirectionIfMetricChanged()
        }
        // Season changes through the nav-bar menu rotate the roster data beneath
        // us; re-default the sort direction so the chip never displays a metric
        // the new season doesn't have.
        .onChange(of: displaySeason) { _, _ in
            applyDefaultDirectionIfMetricChanged()
        }
        // Same reasoning for the phase: a playoff roster carries a different set
        // of metrics than the regular season's, so the sort chip has to re-resolve.
        .onChange(of: viewModel?.selectedPhase) { _, _ in
            applyDefaultDirectionIfMetricChanged()
        }
        .task(id: "\(rosterMode.rawValue)-\(rosterWindow.rawValue)-\(displaySeason)-\(viewModel?.selectedPhase.rawValue ?? "")-\(store.isPro)-\(viewModel?.freshnessRevision ?? "none")") {
            guard isRosterRecent else { return }
            await viewModel?.loadRecentFormIfNeeded(window: rosterWindow)
        }
        .sheet(isPresented: $showingTrial) {
            TrialPitchSheet(trigger: .teamView)
        }
        .sheet(item: $trialTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }

    // MARK: - Tabs

    /// Mirrors the player profile's tab selector with equal-width court controls
    /// that swap the card content below. Two tabs: the team's percentile profile and
    /// its sortable roster.
    private var tabSelector: some View {
        HStack(spacing: 8) {
            ForEach(TeamTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(tab.rawValue)
                        .font(HardwoodType.smallBold)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .white : HardwoodPalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isSelected ? HardwoodPalette.court : HardwoodPalette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var advancedContent: some View {
        VStack(spacing: 12) {
            TeamRankingsCard(
                team: team,
                season: displaySeason,
                seasonPhase: displayPhase,
                players: players,
                leaguePlayers: leaguePlayers,
                loadRecent: loadRecent,
                freshnessRevision: viewModel?.freshnessRevision,
                freshnessStatus: viewModel?.freshnessStatus,
                supportsRecent: supportsRecent,
                onUpgradeTap: {
                    // Explicit tap, always answer it; the gate only caps
                    // automatic pop-ups.
                    showingTrial = true
                }
            )

        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    /// The league's rows for one window, for the team cards' Recent modes.
    private var loadRecent: ((RecentWindow) async -> [RecentForm])? {
        guard let viewModel else { return nil }
        let season = displaySeason
        let phase = displayPhase
        return { window in
            await viewModel.leagueRecentForm(window: window, season: season, phase: phase)
        }
    }

    private var standardContent: some View {
        TeamStandardCard(
            team: team,
            season: displaySeason,
            seasonPhase: displayPhase,
            players: players,
            leaguePlayers: leaguePlayers,
            loadRecent: loadRecent,
            supportsRecent: supportsRecent,
            onUpgradeTap: { showingTrial = true }
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var rosterContent: some View {
        VStack(spacing: 0) {
            rosterModePicker
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if isRosterRecent {
                HardwoodSegmented(
                    segments: RecentWindow.allCases.map {
                        .init(value: $0, label: $0.segmentLabel)
                    },
                    selection: $rosterWindow
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            HardwoodTabs(
                tabs: PlayerPositionGroup.allCases.map(\.rawValue),
                selected: Binding(
                    get: { rosterPosition.rawValue },
                    set: { raw in
                        if let next = PlayerPositionGroup.allCases.first(where: { $0.rawValue == raw }) {
                            rosterPosition = next
                        }
                    }
                )
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Position")
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if !players.isEmpty {
                sortControlsRow
                if isSearching || !searchText.isEmpty {
                    searchRow
                }
            }

            rosterSection
        }
    }

    private func applyDefaultDirectionIfMetricChanged() {
        let key = sortMetric.map { "\($0.category.rawValue)|\($0.label)" } ?? "-"
        guard key != lastDefaultedSortKey else { return }
        lastDefaultedSortKey = key
        sortDescending = DashboardViewModel.defaultSortDescending(
            label: sortMetric?.label,
            category: sortMetric?.category
        )
    }

    /// The Stats board's control row, item for item: stat picker and sort
    /// arrow on the left, search and View on the right.
    private var sortControlsRow: some View {
        HStack(spacing: 8) {
            BoardPickerStrip {
            StatPickerMenu(
                advanced: StatPickerMenu.Option.categorized(rosterLabels(.advanced), selected: sortMetric?.label),
                standard: rosterLabels(.traditional).map {
                    .init(id: $0, label: $0, isSelected: $0 == sortMetric?.label)
                },
                activeLabel: sortLabel,
                onSelectAdvanced: { rosterStat = $0.id },
                onSelectStandard: { rosterStat = $0.id }
            )
            SortDirectionButton(descending: sortDescending, statLabel: sortLabel) {
                sortDescending.toggle()
            }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isSearching.toggle() }
                if !isSearching { searchText = "" }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HardwoodChip(systemImage: "magnifyingglass", isActive: isSearching || !searchText.isEmpty)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search players")

            rosterViewMenu
                .fixedSize()
        }
        .padding(.trailing, 12)
        .frame(height: HardwoodControl.height + 2)
        .padding(.top, HardwoodGeo.controlRowGap)
    }

    @ViewBuilder
    private var rosterModePicker: some View {
        if supportsRecent {
            HardwoodSegmented(
                segments: RosterMode.allCases.map {
                    .init(value: $0, label: $0.rawValue, isLocked: !store.isPro && $0 == .recent)
                },
                selection: $rosterMode,
                onLockedTap: { _ in trialTrigger = .recentForm }
            )
        }
    }

    /// The Stats board's View menu, less what a single roster has no use for
    /// (conference, Best & Worst).
    private var rosterViewMenu: some View {
        Menu {
            Section("Qualifier") {
                ForEach(DashboardViewModel.QualifierLevel.allCases) { level in
                    Button {
                        qualifierLevel = level
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        let title = "\(level.rawValue) · \(level.description)"
                        if level == qualifierLevel {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }
        } label: {
            HardwoodChip(
                title: "View",
                systemImage: "slider.horizontal.3",
                trailing: .chevron,
                isActive: qualifierLevel != .all
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("View options")
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            SearchField(text: $searchText, focusOnAppear: true, prompt: "Search roster")
            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = false
                    searchText = ""
                }
            }
            .font(HardwoodType.small)
            .foregroundStyle(HardwoodPalette.court)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var rosterSection: some View {
        VStack(spacing: 0) {
            if players.isEmpty {
                emptyStateView(
                    icon: "person.2.slash",
                    title: "No players tracked",
                    description: "No players are tracked for \(teamFullName(team)) in the \(SeasonLabel.text(displaySeason)) season."
                )
            } else if isRosterRecent && !hasRecentData {
                if let error = viewModel?.recentFormError {
                    VStack(spacing: 10) {
                        Text(error)
                            .font(HardwoodType.small)
                            .foregroundStyle(HardwoodPalette.inkSecondary)
                        Button("Try Again") {
                            Task { await viewModel?.loadRecentFormIfNeeded(window: rosterWindow) }
                        }
                        .font(HardwoodType.smallBold)
                        .foregroundStyle(HardwoodPalette.court)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.75)
                        Text("Loading the \(rosterWindow.prose)…")
                            .font(HardwoodType.small)
                            .foregroundStyle(HardwoodPalette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else if filteredPlayers.isEmpty && isRosterRecent && searchText.isEmpty {
                emptyStateView(
                    icon: "calendar.badge.clock",
                    title: "No recent games",
                    description: "No \(teamFullName(team)) player has \(sortLabel) over the \(rosterWindow.prose). Try Season or a longer window."
                )
            } else if filteredPlayers.isEmpty && searchText.isEmpty && qualifierLevel != .all {
                ContentUnavailableView {
                    Label("No players match these filters", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Qualified hides players under the playing-time minimum.")
                } actions: {
                    Button("Clear Filters") { qualifierLevel = .all }
                        .buttonStyle(.borderedProminent)
                        .tint(HardwoodPalette.court)
                }
                .padding(.vertical, 48)
            } else if filteredPlayers.isEmpty {
                emptyStateView(
                    icon: "magnifyingglass",
                    title: "No players found",
                    description: searchText.isEmpty
                        ? "No \(rosterPosition == .all ? "" : rosterPosition.noun + " ")players match this view. Try All or another position."
                        : "Try a different search term."
                )
            } else {
                Button {
                    sortDescending.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    LeaderboardTableHeader(
                        sortDescending: sortDescending,
                        sortLabel: isRosterRecent
                            ? "\(sortLabel) · \(rosterWindow.segmentLabel)"
                            : sortLabel
                    )
                }
                .buttonStyle(.plain)

                let ranks = rosterRanks
                ForEach(Array(filteredPlayers.enumerated()), id: \.element.id) { index, player in
                    NavigationLink(value: player) {
                        LeaderboardTableRow(
                            rank: ranks.map { $0[player.id] ?? 0 } ?? index + 1,
                            player: player,
                            metricLabel: rowDisplayMetric.label,
                            metricCategory: rowDisplayMetric.category,
                            trendDelta: isRosterRecent ? recentDelta(player) : nil,
                            trendDecimals: rowDisplayMetric.label.map {
                                RecentMetricKey.decimals(for: $0)
                            } ?? 3,
                            valueOverride: isRosterRecent ? recentValueText(player) : nil,
                            // Minutes beside the position, the Stats board's row.
                            volume: isRosterRecent ? nil : viewModel?.volumeCaption(for: player, category: rowDisplayMetric.category),
                            isSmallSample: !isRosterRecent && isSmallSample(player),
                            stripe: index + 1
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
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func emptyStateView(icon: String, title: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(description)
        }
        .padding(.vertical, 48)
    }

    /// Team name in the nav title doubles as a switcher menu - tap to jump to
    /// any other team without popping back to the Teams list.
    private var teamSwitcherMenu: some View {
        Menu {
            ForEach(allTeams, id: \.self) { abbr in
                NavigationLink(value: TeamDestination(abbr: abbr)) {
                    HStack {
                        Text(teamFullName(abbr))
                        if abbr == team {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(teamFullName(team))
                    .font(HardwoodType.bodyBold)
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Team")
        .accessibilityValue(teamFullName(team))
        .accessibilityHint("Switch to another team")
    }

    private static let allTeamAbbrs: [String] = nbaTeamAbbreviations

    private var allTeams: [String] {
        Self.allTeamAbbrs.sorted { teamFullName($0).localizedCompare(teamFullName($1)) == .orderedAscending }
    }

    /// Season *and* season type, the same one control the Stats / Trends / Teams
    /// bars carry. This was a season-only menu, which left the playoffs
    /// unreachable from the one Teams screen most sessions actually see: every
    /// number on this page is filtered by `selectedPhase`, and the Teams tab
    /// pushes straight into your favorite team on first visit, so the phase
    /// control back on the list was never passed through.
    private func navSeasonMenu(viewModel: DashboardViewModel) -> some View {
        SeasonPhasePicker(
            // A single team page, so no All Time - see
            // `seasonsExcludingAllTime` for why a career row can't be
            // attributed to one franchise.
            seasons: viewModel.seasonsExcludingAllTime,
            selectedSeason: viewModel.selectedSeason,
            selectedPhase: viewModel.selectedPhase,
            isSeasonLocked: { viewModel.isSeasonLocked($0) },
            onSelectSeason: { season in
                if viewModel.isSeasonLocked(season) {
                    trialTrigger = .lockedSeason(season)
                } else {
                    viewModel.selectSeason(season)
                }
            },
            onSelectPhase: { viewModel.selectedPhase = $0 }
        ) {
            // No glyph and the short year alone: the team name in the principal
            // slot is long ("Portland Trail Blazers"), and spelling the phase out
            // here as well tipped the bar into sweeping the trailing item into a
            // "..." overflow. The pill still says which phase it is, just in the
            // shortest form that reads as a season type.
            HardwoodNavPill(
                title: SeasonLabel.text(viewModel.selectedSeason)
                    + (viewModel.selectedPhase == .playoffs ? " · Playoffs" : "")
            )
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TeamView(
            team: "BOS",
            seedPlayers: SampleData.players.filter { $0.team == "BOS" },
            seedSeason: 2026
        )
    }
}
#endif
