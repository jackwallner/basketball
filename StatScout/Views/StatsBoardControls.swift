import SwiftUI

/// Which league-wide board the Stats tab is drawing.
enum StatsBoard: String, Hashable {
    case advanced
    case standard
    case bestWorst
}

/// The traditional line offered for each position cohort: the same fifteen
/// counting stats for everyone, led by what that cohort is read on.
enum StandardStatCatalog {
    private static let everyone = [
        "PPG", "RPG", "APG", "SPG", "BPG", "FG", "3P", "FT", "TOV", "PF", "+/-", "MPG", "MIN", "G", "GS",
    ]

    static func stats(for position: PlayerPositionGroup) -> [String] {
        let lead: String
        switch position {
        case .all, .forward: lead = "PPG"
        case .guard: lead = "APG"
        case .center: lead = "RPG"
        }
        return [lead] + everyone.filter { $0 != lead }
    }

    /// Best first: turnovers and fouls read better low, so their boards open
    /// lowest-first.
    static func defaultDescending(for stat: String, position: PlayerPositionGroup) -> Bool {
        StandardStatSemantics.higherIsBetter(label: stat)
    }

    static func defaultStat(for position: PlayerPositionGroup) -> String {
        stats(for: position).first ?? "G"
    }

    /// The stat to show after the position tab changes.
    ///
    /// A stat the user picked on purpose follows them to any position that
    /// offers it. The previous position's own default does not: it is not a
    /// choice, and carrying it over ranked centers by APG after a
    /// G, F, C walk through the tabs.
    static func stat(
        keeping current: String,
        from old: PlayerPositionGroup,
        to new: PlayerPositionGroup
    ) -> String {
        if current != defaultStat(for: old), stats(for: new).contains(current) {
            return current
        }
        return defaultStat(for: new)
    }
}

/// The one control used everywhere to choose which statistic a board ranks.
struct StatPickerMenu: View {
    struct Option: Identifiable {
        let id: String
        let label: String
        var isSelected = false
        /// The metric category the option sits under in the menu.
        var group: String? = nil

        /// Advanced metric labels as options grouped by category, in the
        /// order the player page reads (Scoring, Shooting, ... Impact), each
        /// category in its own priority order.
        static func categorized(_ labels: [String], selected: String?) -> [Option] {
            let order = MetricCategory.allCases
            return labels
                .map { label -> (option: Option, rank: (Int, Int)) in
                    let definition = BasketballMetricRegistry.definitions.first { $0.label == label }
                    let category = definition?.category
                    return (
                        Option(id: label, label: label, isSelected: label == selected, group: category?.rawValue),
                        (category.flatMap { order.firstIndex(of: $0) } ?? order.count, definition?.priority ?? Int.max)
                    )
                }
                .sorted { $0.rank < $1.rank }
                .map(\.option)
        }
    }

    var advanced: [Option] = []
    var standard: [Option] = []
    let activeLabel: String
    var onSelectAdvanced: (Option) -> Void = { _ in }
    var onSelectStandard: (Option) -> Void = { _ in }

    var body: some View {
        Menu {
            if advanced.contains(where: { $0.group != nil }) {
                ForEach(groups(advanced), id: \.title) { group in
                    Section(group.title) {
                        rows(group.options, select: onSelectAdvanced)
                    }
                }
            } else if !advanced.isEmpty {
                Section("Advanced") {
                    rows(advanced, select: onSelectAdvanced)
                }
            }
            if !standard.isEmpty {
                Section("Standard") {
                    rows(standard, select: onSelectStandard)
                }
            }
        } label: {
            HardwoodInlinePill(systemImage: "chart.bar.fill", title: activeLabel)
        }
        .menuOrder(.fixed)
        .hardwoodMenuAppearance()
        .accessibilityLabel("Stat")
        .accessibilityValue(activeLabel)
    }

    /// Consecutive options sharing a group, in order.
    private func groups(_ options: [Option]) -> [(title: String, options: [Option])] {
        var result: [(title: String, options: [Option])] = []
        for option in options {
            let title = option.group ?? "Advanced"
            if result.last?.title == title {
                result[result.count - 1].options.append(option)
            } else {
                result.append((title, [option]))
            }
        }
        return result
    }

    private func rows(
        _ options: [Option],
        select: @escaping (Option) -> Void
    ) -> some View {
        ForEach(options) { option in
            Button {
                select(option)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                if option.isSelected {
                    Label(option.label, systemImage: "checkmark")
                } else {
                    Text(option.label)
                }
            }
        }
    }
}

