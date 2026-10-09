import SwiftUI

/// League-wide recent form, ranked by change rather than by level.
///
/// The same THEN / NOW / delta framing the baseball app's rolling leaderboard
/// uses, because the delta is the story. A 38% three-point mark is interesting;
/// a 38% that was 31% over the two weeks before is a shooter you want to know
/// about right now, and that is the thing season totals cannot tell you.
///
/// Colour is the app's own performance gradient. The flame / snowflake accent
/// is reserved for the direction control rather than applied to every row:
/// marking everything marks nothing. (Those are SF Symbols, not emoji, which
/// render as missing-glyph boxes here.)
///
/// Purely league-wide. The players you follow live on the Compare tab, which is
/// where they can actually be used; a personal list wedged above this board
/// made the tab answer two questions at once and buried the leaderboard the
/// subscription is sold on. Followed players are still marked with a star here,
/// and any row can be followed from its context menu.
struct HotColdView: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    let isActive: Bool
    @State private var favorites = FavoritesStore.shared
    @State private var showingCold = false
    @State private var side: TrendSide = .guard
    @State private var metric: TrendMetric = TrendMetric.guardAdvanced[0]
    @State private var selectedSeason: Int
    @State private var selectedPhase: SeasonPhase
    @State private var paywallTrigger: PaywallTrigger?

    init(viewModel: DashboardViewModel, isActive: Bool = true) {
        self.viewModel = viewModel
        self.isActive = isActive
        // Trends is a recent-seasons board, not a season browser:
        // `player_recent_form` is only kept for the newest two seasons, so this
        // opens on the live one whatever the Stats tab is pointed at rather than
        // inheriting a 2017 selection that would render an empty board.
        _selectedSeason = State(initialValue: viewModel.recentFormSeason)
        _selectedPhase = State(initialValue: viewModel.selectedPhase)
    }

    private var metricOptions: [TrendMetric] {
        TrendMetric.advanced(for: side) + TrendMetric.standard(for: side)
    }

    private var forms: [RecentForm] {
        viewModel.recentFormRows(
            window: viewModel.recentWindow,
            playerType: side.playerType,
            season: selectedSeason,
            phase: selectedPhase
        )
    }

    private static let zeroIsReal: Set<String> = [
        "fg_pct", "ft_pct", "ts_pct", "efg_pct", "rim_fg", "three_pct", "three_pm",
    ]

    /// How much better this player got. Falling numbers are the improvement for
    /// a turnover rate or a foul rate, so the board ranks on this rather
    /// than on the raw delta.
    private func improvement(_ form: RecentForm) -> Double? {
        guard let delta = form.delta[metric.key] else { return nil }
        // A prior window of exactly zero means the player barely played in it
        // (a rate with no possessions behind it reads 0.0), so the "rise" is
        // the whole value and tops every board. Shooting percentages are the
        // exception: an honest 0-for-5 is a real zero.
        if form.priorMetrics[metric.key] == 0, !Self.zeroIsReal.contains(metric.key) { return nil }
        return metric.lowerIsBetter ? -delta : delta
    }

    /// True when nobody on this board has a prior window for the metric yet.
    ///
    /// Movement compares a window with the same span before it, so a two-week
    /// window has nothing to compare until the fifth week of the season, four
    /// weeks until the ninth. Until then the board ranks the current window by
    /// level instead of showing an empty "no movement" screen in the weeks new
    /// fans arrive.
    private var isEarlySeason: Bool {
        !forms.isEmpty && !forms.contains { $0.priorMetrics[metric.key] != nil }
    }

    /// Early-season board: the current window ranked by the metric itself.
    /// A volume floor still applies, so one hot night can't top TS%.
    private var earlyRanked: [RecentForm] {
        forms
            .filter { $0.metrics[metric.key] != nil && !$0.isSmallSample(minimumGames: 1) }
            .sorted {
                let a = $0.metrics[metric.key] ?? 0
                let b = $1.metrics[metric.key] ?? 0
                return metric.lowerIsBetter ? a < b : a > b
            }
    }

    private var earlyTitle: String {
        "\(side.label.uppercased()) · \(viewModel.recentWindow.label.uppercased()) LEADERS"
    }

    /// Ranked by improvement, hot first or cold first. Small samples are
    /// excluded outright: two garbage-time games produce enormous deltas that
    /// would crowd out every real riser.
    private var ranked: [RecentForm] {
        forms
            .filter { !$0.isSmallSample && improvement($0) != nil }
            .sorted {
                let a = improvement($0) ?? 0
                let b = improvement($1) ?? 0
                return showingCold ? a < b : a > b
            }
    }

    /// Free users get the header and a full-height locked board; Pro users get
    /// a scrolling one.
    ///
    /// The locked board deliberately does *not* scroll. It used to sit in the
    /// same `ScrollView` as the Pro board, which meant its height was whatever
    /// twelve invented rows happened to add up to, short of the viewport on a
    /// big phone, so the card stopped mid-screen with canvas under it and the
    /// unlock panel floating in the middle of nothing. There is also nothing
    /// below the fold to scroll *to* when the rows are a teaser.
    var body: some View { let _ = TabProbe.hit("HotColdView") // TABPROBE
        Group {
            if store.isPro {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        DataFreshnessView(
                            viewModel: viewModel,
                            season: selectedSeason,
                            phase: selectedPhase
                        )
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                        proContent
                        Color.clear.frame(height: 88)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .refreshable {
                    await viewModel.load()
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    header
                        .background(HardwoodPalette.canvas)
                }
            } else {
                VStack(spacing: 0) {
                    DataFreshnessView(
                        viewModel: viewModel,
                        season: selectedSeason,
                        phase: selectedPhase
                    )
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    header
                    lockedContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HardwoodPalette.canvas)
        .modifier(
            SeasonPhaseNavBar(
                title: "Trends",
                // Two seasons at most, not the full menu. Everything older has no
                // recent-form rows to rank, so listing 2002-03 through 2023-24
                // here offered twenty-two ways to reach an empty board.
                seasons: viewModel.recentFormSeasons,
                selectedSeason: selectedSeason,
                selectedPhase: selectedPhase,
                isSeasonLocked: viewModel.isSeasonLocked,
                onSelectSeason: selectSeason,
                onSelectPhase: { selectedPhase = $0 }
            )
        )
        // Keyed on entitlement as well as the window. `isPro` starts false and
        // only flips once RevenueCat answers, which on a real device is often
        // after this view is already on screen; with the window alone as the
        // id, that first task had already returned at the guard and nothing
        // ever re-ran it. The board then sat empty forever: not loading, no
        // error, just a bare header.
        //
        // Free users load it too: the top row of the locked board is the real
        // league leader, and a fabricated one would be a lie in the one place
        // we're asking to be trusted. It's a single request against the
        // pre-aggregated rollup table, the same one Pro reads.
        .task(
            id: "\(isActive)-\(viewModel.recentWindow.rawValue)-\(selectedSeason)-\(selectedPhase.rawValue)-\(viewModel.freshnessRevision ?? "none")"
        ) {
            guard isActive else { return }
            await viewModel.loadRecentFormIfNeeded(
                season: selectedSeason,
                phase: selectedPhase
            )
        }
        .onChange(of: side) { _, _ in
            metric = metricOptions[0]
        }
        // The live season resolves from the data, so it can move under the view
        // once the first fetch lands (and again on the September rollover).
        .onChange(of: viewModel.recentFormSeason) { _, season in
            selectedSeason = season
        }
        .sheet(item: $paywallTrigger) { trigger in
            TrialPitchSheet(trigger: trigger)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            positionSelector
                .padding(.top, 8)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    metricPicker
                    Spacer(minLength: 0)
                    if let through = throughLabel {
                        Text(through)
                            .font(HardwoodType.micro)
                            .foregroundStyle(HardwoodPalette.inkTertiary)
                    }
                }

                // Same control as every other inline picker; only the selected
                // fill differs, because here the choice itself encodes hot vs
                // cold.
                if !isEarlySeason {
                    HardwoodSegmented(
                        segments: [
                            .init(value: false, label: "Heating up", systemImage: "flame.fill"),
                            .init(value: true, label: "Cooling off", systemImage: "snowflake"),
                        ],
                        selection: $showingCold,
                        selectedFill: { $0 ? HardwoodPalette.performanceLow : HardwoodPalette.performanceHigh }
                    )
                }

                HardwoodSegmented(
                    segments: TrendWindow.allCases.map { .init(value: $0, label: $0.segmentLabel) },
                    selection: $viewModel.recentWindow
                )

                Text(isEarlySeason
                     ? "Too early for movement: comparing the \(viewModel.recentWindow.prose) with the span before it needs twice as many games. Until then, the best of the \(viewModel.recentWindow.prose)."
                     : "The \(viewModel.recentWindow.prose) across the league, compared with the same span before it. Players with no games in it are excluded.")
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            // The position tabs draw their own underline and hairline, so with
            // no gap the stat chip sat welded to the bottom of the tab strip
            // and read as part of it. Same 10pt Stats puts above its own
            // control row.
            .padding(.top, HardwoodGeo.controlRowGap)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The last game the window covers: the league plays most nights, so a date
    /// says exactly how current the board is.
    private var throughLabel: String? {
        if let asOf = viewModel.recentFormAsOf(
            window: viewModel.recentWindow,
            season: selectedSeason,
            phase: selectedPhase
        ) {
            return "Through \(asOf.formatted(DataCoverage.gameDayStyle))"
        }
        return nil
    }

    /// Up to two seasons are offered, and the older one is Pro: the free tier is
    /// pinned to the live season everywhere, Trends included. So the locked row
    /// opens the paywall rather than doing nothing, the same as the Stats menu.
    private func selectSeason(_ season: Int) {
        guard viewModel.supportsRecentForm(season) else { return }
        if viewModel.isSeasonLocked(season) {
            paywallTrigger = .lockedSeason(season)
        } else {
            selectedSeason = season
        }
    }

    /// Matches the persistent underlined position row at the top of Stats.
    private var positionSelector: some View {
        HardwoodTabs(
            tabs: TrendSide.allCases.map(\.shortLabel),
            selected: Binding(
                get: { side.shortLabel },
                set: { rawValue in
                    guard let next = TrendSide.allCases.first(where: {
                        $0.shortLabel == rawValue
                    }) else { return }
                    side = next
                }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Position")
    }

    private var metricPicker: some View {
        StatPickerMenu(
            advanced: pickerOptions(TrendMetric.advanced(for: side)),
            standard: pickerOptions(TrendMetric.standard(for: side)),
            activeLabel: metric.label,
            onSelectAdvanced: { select($0, from: TrendMetric.advanced(for: side)) },
            onSelectStandard: { select($0, from: TrendMetric.standard(for: side)) }
        )
    }

    private func pickerOptions(_ list: [TrendMetric]) -> [StatPickerMenu.Option] {
        list.map { .init(id: $0.key, label: $0.label, isSelected: $0.key == metric.key) }
    }

    private func select(_ option: StatPickerMenu.Option, from list: [TrendMetric]) {
        guard let picked = list.first(where: { $0.key == option.id }) else { return }
        metric = picked
    }

    @ViewBuilder
    private var proContent: some View {
        if viewModel.isRecentFormLoading && forms.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let error = viewModel.recentFormError, forms.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load recent form", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") {
                    Task {
                        await viewModel.reloadRecentForm(
                            season: selectedSeason,
                            phase: selectedPhase
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(HardwoodPalette.court)
            }
            .padding(.vertical, 32)
        } else if isEarlySeason, !earlyRanked.isEmpty {
            earlySection(forms: Array(earlyRanked.prefix(50)))
        } else if ranked.isEmpty {
            // A metric the pipeline hasn't produced a prior window for yet
            // ranks nobody, and a bare header under a full set of controls
            // reads as a broken screen. Name the reason and point at the
            // metrics that do have movement.
            ContentUnavailableView {
                Label("No movement to rank yet", systemImage: "chart.line.flattrend.xyaxis")
            } description: {
                Text("\(metric.label) doesn't have a prior window to compare against yet. Try another stat or a shorter window.")
            }
            .padding(.vertical, 32)
        } else {
            section(title: boardTitle, forms: Array(ranked.prefix(50)), ranked: true)
        }
    }

    /// Free users get the real number one, then the wall.
    ///
    /// A gate that shows nobody is easy to walk away from. Showing the actual
    /// hottest player in the league, his name, his THEN to NOW, tappable
    /// through to his page, makes the board demonstrably real, and makes the
    /// blurred ranks below it a thing you can't see rather than a thing that
    /// might not exist. Everything under row one stays invented: blur is not a
    /// security boundary, so the rows behind it were never real numbers.
    private var lockedContent: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: isEarlySeason ? earlyTitle : boardTitle)

            leaderRow

            // The rows are drawn as an overlay on an empty flexible spacer, not
            // stacked directly. A VStack of eighteen rows has an ideal height
            // of ~800pt and `frame(maxHeight:)` doesn't shrink a child below
            // its ideal, so laying them out inline made the card taller than
            // the screen and shoved the whole page up, taking the pickers off
            // the top and the unlock panel off the bottom. `Color.clear` has no
            // ideal height of its own, so it takes exactly the space left over;
            // the overlay fills it and the excess is clipped.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        ForEach(Array(teaserRows.dropFirst().enumerated()), id: \.offset) { index, teaser in
                            teaserRow(teaser, index: index + 1)
                        }
                    }
                    .blur(radius: 8)
                    .allowsHitTesting(false)
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    BlurGateUnlock(
                        // Early on there is no movement yet, and the screen
                        // says so above; sell what is actually behind the blur.
                        headline: isEarlySeason
                            ? "See the full board: every player's \(viewModel.recentWindow.prose) at every position, with movement once there is a span to compare"
                            : "See the full board: every position ranked by how far they've moved",
                        trigger: .recentForm
                    )
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
        // Sits just clear of the floating tab bar. Measured from the safe area,
        // not the screen edge, so this is the pill's height above the inset
        // plus a hair; the page doesn't scroll, so unlike every other screen
        // there's nothing to gain from running underneath it.
        .padding(.bottom, 56)
    }

    /// Row one of the locked board: the genuine leader once the rollup lands,
    /// and a placeholder of the same height until then so the card doesn't
    /// resize under the gate as data arrives.
    @ViewBuilder
    private var leaderRow: some View {
        if isEarlySeason, let leader = earlyRanked.first {
            earlyRow(form: leader, rank: 1, index: 0)
        } else if let leader = ranked.first {
            row(form: leader, rank: 1, index: 0)
        } else {
            HStack(spacing: 10) {
                if viewModel.isRecentFormLoading {
                    ProgressView().scaleEffect(0.7)
                }
                Text(viewModel.isRecentFormLoading ? "Loading the board…" : "No movement to rank yet")
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HardwoodGeo.padInline)
            .frame(height: HardwoodGeo.rowHeight)
            .background(HardwoodPalette.surface)
            .overlay(
                Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                alignment: .bottom
            )
        }
    }

    /// Names the group as well as the direction. Baseball's board covers one of
    /// two sides, so "in the league" is unambiguous there; here it's one of
    /// three position groups and the group is the more useful half of the title.
    private var boardTitle: String {
        let direction = showingCold ? "COOLING OFF" : "HEATING UP"
        return "\(side.label.uppercased()) · \(direction)"
    }

    private func earlySection(forms: [RecentForm]) -> some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: earlyTitle)
            ForEach(Array(forms.enumerated()), id: \.element.id) { index, form in
                earlyRow(form: form, rank: index + 1, index: index)
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

    /// A level, not a change: the value and the volume behind it.
    @ViewBuilder
    private func earlyRow(form: RecentForm, rank: Int, index: Int) -> some View {
        let player = viewModel.players(forSeason: form.season, phase: form.seasonPhase)
            .first { $0.playerId == form.playerId }
        let value = form.metrics[metric.key].map { metric.format($0) } ?? "-"
        let rowContent = HStack(spacing: 10) {
            Text("\(rank)")
                .font(HardwoodType.statSmall)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .frame(width: 26, alignment: .leading)
                .monospacedDigit()
            PlayerHeadshot(team: player?.team ?? form.team ?? "", initials: player?.initials ?? "-", size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(player?.name ?? "Player \(form.playerId)")
                    .font(HardwoodType.bodyBold)
                    .foregroundStyle(HardwoodPalette.ink)
                    .lineLimit(1)
                Text([displayTeamAbbr(player?.team ?? form.team ?? ""), volumeText(form)].joined(separator: " · "))
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(HardwoodType.statMed)
                .foregroundStyle(HardwoodPalette.court)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .frame(height: HardwoodGeo.rowHeight)
        .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank). \(player?.name ?? "Player"), \(metric.label) \(value), \(volumeText(form))")

        if let player {
            NavigationLink(value: player) { rowContent }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(player.name)'s profile")
        } else {
            rowContent
        }
    }

    private func volumeText(_ form: RecentForm) -> String {
        let games = form.games == 1 ? "1 game" : "\(form.games) games"
        return "\(games) · \(form.minutes) min"
    }

    private func section(title: String, forms: [RecentForm], ranked: Bool) -> some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: title)
            ForEach(Array(forms.enumerated()), id: \.element.id) { index, form in
                row(form: form, rank: ranked ? index + 1 : nil, index: index)
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
    private func row(form: RecentForm, rank: Int?, index: Int) -> some View {
        let player = viewModel.players(
            forSeason: form.season,
            phase: form.seasonPhase
        ).first { $0.playerId == form.playerId }
        let delta = form.delta[metric.key] ?? 0
        let now = form.metrics[metric.key]
        let then = form.priorMetrics[metric.key]

        let rowContent = HStack(spacing: 10) {
            if let rank {
                Text("\(rank)")
                    .font(HardwoodType.statSmall)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
                    .frame(width: 26, alignment: .leading)
                    .monospacedDigit()
            }

            PlayerHeadshot(
                team: player?.team ?? form.team ?? "",
                initials: player?.initials ?? "-",
                size: 34
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(player?.name ?? "Player \(form.playerId)")
                        .font(HardwoodType.bodyBold)
                        .foregroundStyle(HardwoodPalette.ink)
                        .lineLimit(1)
                    if favorites.isFavorite(playerId: form.playerId) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.yellow)
                    }
                }
                // THEN to NOW, plus the window and the games in it: "2 wk" says
                // when, "7G" says how many.
                if let then, let now {
                    Text([
                        "\(metric.format(then)) → \(metric.format(now))",
                        "\(form.windowLabel) · \(form.games)G",
                    ].joined(separator: " · "))
                        .font(HardwoodType.micro)
                        .foregroundStyle(HardwoodPalette.inkTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TrendArrow(delta: delta, decimals: metric.decimals, lowerIsBetter: metric.lowerIsBetter)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .frame(height: HardwoodGeo.rowHeight)
        .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
        .overlay(
            Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
            alignment: .bottom
        )
        .contentShape(Rectangle())

        Group {
            if let player {
                NavigationLink(value: player) {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(player.name)'s profile")
            } else {
                rowContent
            }
        }
        // Following straight off the board, so a name you spot here can be
        // pinned without a round trip through the player page.
        .contextMenu {
            Button {
                favorites.toggleFavorite(playerId: form.playerId)
            } label: {
                let following = favorites.isFavorite(playerId: form.playerId)
                Label(following ? "Unfollow" : "Follow", systemImage: following ? "star.slash" : "star")
            }
        }
    }

    /// One row of the invented board behind the gate. Same geometry as the real
    /// `row`, so the blur reads as the board continuing rather than as a
    /// different component.
    private func teaserRow(_ teaser: TeaserRow, index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(HardwoodType.statSmall)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .frame(width: 26, alignment: .leading)
            PlayerHeadshot(team: teaser.team, initials: teaser.initials, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(teaser.name)
                    .font(HardwoodType.bodyBold)
                    .foregroundStyle(HardwoodPalette.ink)
                Text("\(metric.format(teaser.then)) → \(metric.format(teaser.now)) · \(viewModel.recentWindow.segmentLabel) · \(teaser.games)G")
                    .font(HardwoodType.micro)
                    .foregroundStyle(HardwoodPalette.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TrendArrow(
                delta: teaser.now - teaser.then,
                decimals: metric.decimals,
                lowerIsBetter: metric.lowerIsBetter
            )
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, HardwoodGeo.padInline)
        .frame(height: HardwoodGeo.rowHeight)
        .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
    }

    struct TeaserRow {
        let name: String
        let team: String
        let initials: String
        let then: Double
        let now: Double
        let games: Int
    }

    /// Enough plausible rows to overflow the tallest phone behind the gate; the
    /// container clips them, so too many costs nothing and too few leaves the
    /// dead void that made this screen read as broken.
    ///
    /// The faces are real players from the selected group's roster (season data
    /// is free, so nothing is being given away), picked and ordered by a seed
    /// built from every control that can change the real board: the metric, the
    /// direction, the window and the season. That's what makes the board
    /// visibly redraw when a picker moves: with a fixed cast the twelve team
    /// colours stayed in exactly the same order no matter what the controls
    /// said, which gives the game away immediately.
    ///
    /// The seed goes at the *front* of the hashed string, not the end, and that
    /// is load-bearing. `stableSeed` is a rolling `h*31 + c` hash, so a
    /// character appended last contributes a value of 0-127 to a number spread
    /// across 100,003: switching the window from 1 to 2 weeks moved every
    /// player's seed by the same +1 and the sort came out in exactly the same
    /// order. Only the labels changed, under a first row that had visibly
    /// re-ranked. Put the seed first and each of its characters is multiplied
    /// by 31 once per following character, so one digit reshuffles everything.
    private var teaserRows: [TeaserRow] {
        let count = 18
        let seed = "\(metric.key)-\(showingCold)-\(viewModel.recentWindow.rawValue)-\(selectedSeason)-\(selectedPhase.rawValue)"
        let roster = viewModel.players(forSeason: selectedSeason)
            .filter { ($0.playerType ?? "") == side.playerType }
        let names: [(String, String, String)]
        if roster.count >= count {
            names = roster
                .map { ($0, Self.stableSeed("\(seed)-\($0.playerId)")) }
                .sorted { $0.1 < $1.1 }
                .prefix(count)
                .map { ($0.0.name, $0.0.team, $0.0.initials) }
        } else {
            // Pre-load, or a season with no roster yet.
            let placeholders = [
                ("Player One", "BOS", "PO"), ("Player Two", "OKC", "PT"),
                ("Player Three", "PHI", "PT"), ("Player Four", "GSW", "PF"),
                ("Player Five", "DAL", "PF"), ("Player Six", "NYK", "PS"),
                ("Player Seven", "DET", "PS"), ("Player Eight", "MIL", "PE"),
                ("Player Nine", "MIA", "PN"), ("Player Ten", "SAS", "PT"),
                ("Player Eleven", "CLE", "PE"), ("Player Twelve", "MIN", "PT"),
                ("Player Thirteen", "LAC", "PT"), ("Player Fourteen", "HOU", "PF"),
                ("Player Fifteen", "TOR", "PF"), ("Player Sixteen", "PHX", "PS"),
                ("Player Seventeen", "DEN", "PS"), ("Player Eighteen", "ORL", "PE"),
            ]
            names = placeholders
                .map { ($0, Self.stableSeed("\(seed)-\($0.0)")) }
                .sorted { $0.1 < $1.1 }
                .map { $0.0 }
        }
        // Centre and spread the invented values on the metric's own scale, so a
        // percentage reads 56%→64% and a per-100 rate reads 21→26.
        let scale: Double
        let spread: Double
        switch metric.decimals {
        case 0:  scale = 12;   spread = 8
        case 2:  scale = 0.45; spread = 0.25
        default: scale = metric.unit == "%" ? 56 : 21
                 spread = metric.unit == "%" ? 10 : 6
        }
        // The column has to move with the controls as well as the cast. A
        // reshuffled set of faces over an identical ladder of numbers (the same
        // 0.12 → 0.34 at rank two under every window) reads as a template being
        // repainted, which is the same tell the fixed cast was. A few percent
        // of seed-derived drift is enough for it to look recomputed.
        let drift = Double(Self.stableSeed(seed) % 1_000) / 1_000
        let base = scale * (0.9 + 0.2 * drift)
        let swing = spread * (0.85 + 0.3 * drift)
        // Cooling off inverts the movement, and a lower-is-better metric
        // inverts it again: heating up on TOV% means the number falls.
        let improving = !showingCold
        let sign: Double = (improving != metric.lowerIsBetter) ? 1 : -1
        let window = viewModel.recentWindow.rawValue

        return names.enumerated().map { index, who in
            // Per-row wobble, bounded well inside the 0.045 decay step so the
            // board still reads as ranked: rank one always moved furthest.
            let wobble = Double(Self.stableSeed("\(seed)-\(who.0)") % 100) / 100 * 0.03 - 0.015
            let decay = max(0.15, 1.0 - Double(index) * 0.045 + wobble)
            let move = swing * decay
            let then = base - sign * move / 2
            let games = window * 3 + (index + Self.stableSeed(seed)) % 2
            return TeaserRow(
                name: who.0,
                team: who.1,
                initials: who.2,
                then: then,
                now: then + sign * move,
                games: games
            )
        }
    }

    /// Deterministic across launches, unlike `hashValue`, so the preview doesn't
    /// reshuffle itself on a redraw.
    ///
    /// FNV-1a with a murmur3 finalizer rather than the `h*31 + c` this used to
    /// be. The old one was affine: every seed mapped the players' hashes by the
    /// same `h*k + c`, so changing the seed rotated one fixed cyclic order
    /// instead of producing a new one, and a seed that differed only in its
    /// last character barely moved the sort at all. The finalizer is what makes
    /// one flipped bit anywhere in the string change the whole result.
    nonisolated static func stableSeed(_ text: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for scalar in text.unicodeScalars {
            hash = (hash ^ UInt64(scalar.value)) &* 0x100_0000_01b3
        }
        hash ^= hash >> 33
        hash = hash &* 0xff51_afd7_ed55_8ccd
        hash ^= hash >> 33
        return Int(hash % 100_003)
    }
}
