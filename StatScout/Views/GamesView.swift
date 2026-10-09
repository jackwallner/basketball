import SwiftUI

/// Route to one game's detail page. Registered with the player-profile route so
/// every tab that can show a player can also open the game he played in.
struct GameRoute: Hashable {
    let gameId: String
}

/// The night's slate: who played whom, the finals, what is on next.
///
/// This is the front door. Scores, schedule and box scores are free for
/// everyone; the analysis layers stay where they were.
struct GamesView: View {
    @Bindable var viewModel: DashboardViewModel
    let isActive: Bool
    @State private var favorites = FavoritesStore.shared
    @State private var selectedDayID: String?

    private var days: [GameDay] { viewModel.slateDays }

    private var selectedDay: GameDay? {
        days.first { $0.id == selectedDayID } ?? viewModel.currentGameDay
    }

    private var slate: [Game] {
        guard let selectedDay else { return [] }
        return Game.slateOrder(viewModel.slateGames(on: selectedDay))
    }

    /// "Tue, Oct 20 · 2026-27 · 3 games".
    private var dayHeading: String? {
        guard let selectedDay else { return nil }
        let season = slate.first.map { SeasonLabel.text($0.season) }
        let count = slate.count == 1 ? "1 game" : "\(slate.count) games"
        return [selectedDay.label, season, count].compactMap { $0 }.joined(separator: " · ")
    }

    private var favoriteGame: Game? {
        guard let team = favorites.team else { return nil }
        return slate.first { $0.involves(team) }
    }

