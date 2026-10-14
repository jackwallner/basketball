import SwiftUI

/// The six numbers a fan checks first on a team page, each with its league
/// rank: scoring both ways, the margin, and the power rating split into
/// offense and defense. Live season only, the one season with standings and
/// ratings loaded.
struct TeamSeasonGlance: View {
    @Bindable var viewModel: DashboardViewModel
    let team: String

    private struct Tile: Identifiable {
        let label: String
        let value: String
        let rank: Int
        var id: String { label }
    }

    /// 1-based rank of `value` among `values`, best first.
    private static func rank(_ value: Double, among values: [Double], higherIsBetter: Bool = true) -> Int {
        values.filter { higherIsBetter ? $0 > value : $0 < value }.count + 1
    }

    private var tiles: [Tile] {
        let abbr = normalizedTeamAbbreviation(team)
        let rows = Array(viewModel.standings.values)
        // A rank means little until every team has a few games: on opening
        // night "1st" would be first of two.
        guard rows.count >= 30, rows.allSatisfy({ $0.games >= 3 }),
              let row = viewModel.standings[abbr] else { return [] }
        func perGame(_ total: Int, _ games: Int) -> Double { Double(total) / Double(games) }
        let tenths: (Double) -> String = { String(format: "%.1f", $0) }

        let scored = rows.map { perGame($0.pointsFor, $0.games) }
        let allowed = rows.map { perGame($0.pointsAgainst, $0.games) }
        let margins = rows.map { perGame($0.differential, $0.games) }
        let myScored = perGame(row.pointsFor, row.games)
        let myAllowed = perGame(row.pointsAgainst, row.games)
        let myMargin = perGame(row.differential, row.games)
        var out = [
            Tile(label: "Points / game", value: tenths(myScored), rank: Self.rank(myScored, among: scored)),
            Tile(label: "Allowed / game", value: tenths(myAllowed), rank: Self.rank(myAllowed, among: allowed, higherIsBetter: false)),
            Tile(label: "Margin", value: TeamRating.signed(myMargin), rank: Self.rank(myMargin, among: margins)),
        ]
        // Only the season this card is titled with; a rating a season behind
        // (the days after the rollover) waits for its own.
        if let rating = viewModel.teamRating(abbr), rating.season == viewModel.freeSeason {
            let all = Array(viewModel.teamRatings.values)
            out.append(Tile(label: "Offense", value: TeamRating.signed(rating.offense),
                            rank: Self.rank(rating.offense, among: all.map(\.offense))))
            out.append(Tile(label: "Defense", value: TeamRating.signed(rating.defense),
                            rank: Self.rank(rating.defense, among: all.map(\.defense))))
            out.append(Tile(label: "Power", value: TeamRating.signed(rating.rating),
                            rank: Self.rank(rating.rating, among: all.map(\.rating))))
        }
        return out
    }

    var body: some View {
        let tiles = tiles
        if !tiles.isEmpty {
            VStack(spacing: 0) {
                HardwoodSectionBar(title: "\(SeasonLabel.text(viewModel.freeSeason)) AT A GLANCE")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
                    ForEach(tiles) { tile in
                        tileView(tile)
                    }
                }
                Text("League rank under each number, 1st is best. Offense, defense and power are StatScout Power Ratings: points per 100 possessions against an average team, adjusted for schedule.")
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HardwoodGeo.padCard)
                    .padding(.vertical, 8)
            }
            .background(HardwoodPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                    .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
            )
        }
    }

    private func tileView(_ tile: Tile) -> some View {
        // 1st reads as the 100th percentile, 30th as the 0th, on the app's ramp.
        let percentile = Int((Double(30 - tile.rank) / 29 * 100).rounded())
        return VStack(spacing: 3) {
            Text(tile.value)
                .font(HardwoodType.statMed)
                .foregroundStyle(HardwoodPalette.ink)
                .monospacedDigit()
            Text(tile.label)
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(tile.rank.ordinalString)
                .font(HardwoodType.smallBold)
                .foregroundStyle(HardwoodPalette.textColor(forPercentile: max(0, min(100, percentile))))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.label) \(tile.value), \(tile.rank.ordinalString) in the league")
    }
}
