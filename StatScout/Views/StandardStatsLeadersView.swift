import SwiftUI

/// Traditional leaderboard with the same position tabs and control vocabulary
/// as the Advanced board.
struct StandardStatsLeadersView: View {
    let players: [Player]
    @Binding var selectedStat: String
    @Binding var selectedPosition: PlayerPositionGroup
    @Binding var sortDescending: Bool
    var season: Int? = nil
    var boardBindings: StatsBoardBindings? = nil
    var viewModel: DashboardViewModel? = nil
    @State private var isSearching = false
    @State private var searchText = ""

    private var availableStats: [String] {
        StandardStatCatalog.stats(for: selectedPosition)
    }

    private var filteredPlayers: [Player] {
        players.filter { player in
            selectedPosition.includes(player)
                && numericStat(for: player) != nil
        }
    }

    /// Each player's sort keys are read once, not on every comparison: reading
    /// one means a case-insensitive search of the stat line and parsing it.
    private var sortedPlayers: [Player] {
        filteredPlayers
            .map { (player: $0, value: numericStat(for: $0) ?? 0, games: games(for: $0)) }
            .sorted { first, second in
                if first.value != second.value {
                    return sortDescending
                        ? first.value > second.value
                        : first.value < second.value
                }
                return first.games > second.games
            }
            .map(\.player)
    }

    var body: some View { let _ = TabProbe.hit("StandardStatsLeadersView") // TABPROBE
        VStack(spacing: 0) {
            positionSelector
            controlRow
            if isSearching {
                HStack(spacing: 8) {
                    SearchField(text: $searchText, focusOnAppear: true)
                    Button("Cancel") {
                        isSearching = false
                        searchText = ""
                    }
                    .font(HardwoodType.small)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            ScrollView {
                VStack(spacing: 0) {
                leadersList
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                if let note = rankingNote {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10, weight: .semibold))
                        Text(note)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }
                Color.clear.frame(height: 88)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await viewModel?.load() }
        }
        .background(HardwoodPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPosition) { _, next in
            guard !StandardStatCatalog.stats(for: next).contains(selectedStat) else {
                return
            }
            selectedStat = StandardStatCatalog.defaultStat(for: next)
            sortDescending = StandardStatCatalog.defaultDescending(
                for: selectedStat,
                position: next
            )
        }
    }

    private var positionSelector: some View {
        HardwoodTabs(
            tabs: PlayerPositionGroup.allCases.map(\.rawValue),
            selected: Binding(
                get: { selectedPosition.rawValue },
                set: { rawValue in
                    guard let position = PlayerPositionGroup.allCases.first(where: {
                        $0.rawValue == rawValue
                    }) else { return }
                    selectedPosition = position
                }
            )
        )
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Position")
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let boardBindings, let viewModel {
                        StatsBoardStatPicker(
                            viewModel: viewModel,
                            bindings: boardBindings
                        )
                    } else {
                        statMenu
                    }

                    SortDirectionButton(
                        descending: sortDescending,
                        statLabel: selectedStat
                    ) {
                        sortDescending.toggle()
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 2)
                .padding(.vertical, 1)
            }
            .scrollBounceBehavior(.basedOnSize)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            Button {
                isSearching.toggle()
                if !isSearching { searchText = "" }
            } label: {
                HardwoodChip(systemImage: "magnifyingglass", isActive: isSearching)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search players or teams")

            if let boardBindings, let viewModel {
                StatsViewMenu(
                    viewModel: viewModel,
                    board: boardBindings.$board
                )
                .fixedSize()
            }
        }
        .padding(.trailing, 12)
        .frame(height: HardwoodControl.height + 2)
        .padding(.top, HardwoodGeo.controlRowGap)
    }

    private var statMenu: some View {
        StatPickerMenu(
            standard: availableStats.map {
                .init(id: $0, label: $0, isSelected: $0 == selectedStat)
            },
            activeLabel: selectedStat,
            onSelectStandard: { option in
                selectedStat = option.id
                sortDescending = StandardStatCatalog.defaultDescending(
                    for: option.id,
                    position: selectedPosition
                )
            }
        )
    }

