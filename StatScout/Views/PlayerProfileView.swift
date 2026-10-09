import SwiftUI

struct PlayerProfileView: View {
    @EnvironmentObject private var store: StoreService
    let player: Player
    let history: [Player]
    var allPlayers: [Player] = []
    /// The live season as the loaded data sees it, not as the calendar does.
    /// Drives the free-tier lock on the season menu and whether Recent form is
    /// offered at all, both of which have to agree with the rest of the app
    /// once a new season is named but hasn't been ingested yet.
    var currentSeason: Int = StatScoutSeason.bundledNewest
    /// Seasons Recent form is offered for, from
    /// `DashboardViewModel.recentFormSeasons`. Nil means "just `currentSeason`",
    /// which is the previews-and-tests path.
    var recentFormSeasons: [Int]?
    var isHistoricalLoading = false
    var hasLoadedHistorical = true
    var historicalLoadingMessage = "Loading past seasons…"
    var historicalLoadingProgress = 0.12
    var loadHistorical: (() async -> Void)?
    /// This player's rolling windows (1, 2 and 4 weeks) from the league
    /// rollup. Both recent-form cards on this page read them, so the percentile
    /// card and the standard line answer "last 2 weeks" with the same games.
    /// (playerId, season, phase). The phase is part of the request, not a
    /// post-filter.
    var fetchRecentForm: ((Int, Int, SeasonPhase) async throws -> [RecentForm])?
    /// Shared freshness state from the tab root. Optional keeps previews and
    /// standalone tests lightweight while production profiles share one cache
    /// revision with Trends and Teams.
    var freshnessViewModel: DashboardViewModel? = nil
    var comparisonCatalog: ComparisonCatalog?
    @State private var showPercentileInfo = false
    @State private var selectedTab: PlayerStatTab = {
        #if DEBUG
        if ScreenshotRoute.current == .yearCompare { return .yearCompare }
        #endif
        return .advanced
    }()
    @State private var selectedPercentileSeason: Int? = nil
    @State private var paywallTrigger: PaywallTrigger?
    @State private var showingPlayerPicker = false
    @State private var comparisonRoute: ComparisonRoute?
    // Contextual trial pitches (compare, recent form, year compare, first-open)
    // all route through the low-friction TrialPitchSheet - its CTA starts the
    // yearly trial directly. PaywallView stays for the deliberate upsell card.
    @State private var trialPitchTrigger: PaywallTrigger?
    @State private var formDisplayMode: FormDisplayMode = .season
    @State private var recentWindow: RecentWindow = .twoWeeks
    /// The player's rolling rows by window length.
    @State private var recentForms: [Int: RecentForm] = [:]
    /// "<playerId>-<season>-<phase>" the loaded rows belong to, so two cards
    /// asking for the same season share one fetch.
    @State private var recentFormsKey: String?
    @State private var recentLoading = false
    @State private var recentLoadingKey: String?
    @State private var recentLoadError: String?
    @State private var recentCurves: LeaguePercentileCurves?
    @State private var standardMode: FormDisplayMode = .season
    @State private var standardWindow: RecentWindow = .twoWeeks
    @State private var favorites = FavoritesStore.shared

    private let profileOpenCountKey = "profileOpenCount"

    enum FormDisplayMode: String, CaseIterable {
        case season = "Season"
        case recent = "Recent"
        case both = "Both"
    }

    enum PlayerStatTab: String, CaseIterable {
        case advanced = "Advanced"
        case standard = "Standard"
        case yearCompare = "Year Compare"
    }

    private var availablePercentileSeasons: [Int] {
        let fromHistory = phaseHistory.compactMap(\.season)
        var set = Set(fromHistory)
        if let s = player.season { set.insert(s) }
        return Array(set).sorted(by: >)
    }

    private var activeSeason: Int? {
        selectedPercentileSeason ?? player.season
    }

    private var displayedPlayer: Player {
        guard let season = activeSeason else { return player }
        return phaseHistory.first { $0.season == season } ?? player
    }

    private var phaseHistory: [Player] {
        history.filter { $0.seasonPhase == player.seasonPhase }
    }

    /// The league cohort every percentile, curve and comparison on this page is
    /// measured against, for the season the selector is actually on.
    ///
    /// `allPlayers` is handed in once, for the season the profile was opened
    /// in. The season selector moved `displayedPlayer`'s numbers but not the
    /// field they were ranked inside, so a 2022 line was being scored against
    /// the 2026 league. Falls back to the injected array whenever there is no
    /// view model (previews and tests) or the selector hasn't moved.
    private var cohortPlayers: [Player] {
        guard let season = activeSeason,
              season != player.season,
              let freshnessViewModel
        else { return allPlayers }
        let cohort = freshnessViewModel.players(forSeason: season, phase: activePhase)
        return cohort.isEmpty ? allPlayers : cohort
    }

