import XCTest
@testable import Hardwood_StatScout

final class PlayerTests: XCTestCase {
    private func player(
        id: Int = 1,
        name: String = "Test",
        team: String = "BOS",
        position: String = "G",
        type: String? = nil,
        metrics: [Metric] = [],
        games: [GameTrend] = []
    ) -> Player {
        Player(
            playerId: id, name: name, team: team, position: position,
            handedness: "", updatedAt: Date(), playerType: type,
            metrics: metrics, standardStats: [], games: games
        )
    }

    func testOverallPercentileDoubleAverage() {
        let metrics = [
            Metric(id: "m1", label: "A", value: "1", percentile: 75, category: .scoring),
            Metric(id: "m2", label: "B", value: "2", percentile: 76, category: .scoring),
            Metric(id: "m3", label: "C", value: "3", percentile: 77, category: .scoring)
        ]
        XCTAssertEqual(player(metrics: metrics).overallPercentile, 76) // 75.9 rounded
    }

    func testShareSummaryIncludesTopSignalAndAppName() {
        let metric = Metric(id: "m1", label: "Pts/100", value: "44.3", percentile: 100, category: .scoring)
        let summary = player(name: "Shai Gilgeous-Alexander", team: "OKC", metrics: [metric]).shareSummary
        XCTAssertTrue(summary.contains("Shai Gilgeous-Alexander"))
        XCTAssertTrue(summary.contains("Pts/100"))
        XCTAssertTrue(summary.contains("100th"))
        XCTAssertTrue(summary.hasSuffix("Hardwood StatScout"))
    }

    func testMultiCategoryOverallUsesBestCategoryAverage() {
        // A rim protector who scores little carries both Defense and Scoring
        // metrics - the headline number should reflect the best category, not a
        // blended average.
        let metrics = [
            Metric(id: "d1", label: "BLK%", value: "6.1%", percentile: 95, category: .defense),
            Metric(id: "d2", label: "BPG", value: "2.4", percentile: 95, category: .defense),
            Metric(id: "s1", label: "PPG", value: "8.0", percentile: 30, category: .scoring),
            Metric(id: "s2", label: "USG%", value: "13.0%", percentile: 30, category: .scoring)
        ]
        XCTAssertEqual(player(type: "c", metrics: metrics).overallPercentile, 95)
        XCTAssertEqual(player(type: "c", metrics: metrics).primaryCategory, .defense)
    }

    func testPlayerDecodesSeasonAndPlayerType() throws {
        let json = """
        {
            "id": 1,
            "name": "Test",
            "team": "BOS",
            "position": "G",
            "handedness": "",
            "image_url": null,
            "updated_at": "2026-06-14T12:00:00Z",
            "season": 2026,
            "player_type": "g",
            "source": "hoopR",
            "metrics": [],
            "standard_stats": [],
            "games": []
        }
        """.data(using: .utf8)!
        let player = try JSONDecoder.statScout.decode(Player.self, from: json)
        XCTAssertEqual(player.season, 2026)
        XCTAssertEqual(player.playerType, "g")
        XCTAssertEqual(player.source, "hoopR")
        XCTAssertEqual(player.seasonPhase, .regular)
        XCTAssertEqual(player.positionGroup, .guard)
    }

    func testEveryPlayerTypeQualifiesForEveryCategory() {
        for type in ["g", "f", "c", "unknown"] {
            let p = player(type: type)
            for category in MetricCategory.allCases {
                XCTAssertTrue(p.matchesPlayerType(for: category), "\(type) should qualify for \(category)")
            }
        }
    }

    func testPositionGroupFromPlayerTypeAndPosition() {
        XCTAssertEqual(player(type: "g").positionGroup, .guard)
        XCTAssertEqual(player(type: "f").positionGroup, .forward)
        XCTAssertEqual(player(type: "c").positionGroup, .center)
        // An unknown type reads the box score's own position, and folds into
        // forwards when there is none.
        XCTAssertEqual(player(position: "C", type: "unknown").positionGroup, .center)
        XCTAssertEqual(player(position: "", type: "unknown").positionGroup, .forward)
    }

    func testAnyTwoPlayersCanBeCompared() throws {
        // There is no offense and defense to keep apart in basketball, so the
        // comparison catalog does not filter on position.
        let guardPlayer = player(id: 1, type: "g")
        let center = player(id: 2, type: "c")
        let route = ComparisonRoute(playerA: guardPlayer, playerB: center)
        XCTAssertEqual(route.playerA.playerId, 1)
        XCTAssertEqual(route.playerB.playerId, 2)
    }