/// Compact direction toggle that sits beside the shared stat picker.
struct SortDirectionButton: View {
    let descending: Bool
    let statLabel: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HardwoodChip(trailing: .sortArrow(descending: descending))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort direction")
        .accessibilityValue("\(statLabel), \(descending ? "highest first" : "lowest first")")
        .accessibilityHint("Tap to flip sort direction")
    }
}

/// Shared state owned by `StatsView` and passed into either leaderboard.
struct StatsBoardBindings {
    @Binding var board: StatsBoard
    @Binding var standardStat: String
    @Binding var standardSortDescending: Bool
}

/// Picking a statistic also selects the vocabulary that owns it.
struct StatsBoardStatPicker: View {
    @Bindable var viewModel: DashboardViewModel
    let bindings: StatsBoardBindings

    private var position: PlayerPositionGroup { viewModel.selectedPosition }

    private var activeLabel: String {
        switch bindings.board {
        case .advanced:
            return viewModel.currentSortMetric ?? viewModel.sortLabel
        case .standard:
            return bindings.standardStat
        case .bestWorst:
            return "Best & Worst"
        }
    }

    var body: some View {
        StatPickerMenu(
            advanced: StatPickerMenu.Option.categorized(
                viewModel.availableAdvancedSortMetrics,
                selected: bindings.board == .advanced ? viewModel.currentSortMetric : nil
            ),
            standard: StandardStatCatalog.stats(for: position).map { stat in
                .init(
                    id: stat,
                    label: stat,
                    isSelected: bindings.board == .standard
                        && stat == bindings.standardStat
                )
            },
            activeLabel: activeLabel,
            onSelectAdvanced: { option in
                bindings.board = .advanced
                viewModel.setUserSortMetric(option.id)
            },
            onSelectStandard: { option in
                bindings.board = .standard
                bindings.standardStat = option.id
                bindings.standardSortDescending = StandardStatCatalog.defaultDescending(
                    for: option.id,
                    position: position
                )
            }
        )
    }
}

/// Secondary board options. Position stays in the persistent tab row, while
/// qualification and Best & Worst live here.
struct StatsViewMenu: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    @Binding var board: StatsBoard

    private var isActive: Bool {
        viewModel.qualifierLevel != .all
            || viewModel.selectedConference != .all
            || viewModel.isRookieFilterActive
            || board == .bestWorst
    }

    var body: some View {
        Menu {
            conferenceSection
            if viewModel.canFilterRookies { playersSection }
            qualifierSection
            boardSection
        } label: {
            HardwoodChip(
                title: "View",
                systemImage: "slider.horizontal.3",
                trailing: .chevron,
                isActive: isActive
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("View options")
    }

    private var conferenceSection: some View {
        Section("Conference") {
            ForEach(NBAConference.allCases) { conference in
                Button {
                    viewModel.selectedConference = conference
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if conference == viewModel.selectedConference {
                        Label(conference.rawValue, systemImage: "checkmark")
                    } else {
                        Text(conference.rawValue)
                    }
                }
            }
        }
    }

    private var playersSection: some View {
        Section("Players") {
            ForEach([false, true], id: \.self) { rookies in
                Button {
                    viewModel.rookiesOnly = rookies
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    let title = rookies ? "Rookies only" : "Everyone"
                    if viewModel.rookiesOnly == rookies {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        }
    }

    private var qualifierSection: some View {
        Section("Qualifier") {
            ForEach(DashboardViewModel.QualifierLevel.allCases) { level in
                Button {
                    viewModel.qualifierLevel = level
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    let title = "\(level.rawValue) · \(level.description)"
                    if level == viewModel.qualifierLevel {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        }
    }

    private var boardSection: some View {
        Section("Show") {
            Button {
                if board == .bestWorst { board = .advanced }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                if board != .bestWorst {
                    Label("Leaderboard", systemImage: "checkmark")
                } else {
                    Text("Leaderboard")
                }
            }

            Button {
                board = .bestWorst
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                if board == .bestWorst {
                    Label("Best & Worst", systemImage: "checkmark")
                } else if store.isPro {
                    Text("Best & Worst")
                } else {
                    Label("Best & Worst (StatScout+)", systemImage: "crown.fill")
                }
            }
        }
    }
}
