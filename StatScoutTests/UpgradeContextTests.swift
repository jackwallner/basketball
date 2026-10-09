import XCTest
@testable import Hardwood_StatScout

/// Regressions for three context bugs: an
/// unprovenanced current-season cache surviving an upgrade, a team page whose
/// roster ignored its own season picker, and drill-down routes that dropped the
/// phase they were opened from.
final class UpgradeContextTests: XCTestCase {

    // MARK: - Current-season cache provenance

    /// The exact shape of the artifact an early build could write to this path: a
    /// real server export, but only the teams that had played by then. It
    /// passes `isCompleteCurrent`, by design, so the validator can never be
    /// what separates it from a full snapshot.
    func testCacheWithoutProvenanceIsDiscardedOnUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let openingWeek = players(teams: ["LAL", "BOS", "SAS", "GSW"], count: 110)
        XCTAssertTrue(
            PlayerSnapshotValidator.isCompleteCurrent(openingWeek),
            "The artifact has to clear the opening-night rule, or this test isn't reproducing the bug"
        )

        // Written without a marker: rows only, nothing beside them.
        let file = directory.appending(path: "players-current.json")
        try JSONEncoder.statScout.encode(openingWeek).write(to: file)

        let cache = TwoTierPlayerCache(directory: directory)
        XCTAssertTrue(
            try cache.loadCurrentPlayers().isEmpty,
            "A snapshot of unknown origin must never populate the current board"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "The discarded snapshot should be removed, not re-read on every launch"
        )
    }

    func testSnapshotSavedByThisBuildIsTrustedOnReload() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = TwoTierPlayerCache(directory: directory)
        try cache.savePlayers(players(teams: ["SAS", "BOS"], count: 30), liveSeason: testLiveSeason)

        XCTAssertEqual(try cache.loadCurrentPlayers().count, 30)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.appending(path: "players-current-provenance.json").path)
        )
        // Still trusted on a second read: the marker is not consumed.
        XCTAssertEqual(try TwoTierPlayerCache(directory: directory).loadCurrentPlayers().count, 30)
    }

    func testDiscardedSnapshotIsReplacedByTheNextServerSave() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.statScout
            .encode(players(teams: ["LAL", "BOS", "SAS", "GSW"], count: 110))
            .write(to: directory.appending(path: "players-current.json"))

        let cache = TwoTierPlayerCache(directory: directory)
        XCTAssertTrue(try cache.loadCurrentPlayers().isEmpty)

        try cache.savePlayers(players(teams: ["SAS", "BOS", "DEN", "MIL"], count: 40), liveSeason: testLiveSeason)
        XCTAssertEqual(try cache.loadCurrentPlayers().count, 40)
    }

    // MARK: - Team page follows its own season picker

    @MainActor
    func testTeamRosterFollowsSelectedSeasonAndPhase() async {
        let seaThisYear = players(teams: ["SAS"], count: 5, season: testLiveSeason)
        let seaLastYear = players(teams: ["SAS"], count: 3, season: testLiveSeason - 1, idOffset: 100)
        let seaPlayoffs = players(
            teams: ["SAS"], count: 2, season: testLiveSeason - 1,
            phase: .playoffs, idOffset: 200
        )
        let vm = makeViewModel(provider: MockProvider(players: seaThisYear + seaLastYear + seaPlayoffs))
        await vm.load()

        vm.selectedSeason = testLiveSeason
        vm.selectedPhase = .regular
        XCTAssertEqual(vm.players(forTeam: "SAS").count, 5)

        // TeamView derives its roster from exactly this call, so moving the
        // page's picker has to move the rows underneath it.
        vm.selectedSeason = testLiveSeason - 1
        XCTAssertEqual(vm.players(forTeam: "SAS").count, 3)

        vm.selectedPhase = .playoffs
        XCTAssertEqual(vm.players(forTeam: "SAS").count, 2)
    }

    // MARK: - Drill-down routes carry their phase

    @MainActor
    func testPlayersForSeasonHonoursAnExplicitPhase() async {
        let regular = players(teams: ["SAS", "BOS"], count: 6, season: testLiveSeason - 1)
        let playoffs = players(
            teams: ["SAS", "BOS"], count: 2, season: testLiveSeason - 1,
            phase: .playoffs, idOffset: 50
        )
        let vm = makeViewModel(provider: MockProvider(players: regular + playoffs))
        await vm.load()
        vm.selectedPhase = .regular

        // A route opened from a playoff profile resolves against its own phase,
        // not whichever one the tab happens to be sitting on.
        XCTAssertEqual(vm.players(forSeason: testLiveSeason - 1, phase: .playoffs).count, 2)
        XCTAssertEqual(vm.players(forSeason: testLiveSeason - 1, phase: .regular).count, 6)
    }

    func testRoutesCarrySeasonAndPhase() {
        let metric = MetricRoute(label: "TS%", category: .scoring, season: 2025, phase: .playoffs)
        XCTAssertEqual(metric.season, 2025)
        XCTAssertEqual(metric.phase, .playoffs)

        let standard = StandardStatRoute(stat: "PPG", season: 2025, phase: .playoffs)
        XCTAssertEqual(standard.season, 2025)
        XCTAssertEqual(standard.phase, .playoffs)

        // Two routes to the same stat in the same year but different halves of
        // it are different destinations, or the stack coalesces them.
        XCTAssertNotEqual(
            metric,
            MetricRoute(label: "TS%", category: .scoring, season: 2025, phase: .regular)
        )
    }

    // MARK: - Helpers

    private func players(
        teams: [String],
        count: Int,
        season: Int = testLiveSeason,
        phase: SeasonPhase = .regular,
        idOffset: Int = 0
    ) -> [Player] {
        (0..<count).map { index in
            Player(
                playerId: idOffset + index, name: "Player \(idOffset + index)",
                team: teams[index % teams.count], position: "G",
                handedness: "", updatedAt: Date(timeIntervalSince1970: 0), season: season,
                seasonPhase: phase,
                playerType: ["g", "f", "c"][index % 3],
                metrics: [
                    Metric(id: "pts", label: "Pts/100", value: "25.0", percentile: 50, category: .scoring),
                    Metric(id: "ast", label: "AST%", value: "15.0%", percentile: 50, category: .playmaking),
                    Metric(id: "reb", label: "REB%", value: "10.0%", percentile: 50, category: .rebounding),
                ],
                standardStats: [], games: []
            )
        }
    }
}