    func testInitialsHandleSuffixes() {
        XCTAssertEqual(player(name: "Larry Nance Jr.").initials, "LN")
        XCTAssertEqual(player(name: "Gary Payton II").initials, "GP")
        XCTAssertEqual(player(name: "Jaime Jaquez Jr.").initials, "JJ")
    }

    func testInitialsStandardNames() {
        XCTAssertEqual(player(name: "Luka Doncic").initials, "LD")
        XCTAssertEqual(player(name: "Shai Gilgeous-Alexander").initials, "SG")
        XCTAssertEqual(player(name: "Nene").initials, "N")
    }

    func testWeeklyDeltaSumsRecentGamesOnly() {
        let now = Date()
        let games = [
            GameTrend(id: "recent-up", date: now.addingTimeInterval(-24 * 3600), opponent: "BOS", summary: "", percentileDelta: 5, keyMetric: "TS%"),
            GameTrend(id: "recent-down", date: now.addingTimeInterval(-2 * 24 * 3600), opponent: "DEN", summary: "", percentileDelta: -2, keyMetric: "USG%"),
            GameTrend(id: "old", date: now.addingTimeInterval(-8 * 24 * 3600), opponent: "LAL", summary: "", percentileDelta: 20, keyMetric: "PPG")
        ]
        XCTAssertEqual(player(games: games).weeklyDelta, 3)
    }

    @MainActor
    func testRawNumericStripsThousandsSeparators() {
        XCTAssertEqual(DashboardViewModel.rawNumeric("1,502")!, 1502, accuracy: 0.001)
        XCTAssertEqual(DashboardViewModel.rawNumeric("61.2%")!, 61.2, accuracy: 0.001)
        XCTAssertEqual(DashboardViewModel.rawNumeric("+6.3")!, 6.3, accuracy: 0.001)
    }

    func testDisplayPositionFallsBackToPlayerType() {
        XCTAssertEqual(player(position: "TBD", type: "c").displayPosition, "C")
        XCTAssertEqual(player(position: "", type: "unknown").displayPosition, "")
    }

    func testVolumeCaptionIsMinutes() {
        var p = player()
        p = Player(
            playerId: 1, name: "Test", team: "BOS", position: "G", handedness: "",
            updatedAt: Date(), metrics: [],
            standardStats: [StandardStat(id: "std-MIN", label: "MIN", value: "2,262")],
            games: []
        )
        XCTAssertEqual(p.volumeCaption(for: .scoring), "2,262 min")
    }
}

final class BasketballMetricRegistryTests: XCTestCase {
    /// The labels the backend writes, in the order the contract lists them.
    static let contractLabels: [MetricCategory: [String]] = [
        .scoring: ["Pts/100", "USG%", "TS%", "eFG%", "FT Rate", "3PT Rate", "PPG", "FG%", "3P%", "FT%", "3PM"],
        .shooting: ["Rim Freq", "Rim FG%", "Short Mid Freq", "Short Mid FG%", "Long Mid Freq", "Long Mid FG%", "Corner 3%", "Non-Corner 3%", "Assisted FG%"],
        .playmaking: ["AST%", "AST/100", "TOV%", "AST:TO", "AST:USG", "APG", "AST", "TOV/G"],
        .rebounding: ["OREB%", "DREB%", "REB%", "RPG", "OREB", "DREB"],
        .defense: ["STL%", "BLK%", "Stocks/100", "Fouls/100", "SPG", "BPG", "STL", "BLK"],
        .impact: ["On-Court +/-", "On-Off", "Min%", "MPG", "GS", "+/-"],
    ]

    func testRegistryMatchesTheContractLabelForLabel() {
        for (category, labels) in Self.contractLabels {
            let registry = BasketballMetricRegistry.definitions
                .filter { $0.category == category }
                .map(\.label)
            XCTAssertEqual(Set(registry), Set(labels), "\(category) labels drifted from the contract")
            XCTAssertEqual(registry.count, labels.count, "\(category) has a duplicate label")
        }
        XCTAssertEqual(BasketballMetricRegistry.definitions.count, 48)
    }

    func testAdvancedAndTraditionalClassification() {
        let ts = Metric(id: "ts", label: "TS%", value: "61.0%", percentile: 90, category: .scoring)
        let ppg = Metric(id: "ppg", label: "PPG", value: "27.1", percentile: 85, category: .scoring)
        XCTAssertEqual(BasketballMetricRegistry.kind(for: ts), .advanced)
        XCTAssertEqual(BasketballMetricRegistry.kind(for: ppg), .traditional)
        // Shooting is advanced throughout.
        XCTAssertTrue(BasketballMetricRegistry.definitions
            .filter { $0.category == .shooting }
            .allSatisfy { $0.kind == .advanced })
    }