    /// The phase this profile is reading, for the game-log fetch and its cache
    /// key. The season selector moves within a phase, never across one.
    private var activePhase: SeasonPhase { player.seasonPhase }

    /// Season *and* phase.
    ///
    /// The profile is scoped to whichever phase you arrived from, and the two
    /// sets of numbers are wildly different - a rotation player's 41% from three
    /// over a season can be 12% over one playoff series, and "G" drops from
    /// eighty-two to five. A header that said only "2025-26" would not tell you
    /// which of the two you were reading, and the short playoff line would look
    /// like a catastrophic season.
    private var seasonLabel: String {
        guard let season = activeSeason else { return "-" }
        return SeasonLabel.text(season, phase: player.seasonPhase)
    }

    /// The advanced metrics, one section per category: every player is eligible
    /// for all six, and the section order is the order the categories are read
    /// in (Scoring first, Impact last).
    private var groupedMetrics: [(category: MetricCategory, metrics: [Metric])] {
        let advanced = displayedPlayer.metrics(kind: .advanced)
        let grouped = Dictionary(grouping: advanced, by: \.category)
        return MetricCategory.allCases.compactMap { category in
            guard let metrics = grouped[category], !metrics.isEmpty else { return nil }
            return (category: category, metrics: BasketballMetricRegistry.sorted(metrics))
        }
    }

