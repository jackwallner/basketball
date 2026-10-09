import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var store: StoreService
    let lastUpdated: Date?
    var dataCoverage: DataCoverage?
    var freshness: DataFreshness?
    @State private var paywallTrigger: PaywallTrigger?

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                proStatusCard
                glossaryCard
                linkCard
                refreshCard
                aboutCard
                versionCard
                disclaimerCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
            Color.clear.frame(height: 88)
        }
        .background(HardwoodPalette.canvas.ignoresSafeArea())
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
    }

    private var glossaryCard: some View {
        NavigationLink {
            StatGlossaryView()
        } label: {
            VStack(spacing: 0) {
                HardwoodSectionBar(title: "REFERENCE")
                row(
                    icon: "text.book.closed.fill",
                    title: "Stat Glossary",
                    subtitle: "Definitions and formulas for every stat in StatScout."
                )
            }
            .background(HardwoodPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                    .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var aboutCard: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: "STATSCOUT")
            HStack(spacing: 12) {
                Image(systemName: "basketball.fill")
                    .font(.title2)
                    .foregroundStyle(HardwoodPalette.court)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Percentile Rankings")
                        .font(HardwoodType.cardTitle)
                        .foregroundStyle(HardwoodPalette.ink)
                    Text("Percentile rankings and leaderboards for every NBA player, ranked within guards, forwards and centers.")
                        .font(HardwoodType.small)
                        .foregroundStyle(HardwoodPalette.inkSecondary)
                }
                Spacer()
            }
            .padding(HardwoodGeo.padCard)
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    private var proStatusCard: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: "STATSCOUT+")
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: store.isPro ? "crown.fill" : "crown")
                        .font(.title2)
                        .foregroundStyle(store.isPro ? Color.yellow : HardwoodPalette.inkTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.isPro ? "StatScout+ Unlocked" : "Free Version")
                            .font(HardwoodType.bodyBold)
                            .foregroundStyle(HardwoodPalette.ink)
                        // Named to match `PaywallView.proFeatures`. This used to
                        // promise "historical seasons and year-over-year
                        // comparisons" and stop there, undercounting the
                        // subscription by three features (Trends, recent form,
                        // head-to-head) on the one screen a user reaches by
                        // going looking for the offer.
                        Text(store.isPro
                             ? "All StatScout+ features are active."
                             : "Unlock Trends, recent form, head-to-head and every season back to 2002-03.")
                            .font(HardwoodType.small)
                            .foregroundStyle(HardwoodPalette.inkSecondary)
                    }
                    Spacer()
                    if !store.isPro {
                        Button(store.isLapsed ? "Renew" : store.upgradeCTALabel) {
                            paywallTrigger = store.defaultUpgradeTrigger
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HardwoodPalette.court)
                        .controlSize(.small)
                    }
                }
                .padding(HardwoodGeo.padCard)

                Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline)
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("Restore Purchases")
                            .font(HardwoodType.smallBold)
                    }
                    .foregroundStyle(HardwoodPalette.linkBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HardwoodGeo.padCard)
                }
                .buttonStyle(.plain)

                if let error = store.lastError {
                    Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline)
                    Text(error)
                        .font(HardwoodType.small)
                        .foregroundStyle(HardwoodPalette.court)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(HardwoodGeo.padCard)
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

    /// Which games are in, phrased the way the boards phrase it.
    ///
    /// The row "Last Refreshed" needs standing next to it. The refresh runs
    /// after every game night against a source that republishes nightly, so on
    /// most days it rewrites every row and closes out few new games: the write
    /// stamp says today while the newest game is last night's. Reporting only
    /// the write stamp made the app contradict the Trends header, which
    /// correctly says "Through Jun 13".
    private var gamesThroughText: String {
        guard let coverage = freshness?.coverage ?? dataCoverage else { return "-" }
        return coverage.asOf.formatted(DataCoverage.gameDayStyle)
    }

    private var checkedText: String {
        (freshness?.checkedAt ?? lastUpdated)?.formatted(date: .long, time: .shortened) ?? "-"
    }

    private var sourcePublishedText: String? {
        freshness?.sourcePublishedAt?.formatted(date: .long, time: .shortened)
    }

    private var refreshCard: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: "DATA")
            row(
                icon: "arrow.triangle.2.circlepath",
                title: "Data Updates",
                subtitle: "Checks for new NBA player data throughout the season."
            )
            Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline)
            row(
                icon: "calendar.badge.clock",
                title: "Games Through",
                subtitle: gamesThroughText
            )
            Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline)
            row(
                icon: "clock.arrow.circlepath",
                title: "Last Checked",
                subtitle: checkedText
            )
            if let sourcePublishedText {
                Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline)
                row(
                    icon: "cloud.sun.fill",
                    title: "Source Published",
                    subtitle: sourcePublishedText
                )
            }
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    private var linkCard: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: "SUPPORT & PRIVACY")
            // The native rating sheet is rate-limited and may show nothing, so
            // this is the way for a user who wants to leave a review to do it.
            // Feedback is a separate action below (Contact Support).
            Link(destination: AppStoreReviewLinks.writeReviewURL) {
                row(
                    icon: "square.and.pencil",
                    title: "Rate on the App Store",
                    subtitle: "Opens the App Store to write a review."
                )
            }
            .buttonStyle(.plain)

            Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline)

            if let supportURL = URL(string: "https://jackwallner.github.io/basketball/support.html") {
                Link(destination: supportURL) {
                    row(
                        icon: "envelope.fill",
                        title: "Contact Support",
                        subtitle: "jackwallner+bb@gmail.com"
                    )
                }
                .buttonStyle(.plain)
            }
            
            Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline)
            
            if let privacyURL = URL(string: "https://jackwallner.github.io/basketball/privacy-policy.html") {
                Link(destination: privacyURL) {
                    row(
                        icon: "shield.lefthalf.filled",
                        title: "Privacy Policy",
                        subtitle: "No ads or tracking."
                    )
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

    private var versionCard: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: "VERSION")
            HStack {
                Text("App Version")
                    .font(HardwoodType.bodyBold)
                    .foregroundStyle(HardwoodPalette.ink)
                Spacer()
                Text(version)
                    .font(HardwoodType.statSmall)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
            }
            .padding(HardwoodGeo.padCard)
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    private var disclaimerCard: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: "DISCLAIMER")
            Text("Not affiliated with, endorsed by, or sponsored by the National Basketball Association, its teams, or the NBPA. Team names and abbreviations are used for identification only. All trademarks are property of their respective owners.")
                .font(HardwoodType.small)
                .foregroundStyle(HardwoodPalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HardwoodGeo.padCard)
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(HardwoodPalette.court)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(HardwoodType.bodyBold)
                    .foregroundStyle(HardwoodPalette.ink)
                Text(subtitle)
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
            }
            Spacer()
        }
        .padding(HardwoodGeo.padCard)
    }
}

