import SwiftUI
import UIKit
import XCTest
@testable import Hardwood_StatScout

// State machine audit repro suite, 2026-11-24. Failing tests are expected on the
// starting commit: each one asserts the promised behaviour. Every test asserts
// its own preconditions first, and each failing claim has a passing control.

// MARK: - Provider fake

/// Serves a different live-season feed on each call, so one view model can be
/// refreshed through an overnight prune.
final class ReproFeedProvider: StatcastProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var feeds: [[Player]]
    private var _calls = 0

    init(feeds: [[Player]]) { self.feeds = feeds }

    var calls: Int { lock.withLock { _calls } }

    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] { [] }

    func fetchCurrentPlayers(season: Int) async throws -> [Player] {
        lock.withLock {
            defer { _calls += 1 }
            return feeds[min(_calls, feeds.count - 1)]
        }
    }

    func fetchDataFreshness() async throws -> DataFreshness? { nil }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
}

/// Thirty teams, three players each (one per cohort), with the metrics the
/// completeness check asks for: a feed the app accepts as a full refresh.
func reproCompleteFeed(season: Int) -> [Player] {
    let types = ["g", "f", "c"]
    return nbaTeamAbbreviations.enumerated().flatMap { index, abbr in
        types.enumerated().map { offset, type in
            Player(
                playerId: 20_000 + index * 3 + offset,
                name: "Repro \(abbr) \(type)",
                team: abbr,
                position: type.uppercased(),
                handedness: "",
                updatedAt: Date(),
                season: season,
                playerType: type,
                metrics: [
                    Metric(id: "pts-\(index)-\(offset)", label: "Pts/100", value: "25.0", percentile: 50, category: .scoring),
                    Metric(id: "ast-\(index)-\(offset)", label: "AST%", value: "15.0%", percentile: 50, category: .playmaking),
                    Metric(id: "reb-\(index)-\(offset)", label: "REB%", value: "10.0%", percentile: 50, category: .rebounding),
                ],
                standardStats: [StandardStat(id: "games-\(index)", label: "G", value: "60")],
                games: []
            )
        }
    }
}

// MARK: - Suite

@MainActor
final class StateMachineAuditRepro: XCTestCase {

    // MARK: SM5-B2: a refresh keeps live-season rows the publisher pruned

    /// The publisher deletes every live-season snapshot it no longer builds
    /// (backend/ingest.py:731-747, "Pruned stale/unqualified rows"). The app
    /// refreshes in place every two minutes while open and on every
    /// foreground (StatScoutApp.swift:149-163), so its board must follow.
    func testRefreshDropsAPlayerThePublisherPruned() async {
        let full = reproCompleteFeed(season: testLiveSeason)
        let pruned = full.first!
        let provider = ReproFeedProvider(feeds: [full, Array(full.dropFirst())])
        let vm = makeViewModel(provider: provider)

        await vm.load()
        XCTAssertEqual(vm.seasonPlayers.count, full.count, "precondition: first load shows the full feed")
        XCTAssertTrue(vm.seasonPlayers.contains { $0.playerId == pruned.playerId })

        await vm.load()
        XCTAssertEqual(provider.calls, 2, "precondition: the refresh asked for the feed again")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.lastFetchFailed, "precondition: the refresh succeeded")

