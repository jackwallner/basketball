import Foundation

/// The running score of a game under way, read from ESPN's public NBA
/// scoreboard. The StatScout backend posts a score only once hoopR publishes
/// the final, so this is what lets a game in progress (and a final from the
/// last few hours) show its score. hoopR is an ESPN mirror, so the game ids
/// are the same.
struct LiveScore: Hashable, Sendable {
    let gameId: String
    let awayScore: Int
    let homeScore: Int
    /// ESPN `status.type.state`: `pre`, `in` or `post`. Only `in` and a
    /// completed `post` are kept (see `parse`).
    let state: String
    /// ESPN `status.type.shortDetail` ("4:12 - 3rd", "Halftime", "End of
    /// 3rd", "Final/OT"), used only to spot halftime.
    let detail: String
    let period: Int
    /// ESPN `status.displayClock`: "4:12", "45.2", "0.0".
    var clock: String = ""

    var isFinal: Bool { state == "post" }
    var isUnderway: Bool { state == "in" }

    private var periodName: String {
        switch period {
        case ...4: return "Q\(max(period, 1))"
        case 5: return "OT"
        default: return "\(period - 4)OT"
        }
    }

    /// "Q3 4:12", "Half", "End Q3", "OT 1:05", "Final/OT".
    var clockLabel: String {
        if isFinal {
            switch period {
            case ...4: return "Final"
            case 5: return "Final/OT"
            default: return "Final/\(period - 4)OT"
            }
        }
        if detail.localizedCaseInsensitiveContains("halftime") { return "Half" }
        if detail.localizedCaseInsensitiveContains("end of") || clock == "0.0" || clock == "0:00" {
            return "End \(periodName)"
        }
        return clock.isEmpty ? periodName : "\(periodName) \(clock)"
    }

    func score(isHome: Bool) -> Int { isHome ? homeScore : awayScore }

    /// Games from one scoreboard payload that have started.
    static func parse(_ data: Data) -> [LiveScore] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return payload.events.compactMap { event in
            let kind = event.status.type
            // A game under way, or one that really finished. A postponed or
            // suspended game is also `post`, with no completion and 0-0.
            guard kind.state == "in" || (kind.state == "post" && kind.completed == true),
                  let competition = event.competitions.first,
                  let home = competition.competitors.first(where: { $0.homeAway == "home" }),
                  let away = competition.competitors.first(where: { $0.homeAway == "away" }),
                  let homeScore = home.score.flatMap(Int.init),
                  let awayScore = away.score.flatMap(Int.init)
            else { return nil }
            return LiveScore(
                gameId: event.id,
                awayScore: awayScore,
                homeScore: homeScore,
                state: event.status.type.state,
                detail: kind.shortDetail ?? "",
                period: event.status.period ?? 1,
                clock: event.status.displayClock ?? ""
            )
        }
    }

    private struct Payload: Decodable {
        let events: [Event]
    }

    private struct Event: Decodable {
        struct Status: Decodable {
            struct Kind: Decodable {
                let state: String
                let completed: Bool?
                let shortDetail: String?
            }
            let period: Int?
            let displayClock: String?
            let type: Kind
        }
        struct Competition: Decodable {
            let competitors: [Competitor]
        }
        struct Competitor: Decodable {
            let homeAway: String
            let score: String?
        }
        let id: String
        let status: Status
        let competitions: [Competition]
    }
}

extension Game {
    /// The one status every surface shows for a game that has tipped off: the
    /// scoreboard's clock when it has one, else "In progress" or, hours on
    /// with no score posted, "Final soon".
    func startedLabel(live: LiveScore?, now: Date = .now) -> String {
        if let live { return live.clockLabel }
        if isScorePending(now: now) { return "Score pending" }
        return status(now: now) == .awaitingScore ? "Final soon" : "In progress"
    }

    /// Tipped off more than twelve hours ago with no score anywhere: over,
    /// not "in progress", but with nothing to show yet.
    func isScorePending(now: Date = .now) -> Bool {
        guard !isFinal, let tipoff else { return false }
        return now.timeIntervalSince(tipoff) > 12 * 3_600
    }
}

/// Reads ESPN's NBA scoreboard for the given game dates ("20261020").
struct LiveScoreClient: Sendable {
    var session: URLSession = .shared

    func fetch(dates: Set<String>) async -> [String: LiveScore] {
        await withTaskGroup(of: [LiveScore].self) { group in
            for date in dates {
                group.addTask {
                    let base = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"
                    guard let url = URL(string: "\(base)?dates=\(date)") else { return [] }
                    var request = URLRequest(url: url, timeoutInterval: 10)
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    guard let (data, response) = try? await session.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                    return LiveScore.parse(data)
                }
            }
            var scores: [String: LiveScore] = [:]
            for await batch in group {
                for score in batch { scores[score.gameId] = score }
            }
            return scores
        }
    }

    /// The scoreboard files a game under its Eastern date; `Game.gameDate`
    /// holds it at Eastern midnight (see `DataFreshness.parseDate`).
    static func dateKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
