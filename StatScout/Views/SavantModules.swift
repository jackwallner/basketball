import SwiftUI

private func positionAndHandedness(_ player: Player) -> String {
    let pos = player.displayPosition.trimmingCharacters(in: .whitespaces)
    let hand = player.handedness.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
    if pos.isEmpty && hand.isEmpty { return "" }
    if hand.isEmpty { return pos }
    if pos.isEmpty { return hand }
    return "\(pos) · \(hand)"
}

private func displayTeamFullName(_ abbr: String) -> String {
    let trimmed = abbr.trimmingCharacters(in: .whitespaces).uppercased()
    if trimmed.isEmpty || trimmed == "TBD" || trimmed == "\u{2014}" || trimmed == "-" {
        return "Free Agent"
    }
    return teamFullName(abbr)
}

// MARK: - Module 1: Player Identity Strip

struct PlayerIdentityStrip: View {
    let player: Player
    var showOverallBadge: Bool = false
    /// Bio from `player_profiles`; nil keeps the strip to team and position.
    var profile: PlayerProfile? = nil

    /// "#11 · G · 24 yrs · 6-1, 196".
    private var bioLine: String {
        guard let profile else { return positionAndHandedness(player) }
        return [
            profile.jersey.map { "#\($0)" },
            player.displayPosition,
            profile.age().map { "\($0) yrs" },
            profile.sizeLabel,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// "2023 R1 #20", or "Undrafted".
    private var originLine: String? {
        profile?.draftLabel
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PlayerHeadshot(team: player.team, initials: player.initials, size: 72)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(HardwoodType.playerName)
                    .foregroundStyle(HardwoodPalette.inkOnDark)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(displayTeamFullName(player.team))
                    .font(HardwoodType.bodyBold)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(bioLine)
                    .font(HardwoodType.small)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let originLine {
                    Text(originLine)
                        .font(HardwoodType.small)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 8)
            if showOverallBadge {
                OverallPercentileBadge(percentile: player.overallPercentile)
            }
        }
        .padding(.horizontal, HardwoodGeo.padPage)
        .padding(.vertical, HardwoodGeo.padPage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HardwoodPalette.midnight)
    }
}

struct TeamIdentityStrip: View {
    let team: String
    var season: Int? = nil

    private var normalizedTeam: String {
        normalizedTeamAbbreviation(team)
    }

    private var seasonLabel: String {
        SeasonLabel.text(season ?? StatScoutSeason.calendarSeason()) + " Season"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(NBATeamColor.color(normalizedTeam))
                    .frame(width: 56, height: 56)
                Text(normalizedTeam)
                    .font(HardwoodType.pageTitle)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(teamFullName(normalizedTeam))
                    .font(HardwoodType.playerName)
                    .foregroundStyle(HardwoodPalette.inkOnDark)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(seasonLabel)
                    .font(HardwoodType.small)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, HardwoodGeo.padPage)
        .padding(.vertical, HardwoodGeo.padPage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HardwoodPalette.midnight)
    }
}

// MARK: - Module 3: Section Bar

struct HardwoodSectionBar: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 0) {
            Text(title.uppercased())
                .font(HardwoodType.sectionTitle)
                .foregroundStyle(HardwoodPalette.ink)
                .padding(.leading, HardwoodGeo.padCard)
            Spacer()
            if let trailing { trailing.padding(.trailing, 12) }
        }
        .frame(height: HardwoodGeo.rowHeightHeader)
        .background(HardwoodPalette.surfaceSunk)
    }
}

struct HardwoodSubSectionBar: View {
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = HardwoodPalette.inkSecondary

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(HardwoodType.statSmall)
                    .foregroundStyle(trailingColor)
            }
        }
        .frame(height: 26)
        .padding(.horizontal, HardwoodGeo.padCard)
        .background(HardwoodPalette.surfaceAlt)
        .overlay(Rectangle().fill(HardwoodPalette.divider).frame(height: 0.5), alignment: .bottom)
    }
}

// MARK: - Module 5: Tab Bar

struct HardwoodTabs: View {
    let tabs: [String]
    @Binding var selected: String

    /// Six basketball categories do not fit as equal columns at phone width
    /// ("PLAYMAKING" lost its tail even shrunk), so a long set scrolls and each
    /// tab keeps its natural width.
    private var scrolls: Bool { tabs.count > 4 }

    var body: some View {
        Group {
            if scrolls {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        tabRow
                    }
                    .onChange(of: selected) { _, next in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(next, anchor: .center) }
                    }
                }
            } else {
                tabRow
            }
        }
        .frame(maxWidth: .infinity)
        .background(HardwoodPalette.surface)
        .overlay(Rectangle().fill(HardwoodPalette.hairline).frame(height: HardwoodGeo.hairline), alignment: .bottom)
    }

    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button(action: {
                    selected = tab
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }) {
                    VStack(spacing: 0) {
                        Text(tab.uppercased())
                            .font(HardwoodType.smallBold)
                            .foregroundStyle(selected == tab ? HardwoodPalette.ink : HardwoodPalette.inkTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: scrolls, vertical: false)
                            .padding(.horizontal, scrolls ? 14 : 4)
                            .frame(maxWidth: scrolls ? nil : .infinity)
                            .frame(height: 40)
                        Rectangle()
                            .fill(selected == tab ? HardwoodPalette.court : Color.clear)
                            .frame(height: 3)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: scrolls ? nil : .infinity)
                .id(tab)
            }
        }
    }
}
