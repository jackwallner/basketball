import SwiftUI

struct TeamScheduleRoute: Hashable {
    let team: String
}

/// The game a team page leads with: the live one, last night's result, the next
/// tip-off, or, in the offseason, how the team's season ended. It sits above the
/// roster cards so the first thing a team page says is what happened on the
/// court. Under it: follow the team, open its schedule.
struct TeamGameCard: View {
    @Bindable var viewModel: DashboardViewModel
    let team: String
    @State private var favorites = FavoritesStore.shared

    /// Which game, and why it is the one shown.
    enum Kind {
        case live, last, next

        var title: String {
            switch self {
            case .live: return "Live"
            case .last: return "Last game"
            case .next: return "Next game"
            }
        }
    }

    /// In progress beats everything; a final from the last day beats the next
    /// game (the result is what people open the page for the morning after);
    /// otherwise the next tip-off, or the latest final once the schedule runs out.
    private var featured: (kind: Kind, game: Game)? {
        let games = viewModel.schedule(forTeam: team)
        let now = Date()
        if let live = games.first(where: { [.inProgress, .awaitingScore].contains($0.status(now: now)) }) {
            return (.live, live)
        }
        let finals = games.filter { $0.status(now: now) == .final }
        if let last = finals.last, let tip = last.tipoff, now.timeIntervalSince(tip) < 24 * 3_600 {
            return (.last, last)
        }
        if let next = games.first(where: { $0.status(now: now) == .upcoming }) {
            return (.next, next)
        }
        return finals.last.map { (.last, $0) }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let featured {
                NavigationLink(value: GameRoute(gameId: featured.game.id)) {
                    content(kind: featured.kind, game: featured.game)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the game")
            }
            actions
        }
    }

