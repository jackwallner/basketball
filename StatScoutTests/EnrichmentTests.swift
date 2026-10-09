import XCTest
@testable import Hardwood_StatScout

final class EnrichmentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "stats.qualifier")
    }

    private func player(
        _ id: Int,
        type: String = "g",
        team: String = "BOS",
        metrics: [Metric],
        stats: [StandardStat] = []
    ) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: team, position: type.uppercased(), handedness: "",
            updatedAt: Date(), season: testLiveSeason, playerType: type,
            metrics: metrics, standardStats: stats, games: []
        )
    }

    private func metric(_ label: String, _ value: String, _ pct: Int, _ category: MetricCategory, qualified: Bool? = nil) -> Metric {
        Metric(id: "\(label)-\(pct)-\(value)", label: label, value: value, percentile: pct, category: category, qualified: qualified)
    }

    // MARK: Unranked zero counts

    func testZeroCountingStatIsUnrankedButRatesAndNonZeroCountsAreNot() {
        XCTAssertTrue(metric("BLK", "0", 47, .defense).isUnranked)
        XCTAssertTrue(metric("3PM", "0", 41, .scoring).isUnranked)
        XCTAssertFalse(metric("BLK", "12", 80, .defense).isUnranked)
        XCTAssertFalse(metric("On-Court +/-", "0.0", 50, .impact).isUnranked, "a rate at zero is a real rank")
        XCTAssertFalse(metric("STL%", "0.0%", 5, .defense).isUnranked)
        var standard = metric("BPG", "0", 47, .defense)
        standard.rankable = false
        XCTAssertTrue(standard.isUnranked)
    }

    func testOverallPercentileLeavesUnrankedZerosOut() {
        let reserve = player(1, type: "c", metrics: [
            metric("TS%", "52.0%", 20, .scoring),
            metric("BLK", "0", 47, .defense),
            metric("3PM", "0", 41, .scoring),
        ])
        XCTAssertEqual(reserve.overallPercentile, 20)
        XCTAssertEqual(reserve.headlineMetric?.label, "TS%")
    }

    // MARK: Standings

    func testStandingsCountRecordsDifferentialAndStreak() {
        func final(_ id: String, _ day: Int, _ away: String, _ home: String, _ a: Int, _ h: Int) -> Game {
            Game(id: id, season: 2026, week: day,
                 tipoff: Date(timeIntervalSince1970: TimeInterval(1_789_000_000 + day * 86_400)),
                 awayTeam: away, homeTeam: home, awayScore: a, homeScore: h)
        }
        let games = [
            final("1", 1, "BOS", "NYK", 110, 104),
            final("2", 2, "LAL", "BOS", 99, 101),
            final("3", 3, "BOS", "MIA", 96, 108),
            Game(id: "4", season: 2026, week: 4, tipoff: nil, awayTeam: "NYK", homeTeam: "BOS"),
        ]
        let table = StandingsRow.build(from: games, teams: ["BOS", "NYK", "LAL", "MIA"])
        let boston = table["BOS"]!
        XCTAssertEqual(boston.record, "2-1")
        XCTAssertEqual(boston.differential, (110 + 101 + 96) - (104 + 99 + 108))
        XCTAssertEqual(boston.streak, "L1")
        XCTAssertEqual(table["MIA"]!.record, "1-0")
        XCTAssertEqual(table["MIA"]!.streak, "W1")
        XCTAssertEqual(StandingsRow.ordered(Array(table.values)).map(\.team), ["MIA", "BOS", "LAL", "NYK"])
    }

    // MARK: Profiles, projections, ratings

    func testProfileDecodesTheFeedRowAndIgnoresTheUnusedNullColumns() throws {
        let json = #"""
        [{"player_id":1966,"season":2026,"jersey":23,"birth_date":"1984-12-30","height_in":81,"weight_lb":250,
          "college":null,"years_exp":23,"rookie_season":2004,"draft_year":2003,"draft_round":1,"draft_pick":1,"draft_team":null,
          "contract_apy":null,"contract_cap_pct":null,"contract_years":null,"contract_year_signed":null,
          "contract_value":null,"contract_guaranteed":null,"snap_games":null,"team_games":null,
          "off_snaps":null,"def_snaps":null,"st_snaps":null,"off_snap_pct":null,"def_snap_pct":null,
          "injury_week":null,"injury_status":null,"injury":null,"practice_status":null,
          "updated_at":"2026-10-08T21:45:13.559902+00:00"}]
        """#
        let profile = try XCTUnwrap(try JSONDecoder.statScout.decode([PlayerProfile].self, from: Data(json.utf8)).first)
        XCTAssertEqual(profile.sizeLabel, "6-9, 250")
        XCTAssertEqual(profile.draftLabel, "2003 R1 #1")
        XCTAssertEqual(profile.jersey, 23)
        let october = ISO8601DateFormatter().date(from: "2026-10-08T00:00:00Z")!
        XCTAssertEqual(profile.age(on: october), 41)
    }

    func testUndraftedPlayerReadsUndrafted() {
        var profile = PlayerProfile(playerId: 1, season: 2026)
        XCTAssertNil(profile.draftLabel)
        profile.yearsExperience = 3
        XCTAssertEqual(profile.draftLabel, "Undrafted")
    }

    func testProjectionLabelsTheFavourite() throws {
        let json = #"[{"game_id":"g","home_margin":-10.8,"home_win_prob":0.211},{"game_id":"h","home_margin":0.4,"home_win_prob":0.51}]"#
        let rows = try JSONDecoder.statScout.decode([GameProjection].self, from: Data(json.utf8))
        XCTAssertEqual(rows[0].label(home: "WAS", away: "OKC"), "OKC by 11.0")
        XCTAssertEqual(rows[0].winProbability(for: "OKC", home: "WAS"), 0.789, accuracy: 0.0001)
        XCTAssertEqual(rows[1].label(home: "WAS", away: "OKC"), "Toss-up")
    }

    func testTeamRatingDecodesPerHundredPossessionsAndSigns() throws {
        let json = #"[{"season":2026,"team":"OKC","rank":1,"games":82,"through_week":28,"rating":8.41,"offense":2.61,"defense":5.8,"schedule":-0.11,"prior_weight":0.196,"wins":64,"losses":18,"ties":0,"points_for":9760,"points_against":8846,"updated_at":"2026-10-08T21:45:13.559902+00:00"}]"#
        let rating = try XCTUnwrap(try JSONDecoder.statScout.decode([TeamRating].self, from: Data(json.utf8)).first)
        XCTAssertEqual(rating.wins, 64)
        XCTAssertEqual(rating.offense + rating.defense, rating.rating, accuracy: 0.001)
        XCTAssertEqual(TeamRating.signed(rating.rating), "+8.4")
        XCTAssertEqual(TeamRating.signed(-0.04), "0.0")
        XCTAssertEqual(TeamRating.signed(-2.37), "-2.4")
    }

    // MARK: Team aggregation

    func testRosterRatesWeightByMinutesAndCountsAdd() {
        let starter = player(1, metrics: [metric("TS%", "60.0%", 80, .scoring), metric("PPG", "20.0", 80, .scoring)],
                             stats: [StandardStat(id: "m", label: "MIN", value: "2,000")])
        let cameo = player(2, metrics: [metric("TS%", "90.0%", 99, .scoring), metric("PPG", "2.0", 20, .scoring)],
                           stats: [StandardStat(id: "m", label: "MIN", value: "100")])
        let roster = [starter, cameo]
        // 100 minutes at 90% barely moves a 2,000-minute 60%.
        XCTAssertEqual(try XCTUnwrap(TeamAggregation.value(label: "TS%", category: .scoring, roster: roster)), 61.4286, accuracy: 0.001)
        // Per-game scoring adds up to the team's.
        XCTAssertEqual(TeamAggregation.value(label: "PPG", category: .scoring, roster: roster), 22.0)
        // No minutes means no weight: dropped rather than let in at weight 1.
        let noMinutes = player(3, metrics: [metric("TS%", "99.0%", 99, .scoring)])
        XCTAssertEqual(try XCTUnwrap(TeamAggregation.value(label: "TS%", category: .scoring, roster: roster + [noMinutes])), 61.4286, accuracy: 0.001)
        XCTAssertEqual(BasketballMetricRegistry.aggregation(for: "MPG", category: .impact), .weighted(.games))
    }

    func testTeamPercentileRanksAmongTeamsAndFlipsForLowerIsBetter() {
        let values = [10.0, 20.0, 30.0, 40.0]
        XCTAssertEqual(TeamAggregation.percentile(40, among: values), 88)
        XCTAssertEqual(TeamAggregation.percentile(40, among: values, higherIsBetter: false), 13)
        XCTAssertEqual(TeamAggregation.percentile(5, among: []), 50)
    }

    func testRecentRowsPoolByMinutes() throws {
        func row(_ id: Int, minutes: Int, ppg: Double) throws -> RecentForm {
            let json = """
            {"player_id":\(id),"season":2026,"player_type":"g","window_weeks":2,"team":"BOS","games":4,
             "plays":50,"touches":\(minutes),"metrics":{"ts_pct":\(ppg)},"prior_metrics":{},"delta":{}}
            """
            return try JSONDecoder.statScout.decode(RecentForm.self, from: Data(json.utf8))
        }
        let rows = [try row(1, minutes: 100, ppg: 60), try row(2, minutes: 300, ppg: 50)]
        XCTAssertEqual(try XCTUnwrap(TeamAggregation.recentValue(key: "ts_pct", rows: rows)), 52.5, accuracy: 0.001)
        XCTAssertNil(TeamAggregation.recentValue(key: "missing", rows: rows))
    }

    // MARK: View model wiring

    @MainActor
    func testQualificationIsPerMetric() async {
        let shooter = player(1, metrics: [
            metric("TS%", "61.0%", 90, .scoring, qualified: true),
            metric("Corner 3%", "48.0%", 99, .shooting, qualified: false),
        ])
        let vm = makeViewModel(provider: MockProvider(players: [shooter]))
        await vm.load()
        vm.qualifierLevel = .qualified
        vm.setUserSortMetric("Corner 3%")
        XCTAssertTrue(vm.leaderboard.isEmpty, "qualified for TS% is not qualified for Corner 3%")
        vm.setUserSortMetric("TS%")
        XCTAssertEqual(vm.leaderboard.map(\.playerId), [1])
    }

    @MainActor
    func testProfilesLoadForTheLiveSeason() async {
        var profile = PlayerProfile(playerId: 1, season: testLiveSeason)
        profile.heightInches = 75
        let provider = ProfileProvider(players: [player(1, metrics: [metric("TS%", "60.0%", 70, .scoring)])], profiles: [profile])
        let vm = makeViewModel(provider: provider)
        await vm.load()
        XCTAssertEqual(vm.profile(for: vm.players[0])?.heightInches, 75)
    }
}

private struct ProfileProvider: StatcastProviding, @unchecked Sendable {
    let players: [Player]
    let profiles: [PlayerProfile]

    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] { [] }
    func fetchCurrentPlayers(season: Int) async throws -> [Player] { players }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
    func fetchPlayerProfiles(season: Int) async throws -> [PlayerProfile] { profiles }
}