    private var leadersList: some View {
        LazyVStack(spacing: 0) {
            Button {
                sortDescending.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 0) {
                    Text("RANK")
                        .font(HardwoodType.micro)
                        .foregroundStyle(HardwoodPalette.inkTertiary)
                        .frame(width: 42, alignment: .leading)
                    // Says who is on the list where the list is read. The rule
                    // otherwise lives only in the View menu, and "leaders" with
                    // no minimum on opening night reads like a ranking of the best.
                    Text(sampleLabel)
                        .font(HardwoodType.micro)
                        .foregroundStyle(HardwoodPalette.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("TEAM")
                        .font(HardwoodType.micro)
                        .foregroundStyle(HardwoodPalette.inkTertiary)
                        .frame(width: 44, alignment: .leading)
                    HStack(spacing: 4) {
                        Text(selectedStat.uppercased())
                            .font(HardwoodType.micro)
                            .foregroundStyle(HardwoodPalette.court)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(HardwoodPalette.court)
                    }
                    .frame(width: 100, alignment: .trailing)
                }
                .frame(height: HardwoodGeo.rowHeightHeader)
                .padding(.horizontal, HardwoodGeo.padInline)
                .background(HardwoodPalette.surfaceAlt)
                .overlay(
                    Rectangle()
                        .fill(HardwoodPalette.divider)
                        .frame(height: HardwoodGeo.hairline),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)

            if viewModel?.isLoading == true && players.isEmpty {
                ProgressView("Loading player stats")
                    .padding(.vertical, 48)
            } else if filteredPlayers.isEmpty {
                ContentUnavailableView {
                    Label("No data available", systemImage: "chart.bar")
                } description: {
                    Text("No \(selectedPosition == .all ? "" : selectedPosition.noun + " ")players have \(selectedStat) data for this season.")
                }
                .padding(.vertical, 48)
                .background(HardwoodPalette.surface)
            } else {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let ranked = Array(sortedPlayers.enumerated()).filter { _, player in
                    query.isEmpty || player.name.localizedCaseInsensitiveContains(query)
                        || player.team.localizedCaseInsensitiveContains(query)
                        || teamFullName(player.team).localizedCaseInsensitiveContains(query)
                }
                let peerValues = filteredPlayers.compactMap { standardStat(for: $0)?.value }
                if ranked.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.vertical, 24)
                }
                ForEach(ranked, id: \.element.id) { index, player in
                    playerRow(rank: index + 1, player: player, peerValues: peerValues)
                        .onAppear {
                            if index == 0 { StartupTrace.mark("first leaderboard row appeared") }
                        }
                }
            }
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    private func playerRow(rank: Int, player: Player, peerValues: [String]) -> some View {
        NavigationLink(value: player) {
            HStack(spacing: 0) {
                Text("\(rank)")
                    .font(HardwoodType.statSmall)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
                    .frame(width: 36, alignment: .leading)

                HStack(spacing: 10) {
                    PlayerHeadshot(
                        team: player.team,
                        initials: player.initials,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name)
                            .font(HardwoodType.bodyBold)
                            .foregroundStyle(HardwoodPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .truncationMode(.tail)
                        Text([player.displayPosition, volumeText(for: player)].compactMap { $0 }.joined(separator: " · "))
                            .font(HardwoodType.micro)
                            .foregroundStyle(HardwoodPalette.inkTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    TeamColorDot(abbr: player.team, size: 6)
                    Text(displayTeamAbbr(player.team))
                        .font(HardwoodType.small)
                        .foregroundStyle(HardwoodPalette.inkSecondary)
                }
                .frame(width: 44, alignment: .leading)

                let pct = percentile(for: player, peerValues: peerValues)
                // A zero count has no honest rank; see `Metric.isUnranked`.
                // Not for a lower-is-better count: a bench player's 0 PF is the
                // best line on the board, not an absence.
                let isZero = numericStat(for: player) == 0
                    && StandardStatSemantics.higherIsBetter(label: selectedStat)
                HStack(spacing: 8) {
                    if isZero {
                        Color.clear.frame(width: 34, height: 7)
                    } else {
                        PercentileBarMini(percentile: pct)
                            .frame(width: 34)
                    }
                    Text(statDisplay(for: player))
                        .font(HardwoodType.statMed)
                        .foregroundStyle(isZero ? HardwoodPalette.inkTertiary : HardwoodPalette.court)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 58, alignment: .trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    isZero
                        ? "\(selectedStat): \(statDisplay(for: player)), not ranked"
                        : "\(selectedStat): \(statDisplay(for: player)), \(pct.ordinalString) percentile"
                )
            }
            .frame(height: HardwoodGeo.rowHeight)
            .padding(.horizontal, HardwoodGeo.padInline)
            .background(
                rank.isMultiple(of: 2)
                    ? HardwoodPalette.surfaceAlt
                    : HardwoodPalette.surface
            )
            .overlay(
                Rectangle()
                    .fill(HardwoodPalette.divider)
                    .frame(height: HardwoodGeo.hairline),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }

    /// Case-insensitive on purpose.
    ///
    /// Callers reach this board from several places and one of them displays its
    /// stat names in caps. An exact match meant a casing difference emptied the
    /// whole board and reported it as "no data for this season", which reads as
    /// a fact about the league rather than a mismatch between two strings. The
    /// route now passes the data's own spelling, and this makes a future one
    /// harmless instead of silent.
    private func standardStat(for player: Player) -> StandardStat? {
        player.standardStats?.first {
            $0.label.compare(selectedStat, options: .caseInsensitive) == .orderedSame
        }
    }

    private var sampleLabel: String {
        guard let viewModel else { return "PLAYER" }
        return viewModel.qualifierLevel == .qualified ? "QUALIFIED PLAYERS" : "ALL PLAYERS"
    }

    /// What the ranking means where it is easy to misread: shooting lines rank
    /// by percentage, not by the made count in front of the slash.
    private var rankingNote: String? {
        ["FG", "3P", "FT"].contains(selectedStat.uppercased())
            ? "Ranked by shooting percentage, not by makes."
            : nil
    }

    /// The volume behind the headline number: games, or minutes when the stat is
    /// the game count itself. A 40% three-point mark means little over three
    /// games.
    private func volumeText(for player: Player) -> String? {
        let stats = player.standardStats ?? []
        func value(_ label: String) -> String? {
            stats.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }?.value
        }
        if selectedStat.uppercased() == "G" {
            return value("MIN").map { "\($0) min" }
        }
        guard let games = value("G") else { return nil }
        return games == "1" ? "1 game" : "\(games) games"
    }

    private func numericStat(for player: Player) -> Double? {
        guard let stat = standardStat(for: player) else { return nil }
        // Via the shared semantics so a paired value (FG, 3P, FT) sorts on its
        // percentage rather than on the count in front of the slash.
        return StandardStatSemantics.numericValue(label: stat.label, value: stat.value)
    }

    /// Every row on this board has the stat it is ranked by - that is the
    /// filter - so every row can carry a percentile, drawn against the same
    /// position cohort the profile's traditional bars use.
    ///
    /// The cohort is passed in rather than recomputed per row: `filteredPlayers`
    /// walks the whole season pool, and a fifty-row board asking for it twice a
    /// row walked it a hundred times per redraw.
    private func percentile(for player: Player, peerValues: [String]) -> Int {
        guard let stat = standardStat(for: player) else { return 50 }
        return StandardStatSemantics.percentile(
            label: stat.label,
            value: stat.value,
            peerValues: peerValues
        )
    }

    private func statDisplay(for player: Player) -> String {
        standardStat(for: player)?.value ?? "-"
    }

    private func games(for player: Player) -> Double {
        guard let value = player.standardStats?.first(where: {
            $0.label == "G"
        })?.value else { return 0 }
        return DashboardViewModel.rawNumeric(value) ?? 0
    }
}

/// Standalone traditional-stat drill-down reached from a player or team page.
struct StandardStatsLeaderboardScreen: View {
    let players: [Player]
    var season: Int? = nil
    @State private var stat: String
    @State private var position: PlayerPositionGroup
    @State private var sortDescending: Bool

    init(
        players: [Player],
        initialStat: String = "PPG",
        initialPosition: PlayerPositionGroup = .all,
        season: Int? = nil
    ) {
        self.players = players
        self.season = season
        _stat = State(initialValue: initialStat)
        _position = State(initialValue: initialPosition)
        _sortDescending = State(
            initialValue: StandardStatCatalog.defaultDescending(
                for: initialStat,
                position: initialPosition
            )
        )
    }

    var body: some View {
        StandardStatsLeadersView(
            players: players,
            selectedStat: $stat,
            selectedPosition: $position,
            sortDescending: $sortDescending,
            season: season
        )
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        StandardStatsLeaderboardScreen(players: SampleData.players)
            .environmentObject(StoreService.shared)
            .navigationTitle("Standard Stats")
    }
}
#endif
