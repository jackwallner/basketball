import XCTest
@testable import Hardwood_StatScout

@MainActor
final class PlayerShareCardTests: XCTestCase {
    private func metric(_ label: String, _ value: String, _ pct: Int) -> Metric {
        Metric(id: label, label: label, value: value, percentile: pct, category: .scoring)
    }

    private var card: PlayerShareCard {
        let first = [metric("TS%", "64.1%", 95), metric("Points/36", "29.4", 97), metric("USG%", "31.0%", 93)]
        let second = [metric("AST%", "34.2%", 90), metric("TOV%", "11.8%", 62)]
        let player = Player(playerId: 1, name: "Stephen Curry", team: "GSW", position: "G", handedness: "",
            updatedAt: Date(), season: StatScoutSeason.bundledNewest, playerType: "guard",
            metrics: first + second, standardStats: [], games: [])
        return PlayerShareCard(
            player: player,
            groups: [("Scoring", first), ("Play", second)],
            seasonLabel: String(StatScoutSeason.bundledNewest),
            isCurrentSeason: true
        )
    }

    func testRendersPNGAtThreeTimesCardWidth() throws {
        let image = try XCTUnwrap(PlayerShareImage.render(card))
        let rendered = try XCTUnwrap(UIImage(data: image.png))
        XCTAssertEqual(rendered.size.width * rendered.scale, PlayerShareCard.width * 3, accuracy: 1)
        XCTAssertEqual(image.fileName, "Stephen-Curry-\(StatScoutSeason.bundledNewest).png")

        let attachment = XCTAttachment(data: image.png, uniformTypeIdentifier: "public.png")
        attachment.name = "share-card"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testShareMessageLinksTheAppStoreListing() {
        let message = StatScoutShare.message(for: card.player, seasonLabel: "2026")
        XCTAssertTrue(message.contains("https://apps.apple.com/app/id\(AppStoreReviewLinks.appStoreID)"))
        XCTAssertTrue(message.hasPrefix("Stephen Curry, 2026 percentiles"))
    }
}