private struct GlossaryEntry: Identifiable {
    let id: String
    let label: String
    let category: String
    let description: String
    /// "Advanced · Efficiency": the kind and family a registry metric belongs to.
    var detail: String? = nil
}

struct StatGlossaryView: View {
    @State private var searchText = ""

    private let supplemental: [GlossaryEntry] = [
        .init(id: "general-games", label: "G", category: "Standard Stats", description: "Games in which the player appeared."),
        .init(id: "standard-fg", label: "FG", category: "Standard Stats", description: "Field goals made and attempted. Ranked by shooting percentage, not by makes."),
        .init(id: "standard-3p", label: "3P", category: "Standard Stats", description: "Three-pointers made and attempted. Ranked by shooting percentage."),
        .init(id: "standard-ft", label: "FT", category: "Standard Stats", description: "Free throws made and attempted. Ranked by shooting percentage."),
        .init(id: "standard-tov", label: "TOV", category: "Standard Stats", description: "Total turnovers. Lower is better."),
        .init(id: "standard-pf", label: "PF", category: "Standard Stats", description: "Total personal fouls. Lower is better."),
        .init(id: "standard-min", label: "MIN", category: "Standard Stats", description: "Total minutes played. Every rate on a roster is weighted by it."),
        .init(id: "general-power", label: "Power Rating", category: "General", description: "Points per 100 possessions better or worse than an average team, from offensive and defensive rating adjusted for schedule. Early in the season last season's rating carries part of the weight. Two ratings read like a point spread, with about two and a half points for home court."),
        .init(id: "general-small-sample", label: "Small sample", category: "General", description: "Below the playing-time minimum for that stat, prorated by how much of the season the typical team has played. A full-season player needs about 870 minutes and 20 games."),
        .init(id: "general-not-ranked", label: "Not ranked", category: "General", description: "A counting stat at zero. When most of the league has none of something, a tie at zero has no honest percentile, so the value shows and the bar does not."),
        .init(id: "general-groups", label: "Position groups", category: "General", description: "Guards (G), forwards (F) and centers (C), as the box score lists them. A center's rebounding is ranked against centers, so a percentile always means \"among players who play where he plays\"."),
        .init(id: "percentile", label: "Percentile", category: "General", description: "A 1–100 rank among players in the same position group, season, and season type. Higher is always better after lower-is-better stats are inverted."),
    ]