    func testEveryCategoryHasBothAdvancedAndTraditionalExceptShooting() {
        for category in MetricCategory.allCases where category != .shooting {
            let definitions = BasketballMetricRegistry.definitions.filter { $0.category == category }
            XCTAssertTrue(definitions.contains { $0.kind == .advanced }, "\(category) has no advanced metric")
            XCTAssertTrue(definitions.contains { $0.kind == .traditional }, "\(category) has no traditional metric")
        }
    }

    func testLowerIsBetterMetricsAreExactlyTheContractOnes() {
        let lower = BasketballMetricRegistry.definitions.filter { !$0.higherIsBetter }.map(\.label)
        XCTAssertEqual(Set(lower), ["TOV%", "Fouls/100", "TOV/G"])
    }

    func testEveryDefinitionIsOpenToEveryPositionGroupWithADescription() {
        for definition in BasketballMetricRegistry.definitions {
            XCTAssertEqual(definition.positions, [.guard, .forward, .center], definition.label)
            XCTAssertFalse(definition.description.isEmpty, definition.label)
            XCTAssertFalse(definition.description.contains("\u{2014}"), "no em dashes: \(definition.label)")
        }
    }

    func testAdvancedMetricsLeadDisplayOrder() {
        for category in MetricCategory.allCases {
            let order = BasketballMetricRegistry.definitions
                .filter { $0.category == category }
                .sorted { $0.priority < $1.priority }
            if let firstTraditional = order.firstIndex(where: { $0.kind == .traditional }),
               let lastAdvanced = order.lastIndex(where: { $0.kind == .advanced }) {
                XCTAssertLessThan(lastAdvanced, firstTraditional, "\(category)")
            }
        }
    }

    func testPositionBoardDefaults() {
        XCTAssertEqual(PlayerPositionGroup.guard.preferredAdvancedMetrics, ["AST%", "TS%", "USG%", "On-Off"])
        XCTAssertEqual(PlayerPositionGroup.forward.preferredAdvancedMetrics, ["Pts/100", "TS%", "USG%", "On-Off"])
        XCTAssertEqual(PlayerPositionGroup.center.preferredAdvancedMetrics, ["REB%", "Rim FG%", "BLK%", "On-Off"])
        XCTAssertEqual(PlayerPositionGroup.guard.preferredTraditionalMetrics, ["APG", "PPG", "SPG"])
        XCTAssertEqual(PlayerPositionGroup.forward.preferredTraditionalMetrics, ["PPG", "RPG", "3PM"])
        XCTAssertEqual(PlayerPositionGroup.center.preferredTraditionalMetrics, ["RPG", "BPG", "FG%"])
        // The All board leads with scoring.
        XCTAssertEqual(PlayerPositionGroup.all.preferredAdvancedMetrics.first, "Pts/100")
        XCTAssertEqual(PlayerPositionGroup.all.preferredTraditionalMetrics.first, "PPG")
        XCTAssertEqual(PlayerPositionGroup.allCases.map(\.rawValue), ["All", "G", "F", "C"])
    }

    @MainActor
    func testLowerIsBetterUsesRegistry() {
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "TOV%", category: .playmaking))
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "Fouls/100", category: .defense))
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "TS%", category: .scoring))
    }

    func testUnknownMetricIsPreserved() {
        let unknown = Metric(id: "unknown", label: "New Metric", value: "1.0", percentile: 50, category: .scoring)
        XCTAssertEqual(BasketballMetricRegistry.kind(for: unknown), .advanced)
        XCTAssertTrue(BasketballMetricRegistry.isSupported(unknown, by: .guard))
        XCTAssertEqual(BasketballMetricRegistry.sorted([unknown]), [unknown])
    }

    func testZeroCountIsUnrankedButZeroRateIsNot() {
        let zeroBlocks = Metric(id: "blk", label: "BLK", value: "0", percentile: 47, category: .defense)
        XCTAssertTrue(zeroBlocks.isUnranked)
        let zeroOnOff = Metric(id: "oo", label: "On-Off", value: "0.0", percentile: 50, category: .impact)
        XCTAssertFalse(zeroOnOff.isUnranked)
    }

    func testFamiliesAreBasketballOnes() {
        XCTAssertEqual(
            Set(MetricFamily.allCases.map(\.rawValue)),
            ["Efficiency", "Usage", "Shooting", "Frequency", "Accuracy", "Playmaking", "Turnovers",
             "Rebounding", "Rim Protection", "Steals", "Impact", "Playing Time", "Production"]
        )
    }
}
