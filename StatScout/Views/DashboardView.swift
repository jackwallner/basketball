import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    var boardBindings: StatsBoardBindings? = nil
    @State private var showingAbout = false
    @State private var paywallTrigger: PaywallTrigger?
    @State private var isSearching = false

    var body: some View { let _ = TabProbe.hit("DashboardView") // TABPROBE
        ZStack {
            VStack(spacing: 0) {
                unifiedControlBar
                if !viewModel.players.isEmpty {
                    activeSortChip
                    if isSearching || !viewModel.searchText.isEmpty {
                        searchRow
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !viewModel.players.isEmpty,
                           isSearching || !viewModel.searchText.isEmpty {
                            teamResults
                        }
                        leaderboardSection
                        if !viewModel.players.isEmpty {
                            coverageNote
                            aboutFooter
                        }
                        // Lets the leaderboard scroll through the floating tab bar instead of
                        // stopping above it with canvas gray showing underneath the glass pill.
                        Color.clear.frame(height: 88)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await viewModel.load()
                }
            }

            if viewModel.isLoading && viewModel.players.isEmpty {
                loadingCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HardwoodPalette.canvas)
        .sheet(isPresented: $showingAbout) {
            NavigationStack {
                AboutView(
                    lastUpdated: viewModel.lastUpdated,
                    dataCoverage: viewModel.dataCoverage
                )
                    .navigationTitle("About")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingAbout = false }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }

    /// Why a season, or the live season so far, shows fewer advanced metrics,
    /// plus what the dimmed rows and the bars mean. Absent for seasons with the
    /// full set, so it never becomes furniture the eye learns to skip.
    private var coverageNoteText: String? {
        let isLive = viewModel.selectedSeason == viewModel.freeSeason && viewModel.selectedPhase == .regular
        let pending = isLive ? MetricCoverage.pendingNote(
            category: nil,
            shotsStatus: viewModel.dataFreshness?.shotsStatus,
            playByPlayStatus: viewModel.dataFreshness?.playByPlayStatus
        ) : nil
        let noun = viewModel.selectedPosition.noun
        let cohort = isLive ? "every \(noun) with a line this season" : "every qualified \(noun)"
        let minimum = viewModel.qualifierLevel == .all
            ? "Dimmed rows are under the playing-time minimum."
            : "Players under the playing-time minimum are hidden; View shows them."
        let ruler = viewModel.selectedPosition == .all
            ? "Bars show each player's percentile within his own position group."
            : "Bars show the percentile among \(cohort)."
        let legend = isLive ? "\(ruler) \(minimum)" : ruler
        return [
            MetricCoverage.note(for: viewModel.selectedSeason, phase: viewModel.selectedPhase),
            pending,
            legend,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    @ViewBuilder
    private var coverageNote: some View {
        if let note = coverageNoteText {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(note)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(HardwoodType.micro)
            .foregroundStyle(HardwoodPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }

    private var aboutFooter: some View {
        VStack(spacing: 8) {
            if !store.isPro {
                Button(action: { paywallTrigger = store.defaultUpgradeTrigger }) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                        Text(store.upgradeCTALabel)
                            .font(HardwoodType.micro)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(HardwoodPalette.court)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Button(action: { showingAbout = true }) {
                Text("About StatScout")
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private var unifiedControlBar: some View {
        VStack(spacing: 8) {
            if (viewModel.isLoading || viewModel.isHistoricalLoading) && !viewModel.players.isEmpty {
                loadingStatusBar
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 12)
            }

            positionSelector
        }
        .padding(.top, 8)
    }

    /// Position group is this app's metric-category control, the same tier as
    /// baseball's Hitting / Pitching / Fielding / Running header, so it uses the
    /// same underlined tabs. It used to be a row of filled rounded-rects 36pt
    /// tall, which is the page-level-switch shape at a fifth distinct control
    /// height, so the one control that decides what the whole screen is about
    /// looked like nothing else in the app.
    private var positionSelector: some View {
        HardwoodTabs(
            tabs: PlayerPositionGroup.allCases.map(\.rawValue),
            selected: Binding(
                get: { viewModel.selectedPosition.rawValue },
                set: { raw in
                    guard let next = PlayerPositionGroup.allCases.first(where: { $0.rawValue == raw }),
                          next != viewModel.selectedPosition else { return }
                    viewModel.selectedPosition = next
                }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Position")
    }

    private var activeSortChip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let boardBindings {
                        StatsBoardStatPicker(
                            viewModel: viewModel,
                            bindings: boardBindings
                        )
                    }
                    SortDirectionButton(
                        descending: viewModel.sortDescending,
                        statLabel: viewModel.currentSortMetric ?? viewModel.sortLabel
                    ) {
                        viewModel.toggleSortDirection()
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 2)
                .padding(.vertical, 1)
            }
            .scrollBounceBehavior(.basedOnSize)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            searchToggle
            if let boardBindings {
                StatsViewMenu(
                    viewModel: viewModel,
                    board: boardBindings.$board
                )
            }
        }
        .padding(.trailing, 12)
        .frame(height: HardwoodControl.height + 2)
        .padding(.top, HardwoodGeo.controlRowGap)
    }

    /// True while the search row is open or a query is still applied, so the
    /// chip stays visually "on" and the user knows results are filtered.
    private var isActiveSearch: Bool { isSearching || !viewModel.searchText.isEmpty }

    // Magnifier that expands the inline search row. When a query is active it
    // stays visually "on" so the user knows results are filtered.
    private var searchToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isSearching.toggle() }
            if !isSearching { viewModel.searchText = "" }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HardwoodChip(systemImage: "magnifyingglass", isActive: isActiveSearch)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search players or teams")
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            SearchField(text: $viewModel.searchText, focusOnAppear: true)
            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = false
                    viewModel.searchText = ""
                }
            }
            .font(HardwoodType.small)
            .foregroundStyle(HardwoodPalette.court)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var sortHeader: some View {
        Button {
            viewModel.toggleSortDirection()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            LeaderboardTableHeader(
                sortDescending: viewModel.sortDescending,
                sortLabel: viewModel.currentSortMetric ?? viewModel.sortLabel
            )
        }
        .buttonStyle(.plain)
    }

    /// Teams matching the search, above the filtered player rows.
    ///
    /// Searching used to only ever narrow the list of players. Someone typing
    /// "knicks" is usually after New York, so the team itself is a result: one
    /// tap to the team page, with the roster still filtered underneath if that's
    /// what they wanted.
    @ViewBuilder
    private var teamResults: some View {
        let teams = viewModel.searchedTeams
        if !teams.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(teams.prefix(3).enumerated()), id: \.element) { index, team in
                    if index > 0 {
                        Rectangle()
                            .fill(HardwoodPalette.divider)
                            .frame(height: HardwoodGeo.hairline)
                    }
                    NavigationLink(value: TeamDestination(abbr: team)) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(NBATeamColor.color(team))
                                    .frame(width: 28, height: 28)
                                Text(displayTeamAbbr(team))
                                    .font(HardwoodType.micro)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            Text(teamFullName(team))
                                .font(HardwoodType.bodyBold)
                                .foregroundStyle(HardwoodPalette.ink)
                            Text("TEAM PAGE")
                                .font(HardwoodType.micro)
                                .foregroundStyle(HardwoodPalette.inkTertiary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(HardwoodPalette.inkTertiary)
                        }
                        .padding(.horizontal, HardwoodGeo.padCard)
                        .frame(height: HardwoodGeo.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(HardwoodPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                    .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var leaderboardSection: some View {
        VStack(spacing: 0) {
            if viewModel.leaderboard.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView {
                    Label("No players found", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search term.")
                }
                .padding(.vertical, 24)
                .frame(minHeight: 200)
            } else if let errorMessage = viewModel.errorMessage, viewModel.leaderboard.isEmpty {
                // An offline first run is not a data error. When the live season
                // is newer than the bundle there is genuinely nothing to show
                // until one update lands, and saying "Data Error" beside a
                // warning triangle blamed the stats for the phone's signal.
                let isOffline = viewModel.lastFailureWasConnectivity
                ContentUnavailableView {
                    Label(
                        isOffline ? "No connection" : "Data Error",
                        systemImage: isOffline ? "wifi.exclamationmark" : "exclamationmark.triangle"
                    )
                } description: {
                    Text(isOffline
                         ? "The current season needs a connection for its first update. Once it has loaded, your saved stats are here offline."
                         : errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HardwoodPalette.inkTertiary)
                }
                .padding(.vertical, 24)
                .frame(minHeight: 200)
            } else if viewModel.leaderboard.isEmpty && viewModel.isHistoricalLoading {
                // Season history is fetched on demand, so the first tap on a past
                // season (or on All Time) arrives before its rows do. This
                // used to fall through to "No player data is available", which
                // reads as a permanent answer to a temporary state - the board
                // filled in seconds later, by which point the user had believed
                // the app.
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading \(SeasonLabel.text(viewModel.selectedSeason))…")
                        .font(HardwoodType.small)
                        .foregroundStyle(HardwoodPalette.inkSecondary)
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if viewModel.leaderboard.isEmpty && !viewModel.isLoading {
                let hasSeasonData = !viewModel.seasonPlayers.isEmpty
                // A live season newer than the bundle (the day 2026-27 publishes)
                // has no bundled rows, and a snapshot baked into a build is stale
                // by the time anyone installs it. So a first run with no
                // connection genuinely has nothing here, and says so - "No
                // player data is available for the 2026-27 season" reads as a
                // verdict on the season rather than on the network, and sent
                // people looking for a refresh control that would not have
                // helped.
                let needsFirstConnection = !hasSeasonData
                    && viewModel.selectedSeason == viewModel.freeSeason
                    && viewModel.lastFetchFailed
                ContentUnavailableView {
                    Label(
                        needsFirstConnection
                            ? "Connect to load \(SeasonLabel.text(viewModel.selectedSeason))"
                            : (hasSeasonData ? "No matching metrics" : "No players yet"),
                        systemImage: needsFirstConnection ? "wifi.exclamationmark" : "basketball"
                    )
                } description: {
                    if needsFirstConnection {
                        Text("The current season needs a connection for its first update. Once it has loaded, your saved stats are here offline.")
                    } else {
                        Text(hasSeasonData
                             ? "No metrics are available for \(viewModel.selectedPosition.rawValue) in \(SeasonLabel.text(viewModel.selectedSeason))."
                             : "No player data is available for the \(SeasonLabel.text(viewModel.selectedSeason)) season.")
                    }
                } actions: {
                    if needsFirstConnection {
                        Button("Try Again") {
                            Task { await viewModel.load() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HardwoodPalette.inkTertiary)
                    }
                }
                .padding(.vertical, 24)
                .frame(minHeight: 200)
            } else {
                sortHeader
                let sortMetric = viewModel.currentSortMetricForDisplay
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.leaderboard.enumerated()), id: \.element.id) { index, player in
                        NavigationLink(value: player) {
                            LeaderboardTableRow(
                                rank: index + 1,
                                player: player,
                                metricLabel: sortMetric.label,
                                metricCategory: sortMetric.category,
                                volume: viewModel.volumeCaption(for: player, category: sortMetric.category),
                                isSmallSample: isSmallSample(player, label: sortMetric.label, category: sortMetric.category)
                            )
                        }
                        .buttonStyle(.plain)
                    }
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
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func isSmallSample(_ player: Player, label: String?, category: MetricCategory?) -> Bool {
        guard let label,
              let metric = player.metrics.first(where: { $0.label == label && (category == nil || $0.category == category) })
        else { return false }
        return !viewModel.isQualified(player, metric: metric)
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView(value: min(max(viewModel.loadingProgress, 0), 1), total: 1)
                .progressViewStyle(.linear)
                .tint(HardwoodPalette.court)
            Text(viewModel.loadingMessage)
                .font(HardwoodType.bodyBold)
                .foregroundStyle(HardwoodPalette.ink)
            Text("\(Int(min(max(viewModel.loadingProgress, 0), 1) * 100))%")
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
        }
        .padding(22)
        .frame(maxWidth: 300)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        .padding(.horizontal, 24)
    }

    private var loadingStatusBar: some View {
        HStack(spacing: 10) {
            ProgressView(value: min(max(viewModel.loadingProgress, 0), 1), total: 1)
                .progressViewStyle(.linear)
                .tint(HardwoodPalette.court)
                .frame(maxWidth: .infinity)
            Text(viewModel.loadingMessage)
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(HardwoodPalette.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DashboardView(viewModel: DashboardViewModel())
            .environmentObject(StoreService.shared)
    }
}
#endif