    private var actions: some View {
        let following = favorites.isFavorite(team: normalizedTeamAbbreviation(team))
        return HStack(spacing: 8) {
            Button {
                favorites.setFavorite(team: following ? nil : normalizedTeamAbbreviation(team))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HardwoodChip(
                    title: following ? "Your team" : "Follow team",
                    systemImage: following ? "star.fill" : "star",
                    isActive: following
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(following ? "Stops pinning this team's games" : "Pins this team's games at the top of Games")

            NavigationLink(value: TeamScheduleRoute(team: normalizedTeamAbbreviation(team))) {
                HardwoodChip(title: "Schedule", systemImage: "calendar")
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private func content(kind: Kind, game: Game) -> some View {
        shell(kind: kind, game: game) {
            TeamColorDot(abbr: game.opponent(of: team), size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.matchupLabel(for: team)) · \(teamFullName(game.opponent(of: team)))")
                    .font(HardwoodType.bodyBold)
                    .foregroundStyle(HardwoodPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(detail(game))
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
            }
            Spacer(minLength: 8)
            if let line = game.resultLine(for: team) {
                Text(line)
                    .font(HardwoodType.statMed)
                    .foregroundStyle(game.result(for: team) == "L" ? HardwoodPalette.performanceLow : HardwoodPalette.performanceHigh)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HardwoodPalette.inkTertiary)
        }
    }

    private func detail(_ game: Game) -> String {
        switch game.status() {
        case .final:
            return "\(game.dayLabel) · " + (viewModel.hasStats(game) ? "box score" : "stats arriving")
        case .inProgress, .awaitingScore:
            return "In progress"
        case .upcoming:
            return "\(game.dayLabel), \(game.tipoff?.formatted(date: .omitted, time: .shortened) ?? "time TBD")"
        }
    }

    private func shell<Content: View>(kind: Kind, game: Game, @ViewBuilder content: () -> Content) -> some View {
        // The record belongs to the live season; a 2026-27 game has none yet.
        let record = game.season == viewModel.freeSeason ? viewModel.record(forTeam: team) : nil
        return VStack(alignment: .leading, spacing: 6) {
            Text(([kind.title, SeasonLabel.text(game.season)] + [record].compactMap { $0 }).joined(separator: " · ").uppercased())
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkSecondary)
            HStack(spacing: 10) {
                content()
            }
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }
}

/// One team's schedule: every game, the opponent, the result or the tip-off.
struct TeamScheduleView: View {
    @Bindable var viewModel: DashboardViewModel
    let team: String

    /// One season's games for the team, in tip-off order.
    private struct SeasonBlock: Identifiable {
        let season: Int
        let games: [Game]
        var id: Int { season }
    }

    /// The live season, then the upcoming one while it is pending. Newest first
    /// would bury this season's results under a list of games not yet played, so
    /// the order is the order they happen in.
    private var sections: [SeasonBlock] {
        Dictionary(grouping: viewModel.schedule(forTeam: team), by: \.season)
            .map { SeasonBlock(season: $0.key, games: $0.value) }
            .sorted { $0.season < $1.season }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sections) { section in
                    card(section)
                }
                if sections.isEmpty {
                    Text(viewModel.isGamesLoading ? "Loading schedule" : "Schedule not published yet")
                        .font(HardwoodType.small)
                        .foregroundStyle(HardwoodPalette.inkTertiary)
                        .padding(.vertical, 32)
                }
                Color.clear.frame(height: 88)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .background(HardwoodPalette.canvas.ignoresSafeArea())
        .navigationTitle(teamFullName(team))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadGames() }
    }

    private func card(_ section: SeasonBlock) -> some View {
        let isLive = section.season == viewModel.freeSeason
        return VStack(spacing: 0) {
            HardwoodSectionBar(
                title: "\(SeasonLabel.text(section.season)) schedule",
                trailing: (isLive ? viewModel.record(forTeam: team) : nil).map {
                    AnyView(Text($0).font(HardwoodType.statSmall).foregroundStyle(HardwoodPalette.inkSecondary))
                }
            )
            ForEach(Array(numbered(section.games).enumerated()), id: \.element.game.id) { index, entry in
                NavigationLink(value: GameRoute(gameId: entry.game.id)) {
                    row(entry.game, number: entry.number)
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

    /// Games numbered within their phase: 1 to 82 for the regular season, then
    /// "P1", "P2"... for the playoffs.
    private func numbered(_ games: [Game]) -> [(game: Game, number: String)] {
        var counts: [SeasonPhase: Int] = [:]
        return games.map { game in
            counts[game.seasonPhase, default: 0] += 1
            let n = counts[game.seasonPhase] ?? 0
            return (game, game.seasonPhase == .regular ? "\(n)" : "P\(n)")
        }
    }

    private func row(_ game: Game, number: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(HardwoodType.statSmall)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .frame(width: 30, alignment: .leading)
            TeamColorDot(abbr: game.opponent(of: team), size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.matchupLabel(for: team)) · \(teamFullName(game.opponent(of: team)))")
                    .font(HardwoodType.bodyBold)
                    .foregroundStyle(HardwoodPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(game.dayLabel)
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
            }
            Spacer(minLength: 8)
            if let line = game.resultLine(for: team) {
                Text(line)
                    .font(HardwoodType.statMed)
                    .foregroundStyle(game.result(for: team) == "L" ? HardwoodPalette.performanceLow : HardwoodPalette.performanceHigh)
            } else {
                Text(game.status() == .upcoming ? (game.tipoff?.formatted(date: .omitted, time: .shortened) ?? "TBD") : "In progress")
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HardwoodPalette.inkTertiary)
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .frame(minHeight: 52)
        .overlay(Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline), alignment: .bottom)
        .contentShape(Rectangle())
    }
}

/// A player's most recent game on his profile: opponent, result, his line, and
/// a way into the box score. Free, and real: the one-game answer to "how did he
/// look?" that the recent-form cards can't give until there are several games.
struct PlayerLastGameCard: View {
    @Bindable var viewModel: DashboardViewModel
    let player: Player
    let season: Int
    let phase: SeasonPhase

    @State private var log: PlayerGameLog?
    @State private var loadedKey: String?

    private var key: String {
        "\(player.playerId)-\(season)-\(phase.rawValue)-\(viewModel.freshnessRevision ?? "none")"
    }

    private var game: Game? {
        log?.gameId.flatMap { viewModel.game(id: $0) }
    }

    var body: some View {
        // A VStack, not a Group: modifiers on an empty Group land on no view,
        // so the task that fetches the log would never run.
        VStack(spacing: 0) {
            if let log {
                card(log)
                    .padding(.top, 10)
            }
        }
        .task(id: key) { await load() }
    }

    private func load() async {
        guard loadedKey != key else { return }
        do {
            let logs = try await viewModel.fetchGameLogs(playerId: player.playerId, season: season, seasonPhase: phase)
            log = logs.max { $0.gameDate < $1.gameDate }
            loadedKey = key
        } catch {
            if !isTaskCancellation(error) { loadedKey = nil }
        }
    }

    @ViewBuilder
    private func card(_ log: PlayerGameLog) -> some View {
        let line = GameBoxScore(logs: [log]).lines[0]
        let team = log.team ?? player.team
        let summary = GameBoxScore.summary(line)
        let content = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title(log).uppercased())
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
                Spacer(minLength: 0)
                if game != nil {
                    Text("Box score")
                        .font(HardwoodType.micro)
                        .foregroundStyle(HardwoodPalette.court)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HardwoodPalette.court)
                }
            }
            HStack(spacing: 8) {
                Text(matchup(log, team: team))
                    .font(HardwoodType.bodyBold)
                    .foregroundStyle(HardwoodPalette.ink)
                    .lineLimit(1)
                if let result = game?.resultLine(for: team) {
                    Text(result)
                        .font(HardwoodType.statSmall)
                        .foregroundStyle(game?.result(for: team) == "L" ? HardwoodPalette.performanceLow : HardwoodPalette.performanceHigh)
                }
                Spacer(minLength: 0)
            }
            if !summary.isEmpty {
                Text(summary)
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .contentShape(Rectangle())

        if let game {
            NavigationLink(value: GameRoute(gameId: game.id)) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the game")
        } else {
            content
        }
    }

    private func title(_ log: PlayerGameLog) -> String {
        if let game { return "Last game · \(game.dayLabel)" }
        return "Last game · \(log.gameDate.formatted(DataCoverage.gameDayStyle))"
    }

    private func matchup(_ log: PlayerGameLog, team: String) -> String {
        if let game { return game.matchupLabel(for: team) }
        return "vs \(displayTeamAbbr(log.opponent ?? ""))"
    }
}

/// Every game this season, newest first: opponent, result, and the player's
/// line. The night-by-night view an 82-game season is read in, free, and the
/// natural companion to the Pro rolling windows.
struct PlayerGameLogCard: View {
    @Bindable var viewModel: DashboardViewModel
    let player: Player
    let season: Int
    let phase: SeasonPhase

    @State private var entries: [Entry] = []
    @State private var loadedKey: String?
    @State private var failed = false

    struct Entry: Identifiable, Hashable {
        let id: String
        let gameId: String?
        let gameDate: Date
        let team: String
        let opponent: String?
        let summary: String
    }

    private var key: String {
        "\(player.playerId)-\(season)-\(phase.rawValue)-\(viewModel.freshnessRevision ?? "none")"
    }

    var body: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: "GAME LOG")
            if entries.isEmpty {
                Text(failed ? "Couldn't load games. Pull to refresh." : (loadedKey == nil ? "Loading games…" : "No games yet this season."))
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry)
                        .background(index.isMultiple(of: 2) ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                }
            }
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .task(id: key) { await load() }
    }

    private func load() async {
        guard loadedKey != key else { return }
        do {
            let logs = try await viewModel.fetchGameLogs(playerId: player.playerId, season: season, seasonPhase: phase)
            entries = Self.entries(from: logs, fallbackTeam: player.team)
            loadedKey = key
            failed = false
        } catch {
            if !isTaskCancellation(error) { failed = true }
        }
    }

    /// One entry per game; a player with two rows in a game (a player ranked in
    /// two position cohorts) reads as one line.
    static func entries(from logs: [PlayerGameLog], fallbackTeam: String) -> [Entry] {
        let grouped = Dictionary(grouping: logs) { $0.gameId ?? ISO8601DateFormatter().string(from: $0.gameDate) }
        return grouped.map { id, rows in
            let first = rows[0]
            let summary = GameBoxScore(logs: rows).lines
                .map(GameBoxScore.summary)
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return Entry(
                id: id,
                gameId: first.gameId,
                gameDate: first.gameDate,
                team: first.team ?? fallbackTeam,
                opponent: first.opponent,
                summary: summary
            )
        }
        .sorted { $0.gameDate > $1.gameDate }
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        let game = entry.gameId.flatMap { viewModel.game(id: $0) }
        let content = HStack(alignment: .top, spacing: 10) {
            Text(entry.gameDate.formatted(DataCoverage.gameDayStyle))
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(game?.matchupLabel(for: entry.team) ?? "vs \(displayTeamAbbr(entry.opponent ?? ""))")
                        .font(HardwoodType.bodyBold)
                        .foregroundStyle(HardwoodPalette.ink)
                    if let line = game?.resultLine(for: entry.team) {
                        Text(line)
                            .font(HardwoodType.statSmall)
                            .foregroundStyle(game?.result(for: entry.team) == "L" ? HardwoodPalette.performanceLow : HardwoodPalette.performanceHigh)
                    }
                    Spacer(minLength: 0)
                }
                Text(entry.summary.isEmpty ? "No box score line" : entry.summary)
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline), alignment: .bottom)
        .contentShape(Rectangle())

        if let game {
            NavigationLink(value: GameRoute(gameId: game.id)) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the game")
        } else {
            content
        }
    }
}