    /// Players eligible for comparison: anyone in the league, sorted by overall
    /// percentile proximity to the current player so the closest match is first.
    private var comparablePlayers: [Player] {
        let pool = cohortPlayers.filter { $0.playerId != player.playerId }
        let mine = displayedPlayer.overallPercentile
        return pool.sorted { a, b in
            abs(a.overallPercentile - mine) < abs(b.overallPercentile - mine)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // `displayedPlayer`, so a player who changed teams wears the
                // team he actually played for in the season on screen rather
                // than the one from whichever season you opened the page in.
                PlayerIdentityStrip(
                    player: displayedPlayer,
                    profile: liveProfile
                )

                if let freshnessViewModel {
                    DataFreshnessView(
                        viewModel: freshnessViewModel,
                        season: activeSeason ?? player.season,
                        phase: activePhase
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                    if let season = activeSeason ?? player.season,
                       (recentFormSeasons ?? [currentSeason]).contains(season) {
                        PlayerLastGameCard(
                            viewModel: freshnessViewModel,
                            player: displayedPlayer,
                            season: season,
                            phase: activePhase
                        )
                        .padding(.horizontal, 12)
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
                case .yearCompare:
                    yearCompareContent
                }

                StatGlossaryLink()
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable {
            await refreshProfile()
        }
        .background(HardwoodPalette.canvas.ignoresSafeArea())
        // First-tap activation: profile renders immediately (no full-screen
        // paywall blocking it), and a native half-sheet TrialPitchSheet
        // floats on top with a "Maybe later" dismiss. PaywallGate caps this
        // at 2 per session so repeat taps don't re-prompt. The old full-page
        // .activation PaywallView was removed for being too intrusive - this
        // is the Vitals-style soft pitch that replaced it.
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { favoriteButton }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) { compareButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { favoriteButton }
                ToolbarItem(placement: .topBarTrailing) { compareButton }
            }
        }
        .sheet(isPresented: $showPercentileInfo) {
            PercentileInfoSheet()
        }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
        .sheet(isPresented: $showingPlayerPicker) {
            PlayerPickerSheet(players: comparablePlayers) { selected in
                comparisonRoute = ComparisonRoute(playerA: displayedPlayer, playerB: selected)
            }
        }
        .sheet(item: $trialPitchTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
        .navigationDestination(item: $comparisonRoute) { route in
            PlayerComparisonView(
                playerA: route.playerA,
                playerB: route.playerB,
                catalog: comparisonCatalog
            )
        }
        .onAppear {
            // Defer the first-impression pitch: a user verifying one stat from a
            // group chat shouldn't hit a subscription story before scrolling a
            // single row. Show it from the *second* profile open onward (Pro-only
            // controls - Recent Form, past seasons, Compare - still pitch on tap).
            let opens = UserDefaults.standard.integer(forKey: profileOpenCountKey) + 1
            UserDefaults.standard.set(opens, forKey: profileOpenCountKey)
            if !store.isPro, opens >= 2, PaywallGate.shared.shouldPresent(.playerScouting) {
                trialPitchTrigger = .playerScouting
            } else if opens >= 3 {
                // Third+ profile visit = engaged browsing. Never on a visit that
                // just showed the pitch, or the rating request lands the
                // moment the user dismisses a subscription sheet.
                ReviewPromptTracker.recordPositiveMoment()
            }
        }
    }

    /// Following a player is free. It's the signal the Trends tab and the
    /// review funnel read from, so gating it would suppress the thing we most
    /// want people to do.
    private var favoriteButton: some View {
        let isFavorite = favorites.isFavorite(playerId: player.playerId)
        return Button {
            favorites.toggleFavorite(playerId: player.playerId)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Color.yellow : .white)
        }
        .accessibilityLabel(isFavorite ? "Unfollow \(player.name)" : "Follow \(player.name)")
    }

    private var compareButton: some View {
        Button {
            if store.isPro {
                showingPlayerPicker = true
            } else {
                trialPitchTrigger = .playerComparison
            }
        } label: {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Compare with another player")
    }

    private var tabSelector: some View {
        HStack(spacing: 8) {
            advancedTabButton
            standardTabButton
            yearCompareTabButton
        }
    }

    private var advancedTabButton: some View {
        let isSelected = selectedTab == .advanced
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .advanced
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.advanced.rawValue)
                .font(HardwoodType.bodyBold)
                .foregroundStyle(isSelected ? .white : HardwoodPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? HardwoodPalette.court : HardwoodPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var standardTabButton: some View {
        let isSelected = selectedTab == .standard
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .standard
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.standard.rawValue)
                .font(HardwoodType.bodyBold)
                .foregroundStyle(isSelected ? .white : HardwoodPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? HardwoodPalette.court : HardwoodPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private var yearCompareTabButton: some View {
        let isSelected = selectedTab == .yearCompare
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .yearCompare
            }
            if store.isPro, !hasLoadedHistorical, !isHistoricalLoading {
                Task { await loadHistorical?() }
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(PlayerStatTab.yearCompare.rawValue)
                .font(HardwoodType.bodyBold)
                .foregroundStyle(isSelected ? .white : HardwoodPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? HardwoodPalette.court : HardwoodPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        }
        .buttonStyle(.plain)
    }

    /// Size, age and draft history, for the live season's page only: the
    /// profile table holds one row per player for the season being played.
    private var liveProfile: PlayerProfile? {
        freshnessViewModel?.profile(for: displayedPlayer)
    }

    /// What the page cannot say about this season: a metric the data predates,
    /// or a feed that is still catching up on the latest games.
    private var coverageNote: String? {
        guard let season = displayedPlayer.season else { return nil }
        var parts: [String] = []
        if let note = MetricCoverage.note(for: season, phase: displayedPlayer.seasonPhase) {
            parts.append(note)
        }
        if let freshnessViewModel,
           season == freshnessViewModel.freeSeason,
           displayedPlayer.seasonPhase == .regular,
           let pending = MetricCoverage.pendingNote(
            category: nil,
            shotsStatus: freshnessViewModel.dataFreshness?.shotsStatus,
            playByPlayStatus: freshnessViewModel.dataFreshness?.playByPlayStatus
           ) {
            parts.append(pending)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var advancedContent: some View {
        VStack(spacing: 12) {
            // No headline card. It printed the player's top advanced metric
            // (Pts/100 for a scorer) above a card whose first row is that same
            // metric, with the same value and the same colour - two identical
            // numbers a centimetre apart, and the top one had no bar to read it
            // against. Its season picker was a duplicate too: the percentile
            // card's own section bar carries one.
            percentileRankingsCard

            if let note = coverageNote {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            if !store.isPro {
                RecentFormCard(
                    player: player,
                    season: activeSeason ?? player.season ?? currentSeason,
                    leaguePlayers: cohortPlayers,
                    fetchRecentForm: fetchRecentForm,
                    freshnessRevision: freshnessViewModel?.freshnessRevision,
                    freshnessStatus: freshnessViewModel?.freshnessStatus,
                    onUpgradeTap: { trialPitchTrigger = .recentForm }
                )
                proUpsellCard
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var yearCompareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YEAR-OVER-YEAR")
                        .font(HardwoodType.micro)
                        .foregroundStyle(HardwoodPalette.inkTertiary)
                    Text("Compare how this profile changed by season.")
                        .font(HardwoodType.small)
                        .foregroundStyle(HardwoodPalette.inkSecondary)
                }
                Spacer()
                Button("Compare") {
                    selectedTab = .yearCompare
                    if store.isPro, !hasLoadedHistorical, !isHistoricalLoading {
                        Task { await loadHistorical?() }
                    }
                    if !store.isPro { trialPitchTrigger = .yearCompare }
                }
                .font(HardwoodType.smallBold)
                .buttonStyle(.bordered)
                .tint(HardwoodPalette.midnight)
            }
            if selectedTab == .yearCompare, store.isPro {
                yearCompareContent
            }
        }
        .padding(16)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard).stroke(HardwoodPalette.hairline, lineWidth: 0.5))
    }

    private var proUpsellCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.yellow)
                Text("StatScout+")
                    .font(HardwoodType.smallBold)
                    .foregroundStyle(HardwoodPalette.ink)
            }

            Text("Get the full scouting picture on \(player.name).")
                .font(HardwoodType.body)
                .foregroundStyle(HardwoodPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                proPerk("chart.line.uptrend.xyaxis", "Year-over-year trends across every metric")
                proPerk("person.2.fill", "Head-to-head comparisons vs any player")
                proPerk("calendar.badge.clock", "Every past season, not just this one")
                proPerk("arrow.down.circle.fill", "Saved offline - works on the road")
            }

            Button {
                paywallTrigger = store.defaultUpgradeTrigger
            } label: {
                HStack(spacing: 6) {
                    Text(store.paywallBlurCTA)
                        .font(HardwoodType.bodyBold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(HardwoodPalette.court)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if let subtext = store.paywallBlurSubtext {
                Text(subtext)
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    private func proPerk(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HardwoodPalette.court)
                .frame(width: 16)
            Text(text)
                .font(HardwoodType.small)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var standardContent: some View {
        VStack(spacing: 12) {
            standardStatsGridCard
            if let freshnessViewModel,
               let season = activeSeason ?? player.season,
               (recentFormSeasons ?? [currentSeason]).contains(season) {
                PlayerGameLogCard(
                    viewModel: freshnessViewModel,
                    player: displayedPlayer,
                    season: season,
                    phase: activePhase
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var yearCompareContent: some View {
        if store.isPro {
            if isHistoricalLoading {
                historicalLoadingCard
            } else if !hasLoadedHistorical, loadHistorical != nil {
                loadHistoricalCard
            } else if history.count < 2 {
                ContentUnavailableView {
                    Label("Not enough history", systemImage: "calendar.badge.clock")
                } description: {
                    Text("\(player.name) doesn't have multiple seasons of data to compare.")
                }
                .padding(.vertical, 48)
            } else {
                YearComparisonView(history: phaseHistory)
            }
        } else {
            YearComparePreview(playerName: player.name) {
                trialPitchTrigger = .yearCompare
            }
        }
    }

    private var historicalLoadingCard: some View {
        VStack(spacing: 14) {
            ProgressView(value: min(max(historicalLoadingProgress, 0), 1), total: 1)
                .progressViewStyle(.linear)
                .tint(HardwoodPalette.court)
            Text(historicalLoadingMessage)
                .font(HardwoodType.bodyBold)
                .foregroundStyle(HardwoodPalette.ink)
            Text("\(Int(min(max(historicalLoadingProgress, 0), 1) * 100))%")
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var loadHistoricalCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(HardwoodPalette.court)
            Text("Load past seasons")
                .font(HardwoodType.bodyBold)
                .foregroundStyle(HardwoodPalette.ink)
            Text("Year Compare loads historical data only when you need it.")
                .font(HardwoodType.body)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Load History") {
                Task { await loadHistorical?() }
            }
            .buttonStyle(.borderedProminent)
            .tint(HardwoodPalette.court)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func emptyStateCard(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(description)
            }
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Cards

    private var seasonMenu: some View {
        let seasons = availablePercentileSeasons
        return Group {
            if seasons.count > 1 {
                Menu {
                    ForEach(seasons, id: \.self) { season in
                        let isLocked = season != currentSeason && !store.isPro
                        Button {
                            if isLocked {
                                // Explicit tap on a locked season - always answer it.
                                // PaywallGate only caps automatic pop-ups.
                                trialPitchTrigger = .pastSeason
                            } else {
                                selectedPercentileSeason = season
                            }
                        } label: {
                            HStack {
                                Text(SeasonLabel.text(season))
                                if isLocked {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.yellow)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(seasonLabel)
                            .font(HardwoodType.micro)
                            .foregroundStyle(HardwoodPalette.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(HardwoodPalette.inkSecondary)
                    }
                }
                .menuOrder(.fixed)
            } else {
                Text(seasonLabel)
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var formModePicker: some View {
        HStack(spacing: 6) {
            ForEach(FormDisplayMode.allCases, id: \.self) { mode in
                Button {
                    formDisplayMode = mode
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(mode.rawValue)
                        .font(HardwoodType.smallBold)
                        .foregroundStyle(formDisplayMode == mode ? .white : HardwoodPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(formDisplayMode == mode ? HardwoodPalette.court : HardwoodPalette.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HardwoodPalette.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .padding(.vertical, 10)
        .background(HardwoodPalette.surfaceAlt)
    }

    private var percentileRankingsCard: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(
                title: "ADVANCED PERCENTILES",
                trailing: AnyView(
                    HStack(spacing: 4) {
                        seasonMenu
                        Button(action: { showPercentileInfo = true }) {
                            Text("ⓘ")
                                .font(HardwoodType.micro)
                                .foregroundStyle(HardwoodPalette.linkBlue)
                        }
                        .buttonStyle(.plain)
                    }
                )
            )

            // Recent mode only makes sense for the seasons the rollup still
            // holds, so on an older season it would always read "No games".
            if store.isPro, supportsRecentForm {
                formModePicker
            }

            if formDisplayMode != .season, store.isPro, supportsRecentForm {
                recentWindowPicker
                if recentLoading {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.75)
                        Text("Loading recent form…")
                            .font(HardwoodType.small)
                            .foregroundStyle(HardwoodPalette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else if let recentLoadError {
                    Text(recentLoadError)
                        .font(HardwoodType.small)
                        .foregroundStyle(HardwoodPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else if recentForm == nil {
                    Text(recentEmptyStateText)
                        .font(HardwoodType.small)
                        .foregroundStyle(HardwoodPalette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }

            if groupedMetrics.isEmpty {
                emptyStateCard(
                    icon: "chart.bar",
                    title: "No metrics available",
                    description: "Percentile rankings are not available for this player in the \(seasonLabel) season."
                )
                .padding(.vertical, 24)
            } else {
                ForEach(groupedMetrics, id: \.category) { group in
                    let rows = displayedMetrics(in: group.metrics)
                    if !rows.isEmpty {
                        HardwoodSubSectionBar(
                            title: group.category.rawValue.uppercased()
                        )

                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, metric in
                            percentileMetricRow(metric: metric, index: index)
                        }
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
        .task(id: "\(formDisplayMode)-\(recentWindow.rawValue)-\(player.playerId)-\(activeSeason ?? 0)-\(store.isPro)-\(freshnessViewModel?.freshnessRevision ?? "none")") {
            guard store.isPro, effectiveFormDisplayMode != .season else { return }
            rebuildRecentCurves()
            await loadRecentForms()
        }
        .onAppear { rebuildRecentCurves() }
        .onChange(of: allPlayers.count) { _, _ in rebuildRecentCurves() }
        .onChange(of: activeSeason) { _, _ in rebuildRecentCurves() }
    }

    /// Whether Recent / Both are offered for the season on screen.
    ///
    /// Was "is this the live season", which stopped being the rule when Recent
    /// form was widened to the live season *and the one before it*. Trends and
    /// Teams both read `DashboardViewModel.recentFormSeasons`, and so does this
    /// page: a subscriber opening last season's profile still has a Recent
    /// control on a season the Trends board two taps away still ranks.
    ///
    /// Falls back to the single-season rule when no list is supplied, which is
    /// the previews-and-tests path.
    private var supportsRecentForm: Bool {
        let season = activeSeason ?? currentSeason
        guard let recentFormSeasons else { return season == currentSeason }
        return recentFormSeasons.contains(season)
    }

    private var recentEmptyStateText: String {
        switch freshnessViewModel?.freshnessStatus {
        case .pending, .partial, .checking:
            return "Recent game data is still arriving"
        case .offline, .failed:
            return "Recent game data is unavailable right now"
        default:
            return "No games in the \(recentWindow.prose)"
        }
    }

    /// The mode rows actually render in - forced back to `.season` on a
    /// historical season so a user who toggled Recent/Both doesn't see stale
    /// current-season windows against past-season bars.
    private var effectiveFormDisplayMode: FormDisplayMode {
        supportsRecentForm ? formDisplayMode : .season
    }

    /// The rolling row for the window on screen.
    private var recentForm: RecentForm? { recentForms[recentWindow.rawValue] }

    private var recentWindowPicker: some View {
        HardwoodSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: $recentWindow
        )
        .padding(.horizontal, HardwoodGeo.padInline)
        .padding(.bottom, 8)
        .background(HardwoodPalette.surfaceAlt)
    }

    /// Recent mode shows every season bar: a metric with a window figure renders
    /// the recent value, the rest fall back to the season bar (handled in
    /// `percentileMetricRow`).
    private func displayedMetrics(in metrics: [Metric]) -> [Metric] {
        metrics
    }

    @ViewBuilder
    private func percentileMetricRow(metric: Metric, index: Int) -> some View {
        let recentMetric = recentMetric(for: metric)
        let rowBackground = index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt

        switch effectiveFormDisplayMode {
        case .season:
            NavigationLink(value: MetricRoute(label: metric.label, category: metric.category, season: activeSeason, phase: activePhase)) {
                MetricBar(metric: metric)
                    .padding(.horizontal, HardwoodGeo.padCard)
                    .padding(.vertical, 12)
                    .background(rowBackground)
                    .overlay(
                        Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                        alignment: .bottom
                    )
            }
            .buttonStyle(.plain)
        case .recent:
            if let recentMetric {
                MetricBar(metric: recentMetric)
                    .padding(.horizontal, HardwoodGeo.padCard)
                    .padding(.vertical, 12)
                    .background(rowBackground)
                    .overlay(
                        Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                        alignment: .bottom
                    )
            } else {
                // No window figure for this metric (a season total has no
                // per-week form) - fall back to the season bar so the recent
                // view still shows every percentile bar.
                NavigationLink(value: MetricRoute(label: metric.label, category: metric.category, season: activeSeason, phase: activePhase)) {
                    MetricBar(metric: metric)
                        .padding(.horizontal, HardwoodGeo.padCard)
                        .padding(.vertical, 12)
                        .background(rowBackground)
                        .overlay(
                            Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
            }
        case .both:
            NavigationLink(value: MetricRoute(label: metric.label, category: metric.category, season: activeSeason, phase: activePhase)) {
                DualMetricBar(
                    season: metric,
                    recent: recentMetric,
                    recentCaption: recentWindow.segmentLabel
                )
                .padding(.horizontal, HardwoodGeo.padCard)
                .padding(.vertical, 12)
                .background(rowBackground)
                .overlay(
                    Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// The window figure for a season metric, placed on the same league ruler as
    /// the season bar. Season totals (3PM, AST, STL...) have no per-week
    /// equivalent on that ruler, so they return nil and keep their season bar.
    private func recentMetric(for seasonMetric: Metric) -> Metric? {
        guard let form = recentForm,
              let key = RecentMetricKey.key(for: seasonMetric.label),
              !RecentMetricKey.isSeasonTotal(seasonMetric.label),
              let value = form.metrics[key],
              let pct = recentCurves?.curve(for: seasonMetric.label)?.percentile(for: value) else { return nil }
        return Metric(
            id: "recent-\(seasonMetric.label)",
            label: seasonMetric.label,
            value: RecentMetricKey.format(value, label: seasonMetric.label),
            percentile: pct,
            category: seasonMetric.category
        )
    }

    private func rebuildRecentCurves() {
        // The ruler is the player's own cohort: a center's rebound rate is
        // placed among centers, the same way the season bar was ranked.
        let group = displayedPlayer.positionGroup
        recentCurves = LeaguePercentileCurves(
            players: cohortPlayers.filter { $0.positionGroup == group },
            categories: MetricCategory.allCases,
            labels: MetricCategory.allCases.flatMap(\.metricPriorityOrder)
        )
    }

    private func loadRecentForms() async {
        guard store.isPro, let fetch = fetchRecentForm,
              let season = activeSeason ?? player.season else { return }
        // Two cards want these rows (percentiles and standard stats) and each
        // has its own task, so remember what is already in hand rather than
        // refetching the same season the moment the user switches tabs.
        // The phase belongs in the key. Without it, opening a player's regular
        // season and then his playoffs reused the first fetch's rows under the
        // second heading.
        let key = "\(player.playerId)-\(season)-\(activePhase.rawValue)-\(freshnessViewModel?.freshnessRevision ?? "none")"
        if recentFormsKey == key, !recentForms.isEmpty { return }
        // Both cards ask at once; share one request per key. A different key
        // (the season or phase changed mid-load) gets its own request, and the
        // stale one discards its result instead of labelling last season's
        // rows with this season's heading.
        guard recentLoadingKey != key else { return }
        recentLoadingKey = key
        recentLoading = true
        recentLoadError = nil
        do {
            let rows = try await fetch(player.playerId, season, activePhase)
            guard recentLoadingKey == key else { return }
            // A player ranked in two cohorts has a row per cohort; the one with
            // more minutes is the one that describes him.
            var byWindow: [Int: RecentForm] = [:]
            for row in rows where (byWindow[row.windowWeeks]?.touches ?? -1) < row.touches {
                byWindow[row.windowWeeks] = row
            }
            recentForms = byWindow
            recentFormsKey = key
        } catch {
            guard recentLoadingKey == key else { return }
            // Distinguish "no games" from "fetch failed" - otherwise a network
            // error renders as an honest-looking "No games in the last 2 weeks".
            if !isTaskCancellation(error), recentForms.isEmpty || recentFormsKey != key {
                recentForms = [:]
                recentFormsKey = nil
                recentLoadError = "Couldn't load recent form. Check your connection and try again."
            }
        }
        recentLoadingKey = nil
        recentLoading = false
    }

    private func refreshProfile() async {
        guard let freshnessViewModel else { return }
        // Keep existing rows visible while the shared revision check runs. The
        // task IDs will fetch them again only when a new revision is accepted.
        await freshnessViewModel.load()
        recentFormsKey = nil
        if store.isPro,
           effectiveFormDisplayMode != .season || effectiveStandardMode != .season {
            await loadRecentForms()
        }
    }

    /// The metric category a traditional stat reads under, so its bar and its
    /// leaderboard sit with the right family of numbers.
    private static func standardCategory(for label: String) -> MetricCategory {
        switch label.uppercased() {
        case "PPG", "FG", "3P", "FT": return .scoring
        case "APG", "TOV": return .playmaking
        case "RPG": return .rebounding
        case "SPG", "BPG", "PF": return .defense
        default: return .impact
        }
    }

    /// Averages and shooting lines are rates; the rest are counts. Ranking
    /// counts is honest but playing-time driven, so they are grouped separately
    /// and captioned as volume.
    private static let countingStats: Set<String> = ["G", "GS", "TOV", "PF", "+/-", "MIN"]

    /// Percentile rank for a traditional stat against the league.
    ///
    /// The pipeline publishes percentiles for the advanced metrics but not for
    /// the standard line, so these are computed here: a player's position in
    /// the distribution of every same-cohort player who has the stat. Returns
    /// a midpoint percentile for every existing value, even when only a small
    /// early-season cohort has played.
    private func standardStatPercentile(
        label: String,
        value: String
    ) -> Int {
        StandardStatSemantics.percentile(
            label: label,
            value: value,
            peerValues: peerValues(forStat: label)
        )
    }

    /// Same-cohort players' values for one traditional stat.
    ///
    /// Kept as its own step so the season and recent rows of a card share the
    /// walk over `allPlayers` for a given stat instead of each row starting it
    /// again.
    private func peerValues(forStat label: String) -> [String] {
        let key = label.uppercased()
        let group = displayedPlayer.positionGroup
        return cohortPlayers.compactMap { other in
            guard other.positionGroup == group,
                  let stat = other.standardStats?.first(where: { $0.label.uppercased() == key })
            else { return nil }
            return stat.value
        }
    }

    /// The data's own spelling of a stat, given the uppercased one this card
    /// displays. The leaderboard a row pushes to matches on the stored label, so
    /// routing with a differently cased display label would land on a board that
    /// matched nothing.
    private func standardStatKey(for displayLabel: String) -> String {
        (displayedPlayer.standardStats ?? [])
            .first { $0.label.uppercased() == displayLabel }?.label ?? displayLabel
    }

    /// Standard stats rendered as the same `Metric` the percentile card uses, so
    /// both tabs read on one ruler. Made/attempted lines (FG, 3P, FT) rank by
    /// their percentage rather than by the leading count.
    private func standardMetrics(counting: Bool) -> [Metric] {
        (displayedPlayer.standardStats ?? [])
            .filter { Self.countingStats.contains($0.label.uppercased()) == counting }
            .map { stat in
                let pct = standardStatPercentile(label: stat.label, value: stat.value)
                return Metric(
                    id: "std-\(stat.label)",
                    label: stat.label.uppercased(),
                    value: stat.value,
                    percentile: pct,
                    category: Self.standardCategory(for: stat.label),
                    // A zero count has no honest rank, same rule as the feed's
                    // metrics (`Metric.isUnranked`), except where fewer is
                    // better: a bench player's 0 PF ranks at the top.
                    rankable: counting
                        && StandardStatSemantics.higherIsBetter(label: stat.label)
                        && metricNumericValue(stat.value) == 0 ? false : nil
                )
            }
    }

    /// Standard stat label to its rolling-window column. Only the per-game
    /// averages have one: games played, the made/attempted lines and the totals
    /// keep their season row alone.
    private static let standardRecentKeys: [String: String] = [
        "PPG": "ppg", "RPG": "rpg", "APG": "apg", "SPG": "spg", "BPG": "bpg", "MPG": "mpg",
    ]

    /// What the recent column is made of: the window and the games in it.
    private var standardRecentCaption: String {
        guard let form = recentForms[standardWindow.rawValue] else {
            return standardWindow.segmentLabel
        }
        return "\(standardWindow.segmentLabel) · \(form.games)G"
    }

    /// The recent-window version of one traditional stat, or nil when the window
    /// has no figure for it. Percentile comes from the same league season
    /// distribution the season row uses, so both sit on one ruler.
    private func recentStandardMetric(for seasonMetric: Metric) -> Metric? {
        guard let key = Self.standardRecentKeys[seasonMetric.label],
              let value = recentForms[standardWindow.rawValue]?.metrics[key] else { return nil }
        let text = String(format: "%.1f", value)
        return Metric(
            id: "std-recent-\(seasonMetric.label)",
            label: seasonMetric.label,
            value: text,
            percentile: standardStatPercentile(
                label: seasonMetric.label,
                value: text
            ),
            category: seasonMetric.category
        )
    }

    private var standardStatsGridCard: some View {
        VStack(spacing: 0) {
            // The season already appears in the picker on the right; printing
            // it in the title too was saying it twice.
            HardwoodSectionBar(
                title: "STANDARD STATS",
                trailing: AnyView(seasonMenu)
            )

            // Recent only means something on the seasons the rollup covers; on a
            // past season the window would always be empty.
            if supportsRecentForm {
                standardModePicker
                if effectiveStandardMode != .season {
                    standardWindowPicker
                }
            }

            if (displayedPlayer.standardStats ?? []).isEmpty {
                emptyStateCard(
                    icon: "chart.bar",
                    title: "Standard stats unavailable",
                    description: "Traditional stats are not available for this player."
                )
                .padding(.vertical, 24)
            } else {
                let rates = standardMetrics(counting: false)
                let counts = standardMetrics(counting: true)
                // Only worth labelling the two groups when there are two of
                // them: a lone "TOTALS" bar above every row says nothing.
                let labelled = !rates.isEmpty && !counts.isEmpty

                if !rates.isEmpty {
                    if labelled { HardwoodSubSectionBar(title: "PER GAME & SHOOTING") }
                    standardRows(rates)
                }
                if !counts.isEmpty {
                    if labelled { HardwoodSubSectionBar(title: "TOTALS") }
                    standardRows(counts, startingIndex: rates.count)
                }
            }
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        // Standard Stats is its own tab, so the percentile card's loader never
        // runs while you are looking at this one. Without this the Recent /
        // Both modes rendered season numbers under a "2 wk" caption until you
        // happened to visit the other tab first.
        .task(id: "std-\(standardMode)-\(standardWindow.rawValue)-\(player.playerId)-\(activeSeason ?? 0)-\(store.isPro)-\(freshnessViewModel?.freshnessRevision ?? "none")") {
            guard store.isPro, effectiveStandardMode != .season else { return }
            await loadRecentForms()
        }
    }

    private var effectiveStandardMode: FormDisplayMode {
        (store.isPro && supportsRecentForm) ? standardMode : .season
    }

    private var standardModePicker: some View {
        HardwoodSegmented(
            segments: FormDisplayMode.allCases.map {
                .init(value: $0, label: $0.rawValue, isLocked: !store.isPro && $0 != .season)
            },
            selection: $standardMode,
            onLockedTap: { _ in trialPitchTrigger = .recentForm }
        )
        .padding(.horizontal, HardwoodGeo.padInline)
        .padding(.vertical, 10)
        .background(HardwoodPalette.surfaceAlt)
    }

    private var standardWindowPicker: some View {
        HardwoodSegmented(
            segments: RecentWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
            selection: $standardWindow
        )
        .padding(.horizontal, HardwoodGeo.padInline)
        .padding(.bottom, 8)
        .background(HardwoodPalette.surfaceAlt)
    }

    @ViewBuilder
    private func standardRows(_ metrics: [Metric], startingIndex: Int = 0) -> some View {
        ForEach(Array(metrics.enumerated()), id: \.element.id) { offset, metric in
            let recent = recentStandardMetric(for: metric)
            let background = (startingIndex + offset) % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt

            NavigationLink(value: StandardStatRoute(
                stat: standardStatKey(for: metric.label),
                season: activeSeason,
                phase: activePhase
            )) {
                Group {
                    switch effectiveStandardMode {
                    case .season:
                        MetricBar(metric: metric)
                    case .recent:
                        // No recent figure for this stat, fall back to season
                        // rather than dropping the row, matching the percentile
                        // card's behaviour.
                        MetricBar(metric: recent ?? metric)
                    case .both:
                        DualMetricBar(
                            season: metric,
                            recent: recent,
                            recentCaption: standardRecentCaption
                        )
                    }
                }
                .padding(.horizontal, HardwoodGeo.padCard)
                .padding(.vertical, 12)
                .background(background)
                .overlay(
                    Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)
        }
    }

}

struct PercentileInfoSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Percentile Rankings")
                        .font(HardwoodType.playerName)
                        .foregroundStyle(HardwoodPalette.ink)

                    Text("Percentile rankings compare a player to others in his position group: guards, forwards or centers. A 90th percentile means the player ranks in the top 10% of his group for that metric.")
                        .font(HardwoodType.body)
                        .foregroundStyle(HardwoodPalette.inkSecondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Elite (75-100): Green bars", systemImage: "flame.fill")
                            .font(HardwoodType.bodyBold)
                            .foregroundStyle(HardwoodPalette.performanceHigh)
                        Label("Average (25-75): Charcoal bars", systemImage: "minus")
                            .font(HardwoodType.bodyBold)
                            .foregroundStyle(HardwoodPalette.inkSecondary)
                        Label("Below Average (0-25): Rust bars", systemImage: "snowflake")
                            .font(HardwoodType.bodyBold)
                            .foregroundStyle(HardwoodPalette.performanceLow)
                    }
                    .padding(.vertical, 8)

                    Text("Stats update after new source data is validated. Advanced metrics may arrive later than game totals. Not every metric is tracked for every player.")
                        .font(HardwoodType.small)
                        .foregroundStyle(HardwoodPalette.inkTertiary)
                }
                .padding(24)
            }
            .background(HardwoodPalette.canvas.ignoresSafeArea())
            .navigationTitle("About Percentiles")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PlayerPickerSheet: View {
    let players: [Player]
    var onSelect: (Player) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filteredPlayers: [Player] {
        guard !searchText.isEmpty else { return players }
        return players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.team.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredPlayers) { player in
                Button {
                    dismiss()
                    onSelect(player)
                } label: {
                    HStack(spacing: 12) {
                        PlayerHeadshot(team: player.team, initials: player.initials, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .font(HardwoodType.bodyBold)
                                .foregroundStyle(HardwoodPalette.ink)
                            Text("\(player.team) · \(player.displayPosition)")
                                .font(HardwoodType.small)
                                .foregroundStyle(HardwoodPalette.inkTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search players")
            .navigationTitle("Compare With")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PlayerProfileView(player: SampleData.players[0], history: [SampleData.players[0]])
            .environmentObject(StoreService.shared)
    }
}
#endif
