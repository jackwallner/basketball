import XCTest

/// Persona audit: a busy user is interrupted mid-task (home button, app switcher
/// kill, phone call) and returns later expecting state and context to survive.
/// Every step attaches a screenshot named `<scenario>-<nn>_<what>` and records
/// what it saw with `note`, so the report can quote the observed state. Nothing
/// here fails on lost state: losing it is the finding, not a test fault.
@MainActor
final class InterruptedUserUITests: XCTestCase {
    private let bundle = "com.jackwallner.basketball"
    private var scenario = "00"
    private var step = 0

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: - I1 Onboarding interrupted

    func testI1OnboardingKilledMidway() throws {
        scenario = "I1"; step = 0
        var app = launch(["-ResetUITestState"], fixtures: false)
        Thread.sleep(forTimeInterval: 3)
        shot("onboarding_page1_fresh")
        tap("Continue", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        tap("Continue", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        shot("onboarding_page3_before_interrupt")

        // Phone call / home button, 5s away, then back.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        Thread.sleep(forTimeInterval: 2)
        shot("onboarding_after_background_5s")

        // App switcher kill, relaunch with the same defaults (no reset).
        app.terminate()
        app = launch([], fixtures: false)
        Thread.sleep(forTimeInterval: 3)
        shot("onboarding_after_kill_relaunch")
        note("onboarding after kill: Continue button \(app.buttons["Continue"].exists), Skip \(app.buttons["Skip"].exists)")
    }

    // MARK: - I2 Stats: filters, search and a profile, interrupted

    func testI2StatsContextAcrossBackgroundAndKill() throws {
        scenario = "I2"; step = 0
        var app = launch(["-hasCompletedOnboarding", "YES", "-StartTab", "stats"], fixtures: true)
        waitFor("RANK", in: app)
        shot("stats_default")

        tap("Guards", in: app)
        Thread.sleep(forTimeInterval: 1)
        tap("Search players or teams", in: app)
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 10) { field.typeText("Jokic") }
        Thread.sleep(forTimeInterval: 1)
        shot("stats_guards_search_jokic_keyboard_up")

        // Interrupted with the keyboard up.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        Thread.sleep(forTimeInterval: 2)
        shot("stats_after_background_keyboard_state")
        note("after background: search field \(app.textFields.firstMatch.exists), keyboard \(app.keyboards.count > 0)")

        // Open a profile, scroll, go away, come back.
        let row = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+, .*")).firstMatch
        if row.waitForExistence(timeout: 20) { row.tap() }
        Thread.sleep(forTimeInterval: 3)
        shot("profile_opened")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1)
        shot("profile_scrolled")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        Thread.sleep(forTimeInterval: 2)
        shot("profile_after_background_scroll_kept")

        // Kill and relaunch: where does the user land?
        app.terminate()
        app = launch(["-hasCompletedOnboarding", "YES"], fixtures: true)
        waitFor("RANK", in: app)
        shot("stats_after_kill_relaunch")
        note("after kill: Guards selected \(app.buttons["Guards"].isSelected), search field \(app.textFields.firstMatch.exists)")
    }

    // MARK: - I3 Other tabs: Trends, Teams, Compare picks

    func testI3TabsAfterKill() throws {
        scenario = "I3"; step = 0
        var app = launch(["-hasCompletedOnboarding", "YES", "-StartTab", "compare"], fixtures: true)
        Thread.sleep(forTimeInterval: 4)
        shot("compare_empty")
        let choose = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "player")).element(boundBy: 0)
        note("compare first player-ish button exists: \(choose.exists)")
        let slotA = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Choose")).firstMatch
        if slotA.waitForExistence(timeout: 10) { slotA.tap() }
        Thread.sleep(forTimeInterval: 2)
        shot("compare_picker_open")
        let pick = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Gilgeous")).firstMatch
        if pick.waitForExistence(timeout: 10) { pick.tap() }
        Thread.sleep(forTimeInterval: 2)
        shot("compare_slot_a_picked")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
        app.activate()
        Thread.sleep(forTimeInterval: 2)
        shot("compare_after_background")

        app.terminate()
        app = launch(["-hasCompletedOnboarding", "YES", "-StartTab", "compare"], fixtures: true)
        Thread.sleep(forTimeInterval: 4)
        shot("compare_after_kill_picks")

        // Teams: does it auto-push the favourite, and can you get back?
        app.terminate()
        app = launch(["-hasCompletedOnboarding", "YES", "-StartTab", "teams"], fixtures: true)
        Thread.sleep(forTimeInterval: 5)
        shot("teams_relaunch_landing")

        // Games tab landing day.
        app.terminate()
        app = launch(["-hasCompletedOnboarding", "YES", "-StartTab", "games"], fixtures: true)
        Thread.sleep(forTimeInterval: 5)
        shot("games_relaunch_landing")
    }

    // MARK: - I4 Paywall interrupted

    func testI4PaywallAcrossBackgroundAndKill() throws {
        scenario = "I4"; step = 0
        var app = launch(["-hasCompletedOnboarding", "YES", "-StartTab", "stats"], fixtures: true, pro: false)
        waitFor("RANK", in: app)
        let upgrade = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "StatScout+")).firstMatch
        note("upgrade button exists: \(upgrade.waitForExistence(timeout: 10))")
        if upgrade.exists { upgrade.tap() }
        Thread.sleep(forTimeInterval: 3)
        shot("paywall_open")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 6)
        app.activate()
        Thread.sleep(forTimeInterval: 2)
        shot("paywall_after_background")
        app.terminate()
        app = launch(["-hasCompletedOnboarding", "YES"], fixtures: true, pro: false)
        waitFor("RANK", in: app)
        shot("paywall_after_kill_lands_on_stats")
    }

    // MARK: - Helpers

    private func launch(_ extra: [String], fixtures: Bool, pro: Bool = true) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.launchEnvironment = ["SCREENSHOT_MODE": "1"]
        if pro {
            app.launchEnvironment["FORCE_PRO"] = "1"
            app.launchEnvironment["STATSCOUT_FORCE_PRO"] = "1"
        }
        var arguments = fixtures ? ["-ScreenshotData"] : []
        arguments += extra
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App should launch in the foreground")
        return app
    }

    private func waitFor(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 60) {
        let element = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@ OR value ==[c] %@", text, text)
        ).firstMatch
        if !element.waitForExistence(timeout: timeout) { note("did not see \(text) within \(Int(timeout))s") }
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let matches = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label))
        let target = matches.allElementsBoundByIndex.first(where: \.isHittable) ?? matches.firstMatch
        guard target.waitForExistence(timeout: 20) else { return note("button \(label) not found") }
        target.tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func note(_ text: String) {
        print("AUDIT-NOTE [\(scenario)] \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = "\(scenario)-note-\(step)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        step += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(scenario)-\(String(format: "%02d", step))_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