        XCTAssertFalse(vm.seasonPlayers.contains { $0.playerId == pruned.playerId },
                       "the publisher pruned this player, but the board still ranks him")
        XCTAssertEqual(vm.seasonPlayers.count, full.count - 1)
    }

    /// Control: a row still in the feed is replaced by its newer values.
    func testControlRefreshReplacesARowThatIsStillInTheFeed() async {
        let before = reproCompleteFeed(season: testLiveSeason)
        let after = reproCompleteFeed(season: testLiveSeason)
            .map { player -> Player in
                guard player.playerId == before.first!.playerId else { return player }
                return Player(
                    playerId: player.playerId, name: "Renamed", team: player.team, position: player.position,
                    handedness: "", updatedAt: Date(), season: player.season, playerType: player.playerType,
                    metrics: player.metrics, standardStats: player.standardStats, games: []
                )
            }
        let provider = ReproFeedProvider(feeds: [before, after])
        let vm = makeViewModel(provider: provider)
        await vm.load()
        await vm.load()
        XCTAssertEqual(provider.calls, 2)
        XCTAssertEqual(vm.seasonPlayers.first { $0.playerId == before.first!.playerId }?.name, "Renamed")
        XCTAssertEqual(vm.seasonPlayers.count, before.count)
    }

    // MARK: SM3-B1: returning to a profile from a drill-down counts as a new open

    @MainActor
    final class Nav: ObservableObject {
        @Published var path = NavigationPath()
    }

    enum Dest: Hashable { case profile, metric }

    struct Host: View {
        @ObservedObject var nav: Nav
        let player: Player
        var body: some View {
            NavigationStack(path: $nav.path) {
                Text("root")
                    .navigationDestination(for: Dest.self) { dest in
                        switch dest {
                        case .profile: PlayerProfileView(player: player, history: [player])
                        case .metric: Text("metric leaders")
                        }
                    }
            }
            .environmentObject(StoreService.shared)
        }
    }

    private func spin(_ seconds: Double = 1.0) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func mount(_ nav: Nav) -> UIWindow {
        let player = reproCompleteFeed(season: testLiveSeason)[0]
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: Host(nav: nav, player: player))
        window.makeKeyAndVisible()
        return window
    }

    private let openKey = "profileOpenCount"

    private func isolateProfileCounters() -> () -> Void {
        let d = UserDefaults.standard
        let savedOpens = d.object(forKey: openKey)
        let savedMoments = ReviewPromptTracker.positiveMomentCount
        let savedPending = ReviewPromptTracker.hasPendingPositiveMoment
        d.set(0, forKey: openKey)
        ReviewPromptTracker.positiveMomentCount = 0
        ReviewPromptTracker.hasPendingPositiveMoment = false
        // Use up the 2-per-session pitch cap so no sheet covers the host.
        PaywallGate.shared.markPresented(.playerScouting)
        PaywallGate.shared.markPresented(.playerScouting)
        return {
            if let savedOpens { d.set(savedOpens, forKey: self.openKey) } else { d.removeObject(forKey: self.openKey) }
            ReviewPromptTracker.positiveMomentCount = savedMoments
            ReviewPromptTracker.hasPendingPositiveMoment = savedPending
        }
    }

    /// PlayerProfileView.swift:262-265: "Show it from the *second* profile
    /// open onward"; :271 "Third+ profile visit = engaged browsing". One
    /// profile, two metric drill-downs and back, is one profile open.
    func testReturningToOneProfileFromADrillDownIsNotANewProfileOpen() async {
        let restore = isolateProfileCounters()
        defer { restore() }
        XCTAssertFalse(StoreService.shared.isPro, "precondition: free user")
        let nav = Nav()
        let window = mount(nav)
        defer { window.isHidden = true }

        nav.path.append(Dest.profile)
        await spin()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: openKey), 1, "precondition: first open counted once")

        for _ in 0..<2 {
            nav.path.append(Dest.metric)
            await spin(0.7)
            nav.path.removeLast()
            await spin(0.7)
        }
        XCTAssertEqual(nav.path.count, 1, "precondition: still on the same single profile")

        XCTAssertEqual(UserDefaults.standard.integer(forKey: openKey), 1,
                       "one profile opened once, but the counter says more")
        XCTAssertEqual(ReviewPromptTracker.positiveMomentCount, 0,
                       "no third profile was opened, so no review moment is due")
    }

    /// Control: leaving the profile and opening it again is a second open.
    func testControlOpeningTheProfileTwiceCountsTwice() async {
        let restore = isolateProfileCounters()
        defer { restore() }
        let nav = Nav()
        let window = mount(nav)
        defer { window.isHidden = true }

        nav.path.append(Dest.profile)
        await spin()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: openKey), 1)
        nav.path.removeLast()
        await spin(0.7)
        nav.path.append(Dest.profile)
        await spin()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: openKey), 2)
    }
}