    private var entries: [GlossaryEntry] {
        let registry = BasketballMetricRegistry.definitions.map {
            GlossaryEntry(
                id: "\($0.category.rawValue)-\($0.label)",
                label: $0.label,
                category: $0.category.rawValue,
                description: $0.description,
                detail: "\($0.kind.rawValue) · \($0.family.rawValue)"
            )
        }
        let all = (supplemental + registry).sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.label.localizedCaseInsensitiveContains(searchText)
                || $0.category.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var categories: [String] {
        let order = ["General"] + MetricCategory.allCases.map(\.rawValue) + ["Standard Stats"]
        return order.filter { category in entries.contains { $0.category == category } }
    }

    /// A `ScrollView` of cards, not a `List` with `.searchable`.
    ///
    /// Two things were wrong with the system version. The app draws its own
    /// floating tab bar over every screen, including pushed ones - and on iOS 26
    /// `.searchable` puts the search field at the *bottom* of the screen, so the
    /// field materialised underneath the tab bar with its lower half clipped off.
    /// Nothing about the search was reachable. And the grouped `List` was the one
    /// screen in the app rendering system chrome instead of the card idiom
    /// everything else uses, so it read as a different app.
    ///
    /// The in-content `SearchField` is the same control the Teams tab and the
    /// team roster already use, it sits where the reader's eye starts, and it
    /// cannot collide with the tab bar.
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SearchField(text: $searchText, prompt: "Search stats")

                Text("Values come from ESPN box scores, play-by-play and shot charts via hoopR. Percentiles are calculated within each position group, separately for each season and season type. The current season ranks everyone who has played; past seasons rank qualifying players.")
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No stats found", systemImage: "magnifyingglass")
                    } description: {
                        Text("Nothing matches \"\(searchText)\". Try a stat's abbreviation, like TS% or AST%.")
                    }
                    .padding(.vertical, 40)
                } else {
                    ForEach(categories, id: \.self) { category in
                        categoryCard(category)
                    }
                }

                sourcesCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            // Scroll-under spacer for the floating tab bar, same as every other
            // scrolling screen.
            Color.clear.frame(height: 88)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(HardwoodPalette.canvas.ignoresSafeArea())
        .navigationTitle("Stat Glossary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryCard(_ category: String) -> some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: category.uppercased())

            let rows = entries.filter { $0.category == category }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.label)
                            .font(HardwoodType.bodyBold)
                            .foregroundStyle(HardwoodPalette.ink)
                        if let detail = entry.detail {
                            Text(detail.uppercased())
                                .font(HardwoodType.micro)
                                .foregroundStyle(HardwoodPalette.inkTertiary)
                        }
                    }
                    Text(entry.description)
                        .font(HardwoodType.small)
                        .foregroundStyle(HardwoodPalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HardwoodGeo.padCard)
                .background(index % 2 == 0 ? HardwoodPalette.surface : HardwoodPalette.surfaceAlt)
                .overlay(
                    Rectangle().fill(HardwoodPalette.divider).frame(height: HardwoodGeo.hairline),
                    alignment: .bottom
                )
            }
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    private var sourcesCard: some View {
        VStack(spacing: 0) {
            HardwoodSectionBar(title: "SOURCES")
            sourceRow(
                "hoopR NBA data (ESPN box scores, play-by-play, shots)",
                url: URL(string: "https://hoopr.sportsdataverse.org/")!
            )
            sourceRow(
                "Basketball-Reference Glossary",
                url: URL(string: "https://www.basketball-reference.com/about/glossary.html")!,
                isLast: true
            )
        }
        .background(HardwoodPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: HardwoodGeo.radiusCard)
                .stroke(HardwoodPalette.hairline, lineWidth: 0.5)
        )
    }

    private func sourceRow(_ title: String, url: URL, isLast: Bool = false) -> some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Text(title)
                    .font(HardwoodType.small)
                    .foregroundStyle(HardwoodPalette.court)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HardwoodPalette.inkTertiary)
            }
            .padding(HardwoodGeo.padCard)
            .background(HardwoodPalette.surface)
            .overlay(
                Rectangle()
                    .fill(isLast ? Color.clear : HardwoodPalette.divider)
                    .frame(height: HardwoodGeo.hairline),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        AboutView(
            lastUpdated: Date(),
            dataCoverage: DataCoverage(asOf: .now, week: nil, phase: .regular)
        )
            .environmentObject(StoreService.shared)
    }
}
