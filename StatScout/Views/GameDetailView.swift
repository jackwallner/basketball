import Charts
import SwiftUI

/// One game: the score first, then how the margin moved, the four factors, the
/// plays that decided it and the box score.
struct GameDetailView: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    let gameId: String

    @State private var paywallTrigger: PaywallTrigger?
    @State private var detail: GameDetail?
    @State private var isDetailLoading = false
    @State private var detailFailed = false

    @State private var logs: [PlayerGameLog] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var boxTeam: String = ""

    private var game: Game? { viewModel.game(id: gameId) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let game {
                    header(game)
                    detail(for: game)
                } else if viewModel.isGamesLoading {
                    ProgressView().padding(.vertical, 64)
                } else {
                    ContentUnavailableView("Game not found", systemImage: "calendar.badge.exclamationmark")
                        .padding(.vertical, 48)
                }
                Color.clear.frame(height: 88)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(HardwoodPalette.canvas.ignoresSafeArea())
        .navigationTitle(game.map { "\(displayTeamAbbr($0.awayTeam)) at \(displayTeamAbbr($0.homeTeam))" } ?? "Game")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadGames(force: true)
            await loadLogs(force: true)
            await loadDetail()
        }
        .task { await viewModel.loadGames() }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
        .modifier(LiveScorePolling(viewModel: viewModel))
        .task(id: "\(gameId)-\(game.map(viewModel.hasStats) ?? false)-\(viewModel.freshnessRevision ?? "none")") {
            async let details: Void = loadDetail()
            async let lines: Void = loadLogs(force: false)
            _ = await (details, lines)
        }
    }

    private var boxScore: GameBoxScore { GameBoxScore(logs: logs) }

    /// Tracked apart from the box score, so a request still in flight or one
    /// that failed never reads as "not published yet".
    private func loadDetail() async {
        guard let game, game.status() != .upcoming else { return }
        isDetailLoading = detail == nil
        defer { isDetailLoading = false }
        do {
            if let loaded = try await viewModel.fetchGameDetail(gameId: gameId) {
                detail = loaded
            }
            detailFailed = false
        } catch {
            if !isTaskCancellation(error), detail == nil {
                detailFailed = true
            }
        }
    }

    private func loadLogs(force: Bool) async {
        guard let game, game.status() == .final || viewModel.hasStats(game) else { return }
        if !force, !logs.isEmpty, viewModel.hasStats(game) { return }
        isLoading = logs.isEmpty
        do {
            logs = try await viewModel.fetchGameLogs(gameId: gameId)
            loadError = nil
        } catch {
            if !isTaskCancellation(error), logs.isEmpty {
                loadError = "Couldn't load the box score. Pull to try again."
            }
        }
        if boxTeam.isEmpty { boxTeam = game.awayTeam }
        isLoading = false
    }

    // MARK: - Header

    private func header(_ game: Game) -> some View {
        let status = game.status()
        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                teamColumn(game.awayTeam, game: game, label: "Away")
                VStack(spacing: 4) {
                    if game.isFinal {
                        HStack(spacing: 10) {
                            scoreText(game.awayScore, winner: game.result(for: game.awayTeam) != "L")
                            Text("-")
                                .font(HardwoodType.statLarge)
                                .foregroundStyle(HardwoodPalette.inkTertiary)
                            scoreText(game.homeScore, winner: game.result(for: game.homeTeam) != "L")
                        }
                    } else if let live = viewModel.liveScore(for: game) {
                        HStack(spacing: 10) {
                            scoreText(live.awayScore, winner: !live.isFinal || live.awayScore > live.homeScore)
                            Text("-")
                                .font(HardwoodType.statLarge)
                                .foregroundStyle(HardwoodPalette.inkTertiary)
                            scoreText(live.homeScore, winner: !live.isFinal || live.homeScore > live.awayScore)
                        }
                    } else {
                        Text(status == .upcoming ? game.tipoffLabel : game.startedLabel(live: nil))
                            .font(HardwoodType.cardTitle)
                            .foregroundStyle(status == .upcoming ? HardwoodPalette.ink : HardwoodPalette.performanceLow)
                    }
                    Text(statusLine(game, status: status))
                        .font(HardwoodType.micro)
                        .foregroundStyle(HardwoodPalette.inkTertiary)
                }
                .frame(minWidth: 110)
                teamColumn(game.homeTeam, game: game, label: "Home")
            }

            if let context = game.contextLine(series: viewModel.seriesStatus(for: game)) {
                Text(context.uppercased())
                    .font(HardwoodType.smallBold)
                    .foregroundStyle(HardwoodPalette.court)
                    .multilineTextAlignment(.center)
            }

            Text([
                game.seasonPhase == .playoffs && game.playoffRoundName == nil ? "Playoffs" : nil,
                SeasonLabel.text(game.season),
                game.dayLabel,
                game.stadium,
            ].compactMap { $0 }.joined(separator: " · "))
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func teamColumn(_ team: String, game: Game, label: String) -> some View {
        NavigationLink(value: TeamDestination(abbr: normalizedTeamAbbreviation(team))) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(NBATeamColor.color(team))
                    Text(displayTeamAbbr(team))
                        .font(HardwoodType.smallBold)
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 48, height: 48)
                Text(teamFullName(team))
                    .font(HardwoodType.smallBold)
                    .foregroundStyle(HardwoodPalette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(([label] + [game.countsInStandings ? viewModel.record(forTeam: team, through: game) : nil].compactMap { $0 }).joined(separator: " · "))
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the team")
    }

    private func scoreText(_ score: Int?, winner: Bool) -> some View {
        Text(score.map(String.init) ?? "-")
            .font(HardwoodType.statHero)
            .foregroundStyle(winner ? HardwoodPalette.ink : HardwoodPalette.inkTertiary)
            .monospacedDigit()
    }

    private func statusLine(_ game: Game, status: GameStatus) -> String {
        if let live = viewModel.liveScore(for: game) {
            return live.isFinal ? live.clockLabel : "Live · \(live.clockLabel)"
        }
        switch status {
        case .final: return game.overtime ? "Final/OT" : "Final"
        case .inProgress, .awaitingScore: return game.isScorePending() ? "No score posted yet" : "Score updates live"
        // The date is on the line below; the projection is the news here.
        case .upcoming: return viewModel.projection(for: game).map { $0.label(home: game.homeTeam, away: game.awayTeam) } ?? ""
        }
    }

    // MARK: - Body

    /// Advanced first, the way analytics box scores read: how the game swung,
    /// how each team played, the plays that decided it, who drove it. The
    /// traditional box score follows for the counts.
    @ViewBuilder
    private func detail(for game: Game) -> some View {
        if detail != nil || !logs.isEmpty {
            if let detail {
                if detail.margin.count > 2 {
                    marginCard(detail, game: game)
                }
                factorsCard(detail, game: game)
                if !detail.bigPlays.isEmpty {
                    bigPlaysCard(detail, game: game)
                }
                playerLinesCards(detail, game: game)
            } else if isDetailLoading {
                ProgressView("Loading advanced breakdown…")
                    .font(HardwoodType.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if detailFailed {
                notice(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't load the advanced breakdown",
                    text: "The score margin and four factors didn't load. Check your connection and try again.",
                    action: ("Try Again", { Task { await loadDetail() } })
                )
            } else {
                notice(
                    icon: "chart.xyaxis.line",
                    title: "Advanced breakdown on the way",
                    text: "The score margin, four factors and player ratings post once play-by-play is published, usually within a few hours of the final."
                )
            }

            if !logs.isEmpty {
                sectionHeading("Box score")
                leadersCard
                teamStatsCard(game)
                boxScoreCard(game)
            }

            footnote("Percentiles rank each number against every team game (or every player game of ten minutes or more) this season, and update as new games arrive. The four factors are eFG%, turnover rate, offensive rebound rate and free throw rate.")
            StatGlossaryLink()
                .padding(.horizontal, 12)
                .padding(.top, 12)
        } else if isLoading {
            ProgressView("Loading box score…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let loadError {
            footnote(loadError)
        } else {
            switch game.status() {
            case .final:
                notice(
                    icon: "clock",
                    title: "Stats arriving",
                    text: "The final score is in. Player stats usually post within a few hours of the final buzzer."
                )
            case .inProgress, .awaitingScore:
                if viewModel.liveScore(for: game)?.isFinal == true {
                    notice(
                        icon: "clock",
                        title: "Stats arriving",
                        text: "The game is final. Player stats usually post within a few hours of the final buzzer."
                    )
                } else if game.isScorePending() {
                    notice(
                        icon: "clock",
                        title: "Score pending",
                        text: "No score has posted for this game yet. It shows here once the final is in."
                    )
                } else {
                    notice(
                        icon: "basketball",
                        title: "Game in progress",
                        text: "The score updates live. The box score posts after the final."
                    )
                }
            case .upcoming:
                upcomingCard(game)
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(HardwoodType.sectionTitle)
            .foregroundStyle(HardwoodPalette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 24)
    }

    private var leadersCard: some View {
        card(title: "Game leaders") {
            ForEach(Array(boxScore.leaders.enumerated()), id: \.element.id) { index, leader in
                playerRow(line: leader.line, index: index) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            TeamColorDot(abbr: leader.line.team, size: 6)
                            Text("\(leader.title.uppercased()) · \(displayTeamAbbr(leader.line.team))")
                                .font(HardwoodType.micro)
                                .foregroundStyle(HardwoodPalette.inkTertiary)
                        }
                        nameText(leader.line)
                        Text(leader.summary)
                            .font(HardwoodType.small)
                            .foregroundStyle(HardwoodPalette.inkSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func teamStatsCard(_ game: Game) -> some View {
        let away = boxScore.totals(for: game.awayTeam)
        let home = boxScore.totals(for: game.homeTeam)
        func percent(_ value: Double?) -> Double { value ?? 0 }
        return card(title: "Team stats") {
            HStack {
                Text(displayTeamAbbr(game.awayTeam)).frame(width: 64, alignment: .leading)
                Spacer()
                Text(displayTeamAbbr(game.homeTeam)).frame(width: 64, alignment: .trailing)
            }
            .font(HardwoodType.smallBold)
            .foregroundStyle(HardwoodPalette.inkSecondary)
            .padding(.horizontal, HardwoodGeo.padCard)
            .frame(height: 30)
            .background(HardwoodPalette.surfaceAlt)

            comparisonRow("Field goals", percent(away.fieldGoalPercentage), percent(home.fieldGoalPercentage), higherIsBetter: true) { String(format: "%.1f%%", $0) }
            comparisonRow("Threes", percent(away.threePointPercentage), percent(home.threePointPercentage), higherIsBetter: true) { String(format: "%.1f%%", $0) }
            comparisonRow("Free throws", percent(away.freeThrowPercentage), percent(home.freeThrowPercentage), higherIsBetter: true) { String(format: "%.1f%%", $0) }
            comparisonRow("Rebounds", away.rebounds, home.rebounds, higherIsBetter: true)
            comparisonRow("Assists", away.assists, home.assists, higherIsBetter: true)
            comparisonRow("Steals", away.steals, home.steals, higherIsBetter: true)
            comparisonRow("Blocks", away.blocks, home.blocks, higherIsBetter: true)
            comparisonRow("Turnovers", away.turnovers, home.turnovers, higherIsBetter: false)
            comparisonRow("Fouls", away.fouls, home.fouls, higherIsBetter: false)
            footnoteRow("Totals add up each team's player lines.")
        }
    }

    private func comparisonRow(_ label: String, _ away: Double, _ home: Double, higherIsBetter: Bool, decimals: Int = 0) -> some View {
        comparisonRow(label, away, home, higherIsBetter: higherIsBetter) { value in
            decimals == 0
                ? Int(value.rounded()).formatted()
                : value.formatted(.number.precision(.fractionLength(decimals)).sign(strategy: .always(includingZero: false)))
        }
    }

    private func comparisonRow(_ label: String, _ away: Double, _ home: Double, higherIsBetter: Bool, format: @escaping (Double) -> String) -> some View {
        let awayBetter = higherIsBetter ? away > home : away < home
        let homeBetter = higherIsBetter ? home > away : home < away
        return HStack {
            Text(format(away))
                .font(HardwoodType.statMed)
                .fontWeight(awayBetter ? .bold : .regular)
                .foregroundStyle(awayBetter ? HardwoodPalette.ink : HardwoodPalette.inkSecondary)
                .frame(width: 64, alignment: .leading)
            Spacer()
            Text(label)
                .font(HardwoodType.small)
                .foregroundStyle(HardwoodPalette.inkSecondary)
            Spacer()
            Text(format(home))
                .font(HardwoodType.statMed)
                .fontWeight(homeBetter ? .bold : .regular)
                .foregroundStyle(homeBetter ? HardwoodPalette.ink : HardwoodPalette.inkSecondary)
                .frame(width: 64, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.horizontal, HardwoodGeo.padCard)
        .frame(height: 36)
        .overlay(Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline), alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(teamFullName(game?.awayTeam ?? "")) \(format(away)), \(teamFullName(game?.homeTeam ?? "")) \(format(home))")
    }

    // MARK: - Advanced

    /// How the score margin moved through the game: home ahead above the line,
    /// away ahead below it. A step line, because the margin only changes when
    /// someone scores.
    private func marginCard(_ detail: GameDetail, game: Game) -> some View {
        let points = detail.margin
        // Regulation is 48 minutes; each overtime adds five.
        let end = max(2880, points.last?.elapsed ?? 2880)
        let reach = max(6, (points.map { abs($0.homeMargin) }.max() ?? 6).rounded(.up))
        let homeColor = NBATeamColor.color(game.homeTeam)
        let awayColor = NBATeamColor.color(game.awayTeam)
        let periodStarts: [Double] = [0, 720, 1440, 2160]
            + (end > 2880 ? stride(from: 2880.0, to: end, by: 300).map { $0 } : [])
        return card(title: "Margin") {
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Time", point.elapsed),
                            yStart: .value("Even", 0),
                            yEnd: .value("Home lead", max(point.homeMargin, 0)),
                            series: .value("Side", "home")
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(homeColor.opacity(0.28))
                        AreaMark(
                            x: .value("Time", point.elapsed),
                            yStart: .value("Even", 0),
                            yEnd: .value("Away lead", min(point.homeMargin, 0)),
                            series: .value("Side", "away")
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(awayColor.opacity(0.28))
                    }
                    RuleMark(y: .value("Even", 0))
                        .foregroundStyle(HardwoodPalette.inkTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Time", point.elapsed),
                            y: .value("Margin", point.homeMargin)
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(HardwoodPalette.ink)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartYScale(domain: -reach...reach)
                .chartXScale(domain: 0...end)
                .chartXAxis {
                    AxisMarks(values: periodStarts) { value in
                        AxisGridLine().foregroundStyle(HardwoodPalette.divider)
                        AxisValueLabel(anchor: .topLeading) {
                            let seconds = value.as(Double.self) ?? 0
                            Text(Self.periodLabel(startingAt: seconds))
                                .font(HardwoodType.micro)
                                .foregroundStyle(HardwoodPalette.inkTertiary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [-reach, 0, reach]) { value in
                        AxisValueLabel {
                            let margin = value.as(Double.self) ?? 0
                            Text(margin > 0 ? displayTeamAbbr(game.homeTeam) : margin < 0 ? displayTeamAbbr(game.awayTeam) : "Even")
                                .font(HardwoodType.micro)
                                .foregroundStyle(HardwoodPalette.inkTertiary)
                        }
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("Score margin chart, \(teamFullName(game.homeTeam)) against \(teamFullName(game.awayTeam))")

                Text("Score margin, play by play. Up is \(displayTeamAbbr(game.homeTeam)) ahead, down is \(displayTeamAbbr(game.awayTeam)) ahead.\(leadsText(detail, game: game))")
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HardwoodGeo.padCard)
        }
    }

    /// "Q1", "Q2", "Q3", "Q4", then "OT", "2OT"... for the overtime periods.
    nonisolated static func periodLabel(startingAt seconds: Double) -> String {
        guard seconds >= 2880 else { return "Q\(Int(seconds / 720) + 1)" }
        return quarterLabel(Int((seconds - 2880) / 300) + 5)
    }

    /// The period number a play carries (5 is the first overtime).
    nonisolated static func quarterLabel(_ period: Int) -> String {
        switch period {
        case ...4: return "Q\(period)"
        case 5: return "OT"
        default: return "\(period - 4)OT"
        }
    }

    /// " Biggest leads: BOS 12, NYK 7."
    private func leadsText(_ detail: GameDetail, game: Game) -> String {
        let leads = detail.largestLeads
        return " Biggest leads: \(displayTeamAbbr(game.homeTeam)) \(leads.home), \(displayTeamAbbr(game.awayTeam)) \(leads.away)."
    }

    enum RateStyle {
        case decimal
        case percent
        case ratio
        case count

        func format(_ value: Double) -> String {
            switch self {
            case .decimal: return value.formatted(.number.precision(.fractionLength(1)))
            case .percent: return value.formatted(.number.precision(.fractionLength(1))) + "%"
            case .ratio: return value.formatted(.number.precision(.fractionLength(2)))
            case .count: return Int(value.rounded()).formatted()
            }
        }
    }

    private struct FactorMetric {
        let label: String
        let key: String
        let style: RateStyle
    }

    /// The four factors first (eFG%, turnovers, offensive rebounds, free throws),
    /// then the ratings and the points that explain them.
    private static let factorMetrics: [FactorMetric] = [
        .init(label: "Points", key: "pts", style: .count),
        .init(label: "Off. rating", key: "ortg", style: .decimal),
        .init(label: "Def. rating", key: "drtg", style: .decimal),
        .init(label: "Pace", key: "pace", style: .decimal),
        .init(label: "eFG%", key: "efg_pct", style: .percent),
        .init(label: "TOV%", key: "tov_pct", style: .percent),
        .init(label: "OREB%", key: "oreb_pct", style: .percent),
        .init(label: "FT rate", key: "ft_rate", style: .ratio),
        .init(label: "Points in paint", key: "points_in_paint", style: .count),
        .init(label: "Fast-break points", key: "fast_break_points", style: .count),
        .init(label: "Bench points", key: "bench_points", style: .count),
        .init(label: "Biggest lead", key: "largest_lead", style: .count),
    ]

    private func factorsCard(_ detail: GameDetail, game: Game) -> some View {
        let away = detail.stats(for: game.awayTeam)
        let home = detail.stats(for: game.homeTeam)
        return card(title: "Four factors & ratings") {
            HStack {
                teamLabel(game.awayTeam)
                Spacer()
                Text("Bars: percentile vs all team games")
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                Spacer()
                teamLabel(game.homeTeam)
            }
            .padding(.horizontal, HardwoodGeo.padCard)
            .frame(height: 30)
            .background(HardwoodPalette.surfaceAlt)

            ForEach(Array(Self.factorMetrics.enumerated()), id: \.element.key) { index, metric in
                if away[metric.key] != nil || home[metric.key] != nil {
                    factorRow(metric, away: away, home: home, index: index, game: game)
                }
            }
        }
    }

    private func teamLabel(_ team: String) -> some View {
        HStack(spacing: 4) {
            TeamColorDot(abbr: team, size: 8)
            Text(displayTeamAbbr(team))
                .font(HardwoodType.smallBold)
                .foregroundStyle(HardwoodPalette.ink)
        }
    }

    private func factorRow(_ metric: FactorMetric, away: [String: RatedValue], home: [String: RatedValue], index: Int, game: Game) -> some View {
        func text(_ side: [String: RatedValue]) -> String {
            side[metric.key].map { metric.style.format($0.value) } ?? "-"
        }
        return HStack(spacing: 8) {
            ratedCell(text(away), percentile: away[metric.key]?.percentile, alignment: .leading)
            Text(metric.label)
                .font(HardwoodType.small)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
            ratedCell(text(home), percentile: home[metric.key]?.percentile, alignment: .trailing)
        }
        .padding(.horizontal, HardwoodGeo.padCard)
        .frame(height: 40)
        .background(index.isMultiple(of: 2) ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(metric.label): \(teamFullName(game.awayTeam)) \(text(away))\(away[metric.key]?.percentile.map { ", \($0.ordinalString) percentile" } ?? ""), "
                + "\(teamFullName(game.homeTeam)) \(text(home))\(home[metric.key]?.percentile.map { ", \($0.ordinalString) percentile" } ?? "")"
        )
    }

    /// A value over a thin percentile bar, the value tinted by its rank.
    private func ratedCell(_ text: String, percentile: Int?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(text)
                .font(HardwoodType.statMed)
                .foregroundStyle(percentile.map { HardwoodPalette.textColor(forPercentile: $0) } ?? HardwoodPalette.ink)
            if let percentile {
                PercentileBarMini(percentile: percentile, height: 4)
                    .frame(width: 44)
                    .scaleEffect(x: alignment == .trailing ? -1 : 1)
            } else {
                Color.clear.frame(width: 44, height: 4)
            }
        }
        .frame(width: 64, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func bigPlaysCard(_ detail: GameDetail, game: Game) -> some View {
        card(title: "Plays that decided it") {
            ForEach(Array(detail.bigPlays.enumerated()), id: \.element.id) { index, play in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Self.quarterLabel(play.qtr)) \(play.clock)")
                            .lineLimit(1)
                            .font(HardwoodType.micro)
                            .foregroundStyle(HardwoodPalette.inkTertiary)
                        HStack(spacing: 4) {
                            TeamColorDot(abbr: play.team, size: 6)
                            Text(displayTeamAbbr(play.team))
                                .font(HardwoodType.micro)
                                .foregroundStyle(HardwoodPalette.inkSecondary)
                        }
                    }
                    .frame(width: 66, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        if let kind = play.kind {
                            Text(kind == .leadChange ? "LEAD CHANGE" : "LATE SCORE")
                                .font(HardwoodType.micro)
                                .foregroundStyle(HardwoodPalette.inkTertiary)
                        }
                        Text(play.description)
                            .font(HardwoodType.small)
                            .foregroundStyle(HardwoodPalette.ink)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(marginText(play.homeMargin, game: game))
                        .font(HardwoodType.statSmall)
                        .foregroundStyle(HardwoodPalette.ink)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 54, alignment: .trailing)
                }
                .padding(.horizontal, HardwoodGeo.padInline)
                .padding(.vertical, 10)
                .background(index.isMultiple(of: 2) ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                .accessibilityElement(children: .combine)
            }
            footnoteRow("The right-hand figure is the score margin after the play. Late scores are baskets in the last five minutes of the fourth quarter or overtime with the game inside five points.")
        }
    }

    /// "BOS +4", "Tied": the margin after a play, named for the side ahead.
    private func marginText(_ homeMargin: Int, game: Game) -> String {
        guard homeMargin != 0 else { return "Tied" }
        let ahead = homeMargin > 0 ? game.homeTeam : game.awayTeam
        return "\(displayTeamAbbr(ahead)) +\(abs(homeMargin))"
    }

    @ViewBuilder
    private func playerLinesCards(_ detail: GameDetail, game: Game) -> some View {
        if store.isPro {
            let team = boxTeam.isEmpty ? game.awayTeam : boxTeam
            let lines = detail.players(for: team)
            if !lines.isEmpty {
                VStack(spacing: 0) {
                    teamPicker(game, team: team)
                    card(title: "Player ratings") {
                        tableHeader(["MIN", "PTS", "REB", "AST", "TS%", "USG%", "+/-"], width: 40)
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            ratingRow(line, index: index, game: game)
                        }
                        footnoteRow("Bars rank each night against every player game of ten minutes or more this season.")
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                Text("Every player's night, ranked")
                    .font(HardwoodType.cardTitle)
                    .foregroundStyle(HardwoodPalette.ink)
                Text("Points, rebounds, assists, TS%, usage and plus/minus for every player, each ranked against the season.")
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PlusDirectCTA(trigger: .advancedBoxScore, style: .capsule)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(HardwoodPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                    .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }

    private func ratingRow(_ line: GameDetail.PlayerLine, index: Int, game: Game) -> some View {
        let player = viewModel.player(id: line.playerId, season: game.season, phase: game.seasonPhase)
        func rated(_ value: RatedValue?, _ style: RateStyle, signed: Bool = false) -> (String, Int?) {
            guard let value else { return ("-", nil) }
            var text = style.format(value.value)
            if signed, value.value > 0 { text = "+" + text }
            return (text, value.percentile)
        }
        let cells: [(String, Int?)] = [
            (line.minutes.map(String.init) ?? "-", nil),
            rated(line.points, .count),
            rated(line.rebounds, .count),
            rated(line.assists, .count),
            rated(line.trueShooting, .decimal),
            rated(line.usage, .decimal),
            rated(line.plusMinus, .count, signed: true),
        ]
        let row = HStack(spacing: 0) {
            HStack(spacing: 6) {
                TeamColorDot(abbr: line.team, size: 7)
                Text(Self.shortName(player?.name ?? line.name ?? "Player"))
                    .font(HardwoodType.smallBold)
                    .foregroundStyle(HardwoodPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell.0)
                    .font(HardwoodType.statSmall)
                    .fontWeight(cell.1 == nil ? .regular : .semibold)
                    .foregroundStyle(cell.1.map { HardwoodPalette.textColor(forPercentile: $0) } ?? HardwoodPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .frame(minHeight: 40)
        .background(index.isMultiple(of: 2) ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
        .contentShape(Rectangle())
        return Group {
            if let player {
                NavigationLink(value: player) { row }
                    .buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    /// "S. Gilgeous-Alexander" from "Shai Gilgeous-Alexander": a box score row
    /// has no room for a full first name.
    nonisolated static func shortName(_ name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        guard parts.count > 1, let first = parts.first?.first else { return name }
        return "\(first). " + parts.dropFirst().joined(separator: " ")
    }

    private func teamPicker(_ game: Game, team: String) -> some View {
        HardwoodSegmented(
            segments: [
                .init(value: game.awayTeam, label: teamFullName(game.awayTeam)),
                .init(value: game.homeTeam, label: teamFullName(game.homeTeam)),
            ],
            selection: Binding(get: { team }, set: { boxTeam = $0 })
        )
        .padding(.horizontal, 12)
        .padding(.top, 16)
    }

    private func boxScoreCard(_ game: Game) -> some View {
        let team = boxTeam.isEmpty ? game.awayTeam : boxTeam
        return VStack(spacing: 0) {
            // The advanced player ratings carry their own picker for Pro; the
            // traditional box score always needs one.
            if !store.isPro || detail == nil {
                teamPicker(game, team: team)
            }

            card(title: "\(teamFullName(team)) box score") {
                fullBoxScore(boxScore.rotation(for: team))
                footnoteRow(
                    "Starters first, then the bench by minutes. Swipe the table for steals, blocks, turnovers and fouls."
                        + (boxScore.rotation(for: team).contains { $0.metrics["plus_minus"] != nil } ? "" : " Plus/minus starts in 2008-09.")
                )
            }
        }
    }

    /// Every box-score column, the way a box score reads: names pinned on the
    /// left, the counts scrolling sideways beside them.
    private func fullBoxScore(_ lines: [GameBoxScore.PlayerLine]) -> some View {
        let columns: [(title: String, width: CGFloat, value: (GameBoxScore.PlayerLine) -> String)] = [
            ("MIN", 34, { "\($0.minutes)" }),
            ("PTS", 34, { "\($0.int("pts"))" }),
            ("REB", 34, { "\($0.int("reb"))" }),
            ("AST", 34, { "\($0.int("ast"))" }),
            ("FG", 50, { $0.made("fgm", of: "fga") }),
            ("3P", 44, { $0.made("fg3m", of: "fg3a") }),
            ("FT", 44, { $0.made("ftm", of: "fta") }),
            ("STL", 34, { "\($0.int("stl"))" }),
            ("BLK", 34, { "\($0.int("blk"))" }),
            ("TO", 30, { "\($0.int("tov"))" }),
            ("PF", 30, { "\($0.int("pf"))" }),
            ("+/-", 40, { $0.plusMinusText }),
        ]
        let rowHeight: CGFloat = 40
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Text("PLAYER")
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 26)
                    .padding(.leading, HardwoodGeo.padInline)
                    .background(HardwoodPalette.surfaceAlt)
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    playerRow(line: line, index: index, height: rowHeight) {
                        nameText(line)
                    }
                }
            }
            .frame(width: 108)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(columns, id: \.title) { column in
                            Text(column.title).frame(width: column.width, alignment: .trailing)
                        }
                    }
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .padding(.trailing, HardwoodGeo.padInline)
                    .frame(height: 26)
                    .background(HardwoodPalette.surfaceAlt)
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        HStack(spacing: 0) {
                            ForEach(columns, id: \.title) { column in
                                Text(column.value(line))
                                    .frame(width: column.width, alignment: .trailing)
                            }
                        }
                        .font(HardwoodType.statSmall)
                        .foregroundStyle(HardwoodPalette.ink)
                        .lineLimit(1)
                        .padding(.trailing, HardwoodGeo.padInline)
                        .frame(height: rowHeight)
                        .background(index.isMultiple(of: 2) ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                    }
                }
            }
        }
        .monospacedDigit()
    }

    /// The preview a fan opens before tip-off: who is favoured, how the two
    /// teams compare, and the season series so far.
    @ViewBuilder
    private func upcomingCard(_ game: Game) -> some View {
        let rows = matchupRows(game)
        if viewModel.projection(for: game) == nil && rows.isEmpty {
            notice(
                icon: "calendar",
                title: "Not started yet",
                text: "The score updates live from tip-off, and the box score posts after the final. Scout both rosters from the team pages above."
            )
        } else {
            card(title: "Matchup") {
                if let projection = viewModel.projection(for: game) {
                    winChance(projection, game: game)
                }
                if !rows.isEmpty {
                    HStack(spacing: 0) {
                        Text(displayTeamAbbr(game.awayTeam)).frame(width: 96, alignment: .leading)
                        Spacer(minLength: 0)
                        Text(displayTeamAbbr(game.homeTeam)).frame(width: 96, alignment: .trailing)
                    }
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .padding(.horizontal, HardwoodGeo.padInline)
                    .frame(height: 26)
                    .background(HardwoodPalette.surfaceAlt)
                    ForEach(Array(rows.enumerated()), id: \.element.label) { index, row in
                        matchupRow(row)
                            .background(index.isMultiple(of: 2) ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                    }
                }
                if let series = seasonSeries(game) {
                    Text(series)
                        .font(HardwoodType.smallBold)
                        .foregroundStyle(HardwoodPalette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, HardwoodGeo.padCard)
                        .padding(.top, 10)
                }
                footnoteRow(matchupFootnote(game))
            }
        }
    }

    private struct MatchupRow {
        let label: String
        let away: String
        let home: String
        /// Which side the row favours: -1 away, 1 home, 0 neither.
        let edge: Int
    }

    private func matchupRows(_ game: Game) -> [MatchupRow] {
        var rows: [MatchupRow] = []
        func edge(_ away: Double, _ home: Double, higherIsBetter: Bool = true) -> Int {
            guard away != home else { return 0 }
            return (home > away) == higherIsBetter ? 1 : -1
        }
        // Records and scoring belong to the season being played; a game from a
        // season that hasn't started has neither.
        if game.season == viewModel.freeSeason,
           let away = viewModel.standings[normalizedTeamAbbreviation(game.awayTeam)],
           let home = viewModel.standings[normalizedTeamAbbreviation(game.homeTeam)],
           away.games > 0, home.games > 0 {
            rows.append(MatchupRow(label: "Record", away: away.record, home: home.record,
                                   edge: edge(away.winPercentage, home.winPercentage)))
            func perGame(_ total: Int, _ games: Int) -> Double { Double(total) / Double(games) }
            let tenths: (Double) -> String = { String(format: "%.1f", $0) }
            let ap = perGame(away.pointsFor, away.games), hp = perGame(home.pointsFor, home.games)
            rows.append(MatchupRow(label: "PTS/G", away: tenths(ap), home: tenths(hp), edge: edge(ap, hp)))
            let aa = perGame(away.pointsAgainst, away.games), ha = perGame(home.pointsAgainst, home.games)
            rows.append(MatchupRow(label: "OPP PTS/G", away: tenths(aa), home: tenths(ha), edge: edge(aa, ha, higherIsBetter: false)))
            if let a = away.streak, let h = home.streak {
                rows.append(MatchupRow(label: "Streak", away: a, home: h, edge: 0))
            }
        }
        let ratings = Array(viewModel.teamRatings.values)
        if let away = viewModel.teamRating(game.awayTeam), let home = viewModel.teamRating(game.homeTeam) {
            func rank(_ value: Double, _ key: (TeamRating) -> Double) -> String {
                (ratings.filter { key($0) > value }.count + 1).ordinalString
            }
            func pair(_ label: String, _ key: @escaping (TeamRating) -> Double) {
                rows.append(MatchupRow(
                    label: label,
                    away: "\(TeamRating.signed(key(away))) · \(rank(key(away), key))",
                    home: "\(TeamRating.signed(key(home))) · \(rank(key(home), key))",
                    edge: edge(key(away), key(home))
                ))
            }
            pair("Power", \.rating)
            pair("Offense", \.offense)
            pair("Defense", \.defense)
        }
        return rows
    }

    private func matchupRow(_ row: MatchupRow) -> some View {
        HStack(spacing: 0) {
            Text(row.away)
                .font(row.edge < 0 ? HardwoodType.smallBold : HardwoodType.small)
                .foregroundStyle(row.edge < 0 ? HardwoodPalette.ink : HardwoodPalette.inkSecondary)
                .frame(width: 96, alignment: .leading)
            Text(row.label)
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkTertiary)
                .frame(maxWidth: .infinity)
            Text(row.home)
                .font(row.edge > 0 ? HardwoodType.smallBold : HardwoodType.small)
                .foregroundStyle(row.edge > 0 ? HardwoodPalette.ink : HardwoodPalette.inkSecondary)
                .frame(width: 96, alignment: .trailing)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, HardwoodGeo.padInline)
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label): away \(row.away), home \(row.home)")
    }

    private func winChance(_ projection: GameProjection, game: Game) -> some View {
        let home = projection.homeWinProbability
        return VStack(spacing: 8) {
            HStack {
                Text("\(displayTeamAbbr(game.awayTeam)) \(Int(((1 - home) * 100).rounded()))%")
                Spacer()
                Text("WIN CHANCE")
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                Spacer()
                Text("\(Int((home * 100).rounded()))% \(displayTeamAbbr(game.homeTeam))")
            }
            .font(HardwoodType.bodyBold)
            .foregroundStyle(HardwoodPalette.ink)
            .monospacedDigit()
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    NBATeamColor.color(game.awayTeam)
                        .frame(width: max(0, (proxy.size.width - 2) * (1 - home)))
                    // Two blues (PHI at NYK) read as one bar; the home side
                    // goes neutral when the colours are too close to tell apart.
                    Self.isClose(NBATeamColor.color(game.awayTeam), NBATeamColor.color(game.homeTeam))
                        ? HardwoodPalette.inkTertiary
                        : NBATeamColor.color(game.homeTeam)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            Text("Projected: " + projection.label(home: game.homeTeam, away: game.awayTeam))
                .font(HardwoodType.micro)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .frame(maxWidth: .infinity)
        }
        .padding(HardwoodGeo.padCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Win chance: \(teamFullName(game.awayTeam)) \(Int(((1 - home) * 100).rounded())) percent, \(teamFullName(game.homeTeam)) \(Int((home * 100).rounded())) percent. Projected \(projection.label(home: game.homeTeam, away: game.awayTeam))")
    }

    private static func isClose(_ a: Color, _ b: Color) -> Bool {
        var (r1, g1, b1, r2, g2, b2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0, 0, 0)
        UIColor(a).getRed(&r1, green: &g1, blue: &b1, alpha: nil)
        UIColor(b).getRed(&r2, green: &g2, blue: &b2, alpha: nil)
        let distance = sqrt(pow(r1 - r2, 2) + pow(g1 - g2, 2) + pow(b1 - b2, 2))
        return distance < 0.3
    }

    /// "Season series: NYK leads 2-1", from this season's finals between them.
    private func seasonSeries(_ game: Game) -> String? {
        guard game.seasonPhase == .regular else { return nil }
        let meetings = viewModel.schedule(forTeam: game.awayTeam).filter {
            $0.isFinal && $0.season == game.season && $0.countsInStandings && $0.involves(game.homeTeam)
        }
        guard !meetings.isEmpty else { return nil }
        let awayWins = meetings.filter { $0.result(for: game.awayTeam) == "W" }.count
        let homeWins = meetings.count - awayWins
        if awayWins == homeWins { return "Season series tied \(awayWins)-\(homeWins)" }
        let leader = awayWins > homeWins ? game.awayTeam : game.homeTeam
        return "Season series: \(displayTeamAbbr(leader)) leads \(max(awayWins, homeWins))-\(min(awayWins, homeWins))"
    }

    private func matchupFootnote(_ game: Game) -> String {
        // Ratings can trail the schedule (the pending month, the first days
        // after the rollover); say which season they describe when it isn't
        // this game's.
        let rated = viewModel.teamRating(game.homeTeam)?.season ?? game.season
        let ratingSeason = rated == game.season ? "" : " Ratings are from \(SeasonLabel.text(rated)) until this season has games."
        return "Win chance and margin come from StatScout Power Ratings: points per 100 possessions against an average team, adjusted for schedule, plus home court. Ranks are among all 30 teams." + ratingSeason
            + " The score updates live from tip-off."
    }

    // MARK: - Pieces

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: title)
            content()
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

    private func tableHeader(_ columns: [String], width: CGFloat = 46) -> some View {
        HStack(spacing: 0) {
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                Text(column)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: width, alignment: .trailing)
            }
        }
        .font(HardwoodType.micro)
        .foregroundStyle(HardwoodPalette.inkTertiary)
        .padding(.horizontal, HardwoodGeo.padInline)
        .frame(height: 26)
        .background(HardwoodPalette.surfaceAlt)
    }

    /// A tappable row when the player is in the live dataset, a plain one if not.
    @ViewBuilder
    private func playerRow<Content: View>(line: GameBoxScore.PlayerLine, index: Int, height: CGFloat? = nil, @ViewBuilder content: () -> Content) -> some View {
        let row = content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HardwoodGeo.padInline)
            .padding(.vertical, height == nil ? 8 : 0)
            .frame(minHeight: height ?? 40)
            .frame(height: height)
            .background(index.isMultiple(of: 2) ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
            .contentShape(Rectangle())
        if let player = player(for: line) {
            NavigationLink(value: player) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func nameText(_ line: GameBoxScore.PlayerLine) -> some View {
        Text(player(for: line).map { Self.shortName($0.name) } ?? "Player \(line.playerId)")
            .font(HardwoodType.smallBold)
            .foregroundStyle(HardwoodPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private func player(for line: GameBoxScore.PlayerLine) -> Player? {
        guard let game else { return nil }
        return viewModel.player(id: line.playerId, season: game.season, phase: game.seasonPhase)
    }

    private func notice(
        icon: String,
        title: String,
        text: String,
        action: (label: String, perform: () -> Void)? = nil
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(HardwoodPalette.inkTertiary)
            Text(title)
                .font(HardwoodType.cardTitle)
                .foregroundStyle(HardwoodPalette.ink)
            Text(text)
                .font(HardwoodType.small)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.label, action: action.perform)
                    .font(HardwoodType.smallBold)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(HardwoodType.micro)
            .foregroundStyle(HardwoodPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }

    private func footnoteRow(_ text: String) -> some View {
        Text(text)
            .font(HardwoodType.micro)
            .foregroundStyle(HardwoodPalette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HardwoodGeo.padCard)
            .padding(.vertical, 10)
    }
}