    var body: some View { let _ = TabProbe.hit("GamesView") // TABPROBE
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.slateGames.isEmpty {
                    emptyState
                } else {
                    daySelector
                        .padding(.top, 10)
                    if let heading = dayHeading {
                        Text(heading)
                            .font(HardwoodType.micro)
                            .foregroundStyle(HardwoodPalette.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    content
                }
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(HardwoodPalette.canvas.ignoresSafeArea())
        .refreshable { await viewModel.loadGames(force: true) }
        .task(id: isActive) {
            guard isActive else { return }
            await pollWhileActive()
        }
    }

    /// Re-reads the schedule while this tab is on screen: every two minutes
    /// while a game is under way or a final is still waiting on its stats, every
    /// ten otherwise. The backend itself only updates every fifteen minutes on a
    /// game day, so anything faster would be noise.
    private func pollWhileActive() async {
        while !Task.isCancelled {
            await viewModel.loadGames()
            let now = Date()
            let busy = viewModel.games.contains { game in
                switch game.status(now: now) {
                case .inProgress, .awaitingScore: return true
                case .final:
                    guard let tipoff = game.tipoff else { return false }
                    return !viewModel.hasStats(game) && now.timeIntervalSince(tipoff) < 12 * 3_600
                case .upcoming: return false
                }
            }
            try? await Task.sleep(for: .seconds(busy ? 120 : 600))
        }
    }

    // MARK: - Day selector

    private var daySelector: some View {
        let selectedID = selectedDay?.id
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(days) { day in
                        let isSelected = day.id == selectedID
                        Button {
                            selectedDayID = day.id
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(day.shortLabel)
                                .font(HardwoodType.smallBold)
                                .foregroundStyle(isSelected ? .white : HardwoodPalette.inkSecondary)
                                .padding(.horizontal, 12)
                                .frame(height: HardwoodControl.height)
                                .background(isSelected ? HardwoodPalette.court : HardwoodPalette.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.clear : HardwoodPalette.hairline, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .id(day.id)
                        .accessibilityLabel(day.label)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
                    }
                }
                .padding(.horizontal, 12)
            }
            .onAppear {
                if let id = selectedDay?.id { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: selectedDay?.id) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    // MARK: - Slate

    @ViewBuilder
    private var content: some View {
        if let favoriteGame {
            section(title: "Your team", games: [favoriteGame])
        }
        let now = Date()
        let remaining = slate.filter { $0.id != favoriteGame?.id }
        let live = remaining.filter { [.inProgress, .awaitingScore].contains($0.status(now: now)) }
        let finals = remaining.filter { $0.status(now: now) == .final }
        let upcoming = remaining.filter { $0.status(now: now) == .upcoming }
        if !live.isEmpty { section(title: "In progress", games: live) }
        if !finals.isEmpty { section(title: "Final", games: finals) }
        if !upcoming.isEmpty { section(title: "Upcoming", games: upcoming) }

        if upcoming.contains(where: { viewModel.projection(for: $0) != nil }) {
            Text("Projected margins come from StatScout Power Ratings: each team's points per 100 possessions against an average team, adjusted for schedule, plus two and a half points for home court. Details on the Teams tab.")
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }

        if viewModel.isSeasonPending, selectedDay?.id == viewModel.currentGameDay?.id, !viewModel.lastPlayedGames.isEmpty {
            section(title: "Last played · \(SeasonLabel.text(viewModel.freeSeason))", games: viewModel.lastPlayedGames)
        }

        Text(favorites.team == nil
             ? "Scores post when each game goes final, stats usually within a few hours. Follow a team from its page to pin its game here."
             : "Scores post when each game goes final. Player stats usually follow within a few hours.")
            .font(HardwoodType.micro)
            .foregroundStyle(HardwoodPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private func section(title: String, games: [Game]) -> some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: title)
            ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                NavigationLink(value: GameRoute(gameId: game.id)) {
                    GameRow(
                        game: game,
                        hasStats: viewModel.hasStats(game),
                        highlight: favorites.team,
                        awayRecord: viewModel.record(forTeam: game.awayTeam, through: game),
                        homeRecord: viewModel.record(forTeam: game.homeTeam, through: game),
                        projection: viewModel.projection(for: game)
                    )
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
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isGamesLoading {
            ProgressView("Loading games")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
        } else {
            ContentUnavailableView {
                Label(
                    viewModel.gamesError == nil ? "No games scheduled" : "Couldn't load games",
                    systemImage: viewModel.gamesError == nil ? "calendar" : "wifi.slash"
                )
            } description: {
                Text(viewModel.gamesError ?? "The \(SeasonLabel.text(viewModel.upcomingSeason ?? viewModel.freeSeason)) schedule isn't published yet.")
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.loadGames(force: true) }
                }
                .buttonStyle(.borderedProminent)
                .tint(HardwoodPalette.court)
            }
            .padding(.vertical, 48)
        }
    }
}

// MARK: - Row

/// Two stacked team lines with scores, and the status on the right.
struct GameRow: View {
    let game: Game
    let hasStats: Bool
    var highlight: String? = nil
    /// Each team's record through this game: after it for a final, going into
    /// it for one still to be played.
    var awayRecord: String? = nil
    var homeRecord: String? = nil
    /// The power ratings' projected margin, upcoming games only.
    var projection: GameProjection? = nil

    var body: some View {
        let status = game.status()
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                teamLine(game.awayTeam, score: game.awayScore, status: status, record: awayRecord)
                teamLine(game.homeTeam, score: game.homeScore, status: status, record: homeRecord)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 3) {
                Text(statusTitle(status))
                    .font(HardwoodType.smallBold)
                    .foregroundStyle(status == .inProgress ? HardwoodPalette.performanceLow : HardwoodPalette.ink)
                if let detail = statusDetail(status) {
                    Text(detail)
                        .font(HardwoodType.micro)
                        .foregroundStyle(HardwoodPalette.inkTertiary)
                }
            }
            .frame(width: 104, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HardwoodPalette.inkTertiary)
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .padding(.vertical, 10)
        .overlay(
            Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(status))
        .accessibilityHint("Opens the game")
    }

    private func teamLine(_ team: String, score: Int?, status: GameStatus, record: String?) -> some View {
        let isWinner = game.result(for: team) == "W"
        let dim = status == .final && !isWinner && game.result(for: team) != "T"
        return HStack(spacing: 8) {
            TeamColorDot(abbr: team, size: 10)
            Text(displayTeamAbbr(team))
                .font(HardwoodType.bodyBold)
                .foregroundStyle(dim ? HardwoodPalette.inkTertiary : HardwoodPalette.ink)
                .frame(width: 40, alignment: .leading)
            // The full name plus a record does not fit beside the score, so a
            // row that carries a record shows the nickname ("Knicks").
            Text(record == nil ? teamFullName(team) : (teamFullName(team).split(separator: " ").last.map(String.init) ?? team))
                .font(HardwoodType.small)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let record {
                Text(record)
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
            if let highlight, normalizedTeamAbbreviation(highlight) == normalizedTeamAbbreviation(team) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.yellow)
            }
            Spacer(minLength: 4)
            if let score {
                Text("\(score)")
                    .font(HardwoodType.statMed)
                    .foregroundStyle(dim ? HardwoodPalette.inkTertiary : HardwoodPalette.ink)
                    .monospacedDigit()
            }
        }
    }

    private func statusTitle(_ status: GameStatus) -> String {
        switch status {
        case .final: return game.overtime ? "Final/OT" : "Final"
        case .inProgress: return "In progress"
        case .awaitingScore: return "Final soon"
        case .upcoming: return game.tipoffLabel
        }
    }

    private func statusDetail(_ status: GameStatus) -> String? {
        switch status {
        case .final: return hasStats ? game.dayLabel : "Stats arriving"
        case .inProgress, .awaitingScore: return "Score at final"
        case .upcoming:
            if let projection {
                return projection.label(home: game.homeTeam, away: game.awayTeam)
            }
            return game.tipoff.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        }
    }

    private func accessibilityText(_ status: GameStatus) -> String {
        let away = teamFullName(game.awayTeam)
        let home = teamFullName(game.homeTeam)
        switch status {
        case .final:
            let score = "\(away) \(game.awayScore ?? 0), \(home) \(game.homeScore ?? 0)"
            return "\(score), \(statusTitle(status))" + (hasStats ? "" : ", stats arriving")
        case .inProgress, .awaitingScore:
            return "\(away) at \(home), in progress"
        case .upcoming:
            let projected = projection.map { ", projected \($0.label(home: game.homeTeam, away: game.awayTeam))" } ?? ""
            return "\(away) at \(home), \(game.dayLabel) at \(game.tipoff?.formatted(date: .omitted, time: .shortened) ?? "time TBD")\(projected)"
        }
    }
}
