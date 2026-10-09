import SwiftUI

/// Conference standings from posted finals, with each team's power rating
/// beside its record.
struct StandingsView: View {
    @Bindable var viewModel: DashboardViewModel
    let conferences: [(name: String, teams: [String])]

    var body: some View {
        let table = viewModel.standings
        VStack(spacing: 12) {
            ForEach(conferences, id: \.name) { division in
                let rows = StandingsRow.ordered(division.teams.compactMap { table[$0] })
                VStack(spacing: 0) {
                    header(division.name)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        NavigationLink(value: TeamDestination(abbr: row.team)) {
                            line(row)
                                .background(index.isMultiple(of: 2) ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
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
            }
            Text("Ordered by win percentage, then point differential, not the NBA's full tiebreakers. PWR is the StatScout Power Rating: points per 100 possessions better or worse than an average team, adjusted for schedule.")
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
    }

    private func header(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text(title.uppercased())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("W-L").frame(width: 44, alignment: .trailing)
            Text("DIFF").frame(width: 44, alignment: .trailing)
            Text("STRK").frame(width: 40, alignment: .trailing)
            Text("PWR").frame(width: 48, alignment: .trailing)
        }
        .font(HardwoodType.micro)
        .foregroundStyle(HardwoodPalette.inkTertiary)
        .frame(height: HardwoodGeo.rowHeightHeader)
        .padding(.horizontal, HardwoodGeo.padInline)
        .background(HardwoodPalette.surfaceAlt)
        .overlay(Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline), alignment: .bottom)
    }

    private func line(_ row: StandingsRow) -> some View {
        let rating = viewModel.teamRating(row.team)
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                TeamColorDot(abbr: row.team, size: 10)
                Text(displayTeamAbbr(row.team))
                    .font(HardwoodType.bodyBold)
                    .foregroundStyle(HardwoodPalette.ink)
                    .frame(width: 40, alignment: .leading)
                Text(teamNickname(row.team))
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.record)
                .font(HardwoodType.statSmall)
                .foregroundStyle(HardwoodPalette.ink)
                .frame(width: 44, alignment: .trailing)
            Text(row.games == 0 ? "-" : (row.differential > 0 ? "+\(row.differential)" : "\(row.differential)"))
                .font(HardwoodType.statSmall)
                .foregroundStyle(row.differential > 0 ? HardwoodPalette.performanceHigh : (row.differential < 0 ? HardwoodPalette.performanceLow : HardwoodPalette.inkSecondary))
                .frame(width: 44, alignment: .trailing)
            Text(row.streak ?? "-")
                .font(HardwoodType.statSmall)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .frame(width: 40, alignment: .trailing)
            Text(rating.map { TeamRating.signed($0.rating) } ?? "-")
                .font(HardwoodType.statSmall)
                .foregroundStyle(HardwoodPalette.ink)
                .frame(width: 48, alignment: .trailing)
        }
        .monospacedDigit()
        .frame(height: 44)
        .padding(.horizontal, HardwoodGeo.padInline)
        .overlay(Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline), alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(teamFullName(row.team)), \(row.record), point differential \(row.differential)"
                + (rating.map { ", power rating \(TeamRating.signed($0.rating))" } ?? "")
        )
    }
}

/// The league ranked by power rating: what a team scores minus what it allows
/// per 100 possessions, adjusted for who it played.
struct PowerRankingsView: View {
    @Bindable var viewModel: DashboardViewModel

    private var ratings: [TeamRating] {
        viewModel.teamRatings.values.sorted { $0.rank < $1.rank }
    }

    var body: some View {
        VStack(spacing: 12) {
            if ratings.isEmpty {
                ContentUnavailableView {
                    Label("Power ratings loading", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("Ratings arrive with the next update. Pull to refresh.")
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .background(HardwoodPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
            } else {
                VStack(spacing: 0) {
                    header
                    ForEach(Array(ratings.enumerated()), id: \.element.id) { index, rating in
                        NavigationLink(value: TeamDestination(abbr: rating.team)) {
                            line(rating)
                                .background(index.isMultiple(of: 2) ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
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
            }
            Text(footnote)
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
    }

    private var footnote: String {
        let preseason = ratings.first.map { $0.games == 0 } ?? false
        let lead = preseason ? "Preseason: last season's ratings, regressed. " : ""
        return lead + "Points per 100 possessions better or worse than an average team: what a team scores plus what it holds opponents under, adjusted for schedule. Early in the season, last season's rating carries part of the weight. Read two ratings like a spread, with about two and a half points for home court."
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 28, alignment: .leading)
            Text("TEAM").frame(maxWidth: .infinity, alignment: .leading)
            Text("OFF").frame(width: 44, alignment: .trailing)
            Text("DEF").frame(width: 44, alignment: .trailing)
            Text("RATING").frame(width: 60, alignment: .trailing)
        }
        .font(HardwoodType.micro)
        .foregroundStyle(HardwoodPalette.inkTertiary)
        .frame(height: HardwoodGeo.rowHeightHeader)
        .padding(.horizontal, HardwoodGeo.padInline)
        .background(HardwoodPalette.surfaceAlt)
        .overlay(Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline), alignment: .bottom)
    }

    private func line(_ rating: TeamRating) -> some View {
        let record = viewModel.standings[normalizedTeamAbbreviation(rating.team)]?.record
        return HStack(spacing: 0) {
            Text("\(rating.rank)")
                .font(HardwoodType.statSmall)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .frame(width: 28, alignment: .leading)
            HStack(spacing: 8) {
                TeamColorDot(abbr: rating.team, size: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(teamFullName(rating.team))
                        .font(HardwoodType.bodyBold)
                        .foregroundStyle(HardwoodPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let record {
                        Text(record)
                            .font(HardwoodType.micro)
                            .foregroundStyle(HardwoodPalette.inkTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(TeamRating.signed(rating.offense))
                .font(HardwoodType.statSmall)
                .foregroundStyle(tint(rating.offense))
                .frame(width: 44, alignment: .trailing)
            Text(TeamRating.signed(rating.defense))
                .font(HardwoodType.statSmall)
                .foregroundStyle(tint(rating.defense))
                .frame(width: 44, alignment: .trailing)
            Text(TeamRating.signed(rating.rating))
                .font(HardwoodType.statMed)
                .foregroundStyle(tint(rating.rating))
                .frame(width: 60, alignment: .trailing)
        }
        .monospacedDigit()
        .frame(height: HardwoodGeo.rowHeight)
        .padding(.horizontal, HardwoodGeo.padInline)
        .overlay(Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline), alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(rating.rank). \(teamFullName(rating.team)), rating \(TeamRating.signed(rating.rating)), offense \(TeamRating.signed(rating.offense)), defense \(TeamRating.signed(rating.defense))"
        )
    }

    private func tint(_ value: Double) -> Color {
        if value >= 1 { return HardwoodPalette.performanceHigh }
        if value <= -1 { return HardwoodPalette.performanceLow }
        return HardwoodPalette.inkSecondary
    }
}

/// "Celtics" from "Boston Celtics".
func teamNickname(_ abbr: String) -> String {
    teamFullName(abbr).split(separator: " ").last.map(String.init) ?? abbr
}
