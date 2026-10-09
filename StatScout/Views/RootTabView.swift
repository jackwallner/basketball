import StoreKit
import SwiftUI

struct TeamDestination: Hashable {
    let abbr: String
}

struct MetricRoute: Hashable {
    let label: String
    let category: MetricCategory
    /// Which season's leaderboard to open. The player profile has its own
    /// season selector, so a route from a 2021-22 profile has to carry 2022,
    /// otherwise tapping TS% there opened the current-season leaderboard.
    var season: Int? = nil
    /// Which half of that year. A profile is scoped to the phase you arrived
    /// from and its season selector never crosses one, so a route from a
    /// playoff profile has to carry `.postseason`: the season alone resolved
    /// against whatever the tab's phase happened to be, which landed a playoff
    /// drill-down on the regular-season board under a playoff heading.
    var phase: SeasonPhase? = nil
}

/// Drill-down from a traditional stat row to its league leaderboard.
struct StandardStatRoute: Hashable {
    let stat: String
    var season: Int? = nil
    /// See `MetricRoute.phase`.
    var phase: SeasonPhase? = nil
}

struct RootTabView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var store: StoreService
    @Environment(\.requestReview) private var requestReview
    @State private var viewModel: DashboardViewModel
    @State private var selection = 0
    @State private var reviewRequestedThisSession = false
    // Owned here so TeamsView can auto-push the favorite team and the user can
    // still pop back to the list.
    @State private var teamsPath = NavigationPath()
    @State private var statsPath = NavigationPath()

    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        tabView
            .tint(HardwoodPalette.court)
            .onReceive(NotificationCenter.default.publisher(for: .statscoutPositiveMomentForReview)) { _ in
                scheduleReviewRequestAfterPositiveMoment()
            }
    }

    /// Asks Apple for the rating prompt a few seconds after a passive positive
    /// moment, with no question of our own first. Apple decides whether to show
    /// it; either way the cooldown starts so we do not ask again soon.
    private func scheduleReviewRequestAfterPositiveMoment() {
        guard ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding: hasCompletedOnboarding),
              !reviewRequestedThisSession
        else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding: hasCompletedOnboarding)
            else { return }
            reviewRequestedThisSession = true
            ReviewPromptTracker.markRequested()
            requestReview()
        }
    }

    /// Hand-rolled tab bar rather than a `TabView`.
    ///
    /// On iOS 26 a `TabView` always draws its own Liquid Glass platter, and
    /// `.toolbarBackground(.hidden, for: .tabBar)` is a no-op against it, which
    /// is what made the bar read as a grey box sitting on the canvas. Owning the
    /// bar means there is no system background to fight.
    ///
    /// Tabs live in a `ZStack` and toggle visibility rather than being swapped,
    /// so each one's navigation stack and scroll position survive switching
    /// away and back. Inactive tabs are hidden from VoiceOver too: at
    /// `opacity(0)` they are still perfectly reachable via the rotor.
    private var tabView: some View {
        ZStack(alignment: .bottom) {
            ForEach(Tab.allCases) { tab in
                TabSlot(
                    isActive: selection == tab.rawValue,
                    tracksActivity: tab.tracksActivity
                ) {
                    tabContent(tab)
                }
                .equatable()
                .frame(maxWidth: 900, maxHeight: .infinity)
                    .opacity(selection == tab.rawValue ? 1 : 0)
                    .allowsHitTesting(selection == tab.rawValue)
                    .accessibilityHidden(selection != tab.rawValue)
            }

            floatingTabBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HardwoodPalette.canvas.ignoresSafeArea())
        .ignoresSafeArea(edges: .bottom)
        #if DEBUG
        .onAppear {
            if let tab = Tab.launchArgument { selection = tab.rawValue }
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-TabSwitchBenchmark") else { return }
            await TabSwitchBenchmark.run(isReady: { viewModel.isReady }) { selection = $0 }
        }
        #endif
    }

    private enum Tab: Int, CaseIterable, Identifiable {
        case stats, games, trends, teams, compare

        var id: Int { rawValue }

        /// Whether the tab's screen reads `isActive` (to poll or preload only
        /// while on screen). The others never need re-rendering on a switch.
        var tracksActivity: Bool {
            switch self {
            case .games, .trends, .compare: return true
            case .stats, .teams: return false
            }
        }

        #if DEBUG
        /// Launch with `-StartTab trends|teams|compare` to open straight on a
        /// tab. The Pro gates live two and four tabs in, and the UI-test runner
        /// cannot reliably drive this app to them on the shared simulator pool
        /// (it reports the app as not running while a plain `simctl launch` of
        /// the same build is perfectly healthy). Screenshotting a gate is the
        /// only way to see its price copy, so the way in has to not depend on
        /// synthesised taps. Compiled out of Release.
        static var launchArgument: Tab? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-StartTab"),
                  index + 1 < arguments.count else { return nil }
            return allCases.first { $0.title.lowercased() == arguments[index + 1].lowercased() }
        }
        #endif

        var title: String {
            switch self {
            case .games: return "Games"
            case .stats: return "Stats"
            case .trends: return "Trends"
            case .teams: return "Teams"
            case .compare: return "Compare"
            }
        }

        var icon: String {
            switch self {
            case .games: return "sportscourt.fill"
            case .stats: return "chart.bar.fill"
            case .trends: return "flame.fill"
            case .teams: return "shield.lefthalf.filled"
            case .compare: return "arrow.left.arrow.right"
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: Tab) -> some View {
        switch tab {
        case .games: gamesTab
        case .stats: statsTab
        case .trends: trendsTab
        case .teams: teamsTab
        case .compare: compareTab
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                TabBarButton(
                    icon: tab.icon,
                    label: tab.title,
                    isSelected: selection == tab.rawValue
                ) {
                    guard selection != tab.rawValue else { return }
                    selection = tab.rawValue
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // Near-opaque: the old 0.8 ultra-thin material let the two rows
        // under it read through and collide with the tab labels on every
        // board. It still floats; it just no longer shares its pixels.
        .background {
            Capsule().fill(.regularMaterial)
            Capsule().fill(HardwoodPalette.surface.opacity(0.9))
        }
        .overlay(Capsule().stroke(HardwoodPalette.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .padding(.bottom, 12)
    }

    private var gamesTab: some View {
        NavigationStack {
            GamesView(
                viewModel: viewModel,
                isActive: selection == Tab.games.rawValue
            )
                .navigationTitle("Games · \(SeasonLabel.text(viewModel.upcomingSeason ?? viewModel.freeSeason))")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(HardwoodNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataCoverage: viewModel.dataCoverage))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var statsTab: some View {
        NavigationStack(path: $statsPath) {
            StatsView(viewModel: viewModel)
                // Title and season pills come from SeasonPhaseNavBar.
                .modifier(HardwoodNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataCoverage: viewModel.dataCoverage))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
        #if DEBUG
        .onChange(of: viewModel.players.count, initial: true) { _, _ in
            pushScreenshotRouteIfNeeded()
        }
        #endif
    }

    #if DEBUG
    private func pushScreenshotRouteIfNeeded() {
        // The cached archive loads first, so wait for the live season's row;
        // pushing the first name match would open last season's profile.
        let live = viewModel.players.filter { $0.season == viewModel.freeSeason }
        guard let route = ScreenshotRoute.current, statsPath.isEmpty,
              let player = live.first(where: { $0.name == ScreenshotRoute.playerName })
        else { return }
        switch route {
        case .profile, .yearCompare:
            statsPath.append(player)
        case .compare:
            guard let peer = live.first(where: { $0.name == ScreenshotRoute.peerName }) else { return }
            statsPath.append(ComparisonRoute(playerA: player, playerB: peer))
        }
    }
    #endif

    private var trendsTab: some View {
        NavigationStack {
            HotColdView(
                viewModel: viewModel,
                isActive: selection == Tab.trends.rawValue
            )
                // Title and season pills come from SeasonPhaseNavBar.
                .modifier(HardwoodNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataCoverage: viewModel.dataCoverage))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var teamsTab: some View {
        NavigationStack(path: $teamsPath) {
            TeamsView(viewModel: viewModel, path: $teamsPath)
                // Title and season pills come from SeasonPhaseNavBar.
                .modifier(HardwoodNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataCoverage: viewModel.dataCoverage))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

    private var compareTab: some View {
        NavigationStack {
            // CompareView pushes its own comparisons with item-based
            // destinations, which never collide with the type-based ones in
            // StandardDestinations. The full set is needed because a profile
            // opened here links onward to metric, stat, team and game pages.
            CompareView(
                viewModel: viewModel,
                isActive: selection == Tab.compare.rawValue
            )
                .navigationTitle("Compare")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(HardwoodNavBar())
                .modifier(HomeTabToolbar(lastUpdated: viewModel.lastUpdated, dataCoverage: viewModel.dataCoverage))
                .modifier(StandardDestinations(viewModel: viewModel))
        }
    }

}

#if DEBUG
@MainActor
enum TabProbe {
    static var counts: [String: Int] = [:]
    static func hit(_ name: String) -> Bool { counts[name, default: 0] += 1; return true }
}

/// `-TabSwitchBenchmark`: once data is in, walks every tab several times and
/// logs the longest stretch the main thread stays blocked after each switch.
@MainActor
enum TabSwitchBenchmark {
    /// Ticks a 1 ms timer on the main run loop and keeps the longest gap
    /// between ticks: how long the main thread was busy in one stretch.
    private final class GapMeter {
        private var timer: Timer?
        private var last = CACurrentMediaTime()
        private var longest: CFTimeInterval = 0

        func start() {
            last = CACurrentMediaTime()
            longest = 0
            let timer = Timer(timeInterval: 0.001, repeats: true) { [weak self] _ in
                guard let self else { return }
                let now = CACurrentMediaTime()
                longest = max(longest, now - last)
                last = now
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        func stop() -> Double {
            timer?.invalidate()
            timer = nil
            return max(longest, CACurrentMediaTime() - last) * 1000
        }
    }

    static func run(isReady: () -> Bool, select: (Int) -> Void) async {
        NSLog("%@", "TABBENCH waiting for data")
        while !isReady() { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .seconds(4))
        NSLog("%@", "TABBENCH start")
        let meter = GapMeter()
        var samples: [Int: [Double]] = [:]
        for _ in 0..<6 {
            for tab in [1, 2, 3, 4, 0] {
                TabProbe.counts = [:]
                meter.start()
                select(tab)
                try? await Task.sleep(for: .milliseconds(800))
                let gap = meter.stop()
                samples[tab, default: []].append(gap)
                NSLog("%@", "TABBENCH switch tab=\(tab) gap=\(Int(gap)) bodies=\(TabProbe.counts.sorted { $0.key < $1.key })")
            }
        }
        for tab in samples.keys.sorted() {
            let values = samples[tab, default: []].sorted()
            let median = values[values.count / 2]
            NSLog("%@", "TABBENCH tab=\(tab) median=\(Int(median))ms max=\(Int(values.last ?? 0))ms all=\(values.map { Int($0) })")
        }
        NSLog("%@", "TABBENCH done")
    }
}
#endif

/// One tab's screen, which the root re-renders only when the tab's own
/// on-screen state flips.
///
/// All five tabs stay alive in the root's `ZStack`, so without this every tab
/// switch re-ran the body of every tab, hidden ones included, and the Stats,
/// Teams and Games bodies each walk a full season. Data changes still reach a
/// hidden tab through observation; only the root's own re-render is cut off.
private struct TabSlot<Content: View>: View, Equatable {
    let isActive: Bool
    let tracksActivity: Bool
    @ViewBuilder let content: () -> Content

    var body: some View { content() }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tracksActivity == rhs.tracksActivity
            && (!lhs.tracksActivity || lhs.isActive == rhs.isActive)
    }
}

/// One item in the hand-rolled floating tab bar. The selected pill uses the
/// court green at low opacity rather than a filled capsule so the bar stays
/// light over whatever content scrolls beneath it.
private struct TabBarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(HardwoodType.smallBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? HardwoodPalette.court : HardwoodPalette.inkSecondary)
            .frame(width: 68, height: 52)
            .background(
                isSelected ? HardwoodPalette.court.opacity(0.12) : .clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

private struct HardwoodNavBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(HardwoodPalette.midnight, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// Trailing toolbar group shared by the four home tabs: a settings gear, then
/// the upgrade CTA when the user isn't subscribed.
///
/// The gear is the only entry point to Settings that isn't buried; it used to
/// live only in a link under the bottom of the leaderboard, which nobody
/// scrolls to. Trailing rather than leading because Stats already owns the
/// leading slot with its season pill, and a control that moves between tabs
/// isn't an anchor.
private struct HomeTabToolbar: ViewModifier {
    @EnvironmentObject private var store: StoreService
    let lastUpdated: Date?
    var dataCoverage: DataCoverage?
    /// Owned per tab, not shared. All four tabs stay alive in the ZStack, so a
    /// single shared flag would push Settings onto all four stacks at once.
    @State private var showingSettings = false
    @State private var paywallTrigger: PaywallTrigger?

    /// Yellow crown + short action verb on a filled pill. The old version was
    /// a bare yellow "Pro" label that read as a status badge rather than a
    /// button, tap-through rates were correspondingly weak. The verb makes
    /// the CTA unambiguous, and the trial-aware label appears when an intro
    /// offer is available.
    private var ctaLabel: String { store.upgradeCTALabel }

    private var upgradeButton: some View {
        Button {
            paywallTrigger = store.defaultUpgradeTrigger
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(ctaLabel)
                    .font(HardwoodType.micro)
                    .fontWeight(.bold)
            }
            .foregroundStyle(HardwoodPalette.midnight)
            // Tight, because the season pill next to it now spells out
            // "Regular Season" and the bar has no slack left. Trimming padding
            // here is far cheaper than losing the verb: a bare crown reads as a
            // status badge, which is exactly what this button used to be and
            // why it was rewritten.
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.yellow)
            .clipShape(Capsule())
            .fixedSize()
        }
        .accessibilityLabel("\(ctaLabel), unlock all features")
    }

    /// Outline cog, no filled circle behind it. The Liquid Glass container
    /// gave it a pale disc that made a secondary control louder than the
    /// content it sits above.
    private var settingsButton: some View {
        Button {
            showingSettings = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        }
        .accessibilityLabel("Settings")
    }

    /// Gear then CTA, in the order they were declared as separate items.
    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 10) {
            settingsButton
            if !store.isPro {
                upgradeButton
            }
        }
    }

    func body(content: Content) -> some View {
        content
            // A push rather than a bottom sheet: Settings is a place in the
            // app, not a modal interruption over what you were reading.
            .navigationDestination(isPresented: $showingSettings) {
                AboutView(
                    lastUpdated: lastUpdated,
                    dataCoverage: dataCoverage
                )
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(HardwoodNavBar())
            }
            .toolbar {
                // One trailing item holding both controls, not two items.
                //
                // Two separate `ToolbarItem`s are a group iOS may collapse into
                // a "..." overflow, and it decides that from its own layout
                // arithmetic rather than from the space actually free: widening
                // the season pill to spell out "Regular Season" tipped it, and
                // the CTA vanished into the menu with a hundred and twenty
                // points of empty bar still sitting between the pill and the
                // gear. Trimming the pill did not bring it back, because width
                // was never really the trigger.
                //
                // A single item cannot be split, so both stay visible and the
                // spacing between them is ours. Same reasoning as the leading
                // pill above.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) { trailingControls }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) { trailingControls }
                }
            }
            // The one place that opens the full plan picker. Every other pitch
            // in the app interrupts something the user reached for, so it stays
            // a half sheet; this pill is the user going looking for the offer,
            // and someone who taps it wants to see what the plans cost.
            .sheet(item: $paywallTrigger) { trigger in
                PaywallView(trigger: trigger)
            }
    }
}

/// The player-profile, game and schedule routes, the part of
/// `StandardDestinations` every stack that shows a player or a game needs.
struct PlayerProfileDestination: ViewModifier {
    let viewModel: DashboardViewModel

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Player.self) { player in
                let history = viewModel.playerHistories[player.playerId] ?? []
                let seasonPlayer = history.first {
                    $0.season == player.season
                        && $0.seasonPhase == player.seasonPhase
                } ?? player
                let profileSeason = seasonPlayer.season ?? viewModel.selectedSeason
                let profilePhase = seasonPlayer.seasonPhase
                PlayerProfileView(
                    player: seasonPlayer,
                    history: history,
                    allPlayers: viewModel.players(
                        forSeason: profileSeason,
                        phase: profilePhase
                    ),
                    currentSeason: viewModel.freeSeason,
                    recentFormSeasons: viewModel.recentFormSeasons,
                    isHistoricalLoading: viewModel.isHistoricalLoading,
                    hasLoadedHistorical: viewModel.hasLoadedHistorical,
                    historicalLoadingMessage: viewModel.loadingMessage,
                    historicalLoadingProgress: viewModel.loadingProgress,
                    loadHistorical: { await viewModel.loadHistoricalIfNeeded() },
                    fetchRecentForm: { id, season, phase in
                        try await viewModel.fetchPlayerRecentForm(
                            playerId: id,
                            season: season,
                            seasonPhase: phase
                        )
                    },
                    freshnessViewModel: viewModel,
                    comparisonCatalog: ComparisonCatalog(
                        viewModel: viewModel,
                        defaultPhase: profilePhase
                    )
                )
                    .modifier(HardwoodNavBar())
            }
            .navigationDestination(for: GameRoute.self) { route in
                GameDetailView(viewModel: viewModel, gameId: route.gameId)
                    .modifier(HardwoodNavBar())
            }
            .navigationDestination(for: TeamScheduleRoute.self) { route in
                TeamScheduleView(viewModel: viewModel, team: route.team)
                    .modifier(HardwoodNavBar())
            }
    }
}

private struct StandardDestinations: ViewModifier {
    let viewModel: DashboardViewModel

    func body(content: Content) -> some View {
        content
            .modifier(PlayerProfileDestination(viewModel: viewModel))
            .navigationDestination(for: TeamDestination.self) { dest in
                TeamView(team: dest.abbr, viewModel: viewModel)
                    .modifier(HardwoodNavBar())
            }
            .navigationDestination(for: MetricRoute.self) { route in
                let season = route.season ?? viewModel.selectedSeason
                let phase = route.phase ?? viewModel.selectedPhase
                MetricRankingView(
                    metricLabel: route.label,
                    metricCategory: route.category,
                    players: viewModel.players(forSeason: season, phase: phase),
                    season: season,
                    viewModel: viewModel
                )
                    .modifier(HardwoodNavBar())
            }
            .navigationDestination(for: StandardStatRoute.self) { route in
                let season = route.season ?? viewModel.selectedSeason
                let phase = route.phase ?? viewModel.selectedPhase
                StandardStatsLeaderboardScreen(
                    players: viewModel.players(forSeason: season, phase: phase),
                    initialStat: route.stat,
                    season: season
                )
                    // The phase only earns title space when it isn't the
                    // default: an inline title is tight, and "PPG · 2023-24
                    // Regular Season" sweeps into a truncation that "PPG ·
                    // 2023-24 Playoffs" is worth paying for.
                    .navigationTitle(
                        route.stat + " · " + (phase == .regular
                            ? SeasonLabel.text(season)
                            : SeasonLabel.text(season, phase: phase))
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .modifier(HardwoodNavBar())
            }
            .navigationDestination(for: ComparisonRoute.self) { route in
                PlayerComparisonView(
                    playerA: route.playerA,
                    playerB: route.playerB,
                    catalog: ComparisonCatalog(
                        viewModel: viewModel,
                        defaultPhase: route.playerA.seasonPhase
                    )
                )
                    .modifier(HardwoodNavBar())
            }
    }
}
