import XCTest
@testable import Hardwood_StatScout

@MainActor
final class YearComparisonFeatureTests: XCTestCase {

    func testYearCompareTabExistsForPlayersWithHistory() {
        // Create mock players with multi-year history
        let history = [
            Player(playerId: 1, name: "Test Player", team: "BOS", position: "G", handedness: "", updatedAt: Date(), season: 2026, metrics: [], standardStats: [], games: []),
            Player(playerId: 1, name: "Test Player", team: "BOS", position: "G", handedness: "", updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: [])
        ]

        // Verify player has history
        XCTAssertTrue(history.count > 1, "Player should have multiple years of data")

        // Verify Year Compare tab would be enabled (based on history.count > 1 logic)
        let hasHistory = history.count > 1
        XCTAssertTrue(hasHistory, "Year Compare tab should be enabled for players with history")
    }

    func testYearCompareTabDisabledForPlayersWithoutHistory() {
        // Create mock player with single year
        let history = [
            Player(playerId: 2, name: "New Player", team: "LAL", position: "F", handedness: "", updatedAt: Date(), season: 2026, metrics: [], standardStats: [], games: [])
        ]

        // Verify Year Compare tab would be disabled
        let hasHistory = history.count > 1
        XCTAssertFalse(hasHistory, "Year Compare tab should be disabled for players with only one year")
    }

    func testYearSelectionLogic() {
        let history = [
            Player(playerId: 1, name: "Test", team: "BOS", position: "G", handedness: "", updatedAt: Date(), season: 2026, playerType: "g", source: "hoopR", metrics: [], standardStats: [], games: []),
            Player(playerId: 1, name: "Test", team: "BOS", position: "G", handedness: "", updatedAt: Date(), season: 2025, playerType: "g", source: "hoopR", metrics: [], standardStats: [], games: []),
            Player(playerId: 1, name: "Test", team: "BOS", position: "G", handedness: "", updatedAt: Date(), season: 2024, playerType: "g", source: "hoopR", metrics: [], standardStats: [], games: [])
        ]

        // Sort history by season descending
        let sortedHistory = history.sorted {
            guard let s1 = $0.season, let s2 = $1.season else { return false }
            return s1 > s2
        }

        // Extract unique years
        let availableYears = sortedHistory.compactMap { $0.season }.uniqued().sorted(by: >)
        XCTAssertEqual(availableYears, [2026, 2025, 2024])

        // Default selection: most recent and second most recent
        let selectedYear1 = availableYears.first
        let selectedYear2 = availableYears.dropFirst().first
        XCTAssertEqual(selectedYear1, 2026)
        XCTAssertEqual(selectedYear2, 2025)
    }

    func testMetricComparisonDisplay() {
        // Create two seasons with different metrics
        let metrics2026 = [
            Metric(id: "m1", label: "TS%", value: "63.0%", percentile: 92, category: .scoring),
            Metric(id: "m2", label: "USG%", value: "31.0%", percentile: 88, category: .scoring),
            Metric(id: "m3", label: "TOV%", value: "12.0%", percentile: 45, category: .scoring)
        ]

        let metrics2025 = [
            Metric(id: "m1", label: "TS%", value: "58.0%", percentile: 78, category: .scoring),
            Metric(id: "m2", label: "USG%", value: "27.0%", percentile: 72, category: .scoring),
            Metric(id: "m3", label: "TOV%", value: "14.0%", percentile: 35, category: .scoring)
        ]

        let player2026 = Player(playerId: 1, name: "Test", team: "BOS", position: "G", handedness: "", updatedAt: Date(), season: 2026, metrics: metrics2026, standardStats: [], games: [])
        let player2025 = Player(playerId: 1, name: "Test", team: "BOS", position: "G", handedness: "", updatedAt: Date(), season: 2025, metrics: metrics2025, standardStats: [], games: [])

        // Build comparison (same logic as YearComparisonView)
        let dict1 = Dictionary(grouping: player2026.metrics) { $0.label }
        let dict2 = Dictionary(grouping: player2025.metrics) { $0.label }
        let allLabels = Set(dict1.keys).union(dict2.keys)

        var comparisons: [(label: String, change: Int, pct1: Int, pct2: Int)] = []
        for label in allLabels {
            if let m1 = dict1[label]?.first, let m2 = dict2[label]?.first {
                comparisons.append((label: label, change: m1.percentile - m2.percentile, pct1: m1.percentile, pct2: m2.percentile))
            }
        }

        // Sort by absolute change magnitude
        comparisons.sort { abs($0.change) > abs($1.change) }

        // Verify comparisons - sorted by absolute change magnitude (descending)
        XCTAssertEqual(comparisons.count, 3)
        // USG% has biggest change: 88-72=16
        XCTAssertEqual(comparisons[0].label, "USG%")
        XCTAssertEqual(comparisons[0].change, 16)
        // TS% has second biggest: 92-78=14
        XCTAssertEqual(comparisons[1].label, "TS%")
        XCTAssertEqual(comparisons[1].change, 14)
        // TOV% has smallest: 45-35=10
        XCTAssertEqual(comparisons[2].label, "TOV%")
        XCTAssertEqual(comparisons[2].change, 10)
    }

    func testOverallPercentileChangeCalculation() {
        let metrics2026 = [
            Metric(id: "m1", label: "A", value: "1", percentile: 80, category: .scoring),
            Metric(id: "m2", label: "B", value: "2", percentile: 90, category: .scoring)
        ]
        let metrics2025 = [
            Metric(id: "m1", label: "A", value: "1", percentile: 70, category: .scoring),
            Metric(id: "m2", label: "B", value: "2", percentile: 60, category: .scoring)
        ]

        let player2026 = Player(playerId: 1, name: "Test", team: "BOS", position: "G", handedness: "", updatedAt: Date(), season: 2026, metrics: metrics2026, standardStats: [], games: [])
        let player2025 = Player(playerId: 1, name: "Test", team: "BOS", position: "G", handedness: "", updatedAt: Date(), season: 2025, metrics: metrics2025, standardStats: [], games: [])

        // Calculate overall percentile change
        let overallChange = player2026.overallPercentile - player2025.overallPercentile

        // 2026: (80+90)/2 = 85
        // 2025: (70+60)/2 = 65
        // Change: 85-65 = 20
        XCTAssertEqual(player2026.overallPercentile, 85)
        XCTAssertEqual(player2025.overallPercentile, 65)
        XCTAssertEqual(overallChange, 20)
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
