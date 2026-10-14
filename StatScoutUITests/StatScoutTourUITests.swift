import XCTest

/// A visual tour of every reachable screen and state, for QA before a
/// submission. Runs on live data by default (set `TOUR_FIXTURES=1` for the
/// DEBUG fixture provider) and keeps a screenshot attachment per frame, named
/// `<section>-<step>_<what>`. Long pages are walked top to bottom in page-sized
/// drags, so a tab bar covering the last row, or a clipped footer, shows up.
///
/// Export with `scripts/tour.sh`, which numbers the frames in order.
@MainActor
final class StatScoutTourUITests: XCTestCase {
    private let star = "Shai Gilgeous-Alexander"
    private let big = "Nikola Jokic"
    private let wing = "Jayson Tatum"
    private let peer = "Jalen Brunson"

    private var section = "00"
    private var step = 0

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: - 01 Onboarding and paywall

    func testT01Onboarding() throws {
        let app = launch(pro: false, onboarding: true)
        begin("01")
        Thread.sleep(forTimeInterval: 3)
        shot(app, "onboarding_page_1")
        tapButton("Continue", in: app, required: false)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "onboarding_page_2")
        tapButton("Continue", in: app, required: false)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "onboarding_page_3")
        tapButton("Continue", in: app, required: false)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "onboarding_page_4")
    }

    func testT02Paywall() throws {
        begin("02")
        for mode in ["yearly", "monthly", "lifetime"] {
            let app = XCUIApplication(bundleIdentifier: "com.jackwallner.basketball")
            app.launchArguments = ["-PaywallSnapshot", mode, "-ResetUITestState"]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
            Thread.sleep(forTimeInterval: 4)
            scrollThrough(app, "paywall_\(mode)", maxPages: 5)
            app.terminate()
        }
        for mode in ["trial", "onboarding"] {
            let app = XCUIApplication(bundleIdentifier: "com.jackwallner.basketball")
            app.launchArguments = ["-PaywallSnapshot", mode, "-ResetUITestState"]
            app.launch()
            Thread.sleep(forTimeInterval: 4)
            shot(app, "paywall_\(mode)")
            app.terminate()
        }
    }

    // MARK: - 03 Stats

    func testT03StatsAdvanced() throws {
        let app = launch(board: "advanced")
        begin("03")
        waitForText("RANK", in: app)
        scrollThrough(app, "all_advanced", maxPages: 4)
        scrollToTop(app)
        for title in ["Guards", "Forwards", "Centers"] {
            tapButton(title, in: app)
            Thread.sleep(forTimeInterval: 1)
            scrollThrough(app, "\(title.lowercased())_advanced", maxPages: 2)
            scrollToTop(app)
        }
    }

    func testT04StatsStandard() throws {
        let app = launch(board: "standard")
        begin("04")
        waitForText("RANK", in: app)
        scrollThrough(app, "all_standard", maxPages: 4)
        scrollToTop(app)
        for title in ["Guards", "Forwards", "Centers"] {
            tapButton(title, in: app)
            Thread.sleep(forTimeInterval: 1)
            scrollThrough(app, "\(title.lowercased())_standard", maxPages: 2)
            scrollToTop(app)
        }
    }

    func testT05SortSearchAndViewMenus() throws {
        let app = launch(board: "advanced")
        begin("05")
        waitForText("RANK", in: app)
        tapButton("View options", in: app)
        shot(app, "view_menu_open")
        tapMenuItem("Best & Worst", in: app)
        Thread.sleep(forTimeInterval: 2)
        scrollThrough(app, "best_and_worst", maxPages: 4)
        scrollToTop(app)
        tapButton("View options", in: app)
        tapMenuItem("Leaderboard", in: app)
        Thread.sleep(forTimeInterval: 1.5)

        tapButton("Stat", in: app)
        shot(app, "stat_menu_open")
        tapMenuItem("TS%", in: app)
        Thread.sleep(forTimeInterval: 1)
        shot(app, "sorted_by_ts")
        tapButton("Sort direction", in: app)
        shot(app, "sort_direction_flipped")
        tapButton("Guards", in: app)
        Thread.sleep(forTimeInterval: 1)
        shot(app, "ts_kept_on_guards")

        tapButton("Search players or teams", in: app)
        app.textFields.firstMatch.typeText("Knicks")
        Thread.sleep(forTimeInterval: 1)
        shot(app, "search_team")
        app.textFields.firstMatch.typeText("zzzz")
        Thread.sleep(forTimeInterval: 1)
        shot(app, "search_no_results")
    }

    func testT06Following() throws {
        let app = launch()
        begin("06")
        waitForText("RANK", in: app)
        tapButton("Following", in: app)
        Thread.sleep(forTimeInterval: 1)
        shot(app, "following_empty")
        tapButton("Choose players", in: app, required: false)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "follow_players_sheet")
    }

    // MARK: - 07 Profiles

    func testT07Profile() throws {
        let app = launch()
        begin("07")
        openLeader(star, in: app)
        waitForText("ADVANCED PERCENTILES", in: app)
        scrollThrough(app, "profile_advanced", maxPages: 8)
        scrollToTop(app)
        tapButton("Recent", in: app, required: false)
        Thread.sleep(forTimeInterval: 2)
        shot(app, "profile_recent_mode")
        tapButton("Both", in: app, required: false)
        Thread.sleep(forTimeInterval: 2)
        scrollThrough(app, "profile_both_mode", maxPages: 3)
        scrollToTop(app)
        tapButton("Standard", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "profile_standard", maxPages: 6)
        scrollToTop(app)
        tapButton("Year Compare", in: app)
        Thread.sleep(forTimeInterval: 3)
        scrollThrough(app, "profile_year_compare", maxPages: 6)
    }

    func testT08CenterProfileAndMetricLeaderboard() throws {
        let app = launch()
        begin("08")
        openLeader(big, in: app)
        waitForText("ADVANCED PERCENTILES", in: app)
        shot(app, "center_profile_top")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "REB%")).firstMatch
        if row.waitForExistence(timeout: 10) {
            row.tap()
            Thread.sleep(forTimeInterval: 2)
            scrollThrough(app, "metric_leaderboard_reb", maxPages: 3)
        } else {
            XCTFail("No REB% percentile row to drill into")
        }
    }

    // MARK: - 09 Games

    func testT09Games() throws {
        let app = launch(tab: "games")
        begin("09")
        Thread.sleep(forTimeInterval: 5)
        scrollThrough(app, "games_default_day", maxPages: 4)
        for offset in [-1, 1, 2] {
            guard let chip = dayChip(offsetFromToday: offset, in: app) else { continue }
            chip.tap()
            Thread.sleep(forTimeInterval: 1.5)
            shot(app, "games_day_\(offset)")
        }
        openGameRow(statusHint: nil, in: app)
        Thread.sleep(forTimeInterval: 3)
        scrollThrough(app, "game_page", maxPages: 10)
    }

    func testT10TeamGamePage() throws {
        let app = launch(tab: "teams")
        begin("10")
        openTeamGameCard(in: app)
        Thread.sleep(forTimeInterval: 3)
        scrollThrough(app, "team_game_page", maxPages: 12)
    }

    // MARK: - 11 Trends

    func testT11Trends() throws {
        let app = launch(tab: "trends")
        begin("11")
        Thread.sleep(forTimeInterval: 6)
        scrollThrough(app, "trends_default", maxPages: 4)
        scrollToTop(app)
        for side in ["Guards", "Forwards", "Centers"] {
            tapButton(side, in: app, required: false)
            Thread.sleep(forTimeInterval: 1.5)
            shot(app, "trends_\(side)")
        }
        tapButton("Cooling off", in: app, required: false)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "trends_cooling_off")
        tapButton("Stat", in: app)
        shot(app, "trends_metric_menu")
    }

    // MARK: - 12 Teams

    func testT12TeamPageTabs() throws {
        let app = launch(tab: "teams")
        begin("12")
        waitForText("TEAM ADVANCED STATS", in: app)
        scrollThrough(app, "team_advanced", maxPages: 6)
        scrollToTop(app)
        tapButton("Standard", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "team_standard", maxPages: 6)
        scrollToTop(app)
        tapButton("Roster", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "team_roster", maxPages: 4)
        scrollToTop(app)
        tapButton("Recent", in: app, required: false)
        Thread.sleep(forTimeInterval: 2)
        shot(app, "team_roster_recent")
    }

    func testT13TeamsListStandingsPower() throws {
        let app = launch(tab: "teams")
        begin("13")
        waitForText("TEAM ADVANCED STATS", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "teams_grid", maxPages: 5)
        scrollToTop(app)
        tapButton("Standings", in: app)
        Thread.sleep(forTimeInterval: 2)
        scrollThrough(app, "standings", maxPages: 7)
        scrollToTop(app)
        tapButton("Power", in: app)
        Thread.sleep(forTimeInterval: 2)
        scrollThrough(app, "power_ratings", maxPages: 6)
    }

    // MARK: - 14 Compare

    func testT14CompareTab() throws {
        let app = launch(tab: "compare")
        begin("14")
        waitForText("YOUR PLAYERS", in: app)
        scrollThrough(app, "compare_tab", maxPages: 5)
    }

    func testT15CompareProfileFlow() throws {
        let app = launch()
        begin("15")
        openLeader(star, in: app)
        tapButton("Compare with another player", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "comparison_player_picker")
        app.textFields.firstMatch.typeText("Brunson")
        Thread.sleep(forTimeInterval: 1)
        tapAnyButton(containing: peer, in: app)
        Thread.sleep(forTimeInterval: 3)
        scrollThrough(app, "profile_comparison", maxPages: 8)
    }

    func testT16CompareTeamAndYearOverYear() throws {
        let app = launch(tab: "compare")
        begin("16")
        waitForText("YOUR PLAYERS", in: app)
        scrollToBottom(app)
        shot(app, "compare_bottom_cards")
        tapAnyButton(containing: "Team A", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "team_picker")
        tapAnyButton(containing: "Boston Celtics", in: app)
        scrollToBottom(app)
        tapAnyButton(containing: "Team B", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        tapAnyButton(containing: "New York Knicks", in: app)
        scrollToBottom(app)
        shot(app, "team_slots_filled")
        tapButton("Compare Teams", in: app)
        Thread.sleep(forTimeInterval: 3)
        scrollThrough(app, "team_comparison", maxPages: 6)
    }

    // MARK: - 17 Settings

    func testT17SettingsAndGlossary() throws {
        let app = launch()
        begin("17")
        waitForText("RANK", in: app)
        tapButton("Settings", in: app)
        XCTAssertTrue(app.staticTexts["REFERENCE"].firstMatch.waitForExistence(timeout: 30), "Settings should open")
        scrollThrough(app, "settings", maxPages: 10)
        scrollToTop(app)
        tapAnyButton(containing: "Stat Glossary", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "glossary", maxPages: 6)
    }

    // MARK: - 18 Season picker

    func testT18SeasonPicker() throws {
        let app = launch()
        begin("18")
        waitForText("RANK", in: app)
        seasonControl(in: app).tap()
        Thread.sleep(forTimeInterval: 1)
        shot(app, "season_menu_open")
        tapMenuItem("2023-24", in: app)
        Thread.sleep(forTimeInterval: 5)
        scrollThrough(app, "past_season", maxPages: 2)
        scrollToTop(app)
        seasonControl(in: app).tap()
        tapMenuItem("All Time", in: app)
        Thread.sleep(forTimeInterval: 6)
        scrollThrough(app, "all_time", maxPages: 2)
        scrollToTop(app)
        seasonControl(in: app).tap()
        tapMenuItem("Playoffs", in: app)
        Thread.sleep(forTimeInterval: 3)
        shot(app, "all_time_playoffs")
    }

    // MARK: - 19 Free tier

    func testT19FreeTierGates() throws {
        let trends = launch(tab: "trends", pro: false)
        begin("19")
        Thread.sleep(forTimeInterval: 5)
        shot(trends, "free_trends_gate")
        trends.terminate()

        let compare = launch(tab: "compare", pro: false)
        Thread.sleep(forTimeInterval: 5)
        scrollThrough(compare, "free_compare_gate", maxPages: 4)
        compare.terminate()

        let teams = launch(tab: "teams", pro: false)
        Thread.sleep(forTimeInterval: 5)
        scrollThrough(teams, "free_team_page", maxPages: 4)
        teams.terminate()

        let stats = launch(pro: false)
        waitForText("RANK", in: stats)
        tapButton("View options", in: stats)
        tapMenuItem("Best & Worst", in: stats)
        Thread.sleep(forTimeInterval: 2)
        shot(stats, "free_best_and_worst_gate")
        tapButton("View options", in: stats)
        tapMenuItem("Leaderboard", in: stats)
        seasonControl(in: stats).tap()
        tapMenuItem("2023-24", in: stats)
        Thread.sleep(forTimeInterval: 2)
        shot(stats, "free_locked_season_pitch")
    }

    func testT20FreeProfile() throws {
        let app = launch(pro: false)
        begin("20")
        openLeader(star, in: app)
        waitForText("ADVANCED PERCENTILES", in: app)
        scrollThrough(app, "free_profile", maxPages: 6)
    }

    // MARK: - Launch

    private func launch(
        tab: String = "stats",
        board: String = "advanced",
        pro: Bool = true,
        onboarding: Bool = false,
        fixtures: Bool = ProcessInfo.processInfo.environment["TOUR_FIXTURES"] == "1",
        extra: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.basketball")
        app.launchEnvironment = ["SCREENSHOT_MODE": "1"]
        if pro {
            app.launchEnvironment["FORCE_PRO"] = "1"
            app.launchEnvironment["STATSCOUT_FORCE_PRO"] = "1"
        }
        var arguments = [
            "-stats.board", board,
            "-stats.qualifier", "All Players",
            "-ResetUITestState",
            "-profileOpenCount", "0",
            "-StartTab", tab,
        ]
        if !onboarding { arguments += ["-hasCompletedOnboarding", "YES"] }
        if fixtures { arguments.insert("-ScreenshotData", at: 0) }
        // Live data unless TOUR_FIXTURES=1: what a fan sees today.
        arguments += ["-favoriteTeam", "NYK"]
        app.launchArguments = arguments + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App should launch in the foreground")
        return app
    }

    // MARK: - Capture

    private func begin(_ id: String) {
        section = id
        step = 0
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        attach(XCUIScreen.main.screenshot(), name)
    }

    private func attach(_ screenshot: XCUIScreenshot, _ name: String) {
        step += 1
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(section)-\(String(format: "%02d", step))_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Captures the page, then drags it up a page at a time until a drag no
    /// longer changes the frame.
    private func scrollThrough(_ app: XCUIApplication, _ name: String, maxPages: Int = 8) {
        Thread.sleep(forTimeInterval: 0.8)
        var previous = app.screenshot()
        attach(previous, "\(name)_p1")
        guard maxPages > 1 else { return }
        for page in 2...maxPages {
            dragUp(app)
            Thread.sleep(forTimeInterval: 0.8)
            var current = app.screenshot()
            if pixels(current) == pixels(previous) {
                // A drag that moved nothing may have missed the scroll view;
                // a swipe is the second opinion before calling it the end.
                app.swipeUp(velocity: .slow)
                Thread.sleep(forTimeInterval: 0.8)
                current = app.screenshot()
                if pixels(current) == pixels(previous) { return }
            }
            attach(current, "\(name)_p\(page)")
            previous = current
        }
    }

    /// The page without the status bar (its clock changes every minute) and
    /// without the right edge, where the scroll indicator fades in and out.
    private func pixels(_ screenshot: XCUIScreenshot) -> Data? {
        guard let image = screenshot.image.cgImage else { return nil }
        let top = 260
        let area = CGRect(x: 0, y: top, width: image.width - 40, height: image.height - top)
        return image.cropping(to: area)?.dataProvider?.data as Data?
    }

    private func dragUp(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.26))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.3)
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<12 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.1)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func scrollToBottom(_ app: XCUIApplication) {
        for _ in 0..<12 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.1)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Finding things

    private func waitForText(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 90) {
        let element = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@ OR value ==[c] %@", text, text)
        ).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected \(text) to appear")
    }

    /// The hittable match first: Stats, Trends, Teams and Compare each mount
    /// their own copy of a control, and the hidden ones are not tappable.
    private func button(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label))
        // Every tab stays in the tree at full-screen frames, so Trends' "Stat"
        // menu and Stats' "Defensemen" tab both count as on screen from the
        // other tab. Only the visible tab's copy is hittable.
        let visible = onScreen(matches, in: app)
        return visible.first(where: \.isHittable) ?? visible.first ?? matches.firstMatch
    }

    /// The matches whose frame sits inside the screen, in query order. A
    /// frame read never throws, unlike `isHittable` on an element scrolled
    /// out of its list.
    private func onScreen(_ query: XCUIElementQuery, in app: XCUIApplication) -> [XCUIElement] {
        guard query.firstMatch.exists else { return [] }
        let screen = app.frame
        return query.allElementsBoundByIndex.filter {
            let frame = $0.frame
            return !frame.isEmpty && screen.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    private func tapButton(_ label: String, in app: XCUIApplication, required: Bool = true) {
        let element = button(label, in: app)
        guard element.waitForExistence(timeout: required ? 30 : 5) else {
            if required { XCTFail("Button \(label) not found") }
            return
        }
        element.tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func tapAnyButton(containing text: String, in app: XCUIApplication) {
        // Leaderboard rows ("1, Name, ...") of the Stats tab behind this one stay
        // in the tree; they are never the target.
        let matches = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND NOT (label MATCHES %@) AND NOT (label MATCHES %@)",
                text, "^[0-9]+, .*", ".*, Final(/OT)?$"
            )
        )
        guard matches.firstMatch.waitForExistence(timeout: 30) else {
            return XCTFail("No button containing \(text)")
        }
        (onScreen(matches, in: app).first ?? matches.firstMatch).tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// An item in the open menu. Menus sit above the app's own buttons, so
    /// the last match is the menu's.
    private func tapMenuItem(_ label: String, in app: XCUIApplication, orElse fallback: String? = nil) {
        for text in [label, fallback].compactMap({ $0 }) {
            // Exact text first: a board row beside the menu shares a prefix
            // with an item ("GAx: 1.2, 57th percentile" against "GAx").
            let exact = NSPredicate(format: "label ==[c] %@", text)
            let queries = [
                app.menuItems.matching(exact),
                app.buttons.matching(exact),
                app.descendants(matching: .any).matching(exact),
                app.menuItems.matching(NSPredicate(format: "label BEGINSWITH[c] %@", text)),
            ]
            for matches in queries where matches.firstMatch.waitForExistence(timeout: 6) {
                (onScreen(matches, in: app).last ?? matches.element(boundBy: matches.count - 1)).tap()
                Thread.sleep(forTimeInterval: 0.8)
                return
            }
        }
        XCTFail("Menu item \(label) not found")
    }

    private func scrollMenu(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func dismissMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func seasonControl(in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", "Season and season type"))
        return onScreen(matches, in: app).first ?? matches.firstMatch
    }

    private func openLeader(_ name: String, in app: XCUIApplication) {
        waitForText("RANK", in: app)
        tapButton("Search players or teams", in: app)
        app.textFields.firstMatch.typeText(name)
        let row = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+, \(name),.*")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 90), "Leader row \(name) should load")
        row.tap()
        waitForText(name, in: app)
    }

    private func openTeamGameCard(in app: XCUIApplication) {
        waitForText("Advanced", in: app)
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@", "Last game", "Next game", "Live")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 60), "Team game card should load")
        for _ in 0..<3 {
            card.tap()
            if app.navigationBars.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " at ")).firstMatch
                .waitForExistence(timeout: 20) { return }
            if !card.exists || !card.isHittable { return }
        }
    }

    // MARK: - Games tab

    private static let chipPredicate = NSPredicate(
        format: "label MATCHES %@", "^[A-Z][a-z]+day, [A-Z][a-z]+ [0-9]+$"
    )

    private func dayChip(offsetFromToday offset: Int, in app: XCUIApplication) -> XCUIElement? {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { return nil }
        let label = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let chip = app.buttons[label].firstMatch
        return chip.waitForExistence(timeout: 10) ? chip : nil
    }

    private func openGameRow(statusHint: String?, in app: XCUIApplication) {
        var format = "label CONTAINS[c] ' at ' OR label CONTAINS[c] ' vs '"
        if let statusHint { format = "label CONTAINS[c] \"\(statusHint)\"" }
        let rows = app.buttons.matching(NSPredicate(format: format))
        guard rows.firstMatch.waitForExistence(timeout: 15) else {
            return XCTFail("No game row to open")
        }
        (onScreen(rows, in: app).first ?? rows.firstMatch).tap()
    }
}
