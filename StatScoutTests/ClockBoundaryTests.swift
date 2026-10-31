import XCTest
@testable import Hardwood_StatScout

/// Date logic pinned to a fixed clock and explicit zones, never the machine's.
///
/// Every test names the past fix it guards, or says it is a new guard.
final class ClockBoundaryTests: XCTestCase {
    private let la: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func local(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
                       _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // MARK: The season calendar

    /// SeasonResolverTests: the calendar names the new season on 1 October,
    /// local midnight, three weeks before the first tip-off.
    func testCalendarSeasonFlipsAtLocalMidnightOnOctoberFirst() {
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: local(la, 2026, 9, 30, 23, 59, 59), calendar: la), 2026)
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: local(la, 2026, 10, 1, 0, 0, 0), calendar: la), 2027)
        let instantAfterUTCOctober = instant("2026-10-01T03:00:00Z")
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: instantAfterUTCOctober, calendar: utc), 2027)
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: instantAfterUTCOctober, calendar: la), 2026)
    }

    /// New guard: the season is named for the year it ends in, so New Year,
    /// the Finals in June and the summer all stay in the season that began the
    /// previous October, and neither DST changeover moves the flip.
    func testCalendarSeasonHoldsThroughNewYearTheFinalsAndTheSummer() {
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: local(la, 2026, 12, 31, 23, 59, 59), calendar: la), 2027)
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: local(la, 2027, 1, 1), calendar: la), 2027)
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: local(la, 2027, 3, 14, 2, 30), calendar: la), 2027)
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: local(la, 2027, 6, 20), calendar: la), 2027)
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: local(la, 2027, 9, 30, 23, 59, 59), calendar: la), 2027)
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: local(la, 2027, 10, 1), calendar: la), 2028)
        XCTAssertEqual(StatScoutSeason.calendarSeason(on: local(la, 2026, 11, 1, 1, 30), calendar: la), 2027)
    }

    /// SeasonResolverTests: preseason to regular season to playoffs to
    /// offseason against fixed dates, joining the calendar rule to the
    /// publisher's status row. The new season is only the live one once the
    /// publisher has caught up; the weeks between are a pending season.
    func testSeasonLifecycleFromTheCalendarAndThePublisher() {
        func live(_ moment: Date, season: Int, published: Int, pending: Bool) -> StatScoutSeason.Live {
            let calendarSeason = StatScoutSeason.calendarSeason(on: moment, calendar: la)
            XCTAssertEqual(calendarSeason, season, "\(moment)")
            let status = DataFreshness(
                status: DataFreshnessStatus(rawValue: pending ? "source_pending" : "published"),
                rawStatus: pending ? "source_pending" : "published",
                season: calendarSeason, publishedSeason: published,
                lastErrorCode: pending ? "season_pending" : nil
            )
            return StatScoutSeason.resolveLive(from: status, fallback: 2026)
        }
        // Late September: the old season is still live, nothing pending.
        XCTAssertEqual(live(local(la, 2026, 9, 30, 23), season: 2026, published: 2026, pending: false),
                       .init(season: 2026, upcoming: nil))
        // 1 October: the calendar is a season ahead of the data.
        XCTAssertEqual(live(local(la, 2026, 10, 1), season: 2027, published: 2026, pending: true),
                       .init(season: 2026, upcoming: 2027))
        // Opening night, once the publisher has flipped.
        XCTAssertEqual(live(local(la, 2026, 10, 21, 20), season: 2027, published: 2027, pending: false),
                       .init(season: 2027, upcoming: nil))
        // The Finals, and the summer after them.
        XCTAssertEqual(live(local(la, 2027, 6, 18, 18), season: 2027, published: 2027, pending: false),
                       .init(season: 2027, upcoming: nil))
        XCTAssertEqual(live(local(la, 2027, 8, 1), season: 2027, published: 2027, pending: false),
                       .init(season: 2027, upcoming: nil))
        // The next 1 October starts the cycle again.
        XCTAssertEqual(live(local(la, 2027, 10, 1), season: 2028, published: 2027, pending: true),
                       .init(season: 2027, upcoming: 2028))
    }

    /// SeasonResolverTests: a cold first launch before the server answers is
    /// the calendar's season capped at what the bundle can draw, so the
    /// weeks after 1 October open on the bundled season, not an empty one.
    func testColdLaunchAfterTheOctoberFlipOpensOnTheBundledSeason() {
        let name = "clock-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let october = StatScoutSeason.calendarSeason(on: local(la, StatScoutSeason.bundledNewest, 10, 2), calendar: la)
        XCTAssertEqual(october, StatScoutSeason.bundledNewest + 1)
        XCTAssertEqual(StatScoutSeason.initialLive(defaults: defaults, calendarSeason: october).season,
                       StatScoutSeason.bundledNewest)
        let september = StatScoutSeason.calendarSeason(on: local(la, StatScoutSeason.bundledNewest, 9, 30), calendar: la)
        XCTAssertEqual(StatScoutSeason.initialLive(defaults: defaults, calendarSeason: september).season,
                       StatScoutSeason.bundledNewest)
    }

    // MARK: The day a fan means by "today"

    private func day(_ iso: String) -> GameDay {
        GameDay(date: DataFreshness.parseDate(iso)!, phase: .regular)
    }

    /// Found by this test: the front door held a day for 32 hours after
    /// Eastern midnight, which is 8 AM Eastern only on ordinary days. On the
    /// fall-back night it flipped at 7 AM and on the spring-forward night at
    /// 9 AM. The handover is now 8 AM on the Eastern clock.
    func testGameDayHandsOverAtEightAMEasternIncludingTheChangeoverDays() {
        XCTAssertEqual(day("2026-10-20").handover, instant("2026-10-21T12:00:00Z"), "EDT: 8 AM is 12:00Z")
        XCTAssertEqual(day("2026-10-31").handover, instant("2026-11-01T13:00:00Z"), "8 AM on fall-back morning is EST, an hour later than 32 hours would say")
        XCTAssertEqual(day("2026-11-01").handover, instant("2026-11-02T13:00:00Z"), "EST: 8 AM is 13:00Z")
        XCTAssertEqual(day("2027-03-13").handover, instant("2027-03-14T12:00:00Z"), "spring-forward morning is EDT")
        XCTAssertEqual(day("2027-03-14").handover, instant("2027-03-15T12:00:00Z"))
    }

    func testCurrentDayFlipsOnTheExactSecondOfTheHandover() {
        let days = [day("2026-11-01"), day("2026-11-02")]
        let handover = instant("2026-11-02T13:00:00Z")
        XCTAssertEqual(GameDay.current(among: days, now: handover.addingTimeInterval(-1))?.id, "2026-11-01")
        XCTAssertEqual(GameDay.current(among: days, now: handover)?.id, "2026-11-02")
        let spring = [day("2027-03-13"), day("2027-03-14")]
        let springHandover = instant("2027-03-14T12:00:00Z")
        XCTAssertEqual(GameDay.current(among: spring, now: springHandover.addingTimeInterval(-1))?.id, "2027-03-13")
        XCTAssertEqual(GameDay.current(among: spring, now: springHandover)?.id, "2027-03-14")
    }

    /// Before the season it is the opening night, after it the last day
    /// played, and no gap in between leaves the front door empty.
    func testCurrentDayBeforeTheSeasonAfterTheFinalsAndAcrossAGap() {
        let days = [day("2026-10-21"), day("2026-10-23"), day("2027-06-18")]
        XCTAssertEqual(GameDay.current(among: days, now: instant("2026-09-01T12:00:00Z"))?.id, "2026-10-21")
        XCTAssertEqual(GameDay.current(among: days, now: instant("2026-10-22T20:00:00Z"))?.id, "2026-10-23")
        XCTAssertEqual(GameDay.current(among: days, now: instant("2027-08-01T12:00:00Z"))?.id, "2027-06-18")
        XCTAssertNil(GameDay.current(among: [], now: instant("2026-10-22T20:00:00Z")))
    }

    // MARK: Eastern days

    /// 2026-10-20 parses as Eastern midnight whatever the phone's zone is:
    /// 04:00Z in daylight time, 05:00Z in standard time, and the changeover
    /// days still start before the 2 AM switch.
    func testGameDatesParseAsEasternMidnightAcrossDST() {
        XCTAssertEqual(DataFreshness.parseDate("2026-10-20"), instant("2026-10-20T04:00:00Z"))
        XCTAssertEqual(DataFreshness.parseDate("2026-11-01"), instant("2026-11-01T04:00:00Z"))
        XCTAssertEqual(DataFreshness.parseDate("2026-11-02"), instant("2026-11-02T05:00:00Z"))
        XCTAssertEqual(DataFreshness.parseDate("2027-03-14"), instant("2027-03-14T05:00:00Z"))
        XCTAssertEqual(DataFreshness.parseDate("2027-03-15"), instant("2027-03-15T04:00:00Z"))
    }

    /// The scoreboard files a game under its Eastern date, turning over at
    /// Eastern midnight (04:00Z or 05:00Z), not the phone's.
    func testScoreboardDateKeyTurnsOverAtEasternMidnight() {
        XCTAssertEqual(LiveScoreClient.dateKey(instant("2026-11-02T04:59:59Z")), "20261101")
        XCTAssertEqual(LiveScoreClient.dateKey(instant("2026-11-02T05:00:00Z")), "20261102")
        XCTAssertEqual(LiveScoreClient.dateKey(instant("2027-03-14T04:59:59Z")), "20270313")
        XCTAssertEqual(LiveScoreClient.dateKey(instant("2027-03-14T05:00:00Z")), "20270314")
        XCTAssertEqual(LiveScoreClient.dateKey(DataFreshness.parseDate("2026-10-20")!), "20261020")
    }

    /// Variable-length fractional seconds from Postgres (football 02a20f41,
    /// same decoder) and offsets in either direction.
    func testTimestampsParseWithAnyFractionalPrecision() {
        let expected = instant("2026-10-09T05:37:56Z")
        for raw in [
            "2026-10-09T05:37:56+00:00", "2026-10-09T05:37:56Z", "2026-10-09T05:37:56.9+00:00",
            "2026-10-09T05:37:56.93+00:00", "2026-10-09T05:37:56.93411+00:00",
            "2026-10-08T22:37:56.934113-07:00",
        ] {
            let parsed = DataFreshness.parseDate(raw)
            XCTAssertNotNil(parsed, raw)
            XCTAssertEqual(parsed?.timeIntervalSince1970 ?? 0, expected.timeIntervalSince1970, accuracy: 1, raw)
        }
    }

    // MARK: Game status

    private func game(_ id: String, tipoff: Date, day: String? = nil, season: Int = testLiveSeason,
                      awayScore: Int? = nil, homeScore: Int? = nil) -> Game {
        Game(id: id, season: season, week: 1, tipoff: tipoff,
             gameDate: day.flatMap(DataFreshness.parseDate), awayTeam: "NYK", homeTeam: "SAS",
             awayScore: awayScore, homeScore: homeScore)
    }

    /// With no live feed a game is in progress for 3.5 hours from tip-off,
    /// awaits a score after that, and reads "Score pending" once 12 hours
    /// have passed. Each edge is exact.
    func testGameStatusAndLabelBoundaries() {
        let tip = instant("2026-12-25T22:00:00Z")
        let g = game("g", tipoff: tip)
        XCTAssertEqual(g.status(now: tip.addingTimeInterval(-1)), .upcoming)
        XCTAssertEqual(g.status(now: tip), .inProgress)
        XCTAssertEqual(g.startedLabel(live: nil, now: tip.addingTimeInterval(3.5 * 3_600 - 1)), "In progress")
        XCTAssertEqual(g.startedLabel(live: nil, now: tip.addingTimeInterval(3.5 * 3_600)), "Final soon")
        XCTAssertFalse(g.isScorePending(now: tip.addingTimeInterval(12 * 3_600)))
        XCTAssertTrue(g.isScorePending(now: tip.addingTimeInterval(12 * 3_600 + 1)))
        XCTAssertEqual(g.startedLabel(live: nil, now: tip.addingTimeInterval(12 * 3_600 + 1)), "Score pending")
        XCTAssertFalse(game("f", tipoff: tip, awayScore: 100, homeScore: 99).isScorePending(now: tip.addingTimeInterval(20 * 3_600)))
    }

    private struct ScheduleProvider: StatcastProviding {
        let games: [Game]
        func fetchGames(season: Int) async throws -> [Game] { games.filter { $0.season == season } }
        func fetchDataFreshness() async throws -> DataFreshness? { nil }
        func fetchHistoricalPlayers(before season: Int) async throws -> [Player] { [] }
        func fetchCurrentPlayers(season: Int) async throws -> [Player] { [] }
        func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
        func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
        func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
    }

    /// New guard for the poll pacing: games count as under way from tip-off
    /// until 12 hours later, and the next tip-off excludes one already
    /// started.
    @MainActor
    func testUnderwayWindowAndNextTipoffEdges() async {
        let tip = instant("2026-12-25T22:00:00Z")
        let later = instant("2026-12-26T01:00:00Z")
        let model = makeViewModel(provider: ScheduleProvider(games: [
            game("a", tipoff: tip, day: "2026-12-25"),
            game("b", tipoff: later, day: "2026-12-25"),
        ]))
        await model.loadGames(force: true)

        XCTAssertFalse(model.hasGamesUnderway(now: tip.addingTimeInterval(-1)))
        XCTAssertTrue(model.hasGamesUnderway(now: tip))
        XCTAssertTrue(model.hasGamesUnderway(now: tip.addingTimeInterval(12 * 3_600 - 1)))
        XCTAssertTrue(model.hasGamesUnderway(now: later.addingTimeInterval(12 * 3_600 - 1)), "the second game is still inside its window")
        XCTAssertFalse(model.hasGamesUnderway(now: later.addingTimeInterval(12 * 3_600)))

        XCTAssertEqual(model.nextTipoff(after: tip.addingTimeInterval(-1)), tip)
        XCTAssertEqual(model.nextTipoff(after: tip), later, "a game that has tipped is no longer next")
        XCTAssertNil(model.nextTipoff(after: later))
    }

    // MARK: Opening night

    /// GamesTests: the line beside a final season reads "starts Oct 20" until
    /// the first tip-off, and "under way" from the tip-off on, with the tip
    /// itself already counting.
    @MainActor
    func testUpcomingSeasonLineFlipsAtTheFirstTipoff() async {
        let finals = game("f", tipoff: instant("2026-06-14T00:30:00Z"), day: "2026-06-13",
                          season: testLiveSeason, awayScore: 94, homeScore: 90)
        let tip = instant("2026-10-20T23:00:00Z")
        let opener = game("o", tipoff: tip, day: "2026-10-20", season: testLiveSeason + 1)
        let pending = DataFreshness(
            status: .pending, rawStatus: "source_pending",
            season: testLiveSeason + 1, publishedSeason: testLiveSeason, lastErrorCode: "season_pending"
        )
        struct Provider: StatcastProviding {
            let games: [Game]
            let freshness: DataFreshness
            func fetchGames(season: Int) async throws -> [Game] { games.filter { $0.season == season } }
            func fetchDataFreshness() async throws -> DataFreshness? { freshness }
            func fetchHistoricalPlayers(before season: Int) async throws -> [Player] { [] }
            func fetchCurrentPlayers(season: Int) async throws -> [Player] { [] }
            func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
            func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
            func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
        }
        let model = makeViewModel(
            provider: Provider(games: [finals, opener], freshness: pending),
            calendarSeason: testLiveSeason + 1
        )
        _ = await model.checkForUpdates(force: true)
        await model.loadGames(force: true)

        let before = model.upcomingSeasonStartsText(now: tip.addingTimeInterval(-1))
        XCTAssertEqual(before, "\(SeasonLabel.text(testLiveSeason + 1)) starts Oct 20")
        let after = model.upcomingSeasonStartsText(now: tip)
        XCTAssertEqual(after, "\(SeasonLabel.text(testLiveSeason + 1)) under way · stats arriving")
    }

    // MARK: Ages and weekly deltas

    private func profile(born: String) throws -> PlayerProfile {
        let json = #"[{"player_id":1,"season":2026,"birth_date":"\#(born)"}]"#
        return try XCTUnwrap(JSONDecoder.statScout.decode([PlayerProfile].self, from: Data(json.utf8)).first)
    }

    /// Age differenced the UTC-midnight birth date in the machine's zone, so
    /// in Pacific time a player turned a year older at 5 PM the evening before
    /// his birthday (the football fix in 73ae5f2, same code).
    func testAgeTurnsOverOnTheBirthdayInTheViewersZone() throws {
        let player = try profile(born: "2000-09-24")
        XCTAssertEqual(player.age(on: local(la, 2026, 9, 23, 20, 0), calendar: la), 25)
        XCTAssertEqual(player.age(on: local(la, 2026, 9, 23, 23, 59, 59), calendar: la), 25)
        XCTAssertEqual(player.age(on: local(la, 2026, 9, 24, 0, 0, 0), calendar: la), 26)
        let leap = try profile(born: "2000-02-29")
        XCTAssertEqual(leap.age(on: local(la, 2027, 2, 28, 23, 59), calendar: la), 26)
        XCTAssertEqual(leap.age(on: local(la, 2027, 3, 1), calendar: la), 27)
    }

    /// New guard: ages are a Gregorian fact. Thailand's default calendar is
    /// Buddhist and Saudi Arabia's is Umm al-Qura, so `Calendar.current` there
    /// numbers this year 2569 or 1448; reading the year off it made a 1995 birth
    /// "574 yrs" (or a negative age) on every player page. The viewer's calendar
    /// supplies the zone and nothing else.
    func testAgeDoesNotDependOnTheDeviceCalendar() throws {
        let player = try profile(born: "1995-03-10")
        for identifier in Self.nonGregorianCalendars {
            let calendar = viewerCalendar(identifier)
            XCTAssertEqual(player.age(on: local(la, 2026, 10, 31, 12), calendar: calendar), 31, "\(identifier)")
            XCTAssertEqual(player.age(on: local(la, 2026, 3, 9, 23, 59, 59), calendar: calendar), 30, "\(identifier) eve")
            XCTAssertEqual(player.age(on: local(la, 2026, 3, 10), calendar: calendar), 31, "\(identifier) birthday")
        }
    }

    /// New guard, same cause: the season flip is the Gregorian 1 October. On a
    /// Japanese or Umm al-Qura calendar the first launch (no remembered live
    /// season yet) resolved to season 9 or 1448 and asked the feed for it.
    func testCalendarSeasonDoesNotDependOnTheDeviceCalendar() {
        for identifier in Self.nonGregorianCalendars {
            let calendar = viewerCalendar(identifier)
            XCTAssertEqual(
                StatScoutSeason.calendarSeason(on: local(la, 2026, 9, 30, 23, 59, 59), calendar: calendar), 2026, "\(identifier)")
            XCTAssertEqual(
                StatScoutSeason.calendarSeason(on: local(la, 2026, 10, 1), calendar: calendar), 2027, "\(identifier)")
            XCTAssertEqual(
                StatScoutSeason.calendarSeason(on: local(la, 2027, 3, 14, 2, 30), calendar: calendar), 2027, "\(identifier)")
        }
    }

    /// Calendars an iPhone can be set to, and the ones whole regions default to.
    private static let nonGregorianCalendars: [Calendar.Identifier] = [
        .buddhist, .japanese, .islamicUmmAlQura, .persian, .hebrew, .republicOfChina, .indian,
    ]

    private func viewerCalendar(_ identifier: Calendar.Identifier) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = la.timeZone
        return calendar
    }

    func testWeeklyDeltaWindowEdge() {
        let now = instant("2026-11-03T12:00:00Z")
        func trend(_ id: String, ageSeconds: TimeInterval, delta: Int) -> GameTrend {
            GameTrend(id: id, date: now.addingTimeInterval(-ageSeconds), opponent: "SAS",
                      summary: "", percentileDelta: delta, keyMetric: "PTS")
        }
        let player = Player(
            playerId: 1, name: "T", team: "NYK", position: "G", handedness: "", updatedAt: now,
            metrics: [], standardStats: [],
            games: [
                trend("edge", ageSeconds: 7 * 86_400, delta: 4),
                trend("just-out", ageSeconds: 7 * 86_400 + 1, delta: 50),
                trend("fresh", ageSeconds: 60, delta: -1),
            ]
        )
        XCTAssertEqual(player.weeklyDelta(asOf: now), 3)
    }
}
