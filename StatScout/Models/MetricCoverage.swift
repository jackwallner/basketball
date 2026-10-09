import Foundation

/// What the data can and cannot say about a given season.
///
/// StatScout carries every season from 2002-03 on, but the *advanced* metrics
/// don't all reach that far back, because the sources don't. ESPN's box score
/// has no plus/minus before 2008-09, the shot feed tracks nearly every attempt
/// only from 2003-04, and On-Off needs a play-by-play replay that reproduces
/// the box score's plus/minus, which it does in only some seasons.
///
/// Without this, those gaps read as bugs. A user who opens 2005-06, sees an
/// Impact board with no On-Court +/- and is told nothing, has been given a
/// reason to distrust the numbers that *are* there. Naming the limit is what
/// makes the rest of the board credible - and it is a limit of the public
/// record, not of the app.
///
/// The season numbers here mirror the constants in `backend/ingest.py`; the
/// coverage table in `handoff/NBA_CONTRACT.md` is the shared reference.
enum MetricCoverage {
    /// Every box-score metric (Scoring, Playmaking, Rebounding, Defense, Min%,
    /// MPG, GS). hoopR's player box starts in 2002; 2003 is the first full
    /// season.
    static let boxScoreFirstSeason = 2003
    /// On-Court +/- and the +/- total. ESPN's plus/minus is a placeholder for
    /// every player through 2007-08.
    static let onCourtFirstSeason = 2009
    /// Shot zones: the shot feed tracks 98-100% of box attempts from 2003-04.
    static let shotZonesFirstSeason = 2004
    /// On-Off is published per season and phase, only where the play-by-play
    /// replay reproduces the box plus/minus for at least 97% of player games.
    /// From this season on it clears the bar every time.
    static let onOffAlwaysFirstSeason = 2021
    static let onOffRegularSeasons: Set<Int> = [2014, 2015]
    static let onOffPostseasons: Set<Int> = [2009, 2010, 2012, 2013, 2014, 2015]

    static func hasOnOff(season: Int, phase: SeasonPhase = .regular) -> Bool {
        if StatScoutSeason.isAllTime(season) { return false }
        if season >= onOffAlwaysFirstSeason { return true }
        switch phase {
        case .regular: return onOffRegularSeasons.contains(season)
        case .playoffs: return onOffPostseasons.contains(season)
        }
    }

    /// One short sentence explaining what this season is missing, or nil when
    /// the season has the full metric set.
    ///
    /// Deliberately at most two clauses. A season that predates several sources
    /// at once would otherwise produce a paragraph nobody reads, so the oldest
    /// and most sweeping limit is the one named.
    static func note(
        for season: Int,
        category: MetricCategory? = nil,
        phase: SeasonPhase = .regular
    ) -> String? {
        // The career rollup spans every era, so it is bounded by all of them at
        // once; saying so once is more honest than listing three start years.
        if StatScoutSeason.isAllTime(season) {
            return "Career totals span \(SeasonLabel.text(boxScoreFirstSeason)) onward. Shot zones count from \(SeasonLabel.text(shotZonesFirstSeason)), On-Court +/- from \(SeasonLabel.text(onCourtFirstSeason)), and career On-Off is not published."
        }

        if category == .shooting {
            return season < shotZonesFirstSeason
                ? "Shot-zone numbers start in \(SeasonLabel.text(shotZonesFirstSeason))."
                : nil
        }

        if category == .impact {
            if season < onCourtFirstSeason {
                return "Plus/minus starts in \(SeasonLabel.text(onCourtFirstSeason)); ESPN's box scores carry none before that."
            }
            return hasOnOff(season: season, phase: phase)
                ? nil
                : "On-Off is not published for this \(phase == .regular ? "season" : "postseason"): the replay of the play-by-play did not match the box score closely enough."
        }

        if category != nil { return nil }

        if season < shotZonesFirstSeason {
            return "Shot zones start in \(SeasonLabel.text(shotZonesFirstSeason)) and plus/minus in \(SeasonLabel.text(onCourtFirstSeason))."
        }
        if season < onCourtFirstSeason {
            return "On-Court +/- and On-Off start later: plus/minus in \(SeasonLabel.text(onCourtFirstSeason))."
        }
        if !hasOnOff(season: season, phase: phase) {
            return "On-Off is not published for this \(phase == .regular ? "season" : "postseason"): the play-by-play replay did not match the box score closely enough."
        }
        return nil
    }

    /// The live season's own gap: a feed that exists for this year but has not
    /// caught up with the games already published. `note(for:)` can only say
    /// what a year predates, so a week after opening night, with the shot feed
    /// a day behind, the Shooting board said nothing about why the zones were
    /// missing for the latest games.
    static func pendingNote(
        category: MetricCategory?,
        shotsStatus: String?,
        playByPlayStatus: String?
    ) -> String? {
        func pending(_ status: String?) -> Bool {
            guard let status = status?.lowercased() else { return false }
            return status != "ready" && status != "not_applicable" && status != "unavailable"
        }
        let shots = "Shot-zone numbers for the latest games are still arriving"
        let onOff = "On/off numbers for the latest games are still arriving"
        switch category {
        case .shooting:
            return pending(shotsStatus) ? shots + "." : nil
        case .impact:
            return pending(playByPlayStatus) ? onOff + "." : nil
        case nil:
            return [pending(shotsStatus) ? shots : nil, pending(playByPlayStatus) ? onOff : nil]
                .compactMap { $0 }
                .map { $0 + "." }
                .joined(separator: " ")
                .nilIfEmpty
        default:
            return nil
        }
    }

    /// Whether a metric is expected to exist at all in this season. Lets a
    /// caller distinguish "nobody qualified" from "not tracked".
    static func isTracked(
        _ label: String,
        in season: Int,
        phase: SeasonPhase = .regular
    ) -> Bool {
        if StatScoutSeason.isAllTime(season) { return label != "On-Off" }
        switch label {
        case "Rim Freq", "Rim FG%", "Short Mid Freq", "Short Mid FG%",
             "Long Mid Freq", "Long Mid FG%", "Corner 3%", "Non-Corner 3%", "Assisted FG%":
            return season >= shotZonesFirstSeason
        case "On-Court +/-", "+/-":
            return season >= onCourtFirstSeason
        case "On-Off":
            return hasOnOff(season: season, phase: phase)
        default:
            return season >= boxScoreFirstSeason
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
