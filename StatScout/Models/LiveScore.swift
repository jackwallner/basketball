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
    /// ESPN `status.type.state`: `pre`, `in` or `post`.
    let state: String
    /// ESPN `status.type.shortDetail`: "Q3 4:12", "Halftime", "End of 3rd",
    /// "Final", "Final/OT".
    let detail: String
    let period: Int

    var isFinal: Bool { state == "post" }
    var isUnderway: Bool { state == "in" }
    var isOvertime: Bool { period > 4 }

    /// "Q3 4:12", "Half", "End Q3", "Final/OT".
    var clockLabel: String {
        if isFinal {
            switch period {
            case ...4: return "Final"
            case 5: return "Final/OT"
            default: return "Final/\(period - 4)OT"
            }
        }
        if detail.localizedCaseInsensitiveContains("halftime") { return "Half" }
        if detail.hasPrefix("End of ") {
            return "End " + (period > 4 ? (period == 5 ? "OT" : "\(period - 4)OT") : "Q\(period)")
        }
        return detail
    }

    func score(isHome: Bool) -> Int { isHome ? homeScore : awayScore }

    /// Games from one scoreboard payload that have started.
    static func parse(_ data: Data) -> [LiveScore] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return payload.events.compactMap { event in
            guard event.status.type.state != "pre",
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
                detail: event.status.type.shortDetail ?? "",
                period: event.status.period ?? 1
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
                let shortDetail: String?
            }
            let period: Int?
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
